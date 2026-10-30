import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../constants/calendar_bounds.dart';
import '../l10n/app_localizations.dart';
import '../utils/date_span_label.dart';
import 'agenda_day_list.dart';
import 'calendar_appearance.dart';
import 'date_range.dart';

/// The rolling spans the overview's Period menu offers, each ending today.
enum OverviewRollingPreset { last12Months, last90Days, allTime }

/// The Period menu's rows, in order. [custom] opens the picker; every other
/// row is a whole period on its own ([OverviewPeriod.fromChoice]).
enum OverviewPeriodChoice {
  thisWeek,
  thisMonth,
  thisYear,
  last12Months,
  last90Days,
  allTime,
  custom,
}

/// The overview list's unit: the span of days it lists.
///
/// A week, a month, a year, a rolling span or a custom one; every kind
/// resolves to an inclusive [DateRange] against today, so a rolling span
/// follows the calendar day by day instead of going stale the way stored
/// dates would. Only this week, this month, this year and the rolling presets
/// are persisted ([encode]): a custom span or a week, month or year paged to
/// is a look at something, not a standing choice.
sealed class OverviewPeriod extends Equatable {
  const OverviewPeriod();

  /// The default, and what every unreadable stored value falls back to.
  factory OverviewPeriod.thisYear({required DateTime today}) =>
      OverviewYearPeriod(today.year);

