import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_guide_demo.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/pages/calendar_guide_page.dart';
import 'package:anta/pages/calendar_guide_practice_page.dart';
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
import 'package:anta/utils/presence_stats.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/layout_errors.dart';
import 'support/practice_calendar_robot.dart';
import 'support/sandbox_write_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = AppLocalizationsEn();
  late Directory tempDir;
  late AppDatabase db;
  late SandboxWriteLog writes;
  late MarkdownBarBloc barBloc;
  late List<int> revisions;

  List<int> staticRevisions() => [
    EventPresence.revision,
    EventSkips.revision,
    OccurrenceDescriptions.revision,
    CalendarCategories.revision,
    EventAlerts.revision,
    PublicHolidays.revision,
    // The templates' facade keeps no revision: every publish swaps its list.
    identityHashCode(CalendarTemplates.all),
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_guide_practice');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    for (final locale in ['en', 'de', 'ro']) {
      await initializeDateFormatting(locale);
    }
    // Real glyphs: the test font draws every glyph a full em wide, which
    // would size the band's caption slot about twice as tall as a phone
    // draws it, and the overflow checks below would be measuring the font.
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
    // Every service a sheet of the page could write through, bound to the
    // recorded database: the built-in categories seed the demo's colours,
    // the rest are empty.
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
    // The editor's toolbar reads the bar service: on the same database, so
    // no second one is opened beside it.
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.forTesting(db),
    );
    // The built-in categories' seed went through the log: it hears writes,
    // so an empty log after a test means nothing was written.
    expect(writes.statements, isNotEmpty);
    writes.statements.clear();
    revisions = staticRevisions();
  });

  tearDown(() async {
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

  /// The page saved nothing: no statement reached the database, none of the
  /// real calendar's static caches moved, and nothing went to the platform's
  /// preferences.
  Future<void> expectNothingSaved() async {
    expect(writes.statements, isEmpty);
    expect(staticRevisions(), revisions);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  }

  /// Takes a write the test itself made out of the log, so the case still
  /// proves the page wrote nothing after it.
  void rebaseline() {
    writes.statements.clear();
    revisions = staticRevisions();
  }

  /// Seeds one template the owner might have, through the real service.
  Future<void> seedTemplate(String name, {String? description}) async {
    await (await EventTemplateService.getInstance()).create(
      EventTemplate(
        id: '',
        name: name,
        categoryId: kDefaultCategoryId,
        description: description,
      ),
    );
    rebaseline();
  }

  Future<PracticeCalendarRobot> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(412, 915),
    Widget home = const CalendarGuidePracticePage(),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return PracticeCalendarRobot(tester);
  }

  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime day(int offset) =>
      DateTime.utc(today.year, today.month, today.day + offset);
  // Built on first use: the locale data loads in setUpAll.
  late final dates = DateFormat.yMMMMEEEEd('en');
  final seedTitles = [
    en.calendarGuideDemoEventDentist,
    en.calendarGuideDemoEventYoga,
    en.calendarGuideDemoEventRent,
    en.calendarGuideDemoEventBirthday,
    en.calendarGuideDemoEventBookClub,
    en.calendarGuideDemoEventFlight,
  ];

  testWidgets("the hub's Practice row pushes the page, and back returns", (
    tester,
  ) async {
    await open(tester, home: const CalendarGuidePage());

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.calendarGuidePage(calendarGuidePracticeSlug),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CalendarGuidePracticePage), findsOneWidget);
    // A plain push: no name and no arguments for a restore to replay.
    final route = ModalRoute.of(
      tester.element(find.byType(CalendarGuidePracticePage)),
    )!;
    expect(route.settings.name, isNull);
    expect(route.settings.arguments, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CalendarGuidePracticePage), findsNothing);
    expect(find.byType(CalendarGuidePage), findsOneWidget);
    await expectNothingSaved();
  });

  testWidgets('opens idle on today, with Start over disabled', (tester) async {
    final robot = await open(tester);

    expect(robot.caption, en.calendarGuidePracticeIdle);
    expect(find.text(en.calendarGuidePracticeBanner), findsOneWidget);
    expect(robot.canReset, isFalse);
    expect(robot.filterBadge, isNull);
    expect(robot.format, CalendarFormat.month);
    // Yoga repeats on today's weekday.
    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventYoga));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.calendarGuidePractice),
      findsOneWidget,
    );
    await expectNothingSaved();
  });

  testWidgets('picking a day names it and counts its events', (tester) async {
    final robot = await open(tester);

    await robot.pickDay(day(2));

    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventDentist));
    // The count is the demo's own, from a twin seeded the way the page
    // seeds it.
    final twin = GuideDemoCalendar(
      l10n: en,
      today: now,
      categories: (await CategoryService.getInstance()).categories,
    );
    expect(
      robot.caption,
      en.calendarGuidePickedDay(
        dates.format(day(2)),
        twin.eventsFor(day(2)).length,
      ),
    );
    expect(robot.canReset, isFalse);
    await expectNothingSaved();
  });

  testWidgets('+ → the editor → Save: the event joins the day panel and the '
      'grid; Start over brings the seed back', (tester) async {
    final robot = await open(tester);
    await robot.pickDay(day(3));

    await robot.add();
    await robot.typeTitle('Swim');
    await robot.saveEditor();

    expect(robot.dayPanelTitles, contains('Swim'));
    expect(
      robot.barLabels.where((label) => label.contains('Swim')),
      hasLength(1),
    );
    expect(
      robot.caption,
      en.calendarGuideDemoAddedShort('Swim', dates.format(day(3))),
    );
    expect(robot.canReset, isTrue);

    await robot.reset();

    expect(robot.caption, en.calendarGuidePracticeIdle);
    expect(robot.canReset, isFalse);
    expect(robot.dayPanelTitles, isNot(contains('Swim')));
    expect(robot.barLabels.where((label) => label.contains('Swim')), isEmpty);
    await expectNothingSaved();
  });

  testWidgets('a row → the detail sheet → Edit: the changed title is saved '
      'to the demo', (tester) async {
    final robot = await open(tester);
    await robot.pickDay(day(2));

    await robot.openRow('guide-demo-dentist');
    expect(robot.detailOpen, isTrue);
    await robot.detailEdit();
    await robot.typeTitle('Dentist again');
    await robot.saveEditor();

    expect(robot.caption, en.calendarGuideDemoChanged('Dentist again'));
    // The trip reopens the detail sheet on the day, as the calendar's does.
    expect(robot.detailOpen, isTrue);
    await robot.detailClose();
    expect(robot.dayPanelTitles, contains('Dentist again'));
    expect(
      robot.dayPanelTitles,
      isNot(contains(en.calendarGuideDemoEventDentist)),
    );
    await expectNothingSaved();
  });

  testWidgets('Skip takes the day off and keeps the other days', (
    tester,
  ) async {
    final robot = await open(tester);

    await robot.openRow('guide-demo-yoga');
    await robot.detailSkip();

    expect(robot.detailOpen, isFalse);
    expect(
      robot.dayPanelTitles,
      isNot(contains(en.calendarGuideDemoEventYoga)),
    );
    expect(
      robot.caption,
      en.calendarGuideDemoSkipped(
        dates.format(today),
        en.calendarGuideDemoEventYoga,
      ),
    );
    // Yoga's other days: a week either way, the missed one counted too.
    await robot.pickDay(day(today.day > 7 ? -7 : 7));
    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventYoga));
    await expectNothingSaved();
  });

  testWidgets("the editor's Delete removes the event from every day", (
    tester,
  ) async {
    final robot = await open(tester);
    await robot.pickDay(day(2));

    await robot.openRow('guide-demo-dentist');
    await robot.detailEdit();
    await robot.deleteInEditor(en.delete);

    expect(robot.detailOpen, isFalse);
    expect(
      robot.caption,
      en.calendarGuideDemoDeleted(en.calendarGuideDemoEventDentist),
    );
    expect(
      robot.dayPanelTitles,
      isNot(contains(en.calendarGuideDemoEventDentist)),
    );
    expect(
      robot.barLabels.where(
        (label) => label.contains(en.calendarGuideDemoEventDentist),
      ),
      isEmpty,
    );
    await expectNothingSaved();
  });

  testWidgets('the funnel: a filter applied counts on the badge and in the '
      'caption', (tester) async {
    final robot = await open(tester);

    await robot.openFilters();
    await robot.tapId(SemanticsIds.filterHolidays);
    await robot.tapId(SemanticsIds.filterApply);

    expect(robot.filterBadge, 1);
    expect(robot.caption, en.calendarGuideDemoFiltered(1));
    expect(robot.canReset, isTrue);
    await expectNothingSaved();
  });

  testWidgets("the view menu's formats reshape the grid and say so", (
    tester,
  ) async {
    final robot = await open(tester);

    await robot.pickFormat(SemanticsIds.calendarFormatWeek);
    expect(robot.format, CalendarFormat.week);
    expect(robot.cellCount, 7);
    expect(robot.caption, en.calendarGuideDemoFormat(en.calendarFormatWeek));

    await robot.pickFormat(SemanticsIds.calendarFormatTwoWeeks);
    expect(robot.format, CalendarFormat.twoWeeks);
    expect(robot.cellCount, 14);
    expect(
      robot.caption,
      en.calendarGuideDemoFormat(en.calendarFormatTwoWeeks),
    );

    await robot.tapId(SemanticsIds.calendarViewMenu);
    await robot.tapId(SemanticsIds.calendarOverviewOpen);
    expect(robot.caption, en.calendarGuideWouldOpen(en.calendarOverview));
    expect(find.byType(CalendarGuidePracticePage), findsOneWidget);
    await expectNothingSaved();
  });

  testWidgets("the ⋮'s four rows only say what they would do", (tester) async {
    final robot = await open(tester);

    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    expect(robot.caption, en.calendarGuideWouldOpen(en.alertsTitle));
    await robot.pickMore(SemanticsIds.calendarExport);
    expect(robot.caption, en.calendarGuideWouldShare);
    await robot.pickMore(SemanticsIds.calendarGuideOpen);
    expect(robot.caption, en.calendarGuideYouAreHere);
    await robot.pickMore(SemanticsIds.calendarSettingsOpen);
    expect(robot.caption, en.calendarGuideWouldOpen(en.calendarSettingsRow));
    expect(find.byType(CalendarGuidePracticePage), findsOneWidget);
    expect(robot.canReset, isFalse);
    await expectNothingSaved();
  });

  testWidgets("the panel's modes each say what they show", (tester) async {
    final robot = await open(tester);
    // Today's first event heads the Upcoming list: Yoga, unless today is
    // also a day of an all-day seed (rent on the 1st, the birthday).
    final todayFirst = robot.dayPanelTitles.first;
    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventYoga));
    expect(robot.canExpandPanel, isFalse);

    await robot.showPanel(CalendarPanelMode.timeline);
    expect(
      robot.caption,
      en.calendarGuideDemoPanelTimeline(en.panelModeTimeline),
    );
    await robot.showPanel(CalendarPanelMode.upcoming);
    expect(robot.caption, en.calendarGuideDemoPanelUpcoming(en.upcomingEvents));
    expect(robot.firstUpcomingOf(seedTitles), todayFirst);
    // The expand button stays, disabled: the practice panel never covers
    // its grid.
    expect(find.byTooltip(en.panelExpand), findsOneWidget);
    expect(robot.canExpandPanel, isFalse);
    await robot.showPanel(CalendarPanelMode.day);
    expect(robot.caption, en.calendarGuideDemoPanelDay(en.panelModeDay));
    await expectNothingSaved();
  });

  testWidgets('the band keeps its height whatever the caption says', (
    tester,
  ) async {
    final robot = await open(tester, size: const Size(360, 780));
    final idle = robot.bandSize;

    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    expect(robot.bandSize, idle);

    await robot.add();
    await robot.typeTitle('A title well past the cut of the caption');
    await robot.saveEditor();
    // Cut at 24 characters, so the slot sized for the cut holds it.
    expect(robot.caption, startsWith('Added “A title well past the cu…”'));
    expect(robot.bandSize, idle);

    await robot.openRow('guide-demo-yoga');
    await robot.detailSkip();
    expect(robot.caption, startsWith('Skipped'));
    expect(robot.bandSize, idle);
    await expectNothingSaved();
  });

  testWidgets('de 2.0 on 360: the band keeps its height across idle, Added, '
      'Skipped, would-open and adherence', (tester) async {
    final de = AppLocalizationsDe();
    final robot = await open(
      tester,
      locale: const Locale('de'),
      textScaler: const TextScaler.linear(2.0),
      size: const Size(360, 780),
    );
    final idle = robot.bandSize;
    expect(robot.caption, de.calendarGuidePracticeIdle);

    await robot.pickMore(SemanticsIds.calendarSettingsOpen);
    expect(robot.caption, de.calendarGuideWouldOpen(de.calendarSettingsRow));
    expect(robot.bandSize, idle);

    // At 2.0 on 360 a month's grid leaves the panel no room: a week does.
    await robot.pickFormat(SemanticsIds.calendarFormatWeek);
    expect(robot.bandSize, idle);

    // The detail sheet's chip: the Day panel's own button sits under the
    // add button there.
    await robot.openRow('guide-demo-yoga');
    await robot.tapId(SemanticsIds.eventDetailMissed);
    expect(
      robot.caption,
      de.eventAdherenceSummary(3, 5, PresenceAdherence.windowDays),
    );
    expect(robot.bandSize, idle);
    await robot.detailClose();

    await robot.add();
    await robot.typeTitle('Schwimmen im Hallenbad am Abend');
    await robot.saveEditor();
    expect(robot.caption, startsWith('„Schwimmen'));
    expect(robot.bandSize, idle);

    await robot.openRow('guide-demo-yoga');
    await robot.detailSkip();
    expect(
      robot.caption,
      de.calendarGuideDemoSkipped(
        DateFormat.yMMMMEEEEd('de').format(today),
        de.calendarGuideDemoEventYoga,
      ),
    );
    expect(robot.bandSize, idle);
    await expectNothingSaved();
  });

  testWidgets('a task ticked in the detail sheet and dismissed at once by '
      'back lands in the demo without an error', (tester) async {
    await seedTemplate('Checklist', description: '- [ ] x');
    final robot = await open(tester);

    await robot.longPressAdd();
    await robot.tapId(
      SemanticsIds.templatePickRow(CalendarTemplates.all.single.id),
    );
    expect(robot.caption, en.calendarGuideDemoTemplate('Checklist'));
    final id = robot.rowIdOf('Checklist');
    expect(id, startsWith(GuideDemoCalendar.idPrefix));

    await robot.openRow(id);
    await robot.tickFirstTask();
    // Back before the sheet's write delay runs out: the tick is handed over
    // from the sheet's dispose.
    await robot.systemBack();

    expect(tester.takeException(), isNull);
    expect(robot.detailOpen, isFalse);
    expect(
      robot.dayPanelEntries
          .firstWhere((entry) => entry.title == 'Checklist')
          .description,
      '- [x] x',
    );
    expect(robot.canReset, isTrue);
    await expectNothingSaved();
  });

  testWidgets("the template picker's Blank opens the editor and Quick alarm "
      'only says what it would open', (tester) async {
    final robot = await open(tester);

    await robot.longPressAdd();
    await robot.tapId(SemanticsIds.templatePickBlank);
    expect(find.byType(EventEditorSheet), findsOneWidget);
    await robot.tapId(SemanticsIds.eventClose);
    expect(find.byType(EventEditorSheet), findsNothing);

    await robot.longPressAdd();
    await robot.tapId(SemanticsIds.quickAlarmRow);
    expect(robot.caption, en.calendarGuideWouldOpen(en.quickAlarmTitle));
    expect(robot.canReset, isFalse);
    await expectNothingSaved();
  });

  group("the demo's presence reaches every shared widget", () {
    testWidgets('the missed week draws faded in the grid and the timeline', (
      tester,
    ) async {
      final robot = await open(tester);
      await robot.pickDay(day(-7));

      final missed = robot
          .barsOn(day(-7))
          .singleWhere(
            (bar) => bar.semanticLabel == en.calendarGuideDemoEventYoga,
          );
      expect(missed.color.a, closeTo(CalendarColors.missedEventAlpha, 0.01));

      await robot.showPanel(CalendarPanelMode.timeline);
      expect(
        robot.timelineOpacityOf(en.calendarGuideDemoEventYoga),
        CalendarColors.missedEventAlpha,
      );

      await robot.pickDay(day(-14));
      final kept = robot
          .barsOn(day(-14))
          .singleWhere(
            (bar) => bar.semanticLabel == en.calendarGuideDemoEventYoga,
          );
      expect(kept.color.a, 1.0);
      expect(robot.timelineOpacityOf(en.calendarGuideDemoEventYoga), 1.0);
      await expectNothingSaved();
    });

    testWidgets('the detail sheet opens Missed on it, with stats from the '
        "demo's marks", (tester) async {
      final robot = await open(tester);
      await robot.pickDay(day(-7));

      await robot.openRow('guide-demo-yoga');
      expect(robot.chipSelected(SemanticsIds.eventDetailMissed), isTrue);
      expect(robot.chipSelected(SemanticsIds.eventDetailPresent), isFalse);
      expect(
        find.text(en.eventAdherenceSummary(4, 5, PresenceAdherence.windowDays)),
        findsOneWidget,
      );
      await expectNothingSaved();
    });

    testWidgets('a mark made in the sheet survives a reopen and the band says '
        'how the event is going', (tester) async {
      final robot = await open(tester);
      final idle = robot.bandSize;

      await robot.openRow('guide-demo-yoga');
      expect(robot.chipSelected(SemanticsIds.eventDetailPresent), isTrue);
      await robot.tapId(SemanticsIds.eventDetailMissed);
      expect(
        robot.caption,
        en.eventAdherenceSummary(3, 5, PresenceAdherence.windowDays),
      );
      expect(robot.bandSize, idle);
      await robot.detailClose();

      await robot.openRow('guide-demo-yoga');
      expect(robot.chipSelected(SemanticsIds.eventDetailMissed), isTrue);
      expect(
        find.descendant(
          of: find.byType(EventDetailSheet),
          matching: find.text(
            en.eventAdherenceSummary(3, 5, PresenceAdherence.windowDays),
          ),
        ),
        findsOneWidget,
      );
      await robot.detailClose();
      expect(
        robot.dayPanelEntries
            .singleWhere(
              (entry) => entry.title == en.calendarGuideDemoEventYoga,
            )
            .missed,
        isTrue,
      );
      await expectNothingSaved();
    });
  });

  testWidgets("a skip made in the detail sheet shows in the editor's skipped "
      'days and survives its Save', (tester) async {
    final robot = await open(tester);

    await robot.openRow('guide-demo-yoga');
    await robot.detailSkip();
    await robot.pickDay(day(7));
    await robot.openRow('guide-demo-yoga');
    await robot.detailEdit();
    await robot.scrollEditorTo(find.text(en.eventSkippedDaysCount(1)));
    expect(find.text(en.eventSkippedDaysCount(1)), findsOneWidget);
    await robot.saveEditor();
    await robot.detailClose();

    await robot.pickDay(today);
    expect(
      robot.dayPanelTitles,
      isNot(contains(en.calendarGuideDemoEventYoga)),
    );
    await expectNothingSaved();
  });

  testWidgets("an alert added in the practice editor is there on the next "
      'open, and nothing is written', (tester) async {
    final robot = await open(tester);
    await robot.pickDay(day(2));

    await robot.openRow('guide-demo-dentist');
    await robot.detailEdit();
    await robot.scrollEditorTo(
      find.bySemanticsIdentifier(SemanticsIds.eventAlertAdd),
    );
    await robot.tapId(SemanticsIds.eventAlertAdd);
    await robot.tapId(SemanticsIds.alertSheetSave);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.eventAlertRemove(0)),
      findsOneWidget,
    );
    await robot.saveEditor();

    await robot.detailEdit();
    await robot.scrollEditorTo(
      find.bySemanticsIdentifier(SemanticsIds.eventAlertRemove(0)),
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.eventAlertRemove(0)),
      findsOneWidget,
    );
    await expectNothingSaved();
  });

  testWidgets("a day's own text shows on that day only, and with per-day off "
      "the detail sheet shows the event's description", (tester) async {
    final robot = await open(tester);

    await robot.openRow('guide-demo-yoga');
    await robot.detailEdit();
    await robot.toggleEditorSwitch(en.eventPerOccurrenceDescriptions);
    await robot.saveEditor();
    await robot.quickEditDescription('Mat by the window');
    expect(
      robot.caption,
      en.calendarGuideDemoChanged(en.calendarGuideDemoEventYoga),
    );
    await robot.detailClose();

    String? yogaText() => robot.dayPanelEntries
        .singleWhere((entry) => entry.title == en.calendarGuideDemoEventYoga)
        .description;
    expect(yogaText(), 'Mat by the window');
    await robot.pickDay(day(7));
    expect(yogaText(), isNull);

    await robot.pickDay(today);
    await robot.openRow('guide-demo-yoga');
    await robot.detailEdit();
    await robot.toggleEditorSwitch(en.eventPerOccurrenceDescriptions);
    await robot.saveEditor();
    expect(robot.detailOpen, isTrue);
    expect(
      find.descendant(
        of: find.byType(EventDetailSheet),
        matching: find.textContaining('Mat by the window', findRichText: true),
      ),
      findsNothing,
    );
    expect(find.text(en.eventDescriptionAdd), findsOneWidget);
    await expectNothingSaved();
  });

  testWidgets("the quick description edit writes the event's text", (
    tester,
  ) async {
    final robot = await open(tester);
    await robot.pickDay(day(2));

    await robot.openRow('guide-demo-dentist');
    await robot.quickEditDescription('Bring the card');
    expect(
      robot.caption,
      en.calendarGuideDemoChanged(en.calendarGuideDemoEventDentist),
    );
    await robot.detailClose();
    expect(
      robot.dayPanelEntries
          .singleWhere(
            (entry) => entry.title == en.calendarGuideDemoEventDentist,
          )
          .description,
      'Bring the card',
    );
    await expectNothingSaved();
  });

  testWidgets('Add date pins a second day to a one-time event', (tester) async {
    final robot = await open(tester);
    await robot.pickDay(day(2));
    // The other day stays in the month the picker opens on.
    final other = day(2).day > 1 ? day(1) : day(3);

    await robot.openRow('guide-demo-dentist');
    await robot.detailAddDate();
    await robot.pickInDatePicker(other);
    await robot.tapId(SemanticsIds.datePickerSave);
    expect(
      robot.caption,
      en.calendarGuideDemoChanged(en.calendarGuideDemoEventDentist),
    );
    await robot.detailClose();

    await robot.pickDay(other);
    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventDentist));
    await expectNothingSaved();
  });

  testWidgets('the Missed-only filter leaves the missed week alone on the '
      'grid', (tester) async {
    final robot = await open(tester);
    await robot.pickDay(day(-7));

    await robot.openFilters();
    await robot.tapId(SemanticsIds.filterOnlyShow);
    await tester.tap(find.text(en.eventPresenceMissed).last);
    await tester.pumpAndSettle();
    await robot.tapId(SemanticsIds.filterListDone);
    await robot.tapId(SemanticsIds.filterApply);

    expect(robot.caption, en.calendarGuideDemoFiltered(1));
    expect(robot.barLabels.where(seedTitles.contains).toList(), [
      en.calendarGuideDemoEventYoga,
    ]);
    expect(
      robot.barsOn(day(-7)).map((bar) => bar.semanticLabel),
      contains(en.calendarGuideDemoEventYoga),
    );
    await expectNothingSaved();
  });

  testWidgets("a Timeline block's tap opens the event's detail sheet", (
    tester,
  ) async {
    final robot = await open(tester);

    await robot.showPanel(CalendarPanelMode.timeline);
    await robot.tapTimelineEvent(en.calendarGuideDemoEventYoga);
    expect(robot.detailOpen, isTrue);
    expect(robot.chipSelected(SemanticsIds.eventDetailPresent), isTrue);
    await expectNothingSaved();
  });

  group('Start over compares with the seed', () {
    testWidgets('Apply with unchanged filters leaves it disabled', (
      tester,
    ) async {
      final robot = await open(tester);

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterApply);

      expect(robot.caption, en.calendarGuideDemoFiltered(0));
      expect(robot.canReset, isFalse);
      await expectNothingSaved();
    });

    testWidgets('an event added then deleted leaves it disabled', (
      tester,
    ) async {
      final robot = await open(tester);
      await robot.pickDay(day(3));

      await robot.add();
      await robot.typeTitle('Swim');
      await robot.saveEditor();
      expect(robot.canReset, isTrue);
      final id = robot.rowIdOf('Swim');
      expect(id, startsWith(GuideDemoCalendar.idPrefix));

      await robot.openRow(id);
      await robot.detailEdit();
      await robot.deleteInEditor(en.delete);

      expect(robot.dayPanelTitles, isNot(contains('Swim')));
      expect(robot.canReset, isFalse);
      await expectNothingSaved();
    });

    testWidgets('a mark then unmark leaves it disabled', (tester) async {
      final robot = await open(tester);

      await robot.pressPresence('guide-demo-yoga', en.eventMarkMissed);
      expect(robot.canReset, isTrue);
      await robot.pressPresence('guide-demo-yoga', en.eventMarkPresent);

      expect(
        robot.caption,
        en.eventAdherenceSummary(4, 5, PresenceAdherence.windowDays),
      );
      expect(robot.canReset, isFalse);
      await expectNothingSaved();
    });
  });

  testWidgets('with the static category cache empty, the seed wears the '
      "categories the service holds", (tester) async {
    // A relaunch onto the guide: the calendar's bloc has not published the
    // categories yet.
    CalendarCategories.updateCache(const []);
    rebaseline();
    final visible = [
      for (final category in (await CategoryService.getInstance()).categories)
        if (!category.isHidden) category.id,
    ];
    expect(visible.length, greaterThan(2));

    final robot = await open(tester);
    final yoga = robot.dayPanelEntries
        .singleWhere((entry) => entry.title == en.calendarGuideDemoEventYoga)
        .event!;
    expect(yoga.categoryId, visible[1]);
    await robot.pickDay(day(2));
    final dentist = robot.dayPanelEntries
        .singleWhere((entry) => entry.title == en.calendarGuideDemoEventDentist)
        .event!;
    expect(dentist.categoryId, visible[0]);
    expect(dentist.categoryId, isNot(CalendarCategories.fallback.id));
    await expectNothingSaved();
  });

  testWidgets('the route is named "Practice calendar", never by the '
      "calendar's title", (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    final named = [
      for (final node
          in find.semantics
              .byPredicate(
                (node) => node.getSemanticsData().flagsCollection.namesRoute,
              )
              .evaluate())
        node.getSemanticsData().label,
    ];
    expect(named, contains(en.calendarGuidePagePractice));
    expect(named, isNot(contains(en.calendar)));
    handle.dispose();
    await expectNothingSaved();
  });

  for (final locale in const [Locale('de'), Locale('ro')]) {
    for (final size in const [Size(360, 780), Size(412, 915)]) {
      for (final brightness in Brightness.values) {
        testWidgets('${locale.languageCode} 2.0 ${size.width.toInt()}×'
            '${size.height.toInt()} ${brightness.name}: no overflow', (
          tester,
        ) async {
          final errors = await layoutErrorsDuring(() async {
            final robot = await open(
              tester,
              locale: locale,
              brightness: brightness,
              textScaler: const TextScaler.linear(2.0),
              size: size,
            );
            await robot.showPanel(CalendarPanelMode.upcoming);
          });
          // In full, so a failure names the widget that overflowed.
          expect([
            for (final error in errors)
              error.toDiagnosticsNode().toStringDeep(),
          ], isEmpty);
          await expectNothingSaved();
        });
      }
    }
  }
}
