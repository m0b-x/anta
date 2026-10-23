import 'package:drift/drift.dart';
import '../crdt/crdt_write.dart';
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
      await _upsertValue(entry.id.value, '', globalValue, stamp);
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

  /// Upserts a single value row. [noteId] should be `''` for global counters.
  ///
  /// Read-then-write rather than `insertOnConflictUpdate`, which cannot compute
  /// `version + 1`. A write over a tombstone **resurrects** the row, and resets
  /// its pin and position: a value deleted and then counted again used to be a
  /// fresh row, and must still read as one.
  ///
  /// Writes nothing when the live row already holds [value], so a flush or a
  /// reset that lands on the stored number stamps no HLC; and nothing under a
  /// tombstoned counter, so a flush still pending when the counter was deleted
  /// cannot bring its values back.
  ///
  /// [ownerId] lands only when the row is created or resurrected: a restore
  /// carries the archived ownership (D16), and a count never changes whose
  /// row it is.
  Future<void> upsertValue(
    String counterId,
    String noteId,
    int value, {
    String? ownerId,
  }) {
    return transaction(
      () => _upsertValue(
        counterId,
        noteId,
        value,
        db.newStamp(),
        ownerId: ownerId,
      ),
    );
  }

  Future<void> _upsertValue(
    String counterId,
    String noteId,
    int value,
    CrdtStamp stamp, {
    String? ownerId,
  }) async {
    final existing = await _valueRow(counterId, noteId);
    if (existing != null && !existing.isDeleted && existing.value == value) {
      return;
    }
    final parent = await (select(
      counters,
    )..where((c) => c.id.equals(counterId))).getSingleOrNull();
    if (parent != null && parent.isDeleted) return;
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
          value: Value(value),
          ownerId: Value(ownerId),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
        ),
      );
      return;
    }
    await (update(counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .write(
          CounterValuesCompanion(
            value: Value(value),
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
          ),
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

  /// Returns all live counter-value rows (for backup export).
  Future<List<CounterValueRow>> getAllValues() {
    return (select(counterValues)..where((v) => _live)).get();
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
