import 'package:equatable/equatable.dart';

import '../constants/alert_constants.dart';
import '../models/calendar_event.dart';
import '../models/date_range.dart';
import '../models/event_digest.dart';
import '../models/upcoming_agenda_filters.dart';
import 'alert_planner.dart';
import 'event_agenda.dart';

/// One digest, at one instant, listing one span — the unit the scheduler arms
/// beside the alerts' [PlannedFire]s.
///
/// [fireAt] is a **local** wall-clock instant; [spanStart] and [spanEnd] are
/// **date-only UTC** and inclusive, the overview's own kind of day, so the
/// span a tap opens is the span the notification counted.
class PlannedDigest extends Equatable implements PlannedEntry {
  final EventDigest digest;

  @override
  final DateTime fireAt;

  final DateTime spanStart;
  final DateTime spanEnd;

  /// Every occurrence in the span, sorted by day then `compareWithinDay` —
  /// the overview's every-occurrence rows.
  final List<EventOccurrence> entries;

  const PlannedDigest({
    required this.digest,
    required this.fireAt,
    required this.spanStart,
    required this.spanEnd,
    required this.entries,
  });

  @override
  String get alertId => digest.id;

  /// A digest belongs to no event.
  @override
  String get eventId => '';

  /// The span's first day: one entry per span, so a re-planned span lands on
  /// its own registration.
  @override
  DateTime get day => spanStart;

  @override
  AlertKind get kind => AlertKind.digest;

  @override
  AlertRegistrationSource get source => AlertRegistrationSource.digest;

  @override
  List<Object?> get props => [
    digest.id,
    fireAt,
    spanStart,
    spanEnd,
    entries.length,
  ];
}

/// Turns digests and the events into the digest entries the OS should hold.
/// **Pure**, `now` injected — [AlertPlanner]'s twin.
///
/// Outside the alerts' horizon on purpose ([DigestHorizon]): a digest's next
/// fires are taken whatever their distance, and its span is listed through
/// the overview's own scan, with the digest's allowlist and nothing else — the
/// grid filter's denylist is not an input, so an archived category's events
/// still list here as they do on the overview.
abstract final class DigestPlanner {
  /// The first [DigestHorizon.maxDigests] **enabled** digests in display
  /// order, each at its next [DigestHorizon.perDigest] instants strictly after
  /// [now], soonest first. An instant whose span lists nothing is left out
  /// unless the digest says [EventDigest.includeEmpty]; the instant after it
  /// is not looked for in its place.
  static List<PlannedDigest> plan({
    required List<EventDigest> digests,
    required List<CalendarEvent> events,
    required DigestHorizon horizon,
    required DateTime now,
  }) {
    final enabled = [
      for (final digest in digests)
        if (digest.enabled) digest,
    ]..sort(_byDisplayOrder);
    final planned = <PlannedDigest>[];
    for (final digest in enabled.take(horizon.maxDigests)) {
      for (final fire in _fires(digest, now).take(horizon.perDigest)) {
        final span = spanFor(digest, fire.day);
        final entries = EventAgenda.occurrencesInRange(
          events: events,
          from: span.start,
          to: span.end,
          categoryIds: digest.categoryIds,
          eventType: AgendaEventType.all,
          collapseRecurring: false,
        );
        if (entries.isEmpty && !digest.includeEmpty) continue;
        planned.add(
          PlannedDigest(
            digest: digest,
            fireAt: fire.at,
            spanStart: span.start,
            spanEnd: span.end,
            entries: entries,
          ),
        );
      }
    }
    // Spelled out for [AlertPlanner.plan]'s reason: `List.sort` is not stable,
    // and two digests at one instant must come out in one order every pass.
    planned.sort((a, b) {
      final byInstant = a.fireAt.compareTo(b.fireAt);
      if (byInstant != 0) return byInstant;
      return a.digest.id.compareTo(b.digest.id);
    });
    return planned;
  }

