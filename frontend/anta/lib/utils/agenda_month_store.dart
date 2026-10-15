import '../constants/calendar_colors.dart';
import '../models/agenda_day_list.dart';
import '../models/day_bar.dart';
import 'agenda_day_list_index.dart';
import 'event_agenda.dart';

/// Calendar months resolved through an [AgendaDayListResolver] — and, for the
/// year tiles, through the lighter [AgendaDayMarkResolver] — and kept for the
/// life of the surface that owns them.
///
/// Resolution happens on navigation, never while a frame is built: [ensure]
/// groups the months it has not seen into contiguous runs of at most twelve
/// months, issues one resolver call per run, and stores a bucket for every
/// requested month — an empty one included — so a month is never resolved
/// twice. A month's day bars are folded the moment it lands, because a
/// mid-swipe frame draws two months at once and the marker builder has to
/// answer for both without folding per cell.
class AgendaMonthStore {
  final AgendaDayListResolver _resolve;

  /// The lighter resolver behind year tiles: marks only, no rows. Optional —
  /// without it a tally is derived from the month's entries, resolved on
  /// demand, which is exactly as correct and only costs the rows.
  final AgendaDayMarkResolver? _resolveMarks;

  final int maxBars;

  final Map<int, AgendaDayListMonth> _months = {};
  final Map<int, Map<int, List<DayBar>>> _bars = {};
  final Map<int, AgendaMonthTally> _tallies = {};

  AgendaMonthStore({
    required AgendaDayListResolver resolve,
    AgendaDayMarkResolver? resolveMarks,
    required this.maxBars,
  }) : _resolve = resolve,
       _resolveMarks = resolveMarks;

  /// `year * 12 + month - 1`, for any day of the month.
  static int keyOf(DateTime day) => day.year * 12 + day.month - 1;

  static DateTime monthOfKey(int key) =>
      DateTime.utc(key ~/ 12, key % 12 + 1, 1);

  static DateTime monthOf(DateTime day) =>
      DateTime.utc(day.year, day.month, 1);

  static int monthOrder(DateTime month) => month.year * 12 + month.month;

  static List<DateTime> monthsOfYear(int year) => [
    for (var month = 1; month <= 12; month++) DateTime.utc(year, month, 1),
  ];

  bool isResolved(DateTime month) => _months.containsKey(keyOf(month));

  /// The bucket for [month] if it has been resolved, else null. Cache-only,
  /// so it is safe to call from a builder or a predicate.
  AgendaDayListMonth? cached(DateTime month) => _months[keyOf(month)];

  AgendaDayListMonth monthFor(DateTime month) {
    ensure([month]);
    return _months[keyOf(month)]!;
  }

  /// Resolves every month in [months] that is not cached yet, one resolver
  /// call per contiguous run of at most twelve months.
  void ensure(Iterable<DateTime> months) {
    _forEachMissingRun(months, _months, _resolveRun);
  }

  /// The tally tier of [ensure]: resolves marks for every month in [months]
  /// whose tally is not known yet — one marks call per contiguous run, and no
  /// call at all for a month whose entries are already cached.
  void ensureTallies(Iterable<DateTime> months) {
    for (final month in months) {
      final key = keyOf(month);
      if (_tallies.containsKey(key)) continue;
      final bucket = _months[key];
      if (bucket != null) _tallies[key] = AgendaMonthTally.ofBucket(bucket);
    }
    if (_resolveMarks == null) {
      ensure(months);
      for (final month in months) {
        final key = keyOf(month);
        _tallies[key] ??= AgendaMonthTally.ofBucket(_months[key]!);
      }
      return;
    }
    _forEachMissingRun(months, _tallies, _resolveMarkRun);
  }

  AgendaMonthTally tallyFor(DateTime month) {
    ensureTallies([month]);
    return _tallies[keyOf(month)]!;
  }

  /// Cache-only twin of [tallyFor].
  AgendaMonthTally? cachedTally(DateTime month) => _tallies[keyOf(month)];

  /// Drops [month]'s bucket, day bars and tally, so the next [ensure] or
  /// [ensureTallies] resolves it again. For a write known to touch that month
  /// alone — a presence mark — which then costs one month's scan where a new
  /// store would resolve the whole period anew; every other month is kept.
  void forget(DateTime month) {
    final key = keyOf(month);
    _months.remove(key);
    _bars.remove(key);
    _tallies.remove(key);
  }

