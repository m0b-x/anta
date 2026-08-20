import 'dart:convert';

import 'package:equatable/equatable.dart';

/// What a month the user turned off actually suppresses.
///
/// Exposed as a choice rather than assumed because the two readings are both
/// legitimate and lead to opposite calendars: someone who keeps the great
/// fasts but not the weekly one in summer wants [weeklyOnly], while someone
/// who simply does not fast in August wants [allFasts].
enum FastingMonthScope {
  /// The month set gates only the year-round weekly rule (default). A great
  /// fast still shows in a month the user does not keep the weekly fast in.
  weeklyOnly,

  /// The month set gates every fasting mark, multi-day fasts and the other
  /// traditions included. A disabled month renders as if fasting were off.
  allFasts;

  /// Forward-compatible parsing: unknown/null values fall back to
  /// [weeklyOnly].
  static FastingMonthScope fromName(String? name) {
    for (final scope in values) {
      if (scope.name == name) return scope;
    }
    return weeklyOnly;
  }
}

/// The personal fasting practice: which weekdays are kept, which months, what
/// a disabled month suppresses, and the exact dates that override both.
///
/// One schedule covers every enabled tradition. It may **subtract** from a
/// tradition's own weekly rule but never **invent** days that tradition does
/// not have — dropping Friday silences the Catholic year-round abstinence,
/// while adding Monday is an Orthodox-side choice that must not fabricate a
/// Catholic Monday abstinence.
///
/// Every field is compute-affecting, which is why `FastingCalendar.configure`
/// compares whole schedules: [Equatable] resolves the sets through
/// `DeepCollectionEquality`, so an equal-but-differently-ordered set is a
/// no-op and leaves the warm per-year maps alone.
class FastingSchedule extends Equatable {
  /// The traditional Wednesday + Friday.
  static const Set<int> defaultWeekdays = {DateTime.wednesday, DateTime.friday};

