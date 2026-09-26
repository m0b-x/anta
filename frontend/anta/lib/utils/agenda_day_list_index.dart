import 'package:flutter/painting.dart' show Color;

import '../models/agenda_day_list.dart';

bool _isDateOnlyUtc(DateTime day) =>
    day.isUtc &&
    day.hour == 0 &&
    day.minute == 0 &&
    day.second == 0 &&
    day.millisecond == 0 &&
    day.microsecond == 0;

int _daysInMonthOf(int year, int month) => DateTime.utc(year, month + 1, 0).day;

class AgendaDayListIndex {
  final DateTime windowStart;
  final DateTime windowEnd;

  final List<DateTime> months;

  final List<DateTime> days;

  final int totalCount;

  final Map<int, List<AgendaDayListEntry>> _byDay;
  final Map<int, List<AgendaDayListEntry>> _byMonth;
  final Map<int, int> _keptByDay;
  final Map<int, int> _keptByMonth;
  final Map<int, int> _markedMasks;
  final Map<int, int> _missedMasks;
  final Map<int, int> _windowMasks;

  AgendaDayListIndex._({
    required this.windowStart,
    required this.windowEnd,
    required this.months,
    required this.days,
    required this.totalCount,
    required Map<int, List<AgendaDayListEntry>> byDay,
    required Map<int, List<AgendaDayListEntry>> byMonth,
    required Map<int, int> keptByDay,
    required Map<int, int> keptByMonth,
    required Map<int, int> markedMasks,
    required Map<int, int> missedMasks,
    required Map<int, int> windowMasks,
  }) : _byDay = byDay,
       _byMonth = byMonth,
       _keptByDay = keptByDay,
       _keptByMonth = keptByMonth,
       _markedMasks = markedMasks,
       _missedMasks = missedMasks,
       _windowMasks = windowMasks;

