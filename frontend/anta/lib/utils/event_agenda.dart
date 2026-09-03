import 'package:flutter/foundation.dart' show visibleForTesting;

import '../constants/event_presence.dart';
import '../constants/fasting_calendar.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../models/calendar_event.dart';
import '../models/fasting_appearance.dart';
import '../models/recurrence_rule.dart';
import '../models/upcoming_agenda_filters.dart';
import 'event_search_query.dart';

/// One dated occurrence of a [CalendarEvent] inside an agenda range.
///
/// A recurring event produces one [EventOccurrence] per matching day, so the
/// same [event] instance can appear many times under different [day] values.
class EventOccurrence {
  final CalendarEvent event;

  /// Date-only UTC day this occurrence falls on, matching the normalization
  /// used by [CalendarEvent.occursOn] and the calendar bloc.
  final DateTime day;

  /// How many occurrences this one **stands for**. Always 1 unless the
  /// collapse pass dropped the event's other in-window days, in which case the
  /// surviving occurrence carries their total — so a collapsed row can say it
  /// represents more than itself instead of passing as a single event.
  final int occurrenceCountInWindow;

  const EventOccurrence({
    required this.event,
    required this.day,
    this.occurrenceCountInWindow = 1,
  });
}

/// One category's events across the window, digested to a single card.
///
/// The event layer's counterpart of [FastingSummary], keyed on **category**
/// because a category is to events what a tradition is to fasting: the thing
/// that gives a row its colour, its icon and its identity.
///
/// Unlike the fasting summaries this needs no scan of its own — it folds an
/// already-built occurrence list, so it can only ever describe occurrences the
/// scan produced, and the card can never disagree with its own drill-down.
class EventCategorySummary {
  final String categoryId;

  /// Every occurrence in the window, ascending — the drill-down's rows, and
  /// what [occurrenceCount] counts.
  final List<EventOccurrence> occurrences;

  /// Distinct events behind [occurrences]. A daily event across ninety days
  /// is **one** event, which is the number worth leading a digest with; the
  /// occurrence tally says how much of the window it fills.
  final int eventCount;

  final DateTime first;
  final DateTime last;

  const EventCategorySummary({
    required this.categoryId,
    required this.occurrences,
    required this.eventCount,
    required this.first,
    required this.last,
  });

  int get occurrenceCount => occurrences.length;
}

/// One fasting period's stretch of days, collapsed for the agenda.
///
/// A run belongs to exactly one ([tradition], [period]) pair, which is what
/// lets a **sparse** period collapse at all: a Great Lent thinned to
/// Wednesdays and Fridays by the personal weekday scope is still one Lent, and
/// grouping by "the day is a fasting day" alone would emit forty one-day rows
/// and merge two neighbouring periods into one meaningless span.
///
/// [start] and [end] are the run's **true** extent — its first and last marked
/// day, which may reach outside the queried window, so a Lent that began
/// before the window still reads as its full length. [day] is where the row is
/// placed: the first marked day of the run that is actually inside the window,
/// so runs merge into the agenda's ascending day walk alongside events and
/// holidays.
///
/// [dayCount] is the number of days actually **marked**, not the calendar
/// distance between the edges: for a contiguous run the two agree, and for a
/// sparse one only the count is honest.
class FastingRun {
  final DateTime day;
  final DateTime start;
  final DateTime end;
  final FastingTradition tradition;
  final FastingPeriod period;
  final int dayCount;

  const FastingRun({
    required this.day,
    required this.start,
    required this.end,
    required this.tradition,
    required this.period,
    required this.dayCount,
  });
}

/// A [FastingRun] still being accumulated by the in-window scan.
///
/// Mutable and private on purpose: the scan touches one of these per marked
/// day, and the immutable [FastingRun] is built once, when the run closes and
/// its outward extent is known.
class _OpenFastingRun {
  final FastingTradition tradition;
  final FastingPeriod period;

  /// First marked day of the run inside the window — the row's placement, and
  /// the anchor the backward walk starts from.
  final DateTime day;

  /// Most recent marked day, against which the next day's gap is measured.
  DateTime last;

  /// Marked days seen inside the window so far.
  int dayCount = 1;

  _OpenFastingRun(this.tradition, this.period, this.day) : last = day;
}

