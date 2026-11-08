part of 'sync_engine.dart';

/// The push side of a run.
class _Pusher {
  final SyncEngine _e;

  /// The outbox entries set aside this session, by table and key, with the
  /// stamp each was parked at: one bad row must not stop every other row,
  /// and an edit since — a shortened note — raises the stamp, so the row is
  /// tried again at once instead of next launch (record §3.5).
  final Map<(String, String), String> parked = {};

  /// The parks stored for the next sessions ([SyncDao.keyPushParked]),
  /// oldest first: this session's, and the earlier sessions' a start did not
  /// drop. Each holds its key's entry back at or below its stamp; an edit
  /// since is a new write, and lets go of the park (scalability record S7).
  final Map<(String, String), String> _stored = {};

  /// Why each key of [parked] and [_stored] is parked, as the Sync page says
  /// it.
  final Map<(String, String), SyncHeldReason> _reasons = {};

  /// Whether [_stored] was read since the last start.
  bool _restored = false;

  /// Every park [restoreParks] found still stored and holding, with the
  /// stamp each held — the ones it let the drain try again among them, which
  /// are in neither [parked] nor [_stored] until an outcome. A refusal of
  /// one at or below that stamp is a known row refused again, which says
  /// nothing of the rules, so it is not counted toward [maxRefusedPerDrain].
  ///
  /// Rebuilt from what is stored at every restore, never carried in memory
  /// alone: a retry cut short — an offline drain, a stop, a killed process —
  /// leaves its parks stored, and the next "Sync now" or start must still
  /// read their refusals as known (scalability record S7).
  final Map<(String, String), String> _retried = {};

  /// The order of the park stored last, this session or a restored one.
  int _lastOrder = 0;

  _Pusher(this._e);

  /// At a start and at "Sync now": this session's parks are forgotten, so
  /// the drain tries them again, and the stored ones are read again by the
  /// next run, which drops the ones due a retry.
  void resetParks() {
    parked.clear();
    _stored.clear();
    _reasons.clear();
    _retried.clear();
    _restored = false;
  }

  /// Whether [entry] is a stored park's row tried again at the stamp it was
  /// parked at, or below.
  bool _isRetry(SyncOutboxRow entry) {
    final stamp = _retried[(entry.syncedTable, entry.rowKey)];
    return stamp != null && entry.hlc.compareTo(stamp) <= 0;
  }

  /// This session's parks and the stored ones, each key once, with the
  /// stamp each holds and why — a row being tried again among them under
  /// its stored reason, until it lands, is raised or is refused again.
  List<SyncParkedRow> get parks => [
    for (final MapEntry(:key, :value) in {
      ..._retried,
      ..._stored,
      ...parked,
    }.entries)
      SyncParkedRow(
        key.$1,
        key.$2,
        value,
        _reasons[key] ?? SyncHeldReason.unencodable,
      ),
  ];

