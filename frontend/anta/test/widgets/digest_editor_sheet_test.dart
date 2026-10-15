import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_digests.dart';
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
    final fires = DigestPlanner.nextFireInstants(
      monthly,
      now: DateTime.now(),
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
    await open(tester, initial: monthly, events: [event]);
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
