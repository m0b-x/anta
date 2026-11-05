import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/calendar_report/calendar_report_bloc.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/overview_view.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/report_cards.dart';
import 'package:anta/models/report_period_choice.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';

import '../database/support/db_test_support.dart';

/// Counts the folds asked of it and answers each with a canned report of
/// the span asked for, so a case reads what the bloc requested.
class _FakeReportService extends CalendarReportService {
  final List<ReportRequest> requests = [];

  /// Set to make every fold throw it.
  Object? failWith;

  @override
  CalendarReport report(ReportRequest request) {
    final failure = failWith;
    if (failure != null) throw failure;
    requests.add(request);
    return CalendarReport(
      span: request.span,
      today: request.today,
      tense: CalendarReport.tenseOf(span: request.span, today: request.today),
      countedTo: CalendarReport.countedToOf(
        span: request.span,
        today: request.today,
      ),
      previousSpan: request.previousSpan,
      events: const {},
      tiles: [ReportTileValue(tile: ReportTile.events, value: requests.length)],
      skippedDays: 0,
      aheadCount: 0,
      categories: const [],
      missed: const [],
      ahead: const [],
    );
  }
}

/// The real service, recording what it was asked, so a case reads both the
/// request and the real fold.
class _RecordingReportService extends CalendarReportService {
  final List<ReportRequest> requests = [];

  @override
  CalendarReport report(ReportRequest request) {
    requests.add(request);
    return super.report(request);
  }
}

