import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_hub_entry.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/alerts_page.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/widgets/digest_editor_sheet.dart';
import 'package:intl/intl.dart';

import '../services/permission_support.dart';
import 'support/digest_sheet_robot.dart';

class _RecordingObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}

/// Records the bloc's digest writes instead of making them.
class _FakeDigestWriter implements DigestWriter {
  final List<String> calls = [];

  @override
  Future<EventDigest?> create(EventDigest draft) async {
    calls.add('create');
    return draft;
  }

  @override
  Future<void> update(EventDigest digest) async => calls.add('update');

  @override
  Future<void> setEnabled(String id, bool enabled) async =>
      calls.add('setEnabled $id $enabled');

  @override
  Future<void> delete(String id) async => calls.add('delete $id');
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

  /// The bloc's digest writes land here: no test opens a database.
  late _FakeDigestWriter digestWriter;

  /// How often the hub ran its permission check after a digest save.
  var permissionChecks = 0;

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
    permissionChecks = 0;
    digestWriter = _FakeDigestWriter();
    bloc = CalendarBloc(
      service: Completer<CalendarEventService>().future,
      alertReconciler: (_, _) async {},
      alertWriter: (eventId, alerts, {knownIds}) async =>
          writes.add((eventId: eventId, alerts: alerts)),
      allAlertsReconciler: (_) async {},
      digestWriter: () async => digestWriter,
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
    EventDigests.resetCache();
  });

  /// [use24HourFormat] sets the phone's clock; left out, the app is pumped
  /// exactly as it always was, with no `MediaQuery` of the suite's own.
  Future<void> pumpHub(
    WidgetTester tester,
    List<AlertHubEntry> Function() entries, {
    AlertHistoryLoader? loadRecent,
    DigestHubLoader? loadDigests,
    PermissionService? permissions,
    bool? use24HourFormat,
    TextScaler? textScaler,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    Future<bool> Function(BuildContext context)? afterDigestSaved,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: use24HourFormat == null && textScaler == null
            ? null
            : (context, child) {
                final data = MediaQuery.of(context);
                return MediaQuery(
                  data: data.copyWith(
                    alwaysUse24HourFormat:
                        use24HourFormat ?? data.alwaysUse24HourFormat,
                    textScaler: textScaler ?? data.textScaler,
                  ),
                  child: child!,
                );
              },
        home: BlocProvider<CalendarBloc>.value(
          value: bloc,
          child: AlertsPage.forTesting(
            loadEntries: () async => entries(),
            loadRecent: loadRecent,
            loadDigests: loadDigests,
            permissions: permissions,
            weekStart: weekStart,
            afterDigestSaved:
                afterDigestSaved ??
                (_) async {
                  permissionChecks++;
                  return false;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the Recent section renders one row per outcome (OS-4)', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    AlertHistoryEntry historyOf(
      AlertOutcome outcome,
      int hour, {
      bool removed = false,
    }) => AlertHistoryEntry(
      event: removed ? null : eventOf(),
      alert: removed ? null : alarm,
      day: DateTime.utc(yesterday.year, yesterday.month, yesterday.day),
      fireAt: DateTime(yesterday.year, yesterday.month, yesterday.day, hour),
      settledAt: DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        hour,
        1,
      ),
      outcome: outcome,
    );
    await pumpHub(
      tester,
      () => [entryOf()],
      loadRecent: () async => [
        historyOf(AlertOutcome.rang, 7),
        historyOf(AlertOutcome.stopped, 8),
        historyOf(AlertOutcome.snoozed, 9),
        historyOf(AlertOutcome.missed, 10, removed: true),
        historyOf(AlertOutcome.delivered, 11),
      ],
    );

    expect(find.text('Recent'), findsOneWidget);
    expect(find.textContaining('Delivered'), findsOneWidget);
    expect(find.byIcon(Icons.alarm_on_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.snooze_rounded), findsOneWidget);
    expect(find.byIcon(Icons.alarm_off_rounded), findsOneWidget);
    expect(find.textContaining('Rang'), findsOneWidget);
    expect(find.textContaining('Stopped'), findsOneWidget);
    expect(find.textContaining('Snoozed'), findsOneWidget);
    expect(find.textContaining('Missed'), findsOneWidget);
    // A row whose event is gone keeps its place under the fallback title.
    expect(find.text('Removed event'), findsOneWidget);
    // The live rows are untouched: one switch, for the one live entry.
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('history alone still shows the section, not the empty state', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await pumpHub(
      tester,
      () => const [],
      loadRecent: () async => [
        AlertHistoryEntry(
          event: eventOf(),
          alert: alarm,
          day: DateTime.utc(yesterday.year, yesterday.month, yesterday.day),
          fireAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 7),
          settledAt: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            7,
            1,
          ),
          outcome: AlertOutcome.stopped,
        ),
      ],
    );

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('No upcoming alerts'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

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

  testWidgets("an all-day alert's time follows the phone's clock, on a live "
      'row and on a Recent one', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final birthday = CalendarEvent(
      id: 'e3',
      title: 'Birthday',
      categoryId: 'gym',
      startDate: fireDay,
      rule: const OneTimeRecurrence(),
    );
    const dayBefore = EventAlert(
      id: 'c1',
      eventId: 'e3',
      daysBefore: 1,
      dayMinute: 20 * 60,
    );
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    List<AlertHubEntry> live() => [
      entryOf(event: birthday, alert: dayBefore, hour: 20, minute: 0),
    ];
    Future<List<AlertHistoryEntry>> recent() async => [
      AlertHistoryEntry(
        event: birthday,
        alert: dayBefore,
        day: DateTime.utc(yesterday.year, yesterday.month, yesterday.day),
        fireAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 20),
        settledAt: DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          20,
          1,
        ),
        outcome: AlertOutcome.stopped,
      ),
    ];

    await pumpHub(tester, live, loadRecent: recent, use24HourFormat: false);
    expect(find.text('The day before, 8:00 PM'), findsOneWidget);
    expect(find.text('Stopped · The day before, 8:00 PM'), findsOneWidget);

    await pumpHub(tester, live, loadRecent: recent, use24HourFormat: true);
    expect(find.text('The day before, 20:00'), findsOneWidget);
    expect(find.text('Stopped · The day before, 20:00'), findsOneWidget);
    expect(find.textContaining('8:00 PM'), findsNothing);
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

  // v42, D5: an inherited alert belongs to the category, so its switch is the
  // event's opt-out — never the alert's own flag, which would silence every
  // other event in the category.
  group('an inherited alert', () {
    final inherited = const CategoryAlert(
      id: 'c1',
      categoryId: 'gym',
      offsetMinutes: 30,
    ).toEventAlert('e1');

    setUp(() {
      CalendarCategories.updateCache(const [
        CalendarCategory(
          id: 'gym',
          name: 'Gym',
          colorValue: 0xFF43A047,
          iconKey: 'event',
          sortOrder: 0,
          isBuiltIn: false,
        ),
      ]);
    });

    tearDown(() => CalendarCategories.updateCache(const []));

    /// The events the bloc holds — what the switch reads at the press.
    void holding(List<CalendarEvent> events) {
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        CalendarPageLoaded(
          allEvents: events,
          focusedDay: fireDay,
          selectedDay: fireDay,
        ),
      );
    }

    testWidgets('says where it comes from', (tester) async {
      await pumpHub(tester, () => [entryOf(alert: inherited)]);

      expect(find.text('30 min before · From Gym'), findsOneWidget);
    });

    testWidgets('its switch is the event\'s flag, written through '
        'UpdateCalendarEvent and never ToggleEventAlert', (tester) async {
      holding([eventOf()]);
      await pumpHub(tester, () => [entryOf(alert: inherited)]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(observer.events.whereType<ToggleEventAlert>(), isEmpty);
      final update = observer.events.whereType<UpdateCalendarEvent>().single;
      expect(update.event.id, 'e1');
      expect(update.event.categoryAlerts, isFalse);
      expect(update.alerts, isNull);
    });

    // The shape `AlertScheduler.hubEntries` lists an opted-out event in: its
    // enabled inherited alert, the event's flag off.
    testWidgets('an opted-out event reads its switch off and switches back '
        'on', (tester) async {
      final optedOut = eventOf().copyWith(categoryAlerts: false);
      holding([optedOut]);
      await pumpHub(tester, () => [entryOf(event: optedOut, alert: inherited)]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      final update = observer.events.whereType<UpdateCalendarEvent>().single;
      expect(update.event.categoryAlerts, isTrue);
    });

    testWidgets('the switch writes the event as the bloc holds it at the '
        'press, not as the row was loaded', (tester) async {
      holding([eventOf(title: 'Renamed')]);
      await pumpHub(tester, () => [entryOf(alert: inherited)]);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      final update = observer.events.whereType<UpdateCalendarEvent>().single;
      expect(update.event.title, 'Renamed');
      expect(update.event.categoryAlerts, isFalse);
    });

    testWidgets('a toggle on an event no longer in the bloc dispatches '
        'nothing', (tester) async {
      await pumpHub(tester, () => [entryOf(alert: inherited)]);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(observer.events.whereType<UpdateCalendarEvent>(), isEmpty);
      expect(observer.events.whereType<ToggleEventAlert>(), isEmpty);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('two events inheriting one alert on one day are two rows', (
      tester,
    ) async {
      final arms = eventOf(id: 'e2', title: 'Arm day');
      await pumpHub(
        tester,
        () => [
          entryOf(alert: inherited),
          entryOf(
            event: arms,
            alert: const CategoryAlert(
              id: 'c1',
              categoryId: 'gym',
              offsetMinutes: 30,
            ).toEventAlert('e2'),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Arm day'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('the switches of one event\'s inherited rows move together; '
        'an own alert\'s stays', (tester) async {
      holding([eventOf()]);
      await pumpHub(
        tester,
        () => [
          entryOf(alert: inherited),
          entryOf(
            alert: const CategoryAlert(
              id: 'c2',
              categoryId: 'gym',
              offsetMinutes: 5,
            ).toEventAlert('e1'),
            minute: 55,
          ),
          entryOf(hour: 18, minute: 0),
        ],
      );

      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      expect(
        tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value),
        [false, false, true],
      );
    });

    testWidgets('its switch tells a screen reader what it means', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpHub(tester, () => [entryOf(alert: inherited)]);

      expect(find.bySemanticsLabel('Alert for Leg day'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Alert for Leg day'))
            .getSemanticsData()
            .hint,
        'Category alerts',
      );
      semantics.dispose();
    });
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

  testWidgets(
    'a snoozed row shows both times and cancels instead of toggling',
    (tester) async {
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
    },
  );

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

    // The alert's row: the Digests group above it has ink wells of its own.
    final row = find.ancestor(
      of: find.text('Leg day'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(row).onLongPress, isNull);
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

  // v42, D14: the hub is where digests live. It reads them from the facade
  // and their fires through the loader seam, and writes only through the
  // bloc's three digest events.
  group('digests', () {
    const birthdays = EventDigest(id: 'd1', name: 'Birthdays');
    final nextFirst = DateTime(2030, 11, 1, 9);

    DigestHubEntry fireOf(EventDigest digest, DateTime at, {int count = 3}) =>
        DigestHubEntry(
          digest: digest,
          fireAt: at,
          spanStart: DateTime.utc(at.year, at.month, at.day),
          spanEnd: DateTime.utc(at.year, at.month + 1, at.day - 1),
          count: count,
        );

    void tallSurface(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1800);
      addTearDown(tester.view.reset);
    }

    setUp(() {
      EventDigests.updateCache(List.unmodifiable(const [birthdays]));
    });

    Finder byId(String id) => find.bySemanticsIdentifier(id);

    /// The bloc was built outside the test's fake clock, so its handler's
    /// awaits finish on the real event loop.
    Future<void> settleBloc(WidgetTester tester) async {
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    testWidgets('the group lists each digest with how it fires and when next', (
      tester,
    ) async {
      tallSurface(tester);
      await pumpHub(
        tester,
        () => const [],
        loadDigests: () async => [fireOf(birthdays, nextFirst)],
        use24HourFormat: true,
      );

      expect(find.text('DIGESTS'), findsOneWidget);
      expect(byId(SemanticsIds.alertsDigestRow('d1')), findsOneWidget);
      expect(
        find.text(
          'Monthly on the 1st, 09:00 · next '
          '${DateFormat.MMMEd('en').format(nextFirst)}',
        ),
        findsOneWidget,
      );
      expect(byId(SemanticsIds.alertsDigestAdd), findsOneWidget);
    });

    testWidgets('a digest with no fire ahead reads how it fires alone', (
      tester,
    ) async {
      await pumpHub(tester, () => const [], use24HourFormat: true);

      expect(find.text('Monthly on the 1st, 09:00'), findsOneWidget);
    });

    testWidgets('the switch dispatches ToggleEventDigest and moves at once', (
      tester,
    ) async {
      await pumpHub(tester, () => const []);
      // The one live switch on a page with no alerts: the digest's.
      final toggle = find.byWidgetPredicate(
        (widget) => widget is Switch && widget.onChanged != null,
      );
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.tap(byId(SemanticsIds.alertsDigestSwitch('d1')));
      await tester.pump();

      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(
        observer.events.whereType<ToggleEventDigest>().single,
        const ToggleEventDigest('d1', enabled: false),
      );
    });

    testWidgets('Add digest is gone at the cap', (tester) async {
      EventDigests.updateCache(
        List.unmodifiable([
          for (var i = 0; i < 10; i++)
            EventDigest(id: 'd$i', name: 'Digest $i', sortOrder: i),
        ]),
      );
      tallSurface(tester);
      await pumpHub(tester, () => const []);

      expect(byId(SemanticsIds.alertsDigestRow('d9')), findsOneWidget);
      expect(byId(SemanticsIds.alertsDigestAdd), findsNothing);
    });

    testWidgets('a digest past the cap says it is not armed', (tester) async {
      // C113: sync can carry a database past `maxDigests` — `nextSortOrder()`
      // is per device — and the planner then arms the first ten silently. The
      // eleventh card's switch is on, so without this it read exactly like a
      // card that fires.
      EventDigests.updateCache(
        List.unmodifiable([
          for (var i = 0; i < 11; i++)
            EventDigest(id: 'd$i', name: 'Digest $i', sortOrder: i),
        ]),
      );
      tallSurface(tester);
      await pumpHub(tester, () => const [], use24HourFormat: true);

      expect(byId(SemanticsIds.alertsDigestRow('d10')), findsOneWidget);
      expect(
        find.text('Monthly on the 1st, 09:00 · not armed, 10 digests at most'),
        findsOneWidget,
      );
      // The ten the pass does arm say nothing of the kind.
      expect(find.text('Monthly on the 1st, 09:00'), findsNWidgets(10));
    });

    testWidgets('the cap reads the switch the user has just moved', (
      tester,
    ) async {
      // C154: the row's switch reads `_pendingDigestEnabled` before the
      // facade republishes, so the caption has to read it too — switching one
      // of the first ten off leaves the eleventh armed, and the two must
      // answer at the same moment.
      EventDigests.updateCache(
        List.unmodifiable([
          for (var i = 0; i < 11; i++)
            EventDigest(id: 'd$i', name: 'Digest $i', sortOrder: i),
        ]),
      );
      tallSurface(tester);
      await pumpHub(tester, () => const [], use24HourFormat: true);
      expect(find.textContaining('not armed'), findsOneWidget);

      await tester.tap(byId(SemanticsIds.alertsDigestSwitch('d0')));
      await tester.pump();

      expect(find.textContaining('not armed'), findsNothing);
    });

    testWidgets('a row opens its sheet, and an edit dispatches '
        'SaveEventDigest; an unchanged Save dispatches nothing', (
      tester,
    ) async {
      await pumpHub(tester, () => const []);

      await tester.tap(byId(SemanticsIds.alertsDigestRow('d1')));
      await tester.pumpAndSettle();
      expect(find.byType(DigestEditorSheet), findsOneWidget);
      expect(find.text('Edit digest'), findsOneWidget);
      await DigestSheetRobot(tester).save();
      expect(observer.events.whereType<SaveEventDigest>(), isEmpty);
      expect(permissionChecks, 0);

      await tester.tap(byId(SemanticsIds.alertsDigestRow('d1')));
      await tester.pumpAndSettle();
      final robot = DigestSheetRobot(tester);
      await robot.pickLead(1);
      await robot.save();

      expect(
        observer.events.whereType<SaveEventDigest>().single,
        SaveEventDigest(birthdays.copyWith(leadDays: 1)),
      );
      // An enabled digest: the permission it may need is asked for.
      expect(permissionChecks, 1);
      await settleBloc(tester);
      expect(digestWriter.calls, ['update']);
    });

    testWidgets('saving a switched-off digest asks for no permission', (
      tester,
    ) async {
      EventDigests.updateCache(
        List.unmodifiable([birthdays.copyWith(enabled: false)]),
      );
      await pumpHub(tester, () => const []);
      await tester.tap(byId(SemanticsIds.alertsDigestRow('d1')));
      await tester.pumpAndSettle();
      final robot = DigestSheetRobot(tester);
      await robot.pickLead(1);
      await robot.save();

      expect(observer.events.whereType<SaveEventDigest>(), hasLength(1));
      expect(permissionChecks, 0);
    });

    testWidgets('Add digest opens a blank sheet; its Save is a new digest', (
      tester,
    ) async {
      await pumpHub(tester, () => const []);

      await tester.tap(byId(SemanticsIds.alertsDigestAdd));
      await tester.pumpAndSettle();
      expect(find.text('New digest'), findsOneWidget);
      await DigestSheetRobot(tester).save();

      final saved = observer.events.whereType<SaveEventDigest>().single.digest;
      // The service mints the id: the bloc creates.
      expect(saved.id, isEmpty);
      expect(saved.enabled, isTrue);
      await settleBloc(tester);
      expect(digestWriter.calls, ['create']);
    });

    testWidgets('the sheet takes the app\'s week start from the hub', (
      tester,
    ) async {
      await pumpHub(
        tester,
        () => const [],
        weekStart: CalendarWeekStart.sunday,
      );
      await tester.tap(byId(SemanticsIds.alertsDigestAdd));
      await tester.pumpAndSettle();
      final robot = DigestSheetRobot(tester);

      await robot.pickCadence(DigestCadence.weekly);

      expect((await robot.anchorChoices()).first, 'Sunday');
    });

    testWidgets('the switch writes the column through the bloc', (
      tester,
    ) async {
      await pumpHub(tester, () => const []);

      await tester.tap(byId(SemanticsIds.alertsDigestSwitch('d1')));
      await settleBloc(tester);

      expect(digestWriter.calls, ['setEnabled d1 false']);
    });

    testWidgets('a switched-off digest dims and promises no next fire; on '
        'again it does', (tester) async {
      tallSurface(tester);
      await pumpHub(
        tester,
        () => const [],
        loadDigests: () async => [fireOf(birthdays, nextFirst)],
        use24HourFormat: true,
      );
      final next =
          'Monthly on the 1st, 09:00 · next '
          '${DateFormat.MMMEd('en').format(nextFirst)}';
      Finder dimmed() => find.ancestor(
        of: find.text('Birthdays'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Opacity &&
              widget.opacity == FormMetrics.switchedOffOpacity,
        ),
      );
      expect(find.text(next), findsOneWidget);
      expect(dimmed(), findsNothing);

      await tester.tap(byId(SemanticsIds.alertsDigestSwitch('d1')));
      await tester.pump();
      expect(find.text(next), findsNothing);
      expect(find.text('Monthly on the 1st, 09:00'), findsOneWidget);
      expect(dimmed(), findsOneWidget);

      await tester.tap(byId(SemanticsIds.alertsDigestSwitch('d1')));
      await tester.pump();
      expect(find.text(next), findsOneWidget);
      expect(dimmed(), findsNothing);
    });

    testWidgets('a digest this build cannot read says so, its switch '
        'disabled and no sheet behind it', (tester) async {
      final unreadable = EventDigest.fromRow(
        id: 'd9',
        name: 'Later',
        payload: '{"cadence":"hourly"}',
      );
      expect(unreadable.isReadable, isFalse);
      EventDigests.updateCache(List.unmodifiable([unreadable]));
      await pumpHub(tester, () => const []);

      expect(find.text('Saved by a newer version of the app'), findsOneWidget);
      final toggle = tester.widget<Switch>(
        find.descendant(
          of: byId(SemanticsIds.alertsDigestSwitch('d9')),
          matching: find.byType(Switch),
        ),
      );
      expect(toggle.onChanged, isNull);

      await tester.tap(byId(SemanticsIds.alertsDigestRow('d9')));
      await tester.pumpAndSettle();
      expect(find.byType(DigestEditorSheet), findsNothing);
    });

    testWidgets('a digest\'s two fires are two ids; the second opens too', (
      tester,
    ) async {
      tallSurface(tester);
      const morning = EventDigest(
        id: 'd2',
        name: 'Morning',
        cadence: DigestCadence.daily,
        anchor: 0,
      );
      EventDigests.updateCache(List.unmodifiable(const [morning]));
      final first = DateTime(fireDay.year, fireDay.month, fireDay.day, 8);
      final second = DateTime(fireDay.year, fireDay.month, fireDay.day + 1, 8);
      await pumpHub(
        tester,
        () => const [],
        loadDigests: () async => [
          fireOf(morning, first),
          fireOf(morning, second),
        ],
      );

      expect(byId(SemanticsIds.alertsDigestFire('d2', first)), findsOneWidget);
      await tester.tap(byId(SemanticsIds.alertsDigestFire('d2', second)));
      await tester.pumpAndSettle();
      expect(find.byType(DigestEditorSheet), findsOneWidget);
    });

    testWidgets('at 200 % on a 360-wide phone a row\'s time stays on one '
        'line, on an alert row, a digest fire row and the Recent rows', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      const morning = EventDigest(
        id: 'd2',
        name: 'Morning',
        cadence: DigestCadence.daily,
        anchor: 0,
      );
      EventDigests.updateCache(List.unmodifiable(const [morning]));
      final at = DateTime(fireDay.year, fireDay.month, fireDay.day, 9);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      AlertHistoryEntry delivered(int hour, {EventDigest? digest}) =>
          AlertHistoryEntry(
            event: digest == null ? eventOf() : null,
            alert: digest == null
                ? const EventAlert(id: 'a1', eventId: 'e1')
                : null,
            digest: digest,
            day: DateTime.utc(yesterday.year, yesterday.month, yesterday.day),
            fireAt: DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
              hour,
              hour == 17 ? 50 : 0,
            ),
            settledAt: DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
              hour,
              hour == 17 ? 51 : 1,
            ),
            outcome: AlertOutcome.delivered,
          );
      await pumpHub(
        tester,
        () => [entryOf()],
        loadDigests: () async => [fireOf(morning, at)],
        loadRecent: () async => [delivered(17), delivered(9, digest: morning)],
        use24HourFormat: true,
        textScaler: const TextScaler.linear(2.0),
      );

      expect(tester.takeException(), isNull);
      // Each time twice: the live row and its Recent twin.
      final times = [
        for (final time in const ['09:00', '17:50'])
          for (var i = 0; i < 2; i++) (time: time, index: i),
      ];
      for (final (:time, :index) in times) {
        final finder = find.text(time, skipOffstage: false).at(index);
        await tester.scrollUntilVisible(finder, 200);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final lineTops = {
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: time.length),
          ))
            box.top,
        };
        expect(lineTops, hasLength(1), reason: '$time wrapped');
      }
    });

    testWidgets('at one instant the digest comes before the alert', (
      tester,
    ) async {
      const morning = EventDigest(
        id: 'd2',
        name: 'Morning',
        cadence: DigestCadence.daily,
        anchor: 0,
      );
      EventDigests.updateCache(List.unmodifiable(const [morning]));
      tallSurface(tester);
      final at = DateTime(fireDay.year, fireDay.month, fireDay.day, 17, 50);
      await pumpHub(
        tester,
        () => [entryOf()],
        loadDigests: () async => [fireOf(morning, at)],
      );

      expect(
        tester.getTopLeft(find.text('Morning').last).dy,
        lessThan(tester.getTopLeft(find.text('Leg day')).dy),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('the page and its bar sit on the page ground '
          '(${brightness.name})', (tester) async {
        final theme = ThemeData(brightness: brightness);
        await pumpHub(tester, () => const [], theme: theme);

        expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          theme.colorScheme.pageGround,
        );
        expect(
          tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
          theme.colorScheme.pageGround,
        );
      });
    }

    testWidgets('a confirmed Delete dispatches DeleteEventDigest', (
      tester,
    ) async {
      await pumpHub(tester, () => const []);
      await tester.tap(byId(SemanticsIds.alertsDigestRow('d1')));
      await tester.pumpAndSettle();

      await DigestSheetRobot(tester).delete();

      expect(
        observer.events.whereType<DeleteEventDigest>().single,
        const DeleteEventDigest('d1'),
      );
      expect(observer.events.whereType<SaveEventDigest>(), isEmpty);
    });

    testWidgets('an enabled digest fires under its day with its count and no '
        'switch; a disabled one does not', (tester) async {
      const morning = EventDigest(
        id: 'd2',
        name: 'Morning',
        cadence: DigestCadence.daily,
        anchor: 0,
        sortOrder: 1,
      );
      const paused = EventDigest(
        id: 'd3',
        name: 'Paused',
        cadence: DigestCadence.daily,
        anchor: 0,
        enabled: false,
        sortOrder: 2,
      );
      EventDigests.updateCache(
        List.unmodifiable(const [birthdays, morning, paused]),
      );
      tallSurface(tester);
      final at = DateTime(fireDay.year, fireDay.month, fireDay.day, 8);
      await pumpHub(
        tester,
        () => [entryOf()],
        loadDigests: () async => [
          fireOf(morning, at),
          fireOf(paused, at, count: 5),
        ],
      );

      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('3 events today'), findsOneWidget);
      expect(find.text('5 events today'), findsNothing);
      expect(byId(SemanticsIds.alertsDigestFire('d2', at)), findsOneWidget);
      // Before the alert at 17:50 on the same day.
      expect(
        tester.getTopLeft(find.text('3 events today')).dy,
        lessThan(tester.getTopLeft(find.text('Leg day')).dy),
      );
      final fireSwitches = tester.widgetList<Switch>(
        find.descendant(
          of: find.ancestor(
            of: find.text('3 events today'),
            matching: find.byType(Card),
          ),
          matching: find.byType(Switch),
        ),
      );
      expect(fireSwitches.every((s) => s.onChanged == null), isTrue);

      await tester.tap(find.text('3 events today'));
      await tester.pumpAndSettle();
      expect(find.byType(DigestEditorSheet), findsOneWidget);
    });

    testWidgets('Recent lists a digest delivery by how it fires', (
      tester,
    ) async {
      tallSurface(tester);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await pumpHub(
        tester,
        () => const [],
        use24HourFormat: true,
        loadRecent: () async => [
          AlertHistoryEntry(
            event: null,
            alert: null,
            digest: birthdays,
            day: DateTime.utc(yesterday.year, yesterday.month, yesterday.day),
            fireAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 9),
            settledAt: DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
              9,
            ),
            outcome: AlertOutcome.delivered,
          ),
        ],
      );

      expect(find.text('Recent'), findsOneWidget);
      expect(
        find.text('Delivered · Monthly on the 1st, 09:00'),
        findsOneWidget,
      );
      expect(find.text('Removed event'), findsNothing);
    });

    testWidgets('with digests but no alerts the empty state sits inline '
        'under the group', (tester) async {
      tallSurface(tester);
      await pumpHub(tester, () => const []);

      expect(find.text('No upcoming alerts'), findsOneWidget);
      expect(byId(SemanticsIds.alertsDigestRow('d1')), findsOneWidget);
      expect(byId(SemanticsIds.alertsDigestAdd), findsOneWidget);
      final addBottom = tester
          .getBottomLeft(byId(SemanticsIds.alertsDigestAdd))
          .dy;
      final emptyTop = tester
          .getTopLeft(find.byIcon(Icons.notifications_none_rounded))
          .dy;
      // Inline, one group gap under the group — not the page's middle.
      expect(emptyTop, greaterThanOrEqualTo(addBottom));
      expect(emptyTop - addBottom, lessThan(1800 / 4));
    });

    testWidgets('with nothing at all the empty state takes the middle, '
        'under Add digest', (tester) async {
      EventDigests.updateCache(const []);
      tallSurface(tester);
      await pumpHub(tester, () => const []);

      expect(byId(SemanticsIds.alertsDigestAdd), findsOneWidget);
      final icon = tester.getCenter(
        find.byIcon(Icons.notifications_none_rounded),
      );
      expect(icon.dy, greaterThan(1800 / 3));
    });
  });
}
