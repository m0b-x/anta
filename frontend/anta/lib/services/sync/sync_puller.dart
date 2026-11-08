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

  /// The envelopes set aside this session, by table and key, with the stamp
  /// each carried — empty when it had none readable; a re-delivery of the
  /// same one is not counted twice. Each holds back every outbox entry of
  /// its key for the session, and is stored too ([SyncDao.keyPullParked]):
  /// the cursor has passed it, and a restart that forgot it would push the
  /// row over a version this device never merged (scalability record S8).
  ///
  /// Deliberately stricter than a stored park ([_stored]): in the session
  /// that met the document nothing is known of what it holds, so nothing of
  /// the row goes out; across a launch the stamp alone is kept, and a local
  /// edit above it outranks that version wherever it lands.
  final Map<(String, String), String> parked = {};

  /// The parks stored by earlier sessions, oldest first, read by
  /// [restoreParks] at the first run of a start. One holds back only the
  /// entries at or below its stamp — a later local edit outranks the version
  /// it stands for — and one with no stamp holds back nothing: it is only
  /// counted until a retry reads its document ([_retryParks]). A key parked
  /// again this session stays here ([_setParked]).
  final Map<(String, String), String> _stored = {};

  /// Why each key of [parked] and [_stored] is parked, as the Sync page says
  /// it.
  final Map<(String, String), SyncHeldReason> _reasons = {};

  /// Whether [_stored] was read since the last start.
  bool _restored = false;

  /// Whether this start still owes [_retryParks], done by its first pull.
  bool _retryDue = true;

  /// Whether the next [_retryParks] reads this session's parks too, behind
  /// the stored ones: "Sync now" asked ([retryAll]).
  bool _retryAll = false;

  /// The build that last completed a retry of every stored park, as
  /// [restoreParks] read it; null when none is known, which owes such a
  /// retry too.
  String? _storedBuild;

  /// The page size a timed-out pull left each table at: lowered only, until
  /// [resetSizes] at the next start. A page that outlasted the call's
  /// deadline on this link would outlast it again, and the back-off alone
  /// would retry it forever (scalability record S10).
  final Map<String, int> _takes = {};

  /// The timeouts each table met with no page landing in between; the
  /// second in a row divides the page more steeply.
  final Map<String, int> _timeoutsInARow = {};

  _Puller(this._e);

  /// Back to each table's own page size, at a start only — never when a
  /// drain empties the outbox, as the push's budget is: that happens nearly
  /// every run and says nothing of the pull's next pages, while a slow link
  /// usually lasts, so a size learned there would hold for one run.
  void resetSizes() {
    _takes.clear();
    _timeoutsInARow.clear();
  }

  /// At a start: this session's parks are forgotten, the stored ones read
  /// again by the next run and retried by its first pull.
  void resetParks() {
    parked.clear();
    _stored.clear();
    _reasons.clear();
    _restored = false;
    _retryDue = true;
    _retryAll = false;
    _storedBuild = null;
  }

  /// "Sync now": the next pull reads the parked documents again as a start
  /// does — the [SyncEngine.maxParkRetries] oldest, this session's before the
  /// stored ones, every one under a new build — so one press costs at most
  /// that many reads; the parks keep holding back what they hold meanwhile,
  /// and a retry that fails parks the key again.
  void retryAll() {
    _retryDue = true;
    _retryAll = true;
  }

  /// This session's parks and the stored ones, each key once, with the
  /// stamp each holds and why.
  List<SyncParkedRow> get parks => [
    for (final MapEntry(:key, :value) in {..._stored, ...parked}.entries)
      SyncParkedRow(
        key.$1,
        key.$2,
        value,
        _reasons[key] ?? SyncHeldReason.unreadable,
      ),
  ];

  /// Whether the outbox entry of [key] at [hlc] waits for the space's
  /// version of the row: this session parked it, or a stored park's stamp
  /// is at or above the entry's.
  bool holdsBack((String, String) key, String hlc) {
    if (parked.containsKey(key)) return true;
    final stamp = _stored[key];
    return stamp != null && stamp.isNotEmpty && hlc.compareTo(stamp) <= 0;
  }

  /// Reads the stored parks once per start, from a run already past the
  /// engine's gate — an unbound database reads nothing.
  Future<void> restoreParks() async {
    if (_restored) return;
    final db = _e._db;
    final rows = await db.syncDao.valuesByPrefix(SyncDao.pullParkedPrefix);
    final restored = _readParks(rows, SyncDao.pullParkedPrefix);
    _stored
      ..clear()
      ..addEntries([
        for (final park in restored) MapEntry(park.key, park.stamp),
      ]);
    for (final park in restored) {
      _reasons[park.key] = park.reason ?? SyncHeldReason.unreadable;
    }
    if (restored.isNotEmpty && restored.last.order > _lastOrder) {
      _lastOrder = restored.last.order;
    }
    _storedBuild = rows.isEmpty
        ? null
        : await db.syncDao.getValue(SyncDao.keyPullParkedBuild);
    _restored = true;
  }

  /// Reads the stored parks' documents again, before the first table of
  /// this start's first pull: every one when the build changed since they
  /// were last retried, else the [SyncEngine.maxParkRetries] oldest. A
  /// document that merges now lets go of its park, one that fails again is
  /// parked again, one no longer there lets go too.
  ///
  /// The build is stored only once a pass over every park reached its end:
  /// a pass a failure cut leaves it as it was, so the next start owes every
  /// park again rather than the parks of the tables it never reached (S8
  /// review F5).
  ///
  /// Best effort: a gateway failure — a timeout on a slow link included —
  /// or a local one is logged, ends the retry for this start and lets the
  /// pull go on, whose own calls meet a link that is really down; a retry
  /// that kept failing must not fail every pull of the start (S8 review F6).
  /// A halt still ends the run.
  Future<void> _retryParks(
    SyncBinding bound, {
    required String? floor,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    if (!_retryDue) return;
    // "Sync now" reads this session's parks too, which are stored but not
    // among [_stored]: first, since they are this run's own failures, and a
    // hundred stored parks ahead of them would starve them.
    final session = _retryAll ? parked.keys : const <(String, String)>[];
    if (_stored.isEmpty && session.isEmpty) {
      _retryDue = false;
      _retryAll = false;
      return;
    }
    final build = _e._runningBuild();
    final everything = _storedBuild != build;
    _retryAll = false;
    final parks = {...session, ..._stored.keys};
    final due = everything
        ? parks.toList()
        : parks.take(SyncEngine.maxParkRetries).toList();
    final byTable = <String, List<String>>{};
    for (final (table, rowKey) in due) {
      byTable.putIfAbsent(table, () => []).add(rowKey);
    }
    final space = _e._spaceOf(bound);
    try {
      for (final table in _e._tables) {
        final keys = byTable[table.table];
        if (keys == null) continue;
        await _e._checkHalt(bound);
        final page = await _e._gateway.readRows(space, table.table, keys);
        await _e._reached(tally);
        final answered = {
          for (final envelope in page.envelopes) envelope.rowKey,
          ...page.skipped,
        };
        await _apply(
          bound,
          table,
          page,
          floor: floor,
          touched: touched,
          tally: tally,
          gone: [
            for (final key in keys)
              if (!answered.contains(key)) key,
          ],
        );
      }
      if (everything) {
        await _e._db.syncDao.setValue(SyncDao.keyPullParkedBuild, build);
        _storedBuild = build;
      }
    } on _Halted {
      rethrow;
    } catch (error, stack) {
      _warn('retrying the parked documents failed: $error\n$stack');
    }
    _retryDue = false;
  }

  /// The documents [table]'s next page asks for.
  int _takeOf(SyncTableBinding<Object> table) {
    final most = _e._gateway.maxBatch;
    final own = table.pullPageLimit ?? most;
    return _takes[table.table] ?? (own < most ? own : most);
  }

  /// A page of [table] timed out: divide its page, more steeply on a second
  /// timeout in a row, never below one document.
  void _shrinkTake(SyncTableBinding<Object> table) {
    final name = table.table;
    final row = _timeoutsInARow[name] = (_timeoutsInARow[name] ?? 0) + 1;
    final divisor = row > 1
        ? SyncEngine.repeatedPullTimeoutDivisor
        : SyncEngine.pullTimeoutDivisor;
    final take = _takeOf(table) ~/ divisor;
    _takes[name] = take < 1 ? 1 : take;
  }

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
  ///
  /// A pull that reached the end of every table ends on
  /// [_refileStrandedNotes], after the initial merge's flag is cleared.
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
    // Once for the pull: the server clock only moves forward, so what it
    // showed before the first table bounds it from below for every table.
    final serverSeen = int.tryParse(
      await db.syncDao.getValue(SyncDao.keyServerSeen) ?? '',
    );
    final touched = <SyncInvalidation>{};
    final failed = <String>{};
    SyncGatewayException? fault;
    var complete = true;
    var cut = false;
    _e._setActivity(SyncActivity.pulling);
    try {
      await _retryParks(bound, floor: floor, touched: touched, tally: tally);
      for (final table in tables) {
        try {
          final whole = await _pullTable(
            bound,
            table,
            floor: floor,
            initial: initial,
            serverSeen: serverSeen,
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
    if (everyTable) {
      await db.syncDao.setValue(
        SyncDao.keyFullPullAt,
        '${_e._now().millisecondsSinceEpoch}',
      );
    }
    if (initial && everyTable) {
      await db.syncDao.deleteValue(SyncDao.keyBindMergePending);
      _e._downloadedRows = 0;
    }
    await _refileStrandedNotes();
    await _sweepOrphanValues();
    return const _PullOutcome(complete: true);
  }

  /// Tombstones the counter values of notes a pull tombstoned, which a merged
  /// note delete never cascades to (`CounterDao.sweepOrphanValues`), and
  /// tells the counters as of a merged page's. Gated as
  /// [_refileStrandedNotes]: only after a complete pull, since a table still
  /// to come may carry the note's newer edit that brings it back; and never
  /// while `bind_merge_pending` holds, where the space has not yet had its say
  /// on the notes. Every complete pull, whatever it touched: a note tombstone
  /// an incomplete run pulled is swept by the next complete one, and the sweep
  /// is one statement. A failure is logged and the run goes on; the
  /// next complete pull sweeps again.
  Future<void> _sweepOrphanValues() async {
    final List<String> swept;
    try {
      final db = _e._db;
      if (await db.syncDao.getValue(SyncDao.keyBindMergePending) != null) {
        return;
      }
      swept = await db.counterDao.sweepOrphanValues();
    } catch (error, stack) {
      _warn('sweeping the values of deleted notes failed: $error\n$stack');
      return;
    }
    if (swept.isEmpty) return;
    try {
      await _e._hooks.afterPage('counter_values', [
        for (final key in swept)
          SyncAppliedRow(
            rowKey: key,
            result: MergeResult.applied,
            tombstone: true,
          ),
      ]);
    } catch (error, stack) {
      _warn('afterPage for the swept values failed: $error\n$stack');
    }
  }

  /// Re-files the live notes a pull left under a folder that is a tombstone
  /// here, which the merge-time repair never reached
  /// (`NoteDao.refileNotesUnderDeletedFolders`), and tells the browser and an
  /// open editor of the moves as of a merged page's. Only after a complete
  /// pull: a table still to come may carry the note's own tombstone, or the
  /// folder's live version. The moves are queued like the merge-time
  /// repair's, so this run's drain pushes them.
  ///
  /// A failure is logged and the run goes on: the sweep is one transaction,
  /// so it left nothing behind, and the next complete pull sweeps again.
  Future<void> _refileStrandedNotes() async {
    final List<({String id, String folderId})> moved;
    try {
      moved = await _e._db.noteDao.refileNotesUnderDeletedFolders();
    } catch (error, stack) {
      _warn('re-filing the notes under deleted folders failed: $error\n$stack');
      return;
    }
    if (moved.isEmpty) return;
    try {
      await _e._hooks.afterPage('notes', [
        for (final note in moved)
          SyncAppliedRow(
            rowKey: note.id,
            result: MergeResult.applied,
            tombstone: false,
            moved: true,
            previousParent: note.folderId,
          ),
      ]);
    } catch (error, stack) {
      _warn('afterPage for the re-filed notes failed: $error\n$stack');
    }
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
  /// the foreground before the table's end. [serverSeen] is the stored
  /// `server_seen` as the pull began.
  ///
  /// The first page re-reads the gateway's overlap before the cursor unless
  /// the cursor is settled ([_settled]); a table pulled to its end is then
  /// marked settled at its new cursor, or unmarked.
  ///
  /// A window holding more documents than a page takes is re-read page
  /// after page ([SyncPullPage.scan]) to its end. How far the re-read got is
  /// kept for this walk only: a later run re-reads the window from its
  /// start, since a write received inside it may have become visible after
  /// this walk read past it — the late commit the overlap exists for — and
  /// a run that went on from a stored scan would settle without reading it.
  Future<bool> _pullTable(
    SyncBinding bound,
    SyncTableBinding<Object> table, {
    required String? floor,
    required bool initial,
    required int? serverSeen,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    // Read before the first page: a push landing during the pull moves
    // `touched` past this mark, so the next signal pulls again rather than
    // the table being marked seen up to a write it never read.
    final signal = _e._signalOf(_e._spaceOf(bound));
    final seenUpTo = signal?.touched[name];
    final serverBefore = _later(serverSeen, SyncEngine._latestTouched(signal));
    final stored = await db.syncDao.getValue(SyncDao.keyPullCursor(name));
    var cursor = stored == null ? null : SyncCursor(stored);
    final mark = await db.syncDao.getValue(SyncDao.keyPullSettled(name));
    var resumed = !_settled(cursor, mark, touched: seenUpTo);
    SyncCursor? scan;
    // The page a fetch over [SyncEngine.chunkFetchBudget] halved to, for
    // the next pull of the same page alone.
    int? fitted;
    while (true) {
      await _e._checkHalt(bound);
      if (!_e._foreground) return false;
      final SyncPullPage page;
      try {
        page = await _e._gateway.pullPage(
          _e._spaceOf(bound),
          name,
          after: cursor,
          limit: fitted ?? _takeOf(table),
          resumed: resumed,
          scan: scan,
        );
      } on SyncGatewayException catch (error) {
        // The run still ends on it, retried on the back-off: an abandoned
        // native call may still be using the link.
        if (error.timedOut) _shrinkTake(table);
        rethrow;
      }
      _timeoutsInARow.remove(name);
      await _e._reached(tally);
      tally.pages++;
      final missing = table is NotesBinding
          ? await NotesBinding.missingChunks(db, page.envelopes, floor: floor)
          : null;
      if (missing != null &&
          missing.length * ContentChunker.maxCodeUnits >
              SyncEngine.chunkFetchBudget &&
          page.envelopes.length > 1) {
        // The bodies this page would read before it merges outgrow the
        // budget: the same page again, halved, from the same cursor and
        // scan — nothing of this one was stored. For this page only: a big
        // note does not last the way a slow link does.
        fitted = page.envelopes.length ~/ 2;
        continue;
      }
      fitted = null;
      final nextScan = page.scan;
      resumed = nextScan != null;
      if (page.envelopes.isEmpty) {
        // The gateway skipped every document of the page and advanced the
        // cursor over them. Storing it here is the only store outside
        // `_apply`'s transaction, and what keeps one page of documents this
        // build cannot read from pinning the table's pull for good: a
        // cursor left behind re-reads the same window every run, and no row
        // past it ever arrives (A2 review R44).
        // A re-read's skipped page moves only the scan, which is not stored.
        // The documents skipped are parked with the cursor that passed them,
        // as `_apply` parks its own (scalability record S8).
        final next = page.next;
        final moved = next != null && next.value != cursor?.value;
        final unread = page.skipped.any(
          (key) => !parked.containsKey((name, key)),
        );
        if (moved || unread) {
          await db.transaction(() async {
            await _checkStillBound(bound);
            if (moved) {
              await db.syncDao.setValue(
                SyncDao.keyPullCursor(name),
                next.value,
              );
            }
            for (final key in page.skipped) {
              await _parkUnreadable(name, key);
            }
          });
          if (moved) cursor = next;
        }
        if (!moved && nextScan?.value == scan?.value) break;
        scan = nextScan;
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
        missing: missing,
        // The bind's download counts every row; the wire cutover's re-read
        // the notes it says it re-syncs.
        counts: initial || (_e._updating && table is NotesBinding),
      );
      _e._emit();
      cursor = page.next ?? cursor;
      scan = nextScan;
      if (!page.hasMore) break;
    }
    if (seenUpTo != null) {
      // A max: a snapshot read before this pull may show an older `touched`
      // than one an earlier pull stored, and lowering the mark would pull
      // the table again for a write already read.
      final seen = seenUpTo.microsecondsSinceEpoch;
      final before = int.tryParse(
        await db.syncDao.getValue(SyncDao.keyPullSeen(name)) ?? '',
      );
      if (before == null || seen > before) {
        await db.syncDao.setValue(SyncDao.keyPullSeen(name), '$seen');
      }
    }
    final settles = _settles(cursor, serverBefore, touched: seenUpTo);
    if (settles && cursor!.value != mark) {
      await db.syncDao.setValue(SyncDao.keyPullSettled(name), cursor.value);
    } else if (!settles && mark != null) {
      await db.syncDao.deleteValue(SyncDao.keyPullSettled(name));
    }
    return true;
  }

  /// Whether [cursor] may be resumed exactly, without the overlap re-read:
  /// a pull marked it settled ([mark], see [_settles]) and no snapshot shows
  /// a write to the table past it ([touched], the live `touched` of the
  /// table, null when no snapshot is held).
  ///
  /// Why exact is enough: the mark says the pull that left the table at
  /// [cursor] began when the server clock already stood
  /// [SyncEngine.settledOverlaps] overlaps past it, so every write stamped at
  /// or before [cursor] had become visible before that pull read, and it was
  /// read then or by an earlier pull; a write stamped after [cursor] lies
  /// past it, where an exact resume reads anyway. When the mark or the
  /// cursor's time is missing, or a write landed past the cursor, the
  /// overlap is re-read as it always was.
  bool _settled(SyncCursor? cursor, String? mark, {DateTime? touched}) {
    if (cursor == null || mark != cursor.value) return false;
    final at = _e._gateway.cursorTime(cursor);
    if (at == null) return false;
    return touched == null || !touched.isAfter(at);
  }

  /// Whether a pull that began when the server clock stood at
  /// [serverBefore] (microseconds) and ended at [cursor] settled it: the
  /// clock already stood [SyncEngine.settledOverlaps] times
  /// [SyncGateway.resumeOverlap] past the cursor's time, so no write stamped
  /// at or before the cursor could still become visible
  /// after the pull's reads, and the table's `touched` as the pull began
  /// ([touched]) was not past the cursor — no write landed in or after the
  /// window that this pull did not reach.
  ///
  /// The server time is the latest `touched` of a snapshot of the space —
  /// live, or stored as `server_seen` for a resume or a cold start that has
  /// no snapshot yet — and only ever a lower bound on the server clock, so
  /// the proof errs only toward re-reading.
  bool _settles(SyncCursor? cursor, int? serverBefore, {DateTime? touched}) {
    if (cursor == null || serverBefore == null) return false;
    final at = _e._gateway.cursorTime(cursor);
    if (at == null) return false;
    if (touched != null && touched.isAfter(at)) return false;
    final settledFrom = at.add(
      _e._gateway.resumeOverlap * SyncEngine.settledOverlaps,
    );
    return serverBefore >= settledFrom.microsecondsSinceEpoch;
  }

  static int? _later(int? a, int? b) =>
      a == null ? b : (b == null || a >= b ? a : b);

  /// One page in one transaction: the merges, the conflict copies and the
  /// cursor; then the clock raised to the page's highest stamp and stored
  /// once (readiness R5), and `afterPage`, the copies among its rows as
  /// inserted notes.
  ///
  /// The clock moves only once the page committed, because `hlc.adopt` is
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
  ///
  /// The parks are stored with the page, the documents the gateway skipped
  /// among them, and a park lets go in the page whose envelope of its key
  /// lands — or whose retry found its document [gone] — so a stored park and
  /// the cursor that passed it commit together (scalability record S8).
  ///
  /// [missing] are the chunks a page of notes lacks, when the caller read
  /// them already ([NotesBinding.missingChunks]). A merge that finds one it
  /// did not ask for gone ([ChunkRowsMoved]) fails its part — the parts
  /// before it stay committed, the run ends on the failure, and the next one
  /// fetches the chunk. That is safe because no part but the last moves the
  /// cursor: the next run reads the whole page again, a row an earlier part
  /// stored merges unchanged against itself, and a park stored by an earlier
  /// part is still ahead of the cursor, so the cursor never passes a park it
  /// did not store.
  ///
  /// A notes page's bodies are assembled before any transaction
  /// ([NotesBinding.prepareBodies]), and each part's are cut and encoded
  /// right before its own ([NotesBinding.readyBodies]): Drift's executor is
  /// exclusive while one runs, so the browser and the calendar wait behind
  /// each page, and the page must hold SQL alone. A page whose stored bodies
  /// outgrow [SyncEngine.pullBodyBudget] is committed in parts, each the
  /// unit described above — its own transaction, parks, copies, stamp,
  /// clock advance and hooks — with the cursor, the skipped documents and
  /// [gone] in the last: a part never moves the cursor past an envelope of a
  /// later one, so a run that ends between two parts reads the page again,
  /// where what the first parts stored merges unchanged. [counts] adds each
  /// part's rows to the run's progress as it commits — during the wire
  /// cutover only the live notes that merged, since its total is the live
  /// note count and a tombstone or a parked envelope would carry the line
  /// to "N of N" before the re-read ends.
  Future<void> _apply(
    SyncBinding bound,
    SyncTableBinding<Object> table,
    SyncPullPage page, {
    required String? floor,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
    List<String> gone = const [],
    List<String>? missing,
    bool counts = false,
  }) async {
    final db = _e._db;
    final envelopes = page.envelopes;
    List<PreparedNoteBody?>? prepared;
    Map<String, String> fetched = const {};
    Set<String>? asked;
    if (table is NotesBinding) {
      final missed =
          missing ??
          await NotesBinding.missingChunks(db, envelopes, floor: floor);
      fetched = await _fetchChunks(bound, missed, tally);
      asked = missed.toSet();
      // The first part's, before the bodies are read: the hook precedes all
      // of a page's reads of this database.
      await _e._hooks.beforePage(table.table);
      // Before the reads, so a stop or a switch during the hook ends the run
      // here instead of after a page of bodies.
      await _e._checkHalt(bound);
      prepared = await table.prepareBodies(
        db,
        envelopes,
        floor: floor,
        fetched: fetched,
        asked: asked,
      );
    }
    var start = 0;
    for (final end in _partEnds(envelopes.length, prepared)) {
      final last = end == envelopes.length;
      final live = await _applyPart(
        bound,
        table,
        envelopes.sublist(start, end),
        prepared?.sublist(start, end),
        floor: floor,
        touched: touched,
        tally: tally,
        next: last ? page.next : null,
        skipped: last ? page.skipped : const [],
        gone: last ? gone : const [],
        fetched: fetched,
        asked: asked,
        announced: start == 0 && prepared != null,
      );
      // A stored part's bodies are let go before the next part is encoded.
      prepared?.fillRange(start, end, null);
      if (counts) {
        _e._downloadedRows += _e._updating ? live : end - start;
        if (!last) _e._emit();
      }
      start = end;
    }
  }

  /// The end of each part [_apply] commits a page of [length] envelopes in:
  /// a new part starts where the next stored body would take the current
  /// one past [SyncEngine.pullBodyBudget], so a part holds at least one
  /// envelope whatever its size. A page of any other table, or of notes
  /// whose bodies fit, is one part.
  static List<int> _partEnds(int length, List<PreparedNoteBody?>? prepared) {
    if (prepared == null) return [length];
    final ends = <int>[];
    var spent = 0;
    for (var i = 0; i < length; i++) {
      final size = prepared[i]?.storedLength ?? 0;
      if (spent > 0 && spent + size > SyncEngine.pullBodyBudget) {
        ends.add(i);
        spent = 0;
      }
      spent += size;
    }
    return ends..add(length);
  }

  /// One part of [_apply]'s page: [envelopes] with their [prepared] bodies,
  /// cut and encoded here, merged in one transaction that stores [next] as
  /// the cursor when given and parks [skipped] and lets [gone] go.
  /// [fetched] and [asked] are the page's, for a body the merge assembles
  /// itself. [announced]: `beforePage` ran for it already. Returns how many
  /// of [envelopes] merged as live rows.
  Future<int> _applyPart(
    SyncBinding bound,
    SyncTableBinding<Object> table,
    List<SyncEnvelope> envelopes,
    List<PreparedNoteBody?>? prepared, {
    required String? floor,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
    required SyncCursor? next,
    required List<String> skipped,
    required List<String> gone,
    Map<String, String> fetched = const {},
    Set<String>? asked,
    bool announced = false,
  }) async {
    final db = _e._db;
    final name = table.table;
    if (!announced) await _e._hooks.beforePage(name);
    // The hook may have outlived the binding, the session or the engine.
    await _e._checkHalt(bound);
    final ready = table is NotesBinding && prepared != null
        ? await table.readyBodies(db, envelopes, prepared, floor: floor)
        : prepared;
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
      await _checkStillBound(bound);
      final conflicts = <SyncNoteConflict>[];
      // The queued stamps by key, read once for the page on its first park
      // under the floor.
      Map<String, String>? queued;
      for (final (i, envelope) in envelopes.indexed) {
        final MergeOutcome outcome;
        try {
          outcome = await db.transaction(
            () => table is NotesBinding
                ? table.mergeRemote(
                    db,
                    envelope,
                    floor: floor,
                    fetched: fetched,
                    asked: asked,
                    prepared: ready?[i],
                  )
                : table.mergeRemote(db, envelope, floor: floor),
          );
        } on SyncGatewayException {
          rethrow;
        } on ChunkRowsMoved {
          rethrow;
        } catch (error) {
          if (_abortsTransaction(error)) rethrow;
          await _park(envelope, error);
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
        await _unpark(envelope.table, envelope.rowKey, unparked);
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
              incoming: outcome.loserIncoming,
            ),
          );
        }
      }
      for (final key in skipped) {
        await _parkUnreadable(name, key);
      }
      for (final key in gone) {
        await _unpark(name, key, unparked);
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
      if (next != null) {
        await db.syncDao.setValue(SyncDao.keyPullCursor(name), next.value);
      }
      // With the rows, not after them: a kill between the commit and a store
      // outside it would leave the seed below stamps this page committed,
      // and the first local edit on a merged row would mint under them (A7
      // review R132). The page's highest stamp, not the clock: `hlc.adopt`
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
    for (final key in unparked) {
      parked.remove(key);
      _stored.remove(key);
      _reasons.remove(key);
    }
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
    return rows.where((row) => !row.tombstone).length;
  }

  /// Reads the [missing] chunks a page's manifests name and this device
  /// lacks ([NotesBinding.missingChunks]), [SyncGateway.rowReadBatch] keys a
  /// call, each held to its hash ([ContentChunksBinding.textOf]) — outside
  /// the page's transaction, since it is network, and before its merges,
  /// which assemble each body from them; a chunk two notes of the page share
  /// is read once (scalability record S6b).
  ///
  /// A chunk the space does not hold, or whose document fails the check, is
  /// left out: the merge of each note naming it fails and parks, and the
  /// page's other notes merge. A gateway failure, a timeout included, ends
  /// the run as a failed page does, with nothing parked.
  Future<Map<String, String>> _fetchChunks(
    SyncBinding bound,
    List<String> missing,
    _RunTally tally,
  ) async {
    if (missing.isEmpty) return const {};
    const table = ContentChunksBinding();
    final space = _e._spaceOf(bound);
    final fetched = <String, String>{};
    const batch = SyncGateway.rowReadBatch;
    for (var at = 0; at < missing.length; at += batch) {
      await _e._checkHalt(bound);
      final keys = missing.skip(at).take(batch).toList();
      final page = await _e._gateway.readRows(space, table.table, keys);
      await _e._reached(tally);
      for (final envelope in page.envelopes) {
        try {
          fetched[envelope.rowKey] = ContentChunksBinding.textOf(envelope);
        } on FormatException catch (error) {
          debugPrint('[SyncEngine] chunk ${envelope.rowKey} refused: $error');
        }
      }
    }
    return fetched;
  }

  /// First inside a page's transaction: [SyncEngine._checkHalt] read the
  /// binding before it, outside, and a bind, a rebind or an unbind
  /// committing in between would otherwise take this space's merges, cursor
  /// and stamp into a binding they are not of (review BA-M4). One binding
  /// read per page; the halt rolls back nothing, since nothing is written
  /// yet.
  Future<void> _checkStillBound(SyncBinding bound) async =>
      SyncEngine._haltUnlessStillBound(await _e._binding.read(), bound);

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
  /// park the envelope, at its stamp — none when the stamp is unreadable
  /// too, as nothing then says which local entries it outranks.
  Future<void> _park(SyncEnvelope envelope, Object error) async {
    final row = '${envelope.table}/${envelope.rowKey}';
    if (error is ArgumentError) {
      _warn('parked $row on an ArgumentError, probably a bug: $error');
    } else if (_isEnvelopeFault(error)) {
      debugPrint('[SyncEngine] parked $row: $error');
    } else {
      _warn('parked $row on ${error.runtimeType}: $error');
    }
    var stamp = envelope.hlc;
    try {
      HlcTimestamp.parse(stamp);
    } on FormatException {
      stamp = '';
    }
    await _setParked(
      envelope.table,
      envelope.rowKey,
      stamp,
      error is ChunksMissing
          ? SyncHeldReason.awaitingText
          : SyncHeldReason.unreadable,
    );
  }

  /// Parks a document of [table] the gateway skipped as unreadable, with no
  /// stamp, unless this session parked it already. A stored park met again
  /// is stored again, with a new order: a retry that found it unreadable
  /// once more must move it behind the others, or a hundred such parks
  /// would take every start's retries until a build change (S8 re-review
  /// R1).
  Future<void> _parkUnreadable(String table, String rowKey) async {
    if (parked.containsKey((table, rowKey))) return;
    debugPrint('[SyncEngine] parked $table/$rowKey: unreadable');
    await _setParked(table, rowKey, '', SyncHeldReason.unreadable);
  }

  /// Records the park and stores it, inside the caller's page transaction;
  /// counted once per key, and never lowered to a lower or empty stamp: the
  /// stamp says which local entries a version this device never merged
  /// outranks, and a later unreadable version does not make the earlier one
  /// merged (S8 review F4).
  ///
  /// A key an earlier session parked, retried and failing again at the
  /// stamp it was stored with, stays among [_stored] alone: holding back
  /// more than the stored park did would hold a park with no stamp across
  /// every launch after all. Any other version of it — a newer one, or one
  /// now unreadable — is a version this session met and could not merge, so
  /// the key is parked for the session too and holds back everything, as
  /// every park of this session does.
  Future<void> _setParked(
    String table,
    String rowKey,
    String stamp,
    SyncHeldReason reason,
  ) async {
    final key = (table, rowKey);
    _reasons[key] = reason;
    final before = _stored[key];
    final String kept;
    if (before != null) {
      kept = stamp.compareTo(before) > 0 ? stamp : before;
      // Behind the others, as its new order stores it: the next "Sync now"
      // of this session reaches the parks after it.
      _stored
        ..remove(key)
        ..[key] = kept;
      if (stamp != before) parked[key] = kept;
    } else {
      final held = parked[key];
      if (held == null) _e._parks++;
      kept = held != null && held.compareTo(stamp) > 0 ? held : stamp;
      parked[key] = kept;
    }
    await _e._db.syncDao.setValue(
      SyncDao.keyPullParked(table, rowKey),
      _parkValue(_nextOrder(), kept, reason),
    );
  }

  /// The order of the park stored last, this session or a restored one.
  int _lastOrder = 0;

  /// The next park's order: the clock in microseconds, kept rising past
  /// [_lastOrder] — `updated_at` stores whole seconds, and parks stored in
  /// one second would rotate in key order instead of age.
  int _nextOrder() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return _lastOrder = now > _lastOrder ? now : _lastOrder + 1;
  }

  /// Lets go of a park of [table]'s [rowKey], if any: its stored key is
  /// deleted in the caller's transaction, and the key added to [unparked],
  /// which leaves the session's sets once that transaction committed.
  Future<void> _unpark(
    String table,
    String rowKey,
    List<(String, String)> unparked,
  ) async {
    final key = (table, rowKey);
    unparked.add(key);
    if (!parked.containsKey(key) && !_stored.containsKey(key)) return;
    await _e._db.syncDao.deleteValue(SyncDao.keyPullParked(table, rowKey));
  }
}

/// The digits a stored park's order is padded to, so the values sort as
/// numbers would.
const int _orderDigits = 20;

/// A stored park's value, pull or push ([SyncDao.keyPullParked]).
String _parkValue(int order, String stamp, SyncHeldReason reason) =>
    '${order.toString().padLeft(_orderDigits, '0')}|$stamp|${reason.name}';

/// A stored park as [_readParks] reads it back; [reason] is null for a park
/// stored before the reason was.
typedef _StoredPark = ({
  int order,
  (String, String) key,
  String stamp,
  SyncHeldReason? reason,
});

/// The parks among [rows], `sync_metadata` keys under [prefix] with their
/// values, oldest first; one that does not parse is skipped.
List<_StoredPark> _readParks(List<(String, String)> rows, String prefix) {
  final parks = <_StoredPark>[];
  for (final (name, value) in rows) {
    final rest = name.substring(prefix.length);
    final dot = rest.indexOf('.');
    final fields = value.split('|');
    final order = fields.length < 2 ? null : int.tryParse(fields[0]);
    if (dot <= 0 || order == null) continue;
    parks.add((
      order: order,
      key: (rest.substring(0, dot), rest.substring(dot + 1)),
      stamp: fields[1],
      reason: fields.length > 2
          ? SyncHeldReason.values.asNameMap()[fields[2]]
          : null,
    ));
  }
  parks.sort((x, y) => x.order.compareTo(y.order));
  return parks;
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
