import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants/calendar_bounds.dart';
import '../../models/agenda_day_list.dart';
import '../../models/calendar_appearance.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_report.dart';
import '../../models/date_range.dart';
import '../../models/overview_period.dart';
import '../../models/report_look.dart';
import '../../models/report_period_choice.dart';
import '../../services/calendar_report_service.dart';
import '../../services/settings_service.dart';
import '../../utils/event_agenda.dart';
import '../../utils/markdown_color_syntax.dart';
import '../calendar/calendar_bloc.dart';
import 'calendar_report_event.dart';
import 'calendar_report_state.dart';

export 'calendar_report_event.dart';
export 'calendar_report_state.dart';

/// The report page's bloc (U): routes the page's picks, listens to the
/// app-wide [CalendarBloc], and folds through its own
/// [CalendarReportService] — owned for the page's life (D30), so the memo
/// dies with the page.
///
/// Folds run in handlers only, never in a build. Events are handled one at a
/// time: a fold yields a frame before it runs (§4.7), and a step pressed in
/// that frame must start from the period the fold settled on.
class CalendarReportBloc extends Bloc<ReportEvent, ReportState> {
  /// [settings] may still be resolving — the page hands over
  /// `SettingsService.getInstance()` unawaited, as DI hands `CalendarBloc`
  /// its service, so `BlocProvider.create` stays synchronous. [clock] is
  /// what today is read from; tests pin it. [nextFrame] is what a fold
  /// waits on before it runs — the end of the next frame; a bloc suite with
  /// no binding passes one that completes at once.
  CalendarReportBloc({
    required CalendarReportService service,
    required CalendarBloc calendar,
    required FutureOr<SettingsService> settings,
    DateTime Function()? clock,
    Future<void> Function()? nextFrame,
  }) : _service = service,
       _calendarBloc = calendar,
       _settingsSeed = settings,
       _clock = clock ?? DateTime.now,
       _nextFrame = nextFrame ?? _endOfFrame,
       super(const ReportLoading()) {
    on<ReportEvent>(_onEvent, transformer: _oneAtATime);
    _calendarSubscription = calendar.stream.listen((state) {
      if (state is CalendarPageLoaded) add(ReportCalendarChanged(state));
    });
  }

  final CalendarReportService _service;
  final CalendarBloc _calendarBloc;
  final FutureOr<SettingsService> _settingsSeed;
  final DateTime Function() _clock;
  final Future<void> Function() _nextFrame;
  late final StreamSubscription<CalendarPageState> _calendarSubscription;

  static Future<void> _endOfFrame() => SchedulerBinding.instance.endOfFrame;

  SettingsService? _settings;
  bool _settingsLoaded = false;
  CalendarPageLoaded? _calendar;
  late DateTime _today = _dayOf(_clock());
  OverviewPeriod? _period;
  OverviewPeriod? _home;
  Set<String> _categoryIds = const {};
  CalendarAppearance _appearance = const CalendarAppearance();
  MarkdownColorPalette _palette = MarkdownColorPalette.presets;
  bool _hapticFeedback = false;

  /// The years of the last events and allowlist they were computed for —
  /// a scan of every event, so it is redone only when either moves.
  AgendaYearBounds _years = (first: 0, last: 0);
  List<CalendarEvent>? _yearsEvents;
  Set<String>? _yearsCategories;
  int? _yearsToday;

  /// What the last fold read and what it gave: a calendar state that moves
  /// none of it changes nothing.
  _FoldKey? _lastKey;
  CalendarReport? _lastReport;

  /// The last Ready emitted: what a refold dims over, and what a fold that
  /// throws falls back to.
  ReportReady? _lastReady;

  /// The service, for the page's test seam that proves no fold runs in a
  /// build.
  @visibleForTesting
  CalendarReportService get service => _service;

  static Stream<ReportEvent> _oneAtATime(
    Stream<ReportEvent> events,
    Stream<ReportEvent> Function(ReportEvent) mapper,
  ) => events.asyncExpand(mapper);

  static DateTime _dayOf(DateTime time) => EventAgenda.dateOnly(time);

