import 'dart:collection';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../constants/analytics_metrics.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../constants/category_kinds.dart';
import '../constants/category_profiles.dart';
import '../constants/event_presence.dart';
import '../constants/event_skips.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../constants/report_metrics.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/category_profile.dart';
import '../models/date_range.dart';
import '../models/overview_period.dart';
import '../models/overview_view.dart';
import '../utils/calendar_report_builder.dart';
import '../utils/event_agenda.dart';
import '../utils/lru_cache.dart';
import 'note_money_ledger_service.dart';

/// One report asked of [CalendarReportService]: what the caller already
/// resolved from its period and its calendar state, so the service reads no
/// settings, no bloc and no clock.
///
/// Deliberately not `Equatable`: nothing compares two requests, and a value
/// compare would walk every event of [events] — the calendar never
/// value-compares `allEvents`. The memo keys on the list's identity instead.
final class ReportRequest {
  /// The period's resolved span, inclusive, date-only UTC.
  final DateRange span;

  /// The span one step back (`OverviewPeriod.stepped(-1)` resolved), or null
  /// when the period has none — the deltas compare against it (D28).
  final DateRange? previousSpan;

  /// The category allowlist, matched against each event's stored category id
  /// as the overview and a digest match it (D32); empty means every category.
  final Set<String> categoryIds;

  /// Every event the calendar holds (`CalendarPageLoaded.allEvents`); the
  /// service scopes them itself.
  final List<CalendarEvent> events;

  /// The day of the report, date-only UTC; the split between counted and
  /// ahead, and what may be missed, follow it.
  final DateTime today;

  /// The app's week start, for week-aligned trend columns.
  final CalendarWeekStart weekStart;

  /// `CalendarPageLoaded.occurrenceRevision`: descriptions and presence moved.
  /// Read as a memo key only, never bumped here.
  final int occurrenceRevision;

  /// `CalendarPageLoaded.membershipRevision`: skips or a reload moved which
  /// days occur. Read as a memo key only, never bumped here.
  final int membershipRevision;

  /// `CalendarPageLoaded.presenceRevision`: a presence mark moved. Read as a
  /// memo key only, never bumped here.
  final int presenceRevision;

  /// Whether an occurrence was missed; null reads `EventPresence.isMissed`.
  ///
  /// This and the four readers below are the guide's seam: its demo keeps
  /// its marks, skips and texts in memory, under ids no facade holds, and
  /// folds through [CalendarReportService.sampleInput] with its own — never
  /// through [CalendarReportService.report], whose memo keys on the
  /// calendar's revisions and not on these (it asserts none is passed).
  final bool Function(CalendarEvent event, DateTime dayUtc)? isMissed;

  /// An event's explicit marks, which tell today unmarked — still to come —
  /// from today marked; null reads `EventPresence.marksFor`.
  final Map<DateTime, PresenceStatus> Function(String eventId)? marksFor;

  /// An event's cancelled days, which the sampling drops and the caption
  /// counts; null reads `EventSkips.daysFor`.
  final Set<DateTime> Function(String eventId)? skipsFor;

  /// An event's per-day texts, which the Tasks tile and the rows read; null
  /// reads `OccurrenceDescriptions.overridesFor`.
  final Map<DateTime, String> Function(String eventId)? descriptionsFor;

  /// A category's effective profile; null reads
  /// `CategoryProfiles.effectiveFor`. The guide's demo passes the
  /// unprofiled one, so the owner's kinds never relabel or drop the demo's
  /// numbers (a Bill category counts no hours).
  final EffectiveProfile Function(String categoryId)? profileOf;

  /// What the second fold compares with (§6.11). Under
  /// [ReportCompare.lastYear] the service shifts the span itself and
  /// [previousSpan] goes unread; a plan always compares with the previous
  /// period.
  final ReportCompare compare;

  /// The saved view folded beside the span under [ReportCompare.view] — its
  /// categories only; null in every other mode.
  final OverviewView? compareView;

  const ReportRequest({
    required this.span,
    this.previousSpan,
    this.categoryIds = const {},
    required this.events,
    required this.today,
    required this.weekStart,
    this.occurrenceRevision = 0,
    this.membershipRevision = 0,
    this.presenceRevision = 0,
    this.isMissed,
    this.marksFor,
    this.skipsFor,
    this.descriptionsFor,
    this.profileOf,
    this.compare = ReportCompare.previous,
    this.compareView,
  }) : assert(
         (compare == ReportCompare.view) == (compareView != null),
         'a view is compared exactly when Compare chose one',
       );
}

/// Turns the live calendar — the events, the presence, skip and description
/// facades, the category catalogue — into a [ReportInput], folds it through
/// [CalendarReportBuilder], and remembers the result, so stepping ◄ then ►
/// re-folds nothing and a presence mark re-folds exactly once.
///
/// A plain class, never a singleton (D30): the report bloc owns one for its
/// page's life, and the digest planner's caller builds one per reconcile, so
/// the memo dies with its owner, nothing needs a `DatabaseLifecycle` reset
/// handler and no memo outlives the data it was folded from.
class CalendarReportService {
  /// [memoFolds] whole reports are kept: a step back and forth and one
  /// category change hit the memo instead of re-scanning.
  CalendarReportService({int memoFolds = ReportMetrics.memoFolds})
    : _reports = LruCache(maxSize: memoFolds);

