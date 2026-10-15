import 'package:equatable/equatable.dart';

import '../constants/calendar_bounds.dart';
import '../l10n/app_localizations.dart';
import '../utils/date_span_label.dart';
import 'agenda_day_list.dart';
import 'date_range.dart';

/// The rolling spans the overview's Period menu offers, each ending today.
enum OverviewRollingPreset { last12Months, last90Days, allTime }

/// The Period menu's rows, in order. [custom] opens the picker; every other
/// row is a whole period on its own ([OverviewPeriod.fromChoice]).
enum OverviewPeriodChoice {
  thisYear,
  last12Months,
  last90Days,
  allTime,
  custom,
}

/// The overview list's unit: the span of days it lists.
///
/// A year, a rolling span or a custom one; every kind resolves to an
/// inclusive [DateRange] against today, so a rolling span follows the
/// calendar day by day instead of going stale the way stored dates would.
/// Only this year and the rolling presets are persisted ([encode]): a custom
/// span or a past year is a look at something, not a standing choice.
sealed class OverviewPeriod extends Equatable {
  const OverviewPeriod();

  /// The default, and what every unreadable stored value falls back to.
  factory OverviewPeriod.thisYear({required DateTime today}) =>
      OverviewYearPeriod(today.year);

  /// The inclusive span this period lists, clamped to [CalendarBounds] and
  /// never ending before it starts. [today] is date-only; [yearBounds] is
  /// what All time reaches back to (`EventAgenda.yearBoundsOf`).
  DateRange resolve({
    required DateTime today,
    required AgendaYearBounds yearBounds,
  }) {
    final day = DateTime.utc(today.year, today.month, today.day);
    final (DateTime start, DateTime end) = switch (this) {
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
  /// A year steps to the next year; anything else becomes a custom span of
  /// its own resolved length laid beside it, because a rolling span moved
  /// off today no longer ends today and must say which days it lists. All
  /// time has no neighbour, and a result wholly outside
  /// `[Jan 1 of yearBounds.first, Dec 31 of yearBounds.last]` or
  /// [CalendarBounds] would list nothing the year nav can reach.
  OverviewPeriod? stepped({
    required int direction,
    required DateTime today,
    required AgendaYearBounds yearBounds,
  }) {
    final OverviewPeriod next;
    switch (this) {
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
  /// period: the year's number, the preset's name, or the custom span in the
  /// Dates sheet's grammar.
  String menuValue(AppLocalizations l10n) => switch (this) {
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

  /// The Period menu's checked row. A year other than today's reads its
  /// number as the value with [OverviewPeriodChoice.custom] checked.
  OverviewPeriodChoice menuChoice({required DateTime today}) => switch (this) {
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
  static OverviewPeriod fromChoice(
    OverviewPeriodChoice choice, {
    required DateTime today,
  }) => switch (choice) {
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

  static const String _thisYear = 'thisYear';
  static const String _presetPrefix = 'preset:';

  /// The stored form: `thisYear`, `preset:<name>`, or null for what is not
  /// persisted (a custom span, a year other than [today]'s) — the caller
  /// clears the key, so the next launch opens on this year.
  String? encode({required DateTime today}) => switch (this) {
    OverviewYearPeriod(:final year) => year == today.year ? _thisYear : null,
    OverviewRollingPeriod(:final preset) => '$_presetPrefix${preset.name}',
    OverviewCustomPeriod() => null,
  };

  /// Reads [encode]'s output forward-compatibly: an absent, empty or unknown
  /// value — a preset a newer build added — is this year.
  static OverviewPeriod decode(String? value, {required DateTime today}) {
    if (value != null && value.startsWith(_presetPrefix)) {
      final name = value.substring(_presetPrefix.length);
      for (final preset in OverviewRollingPreset.values) {
        if (preset.name == name) return OverviewRollingPeriod(preset);
      }
    }
    return OverviewPeriod.thisYear(today: today);
  }

  /// This period once the day has moved from [before] to [today] under a
  /// page left open: This year — the year [before] was in — moves on to
  /// [today]'s, as a reopened page would read it; a past year, a rolling
  /// span and a custom one stay what they are (review 11).
  OverviewPeriod followingToday({
    required DateTime before,
    required DateTime today,
  }) => switch (this) {
    OverviewYearPeriod(:final year)
        when year == before.year && year != today.year =>
      OverviewYearPeriod(today.year),
    _ => this,
  };
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
