import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/calendar_report/calendar_report_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_report_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/alert_keep_notice.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/utils/report_markdown.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_more_categories_sheet.dart';
import 'package:anta/widgets/report_trend_chart.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/digest_sheet_robot.dart';
import 'support/report_robot.dart';

/// A calendar bloc that records the presence marks it is handed and keeps
/// them: the real write reaches the presence store's database, which a
/// widget test under FakeAsync must not open. It counts the reloads asked
/// of it too.
class _RecordingCalendarBloc extends CalendarBloc {
  _RecordingCalendarBloc()
    : super(service: Completer<CalendarEventService>().future);

  final List<SetOccurrencePresence> marks = [];
  int loads = 0;

  /// The digests the footer's Send hands over, kept off the digest store's
  /// database for the marks' reason.
  final List<EventDigest> savedDigests = [];

  @override
  void add(CalendarPageEvent event) {
    if (event is SetOccurrencePresence) {
      marks.add(event);
      return;
    }
    if (event is SaveEventDigest) {
      savedDigests.add(event.digest);
      return;
    }
    if (event is LoadCalendarEvents) loads++;
    super.add(event);
  }

  /// What the real write emits once the store holds the mark: the same
  /// events list, both revisions moved (`_onSetOccurrencePresence`).
  void landMark() {
    final current = state as CalendarPageLoaded;
    // ignore: invalid_use_of_visible_for_testing_member
    emit(
      current.copyWith(
        occurrenceRevision: current.occurrenceRevision + 1,
        presenceRevision: current.presenceRevision + 1,
      ),
    );
  }
}

/// An import/export bloc that records the text and calendar exports it is
/// handed and never answers them, so each stays pending: the real one would
/// reach the share sheet.
class _RecordingImportExportBloc extends ImportExportBloc {
  _RecordingImportExportBloc({required super.service});

  final List<ExportTextRequested> texts = [];
  final List<ExportCalendarRequested> calendars = [];

  @override
  void add(ImportExportEvent event) {
    if (event is ExportTextRequested) {
      texts.add(event);
      return;
    }
    if (event is ExportCalendarRequested) {
      calendars.add(event);
      return;
    }
    super.add(event);
  }
}

/// A report service whose folds throw while [fail] is up, as a fold that
/// hits a bad event would.
class _FailingReportService extends CalendarReportService {
  bool fail = false;
  int failures = 0;

  @override
  CalendarReport report(ReportRequest request) {
    if (fail) {
      failures++;
      throw StateError('fold failed');
    }
    return super.report(request);
  }
}