  final LruCache<_ReportKey, CalendarReport> _reports;

  /// The lookbacks and the lookaheads, one LRU: each key names its window.
  final LruCache<_LookbackKey, List<ReportSample>> _lookbacks = LruCache(
    maxSize: AnalyticsMetrics.lastSeenCacheSize,
  );
  int _foldCount = 0;
  int _scanCount = 0;

  /// Report folds so far — the seam that proves a step back serves the memo
  /// and a presence mark folds once.
  int get foldCount => _foldCount;

  /// Range scans so far — the span's, the previous span's, and per category
  /// that has a target or reads a gap (R) one lookback and, after a past
  /// span, one lookahead, and one bills-ahead window when a scoped category
  /// is a Bill (M1) — the cost seam that proves a memo hit and a cached
  /// window scan nothing.
  int get scanCount => _scanCount;

  /// Walks of the scoped events that group them by category, across every
  /// service — the cost seam that proves the lookbacks group once per scope
  /// however many categories read one. Counted in debug builds only.
  @visibleForTesting
  static int debugCategoryGroupings = 0;

  /// Drops the memo and the lookbacks; [foldCount] and [scanCount] keep
  /// counting.
  void clear() {
    _reports.clear();
    _lookbacks.clear();
  }

  /// The report [request] asks for, from the memo when nothing it reads has
  /// moved. A miss costs one sampling and one fold of the span, and one
  /// sampling of the previous span's counted part: a totals fold of it for
  /// an unprofiled calendar comparing with the previous period, else a
  /// compared fold (§6.11) — itself a memo entry, so a step back and forth
  /// re-folds neither.
  CalendarReport report(ReportRequest request) {
    assert(
      request.isMissed == null &&
          request.marksFor == null &&
          request.skipsFor == null &&
          request.descriptionsFor == null &&
          request.profileOf == null,
      'the memo keys on the calendar\'s revisions, not on readers: a request '
      'with readers folds through sampleInput',
    );
    final window = _Window.of(request);
    final view = window.compare == ReportCompare.view
        ? request.compareView
        : null;
    final key = _ReportKey(
      window.scope,
      window.span,
      window.previousSpan,
      request.weekStart,
      compare: window.compare,
      viewCategoryIds: view == null ? null : _sorted(view.categoryIds),
    );
    final cached = _reports.get(key);
    if (cached != null) return cached;
    final scoped = _Scoped.of(request);
    final previousCounted = window.previousCounted;
    // An unprofiled calendar comparing with the previous period needs only
    // totals, so it folds exactly as it did before Compare.
    final compares =
        !window.plan &&
        (window.compare != ReportCompare.previous ||
            scoped.profiles.values.any((p) => !p.isUnprofiled));
    final CalendarReport report;
    if (compares && view != null) {
      final main = _fold(_input(request, window, owner: this, scoped: scoped));
      report = main.withCompared(_viewFold(request, view, main));
    } else if (compares && previousCounted != null) {
      final compared = _comparedFold(request, scoped, window, previousCounted);
      report = _fold(
        _input(
          request,
          window,
          owner: this,
          scoped: scoped,
          compared: compared,
        ),
      );
    } else {
      report = _fold(_input(request, window, owner: this, scoped: scoped));
    }
    _reports.put(key, report);
    return report;
  }

  CalendarReport _fold(ReportInput input) {
    _foldCount++;
    return CalendarReportBuilder.fold(input);
  }

  /// The previous period's or last year's fold over its counted part (D28),
  /// folded on its own today — the real one when the span is past, the
  /// counted part's last day when it is current — so its numbers are the
  /// deltas' like with like; sampled with the real today, whose pending
  /// rule decides what may still happen.
  CalendarReport _comparedFold(
    ReportRequest request,
    _Scoped scoped,
    _Window window,
    DateRange counted,
  ) {
    final span = window.previousSpan!;
    final today = window.span.end.isBefore(window.today)
        ? window.today
        : counted.end;
    final key = _ReportKey(
      window.scope,
      span,
      null,
      request.weekStart,
      role: ReportFoldRole.compared,
      foldToday: today,
    );
    final cached = _reports.get(key);
    if (cached != null) return cached;
    final compared = _fold(
      _comparedInput(
        scoped,
        span: span,
        counted: counted,
        today: today,
        sampledOn: window.today,
        weekStart: request.weekStart,
      ),
    );
    _reports.put(key, compared);
    return compared;
  }

  /// The saved [view]'s fold over the span and today of [request], with
  /// [main]'s tiles, so the two Totals columns line up.
  CalendarReport _viewFold(
    ReportRequest request,
    OverviewView view,
    CalendarReport main,
  ) {
    final derived = ReportRequest(
      span: request.span,
      categoryIds: view.categoryIds,
      events: request.events,
      today: request.today,
      weekStart: request.weekStart,
      occurrenceRevision: request.occurrenceRevision,
      membershipRevision: request.membershipRevision,
      presenceRevision: request.presenceRevision,
    );
    final window = _Window.of(derived);
    final tileSet = List<ReportTile>.unmodifiable([
      for (final tile in main.tiles) tile.tile,
    ]);
    final key = _ReportKey(
      window.scope,
      window.span,
      null,
      request.weekStart,
      role: ReportFoldRole.compared,
      foldToday: window.today,
      tileSet: tileSet,
    );
    final cached = _reports.get(key);
    if (cached != null) return cached;
    final compared = _fold(
      _comparedInput(
        _Scoped.of(derived),
        span: window.span,
        counted: window.counted,
        today: window.today,
        sampledOn: window.today,
        weekStart: request.weekStart,
        tileSet: tileSet,
      ),
    );
    _reports.put(key, compared);
    return compared;
  }

