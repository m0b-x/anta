import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/semantics_ids.dart';
import 'automation_id.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../utils/event_agenda.dart';
import 'agenda_list_view.dart';

/// How far, in logical pixels, a list may sit below its top and still count
/// as "at the top" for [fabExtendedFor].
///
/// A drag that starts at the top and moves a few pixels has hidden nothing yet
/// and the button should not flinch; past this the reader is into the
/// content. Eight is under the touch slop, so a settled list can never sit
/// inside it by accident.
const double fabTopSlack = 8;

/// Whether [notification] should extend the add button (`true`), collapse it
/// (`false`), or leave it as it is (`null`).
///
/// The rule the button follows, in the reader's terms: **the label shows
/// while the list under it is at the top or moving back toward it, hides
/// once the reader has moved down into the content, and stays hidden until
/// they come back up.** Every input is a movement or a shape of the list,
/// never the finger — and that is the whole fix.
///
/// The previous rule keyed off `UserScrollNotification`, which reports the
/// *drag* direction and then `idle` the moment the finger lifts — so the
/// button collapsed while a finger was moving and popped back the instant it
/// stopped, which read as random; and when a list went away mid-scroll (a
/// mode switch, a day tap while flinging) the idle never came and the button
/// stayed a bare `+` with nothing left to re-extend it. Neither can happen
/// here: the decision is made from where the content *is*, and a list that
/// mounts or reshapes at its top re-extends the button through its own
/// metrics notification.
///
/// Rules, in order:
///  * a non-vertical scrollable is ignored outright — the agenda's summary-chip
///    row, the timeline's hour track and the grid's month pager all scroll
///    sideways and hide nothing;
///  * a [ScrollMetricsNotification] (a list that just mounted, or whose content
///    or viewport changed) extends the button when the list is at its top and
///    is otherwise left alone — a lazy list grows its extent while being read,
///    and that must not pull the label back mid-scroll;
///  * an [OverscrollNotification] past the top extends it (the reader is
///    pulling for more above); past the bottom it is left alone;
///  * a [ScrollUpdateNotification] moving the content back toward the top
///    extends it, one moving down past [fabTopSlack] collapses it, and one
///    that stays within the slack extends it;
///  * everything else — start, end and user-direction notifications — is
///    left alone, so a finger lifting changes nothing.
///
/// Pulled out as a pure function so the table is testable rather than buried
/// in a callback.
bool? fabExtendedFor(Notification notification) {
  switch (notification) {
    case ScrollMetricsNotification(:final metrics):
      if (metrics.axis != Axis.vertical) return null;
      return _atTop(metrics) ? true : null;
    case OverscrollNotification(:final metrics, :final overscroll):
      if (metrics.axis != Axis.vertical) return null;
      return overscroll < 0 ? true : null;
    case ScrollUpdateNotification(:final metrics, :final scrollDelta):
      if (metrics.axis != Axis.vertical) return null;
      if (_atTop(metrics)) return true;
      final delta = scrollDelta;
      if (delta == null || delta == 0) return null;
      return delta < 0;
    default:
      return null;
  }
}

bool _atTop(ScrollMetrics metrics) =>
    !metrics.hasPixels ||
    metrics.pixels <= metrics.minScrollExtent + fabTopSlack;

/// One line describing what [fabExtendedFor] saw and decided, for the
/// developer-options trace over the button. Null when the notification is
/// one the rule ignores by type, so the trace shows only what can matter.
String? describeFabNotification(Notification notification, bool? decision) {
  final String what;
  switch (notification) {
    case ScrollMetricsNotification(:final metrics):
      what = 'metrics ${_describeMetrics(metrics)}';
    case OverscrollNotification(:final metrics, :final overscroll):
      what =
          'overscroll ${overscroll < 0 ? "top" : "bottom"} '
          '${_describeMetrics(metrics)}';
    case ScrollUpdateNotification(:final metrics, :final scrollDelta):
      final arrow = scrollDelta == null
          ? '·'
          : scrollDelta > 0
          ? '↓'
          : scrollDelta < 0
          ? '↑'
          : '·';
      what = 'update $arrow ${_describeMetrics(metrics)}';
    default:
      return null;
  }
  final verdict = switch (decision) {
    true => 'extend',
    false => 'collapse',
    null => 'keep',
  };
  return '$what → $verdict';
}

String _describeMetrics(ScrollMetrics metrics) {
  final axis = metrics.axis == Axis.vertical ? 'v' : 'h';
  if (!metrics.hasPixels) return '$axis ?px';
  return '$axis ${metrics.pixels.round()}px';
}

/// The glyph's lightness on a dark-theme custom accent — see
/// [calendarAddFabColors].
const double _darkGlyphLightness = 0.90;

/// Fill lightness candidates for a dark-theme custom accent, lightest first;
/// the first that clears [_minGlyphContrast] under the glyph wins.
const List<double> _darkFillStops = [0.32, 0.28, 0.24];

/// WCAG AA for the glyph over the fill — the same `(L + 0.05) / (L' + 0.05)`
/// ratio `CalendarDayBars` and `MarkdownColorPalette` compute.
const double _minGlyphContrast = 4.5;

