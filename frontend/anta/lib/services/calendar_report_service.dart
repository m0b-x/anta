import 'dart:collection';

import 'package:equatable/equatable.dart';

import '../constants/calendar_categories.dart';
import '../constants/event_presence.dart';
import '../constants/event_skips.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../constants/report_metrics.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/date_range.dart';
import '../utils/calendar_report_builder.dart';
import '../utils/event_agenda.dart';
import '../utils/lru_cache.dart';

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
  });
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
  int _foldCount = 0;

  /// Report folds so far — the seam that proves a step back serves the memo
  /// and a presence mark folds once.
  int get foldCount => _foldCount;

  /// Drops the memo; [foldCount] keeps counting.
  void clear() => _reports.clear();

  /// The report [request] asks for, from the memo when nothing it reads has
  /// moved. A miss costs one sampling and one fold of the span, and one
  /// sampling and one totals fold of the previous span's counted part.
  CalendarReport report(ReportRequest request) {
    final window = _Window.of(request);
    final key = _ReportKey(
      window.scope,
      window.span,
      window.previousSpan,
      request.weekStart,
    );
    final cached = _reports.get(key);
    if (cached != null) return cached;
    _foldCount++;
    final report = CalendarReportBuilder.fold(_input(request, window));
    _reports.put(key, report);
    return report;
  }

  /// The builder's input for [request], unmemoized: the sampling [report]
  /// folds, public for the digest planner's path — whose caller may fold one
  /// span from it — and for tests.
  static ReportInput sampleInput(ReportRequest request) =>
      _input(request, _Window.of(request));

  static ReportInput _input(ReportRequest request, _Window window) {
    final scoped = _Scoped.of(request);
    final previousCounted = window.previousCounted;
    final samples = _samples(scoped, window.span, window.today);
    return ReportInput(
      span: window.span,
      today: window.today,
      weekStart: request.weekStart,
      events: scoped.byId,
      categoryOf: scoped.categoryOf,
      samples: samples,
      overrides: scoped.overrides,
      skippedDays: _skippedDays(scoped, window),
      categoryOrder: [for (final c in CalendarCategories.all) c.id],
      previousSpan: window.previousSpan,
      previousCounted: previousCounted,
      previousTotals: previousCounted == null
          ? null
          : _previousTotals(scoped, previousCounted, window),
    );
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
  ) {
    final samples = _samples(scoped, counted, window.today);
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
    );
  }

  /// One sample per occurrence in [range], skips already subtracted by
  /// `occursOn`. The allowlist goes to the scan as the digest planner hands
  /// it, so the report counts what the overview lists (D32).
  static List<ReportSample> _samples(
    _Scoped scoped,
    DateRange range,
    DateTime today,
  ) {
    final occurrences = EventAgenda.occurrencesInRange(
      events: scoped.all,
      from: range.start,
      to: range.end,
      categoryIds: scoped.categoryIds,
    );
    return [
      for (final EventOccurrence(:event, :day) in occurrences)
        if (!EventPresence.appliesTo(event) || day.isAfter(today))
          ReportSample(eventId: event.id, day: day)
        else if (day == today &&
            EventPresence.marksFor(event.id)[today] == null)
          // Today unmarked is still to come (D31), whatever an assume-absent
          // default would say of a past day.
          ReportSample(eventId: event.id, day: day, pending: true)
        else
          ReportSample(
            eventId: event.id,
            day: day,
            missed: EventPresence.isMissed(event, day),
          ),
    ];
  }

  /// Skipped days in the counted range, never one after today — what the
  /// caption describes. A skip counts only where the rule still produces the
  /// day: a skip row outlives a rule change, and a cancelled Monday of a
  /// routine moved to Tuesdays skipped nothing.
  static int _skippedDays(_Scoped scoped, _Window window) {
    final counted = window.counted;
    final end = counted.end.isAfter(window.today) ? window.today : counted.end;
    if (end.isBefore(counted.start)) return 0;
    var skipped = 0;
    for (final event in scoped.byId.values) {
      if (!EventSkips.appliesTo(event)) continue;
      for (final day in EventSkips.daysFor(event.id)) {
        if (!day.isBefore(counted.start) &&
            !day.isAfter(end) &&
            event.wouldOccurOnUtcDay(day)) {
          skipped++;
        }
      }
    }
    return skipped;
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
  final _Scope scope;

  const _Window({
    required this.today,
    required this.span,
    required this.previousSpan,
    required this.counted,
    required this.previousCounted,
    required this.plan,
    required this.scope,
  });

  /// The tense and the counted end come from [CalendarReport.tenseOf] and
  /// [CalendarReport.countedToOf], the rule [CalendarReportBuilder.fold]
  /// reads, so the previous span is counted the way the report is.
  factory _Window.of(ReportRequest request) {
    final today = EventAgenda.dateOnly(request.today);
    final span = _clamp(request.span);
    final previous = request.previousSpan;
    final previousSpan = previous == null ? null : _clamp(previous);
    final tense = CalendarReport.tenseOf(span: span, today: today);
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
      scope: _Scope(
        categoryIds: List.unmodifiable(request.categoryIds.toList()..sort()),
        occurrenceRevision: request.occurrenceRevision,
        membershipRevision: request.membershipRevision,
        presenceRevision: request.presenceRevision,
        today: today,
        events: _Same(request.events),
        categoriesRevision: CalendarCategories.revision,
        holidaysRevision: PublicHolidays.revision,
      ),
    );
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
  /// publish, so a view cannot change under a report.
  final Map<String, Map<DateTime, String>> overrides;

  const _Scoped({
    required this.all,
    required this.categoryIds,
    required this.byId,
    required this.categoryOf,
    required this.overrides,
  });

  factory _Scoped.of(ReportRequest request) {
    final ids = request.categoryIds;
    final byId = <String, CalendarEvent>{};
    final categoryOf = <String, String>{};
    final overrides = <String, Map<DateTime, String>>{};
    for (final event in request.events) {
      if (!EventAgenda.passesEventFilters(event, categoryIds: ids)) continue;
      byId[event.id] = event;
      categoryOf[event.id] = CalendarCategories.resolve(event.categoryId).id;
      if (OccurrenceDescriptions.appliesTo(event)) {
        final texts = OccurrenceDescriptions.overridesFor(event.id);
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
    );
  }
}

/// What a memo entry depends on besides its spans and week start.
///
/// Beyond D30's revisions it carries the events list's identity and the
/// catalogue's and the holidays' revisions: an event's create, edit or delete
/// builds a fresh `allEvents` and bumps no counter, a category's change
/// re-resolves `categoryOf` without touching an event, and the holiday set
/// moves the workday and holiday-only rules with no bloc event at all.
final class _Scope extends Equatable {
  final List<String> categoryIds;
  final int occurrenceRevision;
  final int membershipRevision;
  final int presenceRevision;
  final DateTime today;
  final _Same events;
  final int categoriesRevision;
  final int holidaysRevision;

  const _Scope({
    required this.categoryIds,
    required this.occurrenceRevision,
    required this.membershipRevision,
    required this.presenceRevision,
    required this.today,
    required this.events,
    required this.categoriesRevision,
    required this.holidaysRevision,
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
  ];
}

final class _ReportKey extends Equatable {
  final _Scope scope;
  final DateRange span;
  final DateRange? previousSpan;
  final CalendarWeekStart weekStart;

  const _ReportKey(this.scope, this.span, this.previousSpan, this.weekStart);

  @override
  List<Object?> get props => [scope, span, previousSpan, weekStart];
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