/// A whole window's fasting for one tradition, digested to a single card.
///
/// The third presentation of fasting in the agenda, beside one row per day and
/// one row per [FastingRun]: even collapsed to runs, a year-round Wed/Fri
/// practice contributes a row every few days — deliberately, since the weekly
/// fast never bridges — so a 90-day window still buries everything else. One
/// summary per **tradition** rather than per fast, because a window holding
/// Lent *and* the weekly rule would otherwise be right back at several cards.
///
/// Every number here is **window-scoped**: unlike a run, which reports a
/// period's true extent because it *is* the period, a summary describes
/// "fasting in this window", and claiming days outside it would make the card
/// disagree with the list it summarizes.
class FastingSummary {
  final FastingTradition tradition;

  /// `DateTime.weekday` values actually marked inside the window — the input
  /// to the card's "Wed, Fri" / "Daily" pattern fragment.
  final Set<int> weekdays;

  /// First and last marked day inside the window. [first] is the card's tap
  /// target as well as one end of its span label.
  final DateTime first;
  final DateTime last;

  /// Marked days inside the window — the count, never the calendar distance
  /// between [first] and [last], which a sparse practice would inflate.
  final int dayCount;

  /// Every marked day, ascending — the same days [dayCount] counts, which is
  /// what lets the card's drill-down list exactly what the card claims. Kept
  /// here rather than re-walked on demand because a re-walk would lose the
  /// scan's `dayFilter` and quietly disagree with the number above it.
  final List<DateTime> days;

  /// Distinct named multi-day periods present in the window, in first-seen
  /// order. Empty for a window holding only weekly or single-day fasts; a
  /// single entry is what lets the card title itself "Nativity Fast" instead
  /// of falling back to the tradition's name.
  final List<FastingPeriod> spanPeriods;

  const FastingSummary({
    required this.tradition,
    required this.weekdays,
    required this.first,
    required this.last,
    required this.dayCount,
    required this.days,
    required this.spanPeriods,
  });
}

/// A [FastingSummary] still being accumulated by the in-window scan — one per
/// tradition, mutable for the same reason [_OpenFastingRun] is.
class _OpenFastingSummary {
  final FastingTradition tradition;

  /// Every marked day in order. The count is `days.length` rather than a
  /// counter kept beside it, so the number the card prints and the list its
  /// drill-down shows are structurally the same thing.
  final List<DateTime> days = <DateTime>[];
  final Set<int> weekdays = <int>{};
  final List<FastingPeriod> spanPeriods = <FastingPeriod>[];

  _OpenFastingSummary(this.tradition, DateTime first, FastingPeriod period) {
    _addDay(first);
    _addPeriod(period);
  }

  /// [day] is non-decreasing (the scan walks forward), and a tradition marks a
  /// day at most once — but the guard keeps this a list of *days* rather than
  /// of infos regardless of what a later rule change emits.
  void add(DateTime day, FastingPeriod period) {
    if (days.last != day) _addDay(day);
    _addPeriod(period);
  }

  void _addDay(DateTime day) {
    days.add(day);
    weekdays.add(day.weekday);
  }

  void _addPeriod(FastingPeriod period) {
    if (EventAgenda._isSpanPeriod(period) && !spanPeriods.contains(period)) {
      spanPeriods.add(period);
    }
  }

  FastingSummary close() => FastingSummary(
    tradition: tradition,
    weekdays: Set.unmodifiable(weekdays),
    first: days.first,
    last: days.last,
    dayCount: days.length,
    days: List.unmodifiable(days),
    spanPeriods: List.unmodifiable(spanPeriods),
  );
}

/// Expands recurrence rules across a date range into a flat, ordered agenda.
///
/// Deliberately kept out of `CalendarBloc`: the bloc's per-day cache backs
/// `TableCalendar.eventLoader` and must stay O(1), while an agenda query is a
/// one-shot O(days x events) scan driven by user input. Every day check is the
/// same O(1) [CalendarEvent.occursOn] the day cache uses, so the two surfaces
/// can never disagree about which days an event falls on.
abstract final class EventAgenda {
  /// Upper bound on how many days a single query may span. Bounds the scan
  /// regardless of what range a caller (or a custom date picker) asks for.
  static const int maxRangeDays = 366;

