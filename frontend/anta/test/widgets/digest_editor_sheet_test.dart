import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/digest_planner.dart';
import 'package:anta/widgets/digest_editor_sheet.dart';

import '../database/support/db_test_support.dart';
import 'support/digest_sheet_robot.dart';

class _Outcome {
  DigestEditorResult? result;
  bool returned = false;
}

/// The digest sheet through [DigestSheetRobot]: what each row reads back,
/// what Save, Delete and ✕ hand to the caller, and the caption that says
/// what the draft would do — planned from the caller's events.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const surface = Size(800, 1400);

  late Directory tempDir;
  late AppDatabase db;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_digest_sheet');
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
    SettingsService.reset();
    db = await openTestDatabase();
    // The time pad reads its haptics setting.
    SettingsService.forTesting(db);
    CalendarCategories.updateCache([
      for (final (i, (id, name)) in const [
        ('birthday', 'Birthdays'),
        ('gym', 'Gym'),
        ('work', 'Work'),
      ].indexed)
        CalendarCategory(
          id: id,
          name: name,
          colorValue: 0xFFD81B60,
          iconKey: 'event',
          sortOrder: i,
          isBuiltIn: false,
        ),
    ]);
    EventDigests.updateCache(const []);
  });

  tearDown(() async {
    CalendarCategories.updateCache(const []);
    EventDigests.resetCache();
    SettingsService.reset();
    await db.close();
  });

  const birthdays = EventDigest(
    id: 'd1',
    name: 'Birthdays',
    categoryIds: {'birthday'},
    sortOrder: 4,
  );

  /// Every day, in Birthdays — one occurrence on any span's every day.
  final daily = CalendarEvent(
    id: 'e1',
    title: 'Ana',
    categoryId: 'birthday',
    startDate: DateTime.utc(2020, 1, 1),
    rule: const DailyRecurrence(),
  );

  Future<_Outcome> open(
    WidgetTester tester, {
    EventDigest? initial,
    List<CalendarEvent> events = const [],
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    Locale locale = const Locale('en'),
    TextScaler textScaler = TextScaler.noScaling,
    Size size = surface,
    // The sheet's own default; a caption case passes a fixed clock.
    DateTime Function() now = DateTime.now,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                outcome.result = await DigestEditorSheet.show(
                  context,
                  initial: initial,
                  events: events,
                  weekStart: weekStart,
                  now: now,
                );
                outcome.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  }

  EventDigest savedFrom(_Outcome outcome) {
    expect(outcome.returned, isTrue);
    final result = outcome.result;
    expect(result, isA<DigestEditorSaved>());
    return (result as DigestEditorSaved).digest;
  }

  testWidgets('a new digest opens on the defaults, with no Delete', (
    tester,
  ) async {
    await open(tester);
    final robot = DigestSheetRobot(tester);

    expect(find.text('New digest'), findsOneWidget);
    expect(robot.categoriesValue, 'Events');
    expect(robot.nameHint, 'Events');
    expect(robot.cadenceValue, 'Month');
    expect(robot.anchorValue, '1st');
    expect(robot.timeValue, '9:00 AM');
    expect(robot.leadValue, 'From that day');
    expect(robot.includeEmpty, isFalse);
    expect(robot.hasDelete, isFalse);
  });

  testWidgets('the categories row and the hint name the allowlist: none, '
      'one, several', (tester) async {
    for (final (ids, label) in const [
      (<String>{}, 'Events'),
      ({'birthday'}, 'Birthdays'),
      ({'birthday', 'gym', 'work'}, '3 categories'),
    ]) {
      await open(
        tester,
        initial: EventDigest(id: 'd1', categoryIds: ids),
      );
      final robot = DigestSheetRobot(tester);
      expect(robot.categoriesValue, label);
      expect(robot.nameHint, label);
      await robot.close();
      expect(robot.isOpen, isFalse);
    }
  });

  group('the On row', () {
    testWidgets('weekly: seven weekdays from the week start, the pick saved', (
      tester,
    ) async {
      final outcome = await open(tester, weekStart: CalendarWeekStart.sunday);
      final robot = DigestSheetRobot(tester);

      await robot.pickCadence(DigestCadence.weekly);
      expect(robot.cadenceValue, 'Week');
      expect(robot.anchorValue, 'Monday');
      expect(await robot.anchorChoices(), [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ]);
      await robot.pickAnchor(DateTime.friday);
      expect(robot.anchorValue, 'Friday');

      await robot.save();
      final saved = savedFrom(outcome);
      expect(saved.cadence, DigestCadence.weekly);
      expect(saved.anchor, DateTime.friday);
    });

    testWidgets('monthly: the 1st to the 28th, the pick saved', (tester) async {
      final outcome = await open(tester);
      final robot = DigestSheetRobot(tester);

      final choices = await robot.anchorChoices();
      expect(choices, hasLength(EventDigest.lastMonthAnchor));
      expect(choices.take(4), ['1st', '2nd', '3rd', '4th']);
      expect(choices.sublist(20, 23), ['21st', '22nd', '23rd']);
      expect(choices.last, '28th');

      await robot.pickAnchor(15);
      expect(robot.anchorValue, '15th');

      await robot.save();
      expect(savedFrom(outcome).anchor, 15);
    });

    testWidgets('daily: no row at all, and the weekly pick comes back', (
      tester,
    ) async {
      final outcome = await open(tester);
      final robot = DigestSheetRobot(tester);
      await robot.pickCadence(DigestCadence.weekly);
      await robot.pickAnchor(DateTime.wednesday);

      await robot.pickCadence(DigestCadence.daily);
      expect(robot.cadenceValue, 'Day');
      expect(robot.hasAnchor, isFalse);

      await robot.pickCadence(DigestCadence.weekly);
      expect(robot.anchorValue, 'Wednesday');

      await robot.pickCadence(DigestCadence.daily);
      await robot.save();
      final saved = savedFrom(outcome);
      expect(saved.cadence, DigestCadence.daily);
      expect(saved.anchor, 0);
    });
  });

  group('the Shows row', () {
    testWidgets('offers upcoming and the two reports, Upcoming on a new '
        'digest', (tester) async {
      await open(tester);
      final robot = DigestSheetRobot(tester);

      expect(robot.showsValue, 'Upcoming');
      expect(await robot.showsChoices(), [
        'Upcoming',
        'The week just ended',
        'The month just ended',
      ]);
      expect(robot.cadenceEnabled, isTrue);
      expect(robot.leadEnabled, isTrue);
    });

    testWidgets('a report dims Every at its implied cadence and Covers, in '
        'place; Upcoming brings back the cadence it had', (tester) async {
      await open(tester);
      final robot = DigestSheetRobot(tester);
      await robot.pickCadence(DigestCadence.daily);

      await robot.pickShows('week-report');
      expect(robot.showsValue, 'The week just ended');
      expect(robot.cadenceValue, 'Week');
      expect(robot.cadenceEnabled, isFalse);
      expect(robot.leadEnabled, isFalse);
      expect(robot.hasAnchor, isTrue);

      await robot.pickShows('month-report');
      expect(robot.cadenceValue, 'Month');
      expect(robot.cadenceEnabled, isFalse);
      expect(robot.leadEnabled, isFalse);

      await robot.pickShows('upcoming');
      expect(robot.showsValue, 'Upcoming');
      expect(robot.cadenceValue, 'Day');
      expect(robot.cadenceEnabled, isTrue);
      expect(robot.leadEnabled, isTrue);
      expect(robot.hasAnchor, isFalse);
    });

    testWidgets('a week report fires on a weekday from the week start, a '
        'month report on a day of the month', (tester) async {
      await open(tester, weekStart: CalendarWeekStart.sunday);
      final robot = DigestSheetRobot(tester);

      await robot.pickShows('week-report');
      // Entered from Upcoming: the week's first day (D45).
      expect(robot.anchorValue, 'Sunday');
      expect(await robot.anchorChoices(), [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ]);

      await robot.pickShows('month-report');
      expect(robot.anchorValue, '1st');
      final days = await robot.anchorChoices();
      expect(days, hasLength(EventDigest.lastMonthAnchor));
      expect(days.first, '1st');
    });

    testWidgets('Save hands back a week report with its weekday and time', (
      tester,
    ) async {
      final outcome = await open(tester);
      final robot = DigestSheetRobot(tester);

      await robot.pickShows('week-report');
      await robot.pickAnchor(DateTime.sunday);
      await robot.pickTime(const TimeOfDay(hour: 8, minute: 0));
      await robot.save();

      final saved = savedFrom(outcome);
      expect(saved.cadence, DigestCadence.weeklyReport);
      expect(saved.anchor, DateTime.sunday);
      expect(saved.minute, 8 * 60);
    });

    testWidgets('entered from an upcoming weekly digest, the week report '
        "fires on the week's first day, and Upcoming keeps its own weekday "
        '(D45)', (tester) async {
      final outcome = await open(
        tester,
        initial: const EventDigest(
          id: 'd1',
          cadence: DigestCadence.weekly,
          anchor: DateTime.sunday,
        ),
      );
      final robot = DigestSheetRobot(tester);
      expect(robot.anchorValue, 'Sunday');

      await robot.pickShows('week-report');
      expect(robot.anchorValue, 'Monday');

      await robot.pickShows('upcoming');
      expect(robot.cadenceValue, 'Week');
      expect(robot.anchorValue, 'Sunday');

      await robot.pickShows('week-report');
      await robot.save();
      final saved = savedFrom(outcome);
      expect(saved.cadence, DigestCadence.weeklyReport);
      expect(saved.anchor, DateTime.monday);
    });

    testWidgets('an edited week report keeps its weekday through the other '
        'Shows (D45)', (tester) async {
      final outcome = await open(
        tester,
        initial: const EventDigest(
          id: 'r1',
          cadence: DigestCadence.weeklyReport,
          anchor: DateTime.saturday,
        ),
      );
      final robot = DigestSheetRobot(tester);

      await robot.pickShows('month-report');
      await robot.pickShows('week-report');
      expect(robot.anchorValue, 'Saturday');
      await robot.pickShows('upcoming');
      await robot.pickShows('week-report');
      expect(robot.anchorValue, 'Saturday');

      await robot.save();
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull, reason: 'the draft is as it came');
    });

    testWidgets('under a report Every and Covers are disabled where they '
        'stand: 38 %, marked so, no tap, the same height', (tester) async {
      await open(tester);
      final robot = DigestSheetRobot(tester);
      const rows = [SemanticsIds.digestCadence, SemanticsIds.digestLead];
      final heights = {for (final id in rows) id: robot.rowHeight(id)};
      for (final id in rows) {
        expect(robot.rowOpacity(id), isNot(FormMetrics.disabledOpacity));
        final data = robot.rowSemantics(id);
        expect(
          data.flagsCollection.isEnabled,
          isNot(Tristate.isFalse),
          reason: id,
        );
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: id);
      }

      await robot.pickShows('week-report');

      for (final id in rows) {
        expect(robot.rowOpacity(id), FormMetrics.disabledOpacity, reason: id);
        final data = robot.rowSemantics(id);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse, reason: id);
        expect(data.hasAction(SemanticsAction.tap), isFalse, reason: id);
        expect(robot.rowHeight(id), heights[id], reason: id);
      }
      // A tap opens no menu.
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.digestCadence));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.digestCadenceItem(DigestCadence.daily.name),
        ),
        findsNothing,
      );
    });

    testWidgets('a report opened from the caller keeps its anchor; an '
        'unchanged Save hands back nothing (D43)', (tester) async {
      for (final (initial, shows, anchor) in const [
        (
          EventDigest(
            id: 'r1',
            cadence: DigestCadence.weeklyReport,
            anchor: DateTime.saturday,
            minute: 8 * 60,
          ),
          'The week just ended',
          'Saturday',
        ),
        (
          EventDigest(
            id: 'r2',
            cadence: DigestCadence.monthlyReport,
            anchor: 15,
            minute: 8 * 60,
          ),
          'The month just ended',
          '15th',
        ),
      ]) {
        final outcome = await open(tester, initial: initial);
        final robot = DigestSheetRobot(tester);

        expect(robot.showsValue, shows);
        expect(robot.anchorValue, anchor);
        expect(robot.cadenceEnabled, isFalse);

        await robot.save();
        expect(outcome.returned, isTrue);
        expect(outcome.result, isNull);
      }
    });

    testWidgets('a draft without an id is a new digest: Save hands it back '
        'unchanged', (tester) async {
      const draft = EventDigest(
        id: '',
        cadence: DigestCadence.weeklyReport,
        anchor: DateTime.monday,
        minute: 8 * 60,
        categoryIds: {'gym'},
      );
      final outcome = await open(tester, initial: draft);
      final robot = DigestSheetRobot(tester);

      expect(find.text('New digest'), findsOneWidget);
      expect(robot.hasDelete, isFalse);
      expect(robot.showsValue, 'The week just ended');
      expect(robot.categoriesValue, 'Gym');

      await robot.save();
      expect(savedFrom(outcome), draft);
    });

    testWidgets('Upcoming from a report opened by the caller is weekly', (
      tester,
    ) async {
      await open(
        tester,
        initial: const EventDigest(
          id: 'r1',
          cadence: DigestCadence.monthlyReport,
        ),
      );
      final robot = DigestSheetRobot(tester);

      await robot.pickShows('upcoming');
      expect(robot.cadenceValue, 'Week');
    });

    testWidgets("the caption plans the report's span from the week start", (
      tester,
    ) async {
      const report = EventDigest(
        id: 'r1',
        cadence: DigestCadence.weeklyReport,
        anchor: DateTime.sunday,
        categoryIds: {'birthday'},
      );
      // Wednesday 14 October 2026, noon: the fires are Sunday the 18th and
      // the 25th at 09:00.
      DateTime clock() => DateTime(2026, 10, 14, 12);
      // Saturday the 17th: in the Sunday-start week the 18th reports on,
      // in the Monday-start week of the 25th only.
      final saturday = CalendarEvent(
        id: 'e2',
        title: 'Ana',
        categoryId: 'birthday',
        startDate: DateTime.utc(2026, 10, 17),
        rule: const OneTimeRecurrence(),
      );

      await open(
        tester,
        initial: report,
        events: [saturday],
        weekStart: CalendarWeekStart.sunday,
        now: clock,
      );
      expect(
        DigestSheetRobot(tester).caption,
        'Next: Sun, Oct 18 9:00 AM · 1 event last week',
      );
      await DigestSheetRobot(tester).close();

      await open(tester, initial: report, events: [saturday], now: clock);
      expect(
        DigestSheetRobot(tester).caption,
        'Next: Sun, Oct 25 9:00 AM · 1 event last week',
      );
    });

    for (final (locale, monthReport) in const [
      ('de', 'Der abgelaufene Monat'),
      ('en', 'The month just ended'),
    ]) {
      testWidgets('$locale at 200 % on 360 with a report Shows lays out '
          'clean; the caption slot holds its height (D45)', (tester) async {
        await open(
          tester,
          initial: birthdays,
          events: [daily],
          locale: Locale(locale),
          textScaler: const TextScaler.linear(2.0),
          size: const Size(360, 780),
        );
        final robot = DigestSheetRobot(tester);
        final height = robot.captionHeight;

        await robot.pickShows('month-report');
        expect(robot.showsValue, monthReport);
        expect(robot.captionHeight, height);
        await robot.pickShows('week-report');
        expect(robot.captionHeight, height);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the time, the lead and the empty switch reach the draft', (
    tester,
  ) async {
    final outcome = await open(tester);
    final robot = DigestSheetRobot(tester);

    await robot.pickTime(const TimeOfDay(hour: 20, minute: 30));
    expect(robot.timeValue, '8:30 PM');
    await robot.pickLead(1);
    expect(robot.leadValue, 'From the next day');
    await robot.toggleIncludeEmpty();
    expect(robot.includeEmpty, isTrue);

    await robot.save();
    final saved = savedFrom(outcome);
    expect(saved.minute, 20 * 60 + 30);
    expect(saved.leadDays, 1);
    expect(saved.includeEmpty, isTrue);
  });

  testWidgets('the caption counts the next span over the caller\'s events; '
      'it changes text, never height', (tester) async {
    await open(
      tester,
      initial: const EventDigest(
        id: 'd1',
        cadence: DigestCadence.daily,
        anchor: 0,
        categoryIds: {'birthday'},
      ),
      events: [daily],
    );
    final robot = DigestSheetRobot(tester);

    expect(robot.caption, startsWith('Next: '));
    expect(robot.caption, endsWith(' · 1 event today'));
    final height = robot.captionHeight;

    await robot.pickLead(1);
    expect(robot.caption, endsWith(' · 1 event tomorrow'));
    expect(robot.captionHeight, height);

    await robot.pickCadence(DigestCadence.weekly);
    expect(robot.caption, matches(RegExp(r' · 7 events (next week|from .+)$')));
    expect(robot.captionHeight, height);
  });

  testWidgets('the caption skips a fire that would send nothing, as the '
      'planner does with Also when empty off', (tester) async {
    const monthly = EventDigest(id: 'd1', categoryIds: {'birthday'});
    DateTime clock() => DateTime(2026, 10, 14, 12);
    final fires = DigestPlanner.nextFireInstants(
      monthly,
      now: clock(),
      count: 2,
    );
    final second = fires[1];
    // One birthday, in the second fire's month only.
    final event = CalendarEvent(
      id: 'e2',
      title: 'Ana',
      categoryId: 'birthday',
      startDate: DateTime.utc(second.year, second.month, 10),
      rule: const OneTimeRecurrence(),
    );
    await open(tester, initial: monthly, events: [event], now: clock);
    final robot = DigestSheetRobot(tester);

    expect(
      robot.caption,
      startsWith('Next: ${DateFormat.MMMEd('en').format(second)} '),
    );
    expect(robot.caption, endsWith(' · 1 event this month'));

    // Nothing in any of the next twelve months for another category.
    await robot.pickCategories(ticked: const {'gym'});
    expect(robot.caption, 'Nothing to send yet');

    await robot.toggleIncludeEmpty();
    expect(
      robot.caption,
      startsWith('Next: ${DateFormat.MMMEd('en').format(fires.first)} '),
    );
    expect(robot.caption, endsWith(' · No events this month'));
  });

  for (final locale in const [Locale('de'), Locale('ro')]) {
    testWidgets('the caption slot keeps its height through the picks '
        '(${locale.languageCode}, 200 %, 360 wide)', (tester) async {
      await open(
        tester,
        initial: birthdays,
        events: [daily],
        locale: locale,
        textScaler: const TextScaler.linear(2.0),
        size: const Size(360, 780),
      );
      final robot = DigestSheetRobot(tester);
      final height = robot.captionHeight;

      await robot.pickAnchor(15);
      expect(robot.captionHeight, height);
      await robot.pickCadence(DigestCadence.weekly);
      expect(robot.captionHeight, height);
      expect(tester.takeException(), isNull);
    });
  }

  group('the categories picker', () {
    testWidgets('every row ticked, or none, is every category', (tester) async {
      final outcome = await open(tester, initial: birthdays);
      final robot = DigestSheetRobot(tester);

      await robot.pickCategories(all: true);
      expect(robot.categoriesValue, 'Events');
      await robot.pickCategories(ticked: const {'gym'});
      expect(robot.categoriesValue, 'Gym');
      await robot.pickCategories();
      expect(robot.categoriesValue, 'Events');

      await robot.save();
      expect(savedFrom(outcome).categoryIds, isEmpty);
    });

    testWidgets('a subset is kept as it was ticked', (tester) async {
      final outcome = await open(tester);
      final robot = DigestSheetRobot(tester);

      await robot.pickCategories(ticked: const {'birthday', 'work'});
      expect(robot.categoriesValue, '2 categories');

      await robot.save();
      expect(savedFrom(outcome).categoryIds, {'birthday', 'work'});
    });
  });

  testWidgets('Save hands a new digest back without an id, on', (tester) async {
    final outcome = await open(tester);
    final robot = DigestSheetRobot(tester);
    await robot.enterName('  Week ahead ');

    await robot.save();

    final saved = savedFrom(outcome);
    // The service mints the id and the position on create.
    expect(saved.id, isEmpty);
    expect(saved.name, 'Week ahead');
    expect(saved.enabled, isTrue);
  });

  testWidgets('Save on an edit that changed nothing hands back nothing', (
    tester,
  ) async {
    final outcome = await open(tester, initial: birthdays);

    await DigestSheetRobot(tester).save();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('an edit keeps its id, its switch and its place', (tester) async {
    final outcome = await open(
      tester,
      initial: birthdays.copyWith(enabled: false),
    );
    final robot = DigestSheetRobot(tester);
    expect(find.text('Edit digest'), findsOneWidget);

    await robot.pickLead(1);
    await robot.save();

    expect(savedFrom(outcome), birthdays.copyWith(enabled: false, leadDays: 1));
  });

  testWidgets('a new digest past the cap is refused and the sheet stays', (
    tester,
  ) async {
    EventDigests.updateCache(
      List.unmodifiable([
        for (var i = 0; i < 10; i++) EventDigest(id: 'd$i', sortOrder: i),
      ]),
    );
    final outcome = await open(tester);
    final robot = DigestSheetRobot(tester);

    await robot.save();

    expect(find.text('You can keep up to 10 digests'), findsOneWidget);
    expect(robot.isOpen, isTrue);
    expect(outcome.returned, isFalse);
  });

  testWidgets('Delete asks, then hands the id back; a cancel stays', (
    tester,
  ) async {
    final outcome = await open(tester, initial: birthdays);
    final robot = DigestSheetRobot(tester);
    expect(robot.hasDelete, isTrue);

    await robot.delete(confirm: false);
    expect(robot.isOpen, isTrue);
    expect(outcome.returned, isFalse);

    await robot.delete();
    expect(outcome.returned, isTrue);
    expect(outcome.result, isA<DigestEditorDeleted>());
    expect((outcome.result! as DigestEditorDeleted).id, 'd1');
  });

  testWidgets('a clean ✕ closes at once with nothing', (tester) async {
    final outcome = await open(tester, initial: birthdays);
    final robot = DigestSheetRobot(tester);

    await robot.close();

    expect(robot.isAskingToDiscard, isFalse);
    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('a dirty ✕ asks; Keep editing stays, Discard leaves', (
    tester,
  ) async {
    final outcome = await open(tester, initial: birthdays);
    final robot = DigestSheetRobot(tester);
    await robot.toggleIncludeEmpty();

    await robot.close();
    expect(robot.isAskingToDiscard, isTrue);
    await robot.keepEditing();
    expect(robot.isOpen, isTrue);
    expect(robot.includeEmpty, isTrue);

    await robot.close();
    await robot.discard();
    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('back and the scrim leave through the same guard', (
    tester,
  ) async {
    final outcome = await open(tester, initial: birthdays);
    final robot = DigestSheetRobot(tester);
    await robot.toggleIncludeEmpty();

    await robot.systemBack();
    expect(robot.isAskingToDiscard, isTrue);
    await robot.keepEditing();
    await robot.tapBarrier();
    expect(robot.isAskingToDiscard, isTrue);
    await robot.keepEditing();
    expect(robot.isOpen, isTrue);

    // Clean again: back closes at once.
    await robot.toggleIncludeEmpty();
    await robot.systemBack();
    expect(robot.isAskingToDiscard, isFalse);
    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('a clean scrim tap closes at once', (tester) async {
    final outcome = await open(tester, initial: birthdays);

    await DigestSheetRobot(tester).tapBarrier();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('German at 200 % on a 360-wide phone lays out clean', (
    tester,
  ) async {
    await open(
      tester,
      initial: birthdays,
      events: [daily],
      locale: const Locale('de'),
      textScaler: const TextScaler.linear(2.0),
      size: const Size(360, 780),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Zusammenfassung bearbeiten'), findsOneWidget);
    expect(DigestSheetRobot(tester).anchorValue, '1.');
  });
}
