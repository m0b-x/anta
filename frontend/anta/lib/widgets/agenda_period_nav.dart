import 'package:flutter/material.dart';

/// The navigation row above a month grid or a year overview: a chevron each
/// side, the period's title and count in the middle, and a button back to the
/// current period in a fixed slot so the title never shifts when it is
/// disabled. With [onTitleTap] the title becomes the jump control — a tap
/// opens a date picker — and wears a drop-down glyph to say so.
class AgendaPeriodNav extends StatelessWidget {
  /// Side of the square slots the buttons sit in — a full Material touch
  /// target, matching the chevrons.
  static const double slot = 48;

  final String title;
  final String? subtitle;
  final String previousTooltip;
  final String nextTooltip;
  final String todayTooltip;

  /// Null disables the button.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToday;

  final VoidCallback? onTitleTap;
  final String? titleTooltip;

  const AgendaPeriodNav({
    super.key,
    required this.title,
    this.subtitle,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.todayTooltip,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    this.onTitleTap,
    this.titleTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    Widget heading = Text(
      title,
      style: titleStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (onTitleTap != null) {
      heading = Tooltip(
        message: titleTooltip ?? '',
        child: InkWell(
          onTap: onTitleTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: heading),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: previousTooltip,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Column(
              children: [
                heading,
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: slot,
            child: IconButton(
              tooltip: todayTooltip,
              icon: const Icon(Icons.today_rounded),
              onPressed: onToday,
            ),
          ),
          IconButton(
            tooltip: nextTooltip,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
