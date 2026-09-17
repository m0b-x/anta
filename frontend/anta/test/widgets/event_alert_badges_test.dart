import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/event_alert_badge.dart';

/// The badges are read **synchronously** from the facade while a row builds,
/// so what they promise is exactly what the facade says at that instant — and
/// what they must not promise is a ring an event will never make.
void main() {
  final event = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 20),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 18 * 60),
  );

  void publish(List<EventAlert> alerts) {
    EventAlerts.updateCache(
      byEvent: {'e1': List<EventAlert>.unmodifiable(alerts)},
    );
  }

  tearDown(EventAlerts.resetCache);

  Future<void> pumpBadges(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: EventAlertBadges(event: event)),
      ),
    );
  }

  testWidgets('an event with no alerts carries no badge', (tester) async {
    await pumpBadges(tester);

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('an alarm badges in the alarm glyph', (tester) async {
    publish(const [
      EventAlert(
        id: 'a1',
        eventId: 'e1',
        mode: AlertMode.ring,
        offsetMinutes: 0,
      ),
    ]);
    await pumpBadges(tester);

    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'At start',
    );
  });

  testWidgets('a reminder badges in the bell, and both show both', (
    tester,
  ) async {
    publish(const [
      EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 10),
      EventAlert(
        id: 'a2',
        eventId: 'e1',
        mode: AlertMode.ring,
        offsetMinutes: 0,
      ),
    ]);
    await pumpBadges(tester);

    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
  });

  testWidgets('a disabled alert badges nothing', (tester) async {
    publish(const [
      EventAlert(
        id: 'a1',
        eventId: 'e1',
        mode: AlertMode.ring,
        enabled: false,
      ),
    ]);
    await pumpBadges(tester);

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the tooltip names every alert of the tier', (tester) async {
    publish(const [
      EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 10),
      EventAlert(id: 'a2', eventId: 'e1', offsetMinutes: 60),
    ]);
    await pumpBadges(tester);

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      '10 min before · 1 h before',
    );
  });
}
