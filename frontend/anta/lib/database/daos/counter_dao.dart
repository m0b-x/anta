import 'package:drift/drift.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../crdt/pn_counter.dart';
import '../database.dart';
import '../tables/counters_table.dart';
import '../tables/counter_values_table.dart';

part 'counter_dao.g.dart';

/// All CRDT stamping for `counters` and `counter_values` lives here (**v43**),
/// the [CalendarEventDao] rule: a `CrdtWrite` stamp, the row queued in the
/// same transaction, and `version + 1` on every write, tombstones instead of
/// deletes. Nothing above this class — `CounterService`, the bloc, backup —
/// sees a CRDT field, a tombstone or the outbox.
@DriftAccessor(tables: [Counters, CounterValues])
class CounterDao extends DatabaseAccessor<AppDatabase> with _$CounterDaoMixin {
  CounterDao(super.db);

  /// The live-row predicate every read restates, spelled exactly as the
  /// partial indexes' `WHERE`. A literal rather than `isDeleted.equals(false)`,
  /// whose bound parameter the SQLite shipping to Android does not prove
  /// implies the index's predicate.
  static const _live = CustomExpression<bool>('is_deleted = 0');

  // ---------------------------------------------------------------------------
  // Counter definitions
  // ---------------------------------------------------------------------------

  Future<List<CounterRow>> getAllCounters() {
    return (select(counters)
          ..where((c) => _live)
          ..orderBy([
            (c) => OrderingTerm.desc(c.isPinned),
            (c) => OrderingTerm.asc(c.position),
          ]))
        .get();
  }

  Future<void> insertCounter(CountersCompanion entry) {
    return transaction(() => _insertCounter(entry, db.newStamp()));
  }

  /// Creates a counter together with its global value row, both under one
  /// HLC: adding a counter is one user act, and merges as one.
  Future<void> insertCounterWithValue(
    CountersCompanion entry,
    int globalValue,
  ) {
    return transaction(() async {
      final stamp = db.newStamp();
      await _insertCounter(entry, stamp);
      await _writeValue(entry.id.value, '', stamp, absolute: globalValue);
    });
  }

  Future<void> _insertCounter(CountersCompanion entry, CrdtStamp stamp) async {
    await into(counters).insert(
      entry.copyWith(
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: const Value(1),
      ),
    );
    await db.enqueue(counters, entry.id.value, stamp.hlc);
  }

