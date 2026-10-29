import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/pages/alarm_page.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';
import 'support/guide_try_card_robot.dart';
import 'support/practice_calendar_robot.dart';
import 'support/sandbox_write_log.dart';

/// The pages pushed — not the menus and sheets, which are popup routes — so
/// a test can say a card opened a page, or, as often, that it opened none.
class _PushLog extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pushed.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = AppLocalizationsEn();
  late Directory tempDir;
  late AppDatabase db;
  late SandboxWriteLog writes;
  late MarkdownBarBloc barBloc;
  late List<int> revisions;
  late _PushLog pushes;

  /// Every caption a case showed, and the slot's size at each: one size, or
  /// a caption moved the page.
  final shownSlots = <String, Size>{};

  List<int> staticRevisions() => [
    EventPresence.revision,
    EventSkips.revision,
    OccurrenceDescriptions.revision,
    CalendarCategories.revision,
    EventAlerts.revision,
    PublicHolidays.revision,
    identityHashCode(CalendarTemplates.all),
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_guide_try');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    for (final locale in ['en', 'de', 'ro']) {
      await initializeDateFormatting(locale);
    }
    // Real glyphs: the caption slots and the overflow checks measure text.
    await loadGoldenFonts();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    writes = SandboxWriteLog();
    db = await openTestDatabase(interceptor: writes);
    SettingsService.reset();
    SettingsService.forTesting(db);
    // Every service a sheet of the cards could write through, bound to the
    // recorded database.
    await CategoryService.forTesting(db);
    await CalendarEventService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventOccurrenceService.forTesting(db);
    await EventAlertService.forTesting(db);
    await EventTemplateService.forTesting(db);
    await FilterPresetService.forTesting(db);
    await PublicHolidayService.forTesting(db);
    await EventDigestService.forTesting(db);
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.forTesting(db),
    );
    // The Permissions row opens the real page: its bloc over a fake gateway,
    // since a test has no platform to ask.
    GetIt.I.registerFactory<PermissionsBloc>(
      () => PermissionsBloc(
        service: permissionServiceOver(FakePermissionGateway()),
      ),
    );
    expect(writes.statements, isNotEmpty);
    writes.statements.clear();
    revisions = staticRevisions();
    pushes = _PushLog();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await barBloc.close();
    CategoryService.reset();
    CalendarEventService.reset();
    EventPresenceService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    EventAlertService.reset();
    EventTemplateService.reset();
    FilterPresetService.reset();
    PublicHolidayService.reset();
    EventDigestService.reset();
    MarkdownBarService.reset();
    CalendarPaletteService.reset();
    SettingsService.reset();
    CalendarCategories.updateCache(const []);
    await db.close();
  });

  /// The card saved nothing: no statement reached the database, none of the
  /// calendar's static caches moved, nothing went to the preferences.
  Future<void> expectNothingSaved() async {
    expect(writes.statements, isEmpty);
    expect(staticRevisions(), revisions);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  }

  Future<GuideTryCardRobot> open(
    WidgetTester tester,
    CalendarGuideTopic topic, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(412, 915),
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [pushes],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: CalendarGuideTopicPage(topic: topic),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pushes.pushed.clear();
    shownSlots.clear();
    return GuideTryCardRobot(tester, topic.slug);
  }

  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime day(int offset) =>
      DateTime.utc(today.year, today.month, today.day + offset);
  // Built on first use: the locale data loads in setUpAll.
  late final dates = DateFormat.yMMMMEEEEd('en');

  void note(GuideTryCardRobot robot) =>
      shownSlots[robot.caption] = robot.slotSize;
  void expectOneSlotHeight() {
    expect(shownSlots.length, greaterThan(1));
    expect(shownSlots.values.toSet(), hasLength(1), reason: '$shownSlots');
    shownSlots.clear();
  }

  group('the frame', () {
    testWidgets('the card comes first, above How it works', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);

      expect(robot.card, findsOneWidget);
      expect(
        tester.getTopLeft(find.text(en.calendarGuideTryIt)).dy,
        lessThan(tester.getTopLeft(find.text(en.calendarGuideHowItWorks)).dy),
      );
      // The lead-in is the entry's searchable title, drawn as the body's
      // first line.
      expect(
        find.descendant(
          of: robot.card,
          matching: find.text(en.calendarGuideTryScreen),
        ),
        findsOneWidget,
      );
      await expectNothingSaved();
    });

    testWidgets('a page with nothing to try has no card', (tester) async {
      await open(tester, CalendarGuideTopic.good);

      expect(find.text(en.calendarGuideTryIt), findsNothing);
      expect(find.byType(CalendarGuideTryCard), findsNothing);
    });

    testWidgets('the entry is a container node, never merged: the stage\'s '
        'controls and the live caption are nodes of their own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // The screen card: its caption is never empty, and an empty one is
      // left out of the tree with nothing to announce.
      final robot = await open(tester, CalendarGuideTopic.screen);

      final entry = tester.getSemantics(robot.card);
      final add = tester.getSemantics(robot.control('more'));
      final caption = tester.getSemantics(
        find.bySemanticsIdentifier(
          SemanticsIds.calendarGuideTryCaption(CalendarGuideTopic.screen.slug),
        ),
      );
      expect(add.id, isNot(entry.id));
      expect(caption.id, isNot(entry.id));
      bool under(SemanticsNode node) {
        for (var p = node.parent; p != null; p = p.parent) {
          if (p.id == entry.id) return true;
        }
        return false;
      }

      expect(under(add), isTrue);
      expect(under(caption), isTrue);
      expect(
        caption.getSemanticsData().label,
        en.calendarGuideDemoFormat(en.calendarFormatMonth),
      );
      expect(add.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(entry.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(caption.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('what she did survives the card scrolling away', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.alerts,
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(1.5),
      );
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      final said = robot.caption;
      expect(said, isNotEmpty);

      final list = find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuideRow('hub')),
        600,
        scrollable: list,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      // Gone from the tree, as the kit's list drops what is far off screen.
      expect(find.byType(CalendarGuideTryCard), findsNothing);

      await tester.scrollUntilVisible(
        robot.card,
        -600,
        scrollable: list,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      expect(robot.caption, said);
      expect(robot.control('alert-0'), findsOneWidget);
      await expectNothingSaved();
    });
  });

  group('screen', () {
    testWidgets('the menus and the mode switch say what they would do, and '
        'open nothing', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      expect(robot.caption, en.calendarGuideDemoFormat(en.calendarFormatMonth));
      note(robot);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarFormatTwoWeeks);
      expect(
        robot.caption,
        en.calendarGuideDemoFormat(en.calendarFormatTwoWeeks),
      );
      note(robot);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarOverviewOpen);
      expect(
        robot.caption,
        en.calendarGuideWouldOpen(en.calendarOverview),
      );
      note(robot);

      for (final (row, said) in [
        (
          SemanticsIds.calendarAlertsOpen,
          en.calendarGuideWouldOpen(en.alertsTitle),
        ),
        (SemanticsIds.calendarExport, en.calendarGuideWouldShare),
        (SemanticsIds.calendarGuideOpen, en.calendarGuideYouAreHere),
        (
          SemanticsIds.calendarSettingsOpen,
          en.calendarGuideWouldOpen(en.calendarSettingsRow),
        ),
      ]) {
        await robot.tap('more');
        await robot.tapId(row);
        expect(robot.caption, said);
        note(robot);
      }

      for (final (mode, said) in [
        ('timeline', en.calendarGuideDemoPanelTimeline(en.panelModeTimeline)),
        ('upcoming', en.calendarGuideDemoPanelUpcoming(en.upcomingEvents)),
        ('day', en.calendarGuideDemoPanelDay(en.panelModeDay)),
      ]) {
        await robot.tapId(SemanticsIds.panelMode(mode));
        expect(robot.caption, said);
        note(robot);
      }

      // The expand button is drawn, disabled: there is no grid to cover.
      final expand = tester.widget<IconButton>(
        find.descendant(of: robot.card, matching: find.byType(IconButton)).last,
      );
      expect(expand.onPressed, isNull);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('events', () {
    String rowId(String key) => 'row-$key';

    testWidgets('idle, with the three demo rows', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);

      expect(robot.caption, en.calendarGuideDemoLongPressHint);
      for (final key in ['dentist', 'yoga', 'rent']) {
        expect(robot.control(rowId(key)), findsOneWidget, reason: key);
      }
      expect(robot.shows(en.eventAllDay), isTrue);
      await expectNothingSaved();
    });

    testWidgets('+ adds through the sandboxed editor, a row opens, changes '
        'and deletes, and the stage never changes height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      final stage = robot.stageSize;
      note(robot);

      await robot.tap('add');
      expect(find.byType(EventEditorSheet), findsOneWidget);
      await sheets.typeTitle('Swim');
      await sheets.saveEditor();
      expect(robot.caption, en.calendarGuideDemoAdded('Swim', dates.format(today)));
      expect(robot.shows('Swim'), isTrue);
      note(robot);

      await robot.tap(rowId('dentist'));
      expect(find.byType(EventDetailSheet), findsOneWidget);
      await sheets.detailEdit();
      await sheets.typeTitle('Dentist at noon');
      await sheets.saveEditor();
      // The editor's Save returns to the detail sheet, as on the calendar.
      if (sheets.detailOpen) await sheets.detailClose();
      expect(robot.caption, en.calendarGuideDemoChanged('Dentist at noon'));
      expect(robot.shows('Dentist at noon'), isTrue);
      note(robot);

      await robot.tap(rowId('yoga'));
      await sheets.detailEdit();
      await sheets.deleteInEditor(en.delete);
      expect(robot.control(rowId('yoga')), findsNothing);
      expect(
        robot.caption,
        en.calendarGuideDemoDeleted(en.calendarGuideDemoEventYoga),
      );
      note(robot);

      // Three more of hers: the oldest makes room, the stage holds its size.
      for (final title in ['One', 'Two', 'Three']) {
        await robot.tap('add');
        await sheets.typeTitle(title);
        await sheets.saveEditor();
      }
      expect(robot.shows('Swim'), isFalse);
      expect(robot.shows('Three'), isTrue);
      expect(robot.stageSize, stage);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('a long title is cut in the caption', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      final long = 'A' * 40;

      await robot.tap('add');
      await sheets.typeTitle(long);
      await sheets.saveEditor();

      expect(
        robot.caption,
        en.calendarGuideDemoAdded('${'A' * 24}…', dates.format(today)),
      );
      await expectNothingSaved();
    });

    testWidgets('a skip from the detail sheet is kept here only', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);

      // Yoga repeats on today's weekday, so its row stands for today.
      await robot.tap(rowId('yoga'));
      await sheets.detailSkip();
      expect(
        robot.caption,
        en.calendarGuideDemoSkipped(
          dates.format(today),
          en.calendarGuideDemoEventYoga,
        ),
      );
      await expectNothingSaved();
    });

    testWidgets('the long press offers the templates, Blank and the quick '
        'alarm', (tester) async {
      final template = await (await EventTemplateService.getInstance()).create(
        EventTemplate(
          id: '',
          name: 'Haircut',
          categoryId: kDefaultCategoryId,
        ),
      );
      writes.statements.clear();
      revisions = staticRevisions();
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.templatePickRow(template.id));
      expect(robot.caption, en.calendarGuideDemoTemplate('Haircut'));
      expect(robot.shows('Haircut'), isTrue);
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.quickAlarmRow);
      expect(robot.caption, en.calendarGuideWouldOpen(en.quickAlarmTitle));
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.templatePickBlank);
      expect(find.byType(EventEditorSheet), findsOneWidget);
      await sheets.typeTitle('Blank one');
      await sheets.saveEditor();
      expect(
        robot.caption,
        en.calendarGuideDemoAdded('Blank one', dates.format(today)),
      );
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('alerts', () {
    testWidgets('the slot rests empty and reserved', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      expect(robot.caption, isEmpty);
      expect(robot.slotSize.height, greaterThan(0));
      expect(robot.control('alert-0'), findsNothing);
      await expectNothingSaved();
    });

    testWidgets('Add alert, change it, remove it — through the real sheet', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      note(robot);

      await robot.tap('add');
      expect(find.byType(AlertEditorSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.control('alert-0'), findsOneWidget);
      expect(
        robot.caption,
        en.calendarGuideDemoAlertSet(
          en.calendarGuideDemoEventDentist,
          en.eventAlertMinutesBefore(kDraftAlertOffsetMinutes),
        ),
      );
      note(robot);

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertTypeAlarm);
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.shows(en.eventAlertModeRing), isTrue);
      note(robot);

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertRemove);
      expect(robot.control('alert-0'), findsNothing);
      expect(
        robot.caption,
        en.calendarGuideDemoChanged(en.calendarGuideDemoEventDentist),
      );
      note(robot);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the alarm screen opens on its own page and Stop closes it', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      await robot.tap('show-alarm');
      expect(find.byType(AlarmPage), findsOneWidget);
      expect(pushes.pushed, hasLength(1));
      expect(pushes.pushed.single, isA<PageRoute<dynamic>>());
      expect(find.text(en.calendarGuideDemoEventDentist), findsWidgets);

      await robot.tapId(SemanticsIds.alarmStop);
      expect(find.byType(AlarmPage), findsNothing);
      expect(find.byType(CalendarGuideTopicPage), findsOneWidget);
      await expectNothingSaved();
    });

    testWidgets('the quick alarm reports its draft, here only', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      note(robot);

      await robot.tap('quick');
      expect(find.byType(QuickAlarmSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.quickAlarmSave);
      expect(find.byType(QuickAlarmSheet), findsNothing);
      // The sheet's default name; the time and the day are the clock's.
      expect(robot.caption, startsWith('Alarm set for '));
      expect(robot.caption, endsWith(en.calendarGuideDemoHereOnly('')));
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the Permissions row opens the real page', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      await robot.tap('permissions');
      expect(find.byType(PermissionsPage), findsOneWidget);
      expect(pushes.pushed, hasLength(1));
      await expectNothingSaved();
    });
  });

  group('kinds', () {
    testWidgets('idle on one day; repeat, pick a day, skip it', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      expect(
        robot.caption,
        en.calendarGuideDemoOneDay(dates.format(today)),
      );
      note(robot);
      // One day: nothing to skip; its dates can grow.
      expect(robot.enabled('skip'), isFalse);
      expect(robot.enabled('add-date'), isTrue);

      await robot.tap('repeat');
      expect(find.byType(EventRepeatSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.repeatKind('daily'));
      await robot.tapId(SemanticsIds.repeatDone);
      final daysThisMonth =
          DateUtils.getDaysInMonth(today.year, today.month) - today.day + 1;
      expect(
        robot.caption,
        en.calendarGuideDemoRepeats(en.recurrenceDaily, daysThisMonth),
      );
      note(robot);
      // A repeating event has no dates of its own; a day is not picked yet.
      expect(robot.enabled('add-date'), isFalse);
      expect(robot.enabled('skip'), isFalse);

      // Today is always on the shown month and always a day it falls on.
      await tester.tap(
        find.descendant(
          of: robot.card,
          matching: find.text('${today.day}'),
        ).last,
      );
      await tester.pumpAndSettle();
      expect(robot.enabled('skip'), isTrue);

      await robot.tap('skip');
      expect(
        robot.caption,
        en.calendarGuideDemoSkipped(
          dates.format(today),
          en.calendarGuideDemoEventDentist,
        ),
      );
      expect(robot.enabled('skip'), isFalse);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Add date pins the event to the dates picked', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      final sheets = PracticeCalendarRobot(tester);
      note(robot);

      // A day in the picker's opening month: today's own month.
      final extra = today.day < 20 ? day(3) : day(-3);
      await robot.tap('add-date');
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      expect(robot.caption, en.recurrenceSpecificDates(2));
      note(robot);
      // Two days now: one of them can be skipped once picked.
      expect(robot.enabled('add-date'), isTrue);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('no overflow and no clipped label at text scale 2.0', () {
    for (final topic in const [
      CalendarGuideTopic.screen,
      CalendarGuideTopic.events,
      CalendarGuideTopic.kinds,
      CalendarGuideTopic.alerts,
    ]) {
      for (final locale in const [Locale('de'), Locale('ro')]) {
        for (final size in const [Size(360, 780), Size(412, 915)]) {
          for (final brightness in Brightness.values) {
            testWidgets('${topic.slug} ${locale.languageCode} '
                '${size.width.toInt()}×${size.height.toInt()} '
                '${brightness.name}', (tester) async {
              final robot = await open(
                tester,
                topic,
                locale: locale,
                brightness: brightness,
                textScaler: const TextScaler.linear(2.0),
                size: size,
              );
              expect(tester.takeException(), isNull);
              await tester.ensureVisible(
                find.descendant(
                  of: robot.card,
                  matching: find.byType(RepaintBoundary),
                ).first,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final paragraphs = tester.renderObjectList<RenderParagraph>(
                find.descendant(
                  of: robot.card,
                  matching: find.byType(RichText),
                ),
              );
              for (final paragraph in paragraphs) {
                expect(
                  paragraph.didExceedMaxLines,
                  isFalse,
                  reason: paragraph.text.toPlainText(),
                );
              }
              await expectNothingSaved();
            });
          }
        }
      }
    }
  });
}