  /// A compared fold's input: [counted]'s samples alone — the fold reads no
  /// day after its [today] — and no lookback, lookahead, bills ahead or
  /// working days, which only the main fold's cards read.
  ReportInput _comparedInput(
    _Scoped scoped, {
    required DateRange span,
    required DateRange counted,
    required DateTime today,
    required DateTime sampledOn,
    required CalendarWeekStart weekStart,
    List<ReportTile>? tileSet,
  }) {
    final cancelled = _cancelled(scoped, counted, today);
    final samples = _samples(scoped, counted, sampledOn, this);
    // A pending day the compared today has passed has not happened: left
    // out, as the totals fold leaves it out.
    bool stale(ReportSample s) => s.pending && s.day != today;
    return ReportInput(
      span: span,
      today: today,
      weekStart: weekStart,
      events: scoped.byId,
      categoryOf: scoped.categoryOf,
      samples: samples.any(stale)
          ? [
              for (final sample in samples)
                if (!stale(sample)) sample,
            ]
          : samples,
      overrides: scoped.overrides,
      skippedDays: cancelled.length,
      categoryOrder: [for (final c in CalendarCategories.all) c.id],
      profiles: scoped.profiles,
      cancelled: cancelled,
      money: _money(scoped),
      role: ReportFoldRole.compared,
      tileSet: tileSet,
    );
  }

  static List<String> _sorted(Set<String> ids) =>
      List.unmodifiable(ids.toList()..sort());

  /// The builder's input for [request], unmemoized: the sampling [report]
  /// folds, public for the digest planner's path — whose caller may fold one
  /// span from it — and for tests.
  static ReportInput sampleInput(ReportRequest request) =>
      _input(request, _Window.of(request));

  /// The spans a report of [period] folds: its own, and the one a step back
  /// that the deltas compare against (D28), or null where the period has no
  /// step back. One rule for the report page's bloc and the guide's stage.
  static ({DateRange span, DateRange? previousSpan}) spansOf(
    OverviewPeriod period, {
    required DateTime today,
    required AgendaYearBounds years,
  }) => (
    span: period.resolve(today: today, yearBounds: years),
    previousSpan: period
        .stepped(direction: -1, today: today, yearBounds: years)
        ?.resolve(today: today, yearBounds: years),
  );

  /// The years a report's steps may reach: those [events] occur in under
  /// the allowlist [categoryIds], and today's, inside [CalendarBounds]. A
  /// partner's events reach no year: the report never counts them (D15).
  static AgendaYearBounds yearsOf(
    List<CalendarEvent> events, {
    Set<String> categoryIds = const {},
    required DateTime today,
  }) => EventAgenda.yearBoundsOf(
    events.any((e) => e.fromPartner)
        ? [
            for (final event in events)
              if (!event.fromPartner) event,
          ]
        : events,
    categoryIds: categoryIds,
    todayYear: today.year,
    earliestYear: CalendarBounds.earliest.year,
    latestYear: CalendarBounds.latest.year,
  );

  /// [owner] counts the scans and caches the lookbacks; the unmemoized
  /// [sampleInput] passes none and resolves them afresh. Given [compared],
  /// the previous totals are its totals — the same numbers as the totals
  /// fold, from the fold the rules read — and no second sampling runs.
  static ReportInput _input(
    ReportRequest request,
    _Window window, {
    CalendarReportService? owner,
    _Scoped? scoped,
    CalendarReport? compared,
  }) {
    scoped ??= _Scoped.of(request);
    final previousCounted = window.previousCounted;
    final samples = _samples(scoped, window.span, window.today, owner);
    final cancelled = _cancelled(scoped, window.counted, window.today);
    final (
      :workingDays,
      :publicHolidays,
    ) = _readsWorkingDays(window.span, scoped.profiles)
        ? _workingDays(window.span)
        : (workingDays: 0, publicHolidays: 0);
    final lookback = _lookback(scoped, window, owner);
    final lookahead = _lookahead(scoped, window, owner);
    final billsAhead = _billsAhead(scoped, window, owner);
    return ReportInput(
      span: window.span,
      today: window.today,
      weekStart: request.weekStart,
      events: scoped.byId,
      categoryOf: scoped.categoryOf,
      samples: samples,
      overrides: scoped.overrides,
      skippedDays: cancelled.length,
      categoryOrder: [for (final c in CalendarCategories.all) c.id],
      previousSpan: window.previousSpan,
      previousCounted: previousCounted,
      previousTotals: previousCounted == null
          ? null
          : compared?.totals ??
                _previousTotals(scoped, previousCounted, window, owner),
      profiles: scoped.profiles,
      cancelled: cancelled,
      money: _money(scoped),
      lastSeenBefore: _lastSeenBefore(scoped, lookback),
      lookback: lookback,
      lookahead: lookahead,
      billsAhead: billsAhead,
      workingDays: workingDays,
      publicHolidays: publicHolidays,
      compare: window.compare,
      compared: compared,
    );
  }