  /// The week holding [today], starting on the calendar's own first weekday
  /// so the overview's week is the one the grid draws as a row.
  factory OverviewPeriod.thisWeek({
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) {
    final back = (today.weekday - weekStart.weekday) % 7;
    return OverviewWeekPeriod(
      DateTime.utc(today.year, today.month, today.day - back),
    );
  }

  /// The calendar month holding [today].
  factory OverviewPeriod.thisMonth({required DateTime today}) =>
      OverviewMonthPeriod(today.year, today.month);

  /// The inclusive span this period lists, clamped to [CalendarBounds] and
  /// never ending before it starts. [today] is date-only; [yearBounds] is
  /// what All time reaches back to (`EventAgenda.yearBoundsOf`).
  DateRange resolve({
    required DateTime today,
    required AgendaYearBounds yearBounds,
  }) {
    final day = DateTime.utc(today.year, today.month, today.day);
    final (DateTime start, DateTime end) = switch (this) {
      OverviewWeekPeriod(:final start, :final end) => (start, end),
      OverviewMonthPeriod(:final first, :final last) => (first, last),
      OverviewYearPeriod(:final year) => (
        DateTime.utc(year, 1, 1),
        DateTime.utc(year, 12, 31),
      ),
      OverviewRollingPeriod(:final preset) => switch (preset) {
        OverviewRollingPreset.last12Months => (
          day.subtract(const Duration(days: 364)),
          day,
        ),
        OverviewRollingPreset.last90Days => (
          day.subtract(const Duration(days: 89)),
          day,
        ),
        OverviewRollingPreset.allTime => (
          DateTime.utc(yearBounds.first, 1, 1),
          day,
        ),
      },
      OverviewCustomPeriod(:final start, :final end) => (start, end),
    };
    final first = _clamp(start);
    final last = _clamp(end);
    // A start past the end collapses onto the end rather than inverting the
    // span: a reader iterating start..end then lists one day, never none.
    return (start: last.isBefore(first) ? last : first, end: last);
  }

  /// The neighbouring period one step back (`direction < 0`) or forward, or
  /// null where the nav's chevron is disabled.
  ///
  /// A week, a month or a year steps to its calendar neighbour — a month by
  /// the calendar, never by its length, so the month before October is
  /// September 1–30 whatever October's length; anything else becomes a
  /// custom span of its own resolved length laid beside it, because a
  /// rolling span moved off today no longer ends today and must say which
  /// days it lists. All time has no neighbour, and a result wholly outside
  /// `[Jan 1 of yearBounds.first, Dec 31 of yearBounds.last]` or
  /// [CalendarBounds] would list nothing the year nav can reach.
  OverviewPeriod? stepped({
    required int direction,
    required DateTime today,
    required AgendaYearBounds yearBounds,
  }) {
    final OverviewPeriod next;
    switch (this) {
      case OverviewWeekPeriod(:final start):
        next = OverviewWeekPeriod(
          DateTime.utc(start.year, start.month, start.day + 7 * direction.sign),
        );
      case OverviewMonthPeriod(:final year, :final month):
        final first = DateTime.utc(year, month + direction.sign, 1);
        next = OverviewMonthPeriod(first.year, first.month);
      case OverviewYearPeriod(:final year):
        next = OverviewYearPeriod(year + direction.sign);
      case OverviewRollingPeriod(preset: OverviewRollingPreset.allTime):
        return null;
      case OverviewRollingPeriod() || OverviewCustomPeriod():
        final span = resolve(today: today, yearBounds: yearBounds);
        final length = Duration(
          days: span.end.difference(span.start).inDays + 1,
        );
        next = direction < 0
            ? OverviewCustomPeriod(
                span.start.subtract(length),
                span.start.subtract(const Duration(days: 1)),
              )
            : OverviewCustomPeriod(
                span.end.add(const Duration(days: 1)),
                span.end.add(length),
              );
    }
    final (DateTime start, DateTime end) = switch (next) {
      OverviewWeekPeriod(:final start, :final end) => (start, end),
      OverviewMonthPeriod(:final first, :final last) => (first, last),
      OverviewYearPeriod(:final year) => (
        DateTime.utc(year, 1, 1),
        DateTime.utc(year, 12, 31),
      ),
      OverviewCustomPeriod(:final start, :final end) => (start, end),
      OverviewRollingPeriod() => throw StateError('a step is never rolling'),
    };
    final first = DateTime.utc(yearBounds.first, 1, 1);
    final last = DateTime.utc(yearBounds.last, 12, 31);
    final low = first.isAfter(CalendarBounds.earliest)
        ? first
        : CalendarBounds.earliest;
    final high = last.isBefore(CalendarBounds.latest)
        ? last
        : CalendarBounds.latest;
    if (end.isBefore(low) || start.isAfter(high)) return null;
    return next;
  }

  static DateTime _clamp(DateTime day) {
    if (day.isBefore(CalendarBounds.earliest)) return CalendarBounds.earliest;
    if (day.isAfter(CalendarBounds.latest)) return CalendarBounds.latest;
    return day;
  }

  /// How the nav title's Period menu and a saved view's caption name the
  /// period: a week's span and a custom one in the Dates sheet's grammar, a
  /// month as Month mode's nav names it, the year's number, or the preset's
  /// name.
  String menuValue(AppLocalizations l10n) => switch (this) {
    // Clamped as [resolve] clamps, so a week over the calendar's first or
    // last day names only the days the list can show.
    OverviewWeekPeriod(:final start, :final end) => dateSpanLabel(
      l10n,
      _clamp(start),
      _clamp(end),
    ),
    OverviewMonthPeriod(:final year, :final month) => DateFormat.yMMMM(
      l10n.localeName,
    ).format(DateTime(year, month)),
    OverviewYearPeriod(:final year) => '$year',
    OverviewRollingPeriod(:final preset) => switch (preset) {
      OverviewRollingPreset.last12Months => l10n.overviewPeriodLast12Months,
      OverviewRollingPreset.last90Days => l10n.overviewPeriodLast90Days,
      OverviewRollingPreset.allTime => l10n.overviewPeriodAllTime,
    },
    OverviewCustomPeriod(:final start, :final end) => dateSpanLabel(
      l10n,
      start,
      end,
    ),
  };

  /// The Period menu's checked row. A week, month or year other than
  /// today's reads as its value with [OverviewPeriodChoice.custom] checked.
  OverviewPeriodChoice menuChoice({required DateTime today}) => switch (this) {
    OverviewWeekPeriod(:final start, :final end) =>
      _holds(start, end, today)
          ? OverviewPeriodChoice.thisWeek
          : OverviewPeriodChoice.custom,
    OverviewMonthPeriod(:final year, :final month) =>
      year == today.year && month == today.month
          ? OverviewPeriodChoice.thisMonth
          : OverviewPeriodChoice.custom,
    OverviewYearPeriod(:final year) =>
      year == today.year
          ? OverviewPeriodChoice.thisYear
          : OverviewPeriodChoice.custom,
    OverviewRollingPeriod(:final preset) => switch (preset) {
      OverviewRollingPreset.last12Months => OverviewPeriodChoice.last12Months,
      OverviewRollingPreset.last90Days => OverviewPeriodChoice.last90Days,
      OverviewRollingPreset.allTime => OverviewPeriodChoice.allTime,
    },
    OverviewCustomPeriod() => OverviewPeriodChoice.custom,
  };

  /// The period a preset row stands for. [OverviewPeriodChoice.custom] has
  /// none — its period is whatever the picker returns — and throws.
  /// [weekStart] is the calendar's, read by This week alone.
  static OverviewPeriod fromChoice(
    OverviewPeriodChoice choice, {
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) => switch (choice) {
    OverviewPeriodChoice.thisWeek => OverviewPeriod.thisWeek(
      today: today,
      weekStart: weekStart,
    ),
    OverviewPeriodChoice.thisMonth => OverviewPeriod.thisMonth(today: today),
    OverviewPeriodChoice.thisYear => OverviewPeriod.thisYear(today: today),
    OverviewPeriodChoice.last12Months => const OverviewRollingPeriod(
      OverviewRollingPreset.last12Months,
    ),
    OverviewPeriodChoice.last90Days => const OverviewRollingPeriod(
      OverviewRollingPreset.last90Days,
    ),
    OverviewPeriodChoice.allTime => const OverviewRollingPeriod(
      OverviewRollingPreset.allTime,
    ),
    OverviewPeriodChoice.custom => throw ArgumentError.value(
      choice,
      'choice',
      'a custom period comes from the picker',
    ),
  };

  static const String _thisWeek = 'thisWeek';
  static const String _thisMonth = 'thisMonth';
  static const String _thisYear = 'thisYear';
  static const String _presetPrefix = 'preset:';

  /// The stored form: `thisWeek`, `thisMonth`, `thisYear`, `preset:<name>`,
  /// or null for what is not persisted (a custom span, a week, month or year
  /// other than [today]'s) — the caller clears the key, so the next launch
  /// opens on this year.
  String? encode({required DateTime today}) => switch (this) {
    OverviewWeekPeriod(:final start, :final end) =>
      _holds(start, end, today) ? _thisWeek : null,
    OverviewMonthPeriod(:final year, :final month) =>
      year == today.year && month == today.month ? _thisMonth : null,
    OverviewYearPeriod(:final year) => year == today.year ? _thisYear : null,
    OverviewRollingPeriod(:final preset) => '$_presetPrefix${preset.name}',
    OverviewCustomPeriod() => null,
  };

  /// Reads [encode]'s output forward-compatibly: an absent, empty or unknown
  /// value — a preset a newer build added — is this year. This week starts
  /// on [weekStart] as the calendar's does now, not as it did when stored.
  static OverviewPeriod decode(
    String? value, {
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) {
    if (value == _thisWeek) {
      return OverviewPeriod.thisWeek(today: today, weekStart: weekStart);
    }
    if (value == _thisMonth) return OverviewPeriod.thisMonth(today: today);
    if (value != null && value.startsWith(_presetPrefix)) {
      final name = value.substring(_presetPrefix.length);
      for (final preset in OverviewRollingPreset.values) {
        if (preset.name == name) return OverviewRollingPeriod(preset);
      }
    }
    return OverviewPeriod.thisYear(today: today);
  }

  /// This period once the day has moved from [before] to [today] under a
  /// page left open: This week, This month and This year — the unit
  /// [before] was in — move on to the one holding [today], so a page left
  /// open across midnight never lists last week under the This week row. A
  /// week moves by whole weeks and so keeps its first weekday on purpose: a
  /// change of the week start setting is the page's to re-derive, not a day
  /// change's. A unit paged away from [before], a rolling span and a custom
  /// one stay what they are (review 11).
  OverviewPeriod followingToday({
    required DateTime before,
    required DateTime today,
  }) => switch (this) {
    OverviewWeekPeriod(:final start, :final end)
        when _holds(start, end, before) && !_holds(start, end, today) =>
      OverviewWeekPeriod(
        DateTime.utc(
          start.year,
          start.month,
          start.day + 7 * (_utcDay(today).difference(start).inDays / 7).floor(),
        ),
      ),
    OverviewMonthPeriod(:final year, :final month)
        when year == before.year &&
            month == before.month &&
            (year != today.year || month != today.month) =>
      OverviewMonthPeriod(today.year, today.month),
    OverviewYearPeriod(:final year)
        when year == before.year && year != today.year =>
      OverviewYearPeriod(today.year),
    _ => this,
  };

  /// Whether [today]'s date falls in `first .. last`, both date-only UTC.
  static bool _holds(DateTime first, DateTime last, DateTime today) {
    final day = _utcDay(today);
    return !day.isBefore(first) && !day.isAfter(last);
  }

  static DateTime _utcDay(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);
}

/// A calendar week of seven days from [start], the first weekday the
/// calendar's week start names: this week, or the week a step or a saved
/// view lands on.
final class OverviewWeekPeriod extends OverviewPeriod {
  /// Date-only UTC.
  final DateTime start;

  const OverviewWeekPeriod(this.start);

  /// The week's last day, date-only UTC; built from the date's parts so a
  /// week across a DST change still ends on its seventh day.
  DateTime get end => DateTime.utc(start.year, start.month, start.day + 6);

  @override
  List<Object?> get props => [start];
}

/// A calendar month, the 1st to its last day: this month, or the month a
/// step or a saved view lands on.
final class OverviewMonthPeriod extends OverviewPeriod {
  final int year;

  /// `DateTime.january..december`.
  final int month;

  const OverviewMonthPeriod(this.year, this.month);

  /// The month's first day, date-only UTC.
  DateTime get first => DateTime.utc(year, month, 1);

  /// The month's last day, date-only UTC: day 0 of the next month, so the
  /// month's length — a leap February included — comes from the calendar.
  DateTime get last => DateTime.utc(year, month + 1, 0);

  @override
  List<Object?> get props => [year, month];
}

/// A calendar year, January 1 to December 31: this year, or the year set by
/// year mode's paging.
final class OverviewYearPeriod extends OverviewPeriod {
  final int year;

  const OverviewYearPeriod(this.year);

  @override
  List<Object?> get props => [year];
}

/// A span ending today, recomputed on every [resolve].
final class OverviewRollingPeriod extends OverviewPeriod {
  final OverviewRollingPreset preset;

  const OverviewRollingPeriod(this.preset);

  @override
  List<Object?> get props => [preset];
}

/// A span picked in the Dates sheet; [start] and [end] are date-only UTC and
/// inclusive.
final class OverviewCustomPeriod extends OverviewPeriod {
  final DateTime start;
  final DateTime end;

  const OverviewCustomPeriod(this.start, this.end);

  @override
  List<Object?> get props => [start, end];
}