  /// Occurrences between [from] and [to] inclusive, ordered by day and then
  /// by the same rules the day summary panel uses within a day.
  ///
  /// Filters are applied to the event set once, before the day scan:
  /// [hiddenCategoryIds] mirrors the calendar's category filter,
  /// [priorities] keeps only the selected priorities (**empty means every
  /// priority** — the filter is off, not "nothing matches"), and [query] is
  /// an already-parsed [EventSearchQuery] whose terms are AND-ed and matched
  /// case- and diacritic-insensitively against the title, the description,
  /// the localized category label supplied in [categoryLabels] and — for date
  /// terms — the occurrence's own day.
  ///
  /// [labelTextOf] supplies the rest of what a row actually *shows* — its
  /// recurrence pattern, its time or "All day" badge, its priority word — so
  /// text visible on screen is text the search can find. A closure rather than
  /// a value for the same reason [categoryLabels] is a map: this file stays
  /// `AppLocalizations`-free, and the caller resolves the strings where a
  /// localization actually exists. See `AgendaSearchText.forEvent`.
  ///
  /// It is called **at most once per candidate event**, and only for events
  /// the title and category left unsettled — the same gate the description
  /// fold lives behind. Its answer cannot vary by day, so it never reaches the
  /// per-(event, day) path.
  static List<EventOccurrence> occurrencesInRange({
    required List<CalendarEvent> events,
    required DateTime from,
    required DateTime to,
    Set<String> hiddenCategoryIds = const {},
    Set<int> priorities = const {},
    EventSearchQuery query = EventSearchQuery.empty,
    Map<String, String> categoryLabels = const {},
    String Function(CalendarEvent event)? labelTextOf,
    AgendaEventType eventType = AgendaEventType.all,
    Set<String> categoryIds = const {},
    bool collapseRecurring = false,
  }) {
    // The events layer is hidden — no event occurrences, so the scan is skipped
    // entirely and only the annotation rows (holidays/fasting) interleave.
    if (eventType == AgendaEventType.none) return const [];
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;

    final searching = query.isNotEmpty;
    // Folded once per category, never per event or per occurrence: the catalog
    // is a handful of entries and the label is a property of the category, not
    // of the events wearing it.
    final categoryMasks = <String, int>{};
    if (searching) {
      categoryLabels.forEach((id, label) {
        final mask = query.maskOf(label);
        if (mask != 0) categoryMasks[id] = mask;
      });
    }
    // What each surviving candidate already satisfies, decided once per event
    // instead of once per (event, day) — **4.1**. Only an event carrying
    // per-day text, or a query carrying a date term, pays anything per day.
    final matchState = <String, _EventQueryMatch>{};
    final candidates = <CalendarEvent>[];
    for (final event in events) {
      final isOneTime = event.rule is OneTimeRecurrence;
      if (eventType == AgendaEventType.recurring && isOneTime) continue;
      if (eventType == AgendaEventType.oneTime && !isOneTime) continue;
      if (priorities.isNotEmpty && !priorities.contains(event.priority)) {
        continue;
      }
      if (hiddenCategoryIds.contains(event.categoryId)) continue;
      if (categoryIds.isNotEmpty && !categoryIds.contains(event.categoryId)) {
        continue;
      }
      if (!searching) {
        candidates.add(event);
        continue;
      }
      final base =
          query.maskOf(event.title) | (categoryMasks[event.categoryId] ?? 0);
      // Everything the title and the category already answer for is settled;
      // nothing below is folded for what they already closed, so a title hit
      // still costs neither a label nor a description fold.
      final baseSettles = query.couldSatisfy(base);
      // The row's own labels come **before** the description: they are short,
      // already on screen, and settling here spares a whole-description fold.
      // A template that still matches is folded either way, so every
      // description-fold budget this scan is pinned to stays where it was.
      var labels = 0;
      if (!baseSettles && labelTextOf != null) {
        labels = _labelFoldMask(labelTextOf(event), query);
      }
      final settled = base | labels;
      final settledSatisfies = labels == 0
          ? baseSettles
          : query.couldSatisfy(settled);
      var template = 0;
      if (!settledSatisfies) {
        final description = event.description;
        if (description != null) {
          template = _descriptionFoldMask(description, query);
        }
      }
      // Cheap existence probe — the per-day pass decides which days actually
      // match. Without it, an event whose only hit is a single day's override
      // never reaches the scan.
      final varies =
          !settledSatisfies &&
          OccurrenceDescriptions.appliesTo(event) &&
          OccurrenceDescriptions.hasAnyOverride(event.id);
      // Deliberately a *superset* test: with per-occurrence descriptions an
      // event may match only through text living on one specific day, so
      // dropping it here would make that text unfindable. A date term is
      // likewise treated as satisfiable here and narrowed per day below.
      if (!settledSatisfies &&
          !varies &&
          !query.couldSatisfy(settled | template)) {
        continue;
      }
      matchState[event.id] = _EventQueryMatch(
        base: base,
        labels: labels,
        template: template,
        varies: varies,
        always: !query.hasDateClauses && (settledSatisfies || !varies),
      );
      candidates.add(event);
    }
    if (candidates.isEmpty) return const [];

    // Prune candidates that provably cannot occur inside [start, end] before
    // the O(days x candidates) scan — a narrow window against a large store
    // leaves only a small fraction in play. Every survivor is still validated
    // through `occursOnUtcDay`, so this only ever drops non-occurrences. See
    // [partitionForWindow] for what the split does and why.
    final partition = partitionForWindow(candidates, start, end);
    final dense = partition.dense;
    final sparseByDay = partition.sparseByDay;
    final oneTimeByDay = partition.oneTimeByDay;
    if (dense.isEmpty && sparseByDay.isEmpty && oneTimeByDay.isEmpty) {
      return const [];
    }

    /// Whether [event] still matches the query **on this day**.
    ///
    /// Everything above the last line was decided once per event; only an
    /// event carrying per-occurrence text pays anything per day, and then only
    /// for the days it actually overrode. A live override wins over the
    /// template **including when its text is empty**, which is what preserves
    /// the documented asymmetry: a day whose override no longer mentions the
    /// needle drops out of *that day* even though the template still matches,
    /// and symmetrically an override on one day cannot drag the event's every
    /// other occurrence into the results.
    bool matchesQuery(CalendarEvent event, DateTime day) {
      if (!searching) return true;
      final state = matchState[event.id];
      if (state == null) return false;
      if (state.always) return true;
      // Both halves were decided once per event — the labels no more vary by
      // day than the title does.
      var mask = state.base | state.labels;
      if (state.varies) {
        final override = OccurrenceDescriptions.overrideFor(event.id, day);
        mask |= override == null
            ? state.template
            : _descriptionFoldMask(override, query);
      } else {
        mask |= state.template;
      }
      return query.satisfied(mask, day);
    }

    final result = <EventOccurrence>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      List<CalendarEvent>? onDay;
      for (final event in dense) {
        if (event.occursOnUtcDay(day) && matchesQuery(event, day)) {
          (onDay ??= <CalendarEvent>[]).add(event);
        }
      }
      final sparseToday = sparseByDay[day];
      if (sparseToday != null) {
        // A candidate day, not a decision: `occursOnUtcDay` stays the sole
        // arbiter, so the endDate clamp and cancelled occurrences still apply.
        for (final event in sparseToday) {
          if (event.occursOnUtcDay(day) && matchesQuery(event, day)) {
            (onDay ??= <CalendarEvent>[]).add(event);
          }
        }
      }
      final oneTimeToday = oneTimeByDay[day];
      if (oneTimeToday != null) {
        for (final event in oneTimeToday) {
          // The occurrence here is certain; only the search query narrows it,
          // and a one-time event's description never varies by day.
          if (matchesQuery(event, day)) {
            (onDay ??= <CalendarEvent>[]).add(event);
          }
        }
      }
      if (onDay == null) continue;
      onDay.sort(compareWithinDay);
      for (final event in onDay) {
        result.add(EventOccurrence(event: event, day: day));
      }
    }
    if (!collapseRecurring) return List.unmodifiable(result);

