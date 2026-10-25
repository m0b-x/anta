part of 'sync_engine.dart';

/// How a pull ended when no gateway failure, halt or lost access ended the
/// run first.
class _PullOutcome {
  /// Every table asked for was pulled to its end without a fault.
  final bool complete;

  /// A leave stopped the pull before a table's end. Every table was
  /// otherwise reached — pulled to its end, or faulted and recorded.
  final bool cut;

  /// The tables whose pull failed for a local reason. The drain pushes none
  /// of their rows in this run: the page that failed may hold a newer remote
  /// for one of them, or the losing text of a conflict copy not yet filed.
  final Set<String> failedTables;

  /// The first of those failures, which the run reports and retries.
  final SyncGatewayException? fault;

  /// The classes the applied pages touched, told to the caches by the run
  /// itself after its drain when the pull was [cut], already told otherwise.
  final Set<SyncInvalidation> touched;

  const _PullOutcome({
    required this.complete,
    this.cut = false,
    this.failedTables = const {},
    this.fault,
    this.touched = const {},
  });

  bool get reached => !cut;
}

/// The pull side of a run.
class _Puller {
  final SyncEngine _e;

  /// The envelopes set aside this session, by table and key; a re-delivery
  /// of the same one is not counted twice.
  final Set<(String, String)> parked = {};

  _Puller(this._e);

