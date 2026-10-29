import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_bar_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_panel_mode.dart';
import 'calendar_bottom_panel.dart';
import 'calendar_guide_try_card.dart';
import 'calendar_header_menus.dart';

/// The screen page's card: the calendar's bar — its title menu and its ⋮ —
/// over the panel's mode switch, the real widgets each, with nothing under
/// them. A pick changes the demo and the caption says what the real
/// calendar would have done.
class GuideScreenDemo extends GuideCardDemo {
  static const String slug = 'screen';

  CalendarFormat _format = CalendarFormat.month;
  CalendarPanelMode _mode = CalendarPanelMode.day;

  static String _formatLabel(AppLocalizations l10n, CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
  }

  static String _modeCaption(AppLocalizations l10n, CalendarPanelMode mode) {
    return switch (mode) {
      CalendarPanelMode.day => l10n.calendarGuideDemoPanelDay(
        l10n.panelModeDay,
      ),
      CalendarPanelMode.timeline => l10n.calendarGuideDemoPanelTimeline(
        l10n.panelModeTimeline,
      ),
      CalendarPanelMode.upcoming => l10n.calendarGuideDemoPanelUpcoming(
        l10n.upcomingEvents,
      ),
    };
  }

  @override
  String idle(AppLocalizations l10n) =>
      l10n.calendarGuideDemoFormat(l10n.calendarFormatMonth);

  @override
  List<String> candidates(AppLocalizations l10n) => [
    for (final format in CalendarFormat.values)
      l10n.calendarGuideDemoFormat(_formatLabel(l10n, format)),
    for (final mode in CalendarPanelMode.values) _modeCaption(l10n, mode),
    for (final what in [
      l10n.calendarOverview,
      l10n.alertsTitle,
      l10n.calendarSettingsRow,
    ])
      l10n.calendarGuideWouldOpen(what),
    l10n.calendarGuideWouldShare,
    l10n.calendarGuideYouAreHere,
  ];

  void _setFormat(CalendarFormat format) {
    _format = format;
    say((l10n) => l10n.calendarGuideDemoFormat(_formatLabel(l10n, format)));
  }

  void _setMode(CalendarPanelMode mode) {
    _mode = mode;
    say((l10n) => _modeCaption(l10n, mode));
  }

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
                        onPageSelected: (_) => say(
                          (l10n) =>
                              l10n.calendarGuideWouldOpen(l10n.calendarOverview),
                        ),
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
                    onAlerts: () => say(
                      (l10n) => l10n.calendarGuideWouldOpen(l10n.alertsTitle),
                    ),
                    onExport: () => say((l10n) => l10n.calendarGuideWouldShare),
                    onGuide: () => say((l10n) => l10n.calendarGuideYouAreHere),
                    onSettings: () => say(
                      (l10n) =>
                          l10n.calendarGuideWouldOpen(l10n.calendarSettingsRow),
                    ),
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
