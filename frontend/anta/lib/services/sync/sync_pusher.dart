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

  /// The oldest [maxBatch] entries [eligible] lets through, reading further
  /// down the queue while the entries it holds back fill the window.
  Future<List<SyncOutboxRow>> _nextEntries(
    bool Function(SyncOutboxRow entry) eligible,
    int maxBatch,
  ) async {
    final outbox = _e._db.syncOutboxDao;
    for (var limit = maxBatch; ; limit *= 2) {
      final queued = await outbox.pending(limit: limit);
      final entries = queued.where(eligible).take(maxBatch).toList();
      if (entries.length == maxBatch || queued.length < limit) return entries;
    }
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
    final batch = <_Queued>[];
    for (final MapEntry(key: table, value: group) in byTable.entries) {
      final binding = _e._bindingFor(table);
      final List<Object> rows;
      try {
        if (binding == null) throw ArgumentError.value(table, 'table');
        rows = await binding.loadByKeys(db, [for (final e in group) e.rowKey]);
      } on Object catch (error) {
        if (!_isEnvelopeFault(error)) rethrow;
        for (final entry in group) {
          _park(entry, error);
        }
        continue;
      }
      final byKey = {for (final row in rows) binding.rowKeyOf(row): row};
      for (final entry in group) {
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
        batch.add(_Queued(entry, envelope, bytes));
      }
    }
    return batch;
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

  void _park(SyncOutboxRow entry, Object reason) {
    debugPrint(
      '[SyncEngine] parked ${entry.syncedTable}/${entry.rowKey}: $reason',
    );
    final key = (entry.syncedTable, entry.rowKey);
    if (!parked.containsKey(key)) _e._parks++;
    parked[key] = entry.hlc;
  }
}
