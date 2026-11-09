import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';

/// A guide line, written in whatever language the page is in when it is
/// drawn: a coach outlives a change of language.
typedef GuideLine = String Function(AppLocalizations l10n);

/// One step of a guide's coach: the instruction that names the next tap,
/// and the [action] a demo reports when it sees that tap done.
@immutable
class GuideCoachStep {
  const GuideCoachStep(this.action, this.line);

  final String action;
  final GuideLine line;
}

/// The coach line's machine (D46, D49): which instruction a "Try it" card
/// or the practice band shows next, or the report of an action the stage
/// could not show.
///
/// A done set, never a cursor: an action marks its own step done wherever
/// it sits in [steps], so a step she does early is not asked for again,
/// and the line always names the first step not yet done.
///
/// Over it, a reading cursor (D70): [back] shows an earlier step's line
/// again, [forward] walks back toward the live line. It only chooses which
/// line is shown — reading never marks, un-marks or re-runs a step — and
/// any action snaps the view back to the live line.
class GuideCoach {
  GuideCoach(List<GuideCoachStep> steps, {GuideLine? closing})
    : steps = List.unmodifiable(steps),
      _closing = closing ?? _cardsClosing;

  final List<GuideCoachStep> steps;

  /// The line once every step is done: the cards share one, the practice
  /// tour ends on its own.
  final GuideLine _closing;

  static String _cardsClosing(AppLocalizations l10n) =>
      l10n.calendarGuideCoachDone;

  final Set<String> _done = {};
  GuideLine? _report;

  /// The step being read back, as an index into [steps]; null at the live
  /// line. Always before [_live], so it only ever names a done step.
  int? _cursor;

  /// Whether [action] is one of [steps]: a page that runs more than one
  /// tour (the practice calendar's lessons) asks before [did], which takes
  /// steps only.
  bool hasStep(String action) => steps.any((step) => step.action == action);

  /// Whether [action]'s step is done or skipped: a step that only means
  /// something after others (taking filters back off) asks first.
  bool hasDone(String action) => _done.contains(action);

  /// [action] — one of [steps] — happened: its step is done. The stage
  /// shows what it did (D49), so the line goes back to an instruction.
  void did(String action) {
    assert(hasStep(action), action);
    _done.add(action);
    _report = null;
    _cursor = null;
  }

  /// An action that is no step and shows nothing on the stage: its report
  /// is the line until the next action of any kind — a step, a skip, or a
  /// non-step action that calls [clearReport].
  void say(GuideLine report) {
    _report = report;
    _cursor = null;
  }

  /// A non-step action happened: a standing report belonged to the action
  /// before it (D47 / D49), so the line goes back to the instruction.
  void clearReport() {
    _report = null;
    _cursor = null;
  }

  /// Steps past the current instruction without her doing it. Under a
  /// standing report the skip only clears it: she has not seen the
  /// instruction it covers, so that step is not hers to step past yet.
  /// Nothing to step past once every step is done.
  void skip() {
    _cursor = null;
    if (_report != null) {
      _report = null;
      return;
    }
    final step = current;
    if (step == null) return;
    _done.add(step.action);
    _report = null;
  }

  void reset() {
    _done.clear();
    _report = null;
    _cursor = null;
  }

  /// Where the live line stands in [steps]: the current step's index, or
  /// past the end once every step is done. Every step before it is done.
  int get _live {
    final step = current;
    return step == null ? steps.length : steps.indexOf(step);
  }

  /// An earlier step's line is shown rather than the live one.
  bool get reading => _cursor != null;

  /// The step whose line is read back; null at the live line.
  GuideCoachStep? get viewed {
    final cursor = _cursor;
    return cursor == null ? null : steps[cursor];
  }

  /// A done step lies before the one shown.
  bool get canBack => (_cursor ?? _live) > 0;

  /// While reading there is always a line nearer the live one; at the live
  /// line forward skips, so it is off only once the tour is finished.
  bool get canForward => reading || !finished;

  /// Shows the line of the step before the one shown. A standing report
  /// stays: it is the live line's, and comes back with it.
  void back() {
    if (!canBack) return;
    _cursor = (_cursor ?? _live) - 1;
  }

  /// One step toward the live line, which it reaches past the last step
  /// before it; at the live line, [skip].
  void forward() {
    final cursor = _cursor;
    if (cursor == null) {
      skip();
      return;
    }
    final next = cursor + 1;
    _cursor = next < _live ? next : null;
  }

  /// The first step not yet done; null once every step is.
  GuideCoachStep? get current {
    for (final step in steps) {
      if (!_done.contains(step.action)) return step;
    }
    return null;
  }

  bool get finished => current == null;

  /// At least one step is done or skipped: there is a tour to start over.
  bool get advanced => _done.isNotEmpty;

  /// The current instruction, or the closing line once every step is done.
  String next(AppLocalizations l10n) => current?.line(l10n) ?? _closing(l10n);

  String? report(AppLocalizations l10n) => _report?.call(l10n);

  /// A report stands on the line, for a stage that redraws only when an
  /// action would take something down.
  bool get hasReport => _report != null;

  /// The line: one clause (D49) — the step read back while [reading], else
  /// the last action's report while it stands, otherwise what is next.
  /// Reports and the closing line are never read back (D93).
  String line(AppLocalizations l10n) =>
      viewed?.line(l10n) ?? report(l10n) ?? next(l10n);

  /// Every line the coach can show over [reports] — each report at its
  /// longest — for a slot sized for the tallest: every instruction, the
  /// closing line and each report alone.
  List<String> candidates(AppLocalizations l10n, List<String> reports) {
    return {
      for (final step in steps) step.line(l10n),
      _closing(l10n),
      ...reports,
    }.toList();
  }
}
