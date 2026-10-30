import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/calendar_panel_mode.dart';
import '../models/day_summary_entry.dart';
import '../services/day_summary_resolver.dart';
import '../utils/markdown_color_syntax.dart';
import 'agenda_day_list_rows.dart';
import 'agenda_list_view.dart';
import 'calendar_bottom_panel.dart';
import 'day_summary_panel.dart';
import 'day_timeline_view.dart';
import 'form_rows.dart';

/// The calendar's bottom panel — the mode bar over the Day, Timeline or
/// Upcoming body on the page ground — over a [GuideDemoCalendar].
///
/// The one copy of that wiring in the guide: the practice calendar draws it
/// with every tap live, and the screen page's panel card draws it with
/// none, so a change to the real panel's widgets reaches both at once
/// instead of drifting in copies (the owner's rule, D59). Every fact it
/// shows is read from the demo, never from the calendar's static caches,
/// which hold nothing for a demo event.
class GuideDemoPanel extends StatelessWidget {
  const GuideDemoPanel({
    super.key,
    required this.demo,
    required this.appearance,
    required this.palette,
    required this.summaryResolver,
    required this.onModeChanged,
    this.onEventTap,
    this.onToggleMissed,
    this.bottomClearance = FormMetrics.bodyBottom,
  });

  /// The air under the Upcoming list's last row: the add button's clearance
  /// on the practice page, where the button floats over the panel; a list's
  /// usual end on a card, which has no button.
  final double bottomClearance;

  final GuideDemoCalendar demo;
  final CalendarAppearance appearance;
  final MarkdownColorPalette palette;
  final DaySummaryResolver summaryResolver;
  final ValueChanged<CalendarPanelMode> onModeChanged;

  /// Null makes every row of every mode inert — the Day rows, the Timeline's
  /// blocks and chips, the Upcoming rows — with no tap in semantics: a stage
  /// that only shows the panel opens nothing from it. The mode bar stays
  /// live.
  final void Function(CalendarEvent event, DateTime day)? onEventTap;

  /// Null drops the Day panel's presence button.
  final void Function(CalendarEvent event, DateTime day, bool missed)?
  onToggleMissed;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.pageGround,
      child: Column(
        children: [
          PanelModeBar(
            mode: demo.panelMode,
            onChanged: onModeChanged,
            onTouched: () {},
            // The demo panel never covers the grid: the grid is what the
            // page is for.
            expanded: false,
            onToggleExpanded: null,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: RepaintBoundary(
                child: _body(AppLocalizations.of(context)!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<CalendarEvent> _panelEvents(DateTime day) =>
      demo.filters.panelShowsAll ? demo.allEventsFor(day) : demo.eventsFor(day);

  Widget _body(AppLocalizations l10n) {
    final day = demo.selectedDay;
    final tap = onEventTap;
    final toggle = onToggleMissed;
    switch (demo.panelMode) {
      case CalendarPanelMode.day:
        return DaySummaryPanel(
          day: day,
          entries: _dayEntries(day),
          onEventTap: tap == null ? null : (event) => tap(event, day),
          onToggleMissed: toggle == null
              ? null
              : (event, missed) => toggle(event, day, missed),
          colorPalette: palette,
        );
      case CalendarPanelMode.timeline:
        return DayTimelineView(
          day: day,
          events: _panelEvents(day),
          onEventTap: tap == null ? null : (event) => tap(event, day),
          missedDisplay: appearance.missedDisplay,
          isMissed: demo.isMissed,
        );
      case CalendarPanelMode.upcoming:
        return _upcoming(l10n);
    }
  }

  /// The day's entries with each one's presence and description read from
  /// the demo's own marks and rows: the shared resolver reads the real
  /// calendar's caches, which hold nothing for a demo event.
  List<DaySummaryEntry> _dayEntries(DateTime day) {
    final entries = summaryResolver.resolve(day, _panelEvents(day));
    return [
      for (final entry in entries)
        if (entry.event case final event?)
          DaySummaryEntry(
            key: entry.key,
            icon: entry.icon,
            color: entry.color,
            stripeAccent: entry.stripeAccent,
            title: entry.title,
            subtitle: entry.subtitle,
            description: _rowDescription(demo.descriptionFor(event, day)),
            priority: entry.priority,
            event: event,
            presenceTracked: entry.presenceTracked,
            missed: entry.presenceTracked && demo.isMissed(event, day),
          )
        else
          entry,
    ];
  }

  /// The resolver's rule for a row: trimmed, and a blank day shows none.
  static String? _rowDescription(String? raw) {
    final trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// What is coming over the demo's next weeks, drawn by the overview's and
  /// the day list's row builder, with presence from the demo's marks.
  Widget _upcoming(AppLocalizations l10n) {
    final occurrences = demo.upcoming();
    // Converted with nothing dropped, so the entries stay index for index
    // with the occurrences; the missed display is applied below, from the
    // demo's marks.
    final converted = AgendaListView.eventDayEntries(
      occurrences,
      l10n,
      false,
      showRecurrenceLabels: appearance.showRecurrenceLabels,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    final hideMissed = appearance.missedDisplay == CalendarMissedDisplay.hidden;
    final byDay = <DateTime, List<AgendaDayListEntry>>{};
    for (var i = 0; i < occurrences.length; i++) {
      final occurrence = occurrences[i];
      final entry = converted[i];
      final missed =
          entry.presenceTracked &&
          demo.isMissed(occurrence.event, occurrence.day);
      if (hideMissed && missed) continue;
      (byDay[occurrence.day] ??= []).add(
        AgendaDayListEntry(
          day: entry.day,
          icon: entry.icon,
          color: entry.color,
          title: entry.title,
          subtitle: entry.subtitle,
          missed: missed,
          eventId: entry.eventId,
          presenceTracked: entry.presenceTracked,
        ),
      );
    }
    final rows = buildAgendaDayListRows(
      byDay.keys.toList(),
      (day) => byDay[day]!,
      groupByDay: true,
      withMonths: true,
      keptCountOf: (day) => byDay[day]!.where((e) => !e.missed).length,
    );
    final padding = EdgeInsets.fromLTRB(
      RowMetrics.groupInset,
      FormMetrics.bodyTop,
      RowMetrics.groupInset,
      bottomClearance,
    );
    if (rows.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          FormCaption(
            text: l10n.dayListEmptyRange,
            padding: FormMetrics.groupCaptionPadding,
          ),
        ],
      );
    }
    final tap = onEventTap;
    final builder = AgendaDayListRowBuilder(
      rows: rows,
      today: demo.today,
      onEntryTap: tap == null
          ? null
          : (entry) {
              final event = demo.byId(entry.eventId ?? '');
              if (event != null) tap(event, entry.day);
            },
    );
    return ListView.builder(
      padding: padding,
      itemCount: rows.length,
      itemBuilder: builder.build,
    );
  }
}
