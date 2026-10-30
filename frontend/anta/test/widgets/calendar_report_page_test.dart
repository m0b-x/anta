import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/calendar_report/calendar_report_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/report_trend_chart.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/report_robot.dart';

/// The report page over a loaded calendar: its bar, its band and Period
/// menu, the Totals card per the selection (D15) and the tense (T), the
/// caption, the footer, and §4.8's geometry, measured with Roboto loaded.
void main() {
  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;
  late SettingsService settings;
  late CalendarReportService service;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadGoldenFonts();
  });

  /// The page's clock: no case reads the wall clock.
  DateTime clock() => DateTime(2026, 10, 30, 10);
  final today = EventAgenda.dateOnly(clock());

  /// What a fold waits on: the next frame, or while a case holds it, [gate].
  Completer<void>? gate;
  Future<void> nextFrame() =>
      gate?.future ?? SchedulerBinding.instance.endOfFrame;

  /// A tracked, timed daily routine since the start of 2026: Events,
  /// Attended, Missed and Hours.
  final gym = CalendarEvent(
    id: 'e-gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    tracksPresence: true,
  );

  /// An untimed to-do with three task items, one ticked: Tasks.
  final todo = CalendarEvent(
    id: 'e-todo',
    title: 'Tax form',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 3, 10),
    rule: const OneTimeRecurrence(),
    description: '- [x] one\n- [ ] two\n- [ ] three',
  );

  const march = OverviewMonthPeriod(2026, 3);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    gate = null;
    final notes = NoteRepository(database: db);
    importExport = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: db),
        ),
        noteRepository: notes,
      ),
    );
    CalendarCategories.updateCache([
      for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: seed.kind.name,
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: index,
          isBuiltIn: true,
        ),
    ]);
    // One missed gym day in March.
    EventPresence.updateCache(
      byEvent: {
        gym.id: {DateTime.utc(2026, 3, 5): PresenceStatus.missed},
      },
    );
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: [gym, todo],
        focusedDay: today,
        selectedDay: today,
      ),
    );
    service = CalendarReportService();
  });

  tearDown(() async {
    await bloc.close();
    await importExport.close();
    EventPresence.resetCache();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    await db.close();
  });

  /// Opens the page on [period] and [categoryIds] as the overview's look,
  /// or with [plain] as the calendar and a relaunch open it — on what the
  /// report remembers.
  Future<ReportRobot> open(
    WidgetTester tester, {
    OverviewPeriod period = march,
    Set<String> categoryIds = const {},
    bool plain = false,
    DateTime Function()? at,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface = const Size(360, 780),
    Brightness brightness = Brightness.light,
    EdgeInsets viewPadding = EdgeInsets.zero,
  }) async {
    final robot = ReportRobot(tester);
    await robot.open(
      bloc: bloc,
      importExport: importExport,
      service: service,
      clock: at ?? clock,
      nextFrame: nextFrame,
      look: plain ? null : (period: period, categoryIds: categoryIds),
      locale: locale,
      textScale: textScale,
      surface: surface,
      brightness: brightness,
      viewPadding: viewPadding,
    );
    expect(robot.isReady, isTrue);
    return robot;
  }

  group('bar', () {
    testWidgets('the view menu, the Categories button and the ⋮ by id, on a '
        '48 dp bar', (tester) async {
      final robot = await open(tester);
      expect(robot.byId(SemanticsIds.calendarViewMenu), findsOneWidget);
      expect(robot.byId(SemanticsIds.reportCategoriesOpen), findsOneWidget);
      expect(robot.byId(SemanticsIds.reportMore), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppBar)).height,
        AppBarMetrics.toolbarHeight,
      );
      final button = tester.getSize(
        robot.byId(SemanticsIds.reportCategoriesOpen),
      );
      expect(button.width, closeTo(48, 1));
      expect(button.height, closeTo(48, 1));

      await tester.tap(robot.byId(SemanticsIds.calendarViewMenu));
      await tester.pumpAndSettle();
      expect(robot.byId(SemanticsIds.calendarReportOpen), findsOneWidget);
    });

    testWidgets('the badge counts the categories while narrowed, and shows '
        'nothing when every category is in scope', (tester) async {
      var robot = await open(tester, categoryIds: {'gym'});
      expect(robot.categoriesBadge.isLabelVisible, isTrue);
      expect((robot.categoriesBadge.label! as Text).data, '1');
      await tester.pumpWidget(const SizedBox.shrink());

      robot = await open(tester);
      expect(robot.categoriesBadge.isLabelVisible, isFalse);
    });
  });

  group('Period menu', () {
    testWidgets('lists the ten rows by id, no All time', (tester) async {
      final robot = await open(tester);
      await robot.openPeriodMenu();
      for (final id in [
        SemanticsIds.reportPeriodThisWeek,
        SemanticsIds.reportPeriodLastWeek,
        SemanticsIds.reportPeriodNextWeek,
        SemanticsIds.reportPeriodThisMonth,
        SemanticsIds.reportPeriodLastMonth,
        SemanticsIds.reportPeriodNextMonth,
        SemanticsIds.reportPeriodThisYear,
        SemanticsIds.reportPeriodLast12Months,
        SemanticsIds.reportPeriodLast90Days,
        SemanticsIds.reportPeriodCustom,
      ]) {
        expect(robot.byId(id), findsOneWidget, reason: id);
      }
      expect(find.byType(FormMenuItemRow), findsNWidgets(10));
      await robot.closeMenu();
    });

    testWidgets('checks This week, then Last week, and Custom for a span', (
      tester,
    ) async {
      final robot = await open(
        tester,
        period: OverviewPeriod.thisWeek(
          today: today,
          weekStart: CalendarWeekStart.monday,
        ),
      );
      await robot.openPeriodMenu();
      expect(robot.checkedPeriodId, SemanticsIds.reportPeriodThisWeek);
      await robot.pickPeriod(SemanticsIds.reportPeriodLastWeek);
      await robot.openPeriodMenu();
      expect(robot.checkedPeriodId, SemanticsIds.reportPeriodLastWeek);
      await robot.closeMenu();
      // A step back from last week is no row of the menu.
      await tester.tap(robot.byId(SemanticsIds.reportNavPrevious));
      await tester.pumpAndSettle();
      await robot.openPeriodMenu();
      expect(robot.checkedPeriodId, SemanticsIds.reportPeriodCustom);
      await robot.closeMenu();
    });

    testWidgets('a custom span checks Custom', (tester) async {
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 3, 3),
          DateTime.utc(2026, 3, 17),
        ),
      );
      await robot.openPeriodMenu();
      expect(robot.checkedPeriodId, SemanticsIds.reportPeriodCustom);
      await robot.closeMenu();
    });
  });

  group('Totals', () {
    testWidgets('a past month over every category draws the five tiles '
        '(D15) and the caption', (tester) async {
      final robot = await open(tester);
      expect(robot.tiles, [
        ReportTile.events,
        ReportTile.attended,
        ReportTile.missed,
        ReportTile.hours,
        ReportTile.tasks,
      ]);
      expect(
        robot.caption,
        'To ${DateFormat.MMMMd('en').format(DateTime.utc(2026, 3, 31))}'
        ' · against February 2026',
      );
      expect(robot.nav.title, 'March 2026');
      expect(robot.nav.subtitle, '31 events · 1 missed');
    });

    testWidgets('the Attended tile speaks its value, share and change', (
      tester,
    ) async {
      final robot = await open(tester);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(robot.tile(ReportTile.attended)).label,
        'Attended, 30 of 31, 97 percent, 2 more than February 2026',
      );
      handle.dispose();
    });

    testWidgets('an untimed to-do category has no Hours tile', (tester) async {
      final robot = await open(tester, categoryIds: {'other'});
      expect(robot.tiles, [ReportTile.events, ReportTile.tasks]);
    });

    testWidgets('a future month reads as a plan: Planned · Hours · Tasks, '
        'no caption', (tester) async {
      final robot = await open(
        tester,
        period: OverviewMonthPeriod(today.year + 1, 3),
      );
      expect(robot.tiles, [
        ReportTile.planned,
        ReportTile.hours,
        ReportTile.tasks,
      ]);
      expect(robot.caption, isNull);
      expect(robot.nav.subtitle, '31 planned · 31 h');
    });

    testWidgets('an empty period says so and mutes its values', (tester) async {
      final robot = await open(
        tester,
        period: const OverviewMonthPeriod(2025, 6),
      );
      expect(
        robot.caption,
        'June 2025${ReportLabels.separator}Nothing happened',
      );
      expect(robot.footerRow(SemanticsIds.reportShare).onTap, isNull);
    });
  });

  group('footer', () {
    testWidgets('three rows by id; Share and Send disabled, Send monthly on a '
        'month', (tester) async {
      final robot = await open(tester);
      expect(robot.footerRow(SemanticsIds.reportShowList).onTap, isNotNull);
      expect(robot.footerRow(SemanticsIds.reportShare).onTap, isNull);
      final send = robot.footerRow(SemanticsIds.reportSend);
      expect(send.onTap, isNull);
      expect(send.label, 'Send me this report monthly');
    });

    testWidgets('Send reads weekly on a week', (tester) async {
      final robot = await open(
        tester,
        period: OverviewWeekPeriod(DateTime.utc(2026, 3, 2)),
      );
      expect(
        robot.footerRow(SemanticsIds.reportSend).label,
        'Send me this report weekly',
      );
    });
  });

  group('geometry', () {
    testWidgets('en 1.0 at 360: two columns, tiles of 98, a five-tile card '
        'of 296', (tester) async {
      final robot = await open(tester);
      final events = robot.tileRect(ReportTile.events);
      final attended = robot.tileRect(ReportTile.attended);
      expect(events.height, closeTo(98, 1));
      expect(attended.top, events.top, reason: 'two columns');
      expect(
        robot.tileRect(ReportTile.tasks).width,
        closeTo(robot.totalsRect.width, 1),
        reason: 'the odd last tile takes the full width',
      );
      expect(robot.totalsRect.height, closeTo(296, 1));
    });

    testWidgets('en 1.3: tiles of 118', (tester) async {
      final robot = await open(tester, textScale: 1.3);
      expect(robot.tileRect(ReportTile.events).height, closeTo(118, 1));
    });

    testWidgets('de 1.3 at 360: one column', (tester) async {
      final robot = await open(
        tester,
        locale: const Locale('de'),
        textScale: 1.3,
      );
      final events = robot.tileRect(ReportTile.events);
      final attended = robot.tileRect(ReportTile.attended);
      expect(attended.top, greaterThan(events.top));
      expect(events.width, closeTo(robot.totalsRect.width, 1));
    });

    testWidgets('2.0 at 360: one column, tiles of 168', (tester) async {
      final robot = await open(tester, textScale: 2.0);
      final events = robot.tileRect(ReportTile.events);
      expect(events.height, closeTo(168, 1));
      expect(events.width, closeTo(robot.totalsRect.width, 1));
    });

    testWidgets('de at 2.0 on 360 × 780 lays out with no exception', (
      tester,
    ) async {
      await open(tester, locale: const Locale('de'), textScale: 2.0);
      expect(tester.takeException(), isNull);
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      )) {
        expect(paragraph.debugHasOverflowShader, isFalse);
      }
    });

    testWidgets('dark theme draws the same card', (tester) async {
      final robot = await open(tester, brightness: Brightness.dark);
      expect(robot.totalsRect.height, closeTo(296, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the body pads its bottom by bodyBottom and the larger inset', (
      tester,
    ) async {
      final robot = await open(
        tester,
        viewPadding: const EdgeInsets.only(bottom: 24),
      );
      expect(robot.bodyPadding.bottom, FormMetrics.bodyBottom + 24);

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(robot.bodyPadding.bottom, FormMetrics.bodyBottom + 320);
    });

    testWidgets('one Scrollable on the page', (tester) async {
      await open(tester);
      expect(find.byType(Scrollable), findsOneWidget);
    });
  });

  group('Totals columns (D37)', () {
    /// The tile's value line and detail line as drawn.
    ({String value, String detail}) linesOf(
      WidgetTester tester,
      ReportRobot robot,
      ReportTile tile,
    ) {
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: robot.tile(tile), matching: find.byType(Text)),
          )
          .toList();
      return (value: texts[1].textSpan!.toPlainText(), detail: texts[2].data!);
    }

    String spoken(WidgetTester tester, ReportRobot robot) {
      final handle = tester.ensureSemantics();
      final label = tester.getSemantics(robot.tile(ReportTile.attended)).label;
      handle.dispose();
      return label;
    }

    testWidgets('en 1.0, stage 1: two columns, "of" in the value', (
      tester,
    ) async {
      final robot = await open(tester);
      expect(
        robot.tileRect(ReportTile.attended).top,
        robot.tileRect(ReportTile.events).top,
      );
      final lines = linesOf(tester, robot, ReportTile.attended);
      expect(lines.value, '30 of 31');
      expect(lines.detail, startsWith('97 %'));
      expect(robot.totalsRect.height, closeTo(296, 1));
    });

    for (final (name, locale, scale, of) in [
      ('de 1.0', const Locale('de'), 1.0, 'von 31'),
      ('en 1.3', const Locale('en'), 1.3, 'of 31'),
    ]) {
      testWidgets('$name, stage 2: two columns, the bare figure, "of" '
          'leading the detail, the same spoken label', (tester) async {
        final robot = await open(tester, locale: locale, textScale: scale);
        expect(
          robot.tileRect(ReportTile.attended).top,
          robot.tileRect(ReportTile.events).top,
          reason: 'two columns',
        );
        final attended = linesOf(tester, robot, ReportTile.attended);
        expect(attended.value, '30');
        expect(attended.detail, startsWith('$of${ReportLabels.separator}'));
        final tasks = linesOf(tester, robot, ReportTile.tasks);
        expect(tasks.value, '1');
        expect(
          tasks.detail,
          startsWith(locale.languageCode == 'de' ? 'von 3' : 'of 3'),
        );
        final label = spoken(tester, robot);
        expect(
          label,
          contains(locale.languageCode == 'de' ? '30 von 31' : '30 of 31'),
        );
      });
    }

    testWidgets('the spoken label is the same in stage 1 and stage 2', (
      tester,
    ) async {
      var robot = await open(tester);
      final stage1 = spoken(tester, robot);
      await tester.pumpWidget(const SizedBox.shrink());
      robot = await open(tester, textScale: 1.3);
      expect(spoken(tester, robot), stage1);
    });

    testWidgets('de 1.0: the five-tile card keeps 296 in stage 2', (
      tester,
    ) async {
      final robot = await open(tester, locale: const Locale('de'));
      expect(robot.tileRect(ReportTile.events).height, closeTo(98, 1));
      expect(robot.totalsRect.height, closeTo(296, 1));
    });

    testWidgets('de 1.3, stage 3: the hours template does not fit, one '
        'column with the full value', (tester) async {
      final robot = await open(
        tester,
        locale: const Locale('de'),
        textScale: 1.3,
      );
      expect(
        robot.tileRect(ReportTile.attended).top,
        greaterThan(robot.tileRect(ReportTile.events).top),
      );
      expect(linesOf(tester, robot, ReportTile.attended).value, '30 von 31');
    });

    testWidgets('2.0, stage 3: one column with the full value', (tester) async {
      final robot = await open(tester, textScale: 2.0);
      expect(
        robot.tileRect(ReportTile.events).width,
        closeTo(robot.totalsRect.width, 1),
      );
      expect(linesOf(tester, robot, ReportTile.attended).value, '30 of 31');
    });
  });

  group('Over time', () {
    final thisWeek =
        OverviewPeriod.thisWeek(
              today: today,
              weekStart: CalendarWeekStart.monday,
            )
            as OverviewWeekPeriod;
    DateTime weeksFrom(int weeks) => DateTime.utc(
      thisWeek.start.year,
      thisWeek.start.month,
      thisWeek.start.day + 7 * weeks,
    );
    Finder chart() => find.byType(ReportTrendChart);

    testWidgets('a past month draws the chart under its OVER TIME label, '
        'between the Totals caption and the footer', (tester) async {
      final robot = await open(tester);
      expect(chart(), findsOneWidget);
      expect(find.text('OVER TIME'), findsOneWidget);
      final label = tester.getRect(find.text('OVER TIME'));
      expect(label.top, greaterThan(robot.totalsRect.bottom));
      expect(tester.getRect(chart()).top, greaterThan(label.bottom));
      await tester.scrollUntilVisible(
        robot.byId(SemanticsIds.reportShowList),
        200,
      );
      expect(
        tester.getRect(robot.byId(SemanticsIds.reportShowList)).top,
        greaterThan(tester.getRect(chart()).bottom),
      );
      expect(find.byType(Scrollable), findsOneWidget);
    });

    testWidgets('last week draws the chart, one column per day', (
      tester,
    ) async {
      await open(tester, period: OverviewWeekPeriod(weeksFrom(-1)));
      expect(chart(), findsOneWidget);
      final trend = tester.widget<ReportTrendChart>(chart()).trend;
      expect(trend.unit, ReportTrendUnit.day);
      expect(trend.buckets, hasLength(DateTime.daysPerWeek));
    });

    testWidgets('next week is a plan: no chart, no label', (tester) async {
      await open(tester, period: OverviewWeekPeriod(weeksFrom(1)));
      expect(chart(), findsNothing);
      expect(find.text('OVER TIME'), findsNothing);
    });

    testWidgets('under four happened occurrences there is no chart', (
      tester,
    ) async {
      // The to-do category holds one occurrence in March.
      await open(tester, categoryIds: {'other'});
      expect(chart(), findsNothing);
      expect(find.text('OVER TIME'), findsNothing);
    });

    testWidgets('the chart folds nothing through frames', (tester) async {
      await open(tester);
      expect(chart(), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(service.foldCount, 1);
    });

    testWidgets('German at 2.0 and the dark theme lay the chart out', (
      tester,
    ) async {
      await open(tester, locale: const Locale('de'), textScale: 2.0);
      // Below the fold at 2.0: the sliver is built once scrolled to.
      await tester.scrollUntilVisible(chart(), 200);
      expect(chart(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(service.foldCount, 1, reason: 'a scroll folds nothing');
      await tester.pumpWidget(const SizedBox.shrink());

      await open(tester, brightness: Brightness.dark);
      expect(chart(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('opening', () {
    testWidgets('a plain open with nothing stored is This month', (
      tester,
    ) async {
      final robot = await open(tester, plain: true);
      expect(robot.nav.title, 'October 2026');
      expect((robot.state as ReportReady).categoryIds, isEmpty);
    });

    testWidgets('a plain open reads the stored period and categories', (
      tester,
    ) async {
      await settings.setCalendarReportPeriod(
        const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
        today: today,
      );
      await settings.setCalendarReportCategories({'gym'});
      final robot = await open(tester, plain: true);
      expect(robot.nav.title, robot.l10n.overviewPeriodLast90Days);
      expect((robot.state as ReportReady).categoryIds, {'gym'});
    });

    testWidgets('the Categories button is read as its tooltip alone, the '
        'badge excluded', (tester) async {
      final robot = await open(tester, categoryIds: {'gym'});
      final handle = tester.ensureSemantics();
      final data = tester
          .getSemantics(robot.byId(SemanticsIds.reportCategoriesOpen))
          .getSemanticsData();
      expect(data.tooltip, robot.l10n.calendarCategories);
      expect(data.label, isEmpty, reason: 'the badge\'s "1" is not read');
      handle.dispose();
    });
  });

  group('the comparison (D36.3)', () {
    testWidgets('a month so far is compared with the same days of the month '
        'before, named by their span', (tester) async {
      final robot = await open(
        tester,
        period: const OverviewMonthPeriod(2026, 10),
        at: () => DateTime(2026, 10, 15, 10),
      );
      expect(robot.caption, contains('against Sep 1 – Sep 15, 2026'));
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(robot.tile(ReportTile.attended)).label,
        endsWith('than Sep 1 – Sep 15, 2026'),
      );
      handle.dispose();
    });

    testWidgets('a past month is compared with the whole month before, by '
        'its name', (tester) async {
      final robot = await open(tester);
      expect(robot.caption, contains('against February 2026'));
    });
  });

  group('Show as list', () {
    testWidgets('hands the overview the clamped span and the categories', (
      tester,
    ) async {
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2025, 1, 1),
          DateTime.utc(2026, 6, 30),
        ),
        categoryIds: {'gym'},
      );
      final look = (await robot.showAsListAndLeave())!;
      expect(look.start, DateTime.utc(2025, 6, 30));
      expect(look.end, DateTime.utc(2026, 6, 30));
      expect(look.categoryIds, {'gym'});
    });
  });

  group('refold', () {
    /// Holds the next fold open until [release].
    void hold() => gate = Completer<void>();
    Future<void> release(WidgetTester tester) async {
      final held = gate!;
      gate = null;
      held.complete();
      await tester.pump();
      await tester.pump();
    }

    Future<void> stepBack(WidgetTester tester, ReportRobot robot) async {
      await robot.tapId(SemanticsIds.reportNavPrevious);
      await tester.pump();
      expect(robot.state, isA<ReportFolding>());
    }

    testWidgets('dims after 150 ms and absorbs taps; un-dims at once on '
        'Ready', (tester) async {
      final robot = await open(tester);
      hold();
      await stepBack(tester, robot);
      expect(robot.bodyOpacity, 1);
      expect(robot.bodyAbsorbsTaps, isFalse);

      await tester.pump(const Duration(milliseconds: 140));
      expect(robot.bodyOpacity, 1);
      await tester.pump(const Duration(milliseconds: 20));
      expect(robot.bodyOpacity, closeTo(0.6, 0.001));
      expect(robot.bodyAbsorbsTaps, isTrue);

      await release(tester);
      expect(robot.state, isA<ReportReady>());
      expect(robot.bodyOpacity, 1);
      expect(robot.bodyAbsorbsTaps, isFalse);
    });

    testWidgets('a fold landing under 150 ms never dims', (tester) async {
      final robot = await open(tester);
      hold();
      await stepBack(tester, robot);
      await tester.pump(const Duration(milliseconds: 100));
      await release(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(robot.bodyOpacity, 1);
      expect(robot.bodyAbsorbsTaps, isFalse);
    });

    testWidgets('the dim timer dies with the page', (tester) async {
      final robot = await open(tester);
      hold();
      await stepBack(tester, robot);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      gate!.complete();
      gate = null;
      expect(tester.takeException(), isNull);
    });

    testWidgets('while folding only the title shows the new pick: the '
        'subtitle is blank, the caption and Show as list are the old '
        'report\'s (D36.9)', (tester) async {
      final robot = await open(tester, categoryIds: {'gym'});
      final caption = robot.caption;
      hold();
      await stepBack(tester, robot);
      expect(robot.nav.title, 'February 2026');
      expect(robot.nav.subtitle, ' ', reason: 'the line kept, blank');
      expect(robot.caption, caption);
      final look = (await robot.showAsListAndLeave())!;
      expect(look.start, DateTime.utc(2026, 3, 1));
      expect(look.end, DateTime.utc(2026, 3, 31));
      expect(look.categoryIds, {'gym'});
      gate!.complete();
      gate = null;
    });
  });

  group('§4.8 geometry, the rest', () {
    testWidgets('de 1.3: the card is 594', (tester) async {
      final robot = await open(
        tester,
        locale: const Locale('de'),
        textScale: 1.3,
      );
      expect(robot.totalsRect.height, closeTo(594, 1));
    });

    testWidgets('2.0: the card is 844', (tester) async {
      final robot = await open(tester, textScale: 2.0);
      expect(robot.totalsRect.height, closeTo(844, 1));
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('the band keeps its height through a step and a refold at '
          '$scale', (tester) async {
        final robot = await open(tester, textScale: scale);
        double band() => tester.getSize(find.byType(AgendaPeriodNav)).height;
        final height = band();
        gate = Completer<void>();
        await robot.tapId(SemanticsIds.reportNavPrevious);
        await tester.pump();
        expect(robot.state, isA<ReportFolding>());
        expect(band(), height, reason: 'folding');
        final held = gate!;
        gate = null;
        held.complete();
        await tester.pump();
        await tester.pump();
        expect(band(), height, reason: 'ready');
      });
    }
  });

  testWidgets('no fold runs in a build: frames after Ready fold nothing', (
    tester,
  ) async {
    await open(tester);
    expect(service.foldCount, 1);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(service.foldCount, 1);
  });
}