  /// Each scoped event's linked note's net, for the notes whose ledger is
  /// cached (P): read, never recomputed; no ledger service, no money.
  static Map<String, int> _money(_Scoped scoped) {
    final ledger = NoteMoneyLedgerService.instanceOrNull;
    if (ledger == null) return const {};
    return {
      for (final event in scoped.byId.values)
        if (event.noteId case final noteId?)
          event.id: ?ledger.ledgerFor(noteId)?.net,
    };
  }

  /// Whether [span]'s working days are worth resolving (analytics P): a
  /// whole calendar month or year, in a scope whose [profiles] hold a Work,
  /// Meeting or Leave kind — a plan included. A week has no working-days
  /// story, and resolved unconditionally the facts would reach every month's
  /// caption, where walkthroughs 1 and 7 want nothing to change.
  static bool _readsWorkingDays(
    DateRange span,
    Map<String, EffectiveProfile> profiles,
  ) {
    final start = span.start;
    final wholeMonth =
        start.day == 1 &&
        span.end == DateTime.utc(start.year, start.month + 1, 0);
    final wholeYear =
        start == DateTime.utc(start.year, 1, 1) &&
        span.end == DateTime.utc(start.year, 12, 31);
    if (!wholeMonth && !wholeYear) return false;
    return profiles.values.any(
      (profile) => switch (profile.kind) {
        CategoryKind.work || CategoryKind.meeting || CategoryKind.leave => true,
        _ => false,
      },
    );
  }

  /// The span's working days and public holidays (T). [PublicHolidays] is
  /// pure Dart, so the caption's facts cost one walk of at most a year.
  static ({int workingDays, int publicHolidays}) _workingDays(DateRange span) {
    var working = 0;
    var holidays = 0;
    for (
      var day = span.start;
      !day.isAfter(span.end);
      day = DateTime.utc(day.year, day.month, day.day + 1)
    ) {
      final holiday = PublicHolidays.isHoliday(day);
      if (holiday) holidays++;
      if (!holiday && day.weekday <= DateTime.friday) working++;
    }
    return (workingDays: working, publicHolidays: holidays);
  }

  /// Whether [profile] reads how long ago its category was last kept — the
  /// categories that pay for a lookback (R).
  static bool _readsGap(EffectiveProfile profile) =>
      profile.primary == ReportMeasure.lastSeen ||
      profile.secondary.contains(ReportMeasure.lastSeen) ||
      profile.target?.kind == TargetKind.maxGap;

  /// Whether [profile] pays for a lookback (R): a goal reads its streak and
  /// a period starting before the span from it, a gap its last kept day.
  static bool _readsLookback(EffectiveProfile profile) =>
      profile.target != null || _readsGap(profile);

  /// The kept and missed samples of the [AnalyticsMetrics.lookbackDays]
  /// before the span, never past today, of every category that has a target
  /// or reads a gap — one scan per category, whichever it does, cached in
  /// [owner] so a step ◄ ► never rescans.
  static Map<String, List<ReportSample>> _lookback(
    _Scoped scoped,
    _Window window,
    CalendarReportService? owner,
  ) {
    final start = window.span.start;
    final dayBefore = DateTime.utc(start.year, start.month, start.day - 1);
    return _windowSamples(
      scoped,
      window,
      owner,
      from: DateTime.utc(
        start.year,
        start.month,
        start.day - AnalyticsMetrics.lookbackDays,
      ),
      to: dayBefore.isAfter(window.today) ? window.today : dayBefore,
    );
  }

  /// The kept and missed samples after a past span, `span.end + 1` to
  /// today, of the categories [_lookback] scans — what a Last-month report
  /// needs to know a category was kept since and to value a goal period
  /// running past the span's end. Nothing when the span reaches today.
  static Map<String, List<ReportSample>> _lookahead(
    _Scoped scoped,
    _Window window,
    CalendarReportService? owner,
  ) {
    final end = window.span.end;
    if (!end.isBefore(window.today)) return const {};
    return _windowSamples(
      scoped,
      window,
      owner,
      from: DateTime.utc(end.year, end.month, end.day + 1),
      to: window.today,
    );
  }

  /// One scan per category that has a target or reads a gap over `from ..
  /// to`, cached in [owner] under a key naming the window.
  static Map<String, List<ReportSample>> _windowSamples(
    _Scoped scoped,
    _Window window,
    CalendarReportService? owner, {
    required DateTime from,
    required DateTime to,
  }) {
    final result = <String, List<ReportSample>>{};
    for (final MapEntry(key: categoryId, value: profile)
        in scoped.profiles.entries) {
      if (!_readsLookback(profile)) continue;
      final key = _LookbackKey(categoryId, from, to, window.scope);
      var found = owner?._lookbacks.get(key);
      if (found == null) {
        found = _lookbackOf(scoped, categoryId, from, to, window.today);
        owner?._scanCount++;
        owner?._lookbacks.put(key, found);
      }
      result[categoryId] = found;
    }
    return result;
  }

