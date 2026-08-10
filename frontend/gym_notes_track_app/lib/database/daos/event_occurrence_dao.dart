import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/event_occurrences_table.dart';

part 'event_occurrence_dao.g.dart';

@DriftAccessor(tables: [EventOccurrenceDescriptions])
class EventOccurrenceDao extends DatabaseAccessor<AppDatabase>
    with _$EventOccurrenceDaoMixin {
  EventOccurrenceDao(super.db);

  /// Every override row. The table holds only user deltas, so this stays
  /// small enough to keep entirely in memory for O(1) synchronous lookups.
  Future<List<EventOccurrenceRow>> getAll() {
    return select(eventOccurrenceDescriptions).get();
  }

  /// Upsert that preserves `createdAt` on existing rows, mirroring
  /// [CalendarEventDao.upsert]: `insertOnConflictUpdate` would overwrite it
  /// with whatever the caller's companion holds. Try UPDATE with `createdAt`
  /// masked out, INSERT on miss, both inside one transaction.
  Future<void> upsert(EventOccurrenceDescriptionsCompanion entry) {
    return transaction(() async {
      final updated =
          await (update(eventOccurrenceDescriptions)..where(
                (o) =>
                    o.eventId.equals(entry.eventId.value) &
                    o.day.equals(entry.day.value),
              ))
              .write(entry.copyWith(createdAt: const Value.absent()));
      if (updated == 0) {
        await into(eventOccurrenceDescriptions).insert(entry);
      }
    });
  }

  /// Drops one day's override, returning it to the event's template.
  Future<void> deleteFor(String eventId, DateTime day) {
    return (delete(eventOccurrenceDescriptions)..where(
          (o) => o.eventId.equals(eventId) & o.day.equals(day),
        ))
        .go();
  }

  /// Cascade for a deleted event.
  Future<void> deleteForEvent(String eventId) {
    return (delete(
      eventOccurrenceDescriptions,
    )..where((o) => o.eventId.equals(eventId))).go();
  }

  Future<void> deleteAll() {
    return delete(eventOccurrenceDescriptions).go();
  }
}
