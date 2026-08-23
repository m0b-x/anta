import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_panel_mode.dart';
import '../models/calendar_selection_source.dart';
import '../models/upcoming_agenda_filters.dart';
import '../services/day_summary_resolver.dart';
import '../services/settings_service.dart';
import '../utils/event_agenda.dart';
import '../utils/markdown_color_syntax.dart';
import 'day_summary_panel.dart';
import 'day_timeline_view.dart';
import 'upcoming_agenda_view.dart';

/// The calendar's bottom half: the mode switch plus the active panel
/// (day summary / timeline / upcoming agenda).
///
/// Owns the panel mode and the agenda filters — deliberately **below** the
/// page — so a keystroke in the agenda's search field rebuilds only this
/// subtree, never the `TableCalendar` grid above it (~42 custom day cells
/// per frame that a page-level `setState` would redraw for no reason).
/// Both are persisted here too, on change, and restored in [initState];
/// nothing on the settings page edits them, so the panel never needs the
/// page's reload-on-return path. Anything that *is* settings-editable —
/// the markdown colour palette — is passed down from the page instead,
/// which already re-resolves settings when it regains focus.
class CalendarBottomPanel extends StatefulWidget {
  final CalendarPageLoaded loaded;

  /// Whether the panel is currently expanded over the calendar grid. Owned
  /// by the page (it controls the grid's visibility); the panel only renders
  /// the toggle.
  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Edits an event, carrying **which occurrence** the tap came from so the
  /// editor can offer "this day" vs "all days" (v24). Day and timeline modes
  /// supply the selected day; the agenda supplies the row's own day.
  final void Function(CalendarEvent event, DateTime day) onEditEvent;

  /// Opens an event read-only for a specific day. Used by the day panel's row
  /// tap; the agenda keeps its own affordances (tap = jump to the day, pencil
  /// = edit). The day is required because a recurring event's description can
  /// now differ per occurrence.
  final void Function(CalendarEvent event, DateTime day) onShowEvent;

  /// Opens the linked note. Deliberately still day-less — a note link belongs
  /// to the event, not to one of its occurrences.
  final ValueChanged<CalendarEvent> onOpenNote;
  final ValueChanged<DateTime> onSuppressHoliday;

  /// Marks or un-marks one occurrence of a presence-tracking event. Bound
  /// with the selected day here, the same way [onShowEvent] gets its day —
  /// `DaySummaryPanel` itself stays deliberately day-less.
  final void Function(CalendarEvent event, DateTime day, bool missed)
  onToggleMissed;

  /// Palette for `{name:text}` runs inside event descriptions. Owned by the
  /// page (which already re-resolves settings when returning from them)
  /// rather than loaded here a second time — the panel's own settings load
  /// happens once in `initState` and would go stale after an edit.
  final MarkdownColorPalette colorPalette;

  /// Whether event-row subtitles mention the repeat pattern. Owned by the
  /// page for the same staleness reason as [colorPalette]: it is edited on
  /// the settings page, and the page already re-resolves settings on return.
  final bool showRecurrenceLabels;

  /// How missed occurrences render. Owned by the page for the same staleness
  /// reason as [showRecurrenceLabels].
  final CalendarMissedDisplay missedDisplay;

  const CalendarBottomPanel({
    super.key,
    required this.loaded,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEditEvent,
    required this.onShowEvent,
    required this.onOpenNote,
    required this.onSuppressHoliday,
    required this.onToggleMissed,
    required this.colorPalette,
    this.showRecurrenceLabels = true,
    this.missedDisplay = CalendarMissedDisplay.faded,
  });

  @override
  State<CalendarBottomPanel> createState() => _CalendarBottomPanelState();
}

class _CalendarBottomPanelState extends State<CalendarBottomPanel> {
  CalendarPanelMode _mode = CalendarPanelMode.day;
  UpcomingAgendaFilters _filters = const UpcomingAgendaFilters();

  /// Where the upcoming agenda's look-ahead window starts.
  ///
  /// Owned here rather than read straight off `selectedDay`, because the
  /// selection and the window are two different things: an agenda row tap must
  /// move the grid without truncating the list it was tapped in, and with
  /// `followSelectedDay` off a grid tap must not move the window at all.
  /// Deliberately not persisted — the panel opens on today, as the grid does.
  late DateTime _agendaAnchor = EventAgenda.dateOnly(DateTime.now());

