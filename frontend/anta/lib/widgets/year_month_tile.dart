import 'package:flutter/material.dart';

/// One month of a year overview: a label, a count and a dot matrix on a
/// rounded tile. Shared by the agenda drill-down's year mode and the date
/// picker's year view so the two cannot drift apart.
class YearMonthTile extends StatelessWidget {
  static const SliverGridDelegate gridDelegate =
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisExtent: 116,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
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
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.labelLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        count,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: countColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
