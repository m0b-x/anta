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
    // Each attempt at the initial merge counts its own pages: an attempt a
    // leave cut or a fault ended would otherwise add its rows to the last
    // one's and the bind progress would report more rows than the space
    // holds (A2 review R55).
    if (initial) _e._downloadedRows = 0;
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
      if (page.envelopes.isEmpty) {
        // The gateway skipped every document of the page and advanced the
        // cursor over them. Storing it here is the only store outside
        // `_apply`'s transaction, and what keeps one page of documents this
        // build cannot read from pinning the table's pull for good: a
        // cursor left behind re-reads the same window every run, and no row
        // past it ever arrives (A2 review R44).
        final next = page.next;
        if (next == null || next.value == cursor?.value) break;
        await db.syncDao.setValue(SyncDao.keyPullCursor(name), next.value);
        cursor = next;
        if (!page.hasMore) break;
        continue;
      }
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

  /// One page in one transaction: the merges, the conflict copies and the
  /// cursor; then the clock raised to the page's highest stamp and stored
  /// once (readiness R5), and `afterPage`, the copies among its rows as
  /// inserted notes.
  ///
  /// The clock moves only once the page committed, because `hlc.update` is
  /// in-memory and a rollback does not undo it: advanced inside, a page that
  /// rolled back would let the next local edit out-stamp a remote row this
  /// device never merged, which then loses everywhere with no conflict copy
  /// (R65). The store follows the commit for the same reason — inside it
  /// would record the clock the page had before its own stamps.
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
    // The keys whose envelope landed, taken out of [parked] only once the
    // page committed: a later envelope aborting the transaction would
    // otherwise leave the key out of the drain's hold-back while its remote
    // version was rolled back (S3d review H2, A2 review R48).
    final unparked = <(String, String)>[];
    var changed = false;
    // The highest stamp of the envelopes that merged, applied to the clock
    // once the page committed; a parked envelope wrote nothing and moves it
    // no more than a document this device never received.
    String? advance;
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
              for (final entry in await db.syncOutboxDao.pendingForTable(name))
                entry.rowKey: entry.hlc,
            };
            await _yieldToFloor(name, envelope.rowKey, floor, queued);
          }
          continue;
        }
        // A later envelope of a parked key landed: the row is no longer
        // missing, and the drain may push it again.
        unparked.add((envelope.table, envelope.rowKey));
        if (advance == null || envelope.hlc.compareTo(advance!) > 0) {
          advance = envelope.hlc;
        }
        rows.add(
          SyncAppliedRow(
            rowKey: envelope.rowKey,
            result: outcome.result,
            tombstone: isTombstone(envelope),
            moved: outcome.moved,
            previousParent: outcome.previousParent,
            content: outcome.mergedContent,
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
              content: conflict.loserContent,
            ),
          );
        }
      }
      final next = page.next;
      if (next != null) {
        await db.syncDao.setValue(SyncDao.keyPullCursor(name), next.value);
      }
      // With the rows, not after them: a kill between the commit and a store
      // outside it would leave the seed below stamps this page committed,
      // and the first local edit on a merged row would mint under them (A7
      // review R132). The page's highest stamp, not the clock: `hlc.update`
      // is in-memory and a rollback would not undo it, so the advance waits
      // for the commit (R65) — and the seed only has to cover the rows.
      final highest = advance;
      if (highest != null) await db.persistStamp(highest);
    });
    final stamp = advance;
    // Only the in-memory advance is left out here; the seed went in with the
    // page. A page that merged nothing moves neither, where before it paid a
    // `sync_metadata` insert of its own (A7 review R146).
    if (stamp != null) CrdtMerge.advanceClock(db, stamp);
    parked.removeAll(unparked);
    if (changed) touched.add(table.invalidation);
    tally.pulled += rows.length;
    try {
      await _e._hooks.afterPage(name, List.unmodifiable([...rows, ...copies]));
    } catch (error, stack) {
      // The page committed before this call, so a throwing cache hook must
      // not turn an applied page into a table fault — the rule `afterRun`
      // was given by the S3d review's L17 (A2 review R47). `beforePage`
      // keeps throwing: it precedes the page, so failing there is right.
      _warn('afterPage for $name failed: $error\n$stack');
    }
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
/// review H1). The app's database runs in a background isolate, which hands
/// a SQLite error over wrapped, so the cause is unwrapped first (S5 review
/// M3).
///
/// A deny-list — every code but 19 — is safe only here, and must not be
/// copied into a path that swallows: this one rethrows, so a code it reads
/// too strictly fails the page and the page is pulled again, and
/// [SqliteException.resultCode] is the primary code, where an extended
/// `1555 SQLITE_CONSTRAINT_PRIMARYKEY` already reads as 19 (A6 review R128).
bool _abortsTransaction(Object error) {
  var cause = error;
  while (cause is DriftRemoteException) {
    cause = cause.remoteCause;
  }
  return cause is CouldNotRollBackException ||
      (cause is SqliteException && cause.resultCode != _sqliteConstraint);
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
