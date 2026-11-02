import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_bar_metrics.dart';
import 'automation_id.dart';
import 'calendar_header_menus.dart';

/// A calendar view's bar over a guide demo: the title as the view menu, then
/// the view's actions, in the real bars' sizes and colours.
///
/// The one copy of those bars in the guide: the practice page draws it as
/// its own bar with its controls live, and the screen page's stage draws
/// each view's on its stage, so a change to how the calendar's bar is built
/// reaches both (the owner's rule, D59). The callers fill the actions;
/// [filterButton] is the funnel both draw.
class GuideCalendarBar extends StatelessWidget implements PreferredSizeWidget {
  const GuideCalendarBar({
    super.key,
    required this.page,
    required this.onPageSelected,
    required this.actions,
    required this.backgroundColor,
    this.format,
    this.onFormatSelected,
    this.primary = true,
    this.automaticallyImplyLeading = true,
  });

  /// The view the bar sits on: the title names it and the menu checks it.
  final CalendarViewPage page;

  final ValueChanged<CalendarViewPage> onPageSelected;

  /// Null leaves the menu's formats out, as the overview's and the report's
  /// bars do: only the calendar has a grid to reshape.
  final CalendarFormat? format;

  /// Null draws the formats disabled: the practice page before its demo has
  /// loaded.
  final ValueChanged<CalendarFormat>? onFormatSelected;

  final List<Widget> actions;

  /// The view's own page's: `surface` over the calendar, `pageGround` over
  /// the overview and the report (D79).
  final Color backgroundColor;

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
        page: page,
        onPageSelected: onPageSelected,
        format: format,
        onFormatSelected: onFormatSelected,
        // The guide's own heading names the route; this title only quotes
        // the real calendar's.
        namesRoute: false,
      ),
      backgroundColor: backgroundColor,
      scrolledUnderElevation: 0,
      toolbarHeight: AppBarMetrics.toolbarHeight,
      iconTheme: glyphs,
      actionsIconTheme: glyphs,
      actions: actions,
    );
  }
}