  /// Read-then-write so the version can be bumped; a missing or tombstoned
  /// counter is left alone, as the plain UPDATE this replaced left a missing
  /// one. An edit that changes nothing writes nothing, so a save of an
  /// unchanged counter does not read as a change once devices merge.
  /// `created_at` is left out of the comparison: the model's copy carries
  /// milliseconds the column never stored.
  Future<void> updateCounter(CountersCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await (select(
        counters,
      )..where((c) => c.id.equals(id) & _live)).getSingleOrNull();
      if (existing == null) return;
      final merged = existing.copyWithCompanion(entry);
      if (merged.copyWith(createdAt: existing.createdAt) == existing) return;
      final stamp = await db.stampLocal(counters, id);
      await (update(counters)..where((c) => c.id.equals(id))).write(
        entry.copyWith(
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Tombstones a counter **and every value it holds** with one shared HLC,
  /// the [EventAbsenceDao.tombstoneForEvent] shape: one user act, merged as
  /// one, and a value row cannot outlive its counter on another device.
  /// `version + 1` in SQL, so an unbounded value count costs two statements,
  /// and queueing what they tombstoned two more.
  /// Already-tombstoned rows are skipped, so a repeat cannot churn versions.
  Future<void> deleteCounter(String id) {
    final now = DateTime.now();
    return transaction(() async {
      final stamp = db.newStamp();
      final tombstoned = await customUpdate(
        'UPDATE counters SET is_deleted = 1, deleted_at = ?, '
        'hlc_timestamp = ?, device_id = ?, version = version + 1 '
        'WHERE id = ? AND is_deleted = 0',
        variables: [
          Variable<DateTime>(now),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          Variable<String>(id),
        ],
        updates: {counters},
      );
      final values = await customWriteReturning(
        'UPDATE counter_values SET is_deleted = 1, deleted_at = ?, '
        'hlc_timestamp = ?, device_id = ?, version = version + 1 '
        'WHERE counter_id = ? AND is_deleted = 0 RETURNING note_id',
        variables: [
          Variable<DateTime>(now),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          Variable<String>(id),
        ],
        updates: {counterValues},
        updateKind: UpdateKind.update,
      );
      if (tombstoned > 0) {
        await db.enqueue(counters, id, stamp.hlc, op: OutboxOp.tombstone);
      }
      await db.enqueueMany(
        counterValues,
        [
          for (final row in values)
            counterValueRowKey(id, row.read<String>('note_id')),
        ],
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Counter values
  // ---------------------------------------------------------------------------

  /// Writes [value] as an absolute number — a restore, a counter's first
  /// value — through [applyCount]'s rules. [noteId] should be `''` for global
  /// counters.
  Future<void> upsertValue(
    String counterId,
    String noteId,
    int value, {
    String? ownerId,
  }) {
    return transaction(
      () => _writeValue(
        counterId,
        noteId,
        db.newStamp(),
        absolute: value,
        ownerId: ownerId,
      ),
    );
  }

  /// One flushed change of a value: [absolute] when it was set or reset,
  /// then [delta], the taps since, applied as taps on this database's
  /// PN-counter shard ([SyncDao.replicaId]) so another device's taps merged
  /// meanwhile stay counted. [startValue] is where a value with no row
  /// starts. Returns the value stored, or null when the write was refused.
  Future<int?> applyCount(
    String counterId,
    String noteId, {
    int? absolute,
    int delta = 0,
    required int startValue,
  }) {
    return transaction(
      () => _writeValue(
        counterId,
        noteId,
        db.newStamp(),
        absolute: absolute,
        delta: delta,
        startValue: startValue,
      ),
    );
  }

  /// Read-then-write rather than `insertOnConflictUpdate`, which cannot compute
  /// `version + 1`. A write over a tombstone **resurrects** the row, and resets
  /// its pin and position: a value deleted and then counted again used to be a
  /// fresh row, and must still read as one. A resurrecting tap starts from the
  /// counter's start value under an epoch of the tombstone's own stamp, so
  /// the taps counted under the epoch before the delete never come back in a
  /// merge; an absolute write starts an epoch of its own stamp.
  ///
  /// Writes nothing when there is nothing to count or an absolute write lands
  /// on the number the live row holds, so a flush or a reset that changes
  /// nothing stamps no HLC; nothing under a tombstoned counter, and nothing
  /// for a per-note value whose note is a tombstone — a flush still pending
  /// when either was deleted cannot bring a value back.
  ///
  /// [ownerId] lands only when the row is created or resurrected: a restore
  /// carries the archived ownership (D16), and a count never changes whose
  /// row it is.
  Future<int?> _writeValue(
    String counterId,
    String noteId,
    CrdtStamp stamp, {
    int? absolute,
    int delta = 0,
    int startValue = 0,
    String? ownerId,
  }) async {
    final existing = await _valueRow(counterId, noteId);
    final live = existing != null && !existing.isDeleted;
    if (delta == 0 &&
        (absolute == null || (live && existing.value == absolute))) {
      return live ? existing.value : startValue;
    }
    if (noteId.isNotEmpty && await _noteIsTombstoned(noteId)) return null;
    final parent = await (select(
      counters,
    )..where((c) => c.id.equals(counterId))).getSingleOrNull();
    if (parent != null && parent.isDeleted) return null;
    var state = live
        ? _stateOf(existing)
        : PnCounterState(
            epochHlc: existing?.hlcTimestamp ?? PnCounterState.genesis,
            epochValue: startValue,
          );
    if (absolute != null) {
      state = PnCounterState(epochHlc: stamp.hlc, epochValue: absolute);
    }
    if (delta != 0) state = state.tap(await db.syncDao.replicaId(), delta);
    await db.enqueue(
      counterValues,
      counterValueRowKey(counterId, noteId),
      stamp.hlc,
    );
    if (existing == null) {
      await into(counterValues).insert(
        CounterValuesCompanion(
          counterId: Value(counterId),
          noteId: Value(noteId),
          value: Value(state.value),
          ownerId: Value(ownerId),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
          epochHlc: Value(state.epochHlc),
          epochValue: Value(state.epochValue),
          shards: Value(state.shardsColumn),
        ),
      );
      return state.value;
    }
    await (update(counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .write(
          CounterValuesCompanion(
            value: Value(state.value),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(existing.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
            position: existing.isDeleted
                ? const Value(0)
                : const Value.absent(),
            isPinned: existing.isDeleted
                ? const Value(false)
                : const Value.absent(),
            ownerId: existing.isDeleted ? Value(ownerId) : const Value.absent(),
            epochHlc: Value(state.epochHlc),
            epochValue: Value(state.epochValue),
            shards: Value(state.shardsColumn),
          ),
        );
    return state.value;
  }

  /// One primary-key read of the note a per-note value belongs to. A missing
  /// note is not refused: the editor files a value under a note it is still
  /// creating.
  Future<bool> _noteIsTombstoned(String noteId) async {
    final row = await customSelect(
      'SELECT is_deleted FROM notes WHERE id = ?',
      variables: [Variable<String>(noteId)],
      readsFrom: {db.notes},
    ).getSingleOrNull();
    return row != null && row.read<bool>('is_deleted');
  }

  static PnCounterState _stateOf(CounterValueRow row) => PnCounterState(
    epochHlc: row.epochHlc,
    epochValue: row.epochValue,
    shards: PnCounterState.shardsOfColumn(row.shards),
  );

  /// Tombstones the live per-note values of the notes a local delete has
  /// just tombstoned under [stamp], in the delete's own transaction and
  /// under its stamp and [deletedAt]: one user act, merged as one, and a
  /// value can no longer outlive its note. [noteId] for a single note;
  /// without it the notes are found by the stamp, which only this delete
  /// minted — one statement and one bound stamp however many notes went, so
  /// a folder of 33,000 notes stays under SQLite's variable limit. The remote
  /// merge never cascades: the deleting device's drain sends these as their
  /// own rows.
  Future<void> tombstoneValuesOfDeletedNotes(
    CrdtStamp stamp,
    DateTime deletedAt, {
    String? noteId,
  }) async {
    final rows = await customWriteReturning(
      'UPDATE counter_values SET is_deleted = 1, deleted_at = ?, '
      'hlc_timestamp = ?, device_id = ?, version = version + 1 '
      'WHERE is_deleted = 0 AND note_id '
      '${noteId != null ? '= ?' : 'IN (SELECT id FROM notes WHERE hlc_timestamp = ? AND is_deleted = 1)'} '
      'RETURNING counter_id, note_id',
      variables: [
        Variable<DateTime>(deletedAt),
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        Variable<String>(noteId ?? stamp.hlc),
      ],
      updates: {counterValues},
      updateKind: UpdateKind.update,
    );
    await _enqueueTombstones(rows, stamp.hlc);
  }

  /// Tombstones the live per-note values a note's tombstone here outranks and
  /// returns their row keys: the deletes a sync pull merged, which never
  /// cascade, and what an earlier build's deletes left behind.
  ///
  /// Only a value stamped below its note's tombstone goes, and it goes under
  /// the note's own stamp, device and `deleted_at` — never a fresh stamp: a
  /// value another device wrote after the delete, on a note its newer edit
  /// brings back, must keep outranking the sweep here and on every device it
  /// reaches. The tombstone it writes is the one the deleting device's own
  /// cascade wrote, so the two meet as the same write. A note that is missing
  /// rather than tombstoned is left alone: on a bound database its row may
  /// simply not have been pulled yet. Never a hard delete: the tombstone is
  /// what tells the other devices.
  Future<List<String>> sweepOrphanValues() {
    return transaction(() async {
      final rows = await customWriteReturning(
        'UPDATE counter_values SET is_deleted = 1, version = version + 1, '
        '(hlc_timestamp, device_id, deleted_at) = '
        '(SELECT n.hlc_timestamp, n.device_id, n.deleted_at FROM notes n '
        'WHERE n.id = counter_values.note_id) '
        "WHERE is_deleted = 0 AND note_id != '' AND EXISTS "
        '(SELECT 1 FROM notes n WHERE n.id = counter_values.note_id '
        'AND n.is_deleted = 1 '
        'AND n.hlc_timestamp > counter_values.hlc_timestamp) '
        'RETURNING counter_id, note_id, hlc_timestamp',
        updates: {counterValues},
        updateKind: UpdateKind.update,
      );
      final byStamp = <String, List<QueryRow>>{};
      for (final row in rows) {
        byStamp
            .putIfAbsent(row.read<String>('hlc_timestamp'), () => [])
            .add(row);
      }
      for (final MapEntry(key: hlc, value: swept) in byStamp.entries) {
        await _enqueueTombstones(swept, hlc);
      }
      return [
        for (final row in rows)
          counterValueRowKey(
            row.read<String>('counter_id'),
            row.read<String>('note_id'),
          ),
      ];
    });
  }

  Future<void> _enqueueTombstones(List<QueryRow> rows, String hlc) {
    return db.enqueueMany(
      counterValues,
      [
        for (final row in rows)
          counterValueRowKey(
            row.read<String>('counter_id'),
            row.read<String>('note_id'),
          ),
      ],
      hlc,
      op: OutboxOp.tombstone,
    );
  }

  /// Gets a single counter value. Returns null if not set.
  Future<int?> getValue(String counterId, String noteId) async {
    final row =
        await (select(counterValues)..where(
              (v) =>
                  v.counterId.equals(counterId) &
                  v.noteId.equals(noteId) &
                  _live,
            ))
            .getSingleOrNull();
    return row?.value;
  }

  /// Gets all values for a given note (or global values when [noteId] is `''`).
  Future<Map<String, int>> getValuesForNote(String noteId) async {
    final rows = await (select(
      counterValues,
    )..where((v) => v.noteId.equals(noteId) & _live)).get();
    return {for (final r in rows) r.counterId: r.value};
  }

  /// Tombstones the value row for a specific counter + note pair.
  Future<void> deleteValue(String counterId, String noteId) {
    return transaction(() async {
      final stamp = db.newStamp();
      final tombstoned = await customUpdate(
        'UPDATE counter_values SET is_deleted = 1, deleted_at = ?, '
        'hlc_timestamp = ?, device_id = ?, version = version + 1 '
        'WHERE counter_id = ? AND note_id = ? AND is_deleted = 0',
        variables: [
          Variable<DateTime>(DateTime.now()),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          Variable<String>(counterId),
          Variable<String>(noteId),
        ],
        updates: {counterValues},
      );
      if (tombstoned > 0) {
        await db.enqueue(
          counterValues,
          counterValueRowKey(counterId, noteId),
          stamp.hlc,
          op: OutboxOp.tombstone,
        );
      }
    });
  }

  /// Bulk-updates positions for reordering. Expects a map of id → position.
  ///
  /// One shared HLC for the drag, `version + 1` in SQL, and only rows whose
  /// position actually moves are written — re-stamping the rest would mark
  /// every counter changed on every drag.
  Future<void> updatePositions(Map<String, int> positions) async {
    if (positions.isEmpty) return;
    await transaction(() => _writePositions(positions, db.newStamp()));
  }

  /// Writes and queues only the rows that move.
  Future<void> _writePositions(
    Map<String, int> positions,
    CrdtStamp stamp,
  ) async {
    final moved = <String>[];
    for (final entry in positions.entries) {
      final changed = await customUpdate(
        'UPDATE counters SET position = ?, hlc_timestamp = ?, '
        'device_id = ?, version = version + 1 '
        'WHERE id = ? AND is_deleted = 0 AND position != ?',
        variables: [
          Variable<int>(entry.value),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          Variable<String>(entry.key),
          Variable<int>(entry.value),
        ],
        updates: {counters},
      );
      if (changed > 0) moved.add(entry.key);
    }
    await db.enqueueMany(counters, moved, stamp.hlc);
  }

  /// Returns all live counter-value rows (for backup export), less the
  /// per-note values of a tombstoned note, which a sweep has not reached yet:
  /// the archive would carry a count for a note it does not.
  Future<List<CounterValueRow>> getAllValues() {
    return (select(counterValues)..where(
          (v) =>
              _live &
              const CustomExpression<bool>(
                'note_id NOT IN (SELECT id FROM notes WHERE is_deleted = 1)',
              ),
        ))
        .get();
  }

  Future<Map<String, int>> getValuesForCounter(String counterId) async {
    final rows =
        await (select(counterValues)..where(
              (v) =>
                  v.counterId.equals(counterId) &
                  v.noteId.isNotValue('') &
                  _live,
            ))
            .get();
    return {for (final r in rows) r.noteId: r.value};
  }

  Future<List<CounterValueRow>> getValuesForCounterOrdered(
    String counterId,
  ) async {
    return (select(counterValues)
          ..where(
            (v) =>
                v.counterId.equals(counterId) & v.noteId.isNotValue('') & _live,
          )
          ..orderBy([
            (v) => OrderingTerm.desc(v.isPinned),
            (v) => OrderingTerm.asc(v.position),
          ]))
        .get();
  }

  // ---------------------------------------------------------------------------
  // Counter pin
  // ---------------------------------------------------------------------------

  /// Pins or unpins a counter and moves the list to match, as one act: one
  /// HLC for every row the toggle touches, and the toggled counter's flag and
  /// position land in one write, so its version moves once. [positions] is
  /// the whole new order; rows already in place are not written.
  Future<void> setCounterPinned(
    String id,
    bool pinned, {
    Map<String, int> positions = const {},
  }) {
    return transaction(() async {
      final stamp = db.newStamp();
      final toggled = await customUpdate(
        'UPDATE counters SET is_pinned = ?, position = COALESCE(?, position), '
        'hlc_timestamp = ?, device_id = ?, version = version + 1 '
        'WHERE id = ? AND is_deleted = 0 '
        'AND (is_pinned != ? OR position != COALESCE(?, position))',
        variables: [
          Variable<bool>(pinned),
          Variable<int>(positions[id]),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          Variable<String>(id),
          Variable<bool>(pinned),
          Variable<int>(positions[id]),
        ],
        updates: {counters},
      );
      if (toggled > 0) await db.enqueue(counters, id, stamp.hlc);
      await _writePositions({...positions}..remove(id), stamp);
    });
  }

  // ---------------------------------------------------------------------------
  // Counter-value pin + reorder
  // ---------------------------------------------------------------------------

  Future<void> setNoteValuePinned(
    String counterId,
    String noteId,
    bool pinned,
  ) {
    return transaction(() async {
      final stamp = db.newStamp();
      // A pin that is already set writes nothing.
      final changed = await customUpdate(
        'UPDATE counter_values SET is_pinned = ?, hlc_timestamp = ?, '
        'device_id = ?, version = version + 1 '
        'WHERE counter_id = ? AND note_id = ? AND is_deleted = 0 '
        'AND is_pinned != ?',
        variables: [
          Variable<bool>(pinned),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          Variable<String>(counterId),
          Variable<String>(noteId),
          Variable<bool>(pinned),
        ],
        updates: {counterValues},
      );
      if (changed > 0) {
        await db.enqueue(
          counterValues,
          counterValueRowKey(counterId, noteId),
          stamp.hlc,
        );
      }
    });
  }

  /// The [updatePositions] shape for one counter's per-note values.
  Future<void> updateNoteValuePositions(
    String counterId,
    Map<String, int> positions,
  ) async {
    if (positions.isEmpty) return;
    await transaction(() async {
      final stamp = db.newStamp();
      final moved = <String>[];
      for (final entry in positions.entries) {
        final changed = await customUpdate(
          'UPDATE counter_values SET position = ?, hlc_timestamp = ?, '
          'device_id = ?, version = version + 1 '
          'WHERE counter_id = ? AND note_id = ? AND is_deleted = 0 '
          'AND position != ?',
          variables: [
            Variable<int>(entry.value),
            Variable<String>(stamp.hlc),
            Variable<String>(stamp.deviceId),
            Variable<String>(counterId),
            Variable<String>(entry.key),
            Variable<int>(entry.value),
          ],
          updates: {counterValues},
        );
        if (changed > 0) moved.add(counterValueRowKey(counterId, entry.key));
      }
      await db.enqueueMany(counterValues, moved, stamp.hlc);
    });
  }

  // ---------------------------------------------------------------------------
  // Remote merges
  // ---------------------------------------------------------------------------

  /// The counters under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CounterRow>> getCountersByIdsIncludingDeleted(List<String> ids) {
    return CrdtMerge.loadInChunks(
      ids,
      (chunk) => (select(counters)..where((c) => c.id.isIn(chunk))).get(),
    );
  }

  /// The value rows under [keys], tombstones included. Narrowed by counter id
  /// and note id on the primary key's columns — a global counter otherwise
  /// brings every note's value along — then matched through
  /// [counterValueRowKey], the outbox's own key, so a key is never rebuilt
  /// another way.
  Future<List<CounterValueRow>> getValuesByKeysIncludingDeleted(
    List<({String counterId, String noteId})> keys,
  ) {
    return CrdtMerge.loadInChunks(keys, (chunk) async {
      final wanted = {
        for (final k in chunk) counterValueRowKey(k.counterId, k.noteId),
      };
      final rows =
          await (select(counterValues)..where(
                (v) =>
                    v.counterId.isIn({for (final k in chunk) k.counterId}) &
                    v.noteId.isIn({for (final k in chunk) k.noteId}),
              ))
              .get();
      return [
        for (final row in rows)
          if (wanted.contains(counterValueRowKey(row.counterId, row.noteId)))
            row,
      ];
    });
  }

  /// Merges one remote counter on the contract of [CrdtMerge.mergeRemoteRow]. A
  /// tombstone carries no data, so over a local row it writes the stamps, the
  /// deletion and the owner and keeps the rest; its values arrive as their
  /// own rows, never by cascade.
  Future<MergeOutcome> mergeRemoteCounter(CounterRow remote, {String? floor}) {
    return transaction(() async {
      final local = await (select(
        counters,
      )..where((c) => c.id.equals(remote.id))).getSingleOrNull();
      return CrdtMerge.mergeRemoteRow(
        db,
        table: counters,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(counters).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              counters,
            )..where((c) => c.id.equals(remote.id))).write(
              CountersCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            await update(counters).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// Merges one remote value row, keyed `counterId|noteId` with the global
  /// value's `noteId == ''`, on the contract of [CrdtMerge.mergeRemoteRow].
  ///
  /// Stored as received even under a counter tombstoned here: the parent's
  /// tombstone is its own row with its own stamp, and `CounterService` shows
  /// values only under the live counters it lists.
  ///
  /// Two live rows of different stamps join as PN-counters
  /// ([_joinRemoteValue]) unless the bind floor yields, where the space's
  /// state wins whole; a tombstone on either side still goes by the stamps,
  /// and so does a remote that carries no PN-counter state ([joins] false —
  /// an older build's envelope), the pre-S20 rule.
  Future<MergeOutcome> mergeRemoteCounterValue(
    CounterValueRow remote, {
    String? floor,
    bool joins = true,
  }) {
    return transaction(() async {
      final local = await _valueRow(remote.counterId, remote.noteId);
      return CrdtMerge.mergeRemoteRow(
        db,
        table: counterValues,
        rowKey: counterValueRowKey(remote.counterId, remote.noteId),
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        join: joins && local != null && !local.isDeleted && !remote.isDeleted
            ? () => _joinRemoteValue(local, remote)
            : null,
        insert: () => into(counterValues).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(counterValues)..where(
                  (v) =>
                      v.counterId.equals(remote.counterId) &
                      v.noteId.equals(remote.noteId),
                ))
                .write(
                  CounterValuesCompanion(
                    hlcTimestamp: Value(remote.hlcTimestamp),
                    deviceId: Value(remote.deviceId),
                    version: Value(remote.version),
                    isDeleted: const Value(true),
                    deletedAt: Value(remote.deletedAt),
                    ownerId: Value(remote.ownerId),
                  ),
                );
          } else {
            await update(counterValues).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// The join of two live value rows (D8 A): the counts by
  /// [PnCounterState.join], the pin and position — which are not counts —
  /// from the row of the newer stamp, as the stamp order would have it.
  ///
  /// - The local row holds the join: nothing is written when the remote holds
  ///   it too — an echo, such as the same join stored by both devices under
  ///   their own stamps, which would otherwise bounce between them for ever —
  ///   and the local row is re-queued when the remote holds less, which
  ///   repairs a push that landed over it.
  /// - The remote holds it: adopted under its stamp, with no requeue.
  /// - Neither holds it: stored under a fresh local stamp and queued, so the
  ///   other device receives the join. The clock is raised toward the
  ///   remote's stamp first (the folder repair's `advanceClockInTransaction`),
  ///   held to the drift limit, so a remote stamped past it can still sort
  ///   above the join; convergence does not depend on it — the join is of
  ///   states, never of stamps.
  ///
  /// The owner is left out of the comparison: a row written after the bind is
  /// unowned where it was written and owned wherever it was merged.
  Future<MergeJoin> _joinRemoteValue(
    CounterValueRow local,
    CounterValueRow remote,
  ) async {
    final joined = _stateOf(local).join(_stateOf(remote));
    final newer = remote.hlcTimestamp.compareTo(local.hlcTimestamp) > 0
        ? remote
        : local;
    bool holdsJoin(CounterValueRow row) =>
        _stateOf(row) == joined &&
        row.isPinned == newer.isPinned &&
        row.position == newer.position;
    if (holdsJoin(local)) {
      return holdsJoin(remote) ? MergeJoin.echo : MergeJoin.local;
    }
    if (holdsJoin(remote)) return MergeJoin.remote;
    CrdtMerge.advanceClockInTransaction(db, remote.hlcTimestamp);
    final stamp = db.newStamp();
    await db.enqueue(
      counterValues,
      counterValueRowKey(local.counterId, local.noteId),
      stamp.hlc,
    );
    await update(counterValues).replace(
      newer.copyWith(
        value: joined.value,
        epochHlc: joined.epochHlc,
        epochValue: joined.epochValue,
        shards: joined.shardsColumn,
        hlcTimestamp: stamp.hlc,
        deviceId: stamp.deviceId,
        version:
            (local.version > remote.version ? local.version : remote.version) +
            1,
        ownerId: Value(local.ownerId ?? remote.ownerId),
      ),
    );
    return MergeJoin.stored;
  }

  /// Deletes every counter and counter-value row (used before import).
  ///
  /// Stays **hard**, tombstones included: the import re-inserts the archived
  /// ids straight after, and a restore is never a merge.
  Future<void> deleteAll() async {
    await delete(counterValues).go();
    await delete(counters).go();
  }

  /// The value row whatever its state, tombstones included — the write paths
  /// need to see a tombstone to resurrect it.
  Future<CounterValueRow?> _valueRow(String counterId, String noteId) {
    return (select(counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .getSingleOrNull();
  }
}
