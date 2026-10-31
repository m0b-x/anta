import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:anta/widgets/calendar_guide_grid.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_guidelines.dart';
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
    GuidePracticeLesson lesson = GuidePracticeLesson.events,
    Widget? home,
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
          home: home ?? CalendarGuidePracticePage(lesson: lesson),
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
  final seedTitles = [
    en.calendarGuideDemoEventDentist,
    en.calendarGuideDemoEventYoga,
    en.calendarGuideDemoEventRent,
    en.calendarGuideDemoEventBirthday,
    en.calendarGuideDemoEventBookClub,
    en.calendarGuideDemoEventFlight,
  ];
  final eventsTour = GuidePracticeLesson.events.steps;

  for (final lesson in GuidePracticeLesson.values) {
    testWidgets("the hub's ${lesson.name} row pushes that lesson, and back "
        'returns', (tester) async {
      await open(tester, home: const CalendarGuidePage());

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuidePage(lesson.slug)),
      );
      await tester.pumpAndSettle();

      final page = find.byType(CalendarGuidePracticePage);
      expect(page, findsOneWidget);
      expect(tester.widget<CalendarGuidePracticePage>(page).lesson, lesson);
      // A plain push: no name and no arguments for a restore to replay.
      final route = ModalRoute.of(tester.element(page))!;
      expect(route.settings.name, isNull);
      expect(route.settings.arguments, isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CalendarGuidePracticePage), findsNothing);
      expect(find.byType(CalendarGuidePage), findsOneWidget);
      await expectNothingSaved();
    });
  }

  testWidgets('opens idle on today, with Start over disabled', (tester) async {
    final robot = await open(tester);

    expect(robot.caption, en.calendarGuideTourPick);
    expect(find.text(en.calendarGuidePracticeBanner), findsOneWidget);
    expect(robot.canReset, isFalse);
    expect(robot.canSkip, isTrue);
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

  testWidgets('a day with events moves the tour on to its event; a day '
      'without keeps asking for one', (tester) async {
    final robot = await open(tester);
    // The demo's days, from a twin seeded the way the page seeds it.
    final twin = GuideDemoCalendar(
      l10n: en,
      today: now,
      categories: (await CategoryService.getInstance()).categories,
    );
    final empty = [
      for (var d = 1; d <= 28; d++) DateTime.utc(today.year, today.month, d),
    ].firstWhere((d) => twin.eventsFor(d).isEmpty);

    await robot.pickDay(empty);
    expect(robot.caption, en.calendarGuideTourPick);
    expect(robot.canReset, isFalse);

    await robot.pickDay(day(2));
    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventDentist));
    expect(robot.caption, en.calendarGuideTourOpen);
    expect(robot.canReset, isTrue, reason: 'a step of the tour is done');
    await expectNothingSaved();
  });

  testWidgets('the tour walked in order: a row, Edit and Save, + and Save, '
      'the funnel, then the closing line with the skip disabled', (
    tester,
  ) async {
    final robot = await open(tester);
    await robot.pickDay(day(2));

    // The trip's steps reach the band when it returns: under a sheet the
    // line would change unannounced.
    await robot.openRow('guide-demo-dentist');
    expect(robot.caption, en.calendarGuideTourOpen);
    await robot.detailEdit();
    await robot.typeTitle('Dentist again');
    await robot.saveEditor();
    expect(robot.detailOpen, isTrue);
    expect(robot.caption, en.calendarGuideTourOpen);
    await robot.detailClose();
    expect(robot.caption, en.calendarGuideTourAdd);

    await robot.add();
    await robot.typeTitle('Swim');
    await robot.saveEditor();
    expect(robot.caption, en.calendarGuideTourFilter(en.apply));
    expect(robot.canSkip, isTrue);

    await robot.openFilters();
    await robot.tapId(SemanticsIds.filterHolidays);
    await robot.tapId(SemanticsIds.filterApply);
    expect(robot.caption, en.calendarGuideTourDone);
    expect(robot.canSkip, isFalse);
    await expectNothingSaved();
  });

  testWidgets('the skip steps past a line and is disabled at the end; Start '
      'over after a skip alone restarts the tour', (tester) async {
    final robot = await open(tester);

    await robot.skip();
    expect(robot.caption, en.calendarGuideTourOpen);
    expect(robot.canReset, isTrue, reason: 'the demo is clean, the tour not');

    await robot.reset();
    expect(robot.caption, en.calendarGuideTourPick);
    expect(robot.canReset, isFalse);
    expect(robot.canSkip, isTrue);

    for (var i = 0; i < eventsTour.length; i++) {
      await robot.skip();
    }
    expect(robot.caption, en.calendarGuideTourDone);
    expect(robot.canSkip, isFalse);
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
    expect(robot.canReset, isTrue);

    await robot.reset();

    expect(robot.caption, en.calendarGuideTourPick);
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

    // The trip reopens the detail sheet on the day, as the calendar's does.
    expect(robot.detailOpen, isTrue);
    await robot.detailClose();
    expect(robot.caption, en.calendarGuideTourAdd);
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
    // No step: the day panel shows it, and the band still asks for the
    // first step not done.
    expect(robot.caption, en.calendarGuideTourPick);
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
    // No step: the grid and the panel show it.
    expect(robot.caption, en.calendarGuideTourEdit(en.edit, en.save));
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

  testWidgets('the funnel: a filter applied counts on the badge, and the '
      'early step is done where it sits', (tester) async {
    final robot = await open(tester);

    await robot.openFilters();
    await robot.tapId(SemanticsIds.filterHolidays);
    await robot.tapId(SemanticsIds.filterApply);

    expect(robot.filterBadge, 1);
    expect(robot.caption, en.calendarGuideTourPick);
    expect(robot.canReset, isTrue);
    for (var i = 0; i < eventsTour.length - 1; i++) {
      await robot.skip();
    }
    expect(robot.caption, en.calendarGuideTourDone, reason: 'filter is done');
    await expectNothingSaved();
  });

  testWidgets("the view menu's formats reshape the grid, and its Overview "
      'and Report only say what they would open', (tester) async {
    final robot = await open(tester);

    await robot.pickFormat(SemanticsIds.calendarFormatWeek);
    expect(robot.format, CalendarFormat.week);
    expect(robot.cellCount, 7);
    expect(robot.caption, en.calendarGuideTourPick, reason: 'the grid shows it');

    await robot.pickFormat(SemanticsIds.calendarFormatTwoWeeks);
    expect(robot.format, CalendarFormat.twoWeeks);
    expect(robot.cellCount, 14);

    await robot.tapId(SemanticsIds.calendarViewMenu);
    await robot.tapId(SemanticsIds.calendarReportOpen);
    expect(robot.caption, en.calendarGuideWouldOpen(en.reportTitle));
    expect(find.byType(CalendarGuidePracticePage), findsOneWidget);

    await robot.tapId(SemanticsIds.calendarViewMenu);
    await robot.tapId(SemanticsIds.calendarOverviewOpen);
    expect(robot.caption, en.calendarGuideWouldOpen(en.calendarOverview));
    expect(find.byType(CalendarGuidePracticePage), findsOneWidget);

    // The next step's action takes the report away.
    await robot.pickDay(day(2));
    expect(robot.caption, en.calendarGuideTourOpen);
    await expectNothingSaved();
  });

  testWidgets("the ⋮'s four rows only say what they would do, each alone", (
    tester,
  ) async {
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
    expect(robot.canReset, isFalse, reason: 'a report is no step');

    await robot.pickDay(day(2));
    expect(robot.caption, en.calendarGuideTourOpen);
    await expectNothingSaved();
  });

  testWidgets("the panel's modes show their own lists and leave the tour's "
      'line alone', (tester) async {
    final robot = await open(tester);
    // Today's first event heads the Upcoming list: Yoga, unless today is
    // also a day of an all-day seed (rent on the 1st, the birthday).
    final todayFirst = robot.dayPanelTitles.first;
    expect(robot.dayPanelTitles, contains(en.calendarGuideDemoEventYoga));
    expect(robot.canExpandPanel, isFalse);

    await robot.showPanel(CalendarPanelMode.timeline);
    await robot.showPanel(CalendarPanelMode.upcoming);
    expect(robot.firstUpcomingOf(seedTitles), todayFirst);
    // The expand button stays, disabled: the practice panel never covers
    // its grid.
    expect(find.byTooltip(en.panelExpand), findsOneWidget);
    expect(robot.canExpandPanel, isFalse);
    await robot.showPanel(CalendarPanelMode.day);
    expect(robot.caption, en.calendarGuideTourPick);
    await expectNothingSaved();
  });

  testWidgets('a Timeline block opens the event: the band asks for the edit '
      'once the sheet is closed', (tester) async {
    final robot = await open(tester);
    await robot.skip();
    expect(robot.caption, en.calendarGuideTourOpen);

    await robot.showPanel(CalendarPanelMode.timeline);
    await robot.tapTimelineEvent(en.calendarGuideDemoEventYoga);
    expect(robot.detailOpen, isTrue);
    expect(robot.caption, en.calendarGuideTourOpen, reason: 'under the sheet');
    await robot.detailClose();
    expect(robot.caption, en.calendarGuideTourEdit(en.edit, en.save));
    await expectNothingSaved();
  });

  testWidgets("the template picker's Blank saved is the add step", (
    tester,
  ) async {
    final robot = await open(tester);
    for (var i = 0; i < 3; i++) {
      await robot.skip();
    }
    expect(robot.caption, en.calendarGuideTourAdd);

    await robot.longPressAdd();
    await robot.tapId(SemanticsIds.templatePickBlank);
    await robot.typeTitle('Swim');
    await robot.saveEditor();
    expect(robot.caption, en.calendarGuideTourFilter(en.apply));
    await expectNothingSaved();
  });

  testWidgets('a template picked is the add step', (tester) async {
    await seedTemplate('Haircut');
    final robot = await open(tester);
    for (var i = 0; i < 3; i++) {
      await robot.skip();
    }

    await robot.longPressAdd();
    await robot.tapId(
      SemanticsIds.templatePickRow(CalendarTemplates.all.single.id),
    );
    expect(robot.dayPanelTitles, contains('Haircut'));
    expect(robot.caption, en.calendarGuideTourFilter(en.apply));
    await expectNothingSaved();
  });

  testWidgets("with the edit current, the detail sheet's Skip, a format and "
      'a panel mode leave the line where it is', (tester) async {
    final robot = await open(tester);
    await robot.skip();
    await robot.skip();
    final edit = en.calendarGuideTourEdit(en.edit, en.save);
    expect(robot.caption, edit);

    await robot.openRow('guide-demo-yoga');
    await robot.detailSkip();
    expect(robot.detailOpen, isFalse);
    expect(robot.caption, edit);

    await robot.pickFormat(SemanticsIds.calendarFormatWeek);
    expect(robot.caption, edit);

    await robot.showPanel(CalendarPanelMode.timeline);
    expect(robot.caption, edit);
    await expectNothingSaved();
  });

  testWidgets('a report stands until the next action of any kind: a format, '
      'a panel mode, filters applied with none on, the funnel closed', (
    tester,
  ) async {
    final robot = await open(tester);
    final alerts = en.calendarGuideWouldOpen(en.alertsTitle);

    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    expect(robot.caption, alerts);
    await robot.pickFormat(SemanticsIds.calendarFormatWeek);
    expect(robot.caption, en.calendarGuideTourPick);

    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    expect(robot.caption, alerts);
    await robot.showPanel(CalendarPanelMode.timeline);
    expect(robot.caption, en.calendarGuideTourPick);

    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    expect(robot.caption, alerts);
    await robot.openFilters();
    await robot.tapId(SemanticsIds.filterApply);
    expect(robot.caption, en.calendarGuideTourPick);

    // The funnel closed unapplied is an action too (D49).
    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    expect(robot.caption, alerts);
    await robot.openFilters();
    await robot.tapId(SemanticsIds.filterClose);
    expect(robot.caption, en.calendarGuideTourPick);
    expect(robot.canReset, isFalse, reason: 'the funnel is no events step');
    await expectNothingSaved();
  });

  testWidgets('a skip under a standing report only clears it: the step it '
      'covered is shown, not stepped past', (tester) async {
    final robot = await open(tester);

    await robot.pickMore(SemanticsIds.calendarAlertsOpen);
    await robot.skip();
    expect(robot.caption, en.calendarGuideTourPick);
    expect(robot.canReset, isFalse, reason: 'no step is done');

    await robot.skip();
    expect(robot.caption, en.calendarGuideTourOpen);
    await expectNothingSaved();
  });

  /// Walks the band through every line it can show — the idle step, the
  /// view menu's and the ⋮'s reports, then each step skipped to the closing
  /// line — and checks its height against the idle band's after each one.
  Future<void> walkEveryLine(
    PracticeCalendarRobot robot,
    AppLocalizations l10n, {
    GuidePracticeLesson lesson = GuidePracticeLesson.events,
  }) async {
    final idle = robot.bandSize;
    final seen = {robot.caption};
    for (final row in [
      SemanticsIds.calendarOverviewOpen,
      SemanticsIds.calendarReportOpen,
    ]) {
      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(row);
      seen.add(robot.caption);
      expect(robot.bandSize, idle, reason: robot.caption);
    }
    for (final row in [
      SemanticsIds.calendarAlertsOpen,
      SemanticsIds.calendarExport,
      SemanticsIds.calendarGuideOpen,
      SemanticsIds.calendarSettingsOpen,
    ]) {
      await robot.pickMore(row);
      seen.add(robot.caption);
      expect(robot.bandSize, idle, reason: robot.caption);
    }
    while (robot.canSkip) {
      await robot.skip();
      seen.add(robot.caption);
      expect(robot.bandSize, idle, reason: robot.caption);
    }
    expect(seen, {
      for (final step in lesson.steps) step.line(l10n),
      lesson.closing(l10n),
      l10n.calendarGuideWouldOpen(l10n.calendarOverview),
      l10n.calendarGuideWouldOpen(l10n.reportTitle),
      l10n.calendarGuideWouldOpen(l10n.alertsTitle),
      l10n.calendarGuideWouldShare,
      l10n.calendarGuideYouAreHere,
      l10n.calendarGuideWouldOpen(l10n.calendarSettingsRow),
    });
  }

  testWidgets('the band keeps its height whatever line it says', (
    tester,
  ) async {
    final robot = await open(tester, size: const Size(360, 780));
    await walkEveryLine(robot, en);
    await expectNothingSaved();
  });

  testWidgets('de 2.0 on 360: the band keeps its height across every step, '
      'the reports and the closing line', (tester) async {
    final robot = await open(
      tester,
      locale: const Locale('de'),
      textScaler: const TextScaler.linear(2.0),
      size: const Size(360, 780),
    );
    await walkEveryLine(robot, AppLocalizationsDe());
    await expectNothingSaved();
  });

  // The band's slot is as tall as its tallest line; past 1.3 the clamp
  // (D39) holds it, so 2.0 draws as 1.3. Pinned, so a line that grows the
  // band fails here: 72 / 134 / 134 before the tour, never to rise.
  for (final (scale, height) in const [
    (1.0, 72.0),
    (1.3, 111.0),
    (2.0, 111.0),
  ]) {
    testWidgets('de $scale on 360: the band is $height dp', (tester) async {
      final robot = await open(
        tester,
        locale: const Locale('de'),
        textScaler: TextScaler.linear(scale),
        size: const Size(360, 780),
      );
      expect(robot.bandSize.height, height);
      await expectNothingSaved();
    });
  }

  testWidgets('the band reads its first line once: only the tour line is a '
      'live region, and the skip is a node of its own', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    final band = tester.getSemantics(
      find.bySemanticsIdentifier(SemanticsIds.calendarGuidePracticeBanner),
    );
    expect(band.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    expect(band.label, contains(en.calendarGuidePracticeBanner));
    expect(band.label, isNot(contains(en.calendarGuideTourPick)));
    final children = <SemanticsNode>[];
    band.visitChildren((child) {
      children.add(child);
      return true;
    });
    expect(children, hasLength(2));
    final (line, skip) = (children.first, children.last);
    expect(line.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(line.label, en.calendarGuideTourPick);
    expect(line.label, isNot(contains(en.calendarGuidePracticeBanner)));
    expect(skip.getSemanticsData().identifier, SemanticsIds.practiceSkip);
    expect(skip.getSemanticsData().tooltip, en.calendarGuideSkipStep);
    expect(skip.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
    expect(skip.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
    await expectNothingSaved();
  });

  testWidgets('the demo grid\'s chevrons are labelled 48 dp targets and its '
      'month title is plain text', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // The chevrons themselves: the page as a whole also holds the real
    // panel's mode bar, whose segments are the calendar's own decision.
    for (final (glyph, tooltip) in [
      (Icons.chevron_left_rounded, en.dayListPreviousMonth),
      (Icons.chevron_right_rounded, en.dayListNextMonth),
    ]) {
      final chevron = find
          .ancestor(
            of: find.descendant(
              of: find.byWidgetPredicate((widget) => widget is TableCalendar),
              matching: find.byIcon(glyph),
            ),
            matching: find.byType(InkWell),
          )
          .first;
      final node = tester.getSemantics(chevron);
      expect(node.rect.width, greaterThanOrEqualTo(48));
      expect(node.rect.height, greaterThanOrEqualTo(48));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.getSemanticsData().tooltip, tooltip);
    }
    final title = tester.getSemantics(
      find.text(DateFormat.yMMMM('en').format(today)),
    );
    expect(title.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(
      title.getSemanticsData().hasAction(SemanticsAction.longPress),
      isFalse,
    );
    handle.dispose();
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

    testWidgets('a mark made in the sheet survives a reopen, and the sheet '
        'says how the event is going', (tester) async {
      final robot = await open(tester);
      final idle = robot.bandSize;

      await robot.openRow('guide-demo-yoga');
      expect(robot.chipSelected(SemanticsIds.eventDetailPresent), isTrue);
      await robot.tapId(SemanticsIds.eventDetailMissed);
      expect(
        find.descendant(
          of: find.byType(EventDetailSheet),
          matching: find.text(
            en.eventAdherenceSummary(3, 5, PresenceAdherence.windowDays),
          ),
        ),
        findsOneWidget,
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
    await robot.detailClose();
    // A description edit is the tour's change step.
    expect(robot.caption, en.calendarGuideTourAdd);
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
    await robot.detailClose();
    // A dates change is the tour's change step.
    expect(robot.caption, en.calendarGuideTourAdd);

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

    expect(robot.filterBadge, 1);
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

      expect(robot.caption, en.calendarGuideTourPick, reason: 'no filter on');
      expect(robot.canReset, isFalse);
      await expectNothingSaved();
    });

    testWidgets('an event added then deleted leaves the demo clean; the tour '
        'alone keeps it enabled', (tester) async {
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
      // Adding and opening are tour steps, so the bar cannot tell a clean
      // demo apart here: a twin seeded as the page seeds it can.
      expect(robot.canReset, isTrue);
      final twin = GuideDemoCalendar(
        l10n: en,
        today: now,
        categories: (await CategoryService.getInstance()).categories,
      );
      final added = twin.add(
        twin.byId('guide-demo-dentist')!.copyWith(id: twin.newId()),
      );
      expect(twin.isDirty, isTrue);
      twin.remove(added.id);
      expect(twin.isDirty, isFalse);
      await expectNothingSaved();
    });

    testWidgets('a mark then unmark leaves it disabled', (tester) async {
      final robot = await open(tester);

      await robot.pressPresence('guide-demo-yoga', en.eventMarkMissed);
      expect(robot.canReset, isTrue);
      await robot.pressPresence('guide-demo-yoga', en.eventMarkPresent);

      expect(
        robot.dayPanelEntries
            .singleWhere(
              (entry) => entry.title == en.calendarGuideDemoEventYoga,
            )
            .missed,
        isFalse,
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

  testWidgets('the route is named "Practice calendar events", never by the '
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

  group('the filtering lesson', () {
    const filtering = GuidePracticeLesson.filtering;
    final openLine = en.calendarGuideTourFilterOpen;
    final categoryLine = en.calendarGuideTourFilterCategory(
      en.calendarCategories,
      en.apply,
    );
    final traitLine = en.calendarGuideTourFilterTrait(
      en.calendarFilterOnlyShow,
      en.apply,
    );
    final resetLine = en.calendarGuideTourFilterReset(
      en.calendarFilterReset,
      en.apply,
    );

    Future<GuideDemoCalendar> twin() async => GuideDemoCalendar(
      l10n: en,
      today: now,
      categories: (await CategoryService.getInstance()).categories,
      lesson: filtering,
    );

    /// The first visible category: the Dentist wears it, and the funnel's
    /// picker lists it first.
    Future<String> firstCategory() async =>
        (await CategoryService.getInstance()).categories
            .firstWhere((category) => !category.isHidden)
            .id;

    testWidgets('the seed holds the six events plus one per axis, over at '
        'least four categories', (tester) async {
      final demo = await twin();
      CalendarEvent byId(String slug) =>
          demo.byId('${GuideDemoCalendar.idPrefix}$slug')!;

      expect(demo.events, hasLength(12));
      expect(
        demo.events.map((event) => event.title).toList(),
        containsAllInOrder(seedTitles),
      );
      expect(
        {for (final event in demo.events) event.categoryId}.length,
        greaterThanOrEqualTo(4),
      );
      final pilates = byId('pilates');
      expect(pilates.title, en.calendarGuideDemoEventPilates);
      expect(pilates.tracksPresence, isTrue);
      expect(pilates.priority, 2);
      expect(demo.isMissed(pilates, day(-3)), isTrue);
      expect(demo.isMissed(pilates, day(-6)), isFalse);
      expect(byId('piano').endDate!.isBefore(today), isTrue);
      expect(demo.occursOn(byId('piano'), day(-12)), isFalse);
      expect(byId('insurance').countOccurrences, isTrue);
      final tax = byId('tax');
      expect(tax.priority, 1);
      expect(tax.description, en.calendarGuideDemoEventTaxNote);
      expect(tax.allDay, isTrue);
      expect(byId('lunch').allDay, isFalse);
      final plants = byId('plants');
      expect(plants.priority, 5);
      expect(demo.occursOn(plants, today), isTrue);
      expect(demo.occursOn(plants, day(1)), isFalse);
      expect(demo.occursOn(plants, day(3)), isTrue);
      expect(demo.isDirty, isFalse);

      final robot = await open(tester, lesson: filtering);
      expect(robot.caption, openLine);
      expect(
        robot.dayPanelTitles,
        containsAll([
          en.calendarGuideDemoEventYoga,
          en.calendarGuideDemoEventPlants,
        ]),
      );
      await expectNothingSaved();
    });

    testWidgets('the tour in order through the real sheet: a category, a '
        'trait, Reset, then the closing line', (tester) async {
      final robot = await open(tester, lesson: filtering);
      final hidden = await firstCategory();
      final demo = await twin();
      final hiddenTitles = {
        for (final event in demo.events)
          if (event.categoryId == hidden) event.title,
      };
      expect(robot.caption, openLine);

      await robot.openFilters();
      await robot.toggleFilterCategory(hidden);
      expect(robot.caption, openLine, reason: 'under the sheet');
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, traitLine);
      expect(robot.filterBadge, 1);
      expect(robot.barLabels.where(hiddenTitles.contains), isEmpty);

      await robot.openFilters();
      await robot.toggleOnlyShow('tracked');
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, resetLine);
      expect(robot.filterBadge, 2);

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterReset);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, en.calendarGuideTourFilterDone);
      expect(robot.filterBadge, isNull);
      expect(robot.canSkip, isFalse);
      await expectNothingSaved();
    });

    testWidgets('the closing line waits for both kinds: filters taken off '
        'before a trait was set do not end the tour', (tester) async {
      final robot = await open(tester, lesson: filtering);

      await robot.openFilters();
      await robot.toggleFilterCategory(await firstCategory());
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, traitLine);

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterReset);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.filterBadge, isNull);
      expect(robot.caption, traitLine);

      await robot.openFilters();
      await robot.toggleOnlyShow('tracked');
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, resetLine, reason: 'not the closing line');

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterReset);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, en.calendarGuideTourFilterDone);
      await expectNothingSaved();
    });

    /// The live demo, read off the grid the page hands it to.
    GuideDemoCalendar liveDemo(WidgetTester tester) =>
        tester.widget<GuideCalendarGrid>(find.byType(GuideCalendarGrid)).demo;

    /// Every day the demo's per-day map can hold, around today's month.
    final window = [for (var offset = -70; offset <= 70; offset++) day(offset)];

    testWidgets('through the funnel: Missed only keeps Yoga and Pilates and '
        'nothing else; a hidden category takes exactly its own events', (
      tester,
    ) async {
      final robot = await open(tester, lesson: filtering);
      final demo = liveDemo(tester);
      final unfiltered = {
        for (final d in window) d: [for (final e in demo.eventsFor(d)) e.id],
      };

      await robot.openFilters();
      await robot.toggleOnlyShow('missed');
      await robot.tapId(SemanticsIds.filterApply);
      expect(
        {
          for (final d in window)
            for (final event in demo.eventsFor(d)) event.title,
        },
        {en.calendarGuideDemoEventYoga, en.calendarGuideDemoEventPilates},
      );
      expect(
        demo.eventsFor(day(-3)).map((event) => event.title),
        contains(en.calendarGuideDemoEventPilates),
      );

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterReset);
      await robot.tapId(SemanticsIds.filterApply);
      final hidden = await firstCategory();
      final hiddenIds = {
        for (final event in demo.events)
          if (event.categoryId == hidden) event.id,
      };
      expect(hiddenIds, isNotEmpty);
      await robot.openFilters();
      await robot.toggleFilterCategory(hidden);
      await robot.tapId(SemanticsIds.filterApply);
      for (final d in window) {
        expect(
          [for (final event in demo.eventsFor(d)) event.id],
          [
            for (final id in unfiltered[d]!)
              if (!hiddenIds.contains(id)) id,
          ],
          reason: '$d',
        );
      }
      expect(
        unfiltered.values.expand((ids) => ids).where(hiddenIds.contains),
        isNotEmpty,
        reason: 'the window held some of its events',
      );
      await expectNothingSaved();
    });

    testWidgets('the band keeps its height over every filtering line', (
      tester,
    ) async {
      final robot = await open(
        tester,
        lesson: filtering,
        size: const Size(360, 780),
      );
      await walkEveryLine(robot, en, lesson: filtering);
      await expectNothingSaved();
    });

    testWidgets('de 2.0 on 360: the band keeps its height over every '
        'filtering line', (tester) async {
      final robot = await open(
        tester,
        lesson: filtering,
        locale: const Locale('de'),
        textScaler: const TextScaler.linear(2.0),
        size: const Size(360, 780),
      );
      await walkEveryLine(robot, AppLocalizationsDe(), lesson: filtering);
      await expectNothingSaved();
    });

    // The events lesson's pin (D38 / D39) holds for this lesson's lines.
    for (final (scale, height) in const [
      (1.0, 72.0),
      (1.3, 111.0),
      (2.0, 111.0),
    ]) {
      testWidgets('de $scale on 360: the band is $height dp', (tester) async {
        final robot = await open(
          tester,
          lesson: filtering,
          locale: const Locale('de'),
          textScaler: TextScaler.linear(scale),
          size: const Size(360, 780),
        );
        expect(robot.bandSize.height, height);
        await expectNothingSaved();
      });
    }

    testWidgets('the funnel closed unapplied is the first step', (
      tester,
    ) async {
      final robot = await open(tester, lesson: filtering);

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterClose);
      expect(robot.caption, categoryLine);
      expect(robot.filterBadge, isNull);
      await expectNothingSaved();
    });

    testWidgets('a step done early is not asked again: one Apply that hides a '
        'category and sets a trait marks both', (tester) async {
      final robot = await open(tester, lesson: filtering);

      await robot.openFilters();
      await robot.toggleFilterCategory(await firstCategory());
      await robot.toggleOnlyShow('tracked');
      await robot.tapId(SemanticsIds.filterApply);

      expect(robot.caption, resetLine);
      expect(robot.filterBadge, 2);
      await expectNothingSaved();
    });

    testWidgets('a layer turned off is a trait', (tester) async {
      final robot = await open(tester, lesson: filtering);

      await robot.openFilters();
      await robot.tapId(SemanticsIds.filterHolidays);
      await robot.tapId(SemanticsIds.filterApply);

      expect(robot.filterBadge, 1);
      // The category step is still ahead: the band asks for it first.
      expect(robot.caption, categoryLine);
      await robot.skip();
      expect(robot.caption, resetLine, reason: 'the trait is done');
      await expectNothingSaved();
    });

    testWidgets("Start over restores the lesson's twelve events and the "
        'first line', (tester) async {
      final robot = await open(tester, lesson: filtering);
      final seeded = robot.barLabels;

      await robot.openFilters();
      await robot.toggleFilterCategory(await firstCategory());
      await robot.tapId(SemanticsIds.filterApply);
      await robot.add();
      await robot.typeTitle('Swim');
      await robot.saveEditor();
      // The bars are no signal that anything changed: the new event takes the
      // default category, which this filter has just hidden, so it draws no
      // bar; and whether the hidden category's seeded event is on the shown
      // page at all depends on the date (on 2026-10-31 it was not, and the
      // bars read the same as the seed). What always changes is the filter
      // badge and the reset becoming available.
      expect(robot.filterBadge, 1);
      expect(robot.canReset, isTrue);

      await robot.reset();
      expect(robot.caption, openLine);
      expect(robot.filterBadge, isNull);
      expect(robot.canReset, isFalse);
      expect(robot.barLabels, seeded);
      await expectNothingSaved();
    });

    testWidgets('the route is named "Practice calendar filtering" over its '
        'own container', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, lesson: filtering);

      final named = [
        for (final node
            in find.semantics
                .byPredicate(
                  (node) => node.getSemanticsData().flagsCollection.namesRoute,
                )
                .evaluate())
          node.getSemanticsData().label,
      ];
      expect(named, contains(en.calendarGuidePagePracticeFiltering));
      expect(named, isNot(contains(en.calendarGuidePagePractice)));
      expect(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuidePracticeFiltering),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuidePractice),
        findsNothing,
      );
      handle.dispose();
      await expectNothingSaved();
    });

    testWidgets('de 2.0 on 360: no overflow', (tester) async {
      final errors = await layoutErrorsDuring(() async {
        final robot = await open(
          tester,
          lesson: filtering,
          locale: const Locale('de'),
          textScaler: const TextScaler.linear(2.0),
          size: const Size(360, 780),
        );
        await robot.showPanel(CalendarPanelMode.upcoming);
      });
      expect([
        for (final error in errors) error.toDiagnosticsNode().toStringDeep(),
      ], isEmpty);
      await expectNothingSaved();
    });
  });

  // Android's 48 dp targets — `PanelModeBar`'s 32 dp segments, the real
  // calendar's chrome, taken out by name — and WCAG's text contrast, on both
  // lessons, both phones, both themes.
  for (final lesson in GuidePracticeLesson.values) {
    for (final size in const [Size(360, 780), Size(412, 915)]) {
      for (final brightness in Brightness.values) {
        testWidgets('${lesson.name} ${size.width.toInt()} ${brightness.name}: '
            'the tap-target and text-contrast guidelines', (tester) async {
          final handle = tester.ensureSemantics();
          await open(
            tester,
            lesson: lesson,
            brightness: brightness,
            size: size,
          );
          await expectLater(
            tester,
            meetsGuideline(GuideTapTargetGuideline.of(tester)),
          );
          await expectLater(
            tester,
            meetsGuideline(const GuideTextContrastGuideline()),
          );
          handle.dispose();
          await expectNothingSaved();
        });
      }
    }
  }

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