  /// Debounce for persisting the agenda's search text. Discrete filter
  /// choices write through immediately; only per-keystroke text waits.
  Timer? _queryPersistTimer;
  static const Duration _queryPersistDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CalendarBottomPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnchor(previous: oldWidget.loaded);
  }

  /// Moves [_agendaAnchor] to match the current selection, when it should.
  ///
  /// Assigns without `setState`: every caller runs immediately before a build
  /// (`didUpdateWidget`, or inside one of the setState blocks below), so a
  /// second frame would be pure waste.
  ///
  /// Rules, in order:
  ///  * with following off the window belongs to today — which also picks up a
  ///    date rollover on the next rebuild, the same freshness the
  ///    Today/Tomorrow row headers have;
  ///  * with no [previous] the caller is resolving from scratch (filters
  ///    loaded, or the toggle just flipped on), so adopt the selection as it
  ///    stands;
  ///  * an [CalendarSelectionSource.agendaRow] selection never re-anchors, so
  ///    tapping a row cannot drop every row above it;
  ///  * anything else follows the selection when it actually changed.
  void _syncAnchor({CalendarPageLoaded? previous}) {
    if (!_filters.followSelectedDay) {
      _agendaAnchor = EventAgenda.dateOnly(DateTime.now());
      return;
    }
    final loaded = widget.loaded;
    if (previous == null) {
      _agendaAnchor = loaded.selectedDay;
      return;
    }
    if (loaded.selectionSource == CalendarSelectionSource.agendaRow) return;
    if (previous.selectedDay == loaded.selectedDay) return;
    _agendaAnchor = loaded.selectedDay;
  }

  /// Returns the window to today, from the agenda header's anchor chip.
  void _resetAnchor() {
    setState(() => _agendaAnchor = EventAgenda.dateOnly(DateTime.now()));
  }

  @override
  void dispose() {
    _flushPendingPersist();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await SettingsService.getInstance();
    final mode = await settings.getCalendarPanelMode();
    final filters = await settings.getUpcomingAgendaFilters();
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _mode = mode;
      _filters = filters.withoutElapsedRange(
        DateTime.utc(now.year, now.month, now.day),
      );
      // The restored filters decide whether the window follows the selection,
      // so the anchor can only be resolved once they are in.
      _syncAnchor();
    });
  }

  Future<void> _setMode(CalendarPanelMode mode) async {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(mode);
  }

  /// Applies an agenda filter change and persists it.
  ///
  /// A change that only moved the search text is debounced, so typing does
  /// not write a settings row per keystroke; anything else (chips, range,
  /// the filter toggle) flushes immediately and carries the current query
  /// with it.
  void _onFiltersChanged(UpcomingAgendaFilters next) {
    final queryOnly =
        next.copyWith(query: _filters.query) == _filters &&
        next.query != _filters.query;
    final followingChanged =
        next.followSelectedDay != _filters.followSelectedDay;
    setState(() {
      _filters = next;
      // Turning following off returns the window to today; turning it on
      // adopts the current selection immediately rather than waiting for the
      // next tap.
      if (followingChanged) _syncAnchor();
    });
    _queryPersistTimer?.cancel();
    if (queryOnly) {
      _queryPersistTimer = Timer(_queryPersistDelay, () => _persist(next));
      return;
    }
    _persist(next);
  }

  /// If a debounced query write is still pending, cancel the timer and
  /// persist now — leaving the calendar within the debounce window must not
  /// lose the search. Fire-and-forget: dispose cannot await.
  void _flushPendingPersist() {
    final timer = _queryPersistTimer;
    if (timer == null || !timer.isActive) return;
    timer.cancel();
    _persist(_filters);
  }

  Future<void> _persist(UpcomingAgendaFilters filters) async {
    final settings = await SettingsService.getInstance();
    await settings.saveUpcomingAgendaFilters(filters);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PanelModeBar(
          mode: _mode,
          onChanged: _setMode,
          expanded: widget.expanded,
          onToggleExpanded: widget.onToggleExpanded,
        ),
        // SafeArea keeps the panel's content above the device's system
        // navigation bar (gesture pill / 3-button bar) — without it the
        // last rows render underneath and can't be tapped.
        Expanded(child: SafeArea(top: false, child: _buildPanel(context))),
      ],
    );
  }

  /// Builds the active panel. Day and timeline both render the selected day
  /// through the bloc's memoized `eventsForDay`; upcoming works off the
  /// whole event list and does its own range scan.
  Widget _buildPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loaded = widget.loaded;
    final bloc = context.read<CalendarBloc>();
    switch (_mode) {
      case CalendarPanelMode.day:
        final entries = DaySummaryResolver.defaults(
          l10n,
          showRecurrence: widget.showRecurrenceLabels,
        ).resolve(loaded.selectedDay, bloc.eventsForDay(loaded.selectedDay));
        return DaySummaryPanel(
          day: loaded.selectedDay,
          entries: entries,
          // The panel renders exactly one day, so the occurrence is known
          // here — DaySummaryPanel itself stays day-less.
          onEventTap: (event) => widget.onShowEvent(event, loaded.selectedDay),
          onOpenNote: widget.onOpenNote,
          onSuppressHoliday: () => widget.onSuppressHoliday(loaded.selectedDay),
          onToggleMissed: (event, missed) =>
              widget.onToggleMissed(event, loaded.selectedDay, missed),
          colorPalette: widget.colorPalette,
        );
      case CalendarPanelMode.timeline:
        return DayTimelineView(
          day: loaded.selectedDay,
          events: bloc.eventsForDay(loaded.selectedDay),
          // Same tap semantics as the day panel: show first, edit from
          // there. Both render the same day's events, so they must agree.
          onEventTap: (event) => widget.onShowEvent(event, loaded.selectedDay),
          missedDisplay: widget.missedDisplay,
        );
      case CalendarPanelMode.upcoming:
        return UpcomingAgendaView(
          events: loaded.allEvents,
          anchorDay: _agendaAnchor,
          onResetAnchor: _resetAnchor,
          hiddenCategoryIds: loaded.hiddenCategoryIds,
          filters: _filters,
          onFiltersChanged: _onFiltersChanged,
          // Tagged so the anchor sync can tell this apart from a grid tap: it
          // moves the selection (the grid and the day panel follow) but never
          // the agenda's own window.
          onDaySelected: (day) => bloc.add(
            SelectCalendarDay(
              day: day,
              focusedDay: day,
              source: CalendarSelectionSource.agendaRow,
            ),
          ),
          onEditEvent: widget.onEditEvent,
          onOpenNote: widget.onOpenNote,
          colorPalette: widget.colorPalette,
          showRecurrenceLabels: widget.showRecurrenceLabels,
          occurrenceRevision: loaded.occurrenceRevision,
          membershipRevision: loaded.membershipRevision,
          missedDisplay: widget.missedDisplay,
        );
    }
  }
}