    // `result` is ascending by day, so the first time a recurring event's id is
    // seen is its next in-window occurrence — keep that, drop the rest, and
    // hand it the tally of what it now stands for. Two passes over an
    // already-built list: still a post-filter, not a scan short-circuit, so
    // `occursOn` call counts are unchanged.
    final counts = <String, int>{};
    for (final occ in result) {
      if (occ.event.rule is OneTimeRecurrence) continue;
      counts.update(occ.event.id, (n) => n + 1, ifAbsent: () => 1);
    }
    final seen = <String>{};
    final collapsed = <EventOccurrence>[];
    for (final occ in result) {
      if (occ.event.rule is OneTimeRecurrence) {
        collapsed.add(occ);
        continue;
      }
      if (!seen.add(occ.event.id)) continue;
      collapsed.add(
        EventOccurrence(
          event: occ.event,
          day: occ.day,
          occurrenceCountInWindow: counts[occ.event.id] ?? 1,
        ),
      );
    }
    return List.unmodifiable(collapsed);
  }

  /// Splits [events] into what a day-by-day scan of `[start, end]`
  /// (**inclusive** on both ends) actually needs to check, pruning what
  /// provably cannot occur in that span before any per-day work happens.
  /// Every survivor is still validated through `occursOnUtcDay` by the
  /// caller — this only ever drops non-occurrences, never decides membership
  /// itself.
  ///
  /// One-time events occur on exactly one day, so they are bucketed by it
  /// ([oneTimeByDay]) and never enter the per-day scan: a one-time event is
  /// never skipped (`CalendarEvent.occursOnUtcDay` only consults
  /// `EventSkips` for `rule is! OneTimeRecurrence`) and its rule is a bare
  /// `day == start`, so once the (rare) end-date clamp is honoured its
  /// placement on that day is certain.
  ///
  /// Every other survivor is asked for its candidate days
  /// ([RecurrenceRule.candidateDaysIn], **3.2b**) and lands in one of two
  /// places:
  ///
  /// * [sparseByDay] — the rule named the days it can fire on, so the event is
  ///   bucketed under each of them and the scan only reaches it there. Its
  ///   generator is O(occurrences), never O(window days), which is what makes
  ///   bucketing cheaper than the scan it replaces.
  /// * [dense] — the rule returned `null`, meaning "I cannot usefully prune
  ///   myself". Those events are scanned against every day in the window,
  ///   exactly as every recurring event was before 3.2b. A rule that fires
  ///   (nearly) daily belongs here: bucketing 214 days of a `Daily` event
  ///   costs far more than testing it 214 times.
  ///
  /// Only the start-guarded rules can additionally be pruned by their start —
  /// `SpecificDatesRecurrence` has no pre-start guard, since its dates may
  /// fall before `startDate`.
  ///
  /// Shared by [occurrencesInRange] (over its query-filtered candidates) and
  /// `CalendarBloc`'s grid-window partition (over the full event set): both
  /// feed the result into the same per-day `occursOnUtcDay` check, so a bug
  /// here moves both surfaces identically rather than making them disagree.
  static ({
    List<CalendarEvent> dense,
    Map<DateTime, List<CalendarEvent>> sparseByDay,
    Map<DateTime, List<CalendarEvent>> oneTimeByDay,
  })
  partitionForWindow(
    Iterable<CalendarEvent> events,
    DateTime start,
    DateTime end,
  ) {
    final dense = <CalendarEvent>[];
    final sparseByDay = <DateTime, List<CalendarEvent>>{};
    final oneTimeByDay = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      final endUtc = event.endDateUtc;
      // endDate clamps every rule at the model layer, so a series that ended
      // before the window has nothing left inside it.
      if (endUtc != null && endUtc.isBefore(start)) continue;
      final rule = event.rule;
      if (rule is OneTimeRecurrence) {
        final day = event.startDateUtc;
        if (day.isBefore(start) || day.isAfter(end)) continue;
        if (endUtc != null && day.isAfter(endUtc)) continue;
        (oneTimeByDay[day] ??= <CalendarEvent>[]).add(event);
        continue;
      }
      // Only the start-guarded rules can be pruned by their start.
      // `SpecificDatesRecurrence` has no pre-start guard — its dates may fall
      // before `startDate` — so it is never dropped here.
      if (rule is! SpecificDatesRecurrence &&
          !event.retroactive &&
          event.startDateUtc.isAfter(end)) {
        continue;
      }
      // The same endDate clamp, applied forwards: `occursOnUtcDay` rejects
      // every day past it, so generating those would only grow the buckets.
      final last = endUtc != null && endUtc.isBefore(end) ? endUtc : end;
      final candidateDays = rule.candidateDaysIn(
        start,
        last,
        event.startDateUtc,
        retroactive: event.retroactive,
      );
      if (candidateDays == null) {
        dense.add(event);
        continue;
      }
      for (final day in candidateDays) {
        (sparseByDay[day] ??= <CalendarEvent>[]).add(event);
      }
    }
    return (dense: dense, sparseByDay: sparseByDay, oneTimeByDay: oneTimeByDay);
  }

  /// Groups an already-scanned occurrence list into one summary per category —
  /// the agenda's `summary` event presentation.
  ///
  /// A **post-pass**, never a scan: it walks [occurrences] once and touches no
  /// facade, so it costs nothing in `CalendarEvent.occursOn` calls and cannot
  /// see days the scan (and its filters, and the search query) already
  /// excluded. Same discipline as the collapse post-filter above.
  ///
  /// [occurrences] must be the scan's own output — ascending by day — which is
  /// what makes `first`/`last` and the per-category order fall out for free.
  /// Categories are ordered by their first in-window occurrence, matching the
  /// time ordering of everything else in the agenda.
  ///
  /// [hideMissed] is the `CalendarMissedDisplay.hidden` half of presence
  /// (**v26**), resolved here — once, in the aggregation layer — rather than
  /// re-filtered per surface. A hidden occurrence never reaches a row in
  /// `buildAgendaRows` or an entry in `AgendaListView.eventDayEntries`, so a
  /// card counting it would promise a drill-down that opens empty. A category
  /// left with nothing produces **no card at all**, which is the same rule the
  /// day walk applies to a day it emptied. `faded` changes nothing: those
  /// occurrences still render, so they still count.
  static List<EventCategorySummary> categorySummariesOf(
    List<EventOccurrence> occurrences, {
    bool hideMissed = false,
  }) {
    if (occurrences.isEmpty) return const [];
    final byCategory = <String, List<EventOccurrence>>{};
    for (final occurrence in occurrences) {
      if (hideMissed &&
          EventPresence.appliesTo(occurrence.event) &&
          EventPresence.isMissed(occurrence.event.id, occurrence.day)) {
        continue;
      }
      (byCategory[occurrence.event.categoryId] ??= <EventOccurrence>[]).add(
        occurrence,
      );
    }
    return [
      // `byCategory` preserves first-insertion order, and the input is
      // ascending, so this is already "whichever category comes up first".
      for (final entry in byCategory.entries)
        EventCategorySummary(
          categoryId: entry.key,
          occurrences: List.unmodifiable(entry.value),
          eventCount: {for (final o in entry.value) o.event.id}.length,
          first: entry.value.first.day,
          last: entry.value.last.day,
        ),
    ];
  }

  /// Public holidays falling inside the range, in ascending order.
  ///
  /// Kept separate from [occurrencesInRange] because a holiday is a property
  /// of the day rather than an event: it has no id, no category and nothing
  /// to edit. Callers that opt in merge the two lists when grouping by day.
  static List<DateTime> holidayDaysInRange({
    required DateTime from,
    required DateTime to,
  }) {
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;
    final days = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (PublicHolidays.isHoliday(day)) days.add(day);
    }
    return days;
  }

  /// Fasting days falling inside the range, in ascending order. Empty when no
  /// fasting tradition is configured ([FastingCalendar.isEnabled] false), so a
  /// caller that toggles it on pays nothing until the user opts in. Mirrors
  /// [holidayDaysInRange]; both are properties of the day, not events.
  static List<DateTime> fastingDaysInRange({
    required DateTime from,
    required DateTime to,
  }) {
    if (!FastingCalendar.isEnabled) return const [];
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;
    final days = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (FastingCalendar.isFastingDay(day)) days.add(day);
    }
    return days;
  }

  /// Fasting days inside the range, grouped into runs **per fasting period**.
  ///
  /// The collapse counterpart of [fastingDaysInRange]: forty Lent rows become
  /// one. Grouping is by ([FastingTradition], [FastingPeriod]) rather than by
  /// "this day fasts", because the boolean is not enough for either direction —
  /// a period the personal schedule sparsified is still one period, and two
  /// different periods that happen to touch are still two.
  ///
  /// Each run's [FastingRun.start] / [FastingRun.end] are walked **outward past
  /// the window** so a clipped run still reports its real extent, bounded by
  /// [maxRangeDays] steps in each direction.
  ///
  /// [dayFilter] narrows which days count as fasting — the agenda passes its
  /// text query — and is applied to the outward walk too, so a run never claims
  /// an extent made of days the filter excluded. A filtered-out day counts as
  /// unmarked for every run, exactly as an unfasted day does.
  ///
  /// Reads only the memoized [FastingCalendar]; never `CalendarEvent.occursOn`.
  static List<FastingRun> fastingRunsInRange({
    required DateTime from,
    required DateTime to,
    bool Function(DateTime day)? dayFilter,
  }) {
    if (!FastingCalendar.isEnabled) return const [];
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;

    // Insertion order is kept alongside the run so the final sort can stay
    // stable: several runs legitimately share a `day` when traditions or
    // periods overlap, and Dart's `sort` is not stable on its own.
    final closed = <({FastingRun run, int order})>[];
    final open =
        <
          ({FastingTradition tradition, FastingPeriod period}),
          _OpenFastingRun
        >{};
    var order = 0;

    void close(_OpenFastingRun run) {
      final maxGap = _maxFastingGap(run.period);
      final backward = _walkFastingEdge(
        run.day,
        run.tradition,
        run.period,
        maxGap,
        dayFilter,
        forward: false,
      );
      final forward = _walkFastingEdge(
        run.last,
        run.tradition,
        run.period,
        maxGap,
        dayFilter,
        forward: true,
      );
      closed.add((
        run: FastingRun(
          day: run.day,
          start: backward.edge,
          end: forward.edge,
          tradition: run.tradition,
          period: run.period,
          dayCount: run.dayCount + backward.marked + forward.marked,
        ),
        order: order++,
      ));
    }

    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (dayFilter != null && !dayFilter(day)) continue;
      for (final info in FastingCalendar.on(day)) {
        final key = (tradition: info.tradition, period: info.period);
        final current = open[key];
        if (current != null) {
          if (day.difference(current.last).inDays - 1 <=
              _maxFastingGap(info.period)) {
            current.last = day;
            current.dayCount++;
            continue;
          }
          close(current);
        }
        open[key] = _OpenFastingRun(info.tradition, info.period, day);
      }
    }
    for (final run in open.values) {
      close(run);
    }

    closed.sort((a, b) {
      final byDay = a.run.day.compareTo(b.run.day);
      return byDay != 0 ? byDay : a.order.compareTo(b.order);
    });
    return [for (final entry in closed) entry.run];
  }

  /// The whole window's fasting, digested to **one [FastingSummary] per
  /// enabled tradition** — the agenda's `summary` presentation.
  ///
  /// The third and most condensed counterpart of [fastingDaysInRange] and
  /// [fastingRunsInRange]. Unlike runs, it never walks outward past the
  /// window: a summary answers "what does fasting look like here", so every
  /// number it carries is in-window by construction.
  ///
  /// [dayFilter] narrows which days count, exactly as it does for runs — the
  /// agenda passes its text query, and a filtered-out day is unmarked for
  /// every summary.
  ///
  /// Traditions with no marked day in the window produce nothing, and the
  /// result follows [FastingTradition] declaration order, matching the order
  /// [FastingCalendar.on] emits its infos in.
  ///
  /// Reads only the memoized [FastingCalendar]; never `CalendarEvent.occursOn`.
  static List<FastingSummary> fastingSummariesInRange({
    required DateTime from,
    required DateTime to,
    bool Function(DateTime day)? dayFilter,
  }) {
    if (!FastingCalendar.isEnabled) return const [];
    final range = resolveRange(from, to);
    if (range == null) return const [];
    final (start, end) = range;

    final open = <FastingTradition, _OpenFastingSummary>{};
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      if (dayFilter != null && !dayFilter(day)) continue;
      for (final info in FastingCalendar.on(day)) {
        final current = open[info.tradition];
        if (current == null) {
          open[info.tradition] = _OpenFastingSummary(
            info.tradition,
            day,
            info.period,
          );
          continue;
        }
        current.add(day, info.period);
      }
    }
    if (open.isEmpty) return const [];
    return [
      for (final tradition in FastingTradition.values)
        if (open[tradition] case final summary?) summary.close(),
    ];
  }

  /// Named multi-day periods, whose days may be **sparse**: the personal
  /// weekday/month schedule can thin any of them out, and Cheesefare week is
  /// Wed/Fri-only by the rule itself. Their runs bridge a gap of up to
  /// [_spanFastingGap] days so the period reads as one row.
  ///
  /// Everything else — the year-round weekly fasts, the single-day fasts and
  /// forced personal days — keeps strict contiguity. Bridging a weekly fast
  /// would fuse a whole window into one span that means nothing.
  static bool _isSpanPeriod(FastingPeriod period) => switch (period) {
    FastingPeriod.greatLent ||
    FastingPeriod.apostlesFast ||
    FastingPeriod.dormitionFast ||
    FastingPeriod.nativityFast ||
    FastingPeriod.cheesefareWeek ||
    FastingPeriod.lent ||
    FastingPeriod.advent ||
    FastingPeriod.ramadan => true,
    _ => false,
  };

  /// A week: wide enough to bridge any weekday pattern (even a single kept
  /// weekday leaves six unmarked days), narrow enough that two consecutive
  /// years' Nativity fasts can never join.
  static const int _spanFastingGap = 7;

  static int _maxFastingGap(FastingPeriod period) =>
      _isSpanPeriod(period) ? _spanFastingGap : 0;

  /// Extends one end of a run past the window, following the same period and
  /// the same gap rule, and reports how many marked days it added.
  ///
  /// Steps are capped at [maxRangeDays] per direction — counted as *steps*, not
  /// as matches, so a pathological configuration cannot walk forever.
  static ({DateTime edge, int marked}) _walkFastingEdge(
    DateTime from,
    FastingTradition tradition,
    FastingPeriod period,
    int maxGap,
    bool Function(DateTime day)? dayFilter, {
    required bool forward,
  }) {
    final step = Duration(days: forward ? 1 : -1);
    var edge = from;
    var marked = 0;
    var gap = 0;
    var cursor = from;
    for (var i = 0; i < maxRangeDays; i++) {
      cursor = cursor.add(step);
      final hit =
          (dayFilter?.call(cursor) ?? true) &&
          FastingCalendar.on(
            cursor,
          ).any((info) => info.tradition == tradition && info.period == period);
      if (hit) {
        edge = cursor;
        marked++;
        gap = 0;
        continue;
      }
      gap++;
      if (gap > maxGap) break;
    }
    return (edge: edge, marked: marked);
  }

  /// Normalizes and clamps a requested range, or `null` when it is empty.
  /// Shared so the event scan and the holiday scan can never disagree about
  /// which days are in view.
  static (DateTime, DateTime)? resolveRange(DateTime from, DateTime to) {
    final start = dateOnly(from);
    final requestedEnd = dateOnly(to);
    if (requestedEnd.isBefore(start)) return null;
    final maxEnd = start.add(const Duration(days: maxRangeDays - 1));
    return (start, requestedEnd.isAfter(maxEnd) ? maxEnd : requestedEnd);
  }

  /// Ordering of two events falling on the same day: higher priority first —
  /// P1 before P5, so **ascending** on the stored number (matching the
  /// day-cell bar stack) — then all-day before timed, then by start time,
  /// then by title so the order is stable across rebuilds.
  ///
  /// The **single comparator** for same-day event order — the agenda sorts
  /// occurrences with it and `EventSummaryProvider` emits day-panel entries
  /// through it, so the two surfaces cannot disagree.
  static int compareWithinDay(CalendarEvent a, CalendarEvent b) {
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) return byPriority;
    final aTime = a.time;
    final bTime = b.time;
    if (aTime == null && bTime != null) return -1;
    if (aTime != null && bTime == null) return 1;
    if (aTime != null && bTime != null) {
      final byStart = aTime.startMinute.compareTo(bTime.startMinute);
      if (byStart != 0) return byStart;
    }
    final byTitle = a.titleFold.compareTo(b.titleFold);
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  }

  /// Date-only UTC normalization, matching `CalendarBloc._dateOnly`.
  static DateTime dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// Counts description folds performed by [occurrencesInRange] — the work
  /// **4.1** exists to bound. Incremented inside an `assert`, so both the
  /// statement and its closure are stripped from profile and release builds
  /// and cost nothing there, mirroring `CalendarEvent.debugOccursOnCalls`.
  ///
  /// A fold copies a whole description (up to the settings-capped ceiling)
  /// through the shared search normalization, and a top-level function has no
  /// injection seam, so this is what lets a test assert that the scan folds a
  /// template **once per event** rather than once per (event, day). Title
  /// folds are deliberately not counted: those were already once per event
  /// before 4.1.
  @visibleForTesting
  static int debugDescriptionFolds = 0;

  /// Folds [text] into [query]'s term bits, counting the fold. The one place a
  /// description is normalized during a scan, so [debugDescriptionFolds]
  /// cannot drift from what actually happens.
  static int _descriptionFoldMask(String text, EventSearchQuery query) {
    assert(() {
      debugDescriptionFolds++;
      return true;
    }());
    return query.maskOf(text);
  }

  /// Counts calls to `occurrencesInRange`'s `labelTextOf` closure. Mirrors
  /// [debugDescriptionFolds] exactly, `assert`-only so it costs nothing in
  /// profile and release builds.
  ///
  /// The closure builds several localized strings — a recurrence phrase, a
  /// formatted time range — so the property worth pinning is that it runs
  /// **once per candidate event**, never once per (event, day), and not at all
  /// when the title or the category already settled the query.
  @visibleForTesting
  static int debugLabelFolds = 0;

  /// Folds [text] into [query]'s term bits, counting the fold. The one place a
  /// row's display labels are normalized during a scan, so [debugLabelFolds]
  /// cannot drift from what actually happens.
  static int _labelFoldMask(String text, EventSearchQuery query) {
    assert(() {
      debugLabelFolds++;
      return true;
    }());
    return query.maskOf(text);
  }
}

/// What a candidate event already satisfies of the active query, resolved once
/// per event by [EventAgenda.occurrencesInRange]'s pre-filter.
///
/// [base] holds the term bits the title and the category label answer for —
/// neither varies by day. [labels] holds the bits the row's own rendered
/// labels answer for (recurrence pattern, time or "All day", priority word),
/// folded once for what [base] left open and just as day-invariant.
/// [template] holds the template description's bits, folded only for what the
/// two above left open. [varies] means the day loop has to ask
/// [OccurrenceDescriptions] whether this day overrode that template, and a
/// live override **replaces** [template] rather than adding to it, including
/// when its text is empty. [always] short-circuits the whole thing for the
/// common case: no date term to narrow by, and nothing left for a day to
/// change.
class _EventQueryMatch {
  final int base;
  final int labels;
  final int template;
  final bool varies;
  final bool always;

  const _EventQueryMatch({
    required this.base,
    required this.labels,
    required this.template,
    required this.varies,
    required this.always,
  });
}
