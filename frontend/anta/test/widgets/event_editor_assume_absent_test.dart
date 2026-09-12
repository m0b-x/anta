import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';

/// The v37 presence default in the editor, where it is **two** controls with
/// one meaning: a segmented pick that inverts what an unmarked day says, and a
/// from-date that keeps the inversion off the history the event already has.
///
/// The assertions that matter are the ones the UI cannot show you. The
/// from-date is seeded exactly once — on the transition of a **saved**
/// assume-present event — so an event already on the inverted default keeps
/// whatever boundary it has, including none; re-seeding it would silently
/// cut off history every time the user toggled the control and changed their
/// mind. And both fields ride the opt-in they qualify: an event edited down to
/// one-time, or with tracking switched off, must persist neither, or a row
/// carries a default nothing will ever read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;
  late AppDatabase settingsDb;

  final startDate = DateTime.utc(2026, 8, 20);
  final occurrenceDay = DateTime.utc(2026, 8, 26);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_absent');
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
    SettingsService.reset();
    await settingsDb.close();
  });

  CalendarEvent event({
    RecurrenceRule rule = const DailyRecurrence(),
    bool tracksPresence = true,
    bool assumeAbsent = false,
    DateTime? assumeAbsentFrom,
  }) => CalendarEvent(
    id: 'e1',
    title: 'Gym',
    categoryId: 'gym',
    startDate: startDate,
    rule: rule,
    tracksPresence: tracksPresence,
    assumeAbsent: assumeAbsent,
    assumeAbsentFrom: assumeAbsentFrom,
  );

  /// Opens the sheet on a real route, so Save pops a result instead of
  /// tearing down the test's own home page. The returned list holds the
  /// result once the route is gone.
  Future<List<EventEditorResult?>> open(
    WidgetTester tester, {
    CalendarEvent? initial,
    DateTime? day,
  }) async {
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
                  defaultDate: startDate,
                  initialEvent: initial,
                  occurrenceDay: day,
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
    final save = find.byType(FilledButton).first;
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    return (results.single as EventEditorSaved).event;
  }

  /// The presence-default control, found by its own segment labels — the
  /// repeat-mode and retroactive-scope controls above it are `SegmentedButton`s
  /// too, so matching on the type alone matches three.
  final defaultControl = find.byWidgetPredicate(
    (w) =>
        w is SegmentedButton &&
        w.segments.any(
          (s) => s.label is Text && (s.label as Text).data == 'Assume absent',
        ),
  );

  // Located by its leading icon: the "Absent from" label is a section label
  // above the tile, not part of it, like every other picker in the form.
  final fromTile = find.ancestor(
    of: find.byIcon(Icons.event_repeat_rounded),
    matching: find.byType(ListTile),
  );

  Future<void> pick(WidgetTester tester, String label) async {
    final segment = find.descendant(
      of: defaultControl,
      matching: find.text(label),
    );
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String dateLabel(DateTime day) => DateFormat.yMMMMEEEEd('en').format(day);

  group('when the control is offered', () {
    testWidgets('a tracked recurring event gets both readings', (tester) async {
      await open(tester, initial: event());

      expect(defaultControl, findsOneWidget);
      for (final label in ['Assume present', 'Assume absent']) {
        expect(
          find.descendant(of: defaultControl, matching: find.text(label)),
          findsOneWidget,
        );
      }
      // The hint follows the selection, because the two segment labels say
      // what the setting is called and not what it does to a day.
      expect(
        find.text('Days count as attended unless you mark them missed.'),
        findsOneWidget,
      );
    });

    testWidgets('an untracked event is not offered it', (tester) async {
      await open(tester, initial: event(tracksPresence: false));

      // There are no unmarked days to reinterpret while nothing is tracked, so
      // the choice would be a no-op the row still has to store.
      expect(defaultControl, findsNothing);
    });

    testWidgets('a one-time event is not offered it', (tester) async {
      await open(tester, initial: event(rule: const OneTimeRecurrence()));

      // `EventPresence.appliesTo` excludes one-time rules whatever the columns
      // say — the same gate the Track-presence switch itself lives behind.
      expect(defaultControl, findsNothing);
    });

    testWidgets('the hint swaps with the selection', (tester) async {
      await open(tester, initial: event());

      await pick(tester, 'Assume absent');

      expect(
        find.text('Days count as missed until you mark them present.'),
        findsOneWidget,
      );
      expect(
        find.text('Days count as attended unless you mark them missed.'),
        findsNothing,
      );
    });
  });

  group('the from-date', () {
    testWidgets('is seeded with the occurrence the sheet was opened on', (
      tester,
    ) async {
      final results = await open(tester, initial: event(), day: occurrenceDay);

      await pick(tester, 'Assume absent');

      // The day the user came through is the one they meant: they are looking
      // at that occurrence's detail sheet when they decide the event has
      // stopped being attended by default.
      expect(fromTile, findsOneWidget);
      expect(find.text(dateLabel(occurrenceDay)), findsOneWidget);

      final saved = await saveAnd(tester, results);
      expect(saved.assumeAbsent, isTrue);
      expect(saved.assumeAbsentFromUtc, occurrenceDay);
    });

    testWidgets('falls back to today when no occurrence was opened', (
      tester,
    ) async {
      final results = await open(tester, initial: event());

      await pick(tester, 'Assume absent');
      final saved = await saveAnd(tester, results);

      // Not "start of event": flipping an existing event from the event list
      // still means *from now*, and a null would quietly rewrite its history.
      final now = DateTime.now();
      expect(saved.assumeAbsent, isTrue);
      expect(
        saved.assumeAbsentFromUtc,
        DateTime.utc(now.year, now.month, now.day),
      );
    });

    testWidgets('clears back to the whole event', (tester) async {
      final results = await open(tester, initial: event(), day: occurrenceDay);

      await pick(tester, 'Assume absent');
      final clear = find.descendant(
        of: fromTile,
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();

      expect(find.text('Start of event'), findsOneWidget);
      expect(find.text(dateLabel(occurrenceDay)), findsNothing);

      final saved = await saveAnd(tester, results);
      expect(saved.assumeAbsent, isTrue);
      expect(saved.assumeAbsentFrom, isNull);
    });

    testWidgets('a cleared boundary stays cleared across a toggle', (
      tester,
    ) async {
      final results = await open(tester, initial: event(), day: occurrenceDay);

      await pick(tester, 'Assume absent');
      final clear = find.descendant(
        of: fromTile,
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();

      // Changing your mind twice after an explicit clear must not bring the
      // seed back: the clear was a deliberate "whole event", and a boundary
      // that silently returns would be saved with no feedback at all.
      await pick(tester, 'Assume present');
      await pick(tester, 'Assume absent');

      expect(find.text('Start of event'), findsOneWidget);
      expect(find.text(dateLabel(occurrenceDay)), findsNothing);

      final saved = await saveAnd(tester, results);
      expect(saved.assumeAbsent, isTrue);
      expect(saved.assumeAbsentFrom, isNull);
    });

    testWidgets('an already-assume-absent event is never re-seeded', (
      tester,
    ) async {
      final results = await open(
        tester,
        initial: event(assumeAbsent: true),
        day: occurrenceDay,
      );

      // It opens on the inverted default already, covering the whole event.
      expect(find.text('Start of event'), findsOneWidget);

      // A round trip through the other segment must not invent a boundary:
      // the seed fires on the *saved* state, not on the widget's own history,
      // so changing your mind twice inside one session cannot cut the event's
      // past off behind you.
      await pick(tester, 'Assume present');
      await pick(tester, 'Assume absent');

      expect(find.text('Start of event'), findsOneWidget);
      expect(find.text(dateLabel(occurrenceDay)), findsNothing);

      final saved = await saveAnd(tester, results);
      expect(saved.assumeAbsent, isTrue);
      expect(saved.assumeAbsentFrom, isNull);
    });

    testWidgets('an existing boundary survives a round trip untouched', (
      tester,
    ) async {
      final stored = DateTime.utc(2026, 8, 22);
      final results = await open(
        tester,
        initial: event(assumeAbsent: true, assumeAbsentFrom: stored),
        day: occurrenceDay,
      );

      expect(find.text(dateLabel(stored)), findsOneWidget);

      await pick(tester, 'Assume present');
      await pick(tester, 'Assume absent');

      final saved = await saveAnd(tester, results);
      expect(saved.assumeAbsentFromUtc, stored);
    });

    testWidgets('a new event is never offered one', (tester) async {
      final results = await open(tester);

      await tester.enterText(find.byType(TextField).first, 'Gym');
      await tester.pumpAndSettle();
      await tapText(tester, 'Recurring');
      await tapText(tester, 'Track presence');
      await pick(tester, 'Assume absent');

      // A brand-new event has no history for a boundary to protect, and
      // offering one would only invite a date before the event exists.
      expect(find.text('Absent from'), findsNothing);

      final saved = await saveAnd(tester, results);
      expect(saved.assumeAbsent, isTrue);
      expect(saved.assumeAbsentFrom, isNull);
    });
  });

  group('the save mirror', () {
    testWidgets('an untouched tracked event saves false and no boundary', (
      tester,
    ) async {
      final results = await open(tester, initial: event());

      final saved = await saveAnd(tester, results);

      expect(saved.assumeAbsent, isFalse);
      expect(saved.assumeAbsentFrom, isNull);
    });

    testWidgets('switching tracking off clears both', (tester) async {
      final results = await open(
        tester,
        initial: event(assumeAbsent: true, assumeAbsentFrom: occurrenceDay),
      );

      await tapText(tester, 'Track presence');
      expect(defaultControl, findsNothing);
      final saved = await saveAnd(tester, results);

      expect(saved.tracksPresence, isFalse);
      expect(saved.assumeAbsent, isFalse);
      // `copyWith` cannot express "set this nullable field to null" without
      // the clear flag, so a naive save would leave the old date in place and
      // bring it back with the switch.
      expect(saved.assumeAbsentFrom, isNull);
    });

    testWidgets('a one-time rule cannot carry either field', (tester) async {
      // The row can hold both from back when the event was recurring; the
      // editor's gates are what stop them being written again.
      final results = await open(
        tester,
        initial: event(
          rule: const OneTimeRecurrence(),
          assumeAbsent: true,
          assumeAbsentFrom: occurrenceDay,
        ),
      );

      final saved = await saveAnd(tester, results);

      expect(saved.tracksPresence, isFalse);
      expect(saved.assumeAbsent, isFalse);
      expect(saved.assumeAbsentFrom, isNull);
    });
  });
}
