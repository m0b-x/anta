import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../utils/event_agenda.dart';
import 'agenda_list_view.dart';

/// Whether a scroll should extend the add button (`true`), collapse it
/// (`false`), or leave it alone (`null`).
///
/// The **axis guard is the point**: a `UserScrollNotification` bubbles up from
/// every scrollable under the page, and both the agenda's summary-chip row and
/// the timeline's hour track scroll horizontally — letting those drive the
/// button would collapse it on a sideways swipe that never hid anything.
///
/// Pulled out as a pure function so that rule is testable rather than buried in
/// a callback.
bool? fabExtendedFor(UserScrollNotification notification) {
  if (notification.metrics.axis != Axis.vertical) return null;
  return switch (notification.direction) {
    // Content moving up: the user is reading downward, so get out of the way.
    ScrollDirection.reverse => false,
    ScrollDirection.forward || ScrollDirection.idle => true,
  };
}

/// The calendar's add button: an extended FAB naming the day it will add to,
/// collapsing to a circle while the panel scrolls.
///
/// It has always targeted the calendar's **selected** day rather than today,
/// and a bare `+` said nothing about that — after tapping Sep 15 in the grid
/// there was nothing on screen to confirm where a new event would land. The
/// label is the fix; the `+` icon already carries the verb, so the label only
/// has to name the day.
///
/// Nothing here reserves space for itself. Scroll content clears it through
/// `AppSpacing.fabClearance`, which is what makes the last row's trailing
/// actions reachable whether the button is extended, collapsed or idle —
/// collapsing alone would only move the problem to the moment the user stops
/// scrolling.
class CalendarAddFab extends StatelessWidget {
  /// The day a new event lands on, or null while the calendar services are
  /// still resolving — in which case the button is inert, because the editor
  /// reads `CalendarCategories` and would otherwise open on an empty picker.
  final DateTime? selectedDay;

  /// Source of the accent colour. Passed down from the page like every other
  /// appearance consumer, never re-read here.
  final CalendarAppearance appearance;

  /// Drives the collapse. A listenable rather than a constructor `bool` so the
  /// page can update it from a scroll notification **without** `setState` —
  /// which would rebuild the 42-cell grid and the whole bottom panel on every
  /// scroll tick, exactly what their `sameGridInputs` / `samePanelInputs`
  /// gates exist to prevent.
  final ValueListenable<bool> extended;

  final ValueChanged<DateTime> onPressed;

  const CalendarAddFab({
    super.key,
    required this.selectedDay,
    required this.appearance,
    required this.extended,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = appearance.accentOr(theme.colorScheme.primary);
    // The accent is user-picked and can be anything, so `onPrimary` is not
    // enough — the same brightness estimate `CalendarDayCell` uses for the
    // day number on a filled cell.
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final day = selectedDay;

    return ValueListenableBuilder<bool>(
      valueListenable: extended,
      builder: (context, isExtended, _) {
        return FloatingActionButton.extended(
          tooltip: l10n.addEvent,
          backgroundColor: accent,
          foregroundColor: onAccent,
          onPressed: day == null ? null : () => onPressed(day),
          // With no day there is nothing to name, so a labelled button would
          // be worse than a circle. `FloatingActionButton.extended` animates
          // between the two itself — there is no custom transition here.
          isExtended: isExtended && day != null,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            day == null
                ? ''
                : AgendaListView.shortDayLabel(
                    l10n,
                    day,
                    EventAgenda.dateOnly(DateTime.now()),
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
