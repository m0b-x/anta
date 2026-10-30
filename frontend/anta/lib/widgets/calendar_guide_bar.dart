import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_bar_metrics.dart';
import 'automation_id.dart';
import 'calendar_header_menus.dart';

/// The calendar page's bar over a guide demo: the title as the view menu,
/// then three action slots — the saved filters' place, the funnel, the ⋮ —
/// in the calendar page's sizes and colours.
///
/// The one copy of that bar in the guide: the practice page draws it as its
/// own bar with its controls live, and the screen page's grid card draws it
/// on its stage, so a change to how the calendar's bar is built reaches both
/// (the owner's rule, D59). The callers fill the slots; [filterButton] is the
/// funnel both draw.
class GuideCalendarBar extends StatelessWidget implements PreferredSizeWidget {
  const GuideCalendarBar({
    super.key,
    required this.format,
    required this.onFormatSelected,
    required this.onPageSelected,
    required this.savedFiltersSlot,
    required this.filterSlot,
    required this.moreSlot,
    this.primary = true,
    this.automaticallyImplyLeading = true,
  });

  final CalendarFormat format;

  /// Null draws the formats disabled: the practice page before its demo has
  /// loaded.
  final ValueChanged<CalendarFormat>? onFormatSelected;
  final ValueChanged<CalendarViewPage> onPageSelected;

  final Widget savedFiltersSlot;
  final Widget filterSlot;
  final Widget moreSlot;

  /// False on a card: a bar drawn inside a stage has no status bar above it
  /// and no route behind it to go back to.
  final bool primary;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(AppBarMetrics.toolbarHeight);

  /// The calendar page's funnel: a badge counting the active filters on the
  /// glyph, out of the button's merged node. Null [onPressed] draws it
  /// disabled, never hidden.
  static Widget filterButton({
    required String identifier,
    required String tooltip,
    required int activeCount,
    required VoidCallback? onPressed,
  }) {
    return AutomationId(
      identifier: identifier,
      child: IconButton(
        tooltip: tooltip,
        isSelected: activeCount > 0,
        iconSize: AppBarMetrics.glyphSize,
        icon: ExcludeSemantics(
          child: Badge.count(
            count: activeCount,
            isLabelVisible: activeCount > 0,
            child: Icon(
              activeCount > 0
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
            ),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glyphs = IconThemeData(
      size: AppBarMetrics.glyphSize,
      color: colorScheme.onSurface,
    );
    return AppBar(
      primary: primary,
      automaticallyImplyLeading: automaticallyImplyLeading,
      titleSpacing: CalendarViewMenu.titleSpacing,
      excludeHeaderSemantics: true,
      title: CalendarViewMenu(
        page: CalendarViewPage.calendar,
        onPageSelected: onPageSelected,
        format: format,
        onFormatSelected: onFormatSelected,
        // The guide's own heading names the route; this title only quotes
        // the real calendar's.
        namesRoute: false,
      ),
      // The calendar page's bar, so the demo reads as the real thing.
      backgroundColor: colorScheme.surface,
      scrolledUnderElevation: 0,
      toolbarHeight: AppBarMetrics.toolbarHeight,
      iconTheme: glyphs,
      actionsIconTheme: glyphs,
      actions: [savedFiltersSlot, filterSlot, moreSlot],
    );
  }
}