  /// The occurrences from today to today +
  /// [AnalyticsMetrics.billsAheadDays] of every Bill-kind category in scope
  /// — M1's window, which no span holds whole: one scan for them all in
  /// any tense, cached in [owner] beside the lookbacks under a key naming
  /// its window; nothing when no scoped category is a Bill.
  static List<ReportSample> _billsAhead(
    _Scoped scoped,
    _Window window,
    CalendarReportService? owner,
  ) {
    final bills = {
      for (final MapEntry(key: categoryId, value: profile)
          in scoped.profiles.entries)
        if (profile.kind == CategoryKind.bill) categoryId,
    };
    if (bills.isEmpty) return const [];
    final today = window.today;
    final to = DateTime.utc(
      today.year,
      today.month,
      today.day + AnalyticsMetrics.billsAheadDays,
    );
    final key = _LookbackKey.billsAhead(today, to, window.scope);
    final cached = owner?._lookbacks.get(key);
    if (cached != null) return cached;
    final occurrences = EventAgenda.occurrencesInRange(
      events: [
        for (final event in scoped.byId.values)
          if (bills.contains(scoped.categoryOf[event.id])) event,
      ],
      from: today,
      to: to,
    );
    final found = List<ReportSample>.unmodifiable([
      for (final EventOccurrence(:event, :day) in occurrences)
        if (!EventSkips.appliesTo(event) ||
            !scoped.skipsFor(event.id).contains(day))
          ReportSample(eventId: event.id, day: day),
    ]);
    owner?._scanCount++;
    owner?._lookbacks.put(key, found);
    return found;
  }

  /// The last kept day before the span of every category that reads a gap,
  /// from its [lookback] — present only where one was found.
  static Map<String, DateTime> _lastSeenBefore(
    _Scoped scoped,
    Map<String, List<ReportSample>> lookback,
  ) {
    final result = <String, DateTime>{};
    for (final MapEntry(key: categoryId, value: samples) in lookback.entries) {
      if (!_readsGap(scoped.profiles[categoryId]!)) continue;
      for (final sample in samples.reversed) {
        if (sample.missed) continue;
        result[categoryId] = sample.day;
        break;
      }
    }
    return result;
  }

  /// The samples in `from .. to` of [categoryId]'s events, oldest first:
  /// cancelled days and today's unmarked tracked day left out, a tracked
  /// day flagged when missed.
  static List<ReportSample> _lookbackOf(
    _Scoped scoped,
    String categoryId,
    DateTime from,
    DateTime to,
    DateTime today,
  ) {
    if (to.isBefore(from)) return const [];
    final occurrences = EventAgenda.occurrencesInRange(
      events: scoped.byCategory[categoryId] ?? const [],
      from: from,
      to: to,
    );
    return List.unmodifiable([
      for (final EventOccurrence(:event, :day) in occurrences)
        if (!EventSkips.appliesTo(event) ||
            !scoped.skipsFor(event.id).contains(day))
          if (!EventPresence.appliesTo(event))
            ReportSample(eventId: event.id, day: day)
          else if (day != today || scoped.marksFor(event.id)[today] != null)
            ReportSample(
              eventId: event.id,
              day: day,
              missed: scoped.isMissed(event, day),
            ),
    ]);
  }

  /// The previous span's totals over [counted] alone — the same numbers as
  /// sampling the whole previous span, since
  /// [CalendarReportBuilder.foldTotals] reads nothing outside its range. A
  /// plan counts today's pending occurrence as the plan it is (D28: every
  /// occurrence), so its pending flags are cleared first —
  /// [CalendarReportBuilder.foldTotals] leaves a pending sample out, and a
  /// plan's previous span may hold today.
  static ReportTotals _previousTotals(
    _Scoped scoped,
    DateRange counted,
    _Window window,
    CalendarReportService? owner,
  ) {
    final samples = _samples(scoped, counted, window.today, owner);
    return CalendarReportBuilder.foldTotals(
      counted: counted,
      events: scoped.byId,
      samples: window.plan
          ? [
              for (final s in samples)
                s.pending ? ReportSample(eventId: s.eventId, day: s.day) : s,
            ]
          : samples,
      overrides: scoped.overrides,
      categoryOf: scoped.categoryOf,
      profiles: scoped.profiles,
    );
  }

  /// One sample per occurrence in [range]. The scan's `occursOn` subtracts
  /// the static skips; the reader's are subtracted here too — the same days
  /// when there is no reader, so the drop is a no-op then, and a demo's
  /// cancelled day is never both sampled and counted as skipped. The
  /// allowlist goes to the scan as the digest planner hands it, so the
  /// report counts what the overview lists (D32).
  static List<ReportSample> _samples(
    _Scoped scoped,
    DateRange range,
    DateTime today,
    CalendarReportService? owner,
  ) {
    owner?._scanCount++;
    final occurrences = EventAgenda.occurrencesInRange(
      events: scoped.all,
      from: range.start,
      to: range.end,
      categoryIds: scoped.categoryIds,
    );
    final skips = <String, Set<DateTime>>{};
    bool kept(EventOccurrence occurrence) {
      final event = occurrence.event;
      // The scan walks the request's own list, whose identity keys its window
      // index; a partner's occurrence is dropped here, as [_Scoped.of] drops
      // the event.
      if (event.fromPartner) return false;
      return !EventSkips.appliesTo(event) ||
          !(skips[event.id] ??= scoped.skipsFor(
            event.id,
          )).contains(occurrence.day);
    }

    return [
      for (final EventOccurrence(:event, :day) in occurrences.where(kept))
        if (!EventPresence.appliesTo(event) || day.isAfter(today))
          ReportSample(eventId: event.id, day: day)
        else if (day == today && scoped.marksFor(event.id)[today] == null)
          // Today unmarked is still to come (D31), whatever an assume-absent
          // default would say of a past day.
          ReportSample(eventId: event.id, day: day, pending: true)
        else
          ReportSample(
            eventId: event.id,
            day: day,
            missed: scoped.isMissed(event, day),
          ),
    ];
  }