  /// Reads the stored parks once per start, from a run already past the
  /// engine's gate, and drops the ones due a retry so the drain tries them
  /// again: every one under a new build — which may encode a row this one
  /// could not — else the [SyncEngine.maxParkRetries] oldest, at a start and
  /// at "Sync now" alike, so each comes round while one run stays cheap. A
  /// row refused again is parked again under a new order, behind the others.
  ///
  /// A dropped park stays stored until its row has an outcome ([_release],
  /// [_park]): deleting it here lost it to a drain that then failed offline.
  /// A park whose entry is gone — retired by a pull — or was raised past its
  /// stamp by an edit lets go: it holds nothing back any more.
  Future<void> restoreParks() async {
    if (_restored) return;
    final db = _e._db;
    final restored = _readParks(
      await db.syncDao.valuesByPrefix(SyncDao.pushParkedPrefix),
      SyncDao.pushParkedPrefix,
    );
    final build = _e._runningBuild();
    final newBuild =
        await db.syncDao.getValue(SyncDao.keyPushParkedBuild) != build;
    final due = newBuild ? restored.length : SyncEngine.maxParkRetries;
    // A row of a table this build has no binding for fails the run it is
    // met in (A7 review R134): only another build can push it.
    final kept = [
      for (final (index, park) in restored.indexed)
        if (index >= due || (!newBuild && _e._bindingFor(park.key.$1) == null))
          park,
    ];
    final keptKeys = {for (final park in kept) park.key};
    final byTable = <String, List<String>>{};
    for (final park in restored) {
      byTable.putIfAbsent(park.key.$1, () => []).add(park.key.$2);
    }
    final queued = <(String, String), String>{};
    for (final MapEntry(key: table, value: keys) in byTable.entries) {
      for (final entry in (await db.syncOutboxDao.pendingKeys(
        table,
        keys,
      )).values) {
        queued[(table, entry.rowKey)] = entry.hlc;
      }
    }
    final holding = [
      for (final park in restored)
        if (queued[park.key] case final hlc?
            when hlc.compareTo(park.stamp) <= 0)
          park,
    ];
    if (holding.length < restored.length) {
      final holds = {for (final park in holding) park.key};
      await db.transaction(() async {
        for (final park in restored) {
          if (holds.contains(park.key)) continue;
          await db.syncDao.deleteValue(
            SyncDao.keyPushParked(park.key.$1, park.key.$2),
          );
        }
      });
    }
    await db.syncDao.setValue(SyncDao.keyPushParkedBuild, build);
    _stored
      ..clear()
      ..addEntries([
        for (final park in holding)
          if (keptKeys.contains(park.key)) MapEntry(park.key, park.stamp),
      ]);
    _retried
      ..clear()
      ..addEntries([
        for (final park in holding) MapEntry(park.key, park.stamp),
      ]);
    for (final park in holding) {
      _reasons[park.key] = park.reason ?? SyncHeldReason.unencodable;
    }
    if (restored.isNotEmpty && restored.last.order > _lastOrder) {
      _lastOrder = restored.last.order;
    }
    _restored = true;
  }

  /// Whether a park holds [key]'s entry at [hlc] back: this session's at
  /// that very stamp, or a stored one at or above it.
  bool _holds((String, String) key, String hlc) {
    if (parked[key] == hlc) return true;
    final stamp = _stored[key];
    return stamp != null && hlc.compareTo(stamp) <= 0;
  }

  /// Lets go of every park of [keys], the stored ones — a row being tried
  /// again included — in one transaction: their rows landed, or an edit
  /// raised their entries past the parks.
  Future<void> _release(List<(String, String)> keys) async {
    final stored = [
      for (final key in keys)
        if (_stored.containsKey(key) || _retried.containsKey(key)) key,
    ];
    if (stored.isNotEmpty) {
      final db = _e._db;
      await db.transaction(() async {
        for (final (table, rowKey) in stored) {
          await db.syncDao.deleteValue(SyncDao.keyPushParked(table, rowKey));
        }
      });
    }
    for (final key in keys) {
      parked.remove(key);
      _stored.remove(key);
      _reasons.remove(key);
      _retried.remove(key);
    }
  }

