import 'package:equatable/equatable.dart';

import '../../models/agenda_day_list.dart';
import '../../models/calendar_appearance.dart';
import '../../models/calendar_report.dart';
import '../../models/overview_period.dart';
import '../../utils/markdown_color_syntax.dart';

sealed class ReportState extends Equatable {
  const ReportState();

  @override
  List<Object?> get props => [];
}

/// Before the settings and the calendar's first loaded state have both
/// arrived: the page draws its bar, its band and an empty Totals frame,
/// never a spinner. [period] is set once the settings have loaded, so the
/// band can title it while the calendar is still loading.
final class ReportLoading extends ReportState {
  final OverviewPeriod? period;

  const ReportLoading({this.period});

  @override
  List<Object?> get props => [period];
}

/// What every state past loading knows besides its report: the period shown
/// and the one picked, the allowlist, the calendar's appearance, the
/// palette and the haptic switch, the day of the fold and the years a step
/// may reach.
sealed class ReportShown extends ReportState {
  /// The period the report is on — the home, or a step away from it.
  final OverviewPeriod period;

  /// The period as picked, which the band's Today slot returns to.
  final OverviewPeriod home;

  /// The allowlist; empty is every category.
  final Set<String> categoryIds;

  /// The calendar's appearance: its week start decides This week and the
  /// trend's columns, and the range picker draws its grid in it.
  final CalendarAppearance appearance;

  /// The markdown palette a row's detail sheet renders the description in.
  final MarkdownColorPalette palette;

  /// Whether a presence mark clicks.
  final bool hapticFeedback;

  /// The day the report was asked for, date-only UTC.
  final DateTime today;

  /// The years the calendar's events reach (`EventAgenda.yearBoundsOf`):
  /// where a step stops and what the range picker offers.
  final AgendaYearBounds years;

  const ReportShown({
    required this.period,
    required this.home,
    required this.categoryIds,
    required this.appearance,
    required this.palette,
    required this.hapticFeedback,
    required this.today,
    required this.years,
  });

  /// The calendar's first weekday.
  CalendarWeekStart get weekStart => appearance.weekStart;

  /// The report this state draws: the fresh one, or while a refold runs the
  /// previous one, or null before the first fold has landed.
  CalendarReport? get shown;

  @override
  List<Object?> get props => [
    period,
    home,
    categoryIds,
    appearance,
    palette,
    hapticFeedback,
    today,
    years,
  ];
}

/// A fold is running. [previous] is the last report, drawn dimmed until
/// the new one lands (§4.2's refold); null on the first fold.
///
/// [period] and [categoryIds] are already the new pick, which the band's
/// title shows; everything worded from [previous] — the caption, Show as
/// list — reads [previousPeriod] and [previousCategoryIds], the ones it was
/// folded for (D36.9), so the page never pairs a new name with old numbers.
final class ReportFolding extends ReportShown {
  final CalendarReport? previous;

  /// The period [previous] was folded for; null with it.
  final OverviewPeriod? previousPeriod;

  /// The allowlist [previous] was folded over.
  final Set<String> previousCategoryIds;

  const ReportFolding({
    this.previous,
    this.previousPeriod,
    this.previousCategoryIds = const {},
    required super.period,
    required super.home,
    required super.categoryIds,
    required super.appearance,
    required super.palette,
    required super.hapticFeedback,
    required super.today,
    required super.years,
  });

  @override
  CalendarReport? get shown => previous;

  @override
  List<Object?> get props => [
    ...super.props,
    previous,
    previousPeriod,
    previousCategoryIds,
  ];
}

/// The report of [period] over [categoryIds], folded.
final class ReportReady extends ReportShown {
  final CalendarReport report;

  const ReportReady({
    required this.report,
    required super.period,
    required super.home,
    required super.categoryIds,
    required super.appearance,
    required super.palette,
    required super.hapticFeedback,
    required super.today,
    required super.years,
  });

  @override
  CalendarReport get shown => report;

  @override
  List<Object?> get props => [...super.props, report];
}