  /// Pulls [tables] in order. [initial] says the initial merge is pending,
  /// merged under the floor; [everyTable] says the run covers the whole
  /// space, which ends it once every table was pulled to its end (D15).
  ///
  /// A table whose pull fails for a local reason — anything but a gateway
  /// failure, a halt or a lost access, which end the run — is recorded and
  /// the next table pulled: one table that cannot be applied must not stall
  /// every other (record §3.5). Once the app left the foreground the pull
  /// stops before its next page, so the background drain never waits for a
  /// whole pull; the caches then hear of the applied pages from the run,
  /// after that drain.
  Future<_PullOutcome> pull(
    SyncBinding bound,
    List<SyncTableBinding<Object>> tables, {
    required bool initial,
    required bool everyTable,
    required _RunTally tally,
  }) async {
    if (tables.isEmpty) return const _PullOutcome(complete: true);
    final db = _e._db;
    final floor = initial ? await _e._binding.bindFloor() : null;
    final touched = <SyncInvalidation>{};
    final failed = <String>{};
    SyncGatewayException? fault;
    var complete = true;
    var cut = false;
    _e._setActivity(SyncActivity.pulling);
    try {
      for (final table in tables) {
        try {
          final whole = await _pullTable(
            bound,
            table,
            floor: floor,
            initial: initial,
            touched: touched,
            tally: tally,
          );
          if (!whole) {
            complete = false;
            cut = true;
            break;
          }
        } on SyncGatewayException {
          rethrow;
        } on _Halted {
          rethrow;
        } catch (error, stack) {
          _warn(
            'pull of ${table.table} failed on ${error.runtimeType}: '
            '$error\n$stack',
          );
          failed.add(table.table);
          complete = false;
          fault ??= SyncGatewayException(
            SyncGatewayFailure.unknown,
            '${table.table}: $error',
          );
        }
      }
    } finally {
      // Pages already applied stay applied, a halted run's included, so the
      // caches hear of them either way.
      if (!cut) await notifyRun(touched);
    }
    if (!complete) {
      return _PullOutcome(
        complete: false,
        cut: cut,
        failedTables: failed,
        fault: fault,
        touched: touched,
      );
    }
    await db.syncDao.setValue(
      SyncDao.keyLastPullAt,
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    if (initial && everyTable) {
      await db.syncDao.deleteValue(SyncDao.keyBindMergePending);
      _e._downloadedRows = 0;
    }
    return const _PullOutcome(complete: true);
  }

  /// `afterRun` for the classes [touched] — alerts whenever the calendar
  /// moved, since events and categories feed the planner. A throwing hook
  /// must not mask what ended the run — a halt, a lost access — nor fail a
  /// run whose rows all landed.
  Future<void> notifyRun(Set<SyncInvalidation> touched) async {
    if (touched.isEmpty) return;
    final classes = {
      ...touched,
      if (touched.contains(SyncInvalidation.calendar)) SyncInvalidation.alerts,
    };
    try {
      await _e._hooks.afterRun(Set.unmodifiable(classes));
    } catch (error, stack) {
      _warn('afterRun failed: $error\n$stack');
    }
  }

  /// Pulls [table] page after page from its cursor; false when the app left
  /// the foreground before the table's end.
  Future<bool> _pullTable(
    SyncBinding bound,
    SyncTableBinding<Object> table, {
    required String? floor,
    required bool initial,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    // Read before the first page: a push landing during the pull moves
    // `touched` past this mark, so the next signal pulls again rather than
    // the table being marked seen up to a write it never read.
    final seenUpTo = _e._signalOf(_e._spaceOf(bound))?.touched[name];
    final stored = await db.syncDao.getValue(SyncDao.keyPullCursor(name));
    var cursor = stored == null ? null : SyncCursor(stored);
    var resumed = true;
    while (true) {
      await _e._checkHalt(bound);
      if (!_e._foreground) return false;
      final page = await _e._gateway.pullPage(
        _e._spaceOf(bound),
        name,
        after: cursor,
        resumed: resumed,
      );
      await _e._reached(tally);
      resumed = false;
      if (page.envelopes.isEmpty) break;
      await _apply(
        bound,
        table,
        page,
        floor: floor,
        touched: touched,
        tally: tally,
      );
      if (initial) _e._downloadedRows += page.envelopes.length;
      _e._emit();
      cursor = page.next ?? cursor;
      if (!page.hasMore) break;
    }
    if (seenUpTo != null) {
      await db.syncDao.setValue(
        SyncDao.keyPullSeen(name),
        '${seenUpTo.microsecondsSinceEpoch}',
      );
    }
    return true;
  }

  /// One page in one transaction: the merges, the conflict copies, the
  /// cursor, the clock stored once (readiness R5); `afterPage` after it
  /// committed, the copies among its rows as inserted notes.
  ///
  /// Each merge runs in its own savepoint, so an envelope that fails part-way
  /// leaves none of its writes behind; whatever it threw short of a gateway
  /// failure or an aborted transaction ([_abortsTransaction]) parks it, under
  /// the floor yielding the local row ([_yieldToFloor]), and the page goes
  /// on: an escaped exception would roll the page back, and every later run
  /// would meet it again at the same cursor (record §3.5). The copies are
  /// filed before the cursor moves: a copy that fails rolls the page back,
  /// merge and retired entry included, so the next run merges the page again
  /// and files the copy again rather than the losing text being dropped.
  Future<void> _apply(
    SyncBinding bound,
    SyncTableBinding<Object> table,
    SyncPullPage page, {
    required String? floor,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    await _e._hooks.beforePage(name);
    // The hook may have outlived the binding, the session or the engine.
    await _e._checkHalt(bound);
    final rows = <SyncAppliedRow>[];
    // The conflict copies filed in the transaction, announced with the
    // page's rows only once it committed.
    final copies = <SyncAppliedRow>[];
    var changed = false;
    await db.transaction(() async {
      final conflicts = <SyncNoteConflict>[];
      // The queued stamps by key, read once for the page on its first park
      // under the floor.
      Map<String, String>? queued;
      for (final envelope in page.envelopes) {
        final MergeOutcome outcome;
        try {
          outcome = await db.transaction(
            () => table.mergeRemote(db, envelope, floor: floor),
          );
        } on SyncGatewayException {
          rethrow;
        } catch (error) {
          if (_abortsTransaction(error)) rethrow;
          _park(envelope, error);
          if (floor != null) {
            queued ??= {
              for (final entry in await db.syncOutboxDao.pending())
                if (entry.syncedTable == name) entry.rowKey: entry.hlc,
            };
            await _yieldToFloor(name, envelope.rowKey, floor, queued);
          }
          continue;
        }
        // A later envelope of a parked key landed: the row is no longer
        // missing, and the drain may push it again.
        parked.remove((envelope.table, envelope.rowKey));
        rows.add(
          SyncAppliedRow(
            rowKey: envelope.rowKey,
            result: outcome.result,
            tombstone: isTombstone(envelope),
            moved: outcome.moved,
            previousParent: outcome.previousParent,
          ),
        );
        if (outcome.result == MergeResult.inserted ||
            outcome.result == MergeResult.applied) {
          changed = true;
        }
        final loser = outcome.loser;
        if (loser != null) {
          conflicts.add(
            SyncNoteConflict(
              loser: loser,
              loserContent: outcome.loserContent ?? '',
            ),
          );
        }
      }
      for (final conflict in conflicts) {
        final copy = await _e._hooks.fileConflictCopy(conflict);
        if (copy != null) {
          copies.add(
            SyncAppliedRow(
              rowKey: copy,
              result: MergeResult.inserted,
              tombstone: false,
            ),
          );
        }
      }
      final next = page.next;
      if (next != null) {
        await db.syncDao.setValue(SyncDao.keyPullCursor(name), next.value);
      }
      await db.persistClock();
    });
    if (changed) touched.add(table.invalidation);
    tally.pulled += rows.length;
    await _e._hooks.afterPage(name, List.unmodifiable([...rows, ...copies]));
  }

  /// Retires the outbox entry of a row whose envelope parked under the bind
  /// floor when the row's stamp is at or below the floor: the floor says the
  /// local row loses to the space, and pushing it would overwrite the space
  /// with the loser (S3d review H2). The row stays as it is here — missing
  /// the space's version until that row is pushed again (record §8) — and
  /// its key stays out of this session's drains.
  Future<void> _yieldToFloor(
    String table,
    String rowKey,
    String floor,
    Map<String, String> queued,
  ) async {
    final stamp = queued[rowKey];
    if (stamp == null || stamp.compareTo(floor) > 0) return;
    await _e._db.syncOutboxDao.ackThrough(table, rowKey, stamp);
    queued.remove(rowKey);
  }

  /// Logs by kind: a malformed document is expected now and then; an
  /// `ArgumentError` is more likely a bug in a binding than in the document;
  /// anything else is the database's or the engine's own fault. All three
  /// park the envelope.
  void _park(SyncEnvelope envelope, Object error) {
    final row = '${envelope.table}/${envelope.rowKey}';
    if (error is ArgumentError) {
      _warn('parked $row on an ArgumentError, probably a bug: $error');
    } else if (_isEnvelopeFault(error)) {
      debugPrint('[SyncEngine] parked $row: $error');
    } else {
      _warn('parked $row on ${error.runtimeType}: $error');
    }
    if (parked.add((envelope.table, envelope.rowKey))) _e._parks++;
  }
}

/// SQLite's result code for a constraint violation, the one database error
/// that fails a single statement and leaves the transaction standing.
const int _sqliteConstraint = 19;

/// Whether [error] took SQLite's whole transaction with it — a full disk, an
/// I/O error: the merge's savepoint is gone, so parking the envelope would
/// run the rest of the page, the cursor and the clock in autocommit past
/// rows that were rolled back. Such a page fails whole and is retried (S3d
/// review H1).
bool _abortsTransaction(Object error) =>
    error is CouldNotRollBackException ||
    (error is SqliteException && error.resultCode != _sqliteConstraint);

/// What one malformed document raises: a missing or mistyped key, a value a
/// column refuses (drift checks lengths on write), a key that names no row.
/// A pull parks an envelope on anything, these quietly; the push parks only
/// these when it loads rows, and anything else ends its run.
bool _isEnvelopeFault(Object error) =>
    error is FormatException ||
    error is TypeError ||
    error is ArgumentError ||
    error is InvalidDataException;