/// Compact switch selecting what the bottom panel shows, plus the toggle
/// that expands the panel over the calendar grid. Sits between the grid and
/// the panel so the panel's own header stays free for the mode's content.
class _PanelModeBar extends StatelessWidget {
  final CalendarPanelMode mode;
  final ValueChanged<CalendarPanelMode> onChanged;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const _PanelModeBar({
    required this.mode,
    required this.onChanged,
    required this.expanded,
    required this.onToggleExpanded,
  });

  String _labelFor(AppLocalizations l10n, CalendarPanelMode mode) {
    return switch (mode) {
      CalendarPanelMode.day => l10n.panelModeDay,
      CalendarPanelMode.timeline => l10n.panelModeTimeline,
      CalendarPanelMode.upcoming => l10n.upcomingEvents,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<CalendarPanelMode>(
              segments: [
                // Labels only: three icon+label segments overflow a narrow
                // phone once the labels are translated.
                for (final value in CalendarPanelMode.values)
                  ButtonSegment<CalendarPanelMode>(
                    value: value,
                    label: Text(
                      _labelFor(l10n, value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {mode},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
          IconButton(
            tooltip: expanded ? l10n.panelShowCalendar : l10n.panelExpand,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
            ),
            onPressed: onToggleExpanded,
          ),
        ],
      ),
    );
  }
}