  Future<void> _onEvent(ReportEvent event, Emitter<ReportState> emit) async {
    switch (event) {
      case ReportOpened(:final look):
        await _open(look, emit);
      case ReportCalendarChanged(:final calendar):
        final newest = _calendarBloc.state;
        _calendar = newest is CalendarPageLoaded ? newest : calendar;
        await _fold(emit);
      case ReportPeriodPicked(:final period):
        final picked = _clamped(period);
        final kept = _keptOf(picked);
        _period = _home = picked;
        if (await _fold(emit)) {
          await _persist((s) => s.setCalendarReportPeriod(kept, today: _today));
        }
      case ReportStepped(:final direction):
        await _step(direction, emit);
      case ReportHomePressed():
        if (_home == null || _period == _home) return;
        _period = _home;
        await _fold(emit);
      case ReportCategoriesPicked(:final categoryIds):
        _categoryIds = categoryIds;
        if (await _fold(emit)) {
          await _persist((s) => s.setCalendarReportCategories(categoryIds));
        }
      case ReportLookArrived(:final look):
        final categoriesChanged = !setEquals(look.categoryIds, _categoryIds);
        _period = _home = _clamped(_reportable(look.period));
        _categoryIds = look.categoryIds;
        if (await _fold(emit) && categoriesChanged) {
          await _persist(
            (s) => s.setCalendarReportCategories(look.categoryIds),
          );
        }
      case ReportDayChanged(:final today):
        _moveTo(_dayOf(today));
        await _reread();
        await _fold(emit);
      case ReportResumed():
        await _resume(emit);
    }
  }

  Future<void> _open(ReportLook? look, Emitter<ReportState> emit) async {
    try {
      final settings = _settings = await _settingsSeed;
      final loaded = await settings.getCalendarReportSettings(today: _today);
      _appearance = loaded.appearance;
      _palette = loaded.palette;
      _hapticFeedback = loaded.hapticFeedback;
      _period = _home = loaded.period;
      _categoryIds = loaded.categoryIds;
    } catch (e, st) {
      // An unreadable store opens the report on its defaults rather than
      // leaving the page on Loading for good.
      debugPrint('[CalendarReportBloc] settings read failed: $e\n$st');
      _period = _home = OverviewPeriod.thisMonth(today: _today);
    }
    if (look != null) {
      final period = _clamped(_reportable(look.period));
      _period = _home = period;
      _categoryIds = look.categoryIds;
      // A look is for this visit; only a kept kind of period outlives it.
      if (period.encode(today: _today) != null) {
        await _persist((s) => s.setCalendarReportPeriod(period, today: _today));
      }
      await _persist((s) => s.setCalendarReportCategories(look.categoryIds));
    }
    _settingsLoaded = true;
    final current = _calendarBloc.state;
    if (current is CalendarPageLoaded) _calendar ??= current;
    if (_calendar == null) {
      emit(ReportLoading(period: _period));
      return;
    }
    await _fold(emit);
  }

  Future<void> _step(int direction, Emitter<ReportState> emit) async {
    final period = _period;
    final home = _home;
    final calendar = _calendar;
    if (period == null || home == null || calendar == null) return;
    final years = _yearsFor(calendar);
    final stepped = period.stepped(
      direction: direction,
      today: _today,
      yearBounds: years,
    );
    if (stepped == null) return;
    // A step back onto the home's own span is the home again, so the menu
    // checks its row and Today disables (the overview's rule).
    final span = stepped.resolve(today: _today, yearBounds: years);
    _period = span == home.resolve(today: _today, yearBounds: years)
        ? home
        : stepped;
    await _fold(emit);
  }

  /// The day moved under an open page: This week, This month and This year
  /// move on with it, as on the overview.
  void _moveTo(DateTime today) {
    if (today == _today) return;
    final before = _today;
    _today = today;
    _home = _home?.followingToday(before: before, today: today);
    _period = _period?.followingToday(before: before, today: today);
  }

  /// Re-reads the calendar's appearance, whose week start may have moved in
  /// the settings while the page was covered or the app away, with the
  /// palette and the haptic switch, which the settings move too.
  Future<void> _reread() async {
    final settings = _settings;
    if (!_settingsLoaded || settings == null) return;
    try {
      final loaded = await settings.getCalendarReportSettings(today: _today);
      if (loaded.appearance.weekStart != _appearance.weekStart) {
        _followWeekStart(loaded.appearance.weekStart);
      }
      _appearance = loaded.appearance;
      _palette = loaded.palette;
      _hapticFeedback = loaded.hapticFeedback;
    } catch (e, st) {
      debugPrint('[CalendarReportBloc] settings re-read failed: $e\n$st');
    }
  }