  /// The next park's order, as the pull's ([_Puller._nextOrder]).
  int _nextOrder() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return _lastOrder = now > _lastOrder ? now : _lastOrder + 1;
  }

  /// About 900 KB of JSON: under Firestore's 1 MiB document with room for
  /// the envelope's own fields, so an oversized row is parked here rather
  /// than refused for its whole batch.
  static const int maxDocumentBytes = 900000;

  /// About 8 MiB of row data per push at most, under Firestore's 10 MiB
  /// request: a batch near the cap on a slow uplink would time out and be
  /// retried whole forever (S5 review M5).
  static const int maxBatchBytes = 8 * 1024 * 1024;

  /// The part budget each session starts at: 8 MiB inside the call's 60 s
  /// needs over 1.1 Mbit/s, a quarter of it a quarter of that. It doubles
  /// back toward [maxBatchBytes] as full parts land (scalability record S10).
  static const int firstPartBytes = 2 * 1024 * 1024;

  /// The least a timed-out push halves the part budget to; a row larger
  /// than it still goes out alone.
  static const int minPartBytes = 1024 * 1024;

  /// More rows than this refused by the rules in one drain means the rules
  /// changed, not the rows (record §3.5). Fresh rows only: a stored park
  /// tried again and refused again is known, and a start or a "Sync now"
  /// over more than this many of them is no rules change (scalability
  /// record S7).
  static const int maxRefusedPerDrain = 20;

  /// The row bytes a part may carry now.
  int _budget = firstPartBytes;

  /// The most [_budget] may grow back to this session: a part size that
  /// timed out on this link is not tried again until [resetSizes].
  int _ceiling = maxBatchBytes;

  /// The wait [_keepSpacing] is in, so [cancelSpacing] can end it.
  Timer? _spacing;
  Completer<void>? _spaced;

  /// Back to the first part's budget: at a start, and once a drain emptied
  /// the outbox — the backlog that strained the link is through.
  void resetSizes() {
    _budget = firstPartBytes;
    _ceiling = maxBatchBytes;
  }

  /// Pushes the outbox in parts, oldest change first, until it is empty or
  /// a call fails. The entries of [skipTables] stay queued for a later run.
  ///
  /// A part is cut by [_budget] as its rows are encoded, so the drain holds
  /// one part and one row of bodies at a time; the rest stays queued and is
  /// read again for the next part. The part after one cut by bytes starts
  /// [SyncEngine.minPartSpacing] after it at the earliest: each push writes
  /// the space document too, and parts smaller than the count cut must not
  /// raise its write rate (A8 review R97).
  Future<void> drain(
    SyncBinding bound,
    _RunTally tally, {
    Set<String> skipTables = const {},
  }) async {
    final maxBatch = _e._gateway.maxBatch;
    // The entry stamp each row was pushed at in this drain: an entry the
    // acknowledgement could not retire at the same stamp is not pushed again
    // until an edit raises it.
    final pushed = <(String, String), String>{};
    final drain = _DrainState();
    // A key whose pull envelope parked is held back too: this device lacks
    // the space's version of that row, which may be the newer one (S3d
    // review H2, `_Puller.holdsBack`).
    bool eligible(SyncOutboxRow entry) {
      final key = (entry.syncedTable, entry.rowKey);
      return !skipTables.contains(entry.syncedTable) &&
          !_holds(key, entry.hlc) &&
          pushed[key] != entry.hlc &&
          !_e._puller.holdsBack(key, entry.hlc);
    }

    // When the last part cut by bytes went out.
    DateTime? cutPartAt;
    while (true) {
      await _e._checkHalt(bound);
      final entries = await _nextEntries(eligible, maxBatch);
      if (entries.isEmpty) break;
      // An entry let through past its key's park was raised by an edit: a
      // new write, which the park no longer describes. A row being tried
      // again at its park's stamp keeps its park until the outcome.
      final raised = [
        for (final entry in entries)
          if (parked.containsKey((entry.syncedTable, entry.rowKey)) ||
              _stored.containsKey((entry.syncedTable, entry.rowKey)) ||
              (_retried.containsKey((entry.syncedTable, entry.rowKey)) &&
                  !_isRetry(entry)))
            (entry.syncedTable, entry.rowKey),
      ];
      if (raised.isNotEmpty) await _release(raised);
      _e._setActivity(SyncActivity.pushing);
      final (:part, :cut) = await _prepare(
        entries,
        bound.accountUid,
        pushed,
        drain,
      );
      _e._emit();
      if (part.isEmpty) continue;
      for (final queued in part) {
        pushed[(queued.entry.syncedTable, queued.entry.rowKey)] =
            queued.entry.hlc;
      }
      if (cutPartAt != null) await _keepSpacing(cutPartAt);
      cutPartAt = cut ? _e._now() : null;
      await _push(bound, part, tally, drain);
    }
    // The backlog that strained the link is through; the pull's sizes are
    // kept (`_Puller.resetSizes`).
    if (await _e._db.syncOutboxDao.count() == 0) resetSizes();
  }

  /// Waits out what is left of [SyncEngine.minPartSpacing] since [last] on
  /// the engine's scheduler. A wall clock set back waits the whole spacing.
  Future<void> _keepSpacing(DateTime last) async {
    const spacing = SyncEngine.minPartSpacing;
    final since = _e._now().difference(last);
    if (since >= spacing) return;
    final wait = since.isNegative ? spacing : spacing - since;
    final done = _spaced = Completer<void>();
    _spacing = _e._scheduler.schedule(wait, cancelSpacing);
    await done.future;
  }

  /// Ends a spacing wait at once — its timer fired, or the engine stopped:
  /// the drain then meets the halt before its next push rather than holding
  /// the stop for the rest of the wait.
  void cancelSpacing() {
    _spacing?.cancel();
    _spacing = null;
    final done = _spaced;
    _spaced = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// The oldest [maxBatch] entries [eligible] lets through, paging further
  /// down the queue while the entries it holds back fill the window.
  ///
  /// Keyset, not a growing limit: the initial merge queues every row of
  /// every table, and one table held back made each page re-read the queue
  /// from the top — the drain was O(n²) in the queue (A2 review R51).
  Future<List<SyncOutboxRow>> _nextEntries(
    bool Function(SyncOutboxRow entry) eligible,
    int maxBatch,
  ) async {
    final outbox = _e._db.syncOutboxDao;
    final entries = <SyncOutboxRow>[];
    SyncOutboxKey? after;
    while (entries.length < maxBatch) {
      final queued = await outbox.pending(limit: maxBatch, after: after);
      if (queued.isEmpty) break;
      for (final entry in queued) {
        if (eligible(entry)) entries.add(entry);
        if (entries.length == maxBatch) return entries;
      }
      if (queued.length < maxBatch) break;
      final last = queued.last;
      after = (hlc: last.hlc, table: last.syncedTable, rowKey: last.rowKey);
    }
    return entries;
  }

  /// The next part out of [entries]: each row read as it stands now, a
  /// tombstone included, encoded in the queue's order until the next one
  /// would carry the part past [_budget] — [cut] then, the part holding at
  /// least one row and the rest left queued, unencoded. A row gone since it
  /// was queued (an import wipe) retires its entry; one that cannot be
  /// encoded or would exceed [maxDocumentBytes] is parked before the push.
  ///
  /// The rows are loaded for every entry, the bodies only as they are
  /// encoded: a note's row is its metadata, its manifest is read by
  /// `encode`.
  ///
  /// A note's manifest follows every chunk it names that is still queued,
  /// wherever that entry sits in the queue ([_chunksFirst]): its chunks are
  /// encoded one at a time into the part while they fit, the manifest after
  /// the last of them — and when they overflow the part, the rest go out in
  /// the parts after it and the manifest waits for them. So the space never
  /// holds a manifest whose chunks it lacks (scalability record S6). A chunk
  /// that did not fit is kept encoded for the next part
  /// ([_DrainState.chunkAhead]), so each is encoded once per drain.
  Future<({List<_Queued> part, bool cut})> _prepare(
    List<SyncOutboxRow> entries,
    String boundUid,
    Map<(String, String), String> pushed,
    _DrainState drain,
  ) async {
    final db = _e._db;
    final byTable = <String, List<SyncOutboxRow>>{};
    for (final entry in entries) {
      byTable.putIfAbsent(entry.syncedTable, () => []).add(entry);
    }
    final bindings = <String, SyncTableBinding<Object>>{};
    final loaded = <String, Map<String, Object>>{};
    final faulted = <String, Set<String>>{};
    for (final MapEntry(key: table, value: group) in byTable.entries) {
      final binding = _e._bindingFor(table);
      // An entry naming a table no binding covers is this build's bug, not a
      // row's: it ends the run, where parking would have stalled every row
      // of that table for the session (A2 review R46). Parked all the same,
      // and before the throw: the entry stays queued, so a run that only
      // failed would meet it again at the same place and the engine would
      // never get past it (A7 review R134).
      if (binding == null) {
        final fault = ArgumentError.value(
          table,
          'table',
          'no binding for the table',
        );
        for (final entry in group) {
          await _park(entry, fault);
        }
        throw fault;
      }
      final faults = faulted[table] = <String>{};
      final rows = await _loadGroup(binding, group, faults);
      bindings[table] = binding;
      final byKey = loaded[table] = {
        for (final row in rows) binding.rowKeyOf(row): row,
      };
      if (table == _chunksTable) await _keepOwnChunks(byKey, boundUid);
    }
    // In the queue's `(hlc, table, rowKey)` order: the rows are read one
    // table at a time, but a push that stops part-way must have sent a prefix
    // of history rather than whole tables (A2 review R50).
    final maxBatch = _e._gateway.maxBatch;
    final part = <_Queued>[];
    var partBytes = 0;
    // The chunk hashes [part] carries, so a chunk a manifest pulled in ahead
    // of its place in the queue is not sent twice.
    final chunksInPart = <String>{};
    void add(_Queued queued) {
      part.add(queued);
      partBytes += queued.bytes;
      if (queued.entry.syncedTable == _chunksTable) {
        chunksInPart.add(queued.entry.rowKey);
      }
    }

    // Whether a row of [bytes] still goes into the part; the first always
    // does, however large.
    bool fits(int bytes) =>
        part.isEmpty ||
        (partBytes + bytes <= _budget && part.length < maxBatch);

    queue:
    for (final entry in entries) {
      final table = entry.syncedTable;
      if (table == _chunksTable && chunksInPart.contains(entry.rowKey)) {
        continue;
      }
      if (faulted[table]!.contains(entry.rowKey)) continue;
      final row = loaded[table]![entry.rowKey];
      if (row == null) {
        await db.syncOutboxDao.ackThrough(table, entry.rowKey, entry.hlc);
        continue;
      }
      if (table == _chunksTable) {
        final chunk = await _encodeChunk(
          bindings[table]!,
          entry,
          row,
          boundUid,
          drain,
        );
        if (chunk == null) continue;
        if (!fits(chunk.bytes)) {
          drain.chunkAhead = chunk;
          return (part: part, cut: true);
        }
        add(chunk);
        continue;
      }
      final SyncEnvelope envelope;
      try {
        envelope = await bindings[table]!.encode(db, row, boundUid: boundUid);
      } on Object catch (error) {
        await _park(entry, error);
        continue;
      }
      final bytes = envelope.wireBytes;
      if (bytes > maxDocumentBytes) {
        await _park(entry, 'over $maxDocumentBytes bytes');
        continue;
      }
      final chunks = await _chunksFirst(entry, envelope, chunksInPart, pushed);
      if (chunks == null) continue;
      if (chunks.isNotEmpty) {
        final binding = _e._bindingFor(_chunksTable);
        if (binding == null) {
          await _park(entry, _unpushable);
          continue;
        }
        final rows = {
          for (final row in await binding.loadByKeys(db, [
            for (final chunk in chunks) chunk.rowKey,
          ]))
            binding.rowKeyOf(row): row,
        };
        await _keepOwnChunks(rows, boundUid);
        for (final chunk in chunks) {
          final row = rows[chunk.rowKey];
          if (row == null) {
            await db.syncOutboxDao.ackThrough(
              _chunksTable,
              chunk.rowKey,
              chunk.hlc,
            );
            await _park(entry, _unpushable);
            continue queue;
          }
          final queued = await _encodeChunk(
            binding,
            chunk,
            row,
            boundUid,
            drain,
          );
          if (queued == null) {
            await _park(entry, _unpushable);
            continue queue;
          }
          // The chunks left go in the parts after this one, and the manifest
          // after them.
          if (!fits(queued.bytes)) {
            drain.chunkAhead = queued;
            return (part: part, cut: true);
          }
          add(queued);
        }
      }
      if (!fits(bytes)) return (part: part, cut: true);
      add(_Queued(entry, envelope, bytes, _ackOf(entry, envelope)));
    }
    return (part: part, cut: false);
  }

  /// The chunk document for [entry]'s [row], the one [_DrainState.chunkAhead]
  /// holds when it is the same entry; null once the chunk is parked — its
  /// text no longer matches its hash, or it is over the size the rules take.
  Future<_Queued?> _encodeChunk(
    SyncTableBinding<Object> binding,
    SyncOutboxRow entry,
    Object row,
    String boundUid,
    _DrainState drain,
  ) async {
    final ahead = drain.chunkAhead;
    if (ahead != null &&
        ahead.entry.rowKey == entry.rowKey &&
        ahead.entry.hlc == entry.hlc) {
      drain.chunkAhead = null;
      return ahead;
    }
    try {
      final envelope = await binding.encode(_e._db, row, boundUid: boundUid);
      return _Queued(entry, envelope, envelope.wireBytes, entry.hlc);
    } on Object catch (error) {
      await _park(entry, error);
      return null;
    }
  }

  static const String _chunksTable = 'content_chunks';

  /// The stamp a pushed row's entry is retired through: the row's stamp at
  /// read time, so an edit made during the push stays queued — except for a
  /// chunk, whose rows carry the stamps of the notes that hold it while its
  /// entry carries the write that queued it, and whose text cannot change
  /// under its hash: it is retired at the entry's own stamp.
  static String _ackOf(SyncOutboxRow entry, SyncEnvelope envelope) =>
      entry.syncedTable == _chunksTable ? entry.hlc : envelope.hlc;

  /// The queued entries of the chunks [manifest] names that are neither in
  /// the part ([inPart]) nor pushed earlier in this drain ([pushed]), in the
  /// manifest's order — empty for any other row.
  ///
  /// Null once [entry] is parked because one of them is: a manifest never
  /// goes ahead of its chunks. Parked is checked before pushed, since a
  /// chunk the refusal bisect parked was pushed in this drain too, and a
  /// stored park counts as this session's: after a restart the note's next
  /// raise must not push a chunk the rules refused at that stamp. The
  /// manifest's own stamp is parked, so the next save of the note tries
  /// again at once.
  Future<List<SyncOutboxRow>?> _chunksFirst(
    SyncOutboxRow entry,
    SyncEnvelope manifest,
    Set<String> inPart,
    Map<(String, String), String> pushed,
  ) async {
    if (manifest.table != 'notes') return const [];
    final named = dataOf(manifest)[NotesBinding.chunksKey];
    if (named is! List || named.isEmpty) return const [];
    final hashes = {for (final hash in named) hash as String};
    final queued = await _e._db.syncOutboxDao.pendingKeys(
      _chunksTable,
      hashes.toList(),
    );
    final needed = <SyncOutboxRow>[];
    for (final hash in hashes) {
      final chunk = queued[hash];
      if (chunk == null) continue;
      if (_holds((_chunksTable, hash), chunk.hlc)) {
        await _park(entry, _refusedChunk);
        return null;
      }
      if (inPart.contains(hash) || pushed.containsKey((_chunksTable, hash))) {
        continue;
      }
      needed.add(chunk);
    }
    return needed;
  }

  /// Why a manifest is parked for a chunk it names: the rules refused it,
  /// or it could not be read or encoded here.
  static const String _refusedChunk = 'a chunk it names was refused';
  static const String _unpushable = 'a chunk it names cannot be pushed';

  /// Drops from [rows], `content_chunks` rows by hash, every chunk that only
  /// notes of another account hold: a chunk row carries no owner, its note
  /// does, and that account's text is never pushed into this one's space
  /// (D16). Its entry is then retired as a row gone, and a manifest naming
  /// it is held back.
  Future<void> _keepOwnChunks(Map<String, Object> rows, String boundUid) async {
    if (rows.isEmpty) return;
    final own = await _e._db.contentChunkDao.hashesOwnedBy(
      rows.keys.toList(),
      boundUid,
    );
    rows.removeWhere((hash, _) => !own.contains(hash));
  }

  /// The rows of [group], bisected down to the entries whose load faults,
  /// whose keys land in [faulted] parked. A load fault belongs to a row — a
  /// column no longer decodable — so parking the whole group would stall up
  /// to a whole batch of healthy rows of that table for the session, every
  /// session, since the cause is deterministic (A2 review R46).
  Future<List<Object>> _loadGroup(
    SyncTableBinding<Object> binding,
    List<SyncOutboxRow> group,
    Set<String> faulted,
  ) async {
    try {
      return await binding.loadByKeys(_e._db, [
        for (final entry in group) entry.rowKey,
      ]);
    } on Object catch (error) {
      if (!_isEnvelopeFault(error)) rethrow;
      if (group.length == 1) {
        await _park(group.single, error);
        faulted.add(group.single.rowKey);
        return const [];
      }
      final middle = group.length ~/ 2;
      return [
        ...await _loadGroup(binding, group.sublist(0, middle), faulted),
        ...await _loadGroup(binding, group.sublist(middle), faulted),
      ];
    }
  }

  /// Pushes [batch]; a refusal of rows rather than of the drain is narrowed
  /// to the refused rows, which are parked while the rest lands.
  ///
  /// A timeout halves the part budget, never below [minPartBytes], and caps
  /// it there for the session; the run still ends on it, retried on the
  /// back-off, since the abandoned native call may still be using the link.
  /// A full part — at least half the budget — that landed doubles the budget
  /// up to that cap: the link carried it inside the deadline.
  Future<void> _push(
    SyncBinding bound,
    List<_Queued> batch,
    _RunTally tally,
    _DrainState drain,
  ) async {
    try {
      await _send(bound, batch, tally);
    } on SyncGatewayException catch (error) {
      if (error.timedOut) {
        final half = _budget ~/ 2;
        _budget = _ceiling = half < minPartBytes ? minPartBytes : half;
      }
      if (!await _refusesRows(bound, error, drain)) rethrow;
      await _isolate(bound, batch, error, tally, drain);
      return;
    }
    var bytes = 0;
    for (final queued in batch) {
      bytes += queued.bytes;
    }
    if (bytes * 2 >= _budget && _budget < _ceiling) {
      final twice = _budget * 2;
      _budget = twice > _ceiling ? _ceiling : twice;
    }
  }

  /// Whether [error] refuses rows of the batch — `invalidData`, or a denial
  /// the space's diagnosis pinned on a row's shape — rather than the whole
  /// drain. The diagnosis runs once per drain, on the first denial, and
  /// throws [_AccessLost] when the denial is the space's.
  Future<bool> _refusesRows(
    SyncBinding bound,
    SyncGatewayException error,
    _DrainState drain,
  ) async {
    switch (error.failure) {
      case SyncGatewayFailure.invalidData:
        return true;
      case SyncGatewayFailure.permissionDenied:
        if (!drain.diagnosed) {
          drain.diagnosed = true;
          await _diagnose(bound, error);
        }
        return true;
      case SyncGatewayFailure.offline:
      case SyncGatewayFailure.quotaExhausted:
      case SyncGatewayFailure.unknown:
        return false;
    }
  }

  /// A denied push is believed only after the space is read (record §3.5):
  /// gone or unreadable is `noAccess`, a newer schema is `appOutdated`;
  /// otherwise the rules refused a row, which the caller isolates.
  Future<void> _diagnose(SyncBinding bound, SyncGatewayException denied) async {
    final SyncSpaceInfo? info;
    try {
      info = await _e._gateway.readSpace(_e._spaceOf(bound));
    } on SyncGatewayException catch (error) {
      if (error.failure == SyncGatewayFailure.permissionDenied) {
        throw _AccessLost(SyncPause.noAccess, denied);
      }
      rethrow;
    }
    if (info == null) throw _AccessLost(SyncPause.noAccess, denied);
    if (info.schema > _e._schema) {
      throw _AccessLost(SyncPause.appOutdated, denied);
    }
  }

  /// Bisects [batch] — halves, then single rows — down to the refused rows,
  /// parks those and pushes the rest. A half refused for either reason is
  /// bisected again, whatever refused the whole: a batch holding one row of
  /// each kind must not leave the bisect as a bare denial.
  ///
  /// It halves in units ([_unitsOf]), never between a manifest and the
  /// chunks of the batch it names: once a unit is refused alone, its chunks
  /// go first, bisected among themselves, and the manifest only when all of
  /// them landed — a refused one parks it unsent, so the space never holds
  /// a manifest whose chunks it lacks (scalability record S6).
  Future<void> _isolate(
    SyncBinding bound,
    List<_Queued> batch,
    SyncGatewayException refusal,
    _RunTally tally,
    _DrainState drain,
  ) async {
    final units = _unitsOf(batch);
    if (units.length > 1) {
      final middle = units.length ~/ 2;
      for (final half in [units.sublist(0, middle), units.sublist(middle)]) {
        await _tryPush(bound, [for (final unit in half) ...unit], tally, drain);
      }
      return;
    }
    if (batch.length == 1) {
      await _park(batch.single.entry, refusal);
      // Only a fresh row's refusal is evidence the rules changed.
      if (refusal.failure == SyncGatewayFailure.permissionDenied &&
          !_isRetry(batch.single.entry) &&
          ++drain.refused > maxRefusedPerDrain) {
        // The space reads fine — the rules changed — so reading it again
        // proves nothing.
        throw _AccessLost(SyncPause.noAccess, refusal, recheckable: false);
      }
      return;
    }
    final chunks = [
      for (final queued in batch)
        if (queued.entry.syncedTable == _chunksTable) queued,
    ];
    await _tryPush(bound, chunks, tally, drain);
    final refused = {
      for (final chunk in chunks)
        if (parked[(_chunksTable, chunk.entry.rowKey)] == chunk.entry.hlc)
          chunk.entry.rowKey,
    };
    for (final queued in batch) {
      if (queued.entry.syncedTable == _chunksTable) continue;
      if (_namedChunks(queued).any(refused.contains)) {
        await _park(queued.entry, _refusedChunk);
      } else {
        await _tryPush(bound, [queued], tally, drain);
      }
    }
  }

  /// One push of [batch], and on a refusal of rows the bisect of it.
  Future<void> _tryPush(
    SyncBinding bound,
    List<_Queued> batch,
    _RunTally tally,
    _DrainState drain,
  ) async {
    try {
      await _send(bound, batch, tally);
    } on SyncGatewayException catch (error) {
      if (!await _refusesRows(bound, error, drain)) rethrow;
      await _isolate(bound, batch, error, tally, drain);
    }
  }

  /// [batch] in the units the bisect keeps whole, in batch order: each
  /// manifest with every chunk of the batch it names — two manifests naming
  /// one chunk share a unit — and every other row alone.
  static List<List<_Queued>> _unitsOf(List<_Queued> batch) {
    final units = <List<_Queued>?>[];
    final unitOfChunk = <String, int>{};
    for (final queued in batch) {
      final unit = <_Queued>[];
      if (queued.entry.syncedTable != _chunksTable) {
        final joined = {
          for (final hash in _namedChunks(queued)) ?unitOfChunk[hash],
        }.toList()..sort();
        for (final index in joined) {
          unit.addAll(units[index]!);
          units[index] = null;
        }
      }
      unit.add(queued);
      for (final member in unit) {
        if (member.entry.syncedTable == _chunksTable) {
          unitOfChunk[member.entry.rowKey] = units.length;
        }
      }
      units.add(unit);
    }
    return [for (final unit in units) ?unit];
  }

  /// The chunk hashes [queued] names: a live note's manifest, else none.
  static Iterable<String> _namedChunks(_Queued queued) {
    if (queued.entry.syncedTable != 'notes') return const [];
    final named = dataOf(queued.envelope)[NotesBinding.chunksKey];
    return named is List ? named.whereType<String>() : const [];
  }

  /// One push, then each entry retired at the stamp its row had when read:
  /// an entry an edit raised during the push stays queued.
  Future<void> _send(
    SyncBinding bound,
    List<_Queued> batch,
    _RunTally tally,
  ) async {
    await _e._checkHalt(bound);
    final db = _e._db;
    tally.pushAttempts++;
    await _e._gateway.pushBatch(
      _e._spaceOf(bound),
      [for (final queued in batch) queued.envelope],
      pushedBy: _e._deviceId,
      schema: _e._schema,
    );
    // Again after the call, not only before it: a restore that began while
    // the push was in flight is rewriting the very rows it acknowledges, and
    // retiring their entries would leave the re-queued ones unsent. The
    // batch is left unacknowledged and the run ends (A5 review R102).
    await _e._checkHalt(bound);
    await _e._reached(tally);
    await db.transaction(() async {
      for (final queued in batch) {
        await db.syncOutboxDao.ackThrough(
          queued.entry.syncedTable,
          queued.entry.rowKey,
          queued.ack,
        );
      }
    });
    await _release([
      for (final queued in batch)
        (queued.entry.syncedTable, queued.entry.rowKey),
    ]);
    tally.pushed += batch.length;
    for (final queued in batch) {
      tally.pushedBytes += queued.bytes;
    }
    await db.syncDao.setValue(
      SyncDao.keyLastPushAt,
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    _e._emit();
  }

  /// Logs by kind, as the pull's does (S3b review L16, A2 review R54): an
  /// `ArgumentError` out of a binding is more likely a bug than a row, an
  /// oversized or malformed row and a refusal are expected now and then, and
  /// anything else is this side's own fault. All of them park the entry, and
  /// store the park with the reason the Sync page shows: a refusal by the
  /// space's rules, or anything that kept the row from being encoded.
  Future<void> _park(SyncOutboxRow entry, Object reason) async {
    final row = '${entry.syncedTable}/${entry.rowKey}';
    if (reason is ArgumentError) {
      _warn('parked $row on an ArgumentError, probably a bug: $reason');
    } else if (reason is String ||
        reason is SyncGatewayException ||
        _isEnvelopeFault(reason)) {
      debugPrint('[SyncEngine] parked $row: $reason');
    } else {
      _warn('parked $row on ${reason.runtimeType}: $reason');
    }
    final key = (entry.syncedTable, entry.rowKey);
    if (!parked.containsKey(key)) _e._parks++;
    parked[key] = entry.hlc;
    final held = reason is SyncGatewayException
        ? SyncHeldReason.refused
        : SyncHeldReason.unencodable;
    _reasons[key] = held;
    _stored.remove(key);
    _stored[key] = entry.hlc;
    await _e._db.syncDao.setValue(
      SyncDao.keyPushParked(entry.syncedTable, entry.rowKey),
      _parkValue(_nextOrder(), entry.hlc, held),
    );
  }
}