  /// Skipped days in the counted range, never one after today — what the
  /// caption describes, and what Cancelled folds per category. A skip counts
  /// only where the rule still produces the day: a skip row outlives a rule
  /// change, and a cancelled Monday of a routine moved to Tuesdays skipped
  /// nothing.
  static List<ReportSample> _cancelled(
    _Scoped scoped,
    DateRange counted,
    DateTime today,
  ) {
    final end = counted.end.isAfter(today) ? today : counted.end;
    if (end.isBefore(counted.start)) return const [];
    return [
      for (final event in scoped.byId.values)
        if (EventSkips.appliesTo(event))
          for (final day in scoped.skipsFor(event.id))
            if (!day.isBefore(counted.start) &&
                !day.isAfter(end) &&
                event.wouldOccurOnUtcDay(day))
              ReportSample(eventId: event.id, day: day),
    ];
  }
}

/// The spans one request reads, clamped, and the memo's scope part — cheap
/// enough to build before a memo lookup.
final class _Window {
  final DateTime today;
  final DateRange span;
  final DateRange? previousSpan;

  /// The counted part of [span]: its start to today in a current span, the
  /// whole span otherwise.
  final DateRange counted;

  /// The part of [previousSpan] its totals count (D28), or null.
  final DateRange? previousCounted;

  /// Whether [span] is wholly after today — a plan, whose totals count every
  /// occurrence.
  final bool plan;

  /// The mode the report folds in: the request's, else
  /// [ReportCompare.previous] for a plan, for a last year before
  /// [CalendarBounds.earliest] and for a view with no
  /// [ReportRequest.compareView].
  final ReportCompare compare;
  final _Scope scope;

  const _Window({
    required this.today,
    required this.span,
    required this.previousSpan,
    required this.counted,
    required this.previousCounted,
    required this.plan,
    required this.compare,
    required this.scope,
  });

  /// The tense and the counted end come from [CalendarReport.tenseOf] and
  /// [CalendarReport.countedToOf], the rule [CalendarReportBuilder.fold]
  /// reads, so the previous span is counted the way the report is. Under
  /// last year the shifted span stands in for the previous one, and is
  /// counted by the same rule.
  factory _Window.of(ReportRequest request) {
    final today = EventAgenda.dateOnly(request.today);
    final span = _clamp(request.span);
    final tense = CalendarReport.tenseOf(span: span, today: today);
    var compare = tense == ReportTense.future
        ? ReportCompare.previous
        : request.compare;
    // A view compared with no view is a caller's bug the constructor asserts;
    // a release build folds the previous period rather than a previous-period
    // fold labelled as a view.
    if (compare == ReportCompare.view && request.compareView == null) {
      compare = ReportCompare.previous;
    }
    // Clamped like the span: a 366-day span that holds 29 February shifts to
    // 367 days, and the scan would drop the last day the span still names.
    final shifted = compare == ReportCompare.lastYear
        ? _clamp(_lastYearOf(span))
        : null;
    if (shifted != null && shifted.end.isBefore(CalendarBounds.earliest)) {
      compare = ReportCompare.previous;
    }
    final previous = request.previousSpan;
    final previousSpan = compare == ReportCompare.lastYear
        ? shifted
        : previous == null
        ? null
        : _clamp(previous);
    final DateRange counted = (
      start: span.start,
      end: CalendarReport.countedToOf(span: span, today: today),
    );
    DateRange? previousCounted = previousSpan;
    if (previousSpan != null && tense == ReportTense.current) {
      // Like with like (D28): the previous span counted to the same elapsed
      // length, never a partial month against a whole one.
      final elapsed = counted.end.difference(counted.start).inDays;
      final end = DateTime.utc(
        previousSpan.start.year,
        previousSpan.start.month,
        previousSpan.start.day + elapsed,
      );
      previousCounted = (
        start: previousSpan.start,
        end: end.isAfter(previousSpan.end) ? previousSpan.end : end,
      );
    }
    return _Window(
      today: today,
      span: span,
      previousSpan: previousSpan,
      counted: counted,
      previousCounted: previousCounted,
      plan: tense == ReportTense.future,
      compare: compare,
      scope: _Scope(
        categoryIds: List.unmodifiable(request.categoryIds.toList()..sort()),
        occurrenceRevision: request.occurrenceRevision,
        membershipRevision: request.membershipRevision,
        presenceRevision: request.presenceRevision,
        today: today,
        events: _Same(request.events),
        categoriesRevision: CalendarCategories.revision,
        holidaysRevision: PublicHolidays.revision,
        profilesRevision: CategoryProfiles.revision,
        ledgerRevision: NoteMoneyLedgerService.instanceOrNull?.revision ?? -1,
      ),
    );
  }