/// The report page over a loaded calendar: its bar, its band and Period
/// menu, the Totals card per the selection (D15) and the tense (T), the
/// caption, the footer, and §4.8's geometry, measured with Roboto loaded.
void main() {
  late CalendarBloc bloc;
  late _RecordingImportExportBloc importExport;
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
    importExport = _RecordingImportExportBloc(
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
    bloc = _RecordingCalendarBloc();
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
    AlertKeepNotice.instance.clearForTesting();
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
    ValueListenable<EdgeInsets>? viewInsets,
    bool? alwaysUse24HourFormat,
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
      viewInsets: viewInsets,
      alwaysUse24HourFormat: alwaysUse24HourFormat,
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
    testWidgets('three rows by id, all live; Send monthly on a month', (
      tester,
    ) async {
      final robot = await open(tester);
      await robot.reveal(robot.byId(SemanticsIds.reportSend));
      expect(robot.footerRow(SemanticsIds.reportShowList).onTap, isNotNull);
      expect(robot.footerRow(SemanticsIds.reportShare).onTap, isNotNull);
      final send = robot.footerRow(SemanticsIds.reportSend);
      expect(send.onTap, isNotNull);
      expect(send.label, 'Send me this report monthly');
    });

    testWidgets('Share hands the import/export bloc the report shown as '
        'Markdown, named for its span (K)', (tester) async {
      final robot = await open(tester);
      final share = robot.byId(SemanticsIds.reportShare);
      await robot.reveal(share);
      await tester.tap(share);
      await tester.pump();
      final request = importExport.texts.single;
      expect(request.fileName, 'anta_report_20260301-20260331.md');
      expect(request.format, ExportFormat.markdown);
      expect(request.share, isTrue);
      expect(request.text, startsWith('# Report${ReportLabels.separator}'));
      expect(request.text, contains('March 2026'));
      expect(request.text, contains('## Totals\n'));
      expect(request.text, contains('### Gym'));
    });

    testWidgets('the shared text is the Markdown of the report shown, with '
        'its comparison (D46)', (tester) async {
      final robot = await open(tester, alwaysUse24HourFormat: true);
      // Read while the Totals card the robot reads it through is on screen.
      final l10n = robot.l10n;
      final share = robot.byId(SemanticsIds.reportShare);
      await robot.reveal(share);
      await tester.tap(share);
      await tester.pump();
      final report = (robot.state as ReportReady).report;
      final text = importExport.texts.single.text;
      expect(
        text,
        ReportMarkdown.render(
          report,
          ReportLabels(l10n),
          use24Hour: true,
          periodName: 'March 2026',
          against: 'February 2026',
        ),
      );
      expect(text, contains('against February 2026'));
    });

    testWidgets('two taps on Share start one export (D46)', (tester) async {
      final robot = await open(tester);
      final share = robot.byId(SemanticsIds.reportShare);
      await robot.reveal(share);
      await tester.tap(share);
      await tester.pump();
      await tester.tap(share);
      await tester.pump();
      expect(importExport.texts, hasLength(1));
    });

    testWidgets('Share while the ⋮\'s events export is pending starts '
        'nothing (D46)', (tester) async {
      final robot = await open(tester);
      await robot.tapId(SemanticsIds.reportMore);
      await tester.pumpAndSettle();
      await robot.tapId(SemanticsIds.calendarExport);
      await tester.pumpAndSettle();
      expect(importExport.calendars, hasLength(1));
      final share = robot.byId(SemanticsIds.reportShare);
      await robot.reveal(share);
      await tester.tap(share);
      await tester.pump();
      expect(importExport.texts, isEmpty);
    });

    testWidgets('Send on a week opens the digest sheet as a week report over '
        "the report's categories; Save hands the calendar a new one on the "
        "week's first day at the alerts' default time (J, D45)", (
      tester,
    ) async {
      final robot = await open(
        tester,
        period: OverviewWeekPeriod(DateTime.utc(2026, 3, 2)),
        categoryIds: {'gym'},
      );
      await robot.send();
      final sheet = DigestSheetRobot(tester);

      expect(sheet.isOpen, isTrue);
      expect(find.text('New digest'), findsOneWidget);
      expect(sheet.showsValue, 'The week just ended');
      expect(sheet.cadenceValue, 'Week');
      expect(sheet.anchorValue, 'Monday');
      expect(sheet.categoriesValue, 'Gym');
      expect(sheet.timeValue, '9:00 AM');

      await sheet.save();
      expect(sheet.isOpen, isFalse);
      expect((bloc as _RecordingCalendarBloc).savedDigests, [
        const EventDigest(
          id: '',
          cadence: DigestCadence.weeklyReport,
          anchor: DateTime.monday,
          minute: kDefaultAlertDayMinute,
          categoryIds: {'gym'},
        ),
      ]);
      expect(kDefaultAlertDayMinute, 9 * 60);
    });

    testWidgets("a Sunday week start fires the week report on Sunday", (
      tester,
    ) async {
      await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
      final robot = await open(
        tester,
        period: OverviewWeekPeriod(DateTime.utc(2026, 3, 1)),
      );
      await robot.send();

      expect(DigestSheetRobot(tester).anchorValue, 'Sunday');
    });

    testWidgets('Send on a month, or on any other period, opens a month '
        'report on the 1st', (tester) async {
      for (final period in [
        march,
        OverviewCustomPeriod(
          DateTime.utc(2026, 3, 3),
          DateTime.utc(2026, 3, 20),
        ),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final robot = await open(tester, period: period);
        await robot.reveal(robot.byId(SemanticsIds.reportSend));
        expect(
          robot.footerRow(SemanticsIds.reportSend).label,
          'Send me this report monthly',
        );
        await robot.send();
        final sheet = DigestSheetRobot(tester);

        expect(sheet.showsValue, 'The month just ended');
        expect(sheet.anchorValue, '1st');
        expect(sheet.categoriesValue, 'Events');
        await sheet.close();
        expect(sheet.isOpen, isFalse);
      }
      expect((bloc as _RecordingCalendarBloc).savedDigests, isEmpty);
    });

    testWidgets('at the digest cap Send is disabled where it stands: 38 %, '
        'marked so, and a tap opens nothing (D45)', (tester) async {
      EventDigests.updateCache(
        List.unmodifiable([
          for (var i = 0; i < kDigestHorizon.maxDigests; i++)
            EventDigest(id: 'd$i', sortOrder: i),
        ]),
      );
      addTearDown(EventDigests.resetCache);
      final robot = await open(tester);
      final send = robot.byId(SemanticsIds.reportSend);
      await robot.reveal(send);

      expect(robot.footerRow(SemanticsIds.reportSend).onTap, isNull);
      expect(
        tester
            .widgetList<Opacity>(
              find.descendant(of: send, matching: find.byType(Opacity)),
            )
            .first
            .opacity,
        FormMetrics.disabledOpacity,
      );
      final data = tester.getSemantics(send).getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(DigestSheetRobot(tester).isOpen, isFalse);
      expect((bloc as _RecordingCalendarBloc).savedDigests, isEmpty);
    });

    testWidgets("a report digest's tap over a live report serves its look: "
        'the band shows the week, the allowlist is the digest\'s (D43)', (
      tester,
    ) async {
      final robot = ReportRobot(tester);
      await robot.open(
        bloc: bloc,
        importExport: importExport,
        service: service,
        clock: clock,
        nextFrame: nextFrame,
        look: (period: march, categoryIds: const {}),
        surface: const Size(360, 780),
        stamped: true,
      );
      expect(robot.isReady, isTrue);
      expect(robot.nav.title, 'March 2026');
      addTearDown(() => AppNavigator.pendingReportLook.value = null);

      await AppNavigator.toCalendarReportLook(
        start: DateTime.utc(2026, 10, 19),
        end: DateTime.utc(2026, 10, 25),
        categoryIds: {'gym'},
      );
      for (var i = 0; i < 30 && !robot.isReady; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(AppNavigator.pendingReportLook.value, isNull);
      final state = robot.state as ReportShown;
      expect(state.period, OverviewWeekPeriod(DateTime.utc(2026, 10, 19)));
      expect(state.categoryIds, {'gym'});
      expect(
        robot.nav.title,
        ReportLabels(robot.l10n).periodName(state.period),
      );
      expect(robot.nav.title, isNot('March 2026'));
    });

    testWidgets('Send reads weekly on a week', (tester) async {
      final robot = await open(
        tester,
        period: OverviewWeekPeriod(DateTime.utc(2026, 3, 2)),
      );
      await robot.reveal(robot.byId(SemanticsIds.reportSend));
      expect(
        robot.footerRow(SemanticsIds.reportSend).label,
        'Send me this report weekly',
      );
    });

    testWidgets('de and ro at 2.0 on 360: the Send row\'s label stays at two '
        'lines, weekly and monthly (D44)', (tester) async {
      final week = OverviewWeekPeriod(DateTime.utc(2026, 3, 2));
      for (final (period, locale, label) in [
        (march, 'de', 'Monatlich zusenden'),
        (week, 'de', 'Wöchentlich zusenden'),
        (march, 'ro', 'Trimite raportul lunar'),
        (week, 'ro', 'Trimite raportul săptămânal'),
      ]) {
        final robot = await open(
          tester,
          period: period,
          locale: Locale(locale),
          textScale: 2.0,
        );
        final send = robot.byId(SemanticsIds.reportSend);
        await robot.reveal(send);
        expect(robot.footerRow(SemanticsIds.reportSend).label, label);
        final paragraph = tester
            .renderObjectList<RenderParagraph>(
              find.descendant(of: send, matching: find.byType(RichText)),
            )
            .singleWhere((p) => p.text.toPlainText() == label);
        // A replica with no line cap: the lines the label needs, not the
        // lines it is allowed.
        final painter = TextPainter(
          text: paragraph.text,
          textScaler: paragraph.textScaler,
          textDirection: paragraph.textDirection,
        )..layout(maxWidth: paragraph.size.width);
        addTearDown(painter.dispose);
        expect(painter.computeLineMetrics().length, lessThanOrEqualTo(2));
        await tester.pumpWidget(const SizedBox.shrink());
      }
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
      // Tall enough that the Categories card leaves the label on stage.
      final robot = await open(tester, surface: const Size(360, 1600));
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
      final robot = await open(tester);
      await robot.reveal(chart());
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

      final robot = await open(tester, brightness: Brightness.dark);
      await robot.reveal(chart());
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

  group('category groups', () {
    /// A surface tall enough that every card is on stage at once.
    const tall = Size(360, 2400);

    /// Replaces the calendar's events: a new state the report folds.
    void seed(List<CalendarEvent> events, {int presenceRevision = 0}) {
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        CalendarPageLoaded(
          allEvents: events,
          focusedDay: today,
          selectedDay: today,
          presenceRevision: presenceRevision,
        ),
      );
    }

    /// [count] one-offs in [categoryId], one a day from March 1.
    List<CalendarEvent> oneOffs(String categoryId, int count) => [
      for (var i = 0; i < count; i++)
        CalendarEvent(
          id: 'e-$categoryId-$i',
          title: '$categoryId ${i + 1}',
          categoryId: categoryId,
          startDate: DateTime.utc(2026, 3, 1 + i),
          rule: const OneTimeRecurrence(),
        ),
    ];

    DateTime march(int day) => DateTime.utc(2026, 3, day);

    Finder header(ReportCard card) =>
        find.bySemanticsIdentifier(RegExp('^report-group-${card.name}-'));

    FormMeterRow meter(WidgetTester tester, ReportCard card, String id) =>
        tester.widget<FormMeterRow>(
          find.byWidgetPredicate(
            (w) =>
                w is FormMeterRow &&
                w.identifier == SemanticsIds.reportGroup(card.name, id),
          ),
        );

    double glyphTurns(WidgetTester tester, ReportRobot robot, String id) =>
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: robot.group(ReportCard.categories, id),
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns;

    testWidgets('a past month: CATEGORIES between the Totals caption and '
        'OVER TIME, MISSED between the chart and the footer, no Ahead', (
      tester,
    ) async {
      final robot = await open(tester, surface: tall);
      double top(Finder finder) => tester.getRect(finder).top;
      final caption = top(find.text(robot.caption!));
      final categories = top(find.text('CATEGORIES'));
      final overTime = top(find.text('OVER TIME'));
      final missed = top(find.text('MISSED'));
      final footer = top(robot.byId(SemanticsIds.reportShowList));
      expect(categories, greaterThan(caption));
      expect(
        top(robot.group(ReportCard.categories, 'gym')),
        greaterThan(categories),
      );
      expect(
        top(robot.group(ReportCard.categories, 'other')),
        lessThan(overTime),
      );
      expect(overTime, greaterThan(categories));
      expect(missed, greaterThan(top(find.byType(ReportTrendChart))));
      expect(top(robot.group(ReportCard.missed, 'gym')), greaterThan(missed));
      expect(footer, greaterThan(top(robot.group(ReportCard.missed, 'gym'))));
      expect(find.text('AHEAD'), findsNothing);
      expect(header(ReportCard.ahead), findsNothing);
      expect(find.byType(Scrollable), findsOneWidget);
    });

    testWidgets('a month ending after today draws Ahead, its rows the '
        'caption\'s "n ahead"', (tester) async {
      final robot = await open(
        tester,
        period: const OverviewMonthPeriod(2026, 10),
        surface: tall,
      );
      final report = (robot.state as ReportReady).shown;
      expect(report.aheadCount, greaterThan(0));
      expect(
        robot.caption,
        // The caption keeps the count and its word on one line.
        contains(RegExp('${report.aheadCount}.ahead')),
      );
      expect(find.text('AHEAD'), findsOneWidget);
      expect(robot.group(ReportCard.ahead, 'gym'), findsOneWidget);
      expect(report.ahead.single.rows, hasLength(report.aheadCount));
      expect(
        tester.getRect(find.text('AHEAD')).top,
        lessThan(tester.getRect(robot.byId(SemanticsIds.reportShowList)).top),
      );
    });

    testWidgets('a future month is a plan: Categories only', (tester) async {
      final robot = await open(
        tester,
        period: const OverviewMonthPeriod(2026, 11),
        surface: tall,
      );
      expect(find.text('CATEGORIES'), findsOneWidget);
      expect(robot.group(ReportCard.categories, 'gym'), findsOneWidget);
      expect(find.text('MISSED'), findsNothing);
      expect(find.text('AHEAD'), findsNothing);
      expect(header(ReportCard.missed), findsNothing);
      expect(header(ReportCard.ahead), findsNothing);
    });

    testWidgets('twelve rows: four and "8 more", twelve and "Show less" '
        'with nothing above moving, back to four; a header tap closes the '
        'group, and a step there and back keeps it closed', (tester) async {
      seed([gym, todo, ...oneOffs('cardio', 12)]);
      final robot = await open(
        tester,
        categoryIds: {'cardio'},
        surface: const Size(360, 2000),
      );
      Finder row(int i) => robot.row('e-cardio-${i - 1}', march(i));
      for (var i = 1; i <= 4; i++) {
        expect(row(i), findsOneWidget);
      }
      expect(row(5), findsNothing);
      final more = robot.groupMore(ReportCard.categories, 'cardio');
      expect(more, findsOneWidget);
      expect(find.text('8 more'), findsOneWidget);
      final header = robot.group(ReportCard.categories, 'cardio');
      final headerRect = tester.getRect(header);
      final above = [for (var i = 1; i <= 4; i++) tester.getRect(row(i))];

      await robot.tapId(SemanticsIds.reportGroupMore('categories', 'cardio'));
      for (var i = 1; i <= 12; i++) {
        expect(row(i), findsOneWidget, reason: 'row $i');
      }
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.getRect(header), headerRect);
      for (var i = 1; i <= 4; i++) {
        expect(tester.getRect(row(i)), above[i - 1], reason: 'row $i');
      }

      await robot.tapId(SemanticsIds.reportGroupMore('categories', 'cardio'));
      expect(row(4), findsOneWidget);
      expect(row(5), findsNothing);
      expect(find.text('8 more'), findsOneWidget);

      expect(glyphTurns(tester, robot, 'cardio'), 0.5);
      await robot.tapId(SemanticsIds.reportGroup('categories', 'cardio'));
      expect(row(1), findsNothing);
      expect(more, findsNothing);
      expect(header, findsOneWidget);
      expect(glyphTurns(tester, robot, 'cardio'), 0);

      await robot.tapId(SemanticsIds.reportNavPrevious);
      await tester.pumpAndSettle();
      await robot.tapId(SemanticsIds.reportNavNext);
      await tester.pumpAndSettle();
      expect(robot.nav.title, 'March 2026');
      expect(header, findsOneWidget);
      expect(row(1), findsNothing);
      expect(glyphTurns(tester, robot, 'cardio'), 0);
    });

    testWidgets('"8 more" with the header above the viewport: the row above '
        'the tapped one does not move, and still has not once settled', (
      tester,
    ) async {
      // Rest's group below gives the page room to scroll Cardio's header
      // away.
      seed([gym, todo, ...oneOffs('cardio', 12), ...oneOffs('rest', 6)]);
      final robot = await open(tester, categoryIds: {'cardio', 'rest'});
      Finder row(int i) => robot.row('e-cardio-${i - 1}', march(i));
      final header = robot.group(ReportCard.categories, 'cardio');
      final more = robot.groupMore(ReportCard.categories, 'cardio');
      await robot.reveal(header);
      // The header's bottom a few pixels above the body's top.
      final top = tester.getRect(robot.byId(SemanticsIds.reportBody)).top;
      robot.scroll.jumpTo(
        robot.scroll.offset + tester.getRect(header).bottom - top + 8,
      );
      await tester.pump();
      expect(header, findsNothing, reason: 'off screen');
      expect(tester.getRect(row(1)).top, lessThan(top));
      expect(tester.getRect(more).bottom, lessThan(780));
      final above = tester.getRect(row(4));

      await tester.tap(more);
      await tester.pump();
      expect(row(5), findsOneWidget, reason: 'expanded');
      expect(tester.getRect(row(4)), above);
      await tester.pumpAndSettle();
      expect(tester.getRect(row(4)), above);
    });

    testWidgets('"Show less" deep in a long group keeps "n more" under the '
        'finger in the first frame (S)', (tester) async {
      seed([...oneOffs('cardio', 30), ...oneOffs('rest', 6)]);
      final robot = await open(tester, categoryIds: {'cardio', 'rest'});
      Finder disclosure(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(FormActionRow),
      );
      await robot.reveal(disclosure('26 more'));
      await tester.tap(disclosure('26 more'));
      await tester.pump();
      await robot.reveal(disclosure('Show less'));
      const y = 500.0;
      robot.scroll.jumpTo(
        robot.scroll.offset + tester.getRect(disclosure('Show less')).top - y,
      );
      await tester.pump();
      final less = tester.getRect(disclosure('Show less'));
      expect(less.top, closeTo(y, 0.01));
      expect(
        robot.row('e-cardio-4', march(5)),
        findsNothing,
        reason: 'the fifth row is far above the viewport',
      );

      await tester.tapAt(less.center);
      await tester.pump();
      expect(find.text('Show less'), findsNothing);
      expect(tester.getRect(disclosure('26 more')).top, closeTo(y, 1));
      expect(robot.row('e-cardio-4', march(5)), findsNothing);
      expect(
        tester.getRect(robot.group(ReportCard.categories, 'rest')).top,
        greaterThan(y),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(disclosure('26 more')).top, closeTo(y, 1));
    });

    testWidgets('"Show less" above another long open group keeps "n more" '
        'under the finger too (S)', (tester) async {
      seed([...oneOffs('cardio', 30), ...oneOffs('rest', 28)]);
      final robot = await open(tester, categoryIds: {'cardio', 'rest'});
      Finder disclosure(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(FormActionRow),
      );
      await robot.reveal(disclosure('26 more'));
      await tester.tap(disclosure('26 more'));
      await tester.pump();
      await robot.reveal(disclosure('24 more'));
      await tester.tap(disclosure('24 more'));
      await tester.pump();
      // Back up past the Rest header to Cardio's "Show less".
      robot.scroll.jumpTo(robot.scroll.offset - 500);
      await tester.pump();
      const y = 300.0;
      final cardioLess = disclosure('Show less').first;
      robot.scroll.jumpTo(
        robot.scroll.offset + tester.getRect(cardioLess).top - y,
      );
      await tester.pump();
      final less = tester.getRect(cardioLess);
      expect(less.top, closeTo(y, 0.01));
      final restHeader = tester.getRect(
        robot.group(ReportCard.categories, 'rest'),
      );

      await tester.tapAt(less.center);
      await tester.pump();
      expect(find.text('26 more'), findsOneWidget);
      expect(tester.getRect(disclosure('26 more')).top, closeTo(y, 1));
      expect(
        tester.getRect(robot.group(ReportCard.categories, 'rest')).top,
        closeTo(restHeader.top, 1),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(disclosure('26 more')).top, closeTo(y, 1));
    });

    testWidgets('"Show less" near the top clamps the offset at 0, and "n '
        'more" lands the rest of the way up', (tester) async {
      seed([gym, todo, ...oneOffs('cardio', 6)]);
      final robot = await open(tester, categoryIds: {'cardio'});
      final more = robot.groupMore(ReportCard.categories, 'cardio');
      await robot.tapId(SemanticsIds.reportGroupMore('categories', 'cardio'));
      robot.scroll.jumpTo(40);
      await tester.pump();
      expect(find.text('Show less'), findsOneWidget);
      final tapY = tester.getRect(more).top;
      expect(tester.getRect(more).bottom, lessThan(780));
      // The extent the fold takes: the two rows past the preview, in their
      // shells.
      final rowHeight = tester
          .getRect(
            find
                .ancestor(
                  of: robot.row('e-cardio-4', march(5)),
                  matching: find.byType(FormRowShell),
                )
                .first,
          )
          .height;
      final extent = 2 * rowHeight;
      expect(extent, greaterThan(40));

      await robot.tapId(SemanticsIds.reportGroupMore('categories', 'cardio'));
      expect(find.text('2 more'), findsOneWidget);
      // Still longer than the viewport, so no clamp could have done it.
      expect(robot.scroll.position.maxScrollExtent, greaterThan(0));
      expect(robot.scroll.offset, 0);
      expect(tester.getRect(more).top, tapY - (extent - 40));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(robot.scroll.offset, 0);
      expect(tester.getRect(more).top, tapY - (extent - 40));
    });

    testWidgets('nine categories show seven groups and an enabled "2 more '
        'categories"; four show none', (tester) async {
      const rest = [
        'cardio',
        'rest',
        'holiday',
        'competition',
        'measurement',
        'mobility',
        'birthday',
      ];
      seed([
        gym,
        todo,
        for (final id in rest)
          CalendarEvent(
            id: 'e-$id',
            title: id,
            categoryId: id,
            startDate: march(12),
            rule: const OneTimeRecurrence(),
          ),
      ]);
      var robot = await open(tester, surface: tall);
      expect(header(ReportCard.categories), findsNWidgets(7));
      final cap = robot.byId(SemanticsIds.reportCategoriesMore);
      expect(cap, findsOneWidget);
      expect(find.text('2 more categories'), findsOneWidget);
      expect(
        tester.getSemantics(cap).getSemanticsData().flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      // One gap above the cap row, after the last group, and one below it,
      // before OVER TIME.
      final capRect = tester.getRect(
        find.ancestor(of: cap, matching: find.byType(FormRowShell)).first,
      );
      final above = [
        for (final element in find.byType(FormRowShell).evaluate())
          if (element.renderObject case final RenderBox box)
            (box.localToGlobal(Offset.zero) & box.size).bottom,
      ].where((bottom) => bottom < capRect.top).reduce(math.max);
      expect(capRect.top - above, RowMetrics.groupGap);
      final overTime = tester.getRect(
        find.ancestor(
          of: find.text('OVER TIME'),
          matching: find.byType(FormSectionLabel),
        ),
      );
      expect(overTime.top - capRect.bottom, RowMetrics.groupGap);
      await tester.pumpWidget(const SizedBox.shrink());

      robot = await open(
        tester,
        categoryIds: {'gym', 'other', 'cardio', 'rest'},
        surface: tall,
      );
      expect(header(ReportCard.categories), findsNWidgets(4));
      expect(robot.byId(SemanticsIds.reportCategoriesMore), findsNothing);
    });

    /// March over nine categories: Gym's routine, the to-do in Other and a
    /// one-off on the 12th in each of the seven others — one each, so the
    /// built-in order puts Birthday and Other past the card's seven.
    void seedNine() => seed([
      gym,
      todo,
      for (final id in const [
        'cardio',
        'rest',
        'holiday',
        'competition',
        'measurement',
        'mobility',
        'birthday',
      ])
        CalendarEvent(
          id: 'e-$id',
          title: id,
          categoryId: id,
          startDate: march(12),
          rule: const OneTimeRecurrence(),
        ),
    ]);

    Finder inSheet(Finder finder) => find.descendant(
      of: find.bySemanticsIdentifier(SemanticsIds.reportMoreList),
      matching: finder,
    );

    /// Taps the cap row and runs the sheet in; the groups it should list.
    Future<List<ReportCategoryGroup>> openMore(
      WidgetTester tester,
      ReportRobot robot,
    ) async {
      final rest = (robot.state as ReportReady).report.categories
          .skip(7)
          .toList();
      final cap = robot.byId(SemanticsIds.reportCategoriesMore);
      await robot.reveal(cap);
      await tester.tap(cap);
      await tester.pumpAndSettle();
      expect(robot.byId(SemanticsIds.reportMoreClose), findsOneWidget);
      return rest;
    }

    testWidgets('de 2.0 on 412 × 915: a route pushed in the frame after a '
        'jump to the end drops no semantics frame (D44)', (tester) async {
      seedNine();
      final handle = tester.ensureSemantics();
      final robot = await open(
        tester,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(412, 915),
      );
      robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
      await tester.pump();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(CalendarReportPage)),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('de 2.0 on 412 × 915: a route pushed in the same frame as the '
        'jump to the end drops no semantics frame (D44, D46)', (tester) async {
      seedNine();
      final handle = tester.ensureSemantics();
      final robot = await open(
        tester,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(412, 915),
      );
      // No pump between the jump and the push: both land in one frame.
      robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(CalendarReportPage)),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('the cap row opens the rest in the sheet; a dated row picked '
        'there opens its detail sheet on its day, in place', (tester) async {
      seedNine();
      final robot = await open(tester);
      final rest = await openMore(tester, robot);
      expect(
        [for (final group in rest) group.categoryId],
        ['birthday', 'other'],
      );
      for (final group in rest) {
        expect(
          inSheet(robot.group(ReportCard.categories, group.categoryId)),
          findsOneWidget,
        );
      }

      await tester.tap(inSheet(robot.row('e-birthday', march(12))));
      await tester.pumpAndSettle();
      expect(robot.byId(SemanticsIds.reportMoreClose), findsNothing);
      final sheet = robot.detailSheet!;
      expect(sheet.event.id, 'e-birthday');
      expect(sheet.day, march(12));
      await robot.closeSheet();
      expect(robot.detailSheet, isNull);
    });

    testWidgets('a group\'s Show as list in the sheet hands the overview the '
        'folded span and its category', (tester) async {
      // Eight daily categories over nine months: past 200 rows each, so the
      // eighth — Birthday, last in the built-in order — has its Show as list.
      seed([
        for (final id in const [
          'gym',
          'cardio',
          'rest',
          'holiday',
          'competition',
          'measurement',
          'mobility',
          'birthday',
        ])
          CalendarEvent(
            id: 'e-$id',
            title: id,
            categoryId: id,
            startDate: DateTime.utc(2026, 1, 1),
            rule: const DailyRecurrence(),
          ),
      ]);
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 9, 30),
        ),
      );
      final rest = await openMore(tester, robot);
      expect(rest.single.categoryId, 'birthday');
      await tester.tap(
        inSheet(robot.groupMore(ReportCard.categories, 'birthday')),
      );
      await tester.pump();
      final list = inSheet(
        robot.byId(SemanticsIds.reportGroupList('categories', 'birthday')),
      );
      await tester.scrollUntilVisible(
        list,
        600,
        scrollable: inSheet(find.byType(Scrollable)),
      );

      await tester.tap(list);
      // The pick reaches the page a few microtasks after the pop; the
      // overview it pushes is never built here (the robot's rule).
      await tester.idle();
      final look = AppNavigator.pendingOverviewLook.value;
      AppNavigator.pendingOverviewLook.value = null;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(look?.start, DateTime.utc(2026, 1, 1));
      expect(look?.end, DateTime.utc(2026, 9, 30));
      expect(look?.categoryIds, {'birthday'});
    });

    testWidgets('a second tap on the cap row while the sheet opens opens '
        'nothing', (tester) async {
      seedNine();
      final robot = await open(tester);
      await robot.reveal(robot.byId(SemanticsIds.reportCategoriesMore));
      // Twice in one frame, before the sheet's barrier is laid out to catch
      // the second: the page's one guard slot is what stops it.
      final tap = tester
          .widget<FormActionRow>(
            find.byWidgetPredicate(
              (w) =>
                  w is FormActionRow &&
                  w.identifier == SemanticsIds.reportCategoriesMore,
            ),
          )
          .onTap!;
      tap();
      tap();
      await tester.pumpAndSettle();
      expect(find.byType(ReportMoreCategoriesSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.reportMoreClose);
      await tester.pumpAndSettle();
      expect(find.byType(ReportMoreCategoriesSheet), findsNothing);
    });

    testWidgets('the sheet folds with the page\'s state: Birthday closed '
        'there is still closed when it opens again (D42)', (tester) async {
      seedNine();
      final robot = await open(tester);
      await openMore(tester, robot);
      final birthday = inSheet(robot.row('e-birthday', march(12)));
      expect(birthday, findsOneWidget);
      await tester.tap(inSheet(robot.group(ReportCard.categories, 'birthday')));
      await tester.pump();
      expect(birthday, findsNothing);

      await tester.tap(inSheet(robot.row(todo.id, march(10))));
      await tester.pumpAndSettle();
      expect(robot.detailSheet?.event.id, todo.id);
      await robot.closeSheet();

      await openMore(tester, robot);
      expect(
        inSheet(robot.group(ReportCard.categories, 'birthday')),
        findsOneWidget,
      );
      expect(birthday, findsNothing);
    });

    testWidgets('a sheet row tapped twice in one frame closes the sheet once: '
        'the report page stays under the detail sheet (D42)', (tester) async {
      seedNine();
      final robot = await open(tester);
      await openMore(tester, robot);
      // Both before a frame, through the row's semantics action — a
      // screen reader's double activation: the navigator absorbs pointers
      // after a pop, not actions.
      final row = tester.getSemantics(
        inSheet(robot.row('e-birthday', march(12))),
      );
      row.owner!.performAction(row.id, SemanticsAction.tap);
      row.owner!.performAction(row.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byType(ReportMoreCategoriesSheet), findsNothing);
      expect(find.byType(CalendarReportPage), findsOneWidget);
      expect(robot.detailSheet?.event.id, 'e-birthday');
      await robot.closeSheet();
      expect(robot.byId(SemanticsIds.reportBody), findsOneWidget);
    });

    testWidgets('meters: the largest group fills, half its count half; '
        'Missed and Ahead headers draw none', (tester) async {
      seed([gym, ...oneOffs('cardio', 4), ...oneOffs('rest', 2)]);
      await open(tester, categoryIds: {'cardio', 'rest'}, surface: tall);
      expect(meter(tester, ReportCard.categories, 'cardio').fraction, 1.0);
      expect(meter(tester, ReportCard.categories, 'rest').fraction, 0.5);
      await tester.pumpWidget(const SizedBox.shrink());

      EventPresence.updateCache(
        byEvent: {
          gym.id: {DateTime.utc(2026, 10, 5): PresenceStatus.missed},
        },
      );
      await open(
        tester,
        period: const OverviewMonthPeriod(2026, 10),
        surface: tall,
      );
      expect(meter(tester, ReportCard.categories, 'gym').fraction, 1.0);
      expect(meter(tester, ReportCard.missed, 'gym').fraction, isNull);
      expect(meter(tester, ReportCard.ahead, 'gym').fraction, isNull);
    });

    testWidgets('a Missed row\'s presence button writes the mark; the '
        'refold is one fold and the body keeps its offset', (tester) async {
      final recording = bloc as _RecordingCalendarBloc;
      EventPresence.updateCache(
        byEvent: {
          gym.id: {
            march(5): PresenceStatus.missed,
            march(6): PresenceStatus.missed,
          },
        },
      );
      final robot = await open(tester);
      final button = robot.byId(
        SemanticsIds.reportRowPresence(gym.id, march(5)),
      );
      // Short of the end, so the refold's shorter Missed card leaves the
      // offset inside the new extent.
      await tester.scrollUntilVisible(button, 100);
      robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent - 100);
      await tester.pump();
      final offset = robot.scroll.offset;
      expect(offset, greaterThan(0));
      expect(tester.getRect(button).bottom, lessThan(780));
      final label = tester.getRect(find.text('MISSED'));
      final folds = service.foldCount;

      await tester.tap(button);
      await tester.pump();
      // A second tap before the refold lands is dropped.
      await tester.tap(button);
      await tester.pump();
      expect(
        recording.marks.single,
        SetOccurrencePresence(
          eventId: gym.id,
          day: march(5),
          status: PresenceStatus.present,
        ),
      );

      // What the bloc's write does: the mark in the cache, the same events
      // with both revisions moved.
      EventPresence.updateCache(
        byEvent: {
          gym.id: {
            march(5): PresenceStatus.present,
            march(6): PresenceStatus.missed,
          },
        },
      );
      recording.landMark();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(robot.nav.subtitle, isNot(' '), reason: 'the refold landed');
      expect(service.foldCount, folds + 1);
      expect(robot.scroll.offset, offset);
      expect(tester.getRect(find.text('MISSED')), label);
      expect(robot.row(gym.id, march(5)), findsNothing);
    });

    /// March with Gym missed on [days], the page at the end of its scroll.
    Future<ReportRobot> atTheEnd(
      WidgetTester tester,
      List<int> days, {
      ValueListenable<EdgeInsets>? viewInsets,
    }) async {
      EventPresence.updateCache(
        byEvent: {
          gym.id: {for (final day in days) march(day): PresenceStatus.missed},
        },
      );
      final robot = await open(tester, viewInsets: viewInsets);
      // Twice: the lists above estimate their extent from the rows built,
      // and the first jump changes which are.
      for (var i = 0; i < 2; i++) {
        robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
        await tester.pump();
      }
      return robot;
    }

    /// Marks [day] present and lands the write with [left] still missed.
    Future<void> markPresent(
      WidgetTester tester,
      ReportRobot robot,
      int day, {
      List<int> left = const [],
    }) async {
      await tester.tap(
        robot.byId(SemanticsIds.reportRowPresence(gym.id, march(day))),
      );
      await tester.pump();
      EventPresence.updateCache(
        byEvent: {
          gym.id: {
            march(day): PresenceStatus.present,
            for (final missed in left) march(missed): PresenceStatus.missed,
          },
        },
      );
      (bloc as _RecordingCalendarBloc).landMark();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(robot.nav.subtitle, isNot(' '), reason: 'the refold landed');
    }

    testWidgets('at the end of the page a mark on the last Missed row moves '
        'nothing; dragging back drains the room it left, nothing jumping', (
      tester,
    ) async {
      var robot = await atTheEnd(tester, [5, 6]);
      final offset = robot.scroll.offset;
      final label = tester.getRect(find.text('MISSED'));
      final header = robot.group(ReportCard.missed, 'gym');
      final headerRect = tester.getRect(header);

      await markPresent(tester, robot, 6, left: [5]);
      expect(robot.row(gym.id, march(6)), findsNothing);
      expect(robot.scroll.offset, offset);
      expect(tester.getRect(find.text('MISSED')), label);
      expect(tester.getRect(header), headerRect);
      // The room left is exactly what keeps the offset: no more to scroll.
      expect(robot.scroll.position.maxScrollExtent, offset);

      // The page dragged back toward its top by 200: past the touch slop
      // first, then 200 more, under which the header moves by exactly 200.
      final gesture = await tester.startGesture(headerRect.center);
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final before = tester.getRect(header).top;
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(tester.getRect(header).top, before + 100);
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(tester.getRect(header).top, before + 200);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      final pixels = robot.scroll.offset;
      final drained = robot.scroll.position.maxScrollExtent;

      // The same state opened afresh at the same offset — the lists above
      // estimate their extent from the rows built: the content's own
      // extent, no room left over.
      await tester.pumpWidget(const SizedBox.shrink());
      robot = await open(tester);
      robot.scroll.jumpTo(pixels);
      await tester.pump();
      expect(robot.scroll.position.maxScrollExtent, drained);
    });

    testWidgets('at the end of the page a mark that empties Missed moves '
        'nothing above it', (tester) async {
      final robot = await atTheEnd(tester, [5]);
      final offset = robot.scroll.offset;
      final chart = tester.getRect(find.byType(ReportTrendChart));

      await markPresent(tester, robot, 5);
      expect(find.text('MISSED'), findsNothing);
      expect(robot.scroll.offset, offset);
      expect(tester.getRect(find.byType(ReportTrendChart)), chart);
    });

    testWidgets('at the end of the page a long Ahead group closed by its '
        'header keeps the header where it was', (tester) async {
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 10, 1),
          DateTime.utc(2026, 12, 31),
        ),
      );
      for (var i = 0; i < 2; i++) {
        robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
        await tester.pump();
      }
      final offset = robot.scroll.offset;
      final header = robot.group(ReportCard.ahead, 'gym');
      final rect = tester.getRect(header);
      expect(rect.bottom, lessThan(780));
      expect(robot.groupMore(ReportCard.ahead, 'gym'), findsOneWidget);

      await robot.tapId(SemanticsIds.reportGroup('ahead', 'gym'));
      expect(robot.groupMore(ReportCard.ahead, 'gym'), findsNothing);
      expect(robot.scroll.offset, offset);
      expect(tester.getRect(header), rect);
      await tester.pumpAndSettle();
      expect(tester.getRect(header), rect);
    });

    testWidgets('"Show less" at the very end of the page keeps "n more" where '
        'the finger was (S)', (tester) async {
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 10, 1),
          DateTime.utc(2026, 12, 31),
        ),
      );
      final more = robot.groupMore(ReportCard.ahead, 'gym');
      await robot.reveal(more);
      await tester.tap(more);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
        await tester.pump();
      }
      final less = tester.getRect(more);
      expect(less.bottom, lessThan(780));
      expect(
        find.descendant(of: more, matching: find.text('Show less')),
        findsOneWidget,
      );

      await tester.tapAt(less.center);
      await tester.pump();
      expect(
        find.descendant(
          of: more,
          matching: find.textContaining(RegExp(r'^\d+ more$')),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(more).top, less.top);
      await tester.pumpAndSettle();
      expect(tester.getRect(more).top, less.top);
    });

    /// The footer's first row, whose rect says whether the end moved.
    Rect footerRect(WidgetTester tester, ReportRobot robot) =>
        tester.getRect(robot.byId(SemanticsIds.reportShowList));

    testWidgets('at the end of the page a refold of the same look with no '
        'mark pending leaves the shrink to the clamp: the footer holds and '
        'the page ends where a fresh one does (D40)', (tester) async {
      // Cardio's group sits above the viewport at the end: re-categorised
      // or deleted on a sheet's trip, its rows leave above the finger.
      seed([gym, todo, ...oneOffs('cardio', 30)]);
      var robot = await open(tester);
      for (var i = 0; i < 2; i++) {
        robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
        await tester.pump();
      }
      expect(robot.group(ReportCard.categories, 'cardio'), findsNothing);
      final footer = footerRect(tester, robot);

      seed([gym, todo]);
      await tester.pumpAndSettle();
      expect(robot.nav.subtitle, isNot(' '), reason: 'the refold landed');
      expect(footerRect(tester, robot).top, footer.top);
      final pixels = robot.scroll.offset;
      final extent = robot.scroll.position.maxScrollExtent;
      expect(extent, pixels);

      await tester.pumpWidget(const SizedBox.shrink());
      robot = await open(tester);
      robot.scroll.jumpTo(pixels);
      await tester.pump();
      expect(robot.scroll.position.maxScrollExtent, extent);
    });

    testWidgets('a step after a mark at the end releases the slack the mark '
        'left: the new period ends where a fresh page does (D40)', (
      tester,
    ) async {
      var robot = await atTheEnd(tester, [5, 6]);
      final offset = robot.scroll.offset;
      await markPresent(tester, robot, 6, left: [5]);
      expect(robot.scroll.offset, offset);
      expect(robot.scroll.position.maxScrollExtent, offset, reason: 'held');

      await robot.tapId(SemanticsIds.reportNavPrevious);
      await tester.pumpAndSettle();
      expect(robot.nav.title, 'February 2026');
      final pixels = robot.scroll.offset;
      final extent = robot.scroll.position.maxScrollExtent;

      await tester.pumpWidget(const SizedBox.shrink());
      robot = await open(tester, period: const OverviewMonthPeriod(2026, 2));
      robot.scroll.jumpTo(pixels);
      await tester.pump();
      expect(robot.scroll.offset, pixels);
      expect(robot.scroll.position.maxScrollExtent, extent);
    });

    testWidgets('at the end of the page a keyboard raised and lowered under '
        'a sheet moves nothing, with slack held from a mark (D40)', (
      tester,
    ) async {
      final keyboard = ValueNotifier(EdgeInsets.zero);
      addTearDown(keyboard.dispose);
      final robot = await atTheEnd(tester, [5, 6], viewInsets: keyboard);
      // The mark leaves a row's room; the raised keyboard's padding drains
      // it, and the lowered one would let the clamp take that row.
      await markPresent(tester, robot, 6, left: [5]);
      final offset = robot.scroll.offset;
      expect(robot.scroll.position.maxScrollExtent, offset, reason: 'held');
      final footer = footerRect(tester, robot);

      keyboard.value = const EdgeInsets.only(bottom: 300);
      await tester.pump();
      expect(robot.bodyPadding.bottom, FormMetrics.bodyBottom + 300);
      expect(footerRect(tester, robot), footer);

      keyboard.value = EdgeInsets.zero;
      await tester.pump();
      expect(robot.bodyPadding.bottom, FormMetrics.bodyBottom);
      expect(robot.scroll.offset, offset);
      expect(footerRect(tester, robot), footer);
      await tester.pumpAndSettle();
      expect(footerRect(tester, robot), footer);
    });

    /// The extent a fresh page of the same state has at [pixels], on
    /// [period] (March when null): the content's own, no room left over.
    Future<double> freshExtent(
      WidgetTester tester,
      double pixels, {
      OverviewPeriod? period,
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final robot = period == null
          ? await open(tester)
          : await open(tester, period: period);
      robot.scroll.jumpTo(pixels);
      await tester.pump();
      expect(robot.scroll.offset, pixels);
      return robot.scroll.position.maxScrollExtent;
    }

    /// March over Gym, the to-do and Cardio's 30 one-offs, the page at the
    /// end of its scroll, where Cardio's group lies above the viewport.
    Future<ReportRobot> cardioAtTheEnd(
      WidgetTester tester, {
      ValueListenable<EdgeInsets>? viewInsets,
    }) async {
      seed([gym, todo, ...oneOffs('cardio', 30)]);
      final robot = await open(tester, viewInsets: viewInsets);
      for (var i = 0; i < 2; i++) {
        robot.scroll.jumpTo(robot.scroll.position.maxScrollExtent);
        await tester.pump();
      }
      expect(robot.group(ReportCard.categories, 'cardio'), findsNothing);
      return robot;
    }

    testWidgets('a report offstage under a route hears a keyboard raised and '
        'lowered and a refold of the same look: back on stage the footer '
        'holds and the page ends where a fresh one does (D42)', (tester) async {
      final keyboard = ValueNotifier(EdgeInsets.zero);
      addTearDown(keyboard.dispose);
      final robot = await cardioAtTheEnd(tester, viewInsets: keyboard);
      final footer = footerRect(tester, robot);
      final navigator = AppNavigator.navigatorKey.currentState!;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();

      keyboard.value = const EdgeInsets.only(bottom: 300);
      await tester.pump();
      keyboard.value = EdgeInsets.zero;
      await tester.pump();
      seed([gym, todo]);
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        (robot.state as ReportReady).report.categories.map((g) => g.categoryId),
        isNot(contains('cardio')),
        reason: 'the refold landed',
      );
      expect(footerRect(tester, robot).top, footer.top);
      final pixels = robot.scroll.offset;
      final extent = robot.scroll.position.maxScrollExtent;
      expect(await freshExtent(tester, pixels), extent);
    });

    testWidgets('a refold of the same look heard as the keyboard closes '
        'credits the keyboard alone: the footer holds and the page ends '
        'where a fresh one does (D42)', (tester) async {
      final keyboard = ValueNotifier(EdgeInsets.zero);
      addTearDown(keyboard.dispose);
      final robot = await cardioAtTheEnd(tester, viewInsets: keyboard);
      final footer = footerRect(tester, robot);
      keyboard.value = const EdgeInsets.only(bottom: 300);
      await tester.pump();

      seed([gym, todo]);
      await tester.idle();
      keyboard.value = EdgeInsets.zero;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        (robot.state as ReportReady).report.categories.map((g) => g.categoryId),
        isNot(contains('cardio')),
        reason: 'the refold landed',
      );
      expect(footerRect(tester, robot).top, footer.top);
      final pixels = robot.scroll.offset;
      final extent = robot.scroll.position.maxScrollExtent;
      expect(await freshExtent(tester, pixels), extent);
    });

    testWidgets('a step landing in the frame the keyboard closes leaves no '
        'room under the new footer: the release wins (D42)', (tester) async {
      final keyboard = ValueNotifier(EdgeInsets.zero);
      addTearDown(keyboard.dispose);
      final robot = await atTheEnd(tester, [5, 6], viewInsets: keyboard);
      await markPresent(tester, robot, 6, left: [5]);
      expect(
        robot.scroll.position.maxScrollExtent,
        robot.scroll.offset,
        reason: 'held',
      );
      keyboard.value = const EdgeInsets.only(bottom: 300);
      await tester.pump();

      // The step's fold is held, then lands with the keyboard's close: one
      // frame draws February and the smaller clearance.
      final held = gate = Completer<void>();
      await robot.tapId(SemanticsIds.reportNavPrevious);
      gate = null;
      held.complete();
      await tester.idle();
      keyboard.value = EdgeInsets.zero;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(robot.nav.title, 'February 2026');
      final pixels = robot.scroll.offset;
      final extent = robot.scroll.position.maxScrollExtent;
      expect(
        await freshExtent(
          tester,
          pixels,
          period: const OverviewMonthPeriod(2026, 2),
        ),
        extent,
      );
    });

    testWidgets('a mark whose write never lands arms nothing: a refold of the '
        'same look removing a group above leaves the shrink to the clamp '
        '(D42)', (tester) async {
      seed([gym, todo, ...oneOffs('cardio', 30)]);
      final robot = await atTheEnd(tester, [5, 6]);
      expect(robot.group(ReportCard.categories, 'cardio'), findsNothing);
      final footer = footerRect(tester, robot);
      // The recording bloc keeps the mark and emits nothing: a failed write.
      await tester.tap(
        robot.byId(SemanticsIds.reportRowPresence(gym.id, march(6))),
      );
      await tester.pump();
      expect((bloc as _RecordingCalendarBloc).marks, hasLength(1));

      seed([gym, todo]);
      await tester.pumpAndSettle();
      expect(robot.row(gym.id, march(6)), findsOneWidget, reason: 'unmarked');
      expect(footerRect(tester, robot).top, footer.top);
      final pixels = robot.scroll.offset;
      final extent = robot.scroll.position.maxScrollExtent;
      expect(extent, pixels);
      expect(await freshExtent(tester, pixels), extent);
    });

    testWidgets('a refold of the same look between a mark and its own refold '
        'leaves the mark waiting: its refold still holds the MISSED label '
        '(D42)', (tester) async {
      final robot = await atTheEnd(tester, [5, 6]);
      final offset = robot.scroll.offset;
      final label = tester.getRect(find.text('MISSED'));
      await tester.tap(
        robot.byId(SemanticsIds.reportRowPresence(gym.id, march(6))),
      );
      await tester.pump();

      // Another write's revision: a new report that draws the same rows.
      seed([gym, todo], presenceRevision: 1);
      await tester.pumpAndSettle();
      expect(robot.row(gym.id, march(6)), findsOneWidget);
      expect(tester.getRect(find.text('MISSED')), label);

      EventPresence.updateCache(
        byEvent: {
          gym.id: {
            march(6): PresenceStatus.present,
            march(5): PresenceStatus.missed,
          },
        },
      );
      (bloc as _RecordingCalendarBloc).landMark();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(robot.row(gym.id, march(6)), findsNothing);
      expect(robot.scroll.offset, offset);
      expect(tester.getRect(find.text('MISSED')), label);
    });

    testWidgets('a mark clicks once with haptics on and never with them off', (
      tester,
    ) async {
      final clicks = <Object?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') clicks.add(call.arguments);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      EventPresence.updateCache(
        byEvent: {
          gym.id: {march(5): PresenceStatus.missed},
        },
      );
      Future<void> mark() async {
        final robot = ReportRobot(tester);
        final button = robot.byId(
          SemanticsIds.reportRowPresence(gym.id, march(5)),
        );
        await robot.reveal(button);
        await tester.tap(button);
        await tester.pump();
      }

      await settings.setHapticFeedback(true);
      await open(tester);
      await mark();
      expect(clicks, ['HapticFeedbackType.selectionClick']);
      await tester.pumpWidget(const SizedBox.shrink());

      clicks.clear();
      await settings.setHapticFeedback(false);
      await open(tester);
      await mark();
      expect((bloc as _RecordingCalendarBloc).marks, hasLength(2));
      expect(clicks, isEmpty);
    });

    testWidgets('a row\'s detail sheet gets the stored custom palette', (
      tester,
    ) async {
      await db.userSettingsDao.setValue(
        SettingsKeys.markdownCustomColors,
        'brand=ff112233',
      );
      final stored = (await settings.getCalendarReportSettings(
        today: today,
      )).palette;
      final robot = await open(tester);
      final row = robot.row(todo.id, march(10));
      await robot.reveal(row);
      await robot.openSheet(row);
      final palette = robot.detailSheet!.colorPalette;
      expect(palette, stored);
      expect(palette.source, 'brand=ff112233');
      await robot.closeSheet();
    });

    testWidgets('a fold that throws after a mark brings the last Ready back '
        '(D36), whose Missed still lists the row: the mark waits on, and a '
        'repeat tap is dropped until a report folds the row away (D42)', (
      tester,
    ) async {
      final recording = bloc as _RecordingCalendarBloc;
      final failing = service = _FailingReportService();
      EventPresence.updateCache(
        byEvent: {
          gym.id: {march(5): PresenceStatus.missed},
        },
      );
      final robot = await open(tester);
      final button = robot.byId(
        SemanticsIds.reportRowPresence(gym.id, march(5)),
      );
      await robot.reveal(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(recording.marks, hasLength(1), reason: 'the repeat dropped');

      failing.fail = true;
      recording.landMark();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(failing.failures, 1);
      expect(robot.state, isA<ReportReady>());
      expect(button, findsOneWidget, reason: 'the old report is back');

      await tester.tap(button);
      await tester.pump();
      expect(recording.marks, hasLength(1), reason: 'still waiting');

      // The next fold lands with the mark in the store: the row leaves.
      failing.fail = false;
      EventPresence.updateCache(
        byEvent: {
          gym.id: {march(5): PresenceStatus.present},
        },
      );
      recording.landMark();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(button, findsNothing);
    });

    testWidgets('a group closed by its header stays closed through a '
        'presence refold', (tester) async {
      EventPresence.updateCache(
        byEvent: {
          gym.id: {
            march(5): PresenceStatus.missed,
            march(6): PresenceStatus.missed,
          },
        },
      );
      final robot = await open(tester, surface: tall);
      await robot.tapId(SemanticsIds.reportGroup('categories', 'gym'));
      final routine = robot.byId(SemanticsIds.reportRoutine(gym.id));
      expect(routine, findsNothing);

      await markPresent(tester, robot, 5, left: [6]);
      expect(robot.row(gym.id, march(5)), findsNothing);
      expect(robot.row(gym.id, march(6)), findsOneWidget);
      expect(routine, findsNothing);
      expect(glyphTurns(tester, robot, 'gym'), 0);
    });

    testWidgets('the Categories and the Missed Gym groups fold on their own', (
      tester,
    ) async {
      final robot = await open(tester, surface: tall);
      final routine = robot.byId(SemanticsIds.reportRoutine(gym.id));
      final missed = robot.row(gym.id, march(5));
      expect(routine, findsOneWidget);
      expect(missed, findsOneWidget);

      await robot.tapId(SemanticsIds.reportGroup('categories', 'gym'));
      expect(routine, findsNothing);
      expect(missed, findsOneWidget);

      await robot.tapId(SemanticsIds.reportGroup('missed', 'gym'));
      expect(missed, findsNothing);
      expect(routine, findsNothing);

      await robot.tapId(SemanticsIds.reportGroup('categories', 'gym'));
      expect(routine, findsOneWidget);
      expect(missed, findsNothing);
    });

    testWidgets('a span across months writes the month on a row: "Thu 29 '
        'Oct"; the start follows the 24-hour switch', (tester) async {
      seed([
        CalendarEvent(
          id: 'e-run',
          title: 'Run',
          categoryId: 'cardio',
          startDate: DateTime.utc(2026, 10, 29),
          rule: const OneTimeRecurrence(),
          time: const EventTime(startMinute: 17 * 60, durationMinutes: 60),
        ),
      ]);
      final span = OverviewCustomPeriod(
        DateTime.utc(2026, 10, 15),
        DateTime.utc(2026, 11, 15),
      );
      Finder subtitle(Pattern text) => find.descendant(
        of: find.bySemanticsIdentifier(
          SemanticsIds.reportRow('e-run', DateTime.utc(2026, 10, 29)),
        ),
        matching: find.textContaining(text, findRichText: true),
      );

      await open(tester, period: span, alwaysUse24HourFormat: true);
      expect(subtitle('Thu 29 Oct'), findsOneWidget);
      expect(subtitle('17:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      await open(tester, period: span, alwaysUse24HourFormat: false);
      expect(subtitle('Thu 29 Oct'), findsOneWidget);
      expect(subtitle(RegExp(r'5:00\sPM')), findsOneWidget);
      expect(subtitle('17:00'), findsNothing);
    });

    testWidgets('Ahead\'s Show as list starts the day after the counted end', (
      tester,
    ) async {
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 10, 1),
          DateTime.utc(2027, 6, 30),
        ),
      );
      final report = (robot.state as ReportReady).report;
      expect(report.countedTo, today);
      final more = robot.groupMore(ReportCard.ahead, 'gym');
      await robot.reveal(more);
      await tester.tap(more);
      await tester.pump();
      final look = (await robot.showAsListAndLeave(
        id: SemanticsIds.reportGroupList('ahead', 'gym'),
      ))!;
      expect(look.start, DateTime.utc(2026, 10, 31));
      expect(look.end, DateTime.utc(2027, 6, 30));
      expect(look.categoryIds, {'gym'});
    });

    group('a row tap opens the detail sheet in place', () {
      testWidgets('a dated row on its event and day; ✕ returns to the page '
          'with the offset held', (tester) async {
        final robot = await open(tester);
        final row = robot.row(todo.id, march(10));
        await robot.reveal(row);
        // Off the end, where a jump past the lists' estimated extent would
        // be corrected by the next layout whatever the sheet did.
        robot.scroll.jumpTo(robot.scroll.offset - 20);
        await tester.pump();
        final offset = robot.scroll.offset;

        await robot.openSheet(row);
        final sheet = robot.detailSheet!;
        expect(sheet.event.id, todo.id);
        expect(sheet.event.title, 'Tax form');
        expect(sheet.day, march(10));

        await robot.closeSheet();
        expect(robot.detailSheet, isNull);
        expect(robot.scroll.offset, offset);
      });

      testWidgets('a routine row opens on its latest day', (tester) async {
        final robot = await open(tester);
        final report = (robot.state as ReportReady).report;
        final latest = report.categories
            .firstWhere((group) => group.categoryId == 'gym')
            .rows
            .whereType<ReportRoutineRow>()
            .single
            .latestDay;
        expect(latest, march(31));

        await robot.openSheet(robot.byId(SemanticsIds.reportRoutine(gym.id)));
        final sheet = robot.detailSheet!;
        expect(sheet.event.id, gym.id);
        expect(sheet.day, latest);
      });

      testWidgets('a second tap while the sheet opens is ignored', (
        tester,
      ) async {
        final robot = await open(tester);
        final row = robot.row(todo.id, march(10));
        await robot.reveal(row);
        // Twice in one frame, before the sheet's barrier is laid out to
        // catch the second: the guard is what stops it.
        final tap = tester
            .widget<InkWell>(
              find.descendant(of: row, matching: find.byType(InkWell)).first,
            )
            .onTap!;
        tap();
        tap();
        await tester.pumpAndSettle();
        expect(find.byType(EventDetailSheet), findsOneWidget);
        await robot.closeSheet();
        expect(robot.detailSheet, isNull);
      });

      testWidgets('a row whose event has gone opens nothing', (tester) async {
        final robot = await open(tester);
        final row = robot.row(todo.id, march(10));
        await robot.reveal(row);
        // The delete arrives; its refold is held, so the old report — the
        // row with it — is still drawn, undimmed.
        gate = Completer<void>();
        seed([gym]);
        await tester.pump();
        expect(robot.state, isA<ReportFolding>());
        expect(robot.bodyAbsorbsTaps, isFalse);

        await tester.tap(row);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(robot.detailSheet, isNull);

        // The control: in the same held refold, a row whose event is still
        // loaded opens. Its tap is called straight, past the dim that has
        // come up since.
        expect(robot.state, isA<ReportFolding>());
        // Above the viewport by now, in the list's cache.
        tester
            .widget<FormPickerRow>(
              find.byWidgetPredicate(
                (w) =>
                    w is FormPickerRow &&
                    w.identifier == SemanticsIds.reportRoutine(gym.id),
                skipOffstage: false,
              ),
            )
            .onTap!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(robot.detailSheet?.event.id, gym.id);
        gate!.complete();
        gate = null;
        await tester.pumpAndSettle();
        await robot.closeSheet();
      });
    });

    group('a Keep on the alarm page', () {
      testWidgets('pending at open is served after the first frame: a reload '
          'asked, the notice left standing', (tester) async {
        final recording = bloc as _RecordingCalendarBloc;
        AlertKeepNotice.instance.publish();
        await open(tester);
        expect(recording.loads, 1);
        expect(AlertKeepNotice.instance.hasPending, isTrue);
      });

      testWidgets('published while open asks a reload and never takes the '
          'notice', (tester) async {
        final recording = bloc as _RecordingCalendarBloc;
        await open(tester);
        expect(recording.loads, 0);

        AlertKeepNotice.instance.publish();
        await tester.pump();
        expect(recording.loads, 1);
        expect(AlertKeepNotice.instance.hasPending, isTrue);
      });

      testWidgets('already taken by a calendar beneath asks nothing', (
        tester,
      ) async {
        final recording = bloc as _RecordingCalendarBloc;
        void calendarBeneath() => AlertKeepNotice.instance.take();
        AlertKeepNotice.instance.addListener(calendarBeneath);
        addTearDown(
          () => AlertKeepNotice.instance.removeListener(calendarBeneath),
        );
        await open(tester);

        AlertKeepNotice.instance.publish();
        await tester.pump();
        expect(recording.loads, 0);
        expect(AlertKeepNotice.instance.hasPending, isFalse);
      });
    });

    testWidgets('a group\'s Show as list, past 200 rows, hands the overview '
        'the span and its category', (tester) async {
      seed([
        gym,
        CalendarEvent(
          id: 'e-walk',
          title: 'Walk',
          categoryId: 'rest',
          startDate: DateTime.utc(2026, 1, 1),
          rule: const DailyRecurrence(),
        ),
      ]);
      final robot = await open(
        tester,
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 9, 30),
        ),
        categoryIds: {'rest'},
      );
      final more = robot.groupMore(ReportCard.categories, 'rest');
      await tester.ensureVisible(more);
      await tester.pump();
      await tester.tap(more);
      await tester.pump();
      final list = robot.byId(
        SemanticsIds.reportGroupList('categories', 'rest'),
      );
      await tester.scrollUntilVisible(list, 600);
      final look = (await robot.showAsListAndLeave(
        id: SemanticsIds.reportGroupList('categories', 'rest'),
      ))!;
      expect(look.start, DateTime.utc(2026, 1, 1));
      expect(look.end, DateTime.utc(2026, 9, 30));
      expect(look.categoryIds, {'rest'});
    });

    testWidgets('de at 2.0 on 360 × 780 lays the three cards out; the dark '
        'theme draws them; one Scrollable', (tester) async {
      EventPresence.updateCache(
        byEvent: {
          gym.id: {DateTime.utc(2026, 10, 5): PresenceStatus.missed},
        },
      );
      var robot = await open(
        tester,
        period: const OverviewMonthPeriod(2026, 10),
        locale: const Locale('de'),
        textScale: 2.0,
      );
      for (final card in ReportCard.values) {
        await tester.scrollUntilVisible(robot.group(card, 'gym'), 200);
        expect(tester.takeException(), isNull, reason: card.name);
      }
      await tester.scrollUntilVisible(
        robot.byId(SemanticsIds.reportShowList),
        200,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      robot = await open(
        tester,
        period: const OverviewMonthPeriod(2026, 10),
        brightness: Brightness.dark,
        surface: tall,
      );
      for (final card in ReportCard.values) {
        expect(robot.group(card, 'gym'), findsOneWidget, reason: card.name);
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });
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
