import 'package:flutter/painting.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/event_presence.dart';
import '../constants/fasting_calendar.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_cell_tint.dart';
import '../utils/event_agenda.dart';

/// Contract for anything that washes a calendar day cell.
///
/// The same purity contract as `DayBarProvider`: [tintFor] runs for every
/// visible cell on every rebuild (~42 per frame in month format). No I/O, no
/// BLoC access, no recurrence expansion — static facade probes only.
abstract interface class CellTintProvider {
  CellTintLayer? tintFor(DateTime day, List<CalendarEvent> events);
}

/// Washes the cell with the day's **top** event colour.
///
/// "Top" is decided by [EventAgenda.compareWithinDay], the one same-day
/// comparator — the same event the day panel lists first and the grid draws
/// as its first stripe. Exactly one event contributes: averaging a day's
/// colours yields a hue that belongs to no event on it.
///
/// The alpha encodes that event's priority, which is the whole point of the
/// feature: P1 washes strongly, P5 barely. The colour itself follows the day
/// bar's rule (`colorValue ?? category.color`) and deliberately ignores
/// `tintIcon` — that flag governs icon tinting on the summary and detail
/// surfaces, and every grid surface already ignores it.
class EventCellTintProvider implements CellTintProvider {
  final CalendarMissedDisplay missedDisplay;
  final int priority;

  const EventCellTintProvider({
    required this.priority,
    this.missedDisplay = CalendarMissedDisplay.faded,
  });

  @override
  CellTintLayer? tintFor(DateTime day, List<CalendarEvent> events) {
    if (events.isEmpty) return null;

    CalendarEvent? top;
    var topMissed = false;
    for (final event in events) {
      final missed =
          EventPresence.appliesTo(event) &&
          EventPresence.isMissed(event.id, day);
      // A hidden missed occurrence is drawn nowhere else, so it must not be
      // able to claim the wash either.
      if (missed && missedDisplay == CalendarMissedDisplay.hidden) continue;
      if (top == null || EventAgenda.compareWithinDay(event, top) < 0) {
        top = event;
        topMissed = missed;
      }
    }
    if (top == null) return null;

    final base = top.colorValue != null
        ? Color(top.colorValue!)
        : CalendarCategories.resolve(top.categoryId).color;
    final index = (top.priority - kMinEventPriority).clamp(
      0,
      CalendarColors.eventTintAlphaByPriority.length - 1,
    );
    var wash = CalendarColors.eventTintAlphaByPriority[index];
    var edgeAlpha = CalendarColors.cellEdgeAlpha;
    // A missed occurrence keeps the slot it won (matching the bars, where a
    // missed P1 still holds its stripe) but fades to the shared alpha.
    if (topMissed) {
      wash *= CalendarColors.missedEventAlpha;
      edgeAlpha *= CalendarColors.missedEventAlpha;
    }

    return CellTintLayer(
      key: 'event',
      wash: base.withValues(alpha: wash),
      edge: base.withValues(alpha: edgeAlpha),
      priority: priority,
    );
  }
}

/// Washes the cell with the religious-fasting tint already resolved by
/// [FastingCalendar.cellStyleFor] (memoized per day inside the engine). The
/// bold-number "strong" style is not a tint and stays the day cell's own job.
class FastingCellTintProvider implements CellTintProvider {
  final int priority;

  const FastingCellTintProvider({required this.priority});

  @override
  CellTintLayer? tintFor(DateTime day, List<CalendarEvent> events) {
    final tint = FastingCalendar.cellStyleFor(day).tint;
    if (tint == null) return null;
    return CellTintLayer(
      key: 'fasting',
      wash: tint.withValues(alpha: CalendarColors.fastingTintAlpha),
      edge: tint.withValues(alpha: CalendarColors.cellEdgeAlpha),
      priority: priority,
    );
  }
}

/// Chains [CellTintProvider]s into the single [DayCellTint] a cell paints.
///
/// The winner (lowest priority band) takes the wash. The runner-up takes the
/// edge stripe only when [layerRunnerUp] is set — otherwise it contributes
/// nothing, because two stacked washes blend into a colour that belongs to
/// neither source.
///
/// To add a tint source, implement [CellTintProvider] and give it a band in
/// [CellTintResolver.defaults]; no call site changes.
class CellTintResolver {
  /// Band assigned to whichever source the user's conflict setting favours.
  static const int winnerPriority = 0;

  /// Band assigned to the source it favours less.
  static const int runnerUpPriority = 100;

  final List<CellTintProvider> providers;
  final bool layerRunnerUp;

  const CellTintResolver({required this.providers, this.layerRunnerUp = false});

  /// Empty resolver — no provider, so [resolve] always returns
  /// [DayCellTint.empty]. Used by surfaces that render a [CalendarDayCell]
  /// outside the grid (the date pickers).
  static const CellTintResolver none = CellTintResolver(providers: []);

  /// [showFasting] is the grid filter's fasting layer. Turning it off drops
  /// the fasting provider outright, which also takes the day rail's base band
  /// with it — the band *is* the runner-up wash, so there is no second place
  /// to suppress it.
  factory CellTintResolver.defaults(
    CalendarAppearance appearance, {
    bool showFasting = true,
  }) {
    // With event tinting off the fasting wash is the only source, and the
    // conflict setting is unreachable — rendering stays exactly as it was
    // before the feature existed.
    if (!appearance.eventTint) {
      return showFasting
          ? const CellTintResolver(
              providers: [FastingCellTintProvider(priority: winnerPriority)],
            )
          : none;
    }
    final eventFirst =
        appearance.tintConflict != CalendarTintConflict.fastingWins;
    return CellTintResolver(
      providers: [
        EventCellTintProvider(
          priority: eventFirst ? winnerPriority : runnerUpPriority,
          missedDisplay: appearance.missedDisplay,
        ),
        if (showFasting)
          FastingCellTintProvider(
            priority: eventFirst ? runnerUpPriority : winnerPriority,
          ),
      ],
      layerRunnerUp: appearance.tintConflict == CalendarTintConflict.both,
    );
  }

  DayCellTint resolve(DateTime day, List<CalendarEvent> events) {
    CellTintLayer? winner;
    CellTintLayer? runnerUp;
    for (final provider in providers) {
      final layer = provider.tintFor(day, events);
      if (layer == null) continue;
      if (winner == null || layer.priority < winner.priority) {
        runnerUp = winner;
        winner = layer;
      } else if (runnerUp == null || layer.priority < runnerUp.priority) {
        runnerUp = layer;
      }
    }
    if (winner == null) return DayCellTint.empty;
    return DayCellTint(
      wash: winner.wash,
      edge: layerRunnerUp ? runnerUp?.edge : null,
    );
  }
}
