import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';

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

/// The grouped-list container a folder or note row is drawn in.
///
/// Rows in one group share a single rounded rectangle: only the ends round
/// off, and every row but the last carries an inset divider, so a run of
/// rows reads as one card rather than a stack of them.
///
/// Only the ends are a clipped [Material]. A middle row has no corner to
/// round, so it is painted flat and hosts its ink on a transparent
/// [Material] — a clip path and a shape tween per row is what a long list
/// paid for corners that were never drawn.
class ContentRowShell extends StatelessWidget {
  final RowGroupPosition position;
  final bool isSelected;
  final bool isDropTarget;

  /// Where the divider under this row starts: past the leading glyph on a
  /// row that has one, at the group edge on a row that does not.
  final double dividerIndent;

  final Widget child;

  const ContentRowShell({
    super.key,
    required this.position,
    required this.child,
    this.dividerIndent = RowMetrics.dividerIndentPlain,
    this.isSelected = false,
    this.isDropTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = Radius.circular(RowMetrics.groupRadius);
    final color = isSelected
        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
        : colorScheme.rowGroup;
    final borderRadius = BorderRadius.vertical(
      top: position.isFirst ? radius : Radius.zero,
      bottom: position.isLast ? radius : Radius.zero,
    );

    final body = Container(
      foregroundDecoration: isDropTarget
          ? BoxDecoration(
              border: Border.all(color: colorScheme.primary, width: 2),
              borderRadius: borderRadius,
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
              indent: dividerIndent,
              endIndent: 0,
              color: colorScheme.rowDivider,
            ),
        ],
      ),
    );

    final hasCorners = position != RowGroupPosition.middle;

    return Padding(
      padding: EdgeInsets.only(
        left: RowMetrics.groupInset,
        right: RowMetrics.groupInset,
        bottom: position.isLast ? RowMetrics.groupGap : 0,
      ),
      child: hasCorners
          ? Material(
              type: MaterialType.card,
              clipBehavior: Clip.antiAlias,
              color: color,
              borderRadius: borderRadius,
              child: body,
            )
          : ColoredBox(
              color: color,
              child: Material(type: MaterialType.transparency, child: body),
            ),
    );
  }
}

/// The "Folders" / "Notes" label above a group. Sits in the same list as the
/// rows so a single reorderable sliver can render both, and carries no drag
/// listener, which is what makes it undraggable.
///
/// It adds nothing above itself: the air between two groups is the previous
/// group's [RowMetrics.groupGap], so the first label in a list sits flush
/// under the title rather than a gap below it.
class ContentSectionHeader extends StatelessWidget {
  final String label;

  const ContentSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset + RowMetrics.sectionLabelInset,
        0,
        RowMetrics.groupInset,
        RowMetrics.sectionLabelBottomPadding,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: RowMetrics.sectionLabelFontSize,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: RowMetrics.sectionLabelLetterSpacing,
          fontWeight: RowMetrics.sectionLabelFontWeight,
        ),
      ),
    );
  }
}

/// The trailing end of a folder or smart row: the descendant count, then the
/// chevron that says the row opens something.
///
/// The count keeps a reserved width whether or not it has arrived, so a late
/// answer never reflows the name beside it.
class RowCountChevron extends StatelessWidget {
  final int? count;

  const RowCountChevron({super.key, this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final value = count;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: RowMetrics.countMinWidth,
          ),
          child: Text(
            value == null ? '' : '$value',
            textAlign: TextAlign.end,
            maxLines: 1,
            style: TextStyle(
              fontSize: RowMetrics.countFontSize,
              color: colorScheme.outline,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: RowMetrics.gap),
        Icon(
          Icons.chevron_right,
          size: RowMetrics.chevronSize,
          color: colorScheme.outline,
        ),
      ],
    );
  }
}

/// One row of a row's long-press sheet.
class RowAction {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onSelected;

  const RowAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.isDestructive = false,
  });
}

/// The sheet a long-press on a folder or note row raises, now that neither
/// draws a per-row overflow button.
///
/// The bottom padding is `max(viewInsets, viewPadding)`: either alone leaves
/// the last row under the keyboard or under the gesture bar.
///
/// [headerBuilder], when given, draws between the title's divider and the
/// first action, with a divider of its own beneath. It is a *builder* rather
/// than a widget because the header is interactive — the colour-label strip
/// closes the sheet when a swatch is picked — and only the sheet's own
/// context can pop it.
Future<void> showRowActionSheet(
  BuildContext context, {
  required String title,
  required List<RowAction> actions,
  Widget Function(BuildContext sheetContext)? headerBuilder,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final bottomInset = math.max(
        media.viewInsets.bottom,
        media.viewPadding.bottom,
      );
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            if (headerBuilder != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: headerBuilder(sheetContext),
              ),
              const Divider(),
            ],
            for (final action in actions)
              ListTile(
                leading: Icon(
                  action.icon,
                  color: action.isDestructive ? colorScheme.error : null,
                ),
                title: Text(
                  action.label,
                  style: action.isDestructive
                      ? TextStyle(color: colorScheme.error)
                      : null,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action.onSelected();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
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
