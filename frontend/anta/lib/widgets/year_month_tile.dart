import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/overview_list_metrics.dart';

/// One month of a year overview: a label, a count and a dot matrix on a
/// rounded tile. Shared by the agenda drill-down's year mode and the date
/// picker's year view so the two cannot drift apart.
class YearMonthTile extends StatelessWidget {
  static const SliverGridDelegateWithMaxCrossAxisExtent gridDelegate =
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: OverviewListMetrics.yearTileMaxWidth,
        mainAxisExtent: OverviewListMetrics.yearTileHeight,
        mainAxisSpacing: OverviewListMetrics.yearTileSpacing,
        crossAxisSpacing: OverviewListMetrics.yearTileSpacing,
      );

  /// How many tiles [gridDelegate] lays side by side across
  /// [crossAxisExtent] — its own `getLayout` rule, so a surface that lays the
  /// tiles out in rows of its own (the overview's year scroll) cuts them
  /// exactly where the grid would.
  static int columnsFor(double crossAxisExtent) => math.max(
    1,
    (crossAxisExtent /
            (gridDelegate.maxCrossAxisExtent + gridDelegate.crossAxisSpacing))
        .ceil(),
  );

  final String label;
  final String count;
  final Color countColor;
  final String semanticsLabel;
  final Color background;
  final VoidCallback onTap;
  final Widget matrix;

  const YearMonthTile({
    super.key,
    required this.label,
    required this.count,
    required this.countColor,
    required this.semanticsLabel,
    required this.background,
    required this.onTap,
    required this.matrix,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(OverviewListMetrics.yearTileRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(
                OverviewListMetrics.yearTilePadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontSize: OverviewListMetrics.yearTileLabelSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        count,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: OverviewListMetrics.yearTileCountSize,
                          fontWeight: FontWeight.w700,
                          color: countColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: OverviewListMetrics.yearTileMatrixGap),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: matrix,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