  static int _dayKey(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

  static int _monthKey(DateTime day) => day.year * 12 + (day.month - 1);

  static AgendaDayListIndex build(
    List<AgendaDayListEntry> entries, {
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    assert(_isDateOnlyUtc(windowStart), 'windowStart must be date-only UTC');
    assert(_isDateOnlyUtc(windowEnd), 'windowEnd must be date-only UTC');
    assert(
      !windowEnd.isBefore(windowStart),
      'windowEnd must not precede windowStart',
    );

    var start = windowStart;
    var end = windowEnd;
    final byDay = <int, List<AgendaDayListEntry>>{};
    final byMonth = <int, List<AgendaDayListEntry>>{};
    final keptByDay = <int, int>{};
    final keptByMonth = <int, int>{};
    final markedMasks = <int, int>{};

    for (final entry in entries) {
      assert(_isDateOnlyUtc(entry.day), 'entry days must be date-only UTC');
      final day = entry.day;
      if (day.isBefore(start)) start = day;
      if (day.isAfter(end)) end = day;
      final dayKey = _dayKey(day);
      (byDay[dayKey] ??= <AgendaDayListEntry>[]).add(entry);
      final monthKey = _monthKey(day);
      (byMonth[monthKey] ??= <AgendaDayListEntry>[]).add(entry);
      markedMasks[monthKey] =
          (markedMasks[monthKey] ?? 0) | (1 << (day.day - 1));
      // Attendance is the default, so the kept tallies count up from the
      // entries that were *not* missed rather than subtracting later: a
      // hidden-mode list never carries a missed entry at all, and these then
      // equal the totals without a second pass.
      if (!entry.missed) {
        keptByDay[dayKey] = (keptByDay[dayKey] ?? 0) + 1;
        keptByMonth[monthKey] = (keptByMonth[monthKey] ?? 0) + 1;
      }
    }

    // A day is missed only when nothing on it was kept — one attended entry is
    // enough to win the square back.
    final missedMasks = <int, int>{};
    for (final dayKey in byDay.keys) {
      if ((keptByDay[dayKey] ?? 0) != 0) continue;
      final month = (dayKey ~/ 100) % 100;
      final monthKey = (dayKey ~/ 10000) * 12 + (month - 1);
      missedMasks[monthKey] =
          (missedMasks[monthKey] ?? 0) | (1 << (dayKey % 100 - 1));
    }

    final months = <DateTime>[];
    for (
      var month = DateTime.utc(start.year, start.month, 1);
      !month.isAfter(DateTime.utc(end.year, end.month, 1));
      month = DateTime.utc(month.year, month.month + 1, 1)
    ) {
      months.add(month);
    }

    // Arithmetic on the day numbers rather than a `DateTime.utc` per day of
    // every month: only the two edge months are partial, and a run of set bits
    // is one shift.
    final startOrder = start.year * 12 + start.month;
    final endOrder = end.year * 12 + end.month;
    final windowMasks = <int, int>{};
    for (final month in months) {
      final order = month.year * 12 + month.month;
      if (order < startOrder || order > endOrder) {
        windowMasks[_monthKey(month)] = 0;
        continue;
      }
      final firstDay = order == startOrder ? start.day : 1;
      final lastDay = order == endOrder
          ? end.day
          : _daysInMonthOf(month.year, month.month);
      windowMasks[_monthKey(month)] = lastDay < firstDay
          ? 0
          : ((1 << (lastDay - firstDay + 1)) - 1) << (firstDay - 1);
    }

    final days = byDay.keys.toList(growable: false)..sort();

    return AgendaDayListIndex._(
      windowStart: start,
      windowEnd: end,
      months: List.unmodifiable(months),
      days: List.unmodifiable([
        for (final key in days)
          DateTime.utc(key ~/ 10000, (key ~/ 100) % 100, key % 100),
      ]),
      totalCount: entries.length,
      byDay: byDay,
      byMonth: byMonth,
      keptByDay: keptByDay,
      keptByMonth: keptByMonth,
      markedMasks: markedMasks,
      missedMasks: missedMasks,
      windowMasks: windowMasks,
    );
  }

  int countForMonth(DateTime month) => _byMonth[_monthKey(month)]?.length ?? 0;

  /// Entries on [month] that were **not** missed — the attendance count every
  /// number the sheet prints is built from.
  int keptCountForMonth(DateTime month) => _keptByMonth[_monthKey(month)] ?? 0;

  int markedMaskForMonth(DateTime month) => _markedMasks[_monthKey(month)] ?? 0;

  /// Bit `day - 1` set when that day carries entries and **every** one of them
  /// was missed.
  int missedMaskForMonth(DateTime month) => _missedMasks[_monthKey(month)] ?? 0;

  int windowMaskForMonth(DateTime month) => _windowMasks[_monthKey(month)] ?? 0;

  int countForDay(DateTime day) => _byDay[_dayKey(day)]?.length ?? 0;

  int keptCountForDay(DateTime day) => _keptByDay[_dayKey(day)] ?? 0;

  List<AgendaDayListEntry> entriesOn(DateTime day) =>
      _byDay[_dayKey(day)] ?? const <AgendaDayListEntry>[];

  List<AgendaDayListEntry> entriesInMonth(DateTime month) =>
      _byMonth[_monthKey(month)] ?? const <AgendaDayListEntry>[];
}

/// The per-day and per-month numbers a tile or a month bucket prints, folded
/// from marks in one pass — the one place the counting rules live, so a
/// bucket built from entries and a tally built from bare marks cannot
/// disagree about what "missed" or "marked" means.
class _MonthAccumulator {
  final DateTime month;
  final int daysInMonth;
  final Map<int, int> keptByDay = <int, int>{};
  final List<Color?> dayColors;
  int count = 0;
  int keptCount = 0;
  int markedMask = 0;
  int seenMask = 0;

  _MonthAccumulator(this.month)
    : daysInMonth = _daysInMonthOf(month.year, month.month),
      dayColors = List<Color?>.filled(
        _daysInMonthOf(month.year, month.month),
        null,
      );

  /// [color] is kept for the **first** mark of a day: marks arrive in the
  /// scan's same-day order, so the first is the day's top entry.
  void add(DateTime day, {required bool missed, required Color color}) {
    assert(_isDateOnlyUtc(day), 'mark days must be date-only UTC');
    assert(
      day.year == month.year && day.month == month.month,
      'mark days must fall inside the month',
    );
    final bit = 1 << (day.day - 1);
    count++;
    markedMask |= bit;
    if (seenMask & bit == 0) {
      seenMask |= bit;
      dayColors[day.day - 1] = color;
    }
    if (!missed) {
      keptByDay[day.day] = (keptByDay[day.day] ?? 0) + 1;
      keptCount++;
    }
  }

  /// Bit `day - 1` set when the day carries marks and every one of them was
  /// missed — one attended entry wins the square back.
  int get missedMask {
    var mask = 0;
    var remaining = markedMask;
    var day = 1;
    while (remaining != 0) {
      if (remaining & 1 != 0 && (keptByDay[day] ?? 0) == 0) {
        mask |= 1 << (day - 1);
      }
      remaining >>= 1;
      day++;
    }
    return mask;
  }
}

/// A month's counts and masks alone — what a year tile paints — folded from
/// [AgendaDayMark]s without building a single entry.
class AgendaMonthTally {
  final DateTime month;
  final int daysInMonth;
  final int count;

  /// Marks that were not missed.
  final int keptCount;

  final int markedMask;
  final int missedMask;

  /// The colour of each marked day's top mark, index `day - 1`; null on an
  /// unmarked day.
  final List<Color?> dayColors;

  const AgendaMonthTally._({
    required this.month,
    required this.daysInMonth,
    required this.count,
    required this.keptCount,
    required this.markedMask,
    required this.missedMask,
    required this.dayColors,
  });

  static AgendaMonthTally build(DateTime month, Iterable<AgendaDayMark> marks) {
    assert(_isDateOnlyUtc(month), 'month must be date-only UTC');
    assert(month.day == 1, 'month must be the first day of the month');
    final tally = _MonthAccumulator(month);
    for (final mark in marks) {
      tally.add(mark.day, missed: mark.missed, color: mark.color);
    }
    return AgendaMonthTally._of(tally);
  }

  /// The tally a resolved bucket already implies, so a month whose entries
  /// are cached never resolves its marks a second time.
  factory AgendaMonthTally.ofBucket(AgendaDayListMonth bucket) =>
      AgendaMonthTally._(
        month: bucket.month,
        daysInMonth: bucket.daysInMonth,
        count: bucket.count,
        keptCount: bucket.keptCount,
        markedMask: bucket.markedMask,
        missedMask: bucket.missedMask,
        dayColors: bucket.dayColors,
      );

  factory AgendaMonthTally._of(_MonthAccumulator tally) => AgendaMonthTally._(
    month: tally.month,
    daysInMonth: tally.daysInMonth,
    count: tally.count,
    keptCount: tally.keptCount,
    markedMask: tally.markedMask,
    missedMask: tally.missedMask,
    dayColors: List.unmodifiable(tally.dayColors),
  );
}

class AgendaDayListMonth {
  final DateTime month;

  final int daysInMonth;

  final List<DateTime> days;

  final int count;

  /// Entries in the month that were not missed.
  final int keptCount;

  final int markedMask;

  /// Bit `day - 1` set when that day carries entries and every one of them was
  /// missed.
  final int missedMask;

  /// The colour of each marked day's first entry, index `day - 1`.
  final List<Color?> dayColors;

  final Map<int, List<AgendaDayListEntry>> _byDay;
  final Map<int, int> _keptByDay;

  AgendaDayListMonth._({
    required this.month,
    required this.daysInMonth,
    required this.days,
    required this.count,
    required this.keptCount,
    required this.markedMask,
    required this.missedMask,
    required this.dayColors,
    required Map<int, List<AgendaDayListEntry>> byDay,
    required Map<int, int> keptByDay,
  }) : _byDay = byDay,
       _keptByDay = keptByDay;

  static AgendaDayListMonth build(
    DateTime month,
    List<AgendaDayListEntry> entries,
  ) {
    assert(_isDateOnlyUtc(month), 'month must be date-only UTC');
    assert(month.day == 1, 'month must be the first day of the month');

    final tally = _MonthAccumulator(month);
    final byDay = <int, List<AgendaDayListEntry>>{};
    for (final entry in entries) {
      tally.add(entry.day, missed: entry.missed, color: entry.color);
      (byDay[entry.day.day] ??= <AgendaDayListEntry>[]).add(entry);
    }

    final dayNumbers = byDay.keys.toList(growable: false)..sort();

    return AgendaDayListMonth._(
      month: month,
      daysInMonth: tally.daysInMonth,
      days: List.unmodifiable([
        for (final day in dayNumbers)
          DateTime.utc(month.year, month.month, day),
      ]),
      count: tally.count,
      keptCount: tally.keptCount,
      markedMask: tally.markedMask,
      missedMask: tally.missedMask,
      dayColors: List.unmodifiable(tally.dayColors),
      byDay: byDay,
      keptByDay: tally.keptByDay,
    );
  }

  List<AgendaDayListEntry> entriesOn(DateTime day) {
    if (day.year != month.year || day.month != month.month) {
      return const <AgendaDayListEntry>[];
    }
    return _byDay[day.day] ?? const <AgendaDayListEntry>[];
  }

  int countForDay(DateTime day) => entriesOn(day).length;

  int keptCountForDay(DateTime day) {
    if (day.year != month.year || day.month != month.month) return 0;
    return _keptByDay[day.day] ?? 0;
  }
}
