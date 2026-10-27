part of 'sync_engine.dart';

/// The push side of a run.
class _Pusher {
  final SyncEngine _e;

  /// The outbox entries set aside this session, by table and key, with the
  /// stamp each was parked at: one bad row must not stop every other row,
  /// and an edit since — a shortened note — raises the stamp, so the row is
  /// tried again at once instead of next launch (record §3.5).
  final Map<(String, String), String> parked = {};

  _Pusher(this._e);

  /// About 900 KB of JSON: under Firestore's 1 MiB document with room for
  /// the envelope's own fields, so an oversized row is parked here rather
  /// than refused for its whole batch.
  static const int maxDocumentBytes = 900000;

  /// About 8 MiB of row data per push, under Firestore's 10 MiB request: a
  /// batch near the cap on a slow uplink would time out and be retried whole
  /// forever (S5 review M5).
  static const int maxBatchBytes = 8 * 1024 * 1024;

  /// More rows than this refused by the rules in one drain means the rules
  /// changed, not the rows (record §3.5).
  static const int maxRefusedPerDrain = 20;

  /// Pushes the outbox in batches, oldest change first, until it is empty or
  /// a call fails. The entries of [skipTables] stay queued for a later run.
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
    // A key whose pull envelope parked this session is held back too: this
    // device lacks the space's version of that row, which may be the newer
    // one (S3d review H2).
    bool eligible(SyncOutboxRow entry) {
      final key = (entry.syncedTable, entry.rowKey);
      return !skipTables.contains(entry.syncedTable) &&
          parked[key] != entry.hlc &&
          pushed[key] != entry.hlc &&
          !_e._puller.parked.contains(key);
    }

    while (true) {
      await _e._checkHalt(bound);
      final entries = await _nextEntries(eligible, maxBatch);
      if (entries.isEmpty) break;
      _e._setActivity(SyncActivity.pushing);
      final batch = await _prepare(entries, bound.accountUid);
      _e._emit();
      if (batch.isEmpty) continue;
      for (final queued in batch) {
        pushed[(queued.entry.syncedTable, queued.entry.rowKey)] =
            queued.entry.hlc;
      }
      for (final part in _byBytes(batch)) {
        await _push(bound, part, tally, drain);
      }
    }
  }

  /// [batch] cut, in order, into runs of at most [maxBatchBytes] of row
  /// data; a row is never left out, so a run holds at least one.
  static List<List<_Queued>> _byBytes(List<_Queued> batch) {
    final parts = <List<_Queued>>[];
    var part = <_Queued>[];
    var bytes = 0;
    for (final queued in batch) {
      if (part.isNotEmpty && bytes + queued.bytes > maxBatchBytes) {
        parts.add(part);
        part = [];
        bytes = 0;
      }
      part.add(queued);
      bytes += queued.bytes;
    }
    if (part.isNotEmpty) parts.add(part);
    return parts;
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

  /// The batch for [entries]: each row read as it stands now, a tombstone
  /// included. A row gone since it was queued (an import wipe) retires its
  /// entry; one that cannot be encoded or would exceed [maxDocumentBytes]
  /// is parked before the push.
  Future<List<_Queued>> _prepare(
    List<SyncOutboxRow> entries,
    String boundUid,
  ) async {
    final db = _e._db;
    final byTable = <String, List<SyncOutboxRow>>{};
    for (final entry in entries) {
      byTable.putIfAbsent(entry.syncedTable, () => []).add(entry);
    }
    final prepared = <(String, String), _Queued>{};
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
          _park(entry, fault);
        }
        throw fault;
      }
      final faulted = <String>{};
      final rows = await _loadGroup(binding, group, faulted);
      final byKey = {for (final row in rows) binding.rowKeyOf(row): row};
      for (final entry in group) {
        if (faulted.contains(entry.rowKey)) continue;
        final row = byKey[entry.rowKey];
        if (row == null) {
          await db.syncOutboxDao.ackThrough(table, entry.rowKey, entry.hlc);
          continue;
        }
        final SyncEnvelope envelope;
        try {
          envelope = await binding.encode(db, row, boundUid: boundUid);
        } on Object catch (error) {
          _park(entry, error);
          continue;
        }
        final data = envelope.data;
        final bytes = data == null ? 0 : utf8.encode(jsonEncode(data)).length;
        if (bytes > maxDocumentBytes) {
          _park(entry, 'over $maxDocumentBytes bytes');
          continue;
        }
        prepared[(table, entry.rowKey)] = _Queued(entry, envelope, bytes);
      }
    }
    // Back in the queue's `(hlc, table, rowKey)` order: the rows are read one
    // table at a time, but a push that stops part-way must have sent a prefix
    // of history rather than whole tables (A2 review R50).
    return [
      for (final entry in entries) ?prepared[(entry.syncedTable, entry.rowKey)],
    ];
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
        _park(group.single, error);
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
  Future<void> _push(
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
  Future<void> _diagnose(
    SyncBinding bound,
    SyncGatewayException denied,
  ) async {
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
  Future<void> _isolate(
    SyncBinding bound,
    List<_Queued> batch,
    SyncGatewayException refusal,
    _RunTally tally,
    _DrainState drain,
  ) async {
    if (batch.length == 1) {
      _park(batch.single.entry, refusal);
      if (refusal.failure == SyncGatewayFailure.permissionDenied &&
          ++drain.refused > maxRefusedPerDrain) {
        // The space reads fine — the rules changed — so reading it again
        // proves nothing.
        throw _AccessLost(SyncPause.noAccess, refusal, recheckable: false);
      }
      return;
    }
    final middle = batch.length ~/ 2;
    for (final half in [batch.sublist(0, middle), batch.sublist(middle)]) {
      try {
        await _send(bound, half, tally);
      } on SyncGatewayException catch (error) {
        if (!await _refusesRows(bound, error, drain)) rethrow;
        await _isolate(bound, half, error, tally, drain);
      }
    }
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
          queued.envelope.hlc,
        );
      }
    });
    for (final queued in batch) {
      parked.remove((queued.entry.syncedTable, queued.entry.rowKey));
    }
    tally.pushed += batch.length;
    await db.syncDao.setValue(
      SyncDao.keyLastPushAt,
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    _e._emit();
  }

  /// Logs by kind, as the pull's does (S3b review L16, A2 review R54): an
  /// `ArgumentError` out of a binding is more likely a bug than a row, an
  /// oversized or malformed row and a refusal are expected now and then, and
  /// anything else is this side's own fault. All of them park the entry.
  void _park(SyncOutboxRow entry, Object reason) {
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
  }
}
