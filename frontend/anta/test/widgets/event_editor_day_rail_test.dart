import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/day_rail_resolver.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';

/// The rail's per-event override is a **tri-state** column, and `null` is the
/// interesting third state: it means *auto* (follow presence tracking), which
/// is what let the v34 column ship with no backfill.
///
/// So the assertions that matter are the ones a plain bool would get wrong:
/// Auto persists as NULL rather than as `false`, the control is gated exactly
/// where the membership predicate is, and an event the predicate can never
/// admit is not offered the choice at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;
  late AppDatabase settingsDb;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_rail');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
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
    // The control is gated on the rail actually being drawn, so every test
    // that expects to see it has to turn the rail on first — the gate is the
    // point, and `withRailOff` below asserts the other side of it.
    await (await SettingsService.getInstance()).setCalendarDayRailStyle(
      DayRailStyle.line,
    );
  });

  tearDown(() async {
    await barBloc.close();
    SettingsService.reset();
    await settingsDb.close();
  });

  CalendarEvent event({
    required RecurrenceRule rule,
    bool tracksPresence = true,
    bool? showInDayRail,
  }) => CalendarEvent(
    id: 'e1',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 20),
    rule: rule,
    tracksPresence: tracksPresence,
    showInDayRail: showInDayRail,
  );

  /// Opens the sheet on a real route, so Save pops a result instead of
  /// tearing down the test's own home page. The returned list holds the
  /// result once the route is gone.
  Future<List<EventEditorResult?>> open(
    WidgetTester tester,
    CalendarEvent initial,
  ) async {
    final results = <EventEditorResult?>[];
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
                  defaultDate: DateTime.utc(2026, 8, 20),
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

  Future<CalendarEvent> saveAnd(
    WidgetTester tester,
    List<EventEditorResult?> results,
  ) async {
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    return (results.single as EventEditorSaved).event;
  }

  /// The rail control, found by its own segment labels. Scoped rather than
  /// matched on text alone: the retroactive-scope chips higher up the sheet
  /// also say "Always", so a bare `find.text` matches two.
  final railControl = find.byWidgetPredicate(
    (w) =>
        w is SegmentedButton &&
        w.segments.any(
          (s) => s.label is Text && (s.label as Text).data == 'Auto',
        ),
  );

  Future<void> pick(WidgetTester tester, String label) async {
    final segment = find.descendant(
      of: railControl,
      matching: find.text(label),
    );
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();
  }

  testWidgets('a recurring event offers all three positions', (tester) async {
    await open(tester, event(rule: const DailyRecurrence()));

    expect(railControl, findsOneWidget);
    for (final label in ['Auto', 'Always', 'Never']) {
      expect(
        find.descendant(of: railControl, matching: find.text(label)),
        findsOneWidget,
      );
    }
  });

  testWidgets('a one-time event is not offered the control at all', (
    tester,
  ) async {
    await open(tester, event(rule: const OneTimeRecurrence()));

    // The membership predicate excludes one-time rules whatever the column
    // says, so offering the choice here would be offering a no-op.
    expect(railControl, findsNothing);
  });

  testWidgets('with the rail switched off the control is not offered', (
    tester,
  ) async {
    await (await SettingsService.getInstance()).setCalendarDayRailStyle(
      DayRailStyle.none,
    );

    await open(tester, event(rule: const DailyRecurrence()));

    // The second gate, and the same argument as the first: the rail is
    // opt-in and off by default, so on a stock install this control would
    // steer a channel that paints nothing anywhere in the app.
    expect(railControl, findsNothing);
  });

  testWidgets('an override already stored survives the rail being off', (
    tester,
  ) async {
    await (await SettingsService.getInstance()).setCalendarDayRailStyle(
      DayRailStyle.none,
    );
    final results = await open(
      tester,
      event(rule: const DailyRecurrence(), showInDayRail: false),
    );

    final saved = await saveAnd(tester, results);

    // Hiding the control must not quietly reset what it controls — the user
    // gets their "Never" back the moment they switch the rail on again.
    expect(saved.showInDayRail, isFalse);
  });

  testWidgets('an untouched event saves NULL, not false', (tester) async {
    final results = await open(tester, event(rule: const DailyRecurrence()));

    final saved = await saveAnd(tester, results);

    // The whole point of the tri-state: opening and saving an event must not
    // freeze today's auto answer into an explicit one.
    expect(saved.showInDayRail, isNull);
    expect(eventInDayRail(saved), isTrue);
  });

  testWidgets('Always forces an untracked event onto the rail', (tester) async {
    final untracked = event(
      rule: const DailyRecurrence(),
      tracksPresence: false,
    );
    // Auto would leave it off: nothing else in the form puts it on.
    expect(eventInDayRail(untracked), isFalse);
    final results = await open(tester, untracked);

    await pick(tester, 'Always');
    final saved = await saveAnd(tester, results);

    expect(saved.showInDayRail, isTrue);
    expect(eventInDayRail(saved), isTrue);
  });

  testWidgets('Never overrides presence tracking', (tester) async {
    final results = await open(tester, event(rule: const DailyRecurrence()));

    await pick(tester, 'Never');
    final saved = await saveAnd(tester, results);

    expect(saved.showInDayRail, isFalse);
    expect(eventInDayRail(saved), isFalse);
  });

  testWidgets('back to Auto clears the column rather than writing false', (
    tester,
  ) async {
    final results = await open(
      tester,
      event(rule: const DailyRecurrence(), showInDayRail: false),
    );

    await pick(tester, 'Auto');
    final saved = await saveAnd(tester, results);

    // `copyWith` cannot express "set this nullable field to null" without the
    // clear flag, so a naive save would leave the old `false` in place.
    expect(saved.showInDayRail, isNull);
    expect(eventInDayRail(saved), isTrue);
  });

  test('Always still cannot admit a one-time event', () {
    // The control is hidden for these, but a row can carry `true` from back
    // when the event was recurring — the predicate is what keeps it out.
    expect(
      eventInDayRail(
        CalendarEvent(
          id: 'e1',
          title: 'Gym',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 8, 20),
          rule: const OneTimeRecurrence(),
          showInDayRail: true,
        ),
      ),
      isFalse,
    );
  });
}
