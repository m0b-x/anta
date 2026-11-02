import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_report.dart';
import '../models/overview_period.dart';
import '../services/calendar_report_service.dart';
import '../utils/calendar_report_builder.dart';
import '../utils/report_labels.dart';
import 'calendar_guide_try_screen.dart';
import 'report_body.dart';
import 'report_group_stack.dart';

/// The screen stage's Report view (D74): the report page's band and body
/// ([ReportBand], [ReportBody]) over a report folded from the screen page's
/// demo, so its tiles, groups and missed days are the ones the page would
/// draw for these events (D59). The month steps and Today returns (D82);
/// the groups fold and open in place; nothing else answers a tap — the rows
/// are inert, the footer and the cap row disabled, no presence button (D57).
///
/// Owned by [GuideScreenDemo]; it keeps its month and its folds while the
/// stage shows another view (D83). It hears the shared demo through the
/// screen demo ([syncWorld]), never on its own.
class GuideReportView extends ChangeNotifier {
  GuideReportView(this.world, {required this.control});

  final GuideScreenWorld world;

  /// The stage's id for one of the view's controls.
  final String Function(String name) control;

  final ReportGroupFolds _folds = ReportGroupFolds();

  /// This month of the demo's today, which Today returns to, and the month
  /// shown; set on the first fold.
  OverviewPeriod? _home;
  OverviewPeriod? _period;

  CalendarReport? _report;
  AgendaYearBounds? _years;

  /// Whether the stage shows this view: a change to the demo while it does
  /// not is folded on [enter].
  bool _shown = false;
  bool _stale = true;

  /// The shared demo changed — her look, her categories, a pick. The demo
  /// keeps no revision and is small, so any change folds again.
  void syncWorld() {
    _stale = true;
    if (_shown) _fold();
  }

  /// The stage switched to this view.
  void enter() {
    _shown = true;
    if (_stale) _fold();
  }

  /// The stage switched away from this view.
  void leave() => _shown = false;

  /// One fold of the shown month over the demo's events, read through the
  /// demo's own marks, skips and texts: the facades hold nothing for a demo
  /// id, and read through them the report would show no missed day.
  void _fold() {
    final calendar = world.calendar;
    if (calendar == null) return;
    final today = calendar.today;
    final home = _home ??= OverviewPeriod.thisMonth(today: today);
    final period = _period ??= home;
    final events = calendar.events;
    final years = CalendarReportService.yearsOf(events, today: today);
    final (:span, :previousSpan) = CalendarReportService.spansOf(
      period,
      today: today,
      years: years,
    );
    _report = CalendarReportBuilder.fold(
      CalendarReportService.sampleInput(
        ReportRequest(
          span: span,
          previousSpan: previousSpan,
          events: events,
          today: today,
          weekStart: world.appearance.weekStart,
          isMissed: calendar.isMissed,
          marksFor: calendar.marksFor,
          skipsFor: calendar.skipsFor,
          descriptionsFor: calendar.overridesFor,
        ),
      ),
    );
    _years = years;
    _stale = false;
  }

  /// The band offers a step only where there is one, after the first fold.
  void _step(int direction) {
    final next = _period!.stepped(
      direction: direction,
      today: world.calendar!.today,
      yearBounds: _years!,
    );
    if (next == null) return;
    _period = next;
    _fold();
    notifyListeners();
  }

  void _goHome() {
    _period = _home;
    _fold();
    notifyListeners();
  }

  /// The band under the stage's bar and the body taking the rest of the
  /// stage, scrolling inside it.
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = ReportLabels(l10n);
    final today = world.calendar!.today;
    final years = _years ?? (first: today.year, last: today.year);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportBand(
          period: _period,
          home: _home,
          report: _report,
          today: today,
          years: years,
          labels: labels,
          // A plain title: the period menu is the page's (D82).
          onTitleTap: null,
          onStep: _step,
          onHome: _goHome,
          navIdentifier: (name) => control('report-$name'),
        ),
        Expanded(
          child: ReportBody(
            report: _report,
            period: _period,
            today: today,
            years: years,
            weekStart: world.appearance.weekStart,
            labels: labels,
            folds: _folds,
            bottomClearance: 0,
            use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
          ),
        ),
      ],
    );
  }
}