  Future<void> _resume(Emitter<ReportState> emit) async {
    if (!_settingsLoaded) return;
    await _reread();
    final request = _request();
    if (request == null) return;
    // No Folding here: a resume usually changes nothing, and the memo then
    // answers with the very report already shown — an equal state, which
    // emit drops.
    try {
      final report = _service.report(request.request);
      _lastKey = request.key;
      _lastReport = report;
      _emitReady(emit, report, request.years);
    } catch (e, st) {
      debugPrint('[CalendarReportBloc] fold on resume failed: $e\n$st');
    }
  }

  /// Writes a pick through [write]; a store that fails keeps the pick on
  /// screen for this visit and logs.
  Future<void> _persist(
    Future<void> Function(SettingsService settings) write,
  ) async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await write(settings);
    } catch (e, st) {
      debugPrint('[CalendarReportBloc] settings write failed: $e\n$st');
    }
  }

  /// What a pick of [picked] stores: a relative row (Last / Next week or
  /// month) its base preset, so the report reopens on This week or This
  /// month (D18, D36.2); anything else itself, a span that is not kept
  /// clearing the key.
  OverviewPeriod _keptOf(OverviewPeriod picked) {
    final calendar = _calendar;
    if (calendar == null) return picked;
    final years = _yearsFor(calendar);
    final choice = ReportPeriodChoice.checkedFor(
      picked,
      today: _today,
      weekStart: _appearance.weekStart,
      years: years,
    );
    final base = switch (choice) {
      ReportPeriodChoice.lastWeek ||
      ReportPeriodChoice.nextWeek => ReportPeriodChoice.thisWeek,
      ReportPeriodChoice.lastMonth ||
      ReportPeriodChoice.nextMonth => ReportPeriodChoice.thisMonth,
      _ => null,
    };
    return base?.periodFor(
          today: _today,
          weekStart: _appearance.weekStart,
          years: years,
        ) ??
        picked;
  }

  /// This week — as the home and as the period shown — re-read on a week
  /// start just changed in the settings; a week paged away from today stays
  /// the seven days it is.
  void _followWeekStart(CalendarWeekStart weekStart) {
    OverviewPeriod? follow(OverviewPeriod? period) =>
        period is OverviewWeekPeriod &&
            period.menuChoice(today: _today) == OverviewPeriodChoice.thisWeek
        ? OverviewPeriod.thisWeek(today: _today, weekStart: weekStart)
        : period;
    _home = follow(_home);
    _period = follow(_period);
  }

  /// Folds the report the current context asks for; false only when the
  /// fold threw. No refold when that is what was folded last — a calendar
  /// state that moved neither its events nor a revision never flickers the
  /// page — but the Ready is still re-emitted, since the key knows the span
  /// and not the pick: Last month picked after ◄ onto September is the same
  /// fold with a new home, and Today must follow it (D36.7). An equal state
  /// is dropped by emit.
  Future<bool> _fold(Emitter<ReportState> emit) async {
    final request = _request();
    if (request == null) return true;
    final last = _lastReport;
    if (request.key == _lastKey && last != null) {
      _emitReady(emit, last, request.years);
      return true;
    }
    final shown = _lastReady;
    emit(
      ReportFolding(
        previous: shown?.report,
        previousPeriod: shown?.period,
        previousCategoryIds: shown?.categoryIds ?? const {},
        period: _period!,
        home: _home!,
        categoryIds: _categoryIds,
        appearance: _appearance,
        palette: _palette,
        hapticFeedback: _hapticFeedback,
        today: _today,
        years: request.years,
      ),
    );
    // Folding is drawn before the fold holds the isolate: the band titles
    // the pick at once, and a route's first frame never waits on a fold.
    await _nextFrame();
    if (isClosed) return false;
    try {
      final report = _service.report(request.request);
      _lastKey = request.key;
      _lastReport = report;
      _emitReady(emit, report, request.years);
      return true;
    } catch (e, st) {
      debugPrint('[CalendarReportBloc] fold failed: $e\n$st');
      // The pick is undone and the report it replaced comes back, so the
      // page never stays dimmed over a fold that will not land (D36.6).
      if (shown == null) {
        emit(ReportLoading(period: _period));
      } else {
        _period = shown.period;
        _home = shown.home;
        _categoryIds = shown.categoryIds;
        emit(shown);
      }
      return false;
    }
  }

  void _emitReady(
    Emitter<ReportState> emit,
    CalendarReport report,
    AgendaYearBounds years,
  ) {
    final ready = ReportReady(
      report: report,
      period: _period!,
      home: _home!,
      categoryIds: _categoryIds,
      appearance: _appearance,
      palette: _palette,
      hapticFeedback: _hapticFeedback,
      today: _today,
      years: years,
    );
    _lastReady = ready;
    emit(ready);
  }

  ({ReportRequest request, _FoldKey key, AgendaYearBounds years})? _request() {
    final calendar = _calendar;
    final period = _period;
    if (!_settingsLoaded || calendar == null || period == null) return null;
    final years = _yearsFor(calendar);
    final span = period.resolve(today: _today, yearBounds: years);
    final previousSpan = period
        .stepped(direction: -1, today: _today, yearBounds: years)
        ?.resolve(today: _today, yearBounds: years);
    final request = ReportRequest(
      span: span,
      previousSpan: previousSpan,
      categoryIds: _categoryIds,
      events: calendar.allEvents,
      today: _today,
      weekStart: _appearance.weekStart,
      occurrenceRevision: calendar.occurrenceRevision,
      membershipRevision: calendar.membershipRevision,
      presenceRevision: calendar.presenceRevision,
    );
    final key = _FoldKey(
      events: calendar.allEvents,
      occurrenceRevision: calendar.occurrenceRevision,
      membershipRevision: calendar.membershipRevision,
      presenceRevision: calendar.presenceRevision,
      span: span,
      previousSpan: previousSpan,
      categoryIds: _categoryIds,
      today: _today,
      weekStart: _appearance.weekStart,
    );
    return (request: request, key: key, years: years);
  }

  AgendaYearBounds _yearsFor(CalendarPageLoaded calendar) {
    if (!identical(calendar.allEvents, _yearsEvents) ||
        !identical(_categoryIds, _yearsCategories) ||
        _today.year != _yearsToday) {
      _yearsEvents = calendar.allEvents;
      _yearsCategories = _categoryIds;
      _yearsToday = _today.year;
      _years = EventAgenda.yearBoundsOf(
        calendar.allEvents,
        categoryIds: _categoryIds,
        todayYear: _today.year,
        earliestYear: CalendarBounds.earliest.year,
        latestYear: CalendarBounds.latest.year,
      );
    }
    return _years;
  }

  /// The overview's All time has no place in the report (D18): it arrives
  /// as Last 12 months, the longest span the report's menu offers.
  static OverviewPeriod _reportable(OverviewPeriod period) => switch (period) {
    OverviewRollingPeriod(preset: OverviewRollingPreset.allTime) =>
      const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
    _ => period,
  };

  /// A custom span longer than the range scan reaches
  /// ([EventAgenda.maxRangeDays]) keeps its last that many days, so a span
  /// holding today keeps today and its Ahead (D33), and the band titles the
  /// span the service actually folds.
  static OverviewPeriod _clamped(OverviewPeriod period) {
    if (period is! OverviewCustomPeriod) return period;
    final length = period.end.difference(period.start).inDays + 1;
    if (length <= EventAgenda.maxRangeDays) return period;
    final end = period.end;
    return OverviewCustomPeriod(
      DateTime.utc(
        end.year,
        end.month,
        end.day - (EventAgenda.maxRangeDays - 1),
      ),
      end,
    );
  }

  @override
  Future<void> close() async {
    await _calendarSubscription.cancel();
    return super.close();
  }
}

