import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/counters_table.dart';
import '../tables/counter_values_table.dart';

part 'counter_dao.g.dart';

@DriftAccessor(tables: [Counters, CounterValues])
class CounterDao extends DatabaseAccessor<AppDatabase> with _$CounterDaoMixin {
  CounterDao(super.db);

  // ---------------------------------------------------------------------------
  // Counter definitions
  // ---------------------------------------------------------------------------

  Future<List<CounterRow>> getAllCounters() {
    return (select(counters)..orderBy([
          (c) => OrderingTerm.desc(c.isPinned),
          (c) => OrderingTerm.asc(c.position),
        ]))
        .get();
  }

  Future<void> insertCounter(CountersCompanion entry) {
    return into(counters).insert(entry);
  }

  Future<void> updateCounter(CountersCompanion entry) {
    return (update(
      counters,
    )..where((c) => c.id.equals(entry.id.value))).write(entry);
  }

  Future<void> deleteCounter(String id) {
    return (delete(counters)..where((c) => c.id.equals(id))).go();
  }

  Future<void> deleteCounterValues(String counterId) {
    return (delete(
      counterValues,
    )..where((v) => v.counterId.equals(counterId))).go();
  }

  // ---------------------------------------------------------------------------
  // Counter values
  // ---------------------------------------------------------------------------

  /// Upserts a single value row. [noteId] should be `''` for global counters.
  Future<void> upsertValue(String counterId, String noteId, int value) {
    return into(counterValues).insertOnConflictUpdate(
      CounterValuesCompanion(
        counterId: Value(counterId),
        noteId: Value(noteId),
        value: Value(value),
      ),
    );
  }

  /// Gets a single counter value. Returns null if not set.
  Future<int?> getValue(String counterId, String noteId) async {
    final row =
        await (select(counterValues)..where(
              (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
            ))
            .getSingleOrNull();
    return row?.value;
  }

  /// Gets all values for a given note (or global values when [noteId] is `''`).
  Future<Map<String, int>> getValuesForNote(String noteId) async {
    final rows = await (select(
      counterValues,
    )..where((v) => v.noteId.equals(noteId))).get();
    return {for (final r in rows) r.counterId: r.value};
  }

  /// Deletes the value row for a specific counter + note pair.
  Future<void> deleteValue(String counterId, String noteId) {
    return (delete(counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .go();
  }

  /// Bulk-updates positions for reordering. Expects a map of id → position.
  Future<void> updatePositions(Map<String, int> positions) async {
    if (positions.isEmpty) return;
    await transaction(() async {
      await Future.wait(
        positions.entries.map(
          (entry) => (update(counters)..where((c) => c.id.equals(entry.key)))
              .write(CountersCompanion(position: Value(entry.value))),
        ),
      );
    });
  }

  /// Returns all counter-value rows (for backup export).
  Future<List<CounterValueRow>> getAllValues() {
    return select(counterValues).get();
  }

  Future<Map<String, int>> getValuesForCounter(String counterId) async {
    final rows =
        await (select(counterValues)..where(
              (v) => v.counterId.equals(counterId) & v.noteId.isNotValue(''),
            ))
            .get();
    return {for (final r in rows) r.noteId: r.value};
  }

  Future<List<CounterValueRow>> getValuesForCounterOrdered(
    String counterId,
  ) async {
    return (select(counterValues)
          ..where(
            (v) => v.counterId.equals(counterId) & v.noteId.isNotValue(''),
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

  Future<void> setCounterPinned(String id, bool pinned) {
    return (update(counters)..where((c) => c.id.equals(id))).write(
      CountersCompanion(isPinned: Value(pinned)),
    );
  }

  // ---------------------------------------------------------------------------
  // Counter-value pin + reorder
  // ---------------------------------------------------------------------------

  Future<void> setNoteValuePinned(
    String counterId,
    String noteId,
    bool pinned,
  ) {
    return (update(counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .write(CounterValuesCompanion(isPinned: Value(pinned)));
  }

  Future<void> updateNoteValuePositions(
    String counterId,
    Map<String, int> positions,
  ) async {
    if (positions.isEmpty) return;
    await transaction(() async {
      await Future.wait(
        positions.entries.map(
          (entry) =>
              (update(counterValues)..where(
                    (v) =>
                        v.counterId.equals(counterId) &
                        v.noteId.equals(entry.key),
                  ))
                  .write(CounterValuesCompanion(position: Value(entry.value))),
        ),
      );
    });
  }

  /// Deletes every counter and counter-value row (used before import).
  Future<void> deleteAll() async {
    await delete(counterValues).go();
    await delete(counters).go();
  }
}
