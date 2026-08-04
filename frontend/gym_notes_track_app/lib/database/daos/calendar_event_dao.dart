import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/calendar_events_table.dart';

part 'calendar_event_dao.g.dart';

@DriftAccessor(tables: [CalendarEvents])
class CalendarEventDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarEventDaoMixin {
  CalendarEventDao(super.db);

  Future<List<CalendarEventRow>> getAll() {
    return (select(
      calendarEvents,
    )..orderBy([(e) => OrderingTerm.asc(e.startDate)])).get();
  }

  /// Upsert that preserves `createdAt` on existing rows. We can't use
  /// `insertOnConflictUpdate` because it would overwrite `createdAt` with
  /// whatever the caller's companion holds. Instead: try UPDATE (with
  /// `createdAt` masked out), and INSERT on miss. Wrapped in a single
  /// transaction so the update→insert sequence is atomic.
  Future<void> upsert(CalendarEventsCompanion entry) {
    return transaction(() async {
      final updated =
          await (update(calendarEvents)
                ..where((e) => e.id.equals(entry.id.value)))
              .write(entry.copyWith(createdAt: const Value.absent()));
      if (updated == 0) {
        await into(calendarEvents).insert(entry);
      }
    });
  }

  Future<void> deleteById(String id) {
    return (delete(calendarEvents)..where((e) => e.id.equals(id))).go();
  }

  /// Reassigns every event currently in category [fromId] to [toId]. Used
  /// when a custom category is deleted so its events fall back to a surviving
  /// category instead of dangling. Returns the number of rows updated.
  Future<int> reassignCategory(String fromId, String toId) {
    return (update(
      calendarEvents,
    )..where((e) => e.category.equals(fromId))).write(
      CalendarEventsCompanion(
        category: Value(toId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteAll() {
    return delete(calendarEvents).go();
  }
}
