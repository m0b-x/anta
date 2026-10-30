import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_guide_coach.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/alarm_page.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_time_formatter.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/recurrence_formatter.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/agenda_month_store.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/widgets/agenda_day_list_rows.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/agenda_month_grid.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/agenda_year_grid.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/calendar_bottom_panel.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/calendar_appearance_preview.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_filter_sheet.dart';
import 'package:anta/widgets/calendar_guide_stage_slot.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/calendar_guide_try_screen.dart';
import 'package:anta/widgets/category_editor_sheet.dart';
import 'package:anta/widgets/day_summary_panel.dart';
import 'package:anta/widgets/day_timeline_view.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/year_month_tile.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';
import 'support/category_editor_robot.dart';
import 'support/fasting_schedule_robot.dart';
import 'support/fasting_style_robot.dart';
import 'support/guide_guidelines.dart';
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
    // The fasting card never configures the engine (D62).
    FastingCalendar.revision,
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
    DateTime Function() now = DateTime.now,
    String? card,
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
          home: CalendarGuideTopicPage(topic: topic, now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pushes.pushed.clear();
    shownSlots.clear();
    final robot = GuideTryCardRobot(tester, card ?? topic.slug);
    // A card further down the page is built once the list reaches it; a
    // page's first card carries the page's slug and opens in view.
    if (card != null && card != topic.slug) await robot.reveal();
    return robot;
  }

  /// [card]'s instructions in English, in step order.
  List<String> stepsOfCard(GuideCardSpec card) => [
    for (final step in card.steps) step.line(en),
  ];

  /// The screen page's three cards (D58), by slug.
  final screenCards = {
    for (final card in CalendarGuideTopic.screen.cards) card.slug: card,
  };

  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime day(int offset) =>
      DateTime.utc(today.year, today.month, today.day + offset);
  // Built on first use: the locale data loads in setUpAll.
  late final dates = DateFormat.yMMMMEEEEd('en');
  // The events card's Skipped report writes the band's short date (D52).
  late final shortDates = DateFormat.MMMEd('en');

  void note(GuideTryCardRobot robot) => shownSlots[robot.line] = robot.slotSize;

  /// The clock a generic case opens [topic]'s card on: the fasting card's
  /// fast days depend on the date, so its cases stand in Great Lent 2027
  /// whatever day the suite runs; the other cards read today.
  DateTime Function() fixedNowFor(CalendarGuideTopic topic) =>
      topic == CalendarGuideTopic.fasting
      ? () => DateTime(2027, 3, 17, 10)
      : DateTime.now;

  /// [topic]'s instructions in English, in step order.
  List<String> stepsOf(CalendarGuideTopic topic) => [
    for (final card in topic.cards)
      for (final step in card.steps) step.line(en),
  ];

  void expectOneSlotHeight() {
    expect(shownSlots.length, greaterThan(1));
    expect(shownSlots.values.toSet(), hasLength(1), reason: '$shownSlots');
    shownSlots.clear();
  }

  group('the frame', () {
    testWidgets('the card comes first, above How it works', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);

      expect(robot.card, findsOneWidget);
      expect(
        tester.getTopLeft(find.text(en.calendarGuideTryIt)).dy,
        lessThan(tester.getTopLeft(find.text(en.calendarGuideHowItWorks)).dy),
      );
      // The first instruction is the entry's searchable title, drawn as the
      // coach line until she acts — above the stage.
      final first = stepsOf(CalendarGuideTopic.events).first;
      final list = tester.widget<SettingsSectionList>(
        find.byType(SettingsSectionList),
      );
      expect(list.sections.first.entries.single.title, first);
      expect(robot.line, first);
      expect(
        robot.slotRect.bottom,
        lessThan(
          tester
              .getRect(
                find
                    .descendant(
                      of: robot.card,
                      matching: find.byType(RepaintBoundary),
                    )
                    .first,
              )
              .top,
        ),
      );
      await expectNothingSaved();
    });

    // D52: the skip's glyph sits on the line's first row, as the band's does,
    // and not 14 dp below it.
    for (final (locale, size, scale) in const [
      (Locale('en'), Size(412, 915), 1.0),
      (Locale('de'), Size(360, 780), 2.0),
    ]) {
      testWidgets('the skip\'s glyph is centred on the line\'s first row: '
          '${locale.languageCode} $scale', (tester) async {
        final robot = await open(
          tester,
          CalendarGuideTopic.events,
          locale: locale,
          size: size,
          textScaler: TextScaler.linear(scale),
        );
        final glyph = tester.getCenter(
          find.descendant(of: robot.skipButton, matching: find.byType(Icon)),
        );
        final line = find.descendant(
          of: find.bySemanticsIdentifier(
            SemanticsIds.calendarGuideTryCaption(
              CalendarGuideTopic.events.slug,
            ),
          ),
          matching: find.byType(RichText),
        );
        final firstRow = tester
            .renderObject<RenderParagraph>(line)
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 1),
              boxHeightStyle: ui.BoxHeightStyle.max,
            )
            .first;
        final rowCentre =
            tester.getTopLeft(line).dy + (firstRow.top + firstRow.bottom) / 2;
        expect(glyph.dy, moreOrLessEquals(rowCentre, epsilon: 1));
        await expectNothingSaved();
      });
    }

    test('a demo disposed while its sheet is up marks nothing when the sheet '
        'answers, and does not throw', () async {
      final demo = _SheetProbeDemo();
      var redraws = 0;
      demo.addListener(() => redraws++);
      final sheet = Completer<void>();
      final opened = demo.open(sheet.future);

      demo.dispose();
      sheet.complete();
      // A notify after dispose would throw here.
      await opened;
      expect(redraws, 0);
    });

    testWidgets('a page with nothing to try has no card', (tester) async {
      await open(tester, CalendarGuideTopic.good);

      expect(find.text(en.calendarGuideTryIt), findsNothing);
      expect(find.byType(CalendarGuideTryCard), findsNothing);
    });

    testWidgets('the entry is a container node, never merged: the stage\'s '
        'controls, the skip and the live line are nodes of their own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
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

      final skip = tester.getSemantics(robot.skipButton);
      expect(skip.id, isNot(entry.id));
      expect(under(add), isTrue);
      expect(under(caption), isTrue);
      expect(under(skip), isTrue);
      expect(
        caption.getSemanticsData().label,
        stepsOf(CalendarGuideTopic.screen).first,
      );
      expect(skip.getSemanticsData().tooltip, en.calendarGuideSkipStep);
      expect(skip.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
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
      final said = robot.line;
      expect(said, isNot(stepsOf(CalendarGuideTopic.alerts).first));

      final list = find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuideRow('open-often')),
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
      expect(robot.line, said);
      expect(robot.control('alert-0'), findsOneWidget);
      await expectNothingSaved();
    });
  });

  group('the coach walks every card\'s steps', () {
    for (final topic in CalendarGuideTopic.values) {
      for (final card in topic.cards) {
        testWidgets('${card.slug}: idle on the first step alone, skip to the '
            'closing line, then disabled', (tester) async {
          final robot = await open(
            tester,
            topic,
            now: fixedNowFor(topic),
            card: card.slug,
          );
          final steps = stepsOfCard(card);
          // The card's entry is searched by its first instruction (D48).
          final entry = tester
              .widget<SettingsSectionList>(find.byType(SettingsSectionList))
              .sections
              .expand((section) => section.entries)
              .singleWhere(
                (entry) =>
                    entry.identifier ==
                    SemanticsIds.calendarGuideTry(card.slug),
              );
          expect(entry.title, steps.first);
          expect(robot.line, steps.first);
          note(robot);

          for (final next in steps.skip(1)) {
            expect(robot.canSkip, isTrue);
            await robot.skip();
            // With every tradition off the fasting card keeps asking for
            // one until its last step is past (D44).
            expect(
              robot.line,
              topic == CalendarGuideTopic.fasting ? steps.first : next,
            );
            note(robot);
          }
          await robot.skip();
          expect(robot.line, en.calendarGuideCoachDone);
          note(robot);
          // Disabled, never hidden.
          expect(robot.canSkip, isFalse);
          expect(robot.skipButton, findsOneWidget);
          expect(
            robot.lineCandidates,
            containsAll([...steps, en.calendarGuideCoachDone]),
          );
          expect(pushes.pushed, isEmpty);
          expectOneSlotHeight();
          await expectNothingSaved();
        });
      }
    }
  });

  group('screen', () {
    final steps = stepsOfCard(screenCards['screen']!);
    final yoga = en.calendarGuideDemoEventYoga;

    testWidgets('three cards under their own titles, the grid first, all '
        'above How it works', (tester) async {
      await open(tester, CalendarGuideTopic.screen);
      final list = tester.widget<SettingsSectionList>(
        find.byType(SettingsSectionList),
      );
      final cards = CalendarGuideTopic.screen.cards;
      expect(
        [for (final card in cards) card.slug],
        ['screen', 'panel', 'overview'],
      );
      expect(
        [for (final section in list.sections.take(3)) section.title],
        [
          en.calendarGuideCardGrid,
          en.calendarGuideCardPanel,
          en.calendarGuideCardOverview,
        ],
      );
      expect(
        [
          for (final section in list.sections.take(3))
            section.entries.single.title,
        ],
        [for (final card in cards) stepsOfCard(card).first],
      );
      expect(list.sections[3].title, en.calendarGuideHowItWorks);
      expect(find.text(en.calendarGuideTryIt), findsNothing);
      await expectNothingSaved();
    });

    testWidgets('the grid card: the title menu reshapes the grid in one '
        'height, the Overview row reports, the ⋮ moves the line on; nothing '
        'opens', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      final stage = robot.stageSize;
      expect(robot.line, steps[0]);
      note(robot);

      for (final (id, format) in const [
        (SemanticsIds.calendarFormatTwoWeeks, CalendarFormat.twoWeeks),
        (SemanticsIds.calendarFormatWeek, CalendarFormat.week),
        (SemanticsIds.calendarFormatMonth, CalendarFormat.month),
      ]) {
        await robot.tapId(SemanticsIds.calendarViewMenu);
        await robot.tapId(id);
        expect(_gridOf(tester, 'screen').calendarFormat, format);
        expect(robot.stageSize, stage, reason: format.name);
        expect(robot.line, steps[1]);
      }
      note(robot);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarOverviewOpen);
      expect(robot.line, en.calendarGuideWouldOpen(en.calendarOverview));
      note(robot);

      for (final row in [
        SemanticsIds.calendarAlertsOpen,
        SemanticsIds.calendarExport,
        SemanticsIds.calendarGuideOpen,
        SemanticsIds.calendarSettingsOpen,
      ]) {
        await robot.tap('more');
        await robot.tapId(row);
        expect(robot.line, en.calendarGuideCoachDone);
        note(robot);
      }
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the grid card: a step done early is not asked again', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.screen);

      await robot.tap('more');
      await robot.tapId(SemanticsIds.calendarSettingsOpen);
      expect(robot.line, steps[0]);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarFormatWeek);
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.canSkip, isFalse);
      await expectNothingSaved();
    });

    testWidgets('the panel card: every mode moves the line on in one height; '
        'the expand button and the presence button are not offered', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'panel',
      );
      final stage = robot.stageSize;
      expect(robot.line, stepsOfCard(screenCards['panel']!).single);
      note(robot);
      expect(
        tester.widget<DaySummaryPanel>(find.byType(DaySummaryPanel)).day,
        today,
      );
      expect(
        tester
            .widget<DaySummaryPanel>(find.byType(DaySummaryPanel))
            .onToggleMissed,
        isNull,
      );

      for (final (mode, body) in [
        ('timeline', DayTimelineView),
        ('upcoming', AgendaDayListRowBuilder),
        ('day', DaySummaryPanel),
      ]) {
        await robot.tapId(SemanticsIds.panelMode(mode));
        expect(robot.line, en.calendarGuideCoachDone, reason: mode);
        expect(robot.stageSize, stage, reason: mode);
        if (body != AgendaDayListRowBuilder) {
          expect(_inCard('panel', find.byType(body)), findsOneWidget);
        }
        note(robot);
      }
      // Disabled, never hidden: the card has no grid to cover.
      final expand = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(PanelModeBar),
          matching: find.byType(IconButton),
        ),
      );
      expect(expand.onPressed, isNull);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the overview card: the chips switch modes in one slot, the '
        'arrows and Today step the period, a tile opens its month', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'overview',
      );
      final steps = stepsOfCard(screenCards['overview']!);
      final stage = robot.stageSize;
      String title() => _navOf(tester).title;
      DateTime gridMonth() => tester
          .widget<AgendaMonthGrid>(
            _inCard('overview', find.byType(AgendaMonthGrid)),
          )
          .month;
      expect(robot.line, steps[0]);
      note(robot);

      // D68: Month, on the shared day's month, the day picked; the search
      // drawn disabled.
      expect(robot.chip('mode-month').selected, isTrue);
      final thisMonth = DateTime.utc(today.year, today.month);
      expect(gridMonth(), thisMonth);
      expect(
        tester
            .widget<AgendaMonthGrid>(
              _inCard('overview', find.byType(AgendaMonthGrid)),
            )
            .selectedDay,
        today,
      );
      expect(title(), AgendaListView.monthLabel('en', thisMonth, withYear: true));
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: robot.control('search'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await robot.tap('mode-year');
      expect(robot.line, steps[1]);
      expect(robot.stageSize, stage, reason: 'year');
      // Year: the year's twelve tiles.
      expect(
        tester
            .widget<AgendaYearGrid>(
              _inCard('overview', find.byType(AgendaYearGrid)),
            )
            .tiles
            .map((tile) => tile.month),
        AgendaMonthStore.monthsOfYear(today.year),
      );
      expect(title(), '${today.year}');
      note(robot);

      await robot.tap('next');
      expect(robot.line, en.calendarGuideCoachDone);
      expect(title(), '${today.year + 1}');
      await robot.tap('today');
      expect(title(), '${today.year}');

      await robot.tap('mode-list');
      expect(robot.stageSize, stage, reason: 'list');
      expect(title(), _monthSpanLabel(thisMonth));

      await robot.tap('mode-month');
      expect(robot.stageSize, stage, reason: 'month');
      await robot.tap('previous');
      expect(gridMonth(), DateTime.utc(today.year, today.month - 1));

      // A tile opens its month, as the overview's do: here the month she
      // was on, whose row Year opens on.
      await robot.tap('mode-year');
      expect(robot.stageSize, stage, reason: 'year');
      final lastMonth = DateTime.utc(today.year, today.month - 1);
      await _tapOnPage(tester, 'overview', _yearTile(lastMonth));
      expect(robot.chip('mode-month').selected, isTrue);
      expect(gridMonth(), lastMonth);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    // D68: three rows of four fit the slot, so Year opens scrolled to the
    // row of the month she was on — from its own scroll offset, laid out by
    // the grid's delegate.
    for (final (shown, size) in [
      (DateTime.utc(2027, 5), const Size(412, 915)),
      (DateTime.utc(2027, 5), const Size(360, 780)),
      (DateTime.utc(2027, 12), const Size(360, 780)),
    ]) {
      testWidgets('the overview card: Year opens on the row that holds the '
          'month shown, ${shown.month} on ${size.width.toInt()}', (
        tester,
      ) async {
        final robot = await open(
          tester,
          CalendarGuideTopic.screen,
          card: 'overview',
          size: size,
          now: () => DateTime(shown.year, shown.month, 12, 10),
        );
        await robot.tap('mode-year');
        final grid = find
            .descendant(
              of: _inCard('overview', find.byType(AgendaYearGrid)),
              matching: find.byType(Scrollable),
            )
            .first;
        // Where the shown month's tile sits in the slot, and how far the
        // slot has scrolled.
        (Rect, ScrollPosition) measure() {
          final viewport = tester.getRect(grid);
          final rect = tester.getRect(_yearTile(shown));
          return (
            rect.shift(-viewport.topLeft),
            tester.state<ScrollableState>(grid).position,
          );
        }

        final (tile, position) = measure();
        final viewport = tester.getSize(grid);
        // Whole in the slot.
        expect(tile.top, greaterThanOrEqualTo(-0.5));
        expect(tile.bottom, lessThanOrEqualTo(viewport.height + 0.5));
        final columns = YearMonthTile.columnsFor(viewport.width);
        final row = (shown.month - 1) ~/ columns;
        if (position.pixels < position.maxScrollExtent - 0.5) {
          // Its row the slot's first: the row above is scrolled off.
          expect(row, greaterThan(0));
          expect(tile.top, moreOrLessEquals(0, epsilon: 0.5));
        } else {
          // A last row cannot reach the top: the grid stops at its end, the
          // row in view.
          expect(position.maxScrollExtent, greaterThan(0));
        }
        // Stepped away and back, the year opens on that row again.
        await robot.tap('next');
        await robot.tap('previous');
        expect(measure().$1, rectMoreOrLessEquals(tile, epsilon: 0.01));
        await expectNothingSaved();
      });
    }

    testWidgets('the overview card: List lists the shown month; ◄ ► step a '
        'month in Month and List and a year in Year', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'overview',
        now: () => DateTime(2027, 5, 12, 10),
      );
      String title() => _navOf(tester).title;
      final may = DateTime.utc(2027, 5);
      final june = DateTime.utc(2027, 6);
      // The months the list's sections name, by their labels.
      Set<DateTime> listedMonths() {
        final labels = {
          for (final label in tester.widgetList<FormSectionLabel>(
            _inCard(
              'overview',
              find.descendant(
                of: find.byType(ListView),
                matching: find.byType(FormSectionLabel),
              ),
            ),
          ))
            label.text,
        };
        return {
          for (var m = 0; m <= 13; m++)
            if (DateTime.utc(2027, m) case final month
                when labels.contains(
                      AgendaListView.monthLabel('en', month, withYear: true),
                    ) ||
                    labels.contains(
                      AgendaListView.monthLabel('en', month, withYear: false),
                    ))
              month,
        };
      }

      await robot.tap('mode-list');
      expect(title(), _monthSpanLabel(may));
      expect(listedMonths(), {may});
      await robot.tap('next');
      expect(title(), _monthSpanLabel(june));
      expect(listedMonths(), {june});

      await robot.tap('mode-month');
      expect(title(), AgendaListView.monthLabel('en', june, withYear: true));
      await robot.tap('next');
      expect(
        title(),
        AgendaListView.monthLabel('en', DateTime.utc(2027, 7), withYear: true),
      );

      await robot.tap('mode-year');
      expect(title(), '2027');
      await robot.tap('next');
      expect(title(), '2028');
      await robot.tap('today');
      expect(title(), '2027');
      await robot.tap('mode-list');
      expect(title(), _monthSpanLabel(may));
      await expectNothingSaved();
    });

    testWidgets('one picked day: the grid\'s pick is the panel\'s day and '
        'the overview month\'s, and a day picked there is the grid\'s', (
      tester,
    ) async {
      final screen = await open(tester, CalendarGuideTopic.screen);
      // Yoga's day a week away, inside today's month either way.
      final picked = today.day > 7 ? day(-7) : day(7);
      await _tapCell(tester, 'screen', picked);
      expect(_cellOf(tester, 'screen', picked).isSelected, isTrue);

      final panel = GuideTryCardRobot(tester, 'panel');
      await panel.reveal();
      expect(
        tester.widget<DaySummaryPanel>(find.byType(DaySummaryPanel)).day,
        picked,
      );

      final overview = GuideTryCardRobot(tester, 'overview');
      await overview.reveal();
      await overview.tap('mode-month');
      expect(
        tester
            .widget<AgendaMonthGrid>(
              _inCard('overview', find.byType(AgendaMonthGrid)),
            )
            .selectedDay,
        picked,
      );
      // The picked day's rows sit under the mini month, in the slot's own
      // scroll.
      final slot = _inCard('overview', find.byType(CustomScrollView));
      await tester.drag(slot, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        _inCard('overview', find.text(yoga, findRichText: true)),
        findsWidgets,
      );
      await tester.drag(slot, const Offset(0, 300));
      await tester.pumpAndSettle();

      // The first of the month carries the rent: a day to pick there.
      final first = DateTime.utc(today.year, today.month, 1);
      await _tapCell(tester, 'overview', first);
      expect(
        tester
            .widget<AgendaMonthGrid>(
              _inCard('overview', find.byType(AgendaMonthGrid)),
            )
            .selectedDay,
        first,
      );
      await tester.drag(slot, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        _inCard(
          'overview',
          find.text(en.calendarGuideDemoEventRent, findRichText: true),
        ),
        findsWidgets,
      );
      await panel.reveal();
      expect(
        tester.widget<DaySummaryPanel>(find.byType(DaySummaryPanel)).day,
        first,
      );
      await screen.reveal();
      expect(_cellOf(tester, 'screen', first).isSelected, isTrue);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    testWidgets('no tap on a stage opens a page or a sheet: a grid day, a '
        'panel row, a timeline block, an upcoming row, a year tile, a '
        'month-grid day, a list row', (tester) async {
      await open(tester, CalendarGuideTopic.screen);
      void expectNothingOpened(String what) {
        expect(pushes.pushed, isEmpty, reason: what);
        expect(find.byType(BottomSheet), findsNothing, reason: what);
        expect(find.byType(EventDetailSheet), findsNothing, reason: what);
        expect(find.byType(EventEditorSheet), findsNothing, reason: what);
      }

      await _tapCell(tester, 'screen', today);
      expectNothingOpened('a grid day');
      // A long press offers nothing either: no quick add on a card.
      await tester.longPress(_cellTarget('screen', today));
      await tester.pumpAndSettle();
      expectNothingOpened('a grid day held');

      final panel = GuideTryCardRobot(tester, 'panel');
      await panel.reveal();
      await panel.tapId(SemanticsIds.eventRow('guide-demo-yoga'));
      expectNothingOpened('a panel row');
      await panel.tapId(SemanticsIds.panelMode('timeline'));
      await tester.tap(
        find.descendant(
          of: find.byType(DayTimelineView),
          matching: find.text(yoga),
        ),
      );
      await tester.pumpAndSettle();
      expectNothingOpened('a timeline block');
      await panel.tapId(SemanticsIds.panelMode('upcoming'));
      await tester.tap(
        _inCard('panel', find.text(yoga, findRichText: true)).first,
      );
      await tester.pumpAndSettle();
      expectNothingOpened('an upcoming row');

      final overview = GuideTryCardRobot(tester, 'overview');
      await overview.reveal();
      await overview.tap('mode-year');
      // This month's tile, in the row Year opens on; it opens this month.
      await _tapOnPage(
        tester,
        'overview',
        _yearTile(DateTime.utc(today.year, today.month)),
      );
      expectNothingOpened('a year tile');
      await _tapCell(tester, 'overview', DateTime.utc(today.year, today.month));
      expectNothingOpened('a month-grid day');
      await tester.drag(
        _inCard('overview', find.byType(CustomScrollView)),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        _inCard(
          'overview',
          find.text(en.calendarGuideDemoEventRent, findRichText: true),
        ).first,
      );
      await tester.pumpAndSettle();
      expectNothingOpened('a month row');
      // This month's list: the rent is on its first.
      await overview.tap('mode-list');
      await tester.tap(
        _inCard(
          'overview',
          find.text(en.calendarGuideDemoEventRent, findRichText: true),
        ).first,
      );
      await tester.pumpAndSettle();
      expectNothingOpened('a list row');
      await expectNothingSaved();
    });

    ScrollPosition pageOf(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SettingsSectionList),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    testWidgets('a slot\'s end hands a drag on to the page; a slot with '
        'more to show scrolls itself and not the page', (tester) async {
      final panel = await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'panel',
      );
      await panel.tapId(SemanticsIds.panelMode('upcoming'));
      final slot = tester
          .state<ScrollableState>(
            _inCard('panel', find.byType(Scrollable)).first,
          )
          .position;
      final page = pageOf(tester);
      expect(page.pixels, greaterThan(100));
      expect(slot.pixels, 0);
      final start = tester.getCenter(
        _inCard('panel', find.byType(Scrollable)).first,
      );

      // Up the slot: the list has more below, so it scrolls and the page
      // stays.
      var gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -kTouchSlop - 2));
      await tester.pump();
      final pageBefore = page.pixels;
      final slotBefore = slot.pixels;
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(slot.pixels, moreOrLessEquals(slotBefore + 60));
      expect(page.pixels, pageBefore);
      await gesture.up();
      await tester.pumpAndSettle();

      // Back to the slot's top, then on down: past its end the finger moves
      // the page by the same distance.
      slot.jumpTo(0);
      await tester.pump();
      gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, kTouchSlop + 2));
      await tester.pump();
      final pageAtEnd = page.pixels;
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(slot.pixels, 0);
      expect(page.pixels, moreOrLessEquals(pageAtEnd - 60));
      // A fling's overscroll is not handed on: the page stops with the
      // finger.
      final pageAtLift = page.pixels;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(page.pixels, pageAtLift);
      await expectNothingSaved();
    });

    testWidgets('the mini month: a swipe to half-way and back keeps its '
        'month and its grid', (tester) async {
      final overview = await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'overview',
      );
      await overview.tap('mode-month');
      final grid = _inCard(
        'overview',
        find.byWidgetPredicate((widget) => widget is TableCalendar),
      );
      final element = tester.element(grid);
      final month = DateTime.utc(today.year, today.month);
      final width = tester.getSize(grid).width;

      final gesture = await tester.startGesture(tester.getCenter(grid));
      for (var step = 0; step < 6; step++) {
        await gesture.moveBy(Offset(-width * 0.1, 0));
        await tester.pump();
      }
      for (var step = 0; step < 6; step++) {
        await gesture.moveBy(Offset(width * 0.1, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<AgendaMonthGrid>(
              _inCard('overview', find.byType(AgendaMonthGrid)),
            )
            .month,
        month,
      );
      expect(identical(tester.element(grid), element), isTrue);
      await expectNothingSaved();
    });

    testWidgets('the mini month: the picked day tapped again lists the whole '
        'month, the shared day kept; again, the day', (tester) async {
      final overview = await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'overview',
      );
      await overview.tap('mode-month');
      AgendaMonthGrid grid() => tester.widget<AgendaMonthGrid>(
        _inCard('overview', find.byType(AgendaMonthGrid)),
      );
      expect(grid().selectedDay, today);

      await _tapCell(tester, 'overview', today);
      expect(grid().selectedDay, isNull);
      await overview.reveal();
      final panel = GuideTryCardRobot(tester, 'panel');
      await panel.reveal();
      expect(
        tester.widget<DaySummaryPanel>(find.byType(DaySummaryPanel)).day,
        today,
      );

      await overview.reveal();
      await _tapCell(tester, 'overview', today);
      expect(grid().selectedDay, today);
      await expectNothingSaved();
    });

    testWidgets('a language change writes the demo again in it', (
      tester,
    ) async {
      await open(tester, CalendarGuideTopic.screen, card: 'panel');
      await open(
        tester,
        CalendarGuideTopic.screen,
        card: 'panel',
        locale: const Locale('de'),
      );
      await GuideTryCardRobot(
        tester,
        'panel',
      ).tapId(SemanticsIds.panelMode('upcoming'));
      // The dentist is two days out: down the slot's list until it is built.
      final dentist = _inCard(
        'panel',
        find.text(
          AppLocalizationsDe().calendarGuideDemoEventDentist,
          findRichText: true,
        ),
      );
      final slot = tester
          .state<ScrollableState>(
            _inCard('panel', find.byType(Scrollable)).first,
          )
          .position;
      for (var i = 0; i < 20 && dentist.evaluate().isEmpty; i++) {
        slot.jumpTo((slot.pixels + 100).clamp(0.0, slot.maxScrollExtent));
        await tester.pump();
      }
      expect(dentist, findsWidgets);
      expect(
        _inCard(
          'panel',
          find.text(en.calendarGuideDemoEventDentist, findRichText: true),
        ),
        findsNothing,
      );
      await expectNothingSaved();
    });

    test('the picks survive the categories arriving; the same categories '
        'rebuild nothing', () {
      final world = GuideScreenWorld(now: () => DateTime(2026, 10, 30));
      world.ensureCalendar(en);
      final first = world.calendar!
        ..selectedDay = DateTime.utc(2026, 10, 12)
        ..format = CalendarFormat.week
        ..panelMode = CalendarPanelMode.upcoming
        ..focus(DateTime.utc(2026, 11, 3));

      world.adopt(categories: const [CalendarCategories.fallback]);
      final second = world.calendar!;
      expect(identical(second, first), isFalse);
      expect(second.selectedDay, DateTime.utc(2026, 10, 12));
      expect(second.focusedDay, DateTime.utc(2026, 11, 3));
      expect(second.format, CalendarFormat.week);
      expect(second.panelMode, CalendarPanelMode.upcoming);
      expect(second.today, first.today);

      world.adopt(categories: const [CalendarCategories.fallback]);
      expect(identical(world.calendar, second), isTrue);
      world.dispose();
    });
  });

  group('events', () {
    String rowId(String key) => 'row-$key';
    final steps = stepsOf(CalendarGuideTopic.events);

    testWidgets('idle, with the three demo rows', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);

      expect(robot.line, steps[0]);
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
      // The row shows what the add did; the line says what is next.
      expect(robot.line, steps[1]);
      expect(robot.shows('Swim'), isTrue);
      note(robot);

      await robot.tap(rowId('dentist'));
      expect(find.byType(EventDetailSheet), findsOneWidget);
      // Opening is the step, marked when the trip returns.
      expect(robot.line, steps[1]);
      await sheets.detailEdit();
      await sheets.typeTitle('Dentist at noon');
      await sheets.saveEditor();
      // The editor's Save returns to the detail sheet, as on the calendar.
      expect(sheets.detailOpen, isTrue);
      await sheets.detailClose();
      expect(robot.line, steps[3]);
      expect(robot.shows('Dentist at noon'), isTrue);
      note(robot);

      await robot.tap(rowId('yoga'));
      await sheets.detailEdit();
      await sheets.deleteInEditor(en.delete);
      expect(robot.control(rowId('yoga')), findsNothing);
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.canSkip, isFalse);
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

    testWidgets('the detail sheet\'s Add date, Dates and description change '
        'the demo, here only', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      // Days in the picker's opening month: today's own.
      final extra = today.day < 20 ? day(3) : day(-3);
      final more = today.day < 20 ? day(5) : day(-5);
      CalendarDatePickerSheet picker() =>
          tester.widget(find.byType(CalendarDatePickerSheet));
      note(robot);

      // Add date on the one-time Dentist pins it to a set.
      await robot.tap(rowId('dentist'));
      await sheets.detailAddDate();
      expect(picker().initialView, CalendarDatePickerView.month);
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      // Changed before anything was added: the change is done, and the line
      // still asks for the add.
      final changed = steps[0];
      expect(robot.line, changed);
      note(robot);

      // Back on the detail sheet, whose Dates row opens the set as a list.
      expect(sheets.detailOpen, isTrue);
      await robot.tapId(SemanticsIds.eventDetailDates);
      expect(picker().initialView, CalendarDatePickerView.list);
      expect(picker().initialSelection, {today, extra});
      await robot.tapId(SemanticsIds.datePickerView('month'));
      await sheets.pickInDatePicker(more);
      await robot.tapId(SemanticsIds.datePickerSave);
      expect(robot.line, changed);
      await robot.tapId(SemanticsIds.eventDetailDates);
      expect(picker().initialSelection, {today, extra, more});
      // Cancel returns to the detail sheet, the set as it was.
      await robot.tapId(SemanticsIds.datePickerCancel);
      expect(sheets.detailOpen, isTrue);

      // The description cell's quick edit.
      await sheets.quickEditDescription('Bring the card');
      expect(robot.line, changed);
      note(robot);
      expect(
        find.descendant(
          of: find.byType(EventDetailSheet),
          matching: find.textContaining('Bring the card', findRichText: true),
        ),
        findsWidgets,
      );
      await sheets.detailClose();
      // The add, then the open the change already did: straight to delete.
      await robot.tap('add');
      await sheets.typeTitle('Swim');
      await sheets.saveEditor();
      expect(robot.line, steps[3]);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('a long title is cut in the line', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      final long = 'A' * 40;

      // Yoga repeats on today's weekday, so its row stands for today.
      await robot.tap(rowId('yoga'));
      await sheets.detailEdit();
      await sheets.typeTitle(long);
      await sheets.saveEditor();
      expect(sheets.detailOpen, isTrue);
      await sheets.detailSkip();

      expect(
        robot.line,
        en.calendarGuideDemoSkipped(shortDates.format(today), '${'A' * 24}…'),
      );
      await expectNothingSaved();
    });

    testWidgets('a skip from the detail sheet is kept here only; its report '
        'is the line until the next action', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);

      await robot.tap(rowId('yoga'));
      await sheets.detailSkip();
      // A skip is no step of this card and its day is not on the stage:
      // its report alone.
      expect(
        robot.line,
        en.calendarGuideDemoSkipped(
          shortDates.format(today),
          en.calendarGuideDemoEventYoga,
        ),
      );

      // The next action restores an instruction once its trip returns:
      // opening is step 2, so the line asks for the first step not done.
      await robot.tap(rowId('dentist'));
      await sheets.detailClose();
      expect(robot.line, steps[0]);
      await expectNothingSaved();
    });

    testWidgets('the line moves on only once the detail sheet is closed: '
        'a step under a sheet would never be announced', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);

      await robot.tap('add');
      await sheets.typeTitle('Swim');
      await sheets.saveEditor();
      expect(robot.line, steps[1]);

      await robot.tap(rowId('dentist'));
      expect(sheets.detailOpen, isTrue);
      expect(robot.line, steps[1], reason: 'opened, not yet applied');
      await sheets.detailEdit();
      await sheets.typeTitle('Dentist at noon');
      await sheets.saveEditor();
      expect(sheets.detailOpen, isTrue);
      expect(robot.line, steps[1], reason: 'changed, not yet applied');
      expect(robot.shows('Dentist at noon'), isTrue, reason: 'the stage is');

      await sheets.detailClose();
      expect(robot.line, steps[3]);
      await expectNothingSaved();
    });

    testWidgets('the long press offers the templates, Blank and the quick '
        'alarm', (tester) async {
      final template = await (await EventTemplateService.getInstance()).create(
        EventTemplate(id: '', name: 'Haircut', categoryId: kDefaultCategoryId),
      );
      writes.statements.clear();
      revisions = staticRevisions();
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.templatePickRow(template.id));
      expect(robot.line, steps[1]);
      expect(robot.shows('Haircut'), isTrue);
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.quickAlarmRow);
      expect(robot.line, en.calendarGuideWouldOpen(en.quickAlarmTitle));
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.templatePickBlank);
      expect(find.byType(EventEditorSheet), findsOneWidget);
      await sheets.typeTitle('Blank one');
      await sheets.saveEditor();
      expect(robot.line, steps[1]);
      expect(robot.shows('Blank one'), isTrue);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('alerts', () {
    final steps = stepsOf(CalendarGuideTopic.alerts);

    testWidgets('idle on the first step: where to add an alert', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      expect(robot.line, steps[0]);
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
        robot.shows(en.eventAlertMinutesBefore(kDraftAlertOffsetMinutes)),
        isTrue,
      );
      expect(robot.line, steps[1]);
      note(robot);

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertTypeAlarm);
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.shows(en.eventAlertModeRing), isTrue);
      note(robot);

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertRemove);
      expect(robot.control('alert-0'), findsNothing);
      expect(robot.line, steps[1]);
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

      // Removal is off: no Remove / Keep row.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alarmKeepEvent),
        findsNothing,
      );

      await robot.tapId(SemanticsIds.alarmStop);
      expect(find.byType(AlarmPage), findsNothing);
      expect(find.byType(CalendarGuideTopicPage), findsOneWidget);
      // Seen before any alert was added: that step is done, the add is
      // still asked for.
      expect(robot.line, steps[0]);
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.line, en.calendarGuideCoachDone);
      await expectNothingSaved();
    });

    testWidgets('the alarm screen draws what a ring of the event draws, the '
        'Remove / Keep row with removal on', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertTypeAlarm);
      await robot.tapId(SemanticsIds.alertRemoveAfter);
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.line, steps[1]);

      await robot.tap('show-alarm');
      final alarm = find.byType(AlarmPage);
      expect(alarm, findsOneWidget);
      // The line, a live region, holds still under the ring screen: the
      // step is marked once the page has closed.
      String lineUnder() => tester
          .widget<CalendarGuideTryCard>(
            find.byType(CalendarGuideTryCard, skipOffstage: false),
          )
          .demo
          .line(en);
      expect(lineUnder(), steps[1]);
      expect(tester.widget<AlarmPage>(alarm).payload.removeAfterAlert, isTrue);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alarmKeepEvent),
        findsOneWidget,
      );

      // The seed: tomorrow at nine for 45 minutes, in the fallback category.
      final tomorrow = day(1);
      final fireAt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
      final labels = AlertLabels(strings: en, use24Hour: false);
      Finder onPage(String text) =>
          find.descendant(of: alarm, matching: find.text(text));
      expect(
        onPage(
          EventTimeFormatter.formatMinuteFor(
            9 * 60,
            localeName: 'en',
            use24Hour: false,
          ),
        ),
        findsOneWidget,
      );
      expect(
        onPage(
          labels.whenLabel(
            time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
            day: tomorrow,
            fireAt: fireAt,
          ),
        ),
        findsOneWidget,
      );
      final avatar = tester.widget<EventAvatar>(
        find.descendant(of: alarm, matching: find.byType(EventAvatar)),
      );
      expect(avatar.icon, CalendarIcons.forKey('medical_services'));
      expect(
        avatar.color,
        CalendarCategories.resolve(CalendarCategories.fallback.id).color,
      );

      // The preview's Keep only closes the page.
      await robot.tapId(SemanticsIds.alarmKeepEvent);
      expect(find.byType(AlarmPage), findsNothing);
      expect(robot.line, en.calendarGuideCoachDone);
      await expectNothingSaved();
    });

    testWidgets('the quick alarm reports its draft, here only', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      note(robot);

      await robot.tap('quick');
      expect(find.byType(QuickAlarmSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.quickAlarmSave);
      expect(find.byType(QuickAlarmSheet), findsNothing);
      // The sheet's default name; the time and the day are the clock's. The
      // quick alarm is no step, and arms nothing to show: its report alone.
      expect(robot.line, startsWith('Alarm set for '));
      expect(robot.line, endsWith(en.calendarGuideDemoHereOnly('')));
      note(robot);

      // The next action restores the instruction.
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.line, steps[1]);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('a report goes with the next action that is no step: an '
        'alert removed', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.line, steps[1]);

      await robot.tap('quick');
      await robot.tapId(SemanticsIds.quickAlarmSave);
      expect(robot.line, endsWith(en.calendarGuideDemoHereOnly('')));

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertRemove);
      expect(robot.control('alert-0'), findsNothing);
      expect(robot.line, steps[1]);
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
    final steps = stepsOf(CalendarGuideTopic.kinds);

    testWidgets('idle on one day; repeat, pick a day, skip it', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      expect(robot.line, steps[0]);
      note(robot);
      // One day: nothing to skip; its dates can grow.
      expect(robot.enabled('skip'), isFalse);
      expect(robot.enabled('add-date'), isTrue);

      await robot.tap('repeat');
      expect(find.byType(EventRepeatSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.repeatKind('daily'));
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.line, steps[1]);
      note(robot);
      // A repeating event has no dates of its own; a day is not picked yet.
      expect(robot.enabled('add-date'), isFalse);
      expect(robot.enabled('skip'), isFalse);

      // Today is in the month shown and a day a daily event falls on.
      await robot.tap('day');
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
      await PracticeCalendarRobot(tester).pickInDatePicker(today);
      expect(find.byType(CalendarDatePickerSheet), findsNothing);
      expect(robot.enabled('skip'), isTrue);

      await robot.tap('skip');
      expect(robot.line, steps[2]);
      expect(robot.enabled('skip'), isFalse);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Repeat keeps the last rule through "does not repeat", and a '
        'pinned set survives the trip', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      final sheets = PracticeCalendarRobot(tester);
      final weekly = RecurrenceFormatter.format(
        const WeeklyRecurrence(
          weekdays: {1, 2, 3, 4, 5, 6, 7},
          interval: EventRepeatDraft.maxInterval,
        ),
        en,
        'en',
        retroactive: true,
      );
      EventRepeatDraft opened() =>
          tester.widget<EventRepeatSheet>(find.byType(EventRepeatSheet)).draft;
      Future<void> doesNotRepeat() =>
          _tapIn(tester, _inRepeatSheet(find.text(en.recurrenceDoesNotRepeat)));
      note(robot);

      // Weekly on every day, every 99 weeks, until today, also before.
      await robot.tap('repeat');
      await _longestWeeklyRule(tester, en, endOn: today);
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.shows(weekly), isTrue);
      note(robot);

      // Back to one day.
      await robot.tap('repeat');
      await doesNotRepeat();
      await robot.tapId(SemanticsIds.repeatDone);
      // Back to one day before any skip: the skip is still asked for.
      expect(robot.line, steps[1]);
      note(robot);

      // Repeat again opens on the rule she had, switched off.
      await robot.tap('repeat');
      final kept = opened();
      expect(kept.recurring, isFalse);
      expect(kept.kind, RepeatKind.weekly);
      expect(kept.interval, EventRepeatDraft.maxInterval);
      expect(kept.weekdays, {1, 2, 3, 4, 5, 6, 7});
      expect(kept.endDate, today);
      expect(kept.retroactive, isTrue);
      await robot.tapId(SemanticsIds.repeatKind('weekly'));
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.shows(weekly), isTrue);

      // Pinned to two dates, then through Daily and back in the sheet: the
      // set stays, as the editor's "does not repeat" keeps it.
      await robot.tap('repeat');
      await doesNotRepeat();
      await robot.tapId(SemanticsIds.repeatDone);
      final extra = today.day < 20 ? day(3) : day(-3);
      await robot.tap('add-date');
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      final pinned = en.recurrenceSpecificDates(2);
      expect(robot.line, steps[1]);
      expect(robot.shows(pinned), isTrue);
      await robot.tap('repeat');
      expect(opened().kind, RepeatKind.weekly);
      await robot.tapId(SemanticsIds.repeatKind('daily'));
      await doesNotRepeat();
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.line, steps[1]);
      expect(robot.shows(pinned), isTrue);
      expect(robot.enabled('add-date'), isTrue);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Add date pins the event to the dates picked', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      final sheets = PracticeCalendarRobot(tester);

      // A day in the picker's opening month: today's own month.
      final extra = today.day < 20 ? day(3) : day(-3);
      await robot.tap('add-date');
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      // The last step done first: the line still asks for the first.
      expect(robot.line, steps[0]);
      expect(robot.shows(en.recurrenceSpecificDates(2)), isTrue);
      // Two days now: one of them can be skipped once picked.
      expect(robot.enabled('add-date'), isTrue);
      await expectNothingSaved();
    });
  });

  group('attendance', () {
    String counts(int attended, int total, int current, int best) =>
        '${en.eventAdherenceSummary(attended, total, 30)}'
        ' · ${en.eventAdherenceStreak(current, best)}';
    final steps = stepsOf(CalendarGuideTopic.attendance);

    testWidgets('idle on the first step; today\'s button and a past day '
        'change the summary and the streak under the marks, never the '
        'row\'s height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.attendance);
      expect(robot.line, steps[0]);
      // Live from the first build: the seed's own count.
      expect(robot.stageCaptions.first, counts(4, 5, 1, 3));
      final marks = robot.stageCaptionSlotSize(0);
      final stage = robot.stageSize;
      note(robot);
      // Today and the four weeks before it; the week before last missed.
      for (var i = 0; i < 4; i++) {
        expect(robot.chip('day-$i').selected, i != 3, reason: 'day-$i');
      }

      await robot.tap('today');
      expect(robot.line, steps[1]);
      expect(robot.stageCaptions.first, counts(3, 5, 0, 3));
      note(robot);
      expect(
        find.descendant(
          of: robot.control('today'),
          matching: find.byTooltip(en.eventMarkPresent),
        ),
        findsOneWidget,
      );

      await robot.tap('day-3');
      expect(robot.chip('day-3').selected, isTrue);
      expect(robot.line, steps[1]);
      expect(robot.stageCaptions.first, counts(4, 5, 0, 4));

      await robot.tap('today');
      expect(robot.stageCaptions.first, counts(5, 5, 5, 5));
      expect(robot.stageCaptionSlotSize(0), marks);
      expect(robot.stageSize, stage);

      await robot.tap('count');
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.stageCaptions.first, counts(5, 5, 5, 5));
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('a past day\'s chip says present or missed, and flips with '
        'a tap', (tester) async {
      final handle = tester.ensureSemantics();
      final robot = await open(tester, CalendarGuideTopic.attendance);
      String said(String name) {
        final data = tester
            .getSemantics(robot.control(name))
            .getSemanticsData();
        return '${data.label} ${data.hint}';
      }

      expect(said('day-0'), contains(en.eventPresencePresent));
      expect(said('day-3'), contains(en.eventPresenceMissed));
      await robot.tap('day-3');
      expect(said('day-3'), contains(en.eventPresencePresent));
      expect(said('day-3'), isNot(contains(en.eventPresenceMissed)));
      await robot.tap('day-3');
      expect(said('day-3'), contains(en.eventPresenceMissed));
      handle.dispose();
      await expectNothingSaved();
    });

    testWidgets('the count switch enables the styles and the example '
        'follows them, the stage never changing height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.attendance);
      final stage = robot.stageSize;
      final numbered = [1, 2, 3].map(en.eventNumberedWeeks).join(' · ');
      final elapsed = [0, 1, 2].map(en.eventElapsedWeeks).join(' · ');
      // Off: the styles stay drawn, disabled.
      expect(robot.chip('count-numbered').onTap, isNull);
      expect(robot.chip('count-elapsed').onTap, isNull);

      await robot.tap('count');
      expect(robot.chip('count-elapsed').onTap, isNotNull);
      expect(robot.stageCaptions.last, numbered);
      // The second step first: the line still asks for a mark.
      expect(robot.line, steps[0]);

      await robot.tap('count-elapsed');
      expect(robot.chip('count-elapsed').selected, isTrue);
      expect(robot.stageCaptions.last, elapsed);
      expect(robot.stageSize, stage);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });
  });

  group('categories', () {
    final steps = stepsOf(CalendarGuideTopic.categories);

    testWidgets('idle: three rows, the first step, Delete disabled on a '
        'built-in', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.categories);

      expect(robot.line, steps[0]);
      for (var i = 0; i < 3; i++) {
        expect(robot.control('row-$i'), findsOneWidget, reason: 'row-$i');
      }
      expect(robot.shows(en.eventCategoryGym), isTrue);
      expect(robot.shows(en.calendarGuideDemoEventBookClub), isTrue);

      await robot.tap('more-0');
      final delete = tester.widget<PopupMenuItem<dynamic>>(
        find.ancestor(
          of: robot.control('delete'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(delete.enabled, isFalse);
      await robot.tap('delete');
      // Still open, nothing deleted.
      expect(robot.control('edit'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(robot.control('row-0'), findsOneWidget);
      expect(robot.line, steps[0]);
      await expectNothingSaved();
    });

    testWidgets('create, edit, hide, show and delete — in this list only', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final sheet = CategoryEditorRobot(tester);
      final stage = robot.stageSize;
      final gym = en.eventCategoryGym;

      await robot.tap('add');
      expect(find.byType(CategoryEditorSheet), findsOneWidget);
      await sheet.typeName('Chess');
      await sheet.save();
      expect(robot.line, steps[1]);
      expect(robot.control('row-3'), findsOneWidget);
      expect(robot.shows('Chess'), isTrue);
      note(robot);

      await robot.tap('row-2');
      await sheet.typeName('Reading');
      await sheet.save();
      expect(robot.line, steps[1]);
      expect(robot.shows('Reading'), isTrue);
      note(robot);

      await robot.tap('eye-0');
      expect(robot.line, steps[2]);
      expect(steps[2], contains(en.eventCategoryOther));
      note(robot);
      await robot.tap('eye-0');
      expect(robot.line, steps[2]);
      expect(robot.shows(gym), isTrue);

      await robot.tap('more-1');
      await robot.tap('edit');
      expect(find.byType(CategoryEditorSheet), findsOneWidget);
      await sheet.save();
      expect(robot.line, steps[2]);

      await robot.tap('more-2');
      await robot.tap('delete');
      expect(robot.control('row-3'), findsNothing);
      expect(robot.shows('Reading'), isFalse);
      expect(robot.line, en.calendarGuideCoachDone);
      note(robot);
      expect(robot.stageSize, stage);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('at six rows Create category is disabled, not gone', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final sheet = CategoryEditorRobot(tester);
      final stage = robot.stageSize;

      for (final name in ['One', 'Two', 'Three']) {
        expect(robot.enabled('add'), isTrue);
        await robot.tap('add');
        await sheet.typeName(name);
        await sheet.save();
      }
      expect(robot.enabled('add'), isFalse);
      expect(robot.stageSize, stage);
      await expectNothingSaved();
    });
  });

  group('finding', () {
    const all = ['dentist', 'yoga', 'rent', 'birthday', 'book-club', 'flight'];
    final steps = stepsOf(CalendarGuideTopic.finding);

    Future<void> search(
      WidgetTester tester,
      GuideTryCardRobot robot,
      String text,
    ) async {
      await tester.enterText(
        find.descendant(
          of: robot.control('search'),
          matching: find.byType(EditableText),
        ),
        text,
      );
      await tester.pumpAndSettle();
    }

    void expectListed(GuideTryCardRobot robot, Set<String> listed) {
      for (final key in all) {
        expect(
          robot.control('match-$key'),
          listed.contains(key) ? findsOneWidget : findsNothing,
          reason: key,
        );
      }
    }

    testWidgets('a title, a category\'s name and a date narrow the list, '
        'which never changes height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.finding);
      final stage = robot.stageSize;
      expect(robot.line, steps[0]);
      expectListed(robot, all.toSet());
      note(robot);

      await search(tester, robot, 'yoga');
      expect(robot.line, steps[1]);
      expectListed(robot, {'yoga'});
      note(robot);

      // The seed takes the visible built-ins in order: Rent wears the third.
      await search(tester, robot, en.eventCategoryRest);
      expect(robot.line, steps[1]);
      expectListed(robot, {'rent'});

      final flight = day(9);
      await search(tester, robot, DateFormat('d MMMM', 'en').format(flight));
      expect(robot.control('match-flight'), findsOneWidget);
      expect(robot.control('match-dentist'), findsNothing);

      await search(tester, robot, 'nothing like it');
      expect(robot.line, steps[1]);
      expectListed(robot, const {});

      // An emptied field is no search: the list fills, the step stays done.
      await search(tester, robot, '');
      expect(robot.line, steps[1]);
      expectListed(robot, all.toSet());
      expect(robot.stageSize, stage);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the funnel opens the sandboxed filter sheet and its count '
        'narrows the list', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.finding);
      note(robot);

      await robot.tap('filter');
      expect(find.byType(CalendarFilterSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.filterRepeat);
      await robot.tapId(SemanticsIds.filterRepeatOneTime);
      await robot.tapId(SemanticsIds.filterApply);
      expect(find.byType(CalendarFilterSheet), findsNothing);
      // Filtered before any search: the search is still asked for.
      expect(robot.line, steps[0]);
      expectListed(robot, {'dentist', 'flight'});
      note(robot);

      await robot.tap('filter');
      await robot.tapId(SemanticsIds.filterTime);
      await robot.tapId(SemanticsIds.filterTimeAllDay);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.line, steps[0]);
      expectListed(robot, {'flight'});
      expect(
        find.descendant(
          of: robot.control('filter'),
          matching: find.byIcon(Icons.filter_alt_rounded),
        ),
        findsOneWidget,
      );
      note(robot);

      // A query on top of the filters.
      await search(tester, robot, 'dentist');
      expect(robot.line, en.calendarGuideCoachDone);
      expectListed(robot, const {});
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Missed only reads the demo\'s own marks', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.finding);

      await robot.tap('filter');
      await robot.tapId(SemanticsIds.filterOnlyShow);
      await robot.tapId(SemanticsIds.filterListRow('missed'));
      await robot.tapId(SemanticsIds.filterListDone);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.line, steps[0]);
      // The practice Yoga's week before last is marked missed in the demo;
      // the calendar's own presence cache holds no mark of a demo id.
      expectListed(robot, {'yoga'});
      await expectNothingSaved();
    });

    testWidgets('the keyboard up over the focused field overflows nothing', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.finding,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      const inset = 320.0;
      final field = find.descendant(
        of: robot.control('search'),
        matching: find.byType(EditableText),
      );
      void expectAboveKeyboard() =>
          expect(tester.getRect(field).bottom, lessThanOrEqualTo(780 - inset));
      await tester.ensureVisible(robot.control('search'));
      await tester.pumpAndSettle();
      await tester.showKeyboard(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: inset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectAboveKeyboard();
      await tester.enterText(field, 'yoga');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectAboveKeyboard();

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    // The keyboard up: the coach line rises to the top, the field under it
    // and the matches under that, all above the keyboard. The field stays
    // put while she types.
    for (final height in const [915.0, 1200.0]) {
      testWidgets('the keyboard up brings the line, the field and the '
          'matches above it; typing moves nothing (412×$height)', (
        tester,
      ) async {
        final robot = await open(
          tester,
          CalendarGuideTopic.finding,
          size: Size(412, height),
        );
        const inset = 320.0;
        final keyboardTop = height - inset;
        final field = find.descendant(
          of: robot.control('search'),
          matching: find.byType(EditableText),
        );
        await tester.showKeyboard(field);
        await tester.pumpAndSettle();

        tester.view.viewInsets = const FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        final fieldRect = tester.getRect(field);
        final slotRect = robot.slotRect;
        expect(slotRect.top, greaterThanOrEqualTo(0));
        expect(slotRect.bottom, lessThanOrEqualTo(fieldRect.top));
        expect(fieldRect.bottom, lessThanOrEqualTo(keyboardTop));
        expect(
          tester.getRect(robot.control('match-dentist')).bottom,
          lessThanOrEqualTo(keyboardTop),
        );

        await tester.enterText(field, 'yoga');
        await tester.pumpAndSettle();
        expect(robot.line, stepsOf(CalendarGuideTopic.finding)[1]);
        expect(tester.getRect(field), fieldRect);
        expect(robot.slotRect, slotRect);
        expect(tester.takeException(), isNull);
        await expectNothingSaved();
      });
    }

    // Where the line, the field and a match do not all fit, the field goes
    // to the top and the first match stays above the keyboard.
    testWidgets('the keyboard up on a small phone in German at 2.0 keeps the '
        'field and the first match above it (360×780)', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.finding,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      const inset = 320.0;
      const keyboardTop = 780 - inset;
      final field = find.descendant(
        of: robot.control('search'),
        matching: find.byType(EditableText),
      );
      await tester.showKeyboard(field);
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: inset);
      await tester.pumpAndSettle();
      final fieldRect = tester.getRect(field);
      expect(fieldRect.top, greaterThanOrEqualTo(0));
      expect(fieldRect.bottom, lessThanOrEqualTo(keyboardTop));
      expect(
        tester.getRect(robot.control('match-dentist')).bottom,
        lessThanOrEqualTo(keyboardTop),
      );

      await tester.enterText(field, 'Zahnarzt');
      await tester.pumpAndSettle();
      expect(tester.getRect(field), fieldRect);
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });
  });

  group('setup', () {
    final year = today.year;
    final steps = stepsOf(CalendarGuideTopic.setup);
    int countIn(HolidayProfile profile, int year) => HolidaySeeds.forYear(
      profile,
      year,
    ).keys.where((day) => day.year == year).length;

    testWidgets('every holiday set says its own count under the row, the '
        'next days in a slot that never changes height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.setup);
      final stage = robot.stageSize;
      expect(robot.line, steps[0]);
      // Live from the first build: the seed's set.
      expect(
        robot.stageCaptions.first,
        en.calendarGuideDemoHolidays(
          countIn(HolidayProfile.generic, year),
          '$year',
        ),
      );
      final count = robot.stageCaptionSlotSize(0);
      note(robot);
      final next = <String>{};
      for (final profile in HolidayProfile.values) {
        await robot.tap('holidays');
        await robot.tapId(
          SemanticsIds.calendarGuideTryControl(
            'setup',
            'holidays-${profile.name}',
          ),
        );
        expect(robot.line, steps[1], reason: profile.name);
        expect(
          robot.stageCaptions.first,
          en.calendarGuideDemoHolidays(countIn(profile, year), '$year'),
          reason: profile.name,
        );
        expect(robot.stageCaptionSlotSize(0), count, reason: profile.name);
        note(robot);
        final lines = robot.stageCaptions.last;
        expect(
          lines.isEmpty ? 0 : lines.split('\n').length,
          profile == HolidayProfile.none ? 0 : 3,
          reason: profile.name,
        );
        next.add(lines);
        expect(robot.stageSize, stage, reason: profile.name);
      }
      expect(robot.shows(en.holidayProfileNone), isTrue);
      expect(next.length, greaterThan(1));
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('across the year\'s end a holiday is listed once', (
      tester,
    ) async {
      const us = HolidayProfile.unitedStates;
      final newYearObserved = DateTime.utc(2027, 12, 31);
      // The premise: both years' seeds hold the Saturday 1 January 2028
      // observed on 31 December 2027.
      expect(HolidaySeeds.forYear(us, 2027), contains(newYearObserved));
      expect(HolidaySeeds.forYear(us, 2028), contains(newYearObserved));

      final robot = await open(
        tester,
        CalendarGuideTopic.setup,
        now: () => DateTime(2027, 12, 26, 15),
      );
      await robot.tap('holidays');
      await robot.tapId(
        SemanticsIds.calendarGuideTryControl('setup', 'holidays-${us.name}'),
      );

      final lines = robot.stageCaptions.last.split('\n');
      expect(lines, hasLength(3));
      final shownDates = [for (final line in lines) line.split(' · ').first];
      expect(shownDates.toSet(), hasLength(3), reason: '$lines');
      expect(shownDates.first, dates.format(newYearObserved));
      expect(
        robot.stageCaptions.first,
        en.calendarGuideDemoHolidays(countIn(us, 2027), '2027'),
      );
      await expectNothingSaved();
    });

    testWidgets('the year\'s count holds only its own days', (tester) async {
      const us = HolidayProfile.unitedStates;
      final own = countIn(us, 2028);
      expect(own, HolidaySeeds.forYear(us, 2028).length - 1);

      final robot = await open(
        tester,
        CalendarGuideTopic.setup,
        now: () => DateTime(2028, 6, 1, 9),
      );
      await robot.tap('holidays');
      await robot.tapId(
        SemanticsIds.calendarGuideTryControl('setup', 'holidays-${us.name}'),
      );

      expect(
        robot.stageCaptions.first,
        en.calendarGuideDemoHolidays(own, '2028'),
      );
      expect(robot.line, steps[1]);
      await expectNothingSaved();
    });

    testWidgets('starts from her holiday set, read from the service', (
      tester,
    ) async {
      await (await PublicHolidayService.getInstance()).setProfile(
        HolidayProfile.romania,
        reconcile: false,
      );
      writes.statements.clear();
      revisions = staticRevisions();

      final robot = await open(tester, CalendarGuideTopic.setup);

      expect(robot.shows(en.holidayProfileRomania), isTrue);
      // Her own set is no pick: the line still asks for one.
      expect(robot.line, steps[0]);
      await expectNothingSaved();
    });

    testWidgets('the first day of the week turns the sample week', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.setup);
      CalendarWeekStart shown() => tester
          .widget<CalendarAppearancePreview>(
            find.descendant(
              of: robot.card,
              matching: find.byType(CalendarAppearancePreview),
            ),
          )
          .appearance
          .weekStart;
      expect(shown(), CalendarWeekStart.monday);

      for (final start in [
        CalendarWeekStart.sunday,
        CalendarWeekStart.saturday,
        CalendarWeekStart.monday,
      ]) {
        await robot.tap('week-${start.name}');
        expect(shown(), start);
        // The strip's first day is the start's own weekday.
        final todayIndex = (today.weekday - start.weekday + 7) % 7;
        final first = day(-todayIndex);
        expect(first.weekday, start.weekday);
        expect(
          find.descendant(
            of: find.byType(CalendarAppearancePreview),
            matching: find.text('${first.day}'),
          ),
          findsWidgets,
        );
      }
      // The second step done first, with nothing to report: the line asks
      // for the first alone.
      expect(robot.line, steps[0]);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    testWidgets('the settings row opens the real Calendar settings', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.setup);

      await robot.tap('settings');
      expect(find.byType(CalendarSettingsPage), findsOneWidget);
      expect(pushes.pushed, hasLength(1));
      await expectNothingSaved();
    });
  });

  group('fasting', () {
    final steps = stepsOf(CalendarGuideTopic.fasting);
    const traditionIds = [
      'tradition-orthodox',
      'tradition-catholic',
      'tradition-muslim',
      'tradition-jewish',
    ];
    // A strict Wednesday of the Orthodox Great Lent of 2027 (Pascha 2 May).
    final lent = DateTime.utc(2027, 3, 17);
    DateTime inLent() => DateTime(2027, 3, 17, 10);
    // A Wednesday and a Friday of October 2027, outside every long fast:
    // the weekly fast alone marks them.
    final october = DateTime.utc(2027, 10, 13);
    final octoberFriday = DateTime.utc(2027, 10, 15);
    DateTime inOctober() => DateTime(2027, 10, 13, 10);

    bool washed(WidgetTester tester, DateTime day) =>
        _cellOf(tester, 'fasting', day).tint.wash != null;

    bool anyWashed(WidgetTester tester) => tester
        .widgetList<CalendarDayCell>(
          _inCard('fasting', find.byType(CalendarDayCell)),
        )
        .any((cell) => cell.tint.wash != null);

    /// The fasting bars the grid draws; the weekend's are always there.
    int fastingBars(WidgetTester tester) => tester
        .widgetList<CalendarDayBars>(
          _inCard('fasting', find.byType(CalendarDayBars)),
        )
        .expand((strip) => strip.bars)
        .where((bar) => bar.key.startsWith('fasting:'))
        .length;

    /// The panel's entry titles for the picked day.
    List<String> panelTitles(WidgetTester tester) => [
      for (final entry
          in tester
              .widget<DaySummaryPanel>(
                _inCard('fasting', find.byType(DaySummaryPanel)),
              )
              .entries)
        entry.title,
    ];

    testWidgets('idle: every chip off, the three rows disabled, the first '
        'line, a grid with nothing on it', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);

      expect(robot.line, steps.first);
      for (final id in traditionIds) {
        expect(robot.chip(id).selected, isFalse, reason: id);
        expect(robot.chip(id).onTap, isNotNull, reason: id);
      }
      // The four in one row of chips, named as the traditions are.
      expect(
        find.ancestor(
          of: robot.control(traditionIds.first),
          matching: find.byType(FormChipRow),
        ),
        findsOneWidget,
      );
      expect(
        [for (final id in traditionIds) robot.chip(id).label],
        [
          for (final tradition in FastingTradition.values)
            FastingCalendar.traditionNameOf(tradition, en),
        ],
      );
      // Disabled, never hidden.
      expect(robot.pickerRow('appearance').enabled, isFalse);
      expect(robot.pickerRow('appearance').value, isNull);
      expect(robot.pickerRow('practice').enabled, isFalse);
      expect(robot.switchRow('great-fasts').onChanged, isNull);
      expect(robot.control('great-fasts'), findsOneWidget);
      // Today's month, no events, no fast day.
      expect(_gridOf(tester, 'fasting').focusedDay, lent);
      expect(anyWashed(tester), isFalse);
      expect(fastingBars(tester), 0);
      expect(panelTitles(tester), isEmpty);
      expect(FastingCalendar.isEnabled, isFalse);
      await expectNothingSaved();
    });

    // D67: the grid above the chips, so a tradition switched on changes
    // what she can see — on the small phone, with the page scrolled as far
    // as the chips at the screen's bottom edge, two of the grid's rows are
    // whole above them.
    testWidgets('360 × 780 en 1.0: with the chips at the viewport\'s bottom, '
        'two whole grid rows stand above them', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        size: const Size(360, 780),
        now: inLent,
      );
      final chips = find.ancestor(
        of: robot.control(traditionIds.first),
        matching: find.byType(FormChipRow),
      );
      final list = find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first;
      final viewport = tester.getRect(list);
      final page = tester.state<ScrollableState>(list).position;
      page.jumpTo(
        (page.pixels + tester.getRect(chips).bottom - viewport.bottom).clamp(
          page.minScrollExtent,
          page.maxScrollExtent,
        ),
      );
      await tester.pumpAndSettle();
      final chipTop = tester.getRect(chips).top;
      expect(tester.getRect(chips).bottom, lessThanOrEqualTo(viewport.bottom));

      final cells = [
        for (final element in _inCard(
          'fasting',
          find.byType(CalendarDayCell),
        ).evaluate())
          if (element.renderObject case final RenderBox box
              when !_unseen(box))
            box.localToGlobal(Offset.zero) & box.size,
      ];
      final rowHeight = cells.first.height;
      final firstRowTop = cells.map((rect) => rect.top).reduce(math.min);
      // The grid's whole rows on screen: those wholly inside the viewport.
      final shownRows = {
        for (final rect in cells)
          if (rect.top >= viewport.top && rect.bottom <= chipTop)
            rect.top.round(),
      };
      expect(chipTop - math.max(firstRowTop, viewport.top), greaterThanOrEqualTo(
        2 * rowHeight,
      ));
      expect(shownRows.length, greaterThanOrEqualTo(2), reason: '$shownRows');
      await expectNothingSaved();
    });

    testWidgets('Orthodox on in Great Lent: the grid is washed, the panel '
        'names the fast and its rule, the line moves on', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);

      await robot.tapChip('tradition-orthodox');

      expect(robot.chip('tradition-orthodox').selected, isTrue);
      expect(robot.line, steps[1]);
      expect(washed(tester, lent), isTrue);
      expect(panelTitles(tester), [en.fastingGreatLent]);
      expect(robot.shows(en.fastingRegimeStrict), isTrue);
      // The rows wake up; the Appearance row names the tradition it opens.
      expect(robot.pickerRow('appearance').enabled, isTrue);
      expect(robot.pickerRow('appearance').value, en.fastingTraditionOrthodox);
      expect(robot.pickerRow('practice').enabled, isTrue);
      expect(robot.switchRow('great-fasts').onChanged, isNotNull);

      // A picked Saturday reads its own rule, and the weekend's row.
      final saturday = DateTime.utc(2027, 3, 20);
      await _tapCell(tester, 'fasting', saturday);
      expect(panelTitles(tester), [en.fastingGreatLent, en.dayBarWeekend]);
      expect(robot.shows(en.fastingRegimeOil), isTrue);

      // All off again: the other rows are disabled, so the line asks for a
      // tradition (D44) — and the step stays done, so one back on moves the
      // line straight past it.
      await robot.tapChip('tradition-orthodox');
      expect(anyWashed(tester), isFalse);
      expect(panelTitles(tester), [en.dayBarWeekend]);
      expect(robot.pickerRow('appearance').enabled, isFalse);
      expect(robot.line, steps.first);
      await robot.tapChip('tradition-muslim');
      expect(robot.line, steps[1]);
      await robot.tapChip('tradition-muslim');
      expect(robot.line, steps.first);
      expect(FastingCalendar.isEnabled, isFalse);
      await expectNothingSaved();
    });

    testWidgets('the closing line stands with every tradition off', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);
      while (robot.canSkip) {
        await robot.skip();
      }
      expect(robot.line, en.calendarGuideCoachDone);
      await robot.tapChip('tradition-orthodox');
      await robot.tapChip('tradition-orthodox');
      expect(robot.line, en.calendarGuideCoachDone);
      await expectNothingSaved();
    });

    testWidgets('Appearance opens the real style sheet in its sandbox: a bar '
        'replaces the wash, the step is marked once the sheet has closed', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);
      await robot.tapChip('tradition-orthodox');
      expect(fastingBars(tester), 0);

      await robot.tap('appearance');
      final sheet = FastingStyleRobot(tester);
      expect(sheet.isOpen, isTrue);
      expect(sheet.title, contains(en.fastingTraditionOrthodox));
      await sheet.pickStyle(FastingDisplayStyle.bar);
      // Under the sheet the stage follows at once; the line waits.
      expect(robot.line, steps[1]);
      await sheet.close();

      expect(robot.line, steps[2]);
      expect(washed(tester, lent), isFalse);
      expect(fastingBars(tester), greaterThan(0));
      // The panel's row stays: the style is the grid's alone.
      expect(panelTitles(tester), [en.fastingGreatLent]);

      // Bold numbers: no wash, no bar, the day number in the fast's colour.
      await robot.tap('appearance');
      await sheet.pickStyle(FastingDisplayStyle.strong);
      await sheet.close();
      expect(washed(tester, lent), isFalse);
      expect(fastingBars(tester), 0);
      expect(_cellOf(tester, 'fasting', lent).fastingNumberColor, isNotNull);
      await expectNothingSaved();
    });

    testWidgets('the style sheet\'s swatch strip is read-only and its pick '
        'recolours the stage', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);
      await robot.tapChip('tradition-orthodox');
      final before = _cellOf(tester, 'fasting', lent).tint.wash;

      await robot.tap('appearance');
      final sheet = FastingStyleRobot(tester);
      // The sandboxed strip offers no add and no manage dot.
      expect(sheet.swatches.hasAdd, isFalse);
      expect(sheet.swatches.hasManage, isFalse);
      final swatch = sheet.swatches
          .dots()
          .firstWhere((dot) => dot.icon == null && dot.color != null)
          .color!;
      await sheet.pickSwatch(swatch.toARGB32());
      await sheet.close();

      expect(_cellOf(tester, 'fasting', lent).tint.wash, isNot(before));

      // An icon picked in the sandboxed picker is kept here and recorded
      // nowhere among the recent icons.
      await robot.tap('appearance');
      await sheet.chooseIcon('star');
      await sheet.close();
      expect(
        tester
            .widget<DaySummaryPanel>(
              _inCard('fasting', find.byType(DaySummaryPanel)),
            )
            .entries
            .single
            .icon,
        Icons.star_rounded,
      );
      await expectNothingSaved();
    });

    testWidgets('My practice opens the real schedule sheet: a weekday '
        'unticked leaves the grid, the step is marked once it has closed', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        now: inOctober,
      );
      await robot.tapChip('tradition-orthodox');
      expect(washed(tester, october), isTrue);
      expect(panelTitles(tester), [en.fastingWeekdayFast]);

      await robot.tap('practice');
      final sheet = FastingScheduleRobot(tester);
      expect(sheet.isOpen, isTrue);
      expect(sheet.weekdaySelected(DateTime.wednesday), isTrue);
      await sheet.toggleWeekday(DateTime.wednesday);
      expect(robot.line, steps[1]);
      await sheet.close();

      expect(washed(tester, october), isFalse);
      expect(washed(tester, octoberFriday), isTrue);
      expect(panelTitles(tester), isEmpty);
      // Style is still to do: the line asks for it, then the closing line.
      expect(robot.line, steps[1]);
      await robot.tap('appearance');
      await FastingStyleRobot(tester).close();
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.canSkip, isFalse);
      // Reopened, the sheet starts from the practice kept here.
      await robot.tap('practice');
      expect(sheet.weekdaySelected(DateTime.wednesday), isFalse);
      await sheet.close();
      await expectNothingSaved();
    });

    testWidgets('Multi-day fasts: enabled only while Orthodox is on; off, a '
        'Lent day reads as the weekly fast', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);

      await robot.tapChip('tradition-catholic');
      expect(robot.switchRow('great-fasts').onChanged, isNull);
      expect(robot.pickerRow('appearance').value, en.fastingTraditionCatholic);
      await robot.tapChip('tradition-orthodox');
      expect(robot.switchRow('great-fasts').onChanged, isNotNull);
      // The first tradition that is on, in the order of the chips.
      expect(robot.pickerRow('appearance').value, en.fastingTraditionOrthodox);
      expect(panelTitles(tester), [en.fastingGreatLent, en.fastingLent]);

      await robot.tap('great-fasts');
      expect(robot.switchRow('great-fasts').value, isFalse);
      expect(panelTitles(tester), [en.fastingWeekdayFast, en.fastingLent]);
      await robot.tap('great-fasts');
      expect(panelTitles(tester), [en.fastingGreatLent, en.fastingLent]);

      await robot.tapChip('tradition-orthodox');
      expect(robot.switchRow('great-fasts').onChanged, isNull);
      await expectNothingSaved();
    });

    testWidgets('the grid pages through the year\'s end and keeps marking', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        now: () => DateTime(2027, 12, 8, 10),
      );
      await robot.tapChip('tradition-orthodox');
      // The Nativity fast, then January's Eve of the Theophany next year.
      expect(washed(tester, DateTime.utc(2027, 12, 8)), isTrue);
      await _tapOnPage(
        tester,
        'fasting',
        _inCard('fasting', find.byTooltip(en.dayListNextMonth)),
      );
      expect(_gridOf(tester, 'fasting').focusedDay.year, 2028);
      final eve = DateTime.utc(2028, 1, 5);
      expect(washed(tester, eve), isTrue);
      await _tapCell(tester, 'fasting', eve);
      expect(panelTitles(tester), [en.fastingEveOfTheophany]);
      await expectNothingSaved();
    });

    testWidgets('the style sheet\'s title, description, placement and icon '
        'reset reach the panel row, and are kept here only', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);
      await robot.tapChip('tradition-orthodox');
      final saturday = DateTime.utc(2027, 3, 20);
      await _tapCell(tester, 'fasting', saturday);
      expect(panelTitles(tester), [en.fastingGreatLent, en.dayBarWeekend]);

      await robot.tap('appearance');
      final sheet = FastingStyleRobot(tester);
      await sheet.typeTitle('Post');
      await sheet.typeDescription('Bread and **water**');
      await sheet.pickPlacement(FastingRowPlacement.last);
      await sheet.chooseIcon('star');
      expect(sheet.hasIconReset, isTrue);
      await sheet.resetIcon();
      await sheet.close();

      // Last: under the weekend's row.
      expect(panelTitles(tester), [en.dayBarWeekend, 'Post']);
      final row = tester
          .widget<DaySummaryPanel>(
            _inCard('fasting', find.byType(DaySummaryPanel)),
          )
          .entries
          .last;
      expect(row.description, 'Bread and **water**');
      expect(row.subtitle, en.fastingRegimeOil);
      expect(
        row.icon,
        FastingCalendar.defaultIconOf(FastingTradition.orthodox),
      );
      // Reopened, the sheet starts from the look kept here.
      await robot.tap('appearance');
      expect(sheet.titleLabel, 'Post');
      await sheet.close();
      await expectNothingSaved();
    });

    testWidgets('the practice sheet\'s weekday scope and months reach the '
        'grid', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.fasting, now: inLent);
      await robot.tapChip('tradition-orthodox');
      final sheet = FastingScheduleRobot(tester);

      // Wednesday off: the weekly scope keeps the Lent Wednesday...
      await robot.tap('practice');
      await sheet.toggleWeekday(DateTime.wednesday);
      await sheet.close();
      expect(washed(tester, lent), isTrue);
      // ...the all-fasts scope takes it.
      await robot.tap('practice');
      await sheet.pickWeekdayScope(FastingWeekdayScope.allFasts);
      await sheet.close();
      expect(washed(tester, lent), isFalse);
      expect(washed(tester, DateTime.utc(2027, 3, 19)), isTrue);

      // March off: nothing in it is marked.
      await robot.tap('practice');
      expect(sheet.weekdayScope, FastingWeekdayScope.allFasts);
      await sheet.toggleMonth(DateTime.march);
      await sheet.close();
      final march = tester
          .widgetList<CalendarDayCell>(
            _inCard('fasting', find.byType(CalendarDayCell)),
          )
          .where((cell) => cell.day.month == DateTime.march);
      expect(march, isNotEmpty);
      expect(march.where((cell) => cell.tint.wash != null), isEmpty);
      expect(panelTitles(tester), isEmpty);
      await expectNothingSaved();
    });

    // The Dates sheet opens on the real month, so this case stands on the
    // real today and asks the engine which days to pick: the Catholic
    // calendar never marks a Sunday outside Lent and Advent's own rule, and
    // marks every Friday.
    testWidgets('a day skipped in My practice loses its wash and its row; a '
        'day forced gains both', (tester) async {
      final real = DateTime.now();
      final catholic = FastingCalendar.computeYear(
        real.year,
        traditions: const {FastingTradition.catholic},
      );
      final days = [
        for (
          var d = 1;
          d <= DateUtils.getDaysInMonth(real.year, real.month);
          d++
        )
          DateTime.utc(real.year, real.month, d),
      ];
      final forced = days.firstWhere(
        (day) => day.weekday == DateTime.sunday && catholic[day] == null,
      );
      final skipped = days.firstWhere(
        (day) => day.weekday == DateTime.friday && catholic[day] != null,
      );

      final robot = await open(tester, CalendarGuideTopic.fasting);
      await robot.tapChip('tradition-catholic');
      expect(washed(tester, forced), isFalse);
      expect(washed(tester, skipped), isTrue);

      await robot.tap('practice');
      final sheet = FastingScheduleRobot(tester);
      await sheet.addExtraDays();
      await sheet.pickDates([forced]);
      await sheet.addDaysOff();
      await sheet.pickDates([skipped]);
      expect(sheet.datesShown(FastingDateKind.force), hasLength(1));
      expect(sheet.datesShown(FastingDateKind.skip), hasLength(1));
      await sheet.close();

      expect(washed(tester, forced), isTrue);
      await _tapCell(tester, 'fasting', forced);
      expect(panelTitles(tester), [en.fastingPersonalFast, en.dayBarWeekend]);
      expect(washed(tester, skipped), isFalse);
      await _tapCell(tester, 'fasting', skipped);
      expect(panelTitles(tester), isEmpty);
      await expectNothingSaved();
    });

    testWidgets('a year is built on a change, never on a frame', (
      tester,
    ) async {
      int builds() => FastingCalendar.debugComputeYearCalls;
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        now: () => DateTime(2027, 11, 10, 10),
      );
      // Every tradition off: nothing to build.
      var before = builds();
      await tester.pump();
      expect(builds() - before, 0, reason: 'open');

      // November's grid shows 2027 alone.
      await robot.tapChip('tradition-orthodox');
      expect(builds() - before, 1, reason: 'a tradition on');

      before = builds();
      await _tapCell(tester, 'fasting', DateTime.utc(2027, 11, 12));
      await tester.pump();
      expect(builds() - before, 0, reason: 'a day tap and a frame');

      await robot.tap('appearance');
      await FastingStyleRobot(tester).pickStyle(FastingDisplayStyle.bar);
      await FastingStyleRobot(tester).close();
      expect(builds() - before, 0, reason: 'a look');

      // December's grid reaches into January: 2028 once.
      await _tapOnPage(
        tester,
        'fasting',
        _inCard('fasting', find.byTooltip(en.dayListNextMonth)),
      );
      expect(builds() - before, 1, reason: 'into the next year');
      await tester.pump();
      expect(builds() - before, 1, reason: 'a frame after the page');

      // The window's two years, once each.
      before = builds();
      await robot.tapChip('tradition-catholic');
      expect(builds() - before, 2, reason: 'a tradition more');
      await expectNothingSaved();
    });
  });

  group('a stage never changes height at text scale 2.0', () {
    testWidgets('alerts: every alert up to the demo\'s cap, the stage within '
        'the screen', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.alerts,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final stage = robot.stageSize;
      // Sized for two alerts, not the editor's five: a stage taller than
      // the phone was ground she scrolled past under Add alert.
      expect(stage.height, lessThan(780));
      for (var i = 0; i < GuideMetrics.demoAlertCap; i++) {
        await robot.tap('add');
        await robot.tapId(SemanticsIds.alertSheetSave);
        expect(robot.control('alert-$i'), findsOneWidget);
        expect(robot.stageSize, stage, reason: '${i + 1} alerts');
      }
      expect(robot.enabled('add'), isFalse);
      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertRemove);
      expect(robot.stageSize, stage);
      expect(robot.enabled('add'), isTrue);
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('kinds: a picked day and the longest rule', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.kinds,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final de = AppLocalizationsDe();
      final stage = robot.stageSize;
      await robot.tap('day');
      await PracticeCalendarRobot(tester).pickInDatePicker(today);
      expect(robot.stageSize, stage, reason: 'a picked day');
      await robot.tap('repeat');
      await _longestWeeklyRule(tester, de);
      await robot.tapId(SemanticsIds.repeatDone);
      expect(
        robot.shows(
          RecurrenceFormatter.format(
            const WeeklyRecurrence(
              weekdays: {1, 2, 3, 4, 5, 6, 7},
              interval: EventRepeatDraft.maxInterval,
            ),
            de,
            'de',
            retroactive: true,
          ),
        ),
        isTrue,
      );
      expect(robot.stageSize, stage, reason: 'the longest rule');
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('attendance: the count under the marks, every mark and the '
        'count switch', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.attendance,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final stage = robot.stageSize;
      final shown = {robot.stageCaptions.first};
      for (final control in [
        'today',
        'day-3',
        'day-0',
        'today',
        'count',
        'count-elapsed',
        'count',
      ]) {
        await robot.tap(control);
        shown.add(robot.stageCaptions.first);
        expect(robot.stageSize, stage, reason: control);
      }
      expect(shown.length, greaterThan(2));
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('setup: every holiday set\'s count and every first day', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.setup,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final stage = robot.stageSize;
      final counts = {robot.stageCaptions.first};
      for (final profile in HolidayProfile.values) {
        await robot.tap('holidays');
        await robot.tapId(
          SemanticsIds.calendarGuideTryControl(
            'setup',
            'holidays-${profile.name}',
          ),
        );
        counts.add(robot.stageCaptions.first);
        expect(robot.stageSize, stage, reason: profile.name);
      }
      for (final start in CalendarWeekStart.values) {
        await robot.tap('week-${start.name}');
        expect(robot.stageSize, stage, reason: start.name);
      }
      expect(counts.length, greaterThan(2));
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('fasting: every switch, both sheets, a page and a picked day', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
        now: () => DateTime(2027, 3, 17, 10),
      );
      final stage = robot.stageSize;
      for (final tradition in FastingTradition.values) {
        await robot.tapChip('tradition-${tradition.name}');
        expect(robot.stageSize, stage, reason: tradition.name);
      }
      await robot.tap('great-fasts');
      expect(robot.stageSize, stage, reason: 'great fasts');
      final style = FastingStyleRobot(tester);
      for (final look in FastingDisplayStyle.values) {
        await robot.tap('appearance');
        await style.pickStyle(look);
        await style.close();
        expect(robot.stageSize, stage, reason: look.name);
      }
      await robot.tap('practice');
      final schedule = FastingScheduleRobot(tester);
      await schedule.weekdaysNone();
      await schedule.close();
      expect(robot.stageSize, stage, reason: 'no weekday');
      await _tapOnPage(
        tester,
        'fasting',
        _inCard(
          'fasting',
          find.byTooltip(AppLocalizationsDe().dayListNextMonth),
        ),
      );
      expect(robot.stageSize, stage, reason: 'April');
      await _tapCell(tester, 'fasting', DateTime.utc(2027, 4, 24));
      expect(robot.stageSize, stage, reason: 'Lazarus Saturday');
      for (final tradition in FastingTradition.values) {
        await robot.tapChip('tradition-${tradition.name}');
        expect(robot.stageSize, stage, reason: '${tradition.name} off');
      }
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('fasting: the fullest day of 2027–2028, every tradition on, '
        'as tall as an empty one', (tester) async {
      // The day the most traditions mark, by the engine itself.
      final years = [
        for (final year in const [2027, 2028])
          FastingCalendar.computeYear(
            year,
            traditions: FastingTradition.values.toSet(),
          ),
      ];
      final fullest = years
          .expand((year) => year.entries)
          .reduce((a, b) => b.value.length > a.value.length ? b : a);
      final day = fullest.key;
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
        now: () => DateTime(day.year, day.month, day.day, 10),
      );
      final idle = robot.stageSize;
      for (final tradition in FastingTradition.values) {
        await robot.tapChip('tradition-${tradition.name}');
      }
      expect(
        tester
            .widget<DaySummaryPanel>(
              _inCard('fasting', find.byType(DaySummaryPanel)),
            )
            .entries
            .where((entry) => entry.key.startsWith('fasting:')),
        hasLength(fullest.value.length),
      );
      expect(fullest.value.length, greaterThanOrEqualTo(3));
      expect(robot.stageSize, idle, reason: '$day, ${fullest.value.length}');

      final year = years[day.year - 2027];
      final unmarked = [
        for (var d = 1; d <= DateUtils.getDaysInMonth(day.year, day.month); d++)
          DateTime.utc(day.year, day.month, d),
      ].firstWhere((d) => year[d] == null);
      await _tapCell(tester, 'fasting', unmarked);
      expect(robot.stageSize, idle, reason: 'unmarked $unmarked');
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    Future<GuideTryCardRobot> openTall(WidgetTester tester, String card) =>
        open(
          tester,
          CalendarGuideTopic.screen,
          locale: const Locale('de'),
          size: const Size(360, 780),
          textScaler: const TextScaler.linear(2.0),
          card: card,
        );

    testWidgets('screen: every format and six pages of months', (tester) async {
      final robot = await openTall(tester, 'screen');
      final stage = robot.stageSize;
      for (final id in const [
        SemanticsIds.calendarFormatWeek,
        SemanticsIds.calendarFormatTwoWeeks,
        SemanticsIds.calendarFormatMonth,
      ]) {
        await robot.tapId(SemanticsIds.calendarViewMenu);
        await robot.tapId(id);
        expect(robot.stageSize, stage, reason: id);
      }
      // Five- and six-row months, short and long titles.
      for (var page = 0; page < 6; page++) {
        await tester.tap(
          _inCard('screen', find.byIcon(Icons.chevron_right_rounded)),
        );
        await tester.pumpAndSettle();
        expect(robot.stageSize, stage, reason: 'page $page');
      }
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('panel: every mode', (tester) async {
      final robot = await openTall(tester, 'panel');
      final stage = robot.stageSize;
      for (final mode in const ['timeline', 'upcoming', 'day']) {
        await robot.tapId(SemanticsIds.panelMode(mode));
        expect(robot.stageSize, stage, reason: mode);
        if (mode == 'timeline') {
          // The real Timeline's own overflow inside its blocks at 2.0
          // (`day_timeline_view.dart`, the record's §6, older than the
          // guide): the calendar page draws the same.
          expect(
            tester.takeException(),
            isA<FlutterError>().having(
              (error) => error.message,
              'message',
              contains('overflowed'),
            ),
          );
        }
      }
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    // D69: the slot grows with the text to 1.3 and stops there, so the Day
    // body under the grown mode bar still holds a whole row.
    testWidgets('panel: the slot is 390 at 1.3 and at 2.0, and holds one '
        'whole Day row at 2.0', (tester) async {
      final height = const TextScaler.linear(
        GuideMetrics.panelStageMaxTextScale,
      ).scale(GuideMetrics.panelStageHeight);
      expect(height, moreOrLessEquals(390));
      Finder slot() => _inCard('panel', find.byType(GuideStageSlot));

      await open(
        tester,
        CalendarGuideTopic.screen,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(1.3),
        card: 'panel',
      );
      expect(tester.getSize(slot()).height, moreOrLessEquals(height));

      await openTall(tester, 'panel');
      final slotRect = tester.getRect(slot());
      expect(slotRect.height, moreOrLessEquals(height));
      final row = tester.getRect(
        find
            .descendant(
              of: _inCard('panel', find.byType(DaySummaryPanel)),
              matching: find.byType(Card),
            )
            .first,
      );
      expect(row.top, greaterThanOrEqualTo(slotRect.top));
      expect(row.bottom, lessThanOrEqualTo(slotRect.bottom));
      await expectNothingSaved();
    });

    testWidgets('overview: every mode, a step, today and a tile', (
      tester,
    ) async {
      final robot = await openTall(tester, 'overview');
      final stage = robot.stageSize;
      for (final control in const [
        'mode-month',
        'next',
        'mode-list',
        'previous',
        'mode-year',
        'next',
        'today',
      ]) {
        await robot.tap(control);
        expect(robot.stageSize, stage, reason: control);
      }
      await _tapOnPage(
        tester,
        'overview',
        _yearTile(DateTime.utc(today.year, today.month), locale: 'de'),
      );
      expect(robot.stageSize, stage, reason: 'a tile');
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    // D66: the coach line stops growing at 1.3, as the practice band does,
    // so at 2.0 its slot is the slot it is at 1.3.
    for (final topic in CalendarGuideTopic.values) {
      for (final card in topic.cards) {
        testWidgets('${card.slug}: the coach line\'s slot at 2.0 is its slot '
            'at 1.3', (tester) async {
          Future<Size> slotAt(double scale) async {
            final robot = await open(
              tester,
              topic,
              locale: const Locale('de'),
              size: const Size(360, 780),
              textScaler: TextScaler.linear(scale),
              now: fixedNowFor(topic),
              card: card.slug,
            );
            return robot.slotSize;
          }

          final clamped = await slotAt(GuideMetrics.coachMaxTextScale);
          expect(await slotAt(2.0), clamped);
          expect(clamped, isNot(await slotAt(1.0)));
          await expectNothingSaved();
        });
      }
    }

    // The coach line's slot, through every step, the card's report where it
    // has one, and the closing line: one height, so a line that grows never
    // pushes the stage down under her finger.
    for (final topic in CalendarGuideTopic.values) {
      for (final card in topic.cards) {
        testWidgets('${card.slug}: the coach line\'s slot, through the steps '
            'and a report', (tester) async {
          final robot = await open(
            tester,
            topic,
            locale: const Locale('de'),
            size: const Size(360, 780),
            textScaler: const TextScaler.linear(2.0),
            now: fixedNowFor(topic),
            card: card.slug,
          );
          // Where the stage starts under the line's top.
          double offset() =>
              tester
                  .getRect(
                    find
                        .descendant(
                          of: robot.card,
                          matching: find.byType(RepaintBoundary),
                        )
                        .first,
                  )
                  .top -
              robot.slotRect.top;
          // Within float noise: the line's inset (D52) is fractional, and the
          // two tops are read after the page has scrolled.
          final gap = moreOrLessEquals(offset(), epsilon: 1e-6);
          note(robot);

          await _changeOnce(tester, robot, topic);
          note(robot);
          expect(offset(), gap, reason: 'after a report');
          while (robot.canSkip) {
            await robot.skip();
            note(robot);
            expect(offset(), gap, reason: robot.line);
          }
          expect(tester.takeException(), isNull);
          expectOneSlotHeight();
          await expectNothingSaved();
        });
      }
    }
  });

  group('the stage\'s controls are nodes of their own under the entry', () {
    // The screen page's cards: the real widgets keep their own ids, the
    // card's additions are `try-*`; a disabled control is a node all the
    // same, with no tap.
    String screenControl(String slug, String control) =>
        SemanticsIds.calendarGuideTryControl(slug, control);
    for (final (slug, live, disabled) in [
      (
        'screen',
        [SemanticsIds.calendarViewMenu, screenControl('screen', 'more')],
        [
          screenControl('screen', 'saved-filters'),
          screenControl('screen', 'filter'),
        ],
      ),
      (
        'panel',
        [
          SemanticsIds.panelMode('day'),
          SemanticsIds.panelMode('timeline'),
          SemanticsIds.panelMode('upcoming'),
        ],
        <String>[],
      ),
      (
        'overview',
        [
          for (final control in const [
            'mode-year',
            'mode-month',
            'mode-list',
            'previous',
            'next',
          ])
            screenControl('overview', control),
        ],
        [
          screenControl('overview', 'search'),
          screenControl('overview', 'today'),
        ],
      ),
    ]) {
      testWidgets(slug, (tester) async {
        final handle = tester.ensureSemantics();
        final robot = await open(tester, CalendarGuideTopic.screen, card: slug);
        final entry = tester.getSemantics(robot.card);
        bool under(SemanticsNode node) {
          for (var p = node.parent; p != null; p = p.parent) {
            if (p.id == entry.id) return true;
          }
          return false;
        }

        final ids = <int>{entry.id};
        for (final name in [
          ...live,
          ...disabled,
          SemanticsIds.calendarGuideTrySkip(slug),
          SemanticsIds.calendarGuideTryCaption(slug),
        ]) {
          final node = tester.getSemantics(find.bySemanticsIdentifier(name));
          expect(under(node), isTrue, reason: name);
          expect(ids.add(node.id), isTrue, reason: '$name shares a node');
          if (live.contains(name) || disabled.contains(name)) {
            expect(
              node.getSemanticsData().hasAction(SemanticsAction.tap),
              live.contains(name),
              reason: name,
            );
          }
        }
        expect(
          entry.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        handle.dispose();
      });
    }

    for (final (topic, controls) in const [
      (
        CalendarGuideTopic.events,
        ['row-dentist', 'row-yoga', 'row-rent', 'add'],
      ),
      (CalendarGuideTopic.kinds, ['repeat', 'add-date', 'day', 'skip']),
      (
        CalendarGuideTopic.alerts,
        ['alert-0', 'add', 'show-alarm', 'quick', 'permissions'],
      ),
      (CalendarGuideTopic.attendance, ['today', 'day-0', 'count']),
      (CalendarGuideTopic.categories, ['row-0', 'eye-0', 'more-0', 'add']),
      (CalendarGuideTopic.finding, ['search', 'match-yoga', 'filter']),
      (CalendarGuideTopic.setup, ['holidays', 'week-sunday', 'settings']),
      (
        CalendarGuideTopic.fasting,
        [
          'tradition-orthodox',
          'tradition-catholic',
          'tradition-muslim',
          'tradition-jewish',
          'appearance',
          'practice',
          'great-fasts',
        ],
      ),
    ]) {
      testWidgets(topic.slug, (tester) async {
        final handle = tester.ensureSemantics();
        final robot = await open(tester, topic);
        // The alerts card's alert row is there once she has added one.
        if (topic == CalendarGuideTopic.alerts) {
          await robot.tap('add');
          await robot.tapId(SemanticsIds.alertSheetSave);
        }

        final entry = tester.getSemantics(robot.card);
        bool under(SemanticsNode node) {
          for (var p = node.parent; p != null; p = p.parent) {
            if (p.id == entry.id) return true;
          }
          return false;
        }

        final ids = <int>{entry.id};
        for (final name in [
          for (final control in controls)
            SemanticsIds.calendarGuideTryControl(topic.slug, control),
          SemanticsIds.calendarGuideTrySkip(topic.slug),
          SemanticsIds.calendarGuideTryCaption(topic.slug),
        ]) {
          final node = tester.getSemantics(find.bySemanticsIdentifier(name));
          expect(under(node), isTrue, reason: name);
          expect(ids.add(node.id), isTrue, reason: '$name shares a node');
        }
        expect(
          entry.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        handle.dispose();
      });
    }
  });

  /// Every card of every page, the screen page's three included.
  final stageCards = [
    for (final topic in CalendarGuideTopic.values)
      for (final card in topic.cards) (topic, card.slug),
  ];

  group('no overflow and no clipped label at text scale 2.0', () {
    for (final (topic, card) in stageCards) {
      for (final locale in const [Locale('de'), Locale('ro')]) {
        for (final size in const [Size(360, 780), Size(412, 915)]) {
          for (final brightness in Brightness.values) {
            testWidgets('$card ${locale.languageCode} '
                '${size.width.toInt()}×${size.height.toInt()} '
                '${brightness.name}', (tester) async {
              final robot = await open(
                tester,
                topic,
                locale: locale,
                brightness: brightness,
                textScaler: const TextScaler.linear(2.0),
                size: size,
                now: fixedNowFor(topic),
                card: card,
              );
              expect(tester.takeException(), isNull);
              Future<void> expectClean(String state) async {
                await tester.ensureVisible(
                  find
                      .descendant(
                        of: robot.card,
                        matching: find.byType(RepaintBoundary),
                      )
                      .first,
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: state);
                final paragraphs = tester.renderObjectList<RenderParagraph>(
                  find.descendant(
                    of: robot.card,
                    matching: find.byType(RichText),
                  ),
                );
                // The unseen copies that size a slot are not drawn: a
                // stand-in cut at its row's limit is not a clipped label.
                bool unseen(RenderObject paragraph) {
                  for (RenderObject? o = paragraph; o != null; o = o.parent) {
                    if (o is RenderOpacity && o.opacity == 0) return true;
                  }
                  return false;
                }

                // The shared widgets' one-line labels, ellipsised by design
                // at 2.0 on the real pages too: a year tile's month and the
                // Day panel's date and row titles (the fasting card's
                // "Mittwochs- und Freitagsfasten").
                final tileLabels = tester
                    .renderObjectList<RenderParagraph>(
                      find.descendant(
                        of: find.byType(YearMonthTile),
                        matching: find.byType(RichText),
                      ),
                    )
                    .toSet();
                final panelLabels = <RenderParagraph>{
                  for (final panel in find.byType(DaySummaryPanel).evaluate())
                    if (panel.widget case final DaySummaryPanel widget)
                      for (final paragraph
                          in tester.renderObjectList<RenderParagraph>(
                            find.descendant(
                              of: find.byWidget(widget),
                              matching: find.byType(RichText),
                            ),
                          ))
                        if ({
                          DateFormat.MMMMEEEEd(
                            locale.languageCode,
                          ).format(widget.day),
                          for (final entry in widget.entries) entry.title,
                        }.contains(paragraph.text.toPlainText()))
                          paragraph,
                };
                for (final paragraph in paragraphs) {
                  if (unseen(paragraph) ||
                      tileLabels.contains(paragraph) ||
                      panelLabels.contains(paragraph)) {
                    continue;
                  }
                  expect(
                    paragraph.didExceedMaxLines,
                    isFalse,
                    reason: '$state: ${paragraph.text.toPlainText()}',
                  );
                }
              }

              await expectClean('idle');
              // One changed state: what she does first on the card.
              await _changeOnce(tester, robot, topic);
              await expectClean('changed');
              await expectNothingSaved();
            });
          }
        }
      }
    }
  });

  // Every card idle and on its closing line, on both phones in both themes:
  // Android's 48 dp targets — the two accepted exceptions taken out by name
  // in `GuideTapTargetGuideline`, the stage's narrowed day cells and the
  // real panel's mode segments — and WCAG's text contrast, which leaves
  // disabled controls out (the fasting rows at 38 % while nothing is on).
  group('the tap-target and text-contrast guidelines', () {
    for (final (topic, card) in stageCards) {
      for (final size in const [Size(360, 780), Size(412, 915)]) {
        for (final brightness in Brightness.values) {
          testWidgets('$card ${size.width.toInt()} ${brightness.name}', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            final robot = await open(
              tester,
              topic,
              brightness: brightness,
              size: size,
              now: fixedNowFor(topic),
              card: card,
            );
            // The card's section — its title, then the card — from the
            // list's top, then, for a section taller than the screen, up to
            // the list's bottom: a text box at the bar's edge would be
            // sampled with the bar's colours, not its own.
            final section = find
                .ancestor(of: robot.card, matching: find.byType(Card))
                .first;
            Future<void> meetsBoth(String state) async {
              final list = find
                  .descendant(
                    of: find.byType(SettingsSectionList),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              final tall =
                  tester.getSize(section).height > tester.getSize(list).height;
              for (final alignment in [0.0, if (tall) 1.0]) {
                await Scrollable.ensureVisible(
                  tester.element(section),
                  alignment: alignment,
                );
                await tester.pumpAndSettle();
                final where = '$state, aligned $alignment';
                await expectLater(
                  tester,
                  meetsGuideline(
                    GuideTapTargetGuideline.of(
                      tester,
                      gridsOf: find.byType(CalendarGuideTryCard),
                    ),
                  ),
                  reason: where,
                );
                await expectLater(
                  tester,
                  meetsGuideline(const GuideTextContrastGuideline()),
                  reason: where,
                );
              }
            }

            await meetsBoth('idle');
            while (robot.canSkip) {
              await robot.skip();
            }
            await meetsBoth('closing');
            handle.dispose();
            await expectNothingSaved();
          });
        }
      }
    }
  });

  // The two exceptions are load-bearing, and no wider than named: the stock
  // guideline fails on the narrowed grid's cells and on the mode segments,
  // and the guide's passes the same screen.
  for (final (card, size, what) in const [
    ('screen', Size(360, 780), 'the grid card\'s day cells at 360'),
    // Labelled, where they fit: on 360 they are 48 dp icons.
    ('panel', Size(412, 915), 'the panel card\'s mode segments at 412'),
  ]) {
    testWidgets('the tap-target exceptions: $what', (tester) async {
      final handle = tester.ensureSemantics();
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        size: size,
        card: card,
      );
      await tester.ensureVisible(robot.card);
      await tester.pumpAndSettle();
      await expectLater(
        tester,
        doesNotMeetGuideline(androidTapTargetGuideline),
      );
      await expectLater(
        tester,
        meetsGuideline(
          GuideTapTargetGuideline.of(
            tester,
            gridsOf: find.byType(CalendarGuideTryCard),
          ),
        ),
      );
      handle.dispose();
      await expectNothingSaved();
    });
  }

  group('no word breaks across lines inside a stage on 360', () {
    // The two words no stage can hold at de 2.0, even edge to edge in the
    // card, 328 dp on a 360 phone: "Wiederholungen" beside the count's
    // switch is wider than the 182 dp its label keeps (the editor's
    // full-width sheet gives it 32 dp more), and "„Kalendereinstellungen“",
    // the guide's own words, wider than the 256 dp of its row. The screen
    // page's cards are the card's cost too, not the widgets': edge to edge
    // in the card they are still 40 dp narrower than the screen, so the
    // weekday row's "Mon" needs 49.5 dp of its column and gets 45.7 ("Wed"
    // the same) under both grids — the overview's mini month included. (A
    // Day panel row's "Wöchentlich" broke there too while the inert rows
    // drew a chevron; without it the caption fits, D69.)
    // Pinned per state where they differ, so any other break fails.
    const unavoidable = {
      'attendance de 2.0': ['Wiederholungen'],
      'setup de 2.0': ['„Kalendereinstellungen“'],
      'screen en 2.0': ['Mon', 'Wed'],
      // The card opens on Month (D68); its change is Year's tiles.
      'overview en 2.0 idle': ['Mon', 'Wed'],
      'overview en 2.0 changed': <String>[],
      // The fasting card's grid, the screen card's cost again.
      'fasting en 2.0': ['Mon', 'Wed'],
    };
    for (final (locale, scale) in const [
      (Locale('de'), 2.0),
      (Locale('de'), 1.3),
      (Locale('en'), 2.0),
    ]) {
      for (final (topic, card) in stageCards) {
        final name = '$card ${locale.languageCode} $scale';
        testWidgets(name, (tester) async {
          final robot = await open(
            tester,
            topic,
            locale: locale,
            textScaler: TextScaler.linear(scale),
            size: const Size(360, 780),
            now: fixedNowFor(topic),
            card: card,
          );
          final stage = find
              .descendant(
                of: robot.card,
                matching: find.byType(RepaintBoundary),
              )
              .first;
          Future<void> expectWholeWords(String state) async {
            await tester.ensureVisible(stage);
            await tester.pumpAndSettle();
            final broken = [
              for (final paragraph in tester.renderObjectList<RenderParagraph>(
                find.descendant(of: stage, matching: find.byType(RichText)),
              ))
                if (!_unseen(paragraph)) ..._brokenWords(paragraph),
            ];
            expect(
              broken,
              unavoidable['$name $state'] ?? unavoidable[name] ?? isEmpty,
              reason: state,
            );
          }

          await expectWholeWords('idle');
          await _changeOnce(tester, robot, topic);
          await expectWholeWords('changed');
          await expectNothingSaved();
        });
      }
    }
  });
}

/// A card whose one step is marked once a sheet's future completes, as the
/// fasting and alerts cards mark theirs — and every other mark after it.
class _SheetProbeDemo extends GuideCardDemo {
  _SheetProbeDemo()
    : super(
        GuideCardSpec('probe', [
          GuideCoachStep('opened', (l10n) => l10n.calendarGuideTryIt),
        ], (l10n) => l10n.calendarGuideTryIt),
      );

  Future<void> open(Future<void> sheet) async {
    await sheet;
    did('opened');
    say((l10n) => l10n.calendarGuideTryIt);
    changed();
    dropReport();
  }

  @override
  Widget buildStage(BuildContext context) => const SizedBox.shrink();
}

/// [matching] inside the card [slug] — the screen page draws two grids and
/// two lists, one each on two of its cards.
Finder _inCard(String slug, Finder matching) => find.descendant(
  of: find.bySemanticsIdentifier(SemanticsIds.calendarGuideTry(slug)),
  matching: matching,
);

TableCalendar<dynamic> _gridOf(WidgetTester tester, String slug) =>
    tester.widget(
      _inCard(
        slug,
        find.byWidgetPredicate((widget) => widget is TableCalendar),
      ),
    );

/// The overview card's period nav.
AgendaPeriodNav _navOf(WidgetTester tester) =>
    tester.widget(_inCard('overview', find.byType(AgendaPeriodNav)));

/// The overview card's year tile for [month], by the label it draws.
Finder _yearTile(DateTime month, {String locale = 'en'}) => _inCard(
  'overview',
  find.byWidgetPredicate(
    (widget) =>
        widget is YearMonthTile &&
        widget.label == AgendaYearGrid.tileLabel(locale, month),
  ),
);

/// [month] as the overview's nav titles a custom span, in English: the
/// overview card's List mode lists one month (D68).
String _monthSpanLabel(DateTime month) => OverviewCustomPeriod(
  DateTime.utc(month.year, month.month),
  DateTime.utc(month.year, month.month + 1, 0),
).menuValue(AppLocalizationsEn());

Finder _cell(String slug, DateTime day) => _inCard(
  slug,
  find.byWidgetPredicate(
    (widget) => widget is CalendarDayCell && isSameDay(widget.day, day),
  ),
);

CalendarDayCell _cellOf(WidgetTester tester, String slug, DateTime day) =>
    tester.widget(_cell(slug, day).first);

/// The gesture surface `table_calendar` wraps [day]'s cell in: the cell sits
/// under the marker layer and takes no hit.
Finder _cellTarget(String slug, DateTime day) => find
    .ancestor(
      of: _cell(slug, day).first,
      matching: find.byType(GestureDetector),
    )
    .first;

/// Taps [day] where it stands, the page scrolled only as far as it needs:
/// `ensureVisible` would scroll the grid's month pager and page it away.
Future<void> _tapCell(WidgetTester tester, String slug, DateTime day) =>
    _tapOnPage(tester, slug, _cellTarget(slug, day));

/// Taps [target] in the card [slug], the page scrolled only as far as it
/// needs ([GuideTryCardRobot.showOnPage]).
Future<void> _tapOnPage(
  WidgetTester tester,
  String slug,
  Finder target,
) async {
  await GuideTryCardRobot(tester, slug).showOnPage(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Whether [paragraph] is one of the unseen copies that size a slot.
bool _unseen(RenderObject paragraph) {
  for (RenderObject? o = paragraph; o != null; o = o.parent) {
    if (o is RenderOpacity && o.opacity == 0) return true;
  }
  return false;
}

/// The words [paragraph] split across two lines anywhere but at a hyphen,
/// read from the boxes each word's characters were laid out in.
List<String> _brokenWords(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  return [
    for (final word in RegExp(
      '[^\\s\\-\\u00AD\\u2010\\u2011\\u2013\\u2014]+',
    ).allMatches(text))
      if (paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: word.start, extentOffset: word.end),
              )
              .map((box) => box.top.round())
              .toSet()
              .length >
          1)
        word.group(0)!,
  ];
}

/// The first thing she would do on [topic]'s card — on the screen page, on
/// the card [robot] drives: a view, a panel mode, a mode, the quick alarm
/// (the events and alerts cards' report), a rule, a mark, a category, a
/// query, a holiday set.
Future<void> _changeOnce(
  WidgetTester tester,
  GuideTryCardRobot robot,
  CalendarGuideTopic topic,
) async {
  switch (topic) {
    case CalendarGuideTopic.screen when robot.slug == 'panel':
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
    case CalendarGuideTopic.screen when robot.slug == 'overview':
      await robot.tap('mode-year');
    case CalendarGuideTopic.screen:
      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarFormatWeek);
    // The two cards with a report: the report alone is the line.
    case CalendarGuideTopic.events:
      await robot.longPress('add');
      await robot.tapId(SemanticsIds.quickAlarmRow);
    case CalendarGuideTopic.alerts:
      await robot.tap('quick');
      await robot.tapId(SemanticsIds.quickAlarmSave);
    case CalendarGuideTopic.kinds:
      await robot.tap('repeat');
      await robot.tapId(SemanticsIds.repeatKind('weekly'));
      await robot.tapId(SemanticsIds.repeatDone);
    case CalendarGuideTopic.attendance:
      await robot.tap('today');
    case CalendarGuideTopic.categories:
      final sheet = CategoryEditorRobot(tester);
      await robot.tap('add');
      await sheet.typeName('Chess');
      await sheet.save();
    case CalendarGuideTopic.finding:
      await tester.enterText(
        find.descendant(
          of: robot.control('search'),
          matching: find.byType(EditableText),
        ),
        'yoga',
      );
      await tester.pumpAndSettle();
    case CalendarGuideTopic.setup:
      await robot.tap('holidays');
      await robot.tapId(
        SemanticsIds.calendarGuideTryControl(
          'setup',
          'holidays-${HolidayProfile.unitedKingdom.name}',
        ),
      );
    case CalendarGuideTopic.fasting:
      await robot.tapChip('tradition-orthodox');
    default:
      fail('$topic has no card');
  }
  // The line moved off the first instruction it rested on — the first line
  // its slot is sized for: to the next one, or to the card's report.
  expect(robot.line, isNot(robot.lineCandidates.first), reason: topic.slug);
}

/// Taps [target] in the open sheet, scrolled into view first.
Future<void> _tapIn(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The open repeat sheet's live controls: the last of each, after the
/// unseen copy that sizes its area.
Finder _inRepeatSheet(Finder matching) =>
    find.descendant(of: find.byType(EventRepeatSheet), matching: matching).last;

/// Turns the open repeat sheet to the longest rule its words can say:
/// weekly, on every weekday, every 99 weeks, also before the start — and,
/// with [endOn], ending that day.
Future<void> _longestWeeklyRule(
  WidgetTester tester,
  AppLocalizations l10n, {
  DateTime? endOn,
}) async {
  await _tapIn(
    tester,
    find.bySemanticsIdentifier(SemanticsIds.repeatKind('weekly')),
  );
  final names = DateFormat.EEEE(l10n.localeName);
  for (var weekday = 1; weekday <= 7; weekday++) {
    final name = names.format(DateTime(2024, 1, weekday));
    final cell = _inRepeatSheet(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == name,
      ),
    );
    if (tester.widget<Semantics>(cell).properties.selected ?? false) continue;
    await _tapIn(tester, cell);
  }
  final more = _inRepeatSheet(find.byTooltip(l10n.recurrenceIntervalIncrement));
  await tester.ensureVisible(more);
  await tester.pumpAndSettle();
  for (var i = 1; i < EventRepeatDraft.maxInterval; i++) {
    await tester.tap(more);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  if (endOn != null) {
    await _tapIn(tester, _inRepeatSheet(find.text(l10n.never)));
    await PracticeCalendarRobot(tester).pickInDatePicker(endOn);
  }
  await _tapIn(tester, _inRepeatSheet(find.byType(Switch)));
}
