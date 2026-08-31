import 'package:flutter/painting.dart';

import '../constants/calendar_categories.dart';
import '../constants/event_presence.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_rail_mark.dart';
import '../models/recurrence_rule.dart';
import 'resolver_chain.dart';

/// **The** membership definition for the day-cell rail. Both the rail provider
/// and `EventDayBarProvider`'s exclusion read this one function — a second copy
/// would let the two channels disagree about the same event, dropping it from
/// the grid entirely.
///
/// The recurrence guard sits here rather than on the column, so an explicit
/// `showInDayRail == true` on a one-time event still stays out: a day that
/// happens once has no attendance streak to scan across a month.
///
/// `NULL` (the default, and every pre-v34 row) means *auto* — the event is in
/// the rail exactly when presence tracking applies to it, so the schema change
/// needed no backfill:
///
/// ```
/// showInDayRail == null
///     ? EventPresence.appliesTo(event)
///     : showInDayRail && event.rule is! OneTimeRecurrence
/// ```
bool eventInDayRail(CalendarEvent event) =>
    event.rule is! OneTimeRecurrence &&
    (event.showInDayRail ?? event.tracksPresence);

/// Contract for anything that contributes marks to a day cell's rail.
///
/// Providers must be pure & cheap: [marksFor] is called for every visible cell
/// on every rebuild. Avoid I/O, allocations beyond what is needed, and do not
/// call BLoCs from here.
abstract interface class DayRailProvider {
  Iterable<DayRailMark> marksFor(DateTime day, List<CalendarEvent> events);
}

/// Emits one mark per rail-eligible event on the day, in arrival order.
///
/// Colour resolution matches `EventDayBarProvider` — the event's explicit
/// override, else its category colour — but the missed alpha is **not** applied
/// here: [DayRailMark.missed] carries the state and `CalendarDayRail` renders
/// it, which is what lets `dot` style draw a missed mark hollow.
///
/// Presence (**v26**) is applied the same way and in the same order the bar
/// provider applies it: a hidden missed mark is skipped **before** it is added,
/// so it never consumes one of the rail's `maxDayRailMarks` slots. Cost is two
/// static map probes per event, no allocation.
class EventDayRailProvider implements DayRailProvider {
  final AppLocalizations l10n;
  final CalendarMissedDisplay missedDisplay;

  const EventDayRailProvider(
    this.l10n, {
    this.missedDisplay = CalendarMissedDisplay.faded,
  });

  @override
  Iterable<DayRailMark> marksFor(DateTime day, List<CalendarEvent> events) {
    if (events.isEmpty) return const [];
    // `events` arrives pre-sorted by `EventAgenda.compareWithinDay` from
    // `CalendarBloc.eventsForDay`, exactly as `EventDayBarProvider` assumes;
    // never copy and re-sort here.
    List<DayRailMark>? marks;
    for (final event in events) {
      if (!eventInDayRail(event)) continue;
      // `appliesTo` first, exactly as the bar provider does: an event forced
      // into the rail without presence tracking has no attendance to report,
      // and stale marks left by a since-untracked event must not dim it.
      final missed =
          EventPresence.appliesTo(event) &&
          EventPresence.isMissed(event.id, day);
      if (missed && missedDisplay == CalendarMissedDisplay.hidden) continue;
      final color = event.colorValue != null
          ? Color(event.colorValue!)
          : CalendarCategories.resolve(event.categoryId).color;
      (marks ??= <DayRailMark>[]).add(
        DayRailMark(
          // Shares the bar keyspace via the same precomputed `late final`
          // string, so a rail mark and its bar dedup identically and no
          // per-cell string is allocated.
          key: event.barKey,
          color: color,
          priority: event.priority - kMinEventPriority,
          missed: missed,
          semanticLabel: missed
              ? l10n.calendarRailMarkMissedLabel(event.title)
              : event.title,
        ),
      );
    }
    return marks ?? const [];
  }
}

/// Chains a list of [DayRailProvider]s into a sorted, deduplicated list of
/// marks for a given day.
///
/// Note: this resolver does **not** cap the returned list, mirroring
/// `DayBarsResolver`. `CalendarDayRail` decides how many marks fit and renders
/// the overflow affordance for the remainder, controlled by the user's
/// `calendarMaxDayRailMarks` setting.
class DayRailResolver {
  final List<DayRailProvider> providers;

  const DayRailResolver({required this.providers});

  /// Default resolver bundling the one shipped provider. Deliberately still a
  /// chain: a fasting or streak rail would slot in here without touching a
  /// call site.
  factory DayRailResolver.defaults(
    AppLocalizations l10n, {
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) {
    return DayRailResolver(
      providers: [EventDayRailProvider(l10n, missedDisplay: missedDisplay)],
    );
  }

  List<DayRailMark> resolve(DateTime day, List<CalendarEvent> events) =>
      resolveChain(providers.map((p) => p.marksFor(day, events)));
}