  /// The same period a year before [span] (§6.11), so like meets like: a
  /// calendar year the year before; a calendar month the same month, to its
  /// own last day; a whole number of weeks the same weekdays 364 days back;
  /// otherwise both ends a year back, a day past the month's end (29
  /// February) clamped to its last.
  static DateRange _lastYearOf(DateRange span) {
    final (:start, :end) = span;
    final sameMonth = start.year == end.year && start.month == end.month;
    if (start.day == 1 && end == DateTime.utc(end.year, end.month + 1, 0)) {
      if (start.year == end.year && start.month == 1 && end.month == 12) {
        return (
          start: DateTime.utc(start.year - 1, 1, 1),
          end: DateTime.utc(start.year - 1, 12, 31),
        );
      }
      if (sameMonth) {
        return (
          start: DateTime.utc(start.year - 1, start.month, 1),
          end: DateTime.utc(start.year - 1, start.month + 1, 0),
        );
      }
    }
    final days = end.difference(start).inDays + 1;
    if (days % DateTime.daysPerWeek == 0) {
      const back = 52 * DateTime.daysPerWeek;
      return (
        start: DateTime.utc(start.year, start.month, start.day - back),
        end: DateTime.utc(end.year, end.month, end.day - back),
      );
    }
    DateTime yearBack(DateTime day) {
      final last = DateTime.utc(day.year - 1, day.month + 1, 0).day;
      return DateTime.utc(
        day.year - 1,
        day.month,
        day.day > last ? last : day.day,
      );
    }

    return (start: yearBack(start), end: yearBack(end));
  }

  /// The last [EventAgenda.maxRangeDays] days of [span] (D33): a long custom
  /// span that holds today keeps today and what is ahead of it, and the scan
  /// then never clamps, so the report names exactly the days scanned. An
  /// inverted span comes back normalized and inverted — it scans nothing,
  /// and the fold's date-only reads still hold.
  static DateRange _clamp(DateRange span) {
    final start = EventAgenda.dateOnly(span.start);
    final end = EventAgenda.dateOnly(span.end);
    final earliest = DateTime.utc(
      end.year,
      end.month,
      end.day - (EventAgenda.maxRangeDays - 1),
    );
    return (start: start.isBefore(earliest) ? earliest : start, end: end);
  }
}

/// The request's events in scope and what travels with them. The allowlist
/// matches the stored category id ([EventAgenda.passesEventFilters], D32);
/// [categoryOf] holds the resolved one, so an unknown id groups under
/// `other`, where its row is drawn.
final class _Scoped {
  final List<CalendarEvent> all;
  final Set<String> categoryIds;
  final Map<String, CalendarEvent> byId;
  final Map<String, String> categoryOf;

  /// Every per-day text of the events in scope, on every day: the Tasks tile
  /// is decided by the selection (D15), and the builder looks texts up by
  /// day. Views, not copies — the facade replaces its map wholesale on
  /// publish, so a view cannot change under a report; a reader hands maps
  /// that hold still the same way (the guide's demo hands copies).
  final Map<String, Map<DateTime, String>> overrides;

  /// Every resolved category's effective profile, unprofiled ones included,
  /// so the builder never consults [CategoryProfiles].
  final Map<String, EffectiveProfile> profiles;

  /// The request's readers, each the static facade's where it passed none.
  final bool Function(CalendarEvent event, DateTime dayUtc) isMissed;
  final Map<DateTime, PresenceStatus> Function(String eventId) marksFor;
  final Set<DateTime> Function(String eventId) skipsFor;

  /// The events in scope per resolved category, in [byId]'s order — grouped
  /// once, on the first lookback, so a report whose categories each read one
  /// walks the scope once rather than once per category. Each group is a
  /// stable list, so its window index is built once for every window.
  late final Map<String, List<CalendarEvent>> byCategory = () {
    assert(() {
      CalendarReportService.debugCategoryGroupings++;
      return true;
    }());
    final groups = <String, List<CalendarEvent>>{};
    for (final event in byId.values) {
      (groups[categoryOf[event.id]!] ??= <CalendarEvent>[]).add(event);
    }
    return groups;
  }();

  _Scoped({
    required this.all,
    required this.categoryIds,
    required this.byId,
    required this.categoryOf,
    required this.overrides,
    required this.profiles,
    required this.isMissed,
    required this.marksFor,
    required this.skipsFor,
  });

  factory _Scoped.of(ReportRequest request) {
    final ids = request.categoryIds;
    final byId = <String, CalendarEvent>{};
    final categoryOf = <String, String>{};
    final overrides = <String, Map<DateTime, String>>{};
    final profiles = <String, EffectiveProfile>{};
    final textsFor =
        request.descriptionsFor ?? OccurrenceDescriptions.overridesFor;
    final profileOf = request.profileOf ?? CategoryProfiles.effectiveFor;
    for (final event in request.events) {
      // A partner's event is the partner's time (D15): in no figure, even
      // when it shares my built-in category's id.
      if (event.fromPartner) continue;
      if (!EventAgenda.passesEventFilters(event, categoryIds: ids)) continue;
      byId[event.id] = event;
      final categoryId = CalendarCategories.resolve(event.categoryId).id;
      categoryOf[event.id] = categoryId;
      profiles[categoryId] ??= profileOf(categoryId);
      if (OccurrenceDescriptions.appliesTo(event)) {
        final texts = textsFor(event.id);
        if (texts.isNotEmpty) {
          overrides[event.id] = UnmodifiableMapView(texts);
        }
      }
    }
    return _Scoped(
      all: request.events,
      categoryIds: ids,
      byId: byId,
      categoryOf: categoryOf,
      overrides: overrides,
      profiles: profiles,
      isMissed: request.isMissed ?? EventPresence.isMissed,
      marksFor: request.marksFor ?? EventPresence.marksFor,
      skipsFor: request.skipsFor ?? EventSkips.daysFor,
    );
  }
}

