import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_bar_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_panel_mode.dart';
import 'calendar_bottom_panel.dart';
import 'calendar_guide_try_card.dart';
import 'calendar_header_menus.dart';

/// The screen page's card: the calendar's bar — its title menu and its ⋮ —
/// over the panel's mode switch, the real widgets each, with nothing under
/// them. A pick changes the demo and moves the coach line on.
class GuideScreenDemo extends GuideCardDemo {
  GuideScreenDemo() : super(CalendarGuideTopic.screen);

  static const String slug = 'screen';

  CalendarFormat _format = CalendarFormat.month;
  CalendarPanelMode _mode = CalendarPanelMode.day;

  void _setFormat(CalendarFormat format) {
    _format = format;
    did('title');
  }

  void _setMode(CalendarPanelMode mode) {
    _mode = mode;
    did('panel');
  }

  /// Any row of the ⋮: none opens anything here.
  void _more() => did('more');

  @override
  Widget buildStage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The calendar page's bar, in the bar's own type and glyph sizes.
        SizedBox(
          height: AppBarMetrics.toolbarHeight,
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: AppBarMetrics.titleFontSize,
              fontWeight: AppBarMetrics.titleFontWeight,
              color: colorScheme.onSurface,
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                size: AppBarMetrics.glyphSize,
                color: colorScheme.onSurface,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: CalendarViewMenu(
                        page: CalendarViewPage.calendar,
                        onPageSelected: (_) => did('title'),
                        format: _format,
                        onFormatSelected: _setFormat,
                        // The page's heading names the route; this title
                        // only quotes the real calendar's.
                        namesRoute: false,
                      ),
                    ),
                  ),
                  CalendarOverflowMenu(
                    identifier: SemanticsIds.calendarGuideTryControl(
                      slug,
                      'more',
                    ),
                    onAlerts: _more,
                    onExport: _more,
                    onGuide: _more,
                    onSettings: _more,
                  ),
                ],
              ),
            ),
          ),
        ),
        PanelModeBar(
          mode: _mode,
          onChanged: _setMode,
          onTouched: () {},
          expanded: false,
          // Disabled, never hidden: there is no grid here to cover.
          onToggleExpanded: null,
        ),
      ],
    );
  }
}
