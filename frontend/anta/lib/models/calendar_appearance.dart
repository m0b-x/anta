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

/// How an occurrence the user marked as missed is drawn (**v26**).
///
/// Applies to the grid markers, the agenda and the timeline. The day summary
/// panel deliberately ignores this and always shows missed rows faded: it is
/// the surface the toggle lives on, and a row that vanished the moment it was
/// marked could never be un-marked.
enum CalendarMissedDisplay {
  /// Still drawn, dimmed to [CalendarColors.missedEventAlpha] (default). A
  /// mark the user just made should visibly do something, and hiding by
  /// default makes the first mark read as a delete.
  faded,

  /// Not drawn at all. A render-time filter only — the occurrence still
  /// occurs, still counts and still exports.
  hidden;

  /// Forward-compatible parsing: unknown/null values fall back to [faded].
  static CalendarMissedDisplay fromName(String? name) {
    for (final display in values) {
      if (display.name == name) return display;
    }
    return faded;
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

  /// Whether day-panel / agenda event rows mention the repeat pattern
  /// ("Daily", "Every 2 weeks", …) in their subtitle. On by default; turning
  /// it off declutters rows for people whose events are mostly timed
  /// routines, where the pattern reads as redundant next to the time.
  final bool showRecurrenceLabels;

  /// How occurrences marked as missed on a presence-tracking event are drawn.
  final CalendarMissedDisplay missedDisplay;

  const CalendarAppearance({
    this.todayStyle = CalendarTodayStyle.tonal,
    this.markerStyle = CalendarMarkerStyle.bars,
    this.weekStart = CalendarWeekStart.monday,
    this.accentColorValue,
    this.highlightWeekends = false,
    this.showWeekNumbers = false,
    this.maxDayBars = 3,
    this.showRecurrenceLabels = true,
    this.missedDisplay = CalendarMissedDisplay.faded,
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
    bool? showRecurrenceLabels,
    CalendarMissedDisplay? missedDisplay,
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
      showRecurrenceLabels: showRecurrenceLabels ?? this.showRecurrenceLabels,
      missedDisplay: missedDisplay ?? this.missedDisplay,
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
    showRecurrenceLabels,
    missedDisplay,
  ];
}
