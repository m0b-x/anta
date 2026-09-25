import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';

/// The editor is a **draft** surface for alerts exactly as it is for skips:
/// nothing is written, the set rides the result, and the page dispatches it.
///
/// What the UI cannot show you, and what this pins: a new event carries no
/// alert unless the settings name a default to seed it from, and an existing
/// one reads the facade; the remove switch
/// is offered only where it can take effect — a one-time event with something
/// that rings — and is cleared on save wherever it cannot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;
  late AppDatabase settingsDb;

  final startDate = DateTime.utc(2026, 9, 20);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_alerts');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await initializeDateFormatting('en');
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final barService = await MarkdownBarService.getInstance();
    barBloc = MarkdownBarBloc(barService: barService);
    SettingsService.reset();
    settingsDb = await openTestDatabase();
    SettingsService.forTesting(settingsDb);
  });

  tearDown(() async {
    await barBloc.close();
    EventAlerts.resetCache();
    SettingsService.reset();
    await settingsDb.close();
  });

  CalendarEvent eventOf({
    RecurrenceRule rule = const OneTimeRecurrence(),
    bool removeAfterAlert = false,
  }) => CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: startDate,
    rule: rule,
    time: const EventTime(startMinute: 18 * 60),
    removeAfterAlert: removeAfterAlert,
  );

  Future<List<EventEditorResult?>> open(
    WidgetTester tester, {
    CalendarEvent? initial,
  }) async {
    final results = <EventEditorResult?>[];
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    Navigator.of(hostContext)
        .push<EventEditorResult>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: BlocProvider<MarkdownBarBloc>.value(
                value: barBloc,
                child: EventEditorSheet(
                  defaultDate: startDate,
                  initialEvent: initial,
                ),
              ),
            ),
          ),
        )
        .then(results.add);
    await tester.pumpAndSettle();
    return results;
  }

  /// Save is gated on a title, so a brand-new event has to be given one
  /// before anything about its alerts can be reported.
  Future<void> typeTitle(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'Leg day');
    await tester.pumpAndSettle();
  }

  Future<EventEditorSaved> saveAnd(
    WidgetTester tester,
    List<EventEditorResult?> results,
  ) async {
    final save = find.byType(FilledButton).first;
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    return results.single as EventEditorSaved;
  }

  // Alerts are opt-in: as the app ships, a new event carries none.
  testWidgets('a new event starts with no alert as shipped', (tester) async {
    final results = await open(tester);

    expect(find.text('On the day, 09:00'), findsNothing);
    await typeTitle(tester);
    final saved = await saveAnd(tester, results);
    expect(saved.alerts, isEmpty);
  });

  // A brand-new event starts **all day** (`initialEvent == null` means no
  // time), so the seed it gets is the all-day default, not the timed one.
  testWidgets('a new event is seeded from the all-day default', (tester) async {
    await (await SettingsService.getInstance()).setAlertDefaultAllDay((
      mode: AlertMode.notify,
      daysBefore: 0,
      dayMinute: 9 * 60,
    ));

    final results = await open(tester);

    expect(find.text('On the day, 09:00'), findsOneWidget);

    await typeTitle(tester);
    final saved = await saveAnd(tester, results);
    expect(saved.alerts, hasLength(1));
    expect(saved.alerts!.single.daysBefore, 0);
    expect(saved.alerts!.single.dayMinute, 9 * 60);
    expect(saved.alerts!.single.mode, AlertMode.notify);
  });

  testWidgets('a default of none seeds nothing', (tester) async {
    await (await SettingsService.getInstance()).setAlertDefaultAllDay(null);

    final results = await open(tester);

    expect(find.text('On the day, 09:00'), findsNothing);
    await typeTitle(tester);
    final saved = await saveAnd(tester, results);
    expect(saved.alerts, isEmpty);
  });

  testWidgets('an existing event shows what the facade holds', (tester) async {
    EventAlerts.updateCache(
      byEvent: {
        'e1': List<EventAlert>.unmodifiable(const [
          EventAlert(
            id: 'a1',
            eventId: 'e1',
            mode: AlertMode.ring,
            offsetMinutes: 0,
          ),
        ]),
      },
    );

    final results = await open(tester, initial: eventOf());

    expect(find.text('At start'), findsOneWidget);
    expect(find.text('Alarm'), findsOneWidget);

    final saved = await saveAnd(tester, results);
    expect(saved.alerts!.single.id, 'a1');
  });

  testWidgets('the remove switch needs an alarm, and rides the event', (
    tester,
  ) async {
    final results = await open(tester, initial: eventOf());

    // Seeded with nothing that rings: no switch.
    expect(find.text('Remove after it rings'), findsNothing);

    EventAlerts.resetCache();
    await tester.ensureVisible(find.text('Add alert'));
    await tester.tap(find.text('Add alert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alarm'));
    await tester.pumpAndSettle();
    // Two Saves on screen while the alert sheet is up — the form's and the
    // sheet's — so this one is addressed through the sheet that owns it.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertEditorSheet),
        matching: find.widgetWithText(FilledButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    final removeSwitch = find.text('Remove after it rings');
    await tester.ensureVisible(removeSwitch);
    expect(removeSwitch, findsOneWidget);
    await tester.tap(removeSwitch);
    await tester.pumpAndSettle();

    final saved = await saveAnd(tester, results);
    expect(saved.event.removeAfterAlert, isTrue);
    expect(saved.alerts!.where((a) => a.isAlarm), hasLength(1));
  });

  testWidgets('a recurring event never persists the removal flag', (
    tester,
  ) async {
    EventAlerts.updateCache(
      byEvent: {
        'e1': List<EventAlert>.unmodifiable(const [
          EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
        ]),
      },
    );

    final results = await open(
      tester,
      initial: eventOf(rule: const DailyRecurrence(), removeAfterAlert: true),
    );

    expect(find.text('Remove after it rings'), findsNothing);
    final saved = await saveAnd(tester, results);
    expect(saved.event.removeAfterAlert, isFalse);
  });

  testWidgets('removing the last alert clears the flag on save', (
    tester,
  ) async {
    EventAlerts.updateCache(
      byEvent: {
        'e1': List<EventAlert>.unmodifiable(const [
          EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
        ]),
      },
    );

    final results = await open(
      tester,
      initial: eventOf(removeAfterAlert: true),
    );

    await tester.ensureVisible(find.byTooltip('Remove alert'));
    await tester.tap(find.byTooltip('Remove alert'));
    await tester.pumpAndSettle();

    final saved = await saveAnd(tester, results);
    expect(saved.alerts, isEmpty);
    expect(saved.event.removeAfterAlert, isFalse);
  });

  testWidgets('the add chip disappears at the cap', (tester) async {
    EventAlerts.updateCache(
      byEvent: {
        'e1': List<EventAlert>.unmodifiable([
          for (var i = 0; i < kMaxAlertsPerEvent; i++)
            EventAlert(id: 'a$i', eventId: 'e1', offsetMinutes: (i + 1) * 5),
        ]),
      },
    );

    await open(tester, initial: eventOf());

    expect(find.text('Add alert'), findsNothing);
  });

  testWidgets('an all-day event is described in days', (tester) async {
    EventAlerts.updateCache(
      byEvent: {
        'e1': List<EventAlert>.unmodifiable(const [
          EventAlert(
            id: 'a1',
            eventId: 'e1',
            offsetMinutes: 10,
            daysBefore: 1,
            dayMinute: 9 * 60,
          ),
        ]),
      },
    );

    await open(
      tester,
      initial: CalendarEvent(
        id: 'e1',
        title: 'Birthday',
        categoryId: 'other',
        startDate: startDate,
        rule: const OneTimeRecurrence(),
      ),
    );

    expect(find.text('The day before, 09:00'), findsOneWidget);
  });
}