  static const Set<int> allMonths = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};

  /// Cap per exception set. Hand-picked dates are the only unbounded field
  /// here, and `_applyExceptions` walks them on every year build — a runaway
  /// list would turn an O(365) build into an O(n) one and bloat the settings
  /// row for no practice anyone actually keeps.
  static const int maxExceptionDates = 200;

  /// `DateTime.weekday` values (1=Mon..7=Sun) the weekly fast falls on. Empty
  /// is a deliberate "no weekly fast", not a missing value.
  final Set<int> weekdays;

  /// Months (1..12) the practice is kept in. Empty is legitimate and blanks
  /// whatever [monthScope] covers.
  final Set<int> months;

  final FastingMonthScope monthScope;

  /// Dates never marked, whatever the calendar works out. Date-only UTC.
  final Set<DateTime> skipDates;

  /// Dates always marked, even where no tradition fasts. Date-only UTC, and
  /// always disjoint from [skipDates] — force wins.
  final Set<DateTime> forceDates;

  const FastingSchedule({
    this.weekdays = defaultWeekdays,
    this.months = allMonths,
    this.monthScope = FastingMonthScope.weeklyOnly,
    this.skipDates = const {},
    this.forceDates = const {},
  });

  bool get keepsEveryMonth => months.length == allMonths.length;

  int get exceptionCount => skipDates.length + forceDates.length;

  /// Returns a normalized copy: weekdays clamped to 1..7, months to 1..12,
  /// dates reduced to UTC midnight, [skipDates] stripped of anything forced,
  /// and both date sets capped at [maxExceptionDates].
  ///
  /// Normalization lives here rather than in the constructor so the defaults
  /// stay `const` — and so every mutation path (the sheet, [decode]) shares
  /// one set of rules instead of re-deriving them.
  FastingSchedule copyWith({
    Set<int>? weekdays,
    Set<int>? months,
    FastingMonthScope? monthScope,
    Set<DateTime>? skipDates,
    Set<DateTime>? forceDates,
  }) {
    return _normalized(
      weekdays: weekdays ?? this.weekdays,
      months: months ?? this.months,
      monthScope: monthScope ?? this.monthScope,
      skipDates: skipDates ?? this.skipDates,
      forceDates: forceDates ?? this.forceDates,
    );
  }

  static FastingSchedule _normalized({
    required Set<int> weekdays,
    required Set<int> months,
    required FastingMonthScope monthScope,
    required Set<DateTime> skipDates,
    required Set<DateTime> forceDates,
  }) {
    final force = _capped(_dateOnly(forceDates));
    final skip = _capped(_dateOnly(skipDates)..removeWhere(force.contains));
    return FastingSchedule(
      weekdays: {
        for (final day in weekdays)
          if (day >= DateTime.monday && day <= DateTime.sunday) day,
      },
      months: {
        for (final month in months)
          if (month >= 1 && month <= 12) month,
      },
      monthScope: monthScope,
      skipDates: skip,
      forceDates: force,
    );
  }

  static Set<DateTime> _dateOnly(Set<DateTime> dates) => {
    for (final date in dates) DateTime.utc(date.year, date.month, date.day),
  };

  /// Keeps the earliest [maxExceptionDates] entries. Oldest-first because a
  /// practice is edited forward: the dates someone already lived through are
  /// the ones they entered deliberately.
  static Set<DateTime> _capped(Set<DateTime> dates) {
    if (dates.length <= maxExceptionDates) return dates;
    final sorted = dates.toList()..sort();
    return sorted.take(maxExceptionDates).toSet();
  }

  /// JSON object. The three structural fields are always written (their
  /// absence means "default" on read, which is not the same as an empty set);
  /// empty date lists are omitted to keep the stored row small.
  String encode() => jsonEncode({
    'weekdays': (weekdays.toList()..sort()),
    'months': (months.toList()..sort()),
    'monthScope': monthScope.name,
    if (skipDates.isNotEmpty) 'skip': _encodeDates(skipDates),
    if (forceDates.isNotEmpty) 'force': _encodeDates(forceDates),
  });

  static List<String> _encodeDates(Set<DateTime> dates) {
    final sorted = dates.toList()..sort();
    return [
      for (final date in sorted)
        '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
    ];
  }

  /// Decodes [encode]'s output, falling back to the retired weekday CSV.
  ///
  /// Every field degrades independently, and nothing here throws: a corrupt
  /// settings row must never keep the calendar from opening.
  ///
  /// [legacyWeekdayCsv] carries the retired `calendar_fasting_weekdays` value
  /// **including the empty string**, which is why it is nullable: an absent
  /// row (null) means the weekdays were never chosen and the traditional
  /// Wednesday+Friday apply, while `''` means the user cleared them all and
  /// keeps no weekly fast. Collapsing the two loses a deliberate choice.
  static FastingSchedule decode(String? raw, {String? legacyWeekdayCsv}) {
    final trimmed = raw?.trim();
    if (trimmed != null && trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return _normalized(
            weekdays: _parseInts(decoded['weekdays']) ?? defaultWeekdays,
            months: _parseInts(decoded['months']) ?? allMonths,
            monthScope: FastingMonthScope.fromName(
              decoded['monthScope'] is String
                  ? decoded['monthScope'] as String
                  : null,
            ),
            skipDates: _parseDates(decoded['skip']),
            forceDates: _parseDates(decoded['force']),
          );
        }
      } on FormatException {
        // Fall through to the legacy/default path below.
      }
    }
    if (legacyWeekdayCsv != null) {
      return FastingSchedule(weekdays: _parseWeekdayCsv(legacyWeekdayCsv));
    }
    return const FastingSchedule();
  }

  /// Null when the value is not a list at all (the field is absent or
  /// corrupt, so the caller's default applies); an empty set when the list is
  /// present but empty, which is a deliberate "none".
  static Set<int>? _parseInts(Object? value) {
    if (value is! List) return null;
    final ints = <int>{};
    for (final entry in value) {
      if (entry is int) {
        ints.add(entry);
        continue;
      }
      final parsed = int.tryParse(entry.toString());
      if (parsed != null) ints.add(parsed);
    }
    return ints;
  }

  /// Matches exactly what [_encodeDates] writes. Deliberately stricter than
  /// `DateTime.tryParse`, which rolls `2026-13-99` over into a real (wrong)
  /// date — a corrupt row must be dropped, not silently relocated.
  static final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static Set<DateTime> _parseDates(Object? value) {
    if (value is! List) return const {};
    final dates = <DateTime>{};
    for (final entry in value) {
      if (entry is! String) continue;
      final match = _datePattern.firstMatch(entry.trim());
      if (match == null) continue;
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final date = DateTime.utc(int.parse(match.group(1)!), month, day);
      if (date.month != month || date.day != day) continue;
      dates.add(date);
    }
    return dates;
  }

  static Set<int> _parseWeekdayCsv(String raw) {
    final days = <int>{};
    for (final part in raw.split(',')) {
      final day = int.tryParse(part.trim());
      if (day != null && day >= DateTime.monday && day <= DateTime.sunday) {
        days.add(day);
      }
    }
    return days;
  }

  @override
  List<Object?> get props => [
    weekdays,
    months,
    monthScope,
    skipDates,
    forceDates,
  ];
}
