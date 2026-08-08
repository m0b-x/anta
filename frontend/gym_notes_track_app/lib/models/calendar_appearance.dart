import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// How the "today" cell is highlighted in the calendar grid.
enum CalendarTodayStyle {
  /// Soft accent-tinted circle behind the day number (default).
  tonal,

  /// Thin accent ring around the day number.
  ring,

  /// Solid accent circle, like the selected day.
  filled;

  /// Forward-compatible parsing: unknown/null values fall back to [tonal].
  static CalendarTodayStyle fromName(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return tonal;
  }
}

/// How per-day event markers are drawn in the calendar grid.
enum CalendarMarkerStyle {
  /// Stacked full-width colored bars (default).
  bars,

  /// A compact centered row of colored dots.
  dots;

  /// Forward-compatible parsing: unknown/null values fall back to [bars].
  static CalendarMarkerStyle fromName(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return bars;
  }
}

/// First day of the calendar week.
enum CalendarWeekStart {
  monday(DateTime.monday),
  saturday(DateTime.saturday),
  sunday(DateTime.sunday);

  /// `DateTime.monday..sunday` constant for the anchor weekday, used to pick
  /// a localized label via `intl` without an ARB weekday matrix.
  final int weekday;

  const CalendarWeekStart(this.weekday);

  /// Forward-compatible parsing: unknown/null values fall back to [monday].
  static CalendarWeekStart fromName(String? name) {
    for (final start in values) {
      if (start.name == name) return start;
    }
    return monday;
  }
}

/// Bundle of every user-configurable calendar look & feel option.
///
/// Loaded once by the calendar page (and the calendar settings preview)
/// through `SettingsService.getCalendarAppearance()`; persisted as individual
/// settings keys so each option round-trips through backup independently.
class CalendarAppearance extends Equatable {
  final CalendarTodayStyle todayStyle;
  final CalendarMarkerStyle markerStyle;
  final CalendarWeekStart weekStart;

  /// Explicit ARGB accent for today/selected highlights, or `null` to follow
  /// the theme's primary color.
  final int? accentColorValue;

  /// Tint Saturday/Sunday day numbers. Off by default — the red numbers
  /// read as "something is wrong with these days" to users who don't want
  /// the emphasis; opting in is one switch away.
  final bool highlightWeekends;

  /// Show ISO week numbers along the left edge.
  final bool showWeekNumbers;

  /// Maximum bar/dot markers per day cell before the "+N" overflow chip.
  final int maxDayBars;

  const CalendarAppearance({
    this.todayStyle = CalendarTodayStyle.tonal,
    this.markerStyle = CalendarMarkerStyle.bars,
    this.weekStart = CalendarWeekStart.monday,
    this.accentColorValue,
    this.highlightWeekends = false,
    this.showWeekNumbers = false,
    this.maxDayBars = 3,
  });

  /// The effective highlight accent: the user's custom color when set,
  /// otherwise [themePrimary].
  Color accentOr(Color themePrimary) {
    final value = accentColorValue;
    return value == null ? themePrimary : Color(value);
  }

  CalendarAppearance copyWith({
    CalendarTodayStyle? todayStyle,
    CalendarMarkerStyle? markerStyle,
    CalendarWeekStart? weekStart,
    int? accentColorValue,
    bool clearAccentColor = false,
    bool? highlightWeekends,
    bool? showWeekNumbers,
    int? maxDayBars,
  }) {
    return CalendarAppearance(
      todayStyle: todayStyle ?? this.todayStyle,
      markerStyle: markerStyle ?? this.markerStyle,
      weekStart: weekStart ?? this.weekStart,
      accentColorValue: clearAccentColor
          ? null
          : (accentColorValue ?? this.accentColorValue),
      highlightWeekends: highlightWeekends ?? this.highlightWeekends,
      showWeekNumbers: showWeekNumbers ?? this.showWeekNumbers,
      maxDayBars: maxDayBars ?? this.maxDayBars,
    );
  }

  @override
  List<Object?> get props => [
    todayStyle,
    markerStyle,
    weekStart,
    accentColorValue,
    highlightWeekends,
    showWeekNumbers,
    maxDayBars,
  ];
}