/// What a memo entry depends on besides its spans and week start.
///
/// Beyond D30's revisions it carries the events list's identity and the
/// catalogue's and the holidays' revisions: an event's create, edit or delete
/// builds a fresh `allEvents` and bumps no counter, a category's change
/// re-resolves `categoryOf` without touching an event, and the holiday set
/// moves the workday and holiday-only rules with no bloc event at all. The
/// profiles' and the ledger's revisions the same way: a profile edit changes
/// what is counted, and a linked note's edit its money, with no event row
/// touched.
final class _Scope extends Equatable {
  final List<String> categoryIds;
  final int occurrenceRevision;
  final int membershipRevision;
  final int presenceRevision;
  final DateTime today;
  final _Same events;
  final int categoriesRevision;
  final int holidaysRevision;
  final int profilesRevision;

  /// -1 while no ledger service exists, so its first load misses.
  final int ledgerRevision;

  const _Scope({
    required this.categoryIds,
    required this.occurrenceRevision,
    required this.membershipRevision,
    required this.presenceRevision,
    required this.today,
    required this.events,
    required this.categoriesRevision,
    required this.holidaysRevision,
    required this.profilesRevision,
    required this.ledgerRevision,
  });

  @override
  List<Object?> get props => [
    categoryIds,
    occurrenceRevision,
    membershipRevision,
    presenceRevision,
    today,
    events,
    categoriesRevision,
    holidaysRevision,
    profilesRevision,
    ledgerRevision,
  ];
}

/// One category's lookback or lookahead (R): what the scan reads — the
/// category, the window's first and last day, the events, their memberships
/// and marks, the profiles and the catalogue — and never the descriptions or
/// the ledger, so a text edit refolds the report without rescanning the year.
/// The bills-ahead window (M1) shares the cache under its own [kind]: one
/// scan over every Bill-kind category, which the allowlist and the profiles'
/// revision already decide.
final class _LookbackKey extends Equatable {
  final _WindowKind kind;
  final String categoryId;
  final DateTime from;
  final DateTime to;
  final List<String> categoryIds;
  final DateTime today;
  final _Same events;
  final int membershipRevision;
  final int presenceRevision;
  final int profilesRevision;
  final int categoriesRevision;
  final int holidaysRevision;

  _LookbackKey(String categoryId, DateTime from, DateTime to, _Scope scope)
    : this._(_WindowKind.category, categoryId, from, to, scope);

  _LookbackKey.billsAhead(DateTime from, DateTime to, _Scope scope)
    : this._(_WindowKind.billsAhead, '', from, to, scope);

  _LookbackKey._(this.kind, this.categoryId, this.from, this.to, _Scope scope)
    : categoryIds = scope.categoryIds,
      today = scope.today,
      events = scope.events,
      membershipRevision = scope.membershipRevision,
      presenceRevision = scope.presenceRevision,
      profilesRevision = scope.profilesRevision,
      categoriesRevision = scope.categoriesRevision,
      holidaysRevision = scope.holidaysRevision;

  @override
  List<Object?> get props => [
    kind,
    categoryId,
    from,
    to,
    categoryIds,
    today,
    events,
    membershipRevision,
    presenceRevision,
    profilesRevision,
    categoriesRevision,
    holidaysRevision,
  ];
}

/// Which window a [_LookbackKey] names: one category's lookback or
/// lookahead, or the Bill categories' next month.
enum _WindowKind { category, billsAhead }

/// One memo entry: a report, or a compared fold (§6.11). A compared fold's
/// [scope] carries its own allowlist (a view's) and [foldToday] its own
/// today; a main report's [compare] and [viewCategoryIds] make a mode change
/// or an edited view miss.
final class _ReportKey extends Equatable {
  final _Scope scope;
  final DateRange span;
  final DateRange? previousSpan;
  final CalendarWeekStart weekStart;
  final ReportCompare compare;
  final List<String>? viewCategoryIds;
  final ReportFoldRole role;
  final DateTime? foldToday;
  final List<ReportTile>? tileSet;

  const _ReportKey(
    this.scope,
    this.span,
    this.previousSpan,
    this.weekStart, {
    this.compare = ReportCompare.previous,
    this.viewCategoryIds,
    this.role = ReportFoldRole.main,
    this.foldToday,
    this.tileSet,
  });

  @override
  List<Object?> get props => [
    scope,
    span,
    previousSpan,
    weekStart,
    compare,
    viewCategoryIds,
    role,
    foldToday,
    tileSet,
  ];
}

/// Equal only to itself: a value compare would walk every event on each
/// lookup, and the bloc's fresh list per write is the signal that matters.
final class _Same {
  final Object value;

  const _Same(this.value);

  @override
  bool operator ==(Object other) =>
      other is _Same && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}
