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
import 'package:anta/constants/app_colors.dart';
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
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
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
import 'package:anta/widgets/calendar_guide_bar.dart';
import 'package:anta/widgets/calendar_guide_demo_panel.dart';
import 'package:anta/widgets/calendar_guide_grid.dart';
import 'package:anta/widgets/calendar_guide_stage_slot.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/calendar_guide_try_kinds.dart';
import 'package:anta/widgets/calendar_guide_try_screen.dart';
import 'package:anta/widgets/calendar_header_menus.dart';
import 'package:anta/widgets/category_editor_sheet.dart';
import 'package:anta/widgets/day_summary_panel.dart';
import 'package:anta/widgets/day_timeline_view.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/month_dot_matrix.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';
import 'package:anta/widgets/settings_reorder.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/value_change_highlight.dart';
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
  /// whatever day the suite runs; the finding card lists days from the first
  /// of the month, so its cases stand mid-month, where Yoga's missed week
  /// (a week back) is inside it; the other cards read today.
  DateTime Function() fixedNowFor(CalendarGuideTopic topic) => switch (topic) {
    CalendarGuideTopic.fasting => () => DateTime(2027, 3, 17, 10),
    CalendarGuideTopic.finding => () => DateTime(2026, 10, 14, 10),
    _ => DateTime.now,
  };

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
        tester.getTopLeft(find.text(en.calendarGuideTryIt.toUpperCase())).dy,
        lessThan(
          tester
              .getTopLeft(find.text(en.calendarGuideHowItWorks.toUpperCase()))
              .dy,
        ),
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

      expect(find.text(en.calendarGuideTryIt.toUpperCase()), findsNothing);
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

  group('the stepper (D70)', () {
    Finder captionOf(String slug) =>
        find.bySemanticsIdentifier(SemanticsIds.calendarGuideTryCaption(slug));

    testWidgets('back and forward: ids, glyphs and tooltips at the live line '
        'and reading back; back off on the first step', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final steps = stepsOfCard(CalendarGuideTopic.events.cards.first);
      IconButton button(Finder f) => tester.widget<IconButton>(
        find.descendant(of: f, matching: find.byType(IconButton)),
      );
      IconData glyph(Finder f) => (button(f).icon as Icon).icon!;

      expect(robot.backButton, findsOneWidget);
      expect(robot.canBack, isFalse, reason: 'nothing done before the first');
      expect(robot.canSkip, isTrue);
      expect(glyph(robot.backButton), Icons.chevron_left_rounded);
      expect(button(robot.backButton).tooltip, en.calendarGuideStepBack);
      expect(glyph(robot.skipButton), Icons.skip_next_rounded);
      expect(button(robot.skipButton).tooltip, en.calendarGuideSkipStep);

      await robot.skip();
      await robot.skip();
      expect(robot.line, steps[2]);
      expect(robot.canBack, isTrue);

      await robot.back();
      expect(robot.reading, isTrue);
      expect(robot.line, steps[1]);
      expect(glyph(robot.skipButton), Icons.chevron_right_rounded);
      expect(button(robot.skipButton).tooltip, en.calendarGuideStepForward);
      expect(robot.canSkip, isTrue);

      await robot.back();
      expect(robot.line, steps[0]);
      expect(robot.canBack, isFalse);

      await robot.skip();
      expect(robot.line, steps[1]);
      await robot.skip();
      expect(robot.reading, isFalse, reason: 'forward returned to the live');
      expect(robot.line, steps[2]);
      expect(glyph(robot.skipButton), Icons.skip_next_rounded);

      // At the live line forward is today's skip.
      await robot.skip();
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.canSkip, isFalse);
      expect(robot.canBack, isTrue);
      await robot.back();
      expect(robot.line, steps[2]);
      expect(robot.canSkip, isTrue, reason: 'forward is on while reading');
      await expectNothingSaved();
    });

    testWidgets('a step done on the stage snaps a read-back view to the live '
        'line', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      final steps = stepsOfCard(CalendarGuideTopic.alerts.cards.first);
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      final live = robot.line;
      expect(live, isNot(steps.first));

      await robot.back();
      expect(robot.reading, isTrue);
      expect(robot.line, steps.first);

      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.reading, isFalse);
      await expectNothingSaved();
    });

    testWidgets('the read-back line: muted paragraph text led by a primary '
        'done mark that scales with the text', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.events,
        textScaler: const TextScaler.linear(1.3),
      );
      final colorScheme = Theme.of(tester.element(robot.card)).colorScheme;
      final caption = captionOf(CalendarGuideTopic.events.slug);
      // The paragraph's own: the first, above the mark's glyph.
      Color lineColor() =>
          (tester
                      .widget<RichText>(
                        find
                            .descendant(
                              of: caption,
                              matching: find.byType(RichText),
                            )
                            .first,
                      )
                      .text
                  as TextSpan)
              .style!
              .color!;
      final mark = find.descendant(
        of: caption,
        matching: find.byIcon(Icons.check_rounded),
      );

      expect(lineColor(), isSameColorAs(colorScheme.onSurface));
      expect(mark, findsNothing);

      await robot.skip();
      await robot.back();
      expect(lineColor(), isSameColorAs(colorScheme.onSurfaceVariant));
      expect(mark, findsOneWidget);
      expect(
        tester.widget<Icon>(mark).color,
        isSameColorAs(colorScheme.primary),
      );
      // The paragraph scales its inline mark with the text (D90).
      expect(
        tester.getRect(mark).height,
        moreOrLessEquals(GuideMetrics.coachDoneMarkSize * 1.3, epsilon: 0.01),
      );
      expect(
        robot.readBackCandidates,
        stepsOfCard(CalendarGuideTopic.events.cards.first),
      );
      await expectNothingSaved();
    });

    testWidgets('semantics: a live region at the live line; reading back it '
        'is off and the node reads Done before the line', (tester) async {
      final handle = tester.ensureSemantics();
      final robot = await open(tester, CalendarGuideTopic.events);
      final steps = stepsOfCard(CalendarGuideTopic.events.cards.first);
      SemanticsData node() => tester
          .getSemantics(captionOf(CalendarGuideTopic.events.slug))
          .getSemanticsData();

      expect(node().label, steps[0]);
      expect(node().flagsCollection.isLiveRegion, isTrue);

      await robot.skip();
      await robot.back();
      expect(node().label, '${en.calendarGuideStepDone}\n${steps[0]}');
      expect(node().flagsCollection.isLiveRegion, isFalse);
      final back = tester.getSemantics(robot.backButton).getSemanticsData();
      expect(back.tooltip, en.calendarGuideStepBack);

      await robot.skip();
      expect(node().label, steps[1]);
      expect(node().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('forward sits where the skip sat: trailing on the card\'s '
        'inset, 48 square, back touching it on its left', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final forward = tester.getRect(robot.skipButton);
      final back = tester.getRect(robot.backButton);

      expect(forward.size, const Size.square(FormMetrics.trailingButtonSize));
      expect(back.size, const Size.square(FormMetrics.trailingButtonSize));
      // The stage's inset patch ends where the coach row ends.
      expect(
        forward.right,
        moreOrLessEquals(robot.stageRect.right, epsilon: 1),
      );
      expect(back.right, moreOrLessEquals(forward.left, epsilon: 0.01));
      expect(back.top, forward.top);
      expect(robot.slotRect.right, moreOrLessEquals(back.left, epsilon: 0.01));
    });

    testWidgets('fasting: with every tradition off back waits — the line '
        'asks for a tradition in place of the step (D44), and the step before '
        'would read back in the same words; a tradition on brings back and '
        'the read-back lines', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.fasting,
        now: fixedNowFor(CalendarGuideTopic.fasting),
      );
      final steps = stepsOfCard(CalendarGuideTopic.fasting.cards.first);
      await robot.skip();
      await robot.skip();
      expect(robot.line, steps.first, reason: 'D44 asks for a tradition');
      expect(
        robot.canBack,
        isFalse,
        reason: 'back would show the same words, muted',
      );

      // A tradition on: the real next step speaks again, and back works.
      await robot.tapChip('tradition-orthodox');
      expect(robot.line, steps[2]);
      expect(robot.canBack, isTrue);
      await robot.back();
      expect(robot.reading, isTrue);
      expect(robot.line, steps[1]);
      await robot.back();
      expect(robot.line, steps[0]);
      await robot.skip();
      await robot.skip();
      expect(robot.reading, isFalse);
      expect(robot.line, steps[2]);
      await expectNothingSaved();
    });

    // D93: the slot also holds every step line read back with its mark, beside
    // the pair's 96 dp; the designer's numbers, as built.
    // 2.0 stays clamped to 1.3 (D66).
    for (final (topic, at10, at13) in const [
      (CalendarGuideTopic.kinds, 80.0, 100.0),
      (CalendarGuideTopic.alerts, 60.0, 125.0),
      (CalendarGuideTopic.fasting, 80.0, 150.0),
    ]) {
      testWidgets('${topic.slug}: the slot at de 1.0 / 1.3 / 2.0 is '
          '$at10 / $at13 / $at13', (tester) async {
        Future<double> slotAt(double scale) async {
          final robot = await open(
            tester,
            topic,
            locale: const Locale('de'),
            size: const Size(360, 780),
            textScaler: TextScaler.linear(scale),
            now: fixedNowFor(topic),
          );
          return robot.slotSize.height;
        }

        expect(await slotAt(1.0), moreOrLessEquals(at10, epsilon: 0.5));
        expect(await slotAt(1.3), moreOrLessEquals(at13, epsilon: 0.5));
        expect(await slotAt(2.0), moreOrLessEquals(at13, epsilon: 0.5));
      });
    }
  });

  group('screen', () {
    final steps = stepsOf(CalendarGuideTopic.screen);
    final yoga = en.calendarGuideDemoEventYoga;

    /// The Overview view's controls, which keep the overview card's ids
    /// (D86); the card, its coach and its stage are the screen card's.
    GuideTryCardRobot overviewOf(WidgetTester tester) =>
        GuideTryCardRobot(tester, 'overview');

    Finder viewBody(CalendarViewPage view) => find.bySemanticsIdentifier(
      SemanticsIds.calendarGuideScreenView(view.name),
    );

    /// Picks [row] in the stage's title menu.
    Future<void> pick(GuideTryCardRobot robot, String row) async {
      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(row);
    }

    Future<void> showOverview(GuideTryCardRobot robot) =>
        pick(robot, SemanticsIds.calendarOverviewOpen);

    Future<void> showCalendar(GuideTryCardRobot robot) =>
        pick(robot, SemanticsIds.calendarViewCalendar);

    CalendarViewPage shownView(WidgetTester tester) =>
        tester.widget<GuideCalendarBar>(find.byType(GuideCalendarBar)).page;

    DaySummaryPanel dayPanel(WidgetTester tester) =>
        tester.widget<DaySummaryPanel>(find.byType(DaySummaryPanel));

    AgendaMonthGrid miniMonth(WidgetTester tester) =>
        tester.widget<AgendaMonthGrid>(
          _inCard('screen', find.byType(AgendaMonthGrid)),
        );

    /// The stage's one slot: the bar and the view under it.
    Finder stageSlot() => _inCard('screen', find.byType(GuideStageSlot)).first;

    testWidgets('one card under "Try it", above How it works; its tour in '
        'the order the stage asks for it (D73)', (tester) async {
      await open(tester, CalendarGuideTopic.screen);
      final list = tester.widget<SettingsSectionList>(
        find.byType(SettingsSectionList),
      );
      final card = CalendarGuideTopic.screen.cards.single;
      expect(card.slug, 'screen');
      expect(
        [for (final step in card.steps) step.action],
        ['panel', 'more', 'overview', 'mode', 'period', 'report'],
      );
      expect(list.sections.first.title, en.calendarGuideTryIt);
      expect(list.sections.first.entries.single.title, steps.first);
      expect(list.sections[1].title, en.calendarGuideHowItWorks);
      // It opens on the Calendar (D84).
      expect(shownView(tester), CalendarViewPage.calendar);
      expect(viewBody(CalendarViewPage.calendar), findsOneWidget);
      await expectNothingSaved();
    });

    testWidgets('the title menu switches the stage Calendar → Overview → '
        'Calendar at one height; the view shown only closes the menu', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      final stage = robot.stageSize;
      expect(viewBody(CalendarViewPage.overview), findsNothing);

      await showOverview(robot);
      expect(shownView(tester), CalendarViewPage.overview);
      expect(viewBody(CalendarViewPage.overview), findsOneWidget);
      expect(viewBody(CalendarViewPage.calendar), findsNothing);
      expect(find.byType(GuideCalendarGrid), findsNothing);
      expect(robot.stageSize, stage);

      // The Overview's own row: the menu closes, nothing else moves.
      final line = robot.line;
      await pick(robot, SemanticsIds.calendarOverviewOpen);
      expect(shownView(tester), CalendarViewPage.overview);
      expect(robot.line, line);

      await showCalendar(robot);
      expect(shownView(tester), CalendarViewPage.calendar);
      expect(viewBody(CalendarViewPage.calendar), findsOneWidget);
      expect(find.byType(GuideCalendarGrid), findsOneWidget);
      expect(robot.stageSize, stage);

      await pick(robot, SemanticsIds.calendarViewCalendar);
      expect(shownView(tester), CalendarViewPage.calendar);
      expect(find.byType(PopupMenuItem<CalendarViewPage>), findsNothing);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    // D77: the stage is 668 at 1.0 and grows with the panel's share to 1.3,
    // 706.4, and no further; one height in every view and format.
    for (final (locale, size, scale, height) in const [
      (Locale('en'), Size(412, 915), 1.0, 668.0),
      (Locale('en'), Size(412, 915), 1.3, 706.4),
      (Locale('de'), Size(360, 780), 2.0, 706.4),
    ]) {
      testWidgets('the stage is $height at $scale in both views and every '
          'format', (tester) async {
        final robot = await open(
          tester,
          CalendarGuideTopic.screen,
          locale: locale,
          size: size,
          textScaler: TextScaler.linear(scale),
        );
        expect(
          GuideScreenDemo.heightFor(TextScaler.linear(scale)),
          moreOrLessEquals(height),
        );
        expect(tester.getSize(stageSlot()).height, moreOrLessEquals(height));
        // The stage's box, its hairlines included, is the slot (D80).
        expect(robot.stageSize.height, moreOrLessEquals(height));
        final stage = robot.stageSize;
        for (final (id, format) in const [
          (SemanticsIds.calendarFormatTwoWeeks, CalendarFormat.twoWeeks),
          (SemanticsIds.calendarFormatWeek, CalendarFormat.week),
          (SemanticsIds.calendarFormatMonth, CalendarFormat.month),
        ]) {
          await pick(robot, id);
          expect(_gridOf(tester, 'screen').calendarFormat, format);
          expect(
            robot.stageSize.height,
            moreOrLessEquals(stage.height, epsilon: 1),
            reason: format.name,
          );
          await showOverview(robot);
          expect(
            robot.stageSize.height,
            moreOrLessEquals(stage.height, epsilon: 1),
            reason: 'overview after ${format.name}',
          );
          await showCalendar(robot);
        }
        expect(tester.takeException(), isNull);
        await expectNothingSaved();
      });
    }

    // D77's risk: the coach line names the panel, so its mode bar and the
    // Day panel's first row stand inside the stage in the month format — in
    // May 2027, six rows, the row ends 656 dp under the stage's top at 1.0
    // (689 of 706.4 at 1.3); in September 2027, five rows, 62 dp higher.
    for (final locale in const ['en', 'de']) {
      for (final scale in const [1.0, 1.3]) {
        for (final (month, rows) in const [(5, 6), (9, 5)]) {
          testWidgets('$locale at $scale, a $rows-row month: the mode bar and '
              'the first Day row whole inside the stage', (tester) async {
            await open(
              tester,
              CalendarGuideTopic.screen,
              locale: Locale(locale),
              size: const Size(360, 780),
              textScaler: TextScaler.linear(scale),
              now: () => DateTime(2027, month, 12, 10),
            );
            expect(
              _gridOf(tester, 'screen').calendarFormat,
              CalendarFormat.month,
            );
            final slot = tester.getRect(stageSlot());
            final modeBar = tester.getRect(find.byType(PanelModeBar));
            final row = tester.getRect(
              find
                  .descendant(
                    of: find.byType(DaySummaryPanel),
                    matching: find.byType(Card),
                  )
                  .first,
            );
            expect(
              slot.height,
              moreOrLessEquals(
                GuideScreenDemo.heightFor(TextScaler.linear(scale)),
              ),
            );
            expect(modeBar.top, greaterThan(slot.top));
            expect(row.top, greaterThan(modeBar.bottom));
            expect(row.bottom, lessThanOrEqualTo(slot.bottom));
            if (scale == 1.0 && rows == 6) {
              expect(row.bottom - slot.top, moreOrLessEquals(656, epsilon: 1));
            }
            await expectNothingSaved();
          });
        }
      }
    }

    testWidgets('de at 2.0: a six-row and a five-row month, each in the '
        'Calendar and in the Overview, at one stage height', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
        now: () => DateTime(2027, 5, 12, 10),
      );
      final overview = overviewOf(tester);
      final height = GuideScreenDemo.heightFor(const TextScaler.linear(2.0));
      void expectStage(String what) {
        expect(tester.takeException(), isNull, reason: what);
        expect(
          robot.stageSize.height,
          moreOrLessEquals(height, epsilon: 1),
          reason: what,
        );
      }

      Future<void> toSeptember() async {
        for (var i = 0; i < 4; i++) {
          await tester.tap(
            _inCard('screen', find.byIcon(Icons.chevron_right_rounded)),
          );
          await tester.pumpAndSettle();
        }
      }

      double gridHeight() => tester
          .getSize(_inCard('screen', find.byType(GuideCalendarGrid)))
          .height;

      // May 2027 starts on a Saturday: six rows from either first weekday;
      // September 2027 on a Wednesday: five.
      expectStage('May in the Calendar');
      final sixRows = gridHeight();
      await toSeptember();
      expect(_gridOf(tester, 'screen').focusedDay.month, 9);
      expect(gridHeight(), lessThan(sixRows));
      expectStage('September in the Calendar');

      await showOverview(robot);
      // No pick since: the Overview opens on the picked day's May.
      expect(miniMonth(tester).month, DateTime.utc(2027, 5));
      expectStage('May in the Overview');
      for (var i = 0; i < 4; i++) {
        await overview.tap('next');
      }
      expect(miniMonth(tester).month, DateTime.utc(2027, 9));
      expectStage('September in the Overview');
      await expectNothingSaved();
    });

    testWidgets('the grounds in light: the Calendar\'s bar and grid on '
        '`surface`, its panel on `pageGround`; the Overview\'s bar on '
        '`pageGround` (D79)', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      final scheme = AppTheme.light().colorScheme;
      Color barGround() => tester
          .widget<GuideCalendarBar>(find.byType(GuideCalendarBar))
          .backgroundColor;
      // The nearest ground a widget is drawn on.
      Color groundOf(Type type) => tester
          .widget<ColoredBox>(
            find
                .ancestor(
                  of: _inCard('screen', find.byType(type)).first,
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;

      expect(barGround(), scheme.surface);
      expect(groundOf(GuideCalendarGrid), scheme.surface);
      expect(groundOf(PanelModeBar), scheme.pageGround);
      await showOverview(robot);
      expect(barGround(), scheme.pageGround);
      await expectNothingSaved();
    });

    // D77's risk: her look with the most bars a day can carry raises the
    // grid's rows; the panel's share gives way (`Expanded`), the stage
    // does not.
    for (final scale in const [1.0, 2.0]) {
      testWidgets('the most bars a day can carry at $scale: a taller grid, '
          'the same stage, nothing overflows', (tester) async {
        Future<(double, double, double)> measure() async {
          final robot = await open(
            tester,
            CalendarGuideTopic.screen,
            locale: const Locale('de'),
            size: const Size(360, 780),
            textScaler: TextScaler.linear(scale),
            now: () => DateTime(2027, 5, 12, 10),
          );
          expect(tester.takeException(), isNull);
          return (
            robot.stageSize.height,
            tester
                .getSize(_inCard('screen', find.byType(GuideCalendarGrid)))
                .height,
            tester.getSize(find.byType(GuideDemoPanel)).height,
          );
        }

        final (stage, grid, panel) = await measure();
        await (await SettingsService.getInstance()).setCalendarMaxDayBars(
          SettingsKeys.maxCalendarMaxDayBars,
        );
        writes.statements.clear();
        // A fresh page reads her look again.
        await tester.pumpWidget(const SizedBox.shrink());
        final (fullStage, fullGrid, fullPanel) = await measure();
        expect(fullGrid, greaterThan(grid));
        expect(fullStage, moreOrLessEquals(stage, epsilon: 1));
        expect(fullPanel, moreOrLessEquals(panel - (fullGrid - grid)));
        expect(writes.statements, isEmpty);
        expect(staticRevisions(), revisions);
      });
    }

    // D80: the bar and the views reach the stage's edges, so its hairlines
    // are drawn over them — in the dark, where the page's ground is the
    // bar's, they are what tells the stage's bar from the page's.
    testWidgets('the stage\'s hairlines show above the bar and below the '
        'view in both views', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      final outline = AppTheme.light().colorScheme.outlineVariant.toARGB32();
      final stage = find
          .descendant(of: robot.card, matching: find.byType(RepaintBoundary))
          .first;
      Future<void> expectHairlines(String view) async {
        await tester.ensureVisible(stage);
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(stage);
        final (width, height, pixels) = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData();
          final shot = (image.width, image.height, bytes!);
          image.dispose();
          return shot;
        }))!;
        expect(
          height,
          GuideScreenDemo.heightFor(TextScaler.noScaling).round(),
          reason: view,
        );
        int argbAt(int x, int y) {
          final i = (y * width + x) * 4;
          return Color.fromARGB(
            pixels.getUint8(i + 3),
            pixels.getUint8(i),
            pixels.getUint8(i + 1),
            pixels.getUint8(i + 2),
          ).toARGB32();
        }

        for (final (edge, y) in [('top', 0), ('bottom', height - 1)]) {
          for (final x in [width ~/ 8, width ~/ 2, width * 7 ~/ 8]) {
            expect(argbAt(x, y), outline, reason: '$view $edge at $x');
          }
        }
      }

      await expectHairlines('calendar');
      await showOverview(robot);
      await expectHairlines('overview');
      await expectNothingSaved();
    });

    testWidgets('the tour: the panel, the ⋮, the Overview through the title, '
        'its chips, its arrows; the Report says where it would lead and the '
        'view stays', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      expect(robot.line, steps[0]);
      note(robot);

      await robot.tapId(SemanticsIds.panelMode('timeline'));
      expect(robot.line, steps[1]);
      note(robot);

      await robot.tap('more');
      await robot.tapId(SemanticsIds.calendarSettingsOpen);
      expect(robot.line, steps[2]);
      note(robot);

      await showOverview(robot);
      expect(robot.line, steps[3]);
      note(robot);

      final overview = overviewOf(tester);
      await overview.tap('mode-list');
      expect(robot.line, steps[4]);
      note(robot);

      await overview.tap('next');
      expect(robot.line, steps[5]);
      note(robot);

      await pick(robot, SemanticsIds.calendarReportOpen);
      expect(robot.line, en.calendarGuideWouldOpen(en.reportTitle));
      expect(shownView(tester), CalendarViewPage.overview);
      note(robot);

      // The skip under a standing report only clears it (D46); the Report
      // step waits for its view.
      await robot.skip();
      expect(robot.line, steps[5]);
      await robot.skip();
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.canSkip, isFalse);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('a step done early is not asked again', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);

      await robot.tap('more');
      await robot.tapId(SemanticsIds.calendarExport);
      expect(robot.line, steps[0]);
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
      expect(robot.line, steps[2]);
      await expectNothingSaved();
    });

    testWidgets('the Calendar: the formats reshape the grid; the saved '
        'filters and the funnel drawn disabled; the panel offers no expand '
        'and no presence button', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      for (final (id, format) in const [
        (SemanticsIds.calendarFormatTwoWeeks, CalendarFormat.twoWeeks),
        (SemanticsIds.calendarFormatWeek, CalendarFormat.week),
        (SemanticsIds.calendarFormatMonth, CalendarFormat.month),
      ]) {
        await pick(robot, id);
        expect(_gridOf(tester, 'screen').calendarFormat, format);
        expect(robot.line, steps[0]);
      }
      final bar = tester.widget<GuideCalendarBar>(
        find.byType(GuideCalendarBar),
      );
      expect(bar.backgroundColor, AppTheme.light().colorScheme.surface);
      for (final name in const ['saved-filters', 'filter']) {
        expect(
          tester
              .widget<IconButton>(
                find.descendant(
                  of: robot.control(name),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
          reason: name,
        );
      }
      expect(dayPanel(tester).day, today);
      expect(dayPanel(tester).onToggleMissed, isNull);
      final expand = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(PanelModeBar),
          matching: find.byType(IconButton),
        ),
      );
      expect(expand.onPressed, isNull);
      for (final (mode, body) in [
        ('timeline', DayTimelineView),
        ('day', DaySummaryPanel),
      ]) {
        await robot.tapId(SemanticsIds.panelMode(mode));
        expect(_inCard('screen', find.byType(body)), findsOneWidget);
      }
      await expectNothingSaved();
    });

    testWidgets('the Overview\'s bar: its options and saved views drawn '
        'disabled, the ⋮ live, no formats in the title menu', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      await showOverview(robot);
      final bar = tester.widget<GuideCalendarBar>(
        find.byType(GuideCalendarBar),
      );
      expect(bar.backgroundColor, AppTheme.light().colorScheme.pageGround);
      expect(bar.format, isNull);
      for (final name in const ['overview-options', 'overview-views']) {
        expect(
          tester
              .widget<IconButton>(
                find.descendant(
                  of: robot.control(name),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
          reason: name,
        );
      }
      expect(robot.control('saved-filters'), findsNothing);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.calendarFormatWeek),
        findsNothing,
      );
      await robot.tapId(SemanticsIds.calendarOverviewOpen);

      // The ⋮ is the tour's step in every view: done here — with the
      // Overview's own step, done by coming here — the panel's step leads
      // past both.
      await robot.tap('more');
      await robot.tapId(SemanticsIds.calendarGuideOpen);
      expect(robot.line, steps[0]);
      await showCalendar(robot);
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
      expect(robot.line, steps[3]);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    testWidgets('the Overview: the chips switch modes in one height, the '
        'arrows and Today step the period, a tile opens its month', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      await showOverview(robot);
      final overview = overviewOf(tester);
      final stage = robot.stageSize;
      String title() => _navOf(tester).title;
      DateTime gridMonth() => miniMonth(tester).month;

      // D68: Month, on the shared day's month, the day picked; the search
      // drawn disabled.
      expect(overview.chip('mode-month').selected, isTrue);
      final thisMonth = DateTime.utc(today.year, today.month);
      expect(gridMonth(), thisMonth);
      expect(miniMonth(tester).selectedDay, today);
      expect(
        title(),
        AgendaListView.monthLabel('en', thisMonth, withYear: true),
      );
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: overview.control('search'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await overview.tap('mode-year');
      expect(robot.stageSize, stage, reason: 'year');
      // Year: the year's twelve tiles.
      expect(
        tester
            .widget<AgendaYearGrid>(
              _inCard('screen', find.byType(AgendaYearGrid)),
            )
            .tiles
            .map((tile) => tile.month),
        AgendaMonthStore.monthsOfYear(today.year),
      );
      expect(title(), '${today.year}');

      await overview.tap('next');
      // The panel's step is still first: the Overview's marks wait behind
      // it.
      expect(robot.line, steps[0]);
      expect(title(), '${today.year + 1}');
      await overview.tap('today');
      expect(title(), '${today.year}');

      await overview.tap('mode-list');
      expect(robot.stageSize, stage, reason: 'list');
      expect(title(), _monthSpanLabel(thisMonth));

      await overview.tap('mode-month');
      expect(robot.stageSize, stage, reason: 'month');
      await overview.tap('previous');
      expect(gridMonth(), DateTime.utc(today.year, today.month - 1));

      // A tile opens its month, as the overview's do: here the month she
      // was on, whose row Year opens on.
      await overview.tap('mode-year');
      expect(robot.stageSize, stage, reason: 'year');
      final lastMonth = DateTime.utc(today.year, today.month - 1);
      await _tapOnPage(tester, 'screen', _yearTile(lastMonth));
      expect(overview.chip('mode-month').selected, isTrue);
      expect(gridMonth(), lastMonth);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    // D68: Year opens with the row of the month she was on in view — at its
    // top when the year is taller than the view, from its own scroll offset
    // laid out by the grid's delegate; at 1.0 the stage's view holds the
    // whole year.
    for (final (shown, size, scale) in [
      (DateTime.utc(2027, 5), const Size(412, 915), 1.0),
      (DateTime.utc(2027, 5), const Size(360, 780), 1.0),
      (DateTime.utc(2027, 12), const Size(360, 780), 1.0),
      (DateTime.utc(2027, 8), const Size(360, 780), 2.0),
    ]) {
      testWidgets('the Overview: Year opens on the row that holds the month '
          'shown, ${shown.month} on ${size.width.toInt()} at $scale', (
        tester,
      ) async {
        final robot = await open(
          tester,
          CalendarGuideTopic.screen,
          size: size,
          textScaler: TextScaler.linear(scale),
          now: () => DateTime(shown.year, shown.month, 12, 10),
        );
        await showOverview(robot);
        final overview = overviewOf(tester);
        await overview.tap('mode-year');
        final grid = find
            .descendant(
              of: _inCard('screen', find.byType(AgendaYearGrid)),
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
        // Its row the slot's first, the row above scrolled off — unless the
        // grid stops at its end first (a last row, or a year that fits).
        if (position.pixels < position.maxScrollExtent - 0.5) {
          expect(row, greaterThan(0));
          expect(tile.top, moreOrLessEquals(0, epsilon: 0.5));
        }
        if (scale > 1) expect(position.maxScrollExtent, greaterThan(0));
        // Stepped away and back, the year opens on that row again.
        await overview.tap('next');
        await overview.tap('previous');
        expect(measure().$1, rectMoreOrLessEquals(tile, epsilon: 0.01));
        await expectNothingSaved();
      });
    }

    testWidgets('the Overview: List lists the shown month; ◄ ► step a month '
        'in Month and List and a year in Year', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        now: () => DateTime(2027, 5, 12, 10),
      );
      await showOverview(robot);
      final overview = overviewOf(tester);
      String title() => _navOf(tester).title;
      final may = DateTime.utc(2027, 5);
      final june = DateTime.utc(2027, 6);
      // The months the list's sections name, by their labels.
      Set<DateTime> listedMonths() {
        final labels = {
          for (final label in tester.widgetList<FormSectionLabel>(
            _inCard(
              'screen',
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

      await overview.tap('mode-list');
      expect(title(), _monthSpanLabel(may));
      expect(listedMonths(), {may});
      await overview.tap('next');
      expect(title(), _monthSpanLabel(june));
      expect(listedMonths(), {june});

      await overview.tap('mode-month');
      expect(title(), AgendaListView.monthLabel('en', june, withYear: true));
      await overview.tap('next');
      expect(
        title(),
        AgendaListView.monthLabel('en', DateTime.utc(2027, 7), withYear: true),
      );

      await overview.tap('mode-year');
      expect(title(), '2027');
      await overview.tap('next');
      expect(title(), '2028');
      await overview.tap('today');
      expect(title(), '2027');
      await overview.tap('mode-list');
      expect(title(), _monthSpanLabel(may));
      await expectNothingSaved();
    });

    testWidgets('one picked day: the grid\'s pick is the panel\'s day and '
        'the Overview month\'s, and a day picked there is the grid\'s', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      // Yoga's day a week away, inside today's month either way.
      final picked = today.day > 7 ? day(-7) : day(7);
      await _tapCell(tester, 'screen', picked);
      expect(_cellOf(tester, 'screen', picked).isSelected, isTrue);
      expect(dayPanel(tester).day, picked);

      await showOverview(robot);
      expect(miniMonth(tester).selectedDay, picked);
      // The picked day's rows sit under the mini month, in the view's own
      // scroll.
      final slot = _inCard('screen', find.byType(CustomScrollView));
      await tester.drag(slot, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        _inCard('screen', find.text(yoga, findRichText: true)),
        findsWidgets,
      );
      await tester.drag(slot, const Offset(0, 300));
      await tester.pumpAndSettle();

      // The first of the month carries the rent: a day to pick there.
      final first = DateTime.utc(today.year, today.month, 1);
      await _tapCell(tester, 'screen', first);
      expect(miniMonth(tester).selectedDay, first);
      await tester.drag(slot, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(
        _inCard(
          'screen',
          find.text(en.calendarGuideDemoEventRent, findRichText: true),
        ),
        findsWidgets,
      );

      await showCalendar(robot);
      expect(dayPanel(tester).day, first);
      expect(_cellOf(tester, 'screen', first).isSelected, isTrue);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    testWidgets('D83: the Overview opens on the month of a day picked on the '
        'grid since it was left; with no new pick it is as she left it', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        now: () => DateTime(2027, 5, 12, 10),
      );
      await showOverview(robot);
      final overview = overviewOf(tester);
      expect(miniMonth(tester).month, DateTime.utc(2027, 5));
      await overview.tap('next');
      expect(miniMonth(tester).month, DateTime.utc(2027, 6));

      // Away and back with no new pick: June, as she left it.
      await showCalendar(robot);
      await showOverview(robot);
      expect(overview.chip('mode-month').selected, isTrue);
      expect(miniMonth(tester).month, DateTime.utc(2027, 6));

      // Left on May, a day of July picked on the grid: the Overview opens
      // on July — a month neither view was on — with the day picked.
      await overview.tap('previous');
      expect(miniMonth(tester).month, DateTime.utc(2027, 5));
      await showCalendar(robot);
      for (var i = 0; i < 2; i++) {
        await tester.tap(
          _inCard('screen', find.byIcon(Icons.chevron_right_rounded)),
        );
        await tester.pumpAndSettle();
      }
      final picked = DateTime.utc(2027, 7, 14);
      await _tapCell(tester, 'screen', picked);
      await showOverview(robot);
      expect(miniMonth(tester).month, DateTime.utc(2027, 7));
      expect(miniMonth(tester).selectedDay, picked);

      // In Year, a pick in another year moves the year.
      await overview.tap('mode-year');
      await showCalendar(robot);
      for (var i = 0; i < 6; i++) {
        await tester.tap(
          _inCard('screen', find.byIcon(Icons.chevron_right_rounded)),
        );
        await tester.pumpAndSettle();
      }
      final nextYear = DateTime.utc(2028, 1, 12);
      await _tapCell(tester, 'screen', nextYear);
      await showOverview(robot);
      expect(_navOf(tester).title, '2028');
      await expectNothingSaved();
    });

    testWidgets('no tap on the stage opens a page or a sheet: a grid day, a '
        'panel row, a timeline block, an upcoming row, a year tile, a '
        'month-grid day, a list row', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
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
      await robot.tapId(SemanticsIds.eventRow('guide-demo-yoga'));
      expectNothingOpened('a panel row');
      await robot.tapId(SemanticsIds.panelMode('timeline'));
      await tester.ensureVisible(
        find.descendant(
          of: find.byType(DayTimelineView),
          matching: find.text(yoga),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DayTimelineView),
          matching: find.text(yoga),
        ),
      );
      await tester.pumpAndSettle();
      expectNothingOpened('a timeline block');
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
      final upcoming = _inCard(
        'screen',
        find.descendant(
          of: find.byType(GuideDemoPanel),
          matching: find.text(yoga, findRichText: true),
        ),
      ).first;
      await tester.ensureVisible(upcoming);
      await tester.pumpAndSettle();
      await tester.tap(upcoming);
      await tester.pumpAndSettle();
      expectNothingOpened('an upcoming row');

      await showOverview(robot);
      final overview = overviewOf(tester);
      await overview.tap('mode-year');
      // This month's tile, in the row Year opens on; it opens this month.
      await _tapOnPage(
        tester,
        'screen',
        _yearTile(DateTime.utc(today.year, today.month)),
      );
      expectNothingOpened('a year tile');
      await _tapCell(tester, 'screen', DateTime.utc(today.year, today.month));
      expectNothingOpened('a month-grid day');
      await tester.drag(
        _inCard('screen', find.byType(CustomScrollView)),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        _inCard(
          'screen',
          find.text(en.calendarGuideDemoEventRent, findRichText: true),
        ).first,
      );
      await tester.pumpAndSettle();
      expectNothingOpened('a month row');
      // This month's list: the rent is on its first.
      await overview.tap('mode-list');
      await tester.tap(
        _inCard(
          'screen',
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

    Finder panelList() => find
        .descendant(
          of: find.byType(GuideDemoPanel),
          matching: find.byType(Scrollable),
        )
        .first;

    testWidgets('the panel\'s end hands a drag on to the page; a panel with '
        'more to show scrolls itself and not the page; a drag on the grid '
        'scrolls the page', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
      await tester.ensureVisible(find.byType(GuideDemoPanel));
      await tester.pumpAndSettle();
      final slot = tester.state<ScrollableState>(panelList()).position;
      final page = pageOf(tester);
      expect(page.pixels, greaterThan(100));
      expect(slot.pixels, 0);
      final start = tester.getCenter(panelList());

      // Up the panel: the list has more below, so it scrolls and the page
      // stays.
      var gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -kTouchSlop - 2));
      await tester.pump();
      final pageBefore = page.pixels;
      final slotBefore = slot.pixels;
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(slot.pixels, moreOrLessEquals(slotBefore + 30));
      expect(page.pixels, pageBefore);
      await gesture.up();
      await tester.pumpAndSettle();

      // Back to the panel's top, then on down: past its end the finger moves
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

      // The grid takes only taps and sideways swipes (D77): a vertical drag
      // there is the page's.
      final grid = tester.getCenter(
        _inCard('screen', find.byType(GuideCalendarGrid)),
      );
      final pageBeforeGrid = page.pixels;
      gesture = await tester.startGesture(grid);
      await gesture.moveBy(const Offset(0, kTouchSlop + 2));
      await tester.pump();
      final pageAtGrid = page.pixels;
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(page.pixels, moreOrLessEquals(pageAtGrid - 40));
      expect(page.pixels, lessThan(pageBeforeGrid));
      await gesture.up();
      await tester.pumpAndSettle();
      await expectNothingSaved();
    });

    testWidgets('the mini month: a swipe to half-way and back keeps its '
        'month and its grid', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      await showOverview(robot);
      final grid = _inCard(
        'screen',
        find.byWidgetPredicate((widget) => widget is TableCalendar),
      );
      await tester.ensureVisible(grid);
      await tester.pumpAndSettle();
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

      expect(miniMonth(tester).month, month);
      expect(identical(tester.element(grid), element), isTrue);
      await expectNothingSaved();
    });

    testWidgets('the mini month: the picked day tapped again lists the whole '
        'month, the shared day kept; again, the day', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      await showOverview(robot);
      expect(miniMonth(tester).selectedDay, today);

      await _tapCell(tester, 'screen', today);
      expect(miniMonth(tester).selectedDay, isNull);
      await showCalendar(robot);
      expect(dayPanel(tester).day, today);

      await showOverview(robot);
      expect(miniMonth(tester).selectedDay, isNull);
      await _tapCell(tester, 'screen', today);
      expect(miniMonth(tester).selectedDay, today);
      await expectNothingSaved();
    });

    testWidgets('a language change writes the demo again in it', (
      tester,
    ) async {
      await open(tester, CalendarGuideTopic.screen);
      final robot = await open(
        tester,
        CalendarGuideTopic.screen,
        locale: const Locale('de'),
      );
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
      // The dentist is two days out: down the panel's list until it is
      // built.
      final dentist = _inCard(
        'screen',
        find.text(
          AppLocalizationsDe().calendarGuideDemoEventDentist,
          findRichText: true,
        ),
      );
      final slot = tester.state<ScrollableState>(panelList()).position;
      for (var i = 0; i < 20 && dentist.evaluate().isEmpty; i++) {
        slot.jumpTo((slot.pixels + 100).clamp(0.0, slot.maxScrollExtent));
        await tester.pump();
      }
      expect(dentist, findsWidgets);
      expect(
        _inCard(
          'screen',
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
      // The change is the step, marked when the trip returns.
      expect(robot.line, steps[1]);
      await sheets.detailEdit();
      await sheets.typeTitle('Dentist at noon');
      await sheets.saveEditor();
      // The editor's Save returns to the detail sheet, as on the calendar.
      expect(sheets.detailOpen, isTrue);
      await sheets.detailClose();
      expect(robot.line, steps[2]);
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
      // The add, with the change already done: straight to delete.
      await robot.tap('add');
      await sheets.typeTitle('Swim');
      await sheets.saveEditor();
      expect(robot.line, steps[2]);
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
      final skipped = en.calendarGuideDemoSkipped(
        shortDates.format(today),
        en.calendarGuideDemoEventYoga,
      );
      expect(robot.line, skipped);

      // The next action restores an instruction once its trip returns:
      // opening is no step (D72), so the line asks for the first step.
      await robot.tap(rowId('dentist'));
      expect(robot.line, skipped, reason: 'under the sheet');
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
      expect(robot.line, steps[1], reason: 'opened, nothing done');
      await sheets.detailEdit();
      await sheets.typeTitle('Dentist at noon');
      await sheets.saveEditor();
      expect(sheets.detailOpen, isTrue);
      expect(robot.line, steps[1], reason: 'changed, not yet applied');
      expect(robot.shows('Dentist at noon'), isTrue, reason: 'the stage is');

      await sheets.detailClose();
      expect(robot.line, steps[2]);
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

    // The Date row's value.
    late final dayRowDates = DateFormat.yMMMEd('en');
    // A function: a semantics finder is made inside a test, where the tree
    // exists.
    Finder matrix() => _inCard('kinds', find.byType(MonthDotMatrix));

    /// Taps [day]'s square on the kinds card's month, the page scrolled
    /// only as far as the month needs.
    Future<void> tapSquare(GuideTryCardRobot robot, DateTime day) async {
      await robot.showOnPage(matrix());
      await _tapSquare(robot.tester, matrix(), day);
    }

    testWidgets('a tap on the month picks the day; Skip asks that the event '
        'falls on it', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      // Weekly on today's weekday: today has a dot, the day beside it none.
      await robot.tap('repeat');
      await robot.tapId(SemanticsIds.repeatKind('weekly'));
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.line, steps[1]);
      final bare = today.day > 1 ? day(-1) : day(1);
      expect(
        _matrixPainter(tester, matrix()).markedMask >> (bare.day - 1) & 1,
        0,
      );

      await tapSquare(robot, today);
      expect(robot.pickerRow('day').value, dayRowDates.format(today));
      expect(_matrixPainter(tester, matrix()).selectedIndex, today.day - 1);
      expect(
        _matrixPainter(tester, matrix()).selectedColor,
        AppTheme.light().colorScheme.onSurface,
      );
      expect(robot.enabled('skip'), isTrue);

      // The picked day tapped again stays picked.
      await tapSquare(robot, today);
      expect(robot.pickerRow('day').value, dayRowDates.format(today));
      expect(_matrixPainter(tester, matrix()).selectedIndex, today.day - 1);

      // Any day can be picked; Skip only for one the event falls on.
      await tapSquare(robot, bare);
      expect(robot.pickerRow('day').value, dayRowDates.format(bare));
      expect(_matrixPainter(tester, matrix()).selectedIndex, bare.day - 1);
      expect(robot.enabled('skip'), isFalse);

      await tapSquare(robot, today);
      await robot.tap('skip');
      expect(robot.line, steps[2]);
      expect(robot.pickerRow('day').value, isNull);
      final painter = _matrixPainter(tester, matrix());
      expect(painter.selectedIndex, isNull);
      expect(painter.missedMask >> (today.day - 1) & 1, 1);
      expect(robot.enabled('skip'), isFalse);

      // The Date row's picker stays the other way to the same pick.
      await robot.tap('day');
      await PracticeCalendarRobot(tester).pickInDatePicker(bare);
      expect(robot.pickerRow('day').value, dayRowDates.format(bare));
      expect(_matrixPainter(tester, matrix()).selectedIndex, bare.day - 1);
      await expectNothingSaved();
    });

    testWidgets('the Dentist wears the first visible category, never '
        'Other\'s grey', (tester) async {
      await open(tester, CalendarGuideTopic.kinds);
      final first = CalendarCategories.visible.first;
      final avatar = tester.widget<EventAvatar>(
        _inCard('kinds', find.byType(EventAvatar)).first,
      );

      expect(first.color, isNot(const Color(0xFF757575)));
      expect(avatar.color, first.color);
      expect(_matrixPainter(tester, matrix()).markedColor, first.color);
      await expectNothingSaved();
    });

    testWidgets('a relaunch onto the guide: the categories arriving after the '
        'first build recolour the Dentist', (tester) async {
      final categories = CalendarCategories.all;
      // A cold start: the cache is empty when the card first builds. The
      // teardown restores it even if the open throws, so a failure here
      // cannot cascade through every later case on an empty cache.
      addTearDown(() => CalendarCategories.updateCache(categories));
      CalendarCategories.updateCache(const []);
      final robot = await open(tester, CalendarGuideTopic.kinds);
      // The page has handed the service's categories to the card; with
      // the cache back, the avatar resolves the one it took.
      CalendarCategories.updateCache(categories);
      await tapSquare(robot, today);

      final avatar = tester.widget<EventAvatar>(
        _inCard('kinds', find.byType(EventAvatar)).first,
      );
      expect(avatar.color, CalendarCategories.visible.first.color);
      expect(avatar.color, isNot(CalendarCategories.fallback.color));
      expect(writes.statements, isEmpty);
    });

    testWidgets('the categories arriving keep the rule, the skips and the '
        'picked day', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      final demo = GuideKindsDemo();
      addTearDown(demo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: demo,
                builder: (context, _) => demo.buildStage(context),
              ),
            ),
          ),
        ),
      );
      final stageMatrix = find.byType(MonthDotMatrix);
      Future<void> tapControl(String name) async {
        await tester.tap(
          find.bySemanticsIdentifier(
            SemanticsIds.calendarGuideTryControl(GuideKindsDemo.slug, name),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tapControl('repeat');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.repeatKind('weekly')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.repeatDone));
      await tester.pumpAndSettle();
      await _tapSquare(tester, stageMatrix, today);
      await tapControl('skip');
      final bare = today.day > 1 ? day(-1) : day(1);
      await _tapSquare(tester, stageMatrix, bare);
      final before = _matrixPainter(tester, stageMatrix);

      final visible = CalendarCategories.visible;
      demo.adoptCategories([visible[1], visible[0]]);
      await tester.pumpAndSettle();

      final after = _matrixPainter(tester, stageMatrix);
      expect(after.markedColor, visible[1].color);
      expect(after.markedColor, isNot(before.markedColor));
      expect(after.markedMask, before.markedMask);
      expect(after.missedMask, before.missedMask);
      expect(after.missedMask >> (today.day - 1) & 1, 1);
      expect(after.selectedIndex, bare.day - 1);
      expect(
        find.text(
          RecurrenceFormatter.format(
            WeeklyRecurrence(weekdays: {today.weekday}),
            en,
            'en',
          ),
        ),
        findsWidgets,
      );
      expect(writes.statements, isEmpty);
    });

    testWidgets('the month she taps is three times the tiles\' size at '
        'least, and fits 360', (tester) async {
      expect(
        CalendarGuideStageMatrix.scaleFor(
          150,
          minScale: GuideMetrics.stageMatrixTapMinScale,
        ),
        GuideMetrics.stageMatrixTapMinScale,
      );
      expect(
        CalendarGuideStageMatrix.scaleFor(150),
        GuideMetrics.stageMatrixMinScale,
      );
      for (final scaler in const [TextScaler.noScaling, TextScaler.linear(2)]) {
        final robot = await open(
          tester,
          CalendarGuideTopic.kinds,
          size: const Size(360, 780),
          textScaler: scaler,
        );
        final stage = tester.widget<CalendarGuideStageMatrix>(
          _inCard('kinds', find.byType(CalendarGuideStageMatrix)),
        );
        expect(stage.minScale, GuideMetrics.stageMatrixTapMinScale);
        final rect = tester.getRect(matrix());
        expect(
          rect.width / MonthDotMatrix.width,
          greaterThanOrEqualTo(GuideMetrics.stageMatrixTapMinScale),
        );
        final stageRect = robot.stageRect;
        expect(
          rect.left,
          greaterThanOrEqualTo(stageRect.left),
          reason: '$scaler',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(stageRect.right),
          reason: '$scaler',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the finding card\'s month takes no tap and keeps the floor '
        'of two', (tester) async {
      await open(
        tester,
        CalendarGuideTopic.finding,
        now: fixedNowFor(CalendarGuideTopic.finding),
      );
      final stage = tester.widget<CalendarGuideStageMatrix>(
        _inCard('finding', find.byType(CalendarGuideStageMatrix)),
      );
      expect(stage.minScale, GuideMetrics.stageMatrixMinScale);
      expect(stage.matrix.onDayTap, isNull);
      expect(
        find.descendant(
          of: _inCard('finding', find.byType(MonthDotMatrix)),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
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

    /// The open menu's [name] item, for its words and whether it answers.
    PopupMenuItem<dynamic> menuItem(
      WidgetTester tester,
      GuideTryCardRobot robot,
      String name,
    ) => tester.widget<PopupMenuItem<dynamic>>(
      find.ancestor(
        of: robot.control(name),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
    );

    /// Row [index]'s one node: name, caption and state, in that order.
    String rowLabel(WidgetTester tester, GuideTryCardRobot robot, int index) =>
        tester.getSemantics(robot.control('row-$index')).label;

    Future<void> closeMenu(WidgetTester tester) async {
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
    }

    test('the delete step quotes the row menu\'s item as it reads, '
        'ellipsis and all', () {
      final step = [
        for (final card in CalendarGuideTopic.categories.cards) ...card.steps,
      ].singleWhere((step) => step.action == 'deleted');
      for (final l10n in <AppLocalizations>[en, AppLocalizationsDe()]) {
        expect(
          step.line(l10n),
          contains(l10n.categoryDeleteEllipsis),
          reason: l10n.localeName,
        );
      }
    });

    testWidgets('idle: three rows on the page\'s anatomy, the first step, the '
        'page\'s four items disabled where the page disables them', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final gym = en.eventCategoryGym;
      final club = en.calendarGuideDemoEventBookClub;
      final builtIn = [
        en.categoryEventCount(0),
        en.categoryCaptionBuiltIn,
      ].join(' · ');

      expect(robot.line, steps[0]);
      for (var i = 0; i < 3; i++) {
        expect(robot.control('row-$i'), findsOneWidget, reason: 'row-$i');
      }
      // The page's caption with no events: a built-in says so, hers counts.
      expect(rowLabel(tester, robot, 0), '$gym\n$builtIn');
      expect(rowLabel(tester, robot, 2), '$club\n${en.categoryEventCount(0)}');
      // A handle per row, drawn as the page draws it while reorder is on —
      // full strength, no drag listener, no name to promise a reorder.
      final handles = find.descendant(
        of: robot.control('row-0'),
        matching: find.byType(ReorderHandle),
      );
      expect(handles, findsOneWidget);
      expect(tester.widget<ReorderHandle>(handles).enabled, isTrue);
      expect(tester.widget<ReorderHandle>(handles).index, isNull);
      expect(
        find.descendant(
          of: robot.card,
          matching: find.byType(ReorderableDragStartListener),
        ),
        findsNothing,
      );
      expect(robot.control('archived'), findsNothing);
      // The unseen copy that sizes the list is not hit-testable.
      expect(
        find.byTooltip(en.categoryActions).hitTestable(),
        findsNWidgets(3),
      );

      // A built-in at the top: Move to top and Delete disabled in place.
      await robot.tap('more-0');
      expect(
        [
          for (final name in ['move-to-top', 'edit', 'archive', 'delete'])
            (menuItem(tester, robot, name).enabled, name),
        ],
        [
          (false, 'move-to-top'),
          (true, 'edit'),
          (true, 'archive'),
          (false, 'delete'),
        ],
      );
      for (final words in [
        en.moveToTop,
        en.edit,
        en.categoryArchive,
        en.categoryDeleteEllipsis,
      ]) {
        expect(find.text(words), findsOneWidget, reason: words);
      }
      await robot.tap('delete');
      // Still open, nothing deleted.
      expect(robot.control('edit'), findsOneWidget);
      await closeMenu(tester);
      expect(robot.control('row-0'), findsOneWidget);

      // Hers, at the bottom: every item answers.
      await robot.tap('more-2');
      for (final name in ['move-to-top', 'edit', 'archive', 'delete']) {
        expect(menuItem(tester, robot, name).enabled, isTrue, reason: name);
      }
      await closeMenu(tester);
      expect(robot.line, steps[0]);
      await expectNothingSaved();
    });

    testWidgets('a created row flashes once, as the page\'s does after its '
        'reveal (K20), and no other row does', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final sheet = CategoryEditorRobot(tester);
      bool flashing(int index) {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.ancestor(
                  of: robot.control('row-$index'),
                  matching: find.byType(ValueChangeHighlight),
                ),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).border != null;
      }

      await robot.tap('add');
      await sheet.typeName('Chess');
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.categoryEditorSave),
      );
      final seen = <int>{};
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (robot.control('row-3').evaluate().isEmpty) continue;
        for (var row = 0; row < 4; row++) {
          if (flashing(row)) seen.add(row);
        }
      }
      expect(seen, {3});
      await tester.pumpAndSettle();
      expect([
        for (var row = 0; row < 4; row++) flashing(row),
      ], everyElement(isFalse));
      await expectNothingSaved();
    });

    testWidgets('create, edit, archive, restore, move to top and delete — in '
        'this list only', (tester) async {
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

      // Archive moves the row under the Archived header, last.
      await robot.tap('more-0');
      await robot.tap('archive');
      expect(robot.line, steps[2]);
      expect(steps[1], contains(en.categoryArchive));
      expect(steps[2], contains(en.eventCategoryOther));
      expect(robot.control('archived'), findsOneWidget);
      expect(rowLabel(tester, robot, 3), startsWith('$gym\n'));
      expect(rowLabel(tester, robot, 3), endsWith(en.categoryRowArchived));
      expect(rowLabel(tester, robot, 0), isNot(startsWith('$gym\n')));
      final header = tester.getRect(robot.control('archived'));
      expect(
        header.top,
        greaterThan(tester.getRect(robot.control('row-2')).bottom),
      );
      expect(
        header.bottom,
        lessThanOrEqualTo(tester.getRect(robot.control('row-3')).top),
      );
      // Only the leading dims; the name keeps its role at full strength.
      final archivedRow = robot.control('row-3');
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.descendant(
                      of: archivedRow,
                      matching: find.byType(EventAvatar),
                    ),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        FormMetrics.disabledOpacity,
      );
      expect(
        find.ancestor(
          of: find.descendant(of: archivedRow, matching: find.text(gym)),
          matching: find.descendant(
            of: archivedRow,
            matching: find.byType(Opacity),
          ),
        ),
        findsNothing,
      );
      note(robot);

      // Restore brings it back to its slot, and the header goes.
      await robot.tap('more-3');
      expect(find.text(en.categoryRestore), findsOneWidget);
      await robot.tap('archive');
      expect(robot.line, steps[2]);
      expect(robot.control('archived'), findsNothing);
      expect(rowLabel(tester, robot, 0), startsWith('$gym\n'));

      // Move to top, in memory.
      await robot.tap('more-2');
      await robot.tap('move-to-top');
      expect(rowLabel(tester, robot, 0), startsWith('Reading\n'));
      expect(rowLabel(tester, robot, 1), startsWith('$gym\n'));
      expect(robot.line, steps[2]);

      await robot.tap('more-1');
      await robot.tap('edit');
      expect(find.byType(CategoryEditorSheet), findsOneWidget);
      await sheet.save();
      expect(robot.line, steps[2]);

      await robot.tap('more-0');
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

    testWidgets('the last category in use cannot be archived; Move to top '
        'stays within the Archived section', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final stage = robot.stageSize;
      final gym = en.eventCategoryGym;

      // Archive both built-ins: hers is the one left in use.
      await robot.tap('more-0');
      await robot.tap('archive');
      await robot.tap('more-0');
      await robot.tap('archive');
      expect(
        rowLabel(tester, robot, 0),
        startsWith('${en.calendarGuideDemoEventBookClub}\n'),
      );
      // The seed's three rows and the header fit the list's box whole.
      expect(
        tester.getRect(robot.control('row-2')).bottom,
        lessThanOrEqualTo(tester.getRect(robot.control('add')).top),
      );
      await robot.tap('more-0');
      expect(menuItem(tester, robot, 'archive').enabled, isFalse);
      expect(menuItem(tester, robot, 'move-to-top').enabled, isFalse);
      await closeMenu(tester);

      // The archived keep their slots: the first built-in first.
      expect(rowLabel(tester, robot, 1), startsWith('$gym\n'));
      await robot.tap('more-1');
      expect(menuItem(tester, robot, 'move-to-top').enabled, isFalse);
      await closeMenu(tester);
      await robot.tap('more-2');
      expect(menuItem(tester, robot, 'move-to-top').enabled, isTrue);
      await robot.tap('move-to-top');
      expect(rowLabel(tester, robot, 2), startsWith('$gym\n'));
      expect(
        rowLabel(tester, robot, 0),
        startsWith('${en.calendarGuideDemoEventBookClub}\n'),
      );
      expect(robot.stageSize, stage);
      await expectNothingSaved();
    });

    // The composed captions and the Archived header at the longest words:
    // nothing overflows, the stage keeps its height, the coach its slot.
    testWidgets('de 2.0 on 360: archive and restore move nothing and '
        'overflow nothing', (tester) async {
      final de = AppLocalizationsDe();
      final robot = await open(
        tester,
        CalendarGuideTopic.categories,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final stage = robot.stageSize;
      final slot = robot.slotSize;
      expect(tester.takeException(), isNull);

      await robot.tap('more-2');
      await robot.tap('archive');
      expect(tester.takeException(), isNull);
      expect(robot.control('archived'), findsOneWidget);
      expect(
        find.descendant(
          of: robot.control('archived'),
          matching: find.text(de.categorySectionArchived.toUpperCase()),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(robot.control('row-2')).bottom,
        lessThanOrEqualTo(tester.getRect(robot.control('add')).top),
      );
      expect(robot.slotSize, slot);

      await robot.tap('more-2');
      await robot.tap('archive');
      expect(tester.takeException(), isNull);
      expect(robot.control('archived'), findsNothing);
      expect(robot.stageSize, stage);
      expect(robot.slotSize, slot);
      // The caption's column is the categories page's on the same phone:
      // the page's 16 dp side insets are the stage's card edges here.
      final caption = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: robot.control('row-0'),
              matching: find.byType(RichText),
            )
            .last,
      );
      expect(
        caption.constraints.maxWidth,
        360 -
            2 * RowMetrics.groupInset -
            RowMetrics.reorderGlyphTextInset -
            kMinInteractiveDimension,
      );
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
      final robot = await open(
        tester,
        CalendarGuideTopic.finding,
        now: fixedNowFor(CalendarGuideTopic.finding),
      );

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
          if (element.renderObject case final RenderBox box when !_unseen(box))
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
      expect(
        chipTop - math.max(firstRowTop, viewport.top),
        greaterThanOrEqualTo(2 * rowHeight),
      );
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

    testWidgets('Your practice opens the real schedule sheet: a weekday '
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
    testWidgets('a day skipped in Your practice loses its wash and its row; a '
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

    Future<GuideTryCardRobot> openTall(WidgetTester tester) => open(
      tester,
      CalendarGuideTopic.screen,
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScaler: const TextScaler.linear(2.0),
    );

    testWidgets('screen: every format and six pages of months', (tester) async {
      final robot = await openTall(tester);
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

    testWidgets('screen: every panel mode', (tester) async {
      final robot = await openTall(tester);
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

    testWidgets('screen: the Overview\'s every mode, a step, today and a '
        'tile', (tester) async {
      final robot = await openTall(tester);
      final stage = robot.stageSize;
      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarOverviewOpen);
      expect(robot.stageSize, stage, reason: 'the Overview');
      final overview = GuideTryCardRobot(tester, 'overview');
      for (final control in const [
        'mode-month',
        'next',
        'mode-list',
        'previous',
        'mode-year',
        'next',
        'today',
      ]) {
        await overview.tap(control);
        expect(robot.stageSize, stage, reason: control);
      }
      await _tapOnPage(
        tester,
        'screen',
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

          await _eachChange(tester, robot, topic, (state) async {
            note(robot);
            expect(offset(), gap, reason: state);
          });
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
    // The screen stage's views: the real widgets keep their own ids, the
    // card's additions are `try-*` — the Overview's the overview card's
    // (D86); a disabled control is a node all the same, with no tap; each
    // view's body is a container of its own.
    String screenControl(String slug, String control) =>
        SemanticsIds.calendarGuideTryControl(slug, control);
    const slug = 'screen';
    for (final (view, live, disabled) in [
      (
        CalendarViewPage.calendar,
        [
          SemanticsIds.calendarViewMenu,
          screenControl(slug, 'more'),
          SemanticsIds.panelMode('day'),
          SemanticsIds.panelMode('timeline'),
          SemanticsIds.panelMode('upcoming'),
        ],
        [screenControl(slug, 'saved-filters'), screenControl(slug, 'filter')],
      ),
      (
        CalendarViewPage.overview,
        [
          SemanticsIds.calendarViewMenu,
          screenControl(slug, 'more'),
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
          screenControl(slug, 'overview-options'),
          screenControl(slug, 'overview-views'),
          screenControl('overview', 'search'),
          screenControl('overview', 'today'),
        ],
      ),
    ]) {
      testWidgets('screen: ${view.name}', (tester) async {
        final handle = tester.ensureSemantics();
        final robot = await open(tester, CalendarGuideTopic.screen);
        if (view == CalendarViewPage.overview) {
          await robot.tapId(SemanticsIds.calendarViewMenu);
          await robot.tapId(SemanticsIds.calendarOverviewOpen);
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
          ...live,
          ...disabled,
          SemanticsIds.calendarGuideTrySkip(slug),
          SemanticsIds.calendarGuideTryCaption(slug),
          SemanticsIds.calendarGuideScreenView(view.name),
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
        // One view's container at a time; the ⋮'s one id in each (D86).
        for (final other in CalendarViewPage.values) {
          if (other == view) continue;
          expect(
            find.bySemanticsIdentifier(
              SemanticsIds.calendarGuideScreenView(other.name),
            ),
            findsNothing,
            reason: other.name,
          );
        }
        expect(
          find.bySemanticsIdentifier(screenControl(slug, 'more')),
          findsOneWidget,
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
      (CalendarGuideTopic.categories, ['row-0', 'more-0', 'row-2', 'add']),
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

  /// Every card of every page, the screen page's one stage included.
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
                // The Upcoming body's rows are the overview's row builder on
                // `FormPickerRow`, whose caption is capped (two lines by the
                // row's default) and ellipsised past the cap by design, as on
                // the real Upcoming panel; a row's height never follows its
                // text. At ro 2.0 on 360 the weekly schedule caption needs a
                // third line on the days whose abbreviation is widest
                // ("Săptămânal · sâm. · 18:00 – 19:00" on a Saturday), so the
                // exceed there reports the cap, not a clipped label.
                final rowCaptions = <RenderParagraph>{
                  for (final paragraph
                      in tester.renderObjectList<RenderParagraph>(
                        find.descendant(
                          of: find.descendant(
                            of: find.byType(GuideDemoPanel),
                            matching: find.byType(FormPickerRow),
                          ),
                          matching: find.byType(RichText),
                        ),
                      ))
                    if (paragraph.maxLines != null) paragraph,
                };
                // The Overview's List title in the screen stage, a span
                // ("1. Nov. – 30. Nov. 2026"), needs a third line at de 2.0
                // in the stage's 328 dp on 360; the period nav ellipsises
                // past its two lines by design
                // (`FormMetrics.periodTitleMaxLines`). That title, in that
                // state, and nothing else.
                final listTitle = <RenderParagraph>{
                  if (state == 'list')
                    ...tester.renderObjectList<RenderParagraph>(
                      find.descendant(
                        of: find.byType(AgendaPeriodNav),
                        matching: find.text(_navOf(tester).title),
                      ),
                    ),
                };
                for (final paragraph in paragraphs) {
                  if (unseen(paragraph) ||
                      tileLabels.contains(paragraph) ||
                      panelLabels.contains(paragraph) ||
                      rowCaptions.contains(paragraph) ||
                      listTitle.contains(paragraph)) {
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
              // What she does first on the card; on the screen stage, each
              // view and format.
              await _eachChange(tester, robot, topic, expectClean);
              await expectNothingSaved();
            });
          }
        }
      }
    }
  });

  // Every card idle and on its closing line — the screen stage in each of its
  // changed views and formats ([_eachChange]) between — on both phones in
  // both themes:
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
                .ancestor(
                  of: robot.card,
                  matching: find.byType(SettingsSectionCard),
                )
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
            if (topic == CalendarGuideTopic.screen) {
              await _eachChange(tester, robot, topic, meetsBoth);
            }
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
  for (final (size, what) in const [
    (Size(360, 780), 'the screen stage\'s day cells at 360'),
    // Labelled, where they fit: on 360 they are 48 dp icons.
    (Size(412, 915), 'the screen stage\'s mode segments at 412'),
  ]) {
    testWidgets('the tap-target exceptions: $what', (tester) async {
      final handle = tester.ensureSemantics();
      final robot = await open(tester, CalendarGuideTopic.screen, size: size);
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
    // The one word no stage can hold at de 2.0, even edge to edge in the
    // card, 328 dp on a 360 phone: "Wiederholungen" beside the count's
    // switch is wider than the 182 dp its label keeps (the editor's
    // full-width sheet gives it 32 dp more). "Kalender-Einstellungen" breaks
    // at its hyphen, so the setup card holds it since the settings rework's
    // S2 review. The screen
    // page's cards are the card's cost too, not the widgets': edge to edge
    // in the card they are still 40 dp narrower than the screen, so the
    // weekday row's "Mon" needs 49.5 dp of its column and gets 45.7 ("Wed"
    // the same, and Romanian's "mar.", "mie.", "sâm.", "dum.") under both
    // grids — the Calendar's in Month and Week and the Overview's mini month
    // (it opens on Month, D68). (A
    // Day panel row's "Wöchentlich" broke there too while the inert rows
    // drew a chevron; without it the caption fits, D69.)
    // Pinned per state where they differ, so any other break fails.
    const unavoidable = {
      'attendance de 2.0': ['Wiederholungen'],
      'screen en 2.0': ['Mon', 'Wed'],
      // Year's tiles and List's rows draw no weekday row.
      'screen en 2.0 year': <String>[],
      'screen en 2.0 list': <String>[],
      // The fasting card's grid, the screen card's cost again.
      'fasting en 2.0': ['Mon', 'Wed'],
      'screen ro 2.0': ['mar.', 'mie.', 'sâm.', 'dum.'],
      'screen ro 2.0 year': <String>[],
      'screen ro 2.0 list': <String>[],
      'fasting ro 2.0': ['mar.', 'mie.', 'sâm.', 'dum.'],
    };
    for (final (locale, scale) in const [
      (Locale('de'), 2.0),
      (Locale('de'), 1.3),
      (Locale('en'), 2.0),
      (Locale('ro'), 2.0),
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
          await _eachChange(tester, robot, topic, expectWholeWords);
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

/// [matching] inside the card [slug] — the fasting card draws a grid as the
/// screen stage does.
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

/// The screen stage's Overview's period nav.
AgendaPeriodNav _navOf(WidgetTester tester) =>
    tester.widget(_inCard('screen', find.byType(AgendaPeriodNav)));

/// The screen stage's Overview's year tile for [month], by the label it
/// draws.
Finder _yearTile(DateTime month, {String locale = 'en'}) => _inCard(
  'screen',
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
Future<void> _tapOnPage(WidgetTester tester, String slug, Finder target) async {
  await GuideTryCardRobot(tester, slug).showOnPage(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Taps [day]'s square on [matrix] where it stands: the squares carry no
/// semantics (D98), so the tap goes to the point the square is drawn at.
Future<void> _tapSquare(
  WidgetTester tester,
  Finder matrix,
  DateTime day,
) async {
  final widget = tester.widget<MonthDotMatrix>(matrix);
  final rect = tester.getRect(matrix);
  final scale = rect.width / MonthDotMatrix.width;
  final slot = widget.firstWeekdayColumn + day.day - 1;
  const pitch = MonthDotMatrix.cellSize + MonthDotMatrix.gap;
  const half = MonthDotMatrix.cellSize / 2;
  await tester.tapAt(
    rect.topLeft +
        Offset(
              slot % MonthDotMatrix.columns * pitch + half,
              slot ~/ MonthDotMatrix.columns * pitch + half,
            ) *
            scale,
  );
  await tester.pumpAndSettle();
}

/// [matrix]'s painter, for the day it rings and the colours it paints.
MonthDotMatrixPainter _matrixPainter(WidgetTester tester, Finder matrix) =>
    tester
            .widget<CustomPaint>(
              find.descendant(of: matrix, matching: find.byType(CustomPaint)),
            )
            .painter!
        as MonthDotMatrixPainter;

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

/// What she would do first on [topic]'s card, [check]ed after each state it
/// leaves — `changed` — and on the screen stage every view and format the
/// three cards it replaced were checked in: the Calendar in Week over
/// Upcoming (`week`), then the Overview as it opens, in Month (`month`), in
/// Year (`year`) and in List (`list`). Elsewhere: the quick alarm (the
/// events and alerts cards'
/// report), a rule, a mark, a category, a query, a holiday set.
Future<void> _eachChange(
  WidgetTester tester,
  GuideTryCardRobot robot,
  CalendarGuideTopic topic,
  Future<void> Function(String state) check,
) async {
  switch (topic) {
    case CalendarGuideTopic.screen:
      final overview = GuideTryCardRobot(tester, 'overview');
      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarFormatWeek);
      await robot.tapId(SemanticsIds.panelMode('upcoming'));
      await check('week');
      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarOverviewOpen);
      await check('month');
      await overview.tap('mode-year');
      await check('year');
      await overview.tap('mode-list');
      await check('list');
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
  if (topic != CalendarGuideTopic.screen) await check('changed');
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