/// Everything a fold reads, by identity where the calendar compares by
/// identity: two equal keys fold to the same report.
class _FoldKey {
  const _FoldKey({
    required this.events,
    required this.occurrenceRevision,
    required this.membershipRevision,
    required this.presenceRevision,
    required this.span,
    required this.previousSpan,
    required this.categoryIds,
    required this.today,
    required this.weekStart,
  });

  final List<CalendarEvent> events;
  final int occurrenceRevision;
  final int membershipRevision;
  final int presenceRevision;
  final DateRange span;
  final DateRange? previousSpan;
  final Set<String> categoryIds;
  final DateTime today;
  final CalendarWeekStart weekStart;

  @override
  bool operator ==(Object other) =>
      other is _FoldKey &&
      identical(events, other.events) &&
      occurrenceRevision == other.occurrenceRevision &&
      membershipRevision == other.membershipRevision &&
      presenceRevision == other.presenceRevision &&
      span == other.span &&
      previousSpan == other.previousSpan &&
      setEquals(categoryIds, other.categoryIds) &&
      today == other.today &&
      weekStart == other.weekStart;

  @override
  int get hashCode => Object.hash(
    identityHashCode(events),
    occurrenceRevision,
    membershipRevision,
    presenceRevision,
    span,
    previousSpan,
    Object.hashAllUnordered(categoryIds),
    today,
    weekStart,
  );
}
