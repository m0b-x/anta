@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/models/alert_hub_entry.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/alerts_page.dart';
import 'package:anta/services/calendar_event_service.dart';

import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The Alerts hub with the alarm `test/widgets/alerts_page_test.dart` seeds:
/// Leg day at 18:00 tomorrow, rung ten minutes before. Tomorrow rather than
/// a fixed date because the hub lists only what is still to fire, and its
/// day header names tomorrow as such — the one wording that never moves.
void main() {
  late CalendarBloc bloc;

  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final fireDay = DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day);

  final event = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: fireDay,
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 18 * 60),
  );

  const alarm = EventAlert(
    id: 'a1',
    eventId: 'e1',
    mode: AlertMode.ring,
    offsetMinutes: 10,
  );

  setUp(() {
    bloc = CalendarBloc(
      service: Completer<CalendarEventService>().future,
      alertReconciler: (_, _) async {},
      alertWriter: (_, _) async {},
      allAlertsReconciler: (_) async {},
    );
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: const [],
        focusedDay: fireDay,
        selectedDay: fireDay,
      ),
    );
    EventAlerts.updateCache(
      byEvent: {
        'e1': List.unmodifiable(const [alarm]),
      },
    );
  });

  tearDown(() async {
    await bloc.close();
    EventAlerts.resetCache();
    EventDigests.resetCache();
  });

  for (final cell in goldenCells) {
    testWidgets('alerts page, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          goldenApp(
            cell,
            home: BlocProvider<CalendarBloc>.value(
              value: bloc,
              child: AlertsPage.forTesting(
                loadEntries: () async => [
                  AlertHubEntry(
                    event: event,
                    alert: alarm,
                    day: fireDay,
                    fireAt: DateTime(
                      fireDay.year,
                      fireDay.month,
                      fireDay.day,
                      17,
                      50,
                    ),
                  ),
                ],
                afterDigestSaved: (_) async => false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty);
      await expectGolden('alerts_page', cell);
    });
  }
}