/// The report's bloc against a fake service and the real settings and saved
/// views over an in-memory database: what it emits, what it asks the
/// service, what it persists.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late OverviewViewService views;
  late CalendarBloc calendar;

  final today = DateTime.utc(2026, 10, 30);
  DateTime clock() => DateTime(2026, 10, 30, 10);

  final gym = CalendarEvent(
    id: 'gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
  );
  final events = [gym];
  final loaded = CalendarPageLoaded(
    allEvents: events,
    focusedDay: today,
    selectedDay: today,
  );

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    OverviewViewService.reset();
    views = await OverviewViewService.forTesting(db);
    calendar = CalendarBloc(service: Completer<CalendarEventService>().future);
  });

  tearDown(() async {
    await calendar.close();
    SettingsService.reset();
    OverviewViewService.reset();
    await db.close();
  });

  CalendarReportBloc build(
    CalendarReportService service, {
    FutureOr<SettingsService>? settingsSeed,
    FutureOr<OverviewViewService>? viewsSeed,
    Future<void> Function()? nextFrame,
  }) => CalendarReportBloc(
    service: service,
    calendar: calendar,
    settings: settingsSeed ?? settings,
    views: viewsSeed ?? views,
    clock: clock,
    // No binding here: a fold waits on nothing but the event queue.
    nextFrame: nextFrame ?? () async {},
  );

  void loadCalendar([CalendarPageLoaded? state]) {
    // ignore: invalid_use_of_visible_for_testing_member
    calendar.emit(state ?? loaded);
  }

  /// Opens [bloc] over a loaded calendar and waits for its first report.
  Future<List<ReportState>> openReady(
    CalendarReportBloc bloc, {
    ReportOpened opened = const ReportOpened(),
    CalendarPageLoaded? calendarState,
  }) async {
    loadCalendar(calendarState);
    final states = <ReportState>[];
    bloc.stream.listen(states.add);
    bloc.add(opened);
    await pumpEventQueue();
    expect(bloc.state, isA<ReportReady>());
    return states;
  }

  Future<String?> stored(String key) => db.userSettingsDao.getValue(key);

  test('opens Loading until the calendar has loaded, then folds once: '
      'Folding, then Ready on This month', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    final states = <ReportState>[];
    bloc.stream.listen(states.add);

    bloc.add(const ReportOpened());
    await pumpEventQueue();
    expect(states, [
      const ReportLoading(period: OverviewMonthPeriod(2026, 10)),
    ]);
    expect(service.requests, isEmpty);

    loadCalendar();
    await pumpEventQueue();
    expect(states.skip(1).map((s) => s.runtimeType), [
      ReportFolding,
      ReportReady,
    ]);
    final ready = bloc.state as ReportReady;
    expect(ready.period, const OverviewMonthPeriod(2026, 10));
    expect(ready.home, ready.period);
    expect(ready.categoryIds, isEmpty);
    expect(service.requests, hasLength(1));
    final request = service.requests.single;
    expect(request.span, (
      start: DateTime.utc(2026, 10, 1),
      end: DateTime.utc(2026, 10, 31),
    ));
    expect(request.previousSpan, (
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 9, 30),
    ));
    expect(request.today, today);
    expect(identical(request.events, events), isTrue);
  });

  test('the first fold yields a frame: Folding carries no report', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final folding = states.whereType<ReportFolding>().single;
    expect(folding.previous, isNull);
  });

  test('a step then a step back emits two folds; the real service serves the '
      'step back from its memo', () async {
    final service = CalendarReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    expect(service.foldCount, 1);

    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    expect(
      (bloc.state as ReportReady).period,
      const OverviewMonthPeriod(2026, 9),
    );
    expect(
      (bloc.state as ReportReady).home,
      const OverviewMonthPeriod(2026, 10),
    );
    expect(service.foldCount, 2);

    bloc.add(const ReportStepped(1));
    await pumpEventQueue();
    final back = bloc.state as ReportReady;
    expect(back.period, back.home);
    expect(service.foldCount, 2, reason: 'October is a memo hit');
    expect(states.whereType<ReportReady>(), hasLength(3));
    // A step is a look: nothing is written.
    expect(await stored(SettingsKeys.reportPeriod), isNull);
  });

  test('a refold shows the previous report while it runs', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final first = (bloc.state as ReportReady).report;
    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    final folding = states.whereType<ReportFolding>().last;
    expect(identical(folding.previous, first), isTrue);
  });

  test(
    'a calendar state with the same events and revisions emits nothing',
    () async {
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      final states = await openReady(bloc);
      final before = states.length;

      loadCalendar(loaded.copyWith(selectedDay: DateTime.utc(2026, 10, 12)));
      await pumpEventQueue();
      expect(states, hasLength(before));
      expect(service.requests, hasLength(1));
    },
  );

  test('a presence bump refolds exactly once', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final before = states.length;

    loadCalendar(loaded.copyWith(presenceRevision: 1, occurrenceRevision: 1));
    await pumpEventQueue();
    expect(states.skip(before).map((s) => s.runtimeType), [
      ReportFolding,
      ReportReady,
    ]);
    expect(service.requests, hasLength(2));
    expect(service.requests.last.presenceRevision, 1);
    expect(service.requests.last.occurrenceRevision, 1);
  });

  test('a pick of a kept period persists it; Last week persists This week '
      '(D36.2)', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(bloc);
    final years = (bloc.state as ReportReady).years;

    bloc.add(
      ReportPeriodPicked(
        ReportPeriodChoice.thisWeek.periodFor(
          today: today,
          weekStart: CalendarWeekStart.monday,
          years: years,
        ),
      ),
    );
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), 'thisWeek');
    final week = bloc.state as ReportReady;
    expect(week.period, OverviewWeekPeriod(DateTime.utc(2026, 10, 26)));
    expect(week.home, week.period);

    bloc.add(
      ReportPeriodPicked(
        ReportPeriodChoice.lastWeek.periodFor(
          today: today,
          weekStart: CalendarWeekStart.monday,
          years: years,
        ),
      ),
    );
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), 'thisWeek');
    expect(
      (bloc.state as ReportReady).period,
      OverviewWeekPeriod(DateTime.utc(2026, 10, 19)),
    );
  });

  test('Last and Next month persist This month; a Custom pick clears the '
      'key', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(bloc);
    final years = (bloc.state as ReportReady).years;
    OverviewPeriod periodOf(ReportPeriodChoice choice) => choice.periodFor(
      today: today,
      weekStart: CalendarWeekStart.monday,
      years: years,
    );

    bloc.add(ReportPeriodPicked(periodOf(ReportPeriodChoice.thisYear)));
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), 'thisYear');

    bloc.add(ReportPeriodPicked(periodOf(ReportPeriodChoice.lastMonth)));
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), 'thisMonth');
    expect(
      (bloc.state as ReportReady).period,
      const OverviewMonthPeriod(2026, 9),
    );

    bloc.add(ReportPeriodPicked(periodOf(ReportPeriodChoice.thisYear)));
    await pumpEventQueue();
    bloc.add(ReportPeriodPicked(periodOf(ReportPeriodChoice.nextMonth)));
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), 'thisMonth');

    bloc.add(
      ReportPeriodPicked(
        OverviewCustomPeriod(
          DateTime.utc(2026, 3, 1),
          DateTime.utc(2026, 3, 9),
        ),
      ),
    );
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), isNull);
  });

  test('Last year shows the year before and persists This year', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    // A run in 2025 reaches the calendar's first year back to it.
    final run = CalendarEvent(
      id: 'run',
      title: 'Run',
      categoryId: 'gym',
      startDate: DateTime.utc(2025, 3, 4),
      rule: const OneTimeRecurrence(),
    );
    await openReady(
      bloc,
      calendarState: CalendarPageLoaded(
        allEvents: [gym, run],
        focusedDay: today,
        selectedDay: today,
      ),
    );
    final years = (bloc.state as ReportReady).years;

    bloc.add(
      ReportPeriodPicked(
        ReportPeriodChoice.lastYear.periodFor(
          today: today,
          weekStart: CalendarWeekStart.monday,
          years: years,
        ),
      ),
    );
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportPeriod), 'thisYear');
    final ready = bloc.state as ReportReady;
    expect(ready.period, const OverviewYearPeriod(2025));
    expect(ready.home, ready.period);
  });

  test('a pick equal to the shown period still re-emits Ready: home and '
      'Today follow (D36.7)', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    await openReady(bloc);
    final years = (bloc.state as ReportReady).years;

    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    expect(
      (bloc.state as ReportReady).home,
      const OverviewMonthPeriod(2026, 10),
    );
    final folds = service.requests.length;

    bloc.add(
      ReportPeriodPicked(
        ReportPeriodChoice.lastMonth.periodFor(
          today: today,
          weekStart: CalendarWeekStart.monday,
          years: years,
        ),
      ),
    );
    await pumpEventQueue();
    final ready = bloc.state as ReportReady;
    expect(ready.home, const OverviewMonthPeriod(2026, 9));
    expect(ready.period, ready.home, reason: 'Today disabled');
    expect(service.requests, hasLength(folds), reason: 'a memo key hit');
  });

  test('a fold that throws re-emits the last Ready and undoes the pick '
      '(D36.6)', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final first = bloc.state as ReportReady;

    service.failWith = StateError('fold');
    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    expect(states.last, first);
    expect(bloc.state, isNot(isA<ReportFolding>()));

    service.failWith = null;
    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    expect(
      (bloc.state as ReportReady).period,
      const OverviewMonthPeriod(2026, 9),
      reason: 'the failed step left the period where it was',
    );
  });

  test('a first fold that throws goes back to Loading', () async {
    final service = _FakeReportService()..failWith = StateError('fold');
    final bloc = build(service);
    addTearDown(bloc.close);
    loadCalendar();
    bloc.add(const ReportOpened());
    await pumpEventQueue();
    expect(
      bloc.state,
      const ReportLoading(period: OverviewMonthPeriod(2026, 10)),
    );
  });

  test('an unreadable settings store opens on This month, every '
      'category', () async {
    final seed = Completer<SettingsService>();
    final bloc = build(_FakeReportService(), settingsSeed: seed.future);
    addTearDown(bloc.close);
    loadCalendar();
    bloc.add(const ReportOpened());
    await pumpEventQueue();
    seed.completeError(StateError('unreadable'));
    await pumpEventQueue();
    final ready = bloc.state as ReportReady;
    expect(ready.period, const OverviewMonthPeriod(2026, 10));
    expect(ready.categoryIds, isEmpty);
  });

  test('a burst of calendar states folds once, with the last', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    await openReady(bloc);

    for (var revision = 1; revision <= 3; revision++) {
      loadCalendar(loaded.copyWith(presenceRevision: revision));
    }
    await pumpEventQueue();
    expect(service.requests, hasLength(2));
    expect(service.requests.last.presenceRevision, 3);
  });

  test('an All time look arrives as Last 12 months', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(
      bloc,
      opened: const ReportOpened(
        look: (
          period: OverviewRollingPeriod(OverviewRollingPreset.allTime),
          categoryIds: {},
        ),
      ),
    );
    expect(
      (bloc.state as ReportReady).period,
      const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
    );
  });

  test('a week start changed in the settings moves This week on resume; '
      'a paged week stays', () async {
    await settings.setCalendarReportPeriod(
      OverviewPeriod.thisWeek(
        today: today,
        weekStart: CalendarWeekStart.monday,
      ),
      today: today,
    );
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(bloc);
    expect(
      (bloc.state as ReportReady).period,
      OverviewWeekPeriod(DateTime.utc(2026, 10, 26)),
    );

    await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
    bloc.add(const ReportResumed());
    await pumpEventQueue();
    final ready = bloc.state as ReportReady;
    expect(ready.period, OverviewWeekPeriod(DateTime.utc(2026, 10, 25)));
    expect(ready.home, ready.period);
    expect(ready.weekStart, CalendarWeekStart.sunday);

    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    await settings.setCalendarWeekStart(CalendarWeekStart.monday);
    bloc.add(const ReportResumed());
    await pumpEventQueue();
    expect(
      (bloc.state as ReportReady).period,
      OverviewWeekPeriod(DateTime.utc(2026, 10, 18)),
      reason: 'a week paged away from today stays the seven days it is',
    );
  });

  test('a new day re-reads the week start too', () async {
    await settings.setCalendarReportPeriod(
      OverviewPeriod.thisWeek(
        today: today,
        weekStart: CalendarWeekStart.monday,
      ),
      today: today,
    );
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(bloc);

    await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
    bloc.add(ReportDayChanged(DateTime(2026, 11, 2, 7)));
    await pumpEventQueue();
    final ready = bloc.state as ReportReady;
    expect(ready.period, OverviewWeekPeriod(DateTime.utc(2026, 11, 1)));
    expect(ready.weekStart, CalendarWeekStart.sunday);
  });

  test('close() during a fold ends quietly, folding nothing after', () async {
    final service = _FakeReportService();
    var frame = Completer<void>()..complete();
    final bloc = build(service, nextFrame: () => frame.future);
    await openReady(bloc);
    final folds = service.requests.length;

    frame = Completer<void>();
    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    expect(bloc.state, isA<ReportFolding>());

    final closing = bloc.close();
    await pumpEventQueue();
    frame.complete();
    await closing;
    await pumpEventQueue();
    expect(bloc.isClosed, isTrue);
    expect(service.requests, hasLength(folds));
  });

  test('a category pick always persists, the empty set included', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    await openReady(bloc);

    bloc.add(const ReportCategoriesPicked({'gym', 'cardio'}));
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportCategoryIds), 'cardio,gym');
    expect(service.requests.last.categoryIds, {'gym', 'cardio'});
    expect((bloc.state as ReportReady).categoryIds, {'gym', 'cardio'});

    bloc.add(const ReportCategoriesPicked({}));
    await pumpEventQueue();
    expect(await stored(SettingsKeys.reportCategoryIds), '');
  });

  test('the overview\'s look sets the period and the categories, persisting '
      'a kept period and the categories', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    await openReady(
      bloc,
      opened: const ReportOpened(
        look: (period: OverviewYearPeriod(2026), categoryIds: {'gym'}),
      ),
    );
    final ready = bloc.state as ReportReady;
    expect(ready.period, const OverviewYearPeriod(2026));
    expect(ready.home, ready.period);
    expect(ready.categoryIds, {'gym'});
    expect(service.requests.single.categoryIds, {'gym'});
    expect(await stored(SettingsKeys.reportPeriod), 'thisYear');
    expect(await stored(SettingsKeys.reportCategoryIds), 'gym');
  });

  test(
    'a look on a span that is not kept leaves the stored period alone',
    () async {
      await settings.setCalendarReportPeriod(
        const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
        today: today,
      );
      final bloc = build(_FakeReportService());
      addTearDown(bloc.close);
      final span = OverviewCustomPeriod(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 20),
      );
      await openReady(
        bloc,
        opened: ReportOpened(look: (period: span, categoryIds: const {})),
      );
      expect((bloc.state as ReportReady).period, span);
      expect(await stored(SettingsKeys.reportPeriod), 'preset:last90Days');
    },
  );

  test('a report digest\'s look on an open report sets the period, the home '
      'and the categories; the categories persist, the period never', () async {
    await settings.setCalendarReportPeriod(
      const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
      today: today,
    );
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    await openReady(bloc);
    final lastWeek = OverviewWeekPeriod(DateTime.utc(2026, 10, 19));

    bloc.add(ReportLookArrived((period: lastWeek, categoryIds: {'gym'})));
    await pumpEventQueue();

    final ready = bloc.state as ReportReady;
    expect(ready.period, lastWeek);
    expect(ready.home, lastWeek);
    expect(ready.categoryIds, {'gym'});
    expect(service.requests.last.span, (
      start: DateTime.utc(2026, 10, 19),
      end: DateTime.utc(2026, 10, 25),
    ));
    expect(service.requests.last.categoryIds, {'gym'});
    expect(await stored(SettingsKeys.reportCategoryIds), 'gym');
    expect(await stored(SettingsKeys.reportPeriod), 'preset:last90Days');
  });

  test(
    'the stored period and categories are what a plain open shows',
    () async {
      await settings.setCalendarReportPeriod(
        const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
        today: today,
      );
      await settings.setCalendarReportCategories({'cardio'});
      final bloc = build(_FakeReportService());
      addTearDown(bloc.close);
      await openReady(bloc);
      final ready = bloc.state as ReportReady;
      expect(
        ready.period,
        const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
      );
      expect(ready.categoryIds, {'cardio'});
    },
  );

  test(
    'a new day refolds with the new today and moves This month on',
    () async {
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      await openReady(bloc);

      bloc.add(ReportDayChanged(DateTime(2026, 11, 2, 7)));
      await pumpEventQueue();
      final ready = bloc.state as ReportReady;
      expect(ready.today, DateTime.utc(2026, 11, 2));
      expect(ready.period, const OverviewMonthPeriod(2026, 11));
      expect(service.requests.last.today, DateTime.utc(2026, 11, 2));
    },
  );

  test('a custom pick over 366 days keeps its last 366', () async {
    final service = _FakeReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    await openReady(bloc);

    bloc.add(
      ReportPeriodPicked(
        OverviewCustomPeriod(
          DateTime.utc(2025, 1, 1),
          DateTime.utc(2026, 6, 30),
        ),
      ),
    );
    await pumpEventQueue();
    final period = (bloc.state as ReportReady).period as OverviewCustomPeriod;
    expect(period.end, DateTime.utc(2026, 6, 30));
    expect(period.end.difference(period.start).inDays + 1, 366);
    expect(service.requests.last.span.start, period.start);
  });

  test('Today returns a stepped report to its home', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(bloc);
    bloc.add(const ReportStepped(-1));
    bloc.add(const ReportStepped(-1));
    await pumpEventQueue();
    expect(
      (bloc.state as ReportReady).period,
      const OverviewMonthPeriod(2026, 8),
    );

    bloc.add(const ReportHomePressed());
    await pumpEventQueue();
    expect(
      (bloc.state as ReportReady).period,
      const OverviewMonthPeriod(2026, 10),
    );
  });

  test('every shown state carries the palette and the haptic switch, and a '
      'resume re-reads both', () async {
    await settings.setHapticFeedback(false);
    await db.userSettingsDao.setValue(
      SettingsKeys.markdownCustomColors,
      'brand=ff112233',
    );
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final shown = states.whereType<ReportShown>().toList();
    expect(shown.whereType<ReportFolding>(), isNotEmpty);
    for (final state in shown) {
      expect(state.palette.source, 'brand=ff112233');
      expect(state.hapticFeedback, isFalse);
    }

    await settings.setHapticFeedback(true);
    await db.userSettingsDao.deleteValue(SettingsKeys.markdownCustomColors);
    bloc.add(const ReportResumed());
    await pumpEventQueue();
    final ready = bloc.state as ReportReady;
    expect(ready.palette, MarkdownColorPalette.presets);
    expect(ready.hapticFeedback, isTrue);
  });

  test('every shown state carries the stored cards, and a resume re-reads '
      'them without a refold', () async {
    final saved = ReportCards.defaults.toggled(ReportCardKind.missed, false);
    await settings.setReportCards(saved);
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final shown = states.whereType<ReportShown>().toList();
    expect(shown.whereType<ReportFolding>(), isNotEmpty);
    for (final state in shown) {
      expect(state.cards, saved);
    }

    final changed = saved.moved(3, 0).toggled(ReportCardKind.missed, true);
    await settings.setReportCards(changed);
    states.clear();
    bloc.add(const ReportResumed());
    await pumpEventQueue();
    expect(states.whereType<ReportFolding>(), isEmpty);
    final ready = bloc.state as ReportReady;
    expect(ready.cards, changed);
    expect(ready.cards.shown.first, ReportCardKind.totals);
  });

  test('a fresh install shows every card in the page order', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    await openReady(bloc);

    expect((bloc.state as ReportReady).cards, ReportCards.defaults);
  });

  test('every shown state carries the ledger\'s currency, the plain decimal '
      'by default, and a resume re-reads it', () async {
    final bloc = build(_FakeReportService());
    addTearDown(bloc.close);
    var shown = (await openReady(bloc)).whereType<ReportShown>().toList();
    for (final state in shown) {
      expect(state.currencySymbol, '');
      expect(state.currencySuffix, isFalse);
    }

    await settings.setMoneyCurrencySymbol('lei');
    await settings.setMoneyCurrencySuffix(true);
    bloc.add(const ReportResumed());
    await pumpEventQueue();
    final ready = bloc.state as ReportReady;
    expect(ready.currencySymbol, 'lei');
    expect(ready.currencySuffix, isTrue);

    final reopened = build(_FakeReportService());
    addTearDown(reopened.close);
    shown = (await openReady(reopened)).whereType<ReportShown>().toList();
    expect(shown, isNotEmpty);
    for (final state in shown) {
      expect(state.currencySymbol, 'lei');
      expect(state.currencySuffix, isTrue);
    }
  });

  test('a resume with nothing moved emits nothing', () async {
    final service = CalendarReportService();
    final bloc = build(service);
    addTearDown(bloc.close);
    final states = await openReady(bloc);
    final before = states.length;

    bloc.add(const ReportResumed());
    await pumpEventQueue();
    expect(states, hasLength(before));
    expect(service.foldCount, 1);
  });

  group('Compare with (decision H: per visit)', () {
    Future<OverviewView> saveView({
      String name = 'Training',
      Set<String> categoryIds = const {'gym'},
    }) async => (await views.create(
      name: name,
      period: const OverviewYearPeriod(2026),
      options: OverviewListOptions.defaults,
      categoryIds: categoryIds,
    ))!;

    // Events since 2025, so October 2026 has a last year to compare with.
    final reachesLastYear = CalendarPageLoaded(
      allEvents: [
        CalendarEvent(
          id: 'run',
          title: 'Run',
          categoryId: 'gym',
          startDate: DateTime.utc(2025, 1, 1),
          rule: const DailyRecurrence(),
        ),
      ],
      focusedDay: today,
      selectedDay: today,
    );

    test('the first Ready of a visit compares with the previous period, no '
        'view', () async {
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      final states = await openReady(bloc);
      for (final state in states.whereType<ReportShown>()) {
        expect(state.compare, ReportCompare.previous);
        expect(state.compareView, isNull);
      }
      expect(service.requests.single.compare, ReportCompare.previous);
      expect(service.requests.single.compareView, isNull);
    });

    test('Same period last year folds a last-year request, and the real '
        'report compares with a last year that has events', () async {
      final service = _RecordingReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      final since2025 = [
        CalendarEvent(
          id: 'run',
          title: 'Run',
          categoryId: 'gym',
          startDate: DateTime.utc(2025, 1, 1),
          rule: const DailyRecurrence(),
        ),
      ];
      loadCalendar(
        CalendarPageLoaded(
          allEvents: since2025,
          focusedDay: today,
          selectedDay: today,
        ),
      );
      final states = <ReportState>[];
      bloc.stream.listen(states.add);
      bloc.add(const ReportOpened());
      await pumpEventQueue();
      final before = states.length;

      bloc.add(const ReportComparePicked(ReportCompare.lastYear));
      await pumpEventQueue();
      final request = service.requests.last;
      expect(request.compare, ReportCompare.lastYear);
      expect(request.compareView, isNull);
      expect(
        states.skip(before).whereType<ReportFolding>().single.compare,
        ReportCompare.lastYear,
      );
      final ready = bloc.state as ReportReady;
      expect(ready.compare, ReportCompare.lastYear);
      expect(ready.report.compare, ReportCompare.lastYear);
      expect(ready.report.compared, isNotNull);
      expect(ready.report.compared!.span, (
        start: DateTime.utc(2025, 10, 1),
        end: DateTime.utc(2025, 10, 31),
      ));
    });

    test(
      'a view pick folds with the view, and every state carries it',
      () async {
        final view = await saveView();
        final service = _FakeReportService();
        final bloc = build(service);
        addTearDown(bloc.close);
        final states = await openReady(bloc);
        final before = states.length;

        bloc.add(ReportComparePicked(ReportCompare.view, view: view));
        await pumpEventQueue();
        expect(service.requests.last.compare, ReportCompare.view);
        expect(service.requests.last.compareView, view);
        final picked = states.skip(before).whereType<ReportShown>().toList();
        expect(picked.map((s) => s.runtimeType), [ReportFolding, ReportReady]);
        for (final state in picked) {
          expect(state.compare, ReportCompare.view);
          expect(state.compareView, view);
        }
      },
    );

    test(
      'the same pick again folds nothing; a different pick refolds',
      () async {
        final view = await saveView();
        final service = _FakeReportService();
        final bloc = build(service);
        addTearDown(bloc.close);
        final states = await openReady(bloc, calendarState: reachesLastYear);

        bloc.add(const ReportComparePicked(ReportCompare.lastYear));
        await pumpEventQueue();
        expect(service.requests, hasLength(2));
        final settled = states.length;

        bloc.add(const ReportComparePicked(ReportCompare.lastYear));
        await pumpEventQueue();
        expect(service.requests, hasLength(2));
        expect(states, hasLength(settled), reason: 'an equal Ready is dropped');

        bloc.add(ReportComparePicked(ReportCompare.view, view: view));
        await pumpEventQueue();
        expect(service.requests, hasLength(3));
        bloc.add(ReportComparePicked(ReportCompare.view, view: view));
        await pumpEventQueue();
        expect(service.requests, hasLength(3));

        bloc.add(const ReportComparePicked(ReportCompare.previous));
        await pumpEventQueue();
        expect(service.requests, hasLength(4));
        expect(service.requests.last.compare, ReportCompare.previous);
        expect((bloc.state as ReportReady).compare, ReportCompare.previous);
      },
    );

    test('a step, a period pick, Today, a category pick and a calendar '
        'change keep the choice', () async {
      final view = await saveView();
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      await openReady(bloc);
      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();

      void expectKept(String after) {
        expect(
          service.requests.last.compare,
          ReportCompare.view,
          reason: after,
        );
        expect(service.requests.last.compareView, view, reason: after);
        final ready = bloc.state as ReportReady;
        expect(ready.compare, ReportCompare.view, reason: after);
        expect(ready.compareView, view, reason: after);
      }

      bloc.add(const ReportStepped(-1));
      await pumpEventQueue();
      expect(service.requests.last.span.start, DateTime.utc(2026, 9, 1));
      expectKept('a step');

      bloc.add(const ReportHomePressed());
      await pumpEventQueue();
      expect(service.requests.last.span.start, DateTime.utc(2026, 10, 1));
      expectKept('Today');

      bloc.add(const ReportPeriodPicked(OverviewYearPeriod(2026)));
      await pumpEventQueue();
      expect(service.requests.last.span.start, DateTime.utc(2026, 1, 1));
      expectKept('a period pick');

      bloc.add(const ReportCategoriesPicked({'gym'}));
      await pumpEventQueue();
      expect(service.requests.last.categoryIds, {'gym'});
      expectKept('a category pick');

      loadCalendar(loaded.copyWith(presenceRevision: 1));
      await pumpEventQueue();
      expect(service.requests.last.presenceRevision, 1);
      expectKept('a calendar change');
    });

    test(
      'a view the service no longer lists falls back to the previous '
      'period, picked after its deletion or deleted after the pick',
      () async {
        final gone = await saveView(name: 'Gone');
        final kept = await saveView(name: 'Kept');
        await views.delete(gone.id);
        final service = _FakeReportService();
        final bloc = build(service);
        addTearDown(bloc.close);
        await openReady(bloc);

        bloc.add(ReportComparePicked(ReportCompare.view, view: gone));
        await pumpEventQueue();
        expect(service.requests.last.compare, ReportCompare.previous);
        expect(service.requests.last.compareView, isNull);
        var ready = bloc.state as ReportReady;
        expect(ready.compare, ReportCompare.previous);
        expect(ready.compareView, isNull);

        bloc.add(ReportComparePicked(ReportCompare.view, view: kept));
        await pumpEventQueue();
        expect(service.requests.last.compareView, kept);
        await views.delete(kept.id);
        bloc.add(const ReportStepped(-1));
        await pumpEventQueue();
        expect(service.requests.last.compare, ReportCompare.previous);
        expect(service.requests.last.compareView, isNull);
        ready = bloc.state as ReportReady;
        expect(ready.compare, ReportCompare.previous);
        expect(ready.compareView, isNull);

        bloc.add(const ReportHomePressed());
        await pumpEventQueue();
        expect(
          service.requests.last.compare,
          ReportCompare.previous,
          reason: 'the fall-back lasts for the visit',
        );
      },
    );

    test('a view edited in the service is read fresh on the next fold, '
        'which the edit alone refolds', () async {
      final view = await saveView();
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      await openReady(bloc);
      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();
      final folds = service.requests.length;

      await views.update(
        view.copyWith(name: 'Strength', categoryIds: {'gym', 'cardio'}),
      );
      // A calendar state that moves nothing: the edited view alone refolds.
      loadCalendar(loaded.copyWith(selectedDay: DateTime.utc(2026, 10, 12)));
      await pumpEventQueue();
      expect(service.requests, hasLength(folds + 1));
      final fresh = service.requests.last.compareView!;
      expect(fresh.id, view.id);
      expect(fresh.name, 'Strength');
      expect(fresh.categoryIds, {'gym', 'cardio'});
      expect((bloc.state as ReportReady).compareView, fresh);
    });

    test(
      'with no views service a view pick folds the previous period',
      () async {
        final service = _FakeReportService();
        final bloc = CalendarReportBloc(
          service: service,
          calendar: calendar,
          settings: settings,
          clock: clock,
          nextFrame: () async {},
        );
        addTearDown(bloc.close);
        await openReady(bloc);
        bloc.add(
          const ReportComparePicked(
            ReportCompare.view,
            view: OverviewView(
              id: 'v',
              name: 'V',
              period: OverviewYearPeriod(2026),
            ),
          ),
        );
        await pumpEventQueue();
        expect(service.requests.last.compare, ReportCompare.previous);
        expect((bloc.state as ReportReady).compare, ReportCompare.previous);
      },
    );

    test('a fold that throws restores the choice of the last Ready '
        '(D36.6)', () async {
      final view = await saveView();
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      final states = await openReady(bloc);
      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();
      final picked = bloc.state as ReportReady;

      service.failWith = StateError('fold');
      bloc.add(const ReportComparePicked(ReportCompare.previous));
      await pumpEventQueue();
      expect(states.last, picked);

      service.failWith = null;
      bloc.add(const ReportStepped(-1));
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.view);
      expect(service.requests.last.compareView, view);
      final ready = bloc.state as ReportReady;
      expect(ready.compare, ReportCompare.view);
      expect(ready.compareView, view);
    });

    test('a views service that never resolves holds neither the first fold, '
        'a previous-period or last-year pick, nor a later step', () async {
      final service = _FakeReportService();
      final bloc = build(
        service,
        viewsSeed: Completer<OverviewViewService>().future,
      );
      addTearDown(bloc.close);
      await openReady(bloc, calendarState: reachesLastYear);
      expect(service.requests, hasLength(1));

      bloc.add(const ReportComparePicked(ReportCompare.lastYear));
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.lastYear);
      expect((bloc.state as ReportReady).compare, ReportCompare.lastYear);

      bloc.add(const ReportComparePicked(ReportCompare.previous));
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.previous);

      bloc.add(const ReportStepped(-1));
      await pumpEventQueue();
      final ready = bloc.state as ReportReady;
      expect(ready.period, const OverviewMonthPeriod(2026, 9));
      expect(ready.views, isEmpty);
      expect(service.requests, hasLength(4));
    });

    test('a views service that fails folds a view pick as the previous '
        'period', () async {
      final view = await saveView();
      final service = _FakeReportService();
      final bloc = build(
        service,
        viewsSeed: Future<OverviewViewService>.error(StateError('views')),
      );
      addTearDown(bloc.close);
      await openReady(bloc);

      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.previous);
      expect(service.requests.last.compareView, isNull);
      final ready = bloc.state as ReportReady;
      expect(ready.compare, ReportCompare.previous);
      expect(ready.compareView, isNull);
      expect(ready.views, isEmpty);
    });

    test('a resume after the compared view was deleted compares with the '
        'previous period', () async {
      final view = await saveView();
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      await openReady(bloc);
      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();
      expect(service.requests.last.compareView, view);

      await views.delete(view.id);
      bloc.add(const ReportResumed());
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.previous);
      expect(service.requests.last.compareView, isNull);
      final ready = bloc.state as ReportReady;
      expect(ready.compare, ReportCompare.previous);
      expect(ready.compareView, isNull);
      expect(ready.views, isEmpty);
    });

    test('Same period last year on a span whose year before the calendar '
        'does not reach folds the previous period, and the state says '
        'so', () async {
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      // The calendar starts in 2026: October 2026 has no last year.
      final states = await openReady(bloc);
      expect((bloc.state as ReportReady).years.first, 2026);
      final before = states.length;

      bloc.add(const ReportComparePicked(ReportCompare.lastYear));
      await pumpEventQueue();
      expect(service.requests, hasLength(1), reason: 'the first fold again');
      expect(states, hasLength(before), reason: 'an equal Ready is dropped');
      expect((bloc.state as ReportReady).compare, ReportCompare.previous);

      bloc.add(const ReportPeriodPicked(OverviewYearPeriod(2026)));
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.previous);
      expect((bloc.state as ReportReady).compare, ReportCompare.previous);
    });

    test('every shown state carries the saved views; one saved before a '
        'resume reaches the Ready', () async {
      final first = await saveView(name: 'First');
      final service = CalendarReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      final states = await openReady(bloc);
      for (final state in states.whereType<ReportShown>()) {
        expect(state.views, [first]);
      }
      final report = (bloc.state as ReportReady).report;

      final second = await saveView(name: 'Second');
      bloc.add(const ReportResumed());
      await pumpEventQueue();
      final ready = bloc.state as ReportReady;
      expect(ready.views, [first, second]);
      expect(identical(ready.report, report), isTrue, reason: 'a memo hit');
      expect(service.foldCount, 1);
    });

    test('Folding names the choice of the report it draws (D36.9) beside the '
        'new pick', () async {
      final view = await saveView();
      final bloc = build(_FakeReportService());
      addTearDown(bloc.close);
      final states = await openReady(bloc, calendarState: reachesLastYear);

      var before = states.length;
      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();
      var folding = states.skip(before).whereType<ReportFolding>().single;
      expect(folding.previousCompare, ReportCompare.previous);
      expect(folding.previousCompareView, isNull);
      expect(folding.compare, ReportCompare.view);
      expect(folding.compareView, view);

      before = states.length;
      bloc.add(const ReportComparePicked(ReportCompare.lastYear));
      await pumpEventQueue();
      folding = states.skip(before).whereType<ReportFolding>().single;
      expect(folding.previousCompare, ReportCompare.view);
      expect(folding.previousCompareView, view);
      expect(folding.compare, ReportCompare.lastYear);
      expect(folding.compareView, isNull);
    });

    test('a reorder of the saved views does not refold; a rename of the '
        'compared one does', () async {
      final first = await saveView(name: 'First');
      final second = await saveView(name: 'Second');
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      final states = await openReady(bloc);
      bloc.add(ReportComparePicked(ReportCompare.view, view: first));
      await pumpEventQueue();
      final folds = service.requests.length;

      await views.reorder([second.id, first.id]);
      final before = states.length;
      loadCalendar(loaded.copyWith(selectedDay: DateTime.utc(2026, 10, 12)));
      await pumpEventQueue();
      expect(service.requests, hasLength(folds));
      expect(states.skip(before).whereType<ReportFolding>(), isEmpty);
      final reordered = bloc.state as ReportReady;
      expect(reordered.views.map((v) => v.id), [second.id, first.id]);

      final moved = views.views.firstWhere((v) => v.id == first.id);
      await views.update(moved.copyWith(name: 'Renamed'));
      loadCalendar(loaded.copyWith(selectedDay: DateTime.utc(2026, 10, 13)));
      await pumpEventQueue();
      expect(service.requests, hasLength(folds + 1));
      expect(service.requests.last.compareView!.name, 'Renamed');
      expect((bloc.state as ReportReady).compareView!.name, 'Renamed');
    });

    test('after a database switch a resume and a view pick read the new '
        'database\'s saved views', () async {
      await saveView(name: 'Old');
      final service = _FakeReportService();
      final bloc = build(service);
      addTearDown(bloc.close);
      await openReady(bloc);
      expect((bloc.state as ReportReady).views.single.name, 'Old');

      DatabaseLifecycle.notifyDatabaseSwitching();
      // Two open databases on purpose: the one switched from stays open
      // under the settings the bloc already holds.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final switched = await openTestDatabase();
      addTearDown(switched.close);
      final fresh = await OverviewViewService.forTesting(switched);
      final view = (await fresh.create(
        name: 'New',
        period: const OverviewYearPeriod(2026),
        options: OverviewListOptions.defaults,
        categoryIds: const {'gym'},
      ))!;

      bloc.add(const ReportResumed());
      await pumpEventQueue();
      expect((bloc.state as ReportReady).views, [view]);

      bloc.add(ReportComparePicked(ReportCompare.view, view: view));
      await pumpEventQueue();
      expect(service.requests.last.compare, ReportCompare.view);
      expect(service.requests.last.compareView, view);
    });
  });
}
