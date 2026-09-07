import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Where a row sits inside its rounded group, which is what decides its
/// corner radii and whether it draws a trailing divider.
enum RowGroupPosition {
  single,
  first,
  middle,
  last;

  bool get isFirst => this == RowGroupPosition.first || this == single;
  bool get isLast => this == RowGroupPosition.last || this == single;
}

const double _groupRadius = 14;
const double _groupInset = 16;

/// The grouped-list container a folder or note row is drawn in.
///
/// Rows in one group share a single rounded rectangle: only the ends round
/// off, and every row but the last carries an inset divider, so a run of
/// rows reads as one card rather than a stack of them.
class ContentRowShell extends StatelessWidget {
  final RowGroupPosition position;
  final bool isSelected;
  final bool isDropTarget;
  final Widget child;

  const ContentRowShell({
    super.key,
    required this.position,
    required this.child,
    this.isSelected = false,
    this.isDropTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = Radius.circular(_groupRadius);
    return Padding(
      padding: EdgeInsets.only(
        left: _groupInset,
        right: _groupInset,
        bottom: position.isLast ? 12 : 0,
      ),
      child: Material(
        type: MaterialType.card,
        clipBehavior: Clip.antiAlias,
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
            : colorScheme.rowGroup,
        borderRadius: BorderRadius.vertical(
          top: position.isFirst ? radius : Radius.zero,
          bottom: position.isLast ? radius : Radius.zero,
        ),
        child: Container(
          foregroundDecoration: isDropTarget
              ? BoxDecoration(
                  border: Border.all(color: colorScheme.primary, width: 2),
                  borderRadius: BorderRadius.vertical(
                    top: position.isFirst ? radius : Radius.zero,
                    bottom: position.isLast ? radius : Radius.zero,
                  ),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              if (!position.isLast)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 68,
                  endIndent: 0,
                  color: colorScheme.rowDivider,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Folders" / "Notes" label above a group. Sits in the same list as the
/// rows so a single reorderable sliver can render both, and carries no drag
/// listener, which is what makes it undraggable.
class ContentSectionHeader extends StatelessWidget {
  final String label;

  const ContentSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_groupInset + 4, 16, _groupInset, 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Floating chip displayed under the user's finger while a selection batch
/// is being dragged onto a target folder.
class DragFeedbackChip extends StatelessWidget {
  final int count;

  const DragFeedbackChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 8,
      color: colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator, color: colorScheme.onPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
