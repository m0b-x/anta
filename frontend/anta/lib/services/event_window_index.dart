import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

/// The event store bucketed so a scan over a window touches the recurring
/// events plus that window's one-time events, never the whole store.
///
/// About 95% of a large store is one-time events, and every scan outside the
/// grid's memoised window — a picker month, an overview year, the upcoming
/// agenda, a digest's span, the report — used to walk all of them to drop the
/// ones whose single day lies elsewhere. A one-time event occurs on its start
/// day and nowhere else (`OneTimeRecurrence.occursOn` is `day == start`;
/// `endDate` only clamps, it never extends), so its start month is the one
/// bucket that can hold it: no multi-day span to cover.
///
/// **A narrowing, never a decision.** [eventsPossiblyIn] returns candidates;
/// `CalendarEvent.occursOnUtcDay` stays the sole arbiter of occurrence, and a
/// one-time event of a touched month that falls outside the window, is
/// cancelled or is clamped away is still dropped by the caller's own checks.
/// Every non-one-time rule — `SpecificDatesRecurrence` included, whose dates
/// may lie anywhere — is returned for every window.
///
/// Built once per list instance ([of]): the store's lists are replaced on
/// every write, never mutated in place, so a list's identity names its
/// contents.
final class EventWindowIndex {
  EventWindowIndex._(this._events, this._recurring, this._byMonth)
    : _length = _events.length;

  /// The indexed list itself, which every position below points into.
  final List<CalendarEvent> _events;

  /// [_events]' length when it was indexed.
  final int _length;

  /// Positions of the events that are not one-time, ascending.
  final List<int> _recurring;

  /// Positions of the one-time events per [_monthKey] of their start day,
  /// each ascending.
  final Map<int, List<int>> _byMonth;

  /// [_recurring]'s events, built once: the answer for every window that
  /// holds no one-time event.
  late final List<CalendarEvent> _recurringEvents = List.unmodifiable([
    for (final i in _recurring) _events[i],
  ]);

  /// One index per live list, keyed by identity and dropped with the list:
  /// the bloc's copy, a filtered grid list and the service's own list each
  /// keep theirs, so readers alternating between them never rebuild.
  static final Expando<EventWindowIndex> _memo = Expando('EventWindowIndex');

  /// Makes [eventsPossiblyIn] hand back the whole list, as every scan did
  /// before the index — the reference a differential test compares with.
  /// Read in debug builds only; a release build never consults it.
  @visibleForTesting
  static bool debugFullScan = false;

  /// The index of [events], built on the first ask for this instance.
  ///
  /// A cached index whose length no longer matches is rebuilt: no list in
  /// the app changes after it is handed out, so this only ever catches a
  /// caller that grew one in place.
  static EventWindowIndex of(List<CalendarEvent> events) {
    final cached = _memo[events];
    if (cached != null && cached._length == events.length) {
      return cached;
    }
    return _memo[events] = EventWindowIndex._build(events);
  }

  factory EventWindowIndex._build(List<CalendarEvent> events) {
    final recurring = <int>[];
    final byMonth = <int, List<int>>{};
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.rule is OneTimeRecurrence) {
        (byMonth[_monthKey(event.startDateUtc)] ??= <int>[]).add(i);
      } else {
        recurring.add(i);
      }
    }
    return EventWindowIndex._(events, recurring, byMonth);
  }

  static int _monthKey(DateTime day) => day.year * 12 + day.month - 1;

  /// The events that may occur between [fromUtcDay] and [toUtcDay]
  /// (inclusive, date-only UTC): every event that is not one-time, and the
  /// one-time events starting in a month the window touches — in the order
  /// the indexed list holds them, so a caller iterating this instead of the
  /// list sees the same events in the same relative order, minus one-time
  /// events that could not have occurred.
  ///
  /// The result must not be modified; it may be shared between calls.
  List<CalendarEvent> eventsPossiblyIn(DateTime fromUtcDay, DateTime toUtcDay) {
    if (kDebugMode && debugFullScan) return _events;
    if (toUtcDay.isBefore(fromUtcDay) || _byMonth.isEmpty) {
      return _recurringEvents;
    }
    final first = _monthKey(fromUtcDay);
    final last = _monthKey(toUtcDay);
    final buckets = <List<int>>[];
    if (last - first + 1 <= _byMonth.length) {
      for (var key = first; key <= last; key++) {
        final bucket = _byMonth[key];
        if (bucket != null) buckets.add(bucket);
      }
    } else {
      // A window wider than the months the store holds: walking the buckets
      // is cheaper than walking the window.
      for (final MapEntry(:key, value: bucket) in _byMonth.entries) {
        if (key >= first && key <= last) buckets.add(bucket);
      }
    }
    if (buckets.isEmpty) return _recurringEvents;
    if (buckets.length == 1 && _recurring.isEmpty) {
      return [for (final i in buckets.single) _events[i]];
    }
    final positions = <int>[..._recurring];
    for (final bucket in buckets) {
      positions.addAll(bucket);
    }
    positions.sort();
    return [for (final i in positions) _events[i]];
  }
}
