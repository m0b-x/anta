import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_removal_notice.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';

import '../database/support/db_test_support.dart';

/// The notice is what turns A3's silent deletion into an offer, and it waits
/// for a calendar that may not exist yet — so the two properties worth pinning
/// are that it survives until someone takes it, and that it does not survive
/// forever.
void main() {
  final event = CalendarEvent(
    id: 'e1',
    title: 'Wake up',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 9, 20),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 7 * 60),
    removeAfterAlert: true,
  );

  const alerts = [
    EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
  ];

  final notice = AlertRemovalNotice.instance;

  tearDown(notice.clearForTesting);

  test('a notice waits until it is taken, then is gone', () {
    var notified = 0;
    void listener() => notified++;
    notice.addListener(listener);
    addTearDown(() => notice.removeListener(listener));

    notice.publish(event, alerts);

    expect(notified, 1);
    expect(notice.hasPending, isTrue);
    final taken = notice.take();
    expect(taken?.event.id, 'e1');
    // The cascade tombstoned them, so Undo needs them back.
    expect(taken?.alerts, alerts);
    expect(notice.take(), isNull);
  });

  test('a stale notice is dropped rather than offered', () {
    var now = DateTime(2026, 9, 20, 7);
    notice.clock = () => now;

    notice.publish(event, alerts);
    now = now.add(AlertRemovalNotice.freshness + const Duration(seconds: 1));

    expect(notice.take(), isNull);
    expect(notice.hasPending, isFalse);
  });

  group('AlertAcknowledgement', () {
    late AppDatabase db;
    late CalendarEventService events;

    // No gateway is registered, so the reconcile `apply` ends with is inert —
    // what is under test is who gets to remove the event, not the platform.
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      CalendarEventService.reset();
      EventAlertService.reset();
      db = await openTestDatabase();
      events = await CalendarEventService.forTesting(db);
      final alertService = await EventAlertService.forTesting(db);
      await events.upsert(event);
      await alertService.replaceForEvent('e1', alerts);
    });

    tearDown(() async {
      CalendarEventService.reset();
      EventAlertService.reset();
      await db.close();
    });

    AlertPayload payloadOf({
      AlertMode mode = AlertMode.ring,
      String database = 'gym_notes',
    }) => AlertPayload(
      database: database,
      eventId: 'e1',
      alertId: 'a1',
      dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
      osId: 7,
      mode: mode,
      title: 'Wake up',
      timeLabel: '07:00',
      categoryId: 'other',
      removeAfterAlert: true,
    );

    test('a stopped alarm removes the event and offers it back', () async {
      expect(await AlertAcknowledgement.apply(payloadOf()), isTrue);

      expect(events.events, isEmpty);
      expect(EventAlerts.alertsFor('e1'), isEmpty);
      final offered = notice.take();
      expect(offered?.event.id, 'e1');
      expect(offered?.alerts, alerts);
    });

    test('a reminder never does', () async {
      // Tapping a "10 min before" reminder is someone looking at the event.
      // Removing on it would also cancel the alarm the switch was set for.
      final removed = await AlertAcknowledgement.apply(
        payloadOf(mode: AlertMode.notify),
      );

      expect(removed, isFalse);
      expect(events.events.single.id, 'e1');
      expect(notice.hasPending, isFalse);
    });

    test('the event\'s own flag wins over a payload written earlier', () async {
      // "Keep the event" clears the flag on the event; a Stop that arrives
      // from the notification afterwards still carries the old payload.
      await events.upsert(event.copyWith(removeAfterAlert: false));

      expect(await AlertAcknowledgement.apply(payloadOf()), isFalse);
      expect(events.events.single.id, 'e1');
    });

    test('another database\'s alarm removes nothing here', () async {
      final removed = await AlertAcknowledgement.apply(
        payloadOf(database: 'work'),
      );

      expect(removed, isFalse);
      expect(events.events.single.id, 'e1');
    });
  });
}
