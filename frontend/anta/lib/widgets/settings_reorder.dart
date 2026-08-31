/// Shared chrome for the drag-to-reorder settings lists — the markdown
/// shortcuts, the utility buttons and the calendar categories.
///
/// Extracted for the same reason `SettingsSearchField` was: three lists render
/// the same handle, the same drag proxy and the same "reorder is off" hint,
/// and three copies of a look is where one of them silently drifts.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The drag handle at the head of a reorderable row.
///
/// [index] wires the handle to the enclosing reorderable list; leave it null
/// when the list supplies its own default drag handles, or when dragging is
/// currently off. [enabled] is the *visual* state, deliberately separate:
/// the handle keeps its slot and only greys **in place** while a filter is
/// active, so clearing the filter does not shift every row sideways.
class ReorderHandle extends StatelessWidget {
  final int? index;
  final bool enabled;

  const ReorderHandle({super.key, this.index, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.drag_handle,
      size: 24,
      color: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: enabled ? 0.4 : 0.15),
    );
    final at = index;
    if (at == null) return icon;
    return ReorderableDragStartListener(index: at, child: icon);
  }
}

/// The line explaining that reorder is off because a search or filter is
/// active. Reorder and filtering are mutually exclusive in every list that
/// offers both — render indices stop mapping to real positions.
class ReorderLockedHint extends StatelessWidget {
  final double horizontalPadding;

  const ReorderLockedHint({super.key, this.horizontalPadding = 16});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.clearSearchToReorder,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lift a dragged row gets while it is being carried: a hair of scale and
/// a shadow that fade in with the drag animation. Matches
/// `ReorderItemProxyDecorator`, so it can be passed straight as
/// `proxyDecorator`.
Widget reorderDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final t = Curves.easeInOut.transform(animation.value);
      return Transform.scale(
        scale: 1 + 0.02 * t,
        child: Material(
          color: Colors.transparent,
          elevation: 6 * t,
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
      );
    },
    child: child,
  );
}