  /// The days [digest] covers when it fires on [fireDayUtc] (D9): from
  /// `fireDay + leadDays`, one day, seven days, or up to the day before the
  /// same day next month — so monthly on the 1st is the calendar month.
  /// Date-only UTC arithmetic throughout, which no DST can move.
  static DateRange spanFor(EventDigest digest, DateTime fireDayUtc) {
    final start = DateTime.utc(
      fireDayUtc.year,
      fireDayUtc.month,
      fireDayUtc.day + _leadOf(digest),
    );
    final end = switch (digest.cadence) {
      DigestCadence.daily => start,
      DigestCadence.weekly => DateTime.utc(
        start.year,
        start.month,
        start.day + 6,
      ),
      DigestCadence.monthly => DateTime.utc(
        start.year,
        start.month + 1,
        start.day - 1,
      ),
    };
    return (start: start, end: end);
  }

  /// [digest]'s next [count] fire instants strictly after [now], soonest
  /// first — whether or not their spans list anything.
  static List<DateTime> nextFireInstants(
    EventDigest digest, {
    required DateTime now,
    required int count,
  }) => [for (final fire in _fires(digest, now).take(count)) fire.at];

  /// Every fire of [digest] strictly after [now], soonest first. Lazy and
  /// endless: only today's candidate can be behind [now], so taking `n` of
  /// them walks `n + 1` candidate days at most.
  ///
  /// The instant is the wall-clock constructor on the fire day, never a
  /// `Duration` added to local midnight — the DST rule [AlertPlanner.fireInstant]
  /// keeps, for the same reason.
  static Iterable<({DateTime day, DateTime at})> _fires(
    EventDigest digest,
    DateTime now,
  ) sync* {
    final today = DateTime.utc(now.year, now.month, now.day);
    final minute = _minuteOf(digest);
    for (final day in _fireDays(digest, today)) {
      final at = DateTime(day.year, day.month, day.day, 0, minute);
      if (at.isAfter(now)) yield (day: day, at: at);
    }
  }

  /// The days [digest] fires on from [today], date-only UTC, endlessly.
  static Iterable<DateTime> _fireDays(
    EventDigest digest,
    DateTime today,
  ) sync* {
    final anchor = EventDigest.clampAnchor(digest.cadence, digest.anchor);
    switch (digest.cadence) {
      case DigestCadence.daily:
        for (var offset = 0; ; offset++) {
          yield DateTime.utc(today.year, today.month, today.day + offset);
        }
      case DigestCadence.weekly:
        final first = (anchor - today.weekday) % DateTime.daysPerWeek;
        for (var offset = first; ; offset += DateTime.daysPerWeek) {
          yield DateTime.utc(today.year, today.month, today.day + offset);
        }
      case DigestCadence.monthly:
        // The anchor is at most 28, so every month has the day.
        final skip = today.day > anchor ? 1 : 0;
        for (var month = today.month + skip; ; month++) {
          yield DateTime.utc(today.year, month, anchor);
        }
    }
  }

  // What a digest says is read clamped to the ranges [EventDigest] asserts:
  // a release build carries no asserts, and a minute past the day or a 31st
  // would move a fire to another day, or skip months, without a word.
  static int _minuteOf(EventDigest digest) =>
      digest.minute.clamp(0, EventDigest.lastMinute);

  static int _leadOf(EventDigest digest) =>
      digest.leadDays.clamp(0, EventDigest.maxLeadDays);

  /// The ids of the **enabled** digests [plan] leaves out: everything past
  /// [DigestHorizon.maxDigests] in the planner's own display order.
  ///
  /// The cap lived in `create` and the sheet only, so sync could carry a
  /// database past it — `nextSortOrder()` is per device, so two devices both
  /// number their digests `0..n` and the surviving ten are an interleave — and
  /// the over-cap cards sat in the hub with their switches on, firing nothing
  /// and saying nothing. This is what lets the hub say so.
  ///
  /// The order is [plan]'s, and nothing re-denses `sort_order`: it is a synced
  /// column, and a merge that rewrote it would fight between devices.
  static Set<String> overCapIds({
    required List<EventDigest> digests,
    required DigestHorizon horizon,
  }) {
    final enabled = [
      for (final digest in digests)
        if (digest.enabled) digest,
    ];
    if (enabled.length <= horizon.maxDigests) return const {};
    enabled.sort(_byDisplayOrder);
    return {
      for (final digest in enabled.skip(horizon.maxDigests)) digest.id,
    };
  }

  static int _byDisplayOrder(EventDigest a, EventDigest b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  }
}
