/// Shared chrome for the drag-to-reorder settings lists — the markdown
/// shortcuts, the utility buttons and the calendar categories.
///
/// Extracted for the same reason `SettingsSearchField` was: three lists render
/// the same handle, the same drag proxy and the same "reorder is off" hint,
/// and three copies of a look is where one of them silently drifts.
library;

import 'package:flutter/material.dart';

import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';

/// The drag handle at the head of a reorderable row.
///
/// [index] wires the handle to the enclosing reorderable list; leave it null
/// when the list supplies its own default drag handles, or when dragging is
/// currently off. [enabled] is the *visual* state, deliberately separate:
/// the handle keeps its slot and only greys **in place** while a filter is
/// active, so clearing the filter does not shift every row sideways.
///
/// The handle is a [FormMetrics.dragHandleSlot] target around its glyph, so
/// a finger that lands beside the 24 px glyph still lifts the row; the glyph
/// is `outline`, which meets 3:1 on `rowGroup` in both themes where the old
/// `onSurface` at 40 % measured 2.47:1 in light. [label] is the handle's
/// accessible name ("Reorder {name}") — a semantics label, never a
/// `Tooltip`, whose long-press recogniser would win the arena and kill the
/// drag.
class ReorderHandle extends StatelessWidget {
  final int? index;
  final bool enabled;
  final String? label;

  const ReorderHandle({super.key, this.index, this.enabled = true, this.label});

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      Icons.drag_handle,
      size: FormMetrics.dragHandleGlyphSize,
      color: Theme.of(context).colorScheme.outline,
    );
    Widget handle = SizedBox.square(
      dimension: FormMetrics.dragHandleSlot,
      child: Center(
        child: enabled
            ? glyph
            : Opacity(opacity: FormMetrics.disabledOpacity, child: glyph),
      ),
    );
    if (label case final name?) {
      handle = Semantics(label: name, child: handle);
    }
    final at = index;
    if (at == null) return handle;
    return ReorderableDragStartListener(index: at, child: handle);
  }
}

/// The line explaining that reorder is off because a search or filter is
/// active. Reorder and filtering are mutually exclusive in every list that
/// offers both — render indices stop mapping to real positions.
///
/// Drawn in `onSurfaceVariant` at full strength: the line is small text on
/// `pageGround`, where `onSurface` at 60 % measured 4.29:1 in light.
class ReorderLockedHint extends StatelessWidget {
  final double horizontalPadding;

  /// The words, when a list has no filters to name — the shared line says
  /// "search and filters".
  final String? text;

  const ReorderLockedHint({
    super.key,
    this.horizontalPadding = RowMetrics.groupInset,
    this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final color = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        FormMetrics.reorderHintBottomPadding,
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: FormMetrics.reorderHintGlyphSize,
            color: color,
          ),
          const SizedBox(width: FormMetrics.reorderHintGlyphGap),
          Expanded(
            child: Text(
              text ?? l10n.clearSearchToReorder,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The corner the lifted row's shadow follows. A row that paints its own
/// square corners (a middle row of a form group) clips to it as well, so the
/// card and its shadow agree.
const double reorderProxyRadius = 12;

/// The lift a dragged row gets while it is being carried: a hair of scale and
/// a shadow that fade in with the drag animation. Matches
/// `ReorderItemProxyDecorator`, so it can be passed straight as
/// `proxyDecorator`.
///
/// [borderRadius] is the lifted card's own corner when it has one, so the
/// shadow is painted on the shape the card draws rather than beside it.
Widget reorderDragProxy(
  Widget child,
  int index,
  Animation<double> animation, {
  BorderRadius borderRadius = const BorderRadius.all(
    Radius.circular(reorderProxyRadius),
  ),
}) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = Curves.easeInOut.transform(animation.value);
      return Transform.scale(
        scale: 1 + 0.02 * t,
        child: Material(
          color: Colors.transparent,
          elevation: 6 * t,
          borderRadius: borderRadius,
          child: child,
        ),
      );
    },
    child: child,
  );
}
