import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/calendar_report/calendar_report_bloc.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/report_period_choice.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/services/settings_service.dart';

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

/// The report's bloc against a fake service and the real settings over an
/// in-memory database: what it emits, what it asks the service, what it
/// persists.
void main() {
  late AppDatabase db;
  late SettingsService settings;
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
    calendar = CalendarBloc(service: Completer<CalendarEventService>().future);
  });

  tearDown(() async {
    await calendar.close();
    SettingsService.reset();
    await db.close();
  });

  CalendarReportBloc build(
    CalendarReportService service, {
    FutureOr<SettingsService>? settingsSeed,
    Future<void> Function()? nextFrame,
  }) => CalendarReportBloc(
    service: service,
    calendar: calendar,
    settings: settingsSeed ?? settings,
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
  }) async {
    loadCalendar();
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
}
