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

  /// [action] — one of [steps] — happened: its step is done. The stage
  /// shows what it did (D49), so the line goes back to an instruction.
  void did(String action) {
    assert(steps.any((step) => step.action == action), action);
    _done.add(action);
    _report = null;
  }

  /// An action that is no step and shows nothing on the stage: its report
  /// is the line until the next action of any kind — a step, a skip, or a
  /// non-step action that calls [clearReport].
  void say(GuideLine report) => _report = report;

  /// A non-step action happened: a standing report belonged to the action
  /// before it (D47 / D49), so the line goes back to the instruction.
  void clearReport() => _report = null;

  /// Steps past the current instruction without her doing it. Under a
  /// standing report the skip only clears it: she has not seen the
  /// instruction it covers, so that step is not hers to step past yet.
  /// Nothing to step past once every step is done.
  void skip() {
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
  String next(AppLocalizations l10n) =>
      current?.line(l10n) ?? _closing(l10n);

  String? report(AppLocalizations l10n) => _report?.call(l10n);

  /// The line: one clause (D49) — the last action's report while it stands,
  /// otherwise what is next.
  String line(AppLocalizations l10n) => report(l10n) ?? next(l10n);

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
