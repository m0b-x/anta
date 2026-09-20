import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_hub_entry.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/alerts_page.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';

import '../services/permission_support.dart';

class _RecordingObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}

/// The hub is a view: what it shows is what it was handed, and everything it
/// does is a dispatch to the calendar bloc. So the suite hands it rows through
/// the loader seam and watches the bloc — no database, no scheduler, no
/// plugin channel.
void main() {
  late CalendarBloc bloc;
  late _RecordingObserver observer;
  late BlocObserver previousObserver;
  late List<({String eventId, List<EventAlert> alerts})> writes;

  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final fireDay = DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day);

  CalendarEvent eventOf({
    String id = 'e1',
    String title = 'Leg day',
    bool removeAfterAlert = false,
  }) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'gym',
    startDate: fireDay,
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 18 * 60),
    removeAfterAlert: removeAfterAlert,
  );

  const alarm = EventAlert(
    id: 'a1',
    eventId: 'e1',
    mode: AlertMode.ring,
    offsetMinutes: 10,
  );

  AlertHubEntry entryOf({
    CalendarEvent? event,
    EventAlert alert = alarm,
    int hour = 17,
    int minute = 50,
    DateTime? originalFireAt,
    int? snoozeOsId,
  }) => AlertHubEntry(
    event: event ?? eventOf(),
    alert: alert,
    day: fireDay,
    fireAt: DateTime(fireDay.year, fireDay.month, fireDay.day, hour, minute),
    originalFireAt: originalFireAt,
    snoozeOsId: snoozeOsId,
  );

  setUp(() {
    previousObserver = Bloc.observer;
    observer = _RecordingObserver();
    Bloc.observer = observer;
    writes = [];
    bloc = CalendarBloc(
      service: Completer<CalendarEventService>().future,
      alertReconciler: (_, _) async {},
      alertWriter: (eventId, alerts) async =>
          writes.add((eventId: eventId, alerts: alerts)),
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
    Bloc.observer = previousObserver;
    EventAlerts.resetCache();
  });

  Future<void> pumpHub(
    WidgetTester tester,
    List<AlertHubEntry> Function() entries, {
    PermissionService? permissions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<CalendarBloc>.value(
          value: bloc,
          child: AlertsPage.forTesting(
            loadEntries: () async => entries(),
            permissions: permissions,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no alerts shows the empty state', (tester) async {
    await pumpHub(tester, () => const []);

    expect(find.text('No upcoming alerts'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('rows are grouped under a day header, with the one formatter', (
    tester,
  ) async {
    await pumpHub(
      tester,
      () => [
        entryOf(),
        entryOf(
          event: eventOf(id: 'e2', title: 'Swim'),
          alert: const EventAlert(id: 'b1', eventId: 'e2'),
          hour: 18,
          minute: 0,
        ),
      ],
    );

    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('10 min before'), findsOneWidget);
    expect(find.text('Swim'), findsOneWidget);
    expect(find.text('At start'), findsOneWidget);
    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
  });

  testWidgets('the switch dispatches ToggleEventAlert and moves at once', (
    tester,
  ) async {
    await pumpHub(tester, () => [entryOf()]);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      observer.events.whereType<ToggleEventAlert>().single,
      const ToggleEventAlert(eventId: 'e1', alertId: 'a1', enabled: false),
    );
    await tester.pumpAndSettle();
    expect(writes.single.alerts, [alarm.copyWith(enabled: false)]);
  });

  testWidgets('a disabled alert stays listed with its switch off', (
    tester,
  ) async {
    await pumpHub(
      tester,
      () => [entryOf(alert: alarm.copyWith(enabled: false))],
    );

    expect(find.text('Leg day'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('a snoozed row shows both times and cancels instead of toggling', (
    tester,
  ) async {
    await pumpHub(
      tester,
      () => [
        entryOf(
          hour: 18,
          minute: 0,
          originalFireAt: DateTime(
            fireDay.year,
            fireDay.month,
            fireDay.day,
            17,
            50,
          ),
          snoozeOsId: 77,
        ),
      ],
    );

    expect(find.text('Snoozed · 10 min before'), findsOneWidget);
    expect(find.textContaining('5:50'), findsOneWidget);
    expect(find.textContaining('6:00'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byTooltip('Cancel snooze'), findsOneWidget);
  });

  testWidgets('a registry change re-reads the rows', (tester) async {
    var rows = [entryOf()];
    await pumpHub(tester, () => rows);
    expect(find.text('Leg day'), findsOneWidget);

    rows = [];
    AlertScheduler.registryRevision.value++;
    await tester.pumpAndSettle();

    expect(find.text('Leg day'), findsNothing);
    expect(find.text('No upcoming alerts'), findsOneWidget);
  });

  testWidgets('long-press on a remove-after event offers to cancel it (A3)', (
    tester,
  ) async {
    await pumpHub(
      tester,
      () => [entryOf(event: eventOf(removeAfterAlert: true))],
    );

    await tester.longPress(find.text('Leg day'));
    await tester.pumpAndSettle();
    expect(find.textContaining('removes the event'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cancel alarm'));
    await tester.pumpAndSettle();

    expect(
      observer.events.whereType<DeleteCalendarEvent>().single.eventId,
      'e1',
    );
  });

  testWidgets('an ordinary event has no long-press at all', (tester) async {
    await pumpHub(tester, () => [entryOf()]);

    expect(tester.widget<InkWell>(find.byType(InkWell)).onLongPress, isNull);
  });

  testWidgets('a denied permission raises a banner, and its action asks', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(
      statuses: {
        AppPermission.notifications: PermissionStatus.denied,
        AppPermission.fullScreenIntent: PermissionStatus.denied,
        AppPermission.batteryOptimization: PermissionStatus.denied,
      },
    );
    await pumpHub(
      tester,
      () => [entryOf()],
      permissions: permissionServiceOver(gateway),
    );

    expect(find.textContaining('Notifications are off'), findsOneWidget);
    expect(find.textContaining('Full-screen alarms are off'), findsOneWidget);
    expect(find.textContaining('Battery'), findsNothing);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(gateway.prompts, [AppPermission.notifications]);
    expect(find.textContaining('Notifications are off'), findsNothing);
    expect(find.textContaining('Full-screen alarms are off'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(gateway.settingsOpens, [AppPermission.fullScreenIntent]);
  });

  testWidgets('a revoked exact-alarm permission raises its own banner', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(
      statuses: {
        ...allGranted,
        AppPermission.exactAlarms: PermissionStatus.denied,
      },
    );
    await pumpHub(
      tester,
      () => [entryOf()],
      permissions: permissionServiceOver(gateway),
    );

    expect(
      find.textContaining('Alarms & reminders access is off'),
      findsOneWidget,
    );
  });

  testWidgets('a platform with nothing to grant raises no banner', (
    tester,
  ) async {
    await pumpHub(
      tester,
      () => [entryOf()],
      permissions: PermissionService(
        gateway: const NoOpPermissionGateway(),
        store: MemoryPermissionPromptStore(),
        deviceId: () async => 'device-a',
      ),
    );

    expect(find.text('Turn on'), findsNothing);
    expect(find.text('Open settings'), findsNothing);
  });

  testWidgets('no permission service at all raises no banner', (tester) async {
    await pumpHub(tester, () => [entryOf()]);

    expect(find.text('Turn on'), findsNothing);
  });
}