  void _forEachMissingRun(
    Iterable<DateTime> months,
    Map<int, Object> cache,
    void Function(List<int> keys) resolveRun,
  ) {
    final keys = <int>{};
    for (final month in months) {
      final key = keyOf(month);
      if (!cache.containsKey(key)) keys.add(key);
    }
    if (keys.isEmpty) return;
    final missing = keys.toList()..sort();
    var runStart = 0;
    for (var i = 1; i <= missing.length; i++) {
      // A run closes at a gap, and also at twelve months: one resolver call
      // must stay inside `EventAgenda.maxRangeDays`, which a multi-year
      // period would otherwise exceed in release builds, where `_spanOf`'s
      // asserts are gone and the scan silently clamps.
      if (i < missing.length &&
          missing[i] == missing[i - 1] + 1 &&
          i - runStart < 12) {
        continue;
      }
      resolveRun(missing.sublist(runStart, i));
      runStart = i;
    }
  }

  static (DateTime first, DateTime end) _spanOf(List<int> keys) {
    final first = monthOfKey(keys.first);
    final last = monthOfKey(keys.last);
    final end = DateTime.utc(last.year, last.month + 1, 0);
    assert(keys.length <= 12, 'a resolve run may span at most twelve months');
    assert(
      end.difference(first).inDays + 1 <= EventAgenda.maxRangeDays,
      'a resolve run may span at most EventAgenda.maxRangeDays days',
    );
    return (first, end);
  }

  void _resolveRun(List<int> keys) {
    final (first, end) = _spanOf(keys);
    final entries = _resolve(first, end);
    final buckets = <int, List<AgendaDayListEntry>>{};
    for (final entry in entries) {
      (buckets[keyOf(entry.day)] ??= <AgendaDayListEntry>[]).add(entry);
    }
    assert(
      buckets.keys.every(keys.contains),
      'resolve returned entries outside the requested months',
    );
    for (final key in keys) {
      final bucket = AgendaDayListMonth.build(
        monthOfKey(key),
        buckets[key] ?? const <AgendaDayListEntry>[],
      );
      _months[key] = bucket;
      _bars[key] = buildBars(bucket, maxBars: maxBars);
      _tallies[key] = AgendaMonthTally.ofBucket(bucket);
    }
  }

  void _resolveMarkRun(List<int> keys) {
    final (first, end) = _spanOf(keys);
    final marks = _resolveMarks!(first, end);
    final buckets = <int, List<AgendaDayMark>>{};
    for (final mark in marks) {
      (buckets[keyOf(mark.day)] ??= <AgendaDayMark>[]).add(mark);
    }
    assert(
      buckets.keys.every(keys.contains),
      'resolveMarks returned marks outside the requested months',
    );
    for (final key in keys) {
      _tallies[key] = AgendaMonthTally.build(
        monthOfKey(key),
        buckets[key] ?? const <AgendaDayMark>[],
      );
    }
  }

  /// The day bars of a resolved month, keyed by day of month; null while the
  /// month is unresolved. Cache-only.
  Map<int, List<DayBar>>? barsFor(DateTime month) => _bars[keyOf(month)];

  /// Whether [day]'s own month — resolved or not — has anything on that day.
  /// An unresolved month answers false, which is what a month never navigated
  /// to is. Tests the mask bit rather than allocating per call.
  bool hasEntry(DateTime day) {
    final mask = _months[keyOf(day)]?.markedMask ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  /// A bucket's day bars, keyed by day of month — what the store folds for
  /// every month it resolves, public for a surface that folds a bucket of its
  /// own (the overview's month narrowed to a search). A missed occurrence's
  /// bar carries the same fade the grid gives it, so a mini month and the
  /// calendar page say the same thing about the same day.
  static Map<int, List<DayBar>> buildBars(
    AgendaDayListMonth bucket, {
    required int maxBars,
  }) {
    final barKeys = [for (var i = 0; i < maxBars; i++) 'agendaDayList:$i'];
    final bars = <int, List<DayBar>>{};
    for (final day in bucket.days) {
      final entries = bucket.entriesOn(day);
      final count = entries.length < maxBars ? entries.length : maxBars;
      bars[day.day] = [
        for (var i = 0; i < count; i++)
          DayBar(
            key: barKeys[i],
            color: entries[i].missed
                ? entries[i].color.withValues(
                    alpha: CalendarColors.missedEventAlpha,
                  )
                : entries[i].color,
            priority: i,
            semanticLabel: entries[i].title,
          ),
      ];
    }
    return bars;
  }
}
