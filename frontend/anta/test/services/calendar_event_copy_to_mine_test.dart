import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

/// "Copy to my calendar" (share surfaces §6.9 item 4, D19): a partner's
/// event as its read sheet shows it on one day becomes a new event of my
/// own — and nothing of the partner's, nor of mine on their event, comes
/// with it.
void main() {
  late AppDatabase db;
  late CalendarEventService service;
  late EventAlertService alerts;

  final day = DateTime.utc(2026, 9, 23);

  CalendarEvent theirsOf({
    String categoryId = 'gym',
    RecurrenceRule rule = const WeeklyRecurrence(
      weekdays: {DateTime.wednesday},
    ),
    bool perDay = true,
  }) => CalendarEvent(
    id: 'theirs',
    title: 'Climbing',
    categoryId: categoryId,
    startDate: DateTime.utc(2026, 9, 2),
    rule: rule,
    endDate: DateTime.utc(2026, 12, 30),
    time: const EventTime(startMinute: 19 * 60, durationMinutes: 90),
    description: 'The usual wall',
    perOccurrenceDescriptions: perDay,
    priority: 2,
    noteId: 'their-note',
    iconKey: 'hiking',
    colorValue: 0xFF00897B,
    tintIcon: false,
    tracksPresence: true,
    removeAfterAlert: true,
    categoryAlerts: false,
  );

  /// [event] stored with a skipped day, a text for [day] and an alert of
  /// mine, then handed to the partner as the shared reader would hold it.
  Future<CalendarEvent> storeAsPartners(CalendarEvent event) async {
    await service.upsert(event);
    await (await EventSkipService.forTesting(
      db,
    )).markSkipped(event.id, DateTime.utc(2026, 9, 16));
    await (await EventOccurrenceService.forTesting(
      db,
    )).setDescription(event.id, day, 'Bouldering, bring chalk');
    await alerts.replaceForEvent(event.id, [
      EventAlert(id: 'mine-on-theirs', eventId: event.id, mode: AlertMode.ring),
    ]);
    await db.customStatement(
      "UPDATE calendar_events SET owner_id = 'partner' WHERE id = ?",
      [event.id],
    );
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
    await service.reload();
    return service.events.firstWhere((e) => e.id == event.id);
  }

  setUp(() async {
    CalendarEventService.reset();
    EventPresenceService.reset();
    EventAlertService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    db = await openTestDatabase();
    service = await CalendarEventService.forTesting(db);
    alerts = await EventAlertService.forTesting(db);
    // A skip clears the day's mark through the presence service.
    await EventPresenceService.forTesting(db);
    CalendarCategories.updateCache(const [
      CalendarCategory(
        id: 'gym',
        name: 'Gym',
        colorValue: 0xFF43A047,
        iconKey: 'fitness_center',
        sortOrder: 0,
        isBuiltIn: true,
      ),
      CalendarCategory(
        id: 'other',
        name: 'Other',
        colorValue: 0xFF757575,
        iconKey: 'event',
        sortOrder: 1,
        isBuiltIn: true,
      ),
    ]);
  });

  tearDown(() async {
    CalendarCategories.updateCache(const []);
    CalendarEventService.reset();
    EventPresenceService.reset();
    EventAlertService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    await db.close();
  });

  test(
    'a new event of my own with the facts shown, stored and cached',
    () async {
      final theirs = await storeAsPartners(theirsOf(perDay: false));
      expect(theirs.fromPartner, isTrue);

      final copy = await service.copyToMine(theirs, day);

      expect(copy.id, isNot('theirs'));
      expect(copy.fromPartner, isFalse);
      expect(copy.title, 'Climbing');
      expect(copy.time, theirs.time);
      expect(copy.rule, theirs.rule);
      expect(copy.startDate, theirs.startDate);
      expect(copy.endDate, theirs.endDate);
      expect(copy.priority, 2);
      expect(copy.categoryId, 'gym');
      expect(copy.description, 'The usual wall');
      // The event's own look is a fact the read sheet shows.
      expect(copy.iconKey, 'hiking');
      expect(copy.colorValue, 0xFF00897B);
      expect(copy.tintIcon, isFalse);
      expect(copy.createdAt, isNotNull);
      expect(service.events.firstWhere((e) => e.id == copy.id), copy);

      // Mine in the table too: no owner, no share mark — and the partner's
      // event untouched beside it.
      final row = (await db.calendarEventDao.getByIdsIncludingDeleted([
        copy.id,
      ])).single;
      expect(row.ownerId, isNull);
      expect(row.sharedPair, isNull);
      expect(service.events.firstWhere((e) => e.id == 'theirs'), theirs);
    },
  );

  test("a recurring event's copy takes the opened day's text", () async {
    final theirs = await storeAsPartners(theirsOf());

    final onTheDay = await service.copyToMine(theirs, day);
    final onAnother = await service.copyToMine(
      theirs,
      DateTime.utc(2026, 9, 30),
    );

    expect(onTheDay.description, 'Bouldering, bring chalk');
    expect(onAnother.description, 'The usual wall');
    // One text, so no per-day rows to keep apart.
    expect(onTheDay.perOccurrenceDescriptions, isFalse);
    expect(OccurrenceDescriptions.overridesFor(onTheDay.id), isEmpty);
  });

  test('a category I do not have becomes Other; a shared built-in stays '
      'mine', () async {
    final theirs = await storeAsPartners(theirsOf(categoryId: 'their-own'));

    final copy = await service.copyToMine(theirs, day);

    expect(copy.categoryId, kFallbackCategoryId);
  });

  // The catalogue holds the partner's own categories too, for drawing their
  // events; an event of mine can never take one.
  test('the partner\'s own category, held here, is never the copy\'s', () async {
    CalendarCategories.updateCache(const [
      CalendarCategory(
        id: 'other',
        name: 'Other',
        colorValue: 0xFF757575,
        iconKey: 'event',
        sortOrder: 1,
        isBuiltIn: true,
      ),
      CalendarCategory(
        id: 'their-own',
        name: 'Shifts',
        colorValue: 0xFF00897B,
        iconKey: 'work',
        sortOrder: 0,
        isBuiltIn: false,
        fromPartner: true,
      ),
    ]);
    final theirs = await storeAsPartners(theirsOf(categoryId: 'their-own'));

    final copy = await service.copyToMine(theirs, day);

    expect(copy.categoryId, kFallbackCategoryId);
    expect(copy.fromPartner, isFalse);
  });

  test('nothing else comes along: no alert, note, skipped day, presence '
      'or switch of theirs', () async {
    final theirs = await storeAsPartners(theirsOf());

    final copy = await service.copyToMine(theirs, day);

    expect(EventAlerts.alertsFor(copy.id), isEmpty);
    expect(await db.eventAlertDao.getActiveForEvent(copy.id), isEmpty);
    expect(EventAlerts.alertsFor('theirs').single.id, 'mine-on-theirs');
    expect(EventSkips.daysFor(copy.id), isEmpty);
    expect(copy.noteId, isNull);
    expect(copy.tracksPresence, isFalse);
    expect(copy.removeAfterAlert, isFalse);
    expect(copy.categoryAlerts, isTrue);
  });

  test('a day blanked on purpose copies as no description', () async {
    final theirs = await storeAsPartners(theirsOf());
    await db.customStatement(
      "UPDATE calendar_event_occurrences SET description = '' "
      "WHERE event_id = 'theirs'",
    );
    await (await EventOccurrenceService.forTesting(db)).reload();

    final copy = await service.copyToMine(theirs, day);

    expect(copy.description, isNull);
  });
}
