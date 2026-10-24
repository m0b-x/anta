part of 'sync_engine.dart';

/// How a pull ended when no gateway failure, halt or lost access ended the
/// run first.
class _PullOutcome {
  /// Every table asked for was pulled to its end.
  final bool complete;

  /// The tables whose pull failed for a local reason. The drain pushes none
  /// of their rows in this run: the page that failed may hold a newer remote
  /// for one of them, or the losing text of a conflict copy not yet filed.
  final Set<String> failedTables;

  /// The first of those failures, which the run reports and retries.
  final SyncGatewayException? fault;

  const _PullOutcome({
    required this.complete,
    this.failedTables = const {},
    this.fault,
  });
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
  /// whole pull.
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
      if (touched.contains(SyncInvalidation.calendar)) {
        touched.add(SyncInvalidation.alerts);
      }
      if (touched.isNotEmpty) {
        // A throwing hook must not mask what ended the run — a halt, a lost
        // access — nor fail a run whose rows all landed.
        try {
          await _e._hooks.afterRun(Set.unmodifiable(touched));
        } catch (error, stack) {
          _warn('afterRun failed: $error\n$stack');
        }
      }
    }
    if (!complete) {
      return _PullOutcome(complete: false, failedTables: failed, fault: fault);
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
    final seenUpTo = _e._signal?.touched[name];
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
  /// failure parks it and the page goes on — an escaped exception would roll
  /// the page back, and every later run would meet it again at the same
  /// cursor (record §3.5). The copies are filed before the cursor moves: a
  /// copy that fails rolls the page back, merge and retired entry included,
  /// so the next run merges the page again and files the copy again rather
  /// than the losing text being dropped.
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
      for (final envelope in page.envelopes) {
        final MergeOutcome outcome;
        try {
          outcome = await db.transaction(
            () => table.mergeRemote(db, envelope, floor: floor),
          );
        } on SyncGatewayException {
          rethrow;
        } catch (error) {
          _park(envelope, error);
          continue;
        }
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
    parked.add((envelope.table, envelope.rowKey));
  }
}

/// What one malformed document raises: a missing or mistyped key, a value a
/// column refuses (drift checks lengths on write), a key that names no row.
/// A pull parks an envelope on anything, these quietly; the push parks only
/// these when it loads rows, and anything else ends its run.
bool _isEnvelopeFault(Object error) =>
    error is FormatException ||
    error is TypeError ||
    error is ArgumentError ||
    error is InvalidDataException;