/// The add button's fill and glyph, resolved per theme.
///
/// The two themes deliberately get different roles. In light the accent is a
/// saturated tone on a pale ground, so the button keeps the **filled** look:
/// the accent itself, with the glyph picked by the same brightness estimate
/// `CalendarDayCell._onAccent` uses, because a user-picked accent makes
/// `onPrimary` wrong. In dark the theme's primary is a pale tint, and filled
/// with it the button was the brightest object on the screen, brighter than
/// the today ring it sits under. There the button takes the **container**
/// tone instead: the scheme's own `primaryContainer` pair for the theme
/// accent, and for a user-picked accent a 0.90-lightness glyph of its own hue
/// over a fill of the same hue at the **lightest of three stops that still
/// reads** — 0.32, then 0.28, then 0.24. One fixed stop cannot serve every
/// hue: at 0.32 a purple sits a clear tone above the dark surface while teal
/// or cyan, luminous hues, leave the glyph under 3:1; at 0.24 the teal reads
/// but the purple sinks into the surface. Stepping down only as far as the
/// glyph needs keeps both — `test/widgets/calendar_add_fab_test.dart` walks
/// every built-in swatch.
///
/// A pure function so the table is testable without pumping a button.
({Color background, Color foreground}) calendarAddFabColors({
  required ColorScheme scheme,
  required CalendarAppearance appearance,
}) {
  final custom = appearance.accentColorValue;
  if (scheme.brightness == Brightness.dark) {
    if (custom == null) {
      return (
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      );
    }
    final hsl = HSLColor.fromColor(Color(custom));
    final foreground = hsl.withLightness(_darkGlyphLightness).toColor();
    final glyphLuminance = foreground.computeLuminance();
    var background = hsl.withLightness(_darkFillStops.last).toColor();
    for (final stop in _darkFillStops) {
      final candidate = hsl.withLightness(stop).toColor();
      final ratio =
          (glyphLuminance + 0.05) / (candidate.computeLuminance() + 0.05);
      if (ratio >= _minGlyphContrast) {
        background = candidate;
        break;
      }
    }
    return (background: background, foreground: foreground);
  }
  final accent = appearance.accentOr(scheme.primary);
  final onAccent =
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : Colors.black87;
  return (background: accent, foreground: onAccent);
}

/// The calendar's add button: an extended FAB naming the day it will add to,
/// collapsing to a circle while the reader is down inside the panel's list.
///
/// It has always targeted the calendar's **selected** day rather than today,
/// and a bare `+` said nothing about that — after tapping Sep 15 in the grid
/// there was nothing on screen to confirm where a new event would land. The
/// label is the fix; the `+` icon already carries the verb, so the label only
/// has to name the day.
///
/// A long press opens the template picker for that same day — the day-cell
/// long press, reachable with the thumb that is already on the button.
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

  /// Long press: quick-add from a template for the same day. Optional so the
  /// widget stays usable where templates are not wired.
  final ValueChanged<DateTime>? onLongPressed;

  /// The developer-options trace: the last collapse decision, rendered as a
  /// caption above the button. Null (the default) renders nothing and costs
  /// nothing.
  final ValueListenable<String?>? trace;

  /// The resting elevation, shared by the disabled and pressed states.
  static const double elevation = 2;

  const CalendarAddFab({
    super.key,
    required this.selectedDay,
    required this.appearance,
    required this.extended,
    required this.onPressed,
    this.onLongPressed,
    this.trace,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = calendarAddFabColors(
      scheme: Theme.of(context).colorScheme,
      appearance: appearance,
    );
    final day = selectedDay;
    final longPress = onLongPressed;

    final button = ValueListenableBuilder<bool>(
      valueListenable: extended,
      builder: (context, isExtended, _) {
        // The tooltip is the button's accessible name; it is manual so the
        // long press reaches the quick-add below instead of opening it.
        return AutomationId(
          identifier: SemanticsIds.calendarAddEvent,
          child: Tooltip(
            message: l10n.addEvent,
            triggerMode: TooltipTriggerMode.manual,
            child: GestureDetector(
              onLongPress: day == null || longPress == null
                  ? null
                  : () => longPress(day),
              child: FloatingActionButton.extended(
                backgroundColor: colors.background,
                foregroundColor: colors.foreground,
                // Material's default is 6, and this was the only shadow on a
                // page whose bars, cards and controls are all flat — the one
                // thing that made the button look imported from another app.
                // Two is the least that still separates it from rows
                // scrolling under it; the pressed state keeps the same level,
                // as Material 3 does.
                elevation: elevation,
                focusElevation: elevation,
                highlightElevation: elevation,
                hoverElevation: elevation + 2,
                onPressed: day == null ? null : () => onPressed(day),
                // With no day there is nothing to name, so a labelled button
                // would be worse than a circle. `FloatingActionButton.extended`
                // animates between the two itself — there is no custom
                // transition here.
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
              ),
            ),
          ),
        );
      },
    );

    final traceListenable = trace;
    if (traceListenable == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: traceListenable,
          builder: (context, text, _) {
            if (text == null) return const SizedBox.shrink();
            return _FabTraceCaption(text: text);
          },
        ),
        button,
      ],
    );
  }
}

/// The developer-options caption above the button: the last notification the
/// collapse rule saw and what it decided. Excluded from semantics so the
/// trace never leaks into the button's accessible name.
class _FabTraceCaption extends StatelessWidget {
  final String text;

  const _FabTraceCaption({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.2,
                color: scheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
