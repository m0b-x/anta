import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list_mode.dart';
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

/// How many times the panel's mode bar has measured its labels.
///
/// The measurement is three `TextPainter.layout()` calls and it sits on the
/// day-tap path; neither budget suite watches that path, so the count is the
/// only way a test can say the memo still holds.
@visibleForTesting
int panelModeFitMeasurements = 0;

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
  /// supply the selected day; the agenda supplies the row's own day. The event
  /// is **named**: the page resolves the id against its unfiltered list.
  final void Function(String eventId, DateTime day) onEditEvent;

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

  /// Calendar look & feel, forwarded to the agenda so a summary card's
  /// drill-down can render its mini month on the same grid the page does.
  /// Owned by the page for the same staleness reason as [colorPalette].
  final CalendarAppearance appearance;

  const CalendarBottomPanel({
    super.key,
    required this.loaded,
    required this.appearance,
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

  /// Which presentation a summary card's drill-down opens in. Panel state for
  /// the same reason the filters are: the sheet is opened from inside this
  /// subtree, and nothing on the settings page edits it.
  AgendaDayListMode _dayListMode = AgendaDayListMode.list;

  /// The app's haptic setting, read with the panel's own settings and handed
  /// to the drill-down for its year and month jumps.
  bool _hapticFeedback = false;

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

  /// Whether the user has set the value since [initState], so the restore in
  /// [_load] — several settings reads, up to ~1.5 s on a cold start — never
  /// snaps a fresh pick back to the stored one.
  bool _modePicked = false;
  bool _filtersPicked = false;
  bool _dayListModePicked = false;

  /// Whether [_load] has applied the stored agenda filters. A change before
  /// that was made on the defaults and is not written: the write would
  /// replace the stored categories, range and query with defaults the user
  /// never chose. The restore replays it on the stored value instead
  /// ([_replayOnto]) and writes the result.
  bool _filtersRestored = false;

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
    final dayListMode = await settings.getAgendaDayListMode();
    final haptics = await settings.getHapticFeedback();
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      if (!_modePicked) _mode = mode;
      if (!_dayListModePicked) _dayListMode = dayListMode;
      _hapticFeedback = haptics;
      final stored = filters.withoutElapsedRange(
        DateTime.utc(now.year, now.month, now.day),
      );
      _filters = _filtersPicked
          ? _replayOnto(stored, picked: _filters)
          : stored;
      _filtersRestored = true;
      // The restored filters decide whether the window follows the selection,
      // so the anchor can only be resolved once they are in.
      _syncAnchor();
    });
    // A pick the restore yielded to may never have been written — a tap on
    // the shown segment writes nothing, an early filter change waited for
    // this — so the stored values follow what the panel now shows.
    if (_modePicked && _mode != mode) {
      unawaited(settings.setCalendarPanelMode(_mode));
    }
    if (_dayListModePicked && _dayListMode != dayListMode) {
      _persistDayListMode(_dayListMode);
    }
    if (_filtersPicked) _persist(_filters);
  }

  /// [stored] with every field the user changed before the restore landed
  /// taken from [picked]. Those changes were made on the defaults, so a field
  /// still at its default was not touched and the stored value stands; the
  /// custom range moves as one pair.
  static UpcomingAgendaFilters _replayOnto(
    UpcomingAgendaFilters stored, {
    required UpcomingAgendaFilters picked,
  }) {
    const base = UpcomingAgendaFilters();
    T pick<T>(T Function(UpcomingAgendaFilters filters) field) =>
        field(picked) == field(base) ? field(stored) : field(picked);
    Set<E> pickSet<E>(Set<E> Function(UpcomingAgendaFilters filters) field) =>
        setEquals(field(picked), field(base)) ? field(stored) : field(picked);
    final range =
        picked.customStart != base.customStart ||
            picked.customEnd != base.customEnd
        ? picked
        : stored;
    return UpcomingAgendaFilters(
      periodMode: pick((f) => f.periodMode),
      rangeDays: pick((f) => f.rangeDays),
      priorities: pickSet((f) => f.priorities),
      customStart: range.customStart,
      customEnd: range.customEnd,
      query: pick((f) => f.query),
      showHolidays: pick((f) => f.showHolidays),
      showFasting: pick((f) => f.showFasting),
      eventDisplay: pick((f) => f.eventDisplay),
      fastingDisplay: pick((f) => f.fastingDisplay),
      holidayDisplay: pick((f) => f.holidayDisplay),
      followSelectedDay: pick((f) => f.followSelectedDay),
      eventType: pick((f) => f.eventType),
      categoryIds: pickSet((f) => f.categoryIds),
    );
  }

  Future<void> _setMode(CalendarPanelMode mode) async {
    _modePicked = true;
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
    _filtersPicked = true;
    setState(() {
      _filters = next;
      // Turning following off returns the window to today; turning it on
      // adopts the current selection immediately rather than waiting for the
      // next tap.
      if (followingChanged) _syncAnchor();
    });
    _queryPersistTimer?.cancel();
    if (!_filtersRestored) return;
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

  /// Remembers the presentation a summary card's drill-down was left in. The
  /// sheet is still open when this runs, so the write is fire-and-forget like
  /// the filter writes above.
  void _onDayListModeChanged(AgendaDayListMode mode) {
    _dayListModePicked = true;
    if (mode == _dayListMode) return;
    setState(() => _dayListMode = mode);
    _persistDayListMode(mode);
  }

  Future<void> _persistDayListMode(AgendaDayListMode mode) async {
    final settings = await SettingsService.getInstance();
    await settings.setAgendaDayListMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    // The panel sits on the browser's page ground and its cards on the
    // browser's row-group tone (`SurfaceRoles`), which is what separates a
    // day card from the page in light — on plain `surface` the card's
    // default fill was one tone away and barely read. The grid above keeps
    // `surface`, so in light it reads as a sheet over the panel; in dark the
    // ground *is* `surface` and only the cards lift.
    return ColoredBox(
      color: Theme.of(context).colorScheme.pageGround,
      child: Column(
        children: [
          _PanelModeBar(
            mode: _mode,
            onChanged: _setMode,
            onTouched: () => _modePicked = true,
            expanded: widget.expanded,
            onToggleExpanded: widget.onToggleExpanded,
          ),
          // SafeArea keeps the panel's content above the device's system
          // navigation bar (gesture pill / 3-button bar) — without it the
          // last rows render underneath and can't be tapped.
          Expanded(child: SafeArea(top: false, child: _buildPanel(context))),
        ],
      ),
    );
  }

  /// Memoized day-summary resolver, mirroring the grid's own memo in
  /// `_CalendarViewState._resolverFor` — **4.3**. `DaySummaryResolver.defaults`
  /// allocates five stateless providers, and it was being called from `build`,
  /// so every panel rebuild (a day tap, a presence tick, a scroll-driven
  /// notifier that happens to dirty this subtree) threw the previous five away.
  /// Its providers depend only on the localization and the recurrence-label
  /// setting, both of which change far less often than the panel rebuilds.
  DaySummaryResolver? _summaryResolver;
  AppLocalizations? _summaryL10n;
  bool? _summaryShowRecurrence;

  /// The filter's three annotation layers, which compose the resolver's
  /// provider list and are therefore part of its memo key.
  ({bool holidays, bool fasting, bool money})? _summaryLayers;

  DaySummaryResolver _summaryResolverFor(AppLocalizations l10n) {
    final showRecurrence = widget.showRecurrenceLabels;
    final filters = widget.loaded.filters;
    final layers = (
      holidays: filters.showHolidays,
      fasting: filters.showFasting,
      money: filters.showMoney,
    );
    if (_summaryResolver == null ||
        _summaryL10n != l10n ||
        _summaryShowRecurrence != showRecurrence ||
        _summaryLayers != layers) {
      _summaryResolver = DaySummaryResolver.defaults(
        l10n,
        showRecurrence: showRecurrence,
        showHolidays: layers.holidays,
        showFasting: layers.fasting,
        showMoney: layers.money,
      );
      _summaryL10n = l10n;
      _summaryShowRecurrence = showRecurrence;
      _summaryLayers = layers;
    }
    return _summaryResolver!;
  }

  /// The selected day's events for the day and timeline panels — the filtered
  /// set, unless the user has asked the panels to keep showing the whole day.
  ///
  /// Both panels render the same day, so both must ask the same question: a
  /// timeline showing an event the day list omits would be the two disagreeing
  /// about what is on the day.
  List<CalendarEvent> _panelEvents(CalendarBloc bloc, DateTime day) =>
      widget.loaded.filters.panelShowsAll
      ? bloc.allEventsForDay(day)
      : bloc.eventsForDay(day);

  /// Builds the active panel. Day and timeline both render the selected day
  /// through the bloc's memoized `eventsForDay`; upcoming works off the
  /// whole event list and does its own range scan.
  Widget _buildPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loaded = widget.loaded;
    final bloc = context.read<CalendarBloc>();
    switch (_mode) {
      case CalendarPanelMode.day:
        final entries = _summaryResolverFor(
          l10n,
        ).resolve(loaded.selectedDay, _panelEvents(bloc, loaded.selectedDay));
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
          events: _panelEvents(bloc, loaded.selectedDay),
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
          hiddenCategoryIds: loaded.filters.hiddenCategoryIds,
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
          appearance: widget.appearance,
          dayListMode: _dayListMode,
          onDayListModeChanged: _onDayListModeChanged,
          occurrenceRevision: loaded.occurrenceRevision,
          membershipRevision: loaded.membershipRevision,
          missedDisplay: widget.missedDisplay,
          hapticFeedback: _hapticFeedback,
        );
    }
  }
}

/// Compact switch selecting what the bottom panel shows, plus the toggle
/// that expands the panel over the calendar grid. Sits between the grid and
/// the panel so the panel's own header stays free for the mode's content.
///
/// The three labelled segments share the row while every label fits its
/// third; from the text scale where one would not (German from about 1.1:
/// "Demnächst"), each segment shows only its icon and keeps the mode's name
/// as its tooltip and semantics label. Never a scrolling row: a scrolled bar
/// hid a mode off screen and slid under the finger on every switch.
class _PanelModeBar extends StatelessWidget {
  final CalendarPanelMode mode;
  final ValueChanged<CalendarPanelMode> onChanged;

  /// Called on every touch of a segment, the shown one included: the
  /// segmented button reports only a change of selection, while before the
  /// panel's restore lands a tap on the shown segment is a choice too.
  final VoidCallback onTouched;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const _PanelModeBar({
    required this.mode,
    required this.onChanged,
    required this.onTouched,
    required this.expanded,
    required this.onToggleExpanded,
  });

  /// Room left so a label measured to fit exactly is not cut by the
  /// engine's own rounding.
  static const double _fitMargin = 0.5;

  String _labelFor(AppLocalizations l10n, CalendarPanelMode mode) {
    return switch (mode) {
      CalendarPanelMode.day => l10n.panelModeDay,
      CalendarPanelMode.timeline => l10n.panelModeTimeline,
      CalendarPanelMode.upcoming => l10n.upcomingEvents,
    };
  }

  static IconData _iconFor(CalendarPanelMode mode) {
    return switch (mode) {
      CalendarPanelMode.day => Icons.today_outlined,
      CalendarPanelMode.timeline => Icons.view_timeline_outlined,
      CalendarPanelMode.upcoming => Icons.upcoming_outlined,
    };
  }

  /// The last [_labelsFit] answer, with the inputs it was measured on.
  ///
  /// The bar is rebuilt on every day tap, presence tick and description tick —
  /// the panel's `buildWhen` watches the selection — and a measurement is
  /// three `TextSpan` allocations and three `TextPainter.layout()` calls on
  /// that path. The answer can only move with the row's width, the text
  /// scaler, the locale or the label style, so it is kept for as long as those
  /// hold. One entry: a panel shows one bar, and a width or scale change
  /// replaces the question rather than adding one. The direction is in the key
  /// because the measurement resolves the button padding with it — latent
  /// while every locale is LTR, wrong the day one is not.
  static ({
    double width,
    TextScaler scaler,
    String locale,
    TextStyle? style,
    TextDirection direction,
  })?
  _fitInputs;
  static bool _fitAnswer = false;

  /// [_labelsFit] for the build path: measured once per set of inputs.
  bool _labelsFitCached(
    BuildContext context,
    AppLocalizations l10n,
    Iterable<String> labels,
    double width,
  ) {
    final inputs = (
      width: width,
      scaler: MediaQuery.textScalerOf(context),
      locale: l10n.localeName,
      style: Theme.of(context).textTheme.labelLarge,
      direction: Directionality.of(context),
    );
    if (inputs == _fitInputs) return _fitAnswer;
    _fitInputs = inputs;
    return _fitAnswer = _labelsFit(context, labels, width);
  }

  /// Whether every label fits its third of [width] on one line, measured as
  /// a label-only segment draws it: the theme's `labelLarge` under the
  /// current scaler, inside the text button padding Material scales with the
  /// text size (12 → 8 → 4 dp a side over scale 1 → 2 → 3).
  bool _labelsFit(BuildContext context, Iterable<String> labels, double width) {
    panelModeFitMeasurements++;
    final style = Theme.of(context).textTheme.labelLarge;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final padding = ButtonStyleButton.scaledPadding(
      const EdgeInsets.symmetric(horizontal: 12),
      const EdgeInsets.symmetric(horizontal: 8),
      const EdgeInsets.symmetric(horizontal: 4),
      textScaler.scale(style?.fontSize ?? 14) / 14,
    ).resolve(direction);
    final room = width / labels.length - padding.horizontal;
    final painter = TextPainter(
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
    );
    try {
      for (final label in labels) {
        painter
          ..text = TextSpan(text: label, style: style)
          ..layout();
        if (painter.width + _fitMargin > room) return false;
      }
      return true;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const insets = EdgeInsets.fromLTRB(16, 8, 8, 0);
    final labels = {
      for (final value in CalendarPanelMode.values)
        value: _labelFor(l10n, value),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        // The segments get the row less its insets and the compact expand
        // button beside them.
        final expandExtent =
            kMinInteractiveDimension +
            VisualDensity.compact.baseSizeAdjustment.dx;
        final iconsOnly = !_labelsFitCached(
          context,
          l10n,
          labels.values,
          constraints.maxWidth - insets.horizontal - expandExtent,
        );
        return Padding(
          // An icon segment's 48 dp target takes the top inset, so the bar
          // keeps the labelled bar's height and the panel under it does not
          // move when the segments switch.
          padding: iconsOnly ? insets.copyWith(top: 0) : insets,
          child: Row(
            children: [
              Expanded(
                child: Listener(
                  onPointerDown: (_) => onTouched(),
                  child: SegmentedButton<CalendarPanelMode>(
                    segments: [
                      // Labels only while they fit: three icon+label segments
                      // overflow a narrow phone once the labels are
                      // translated.
                      for (final value in CalendarPanelMode.values)
                        ButtonSegment<CalendarPanelMode>(
                          value: value,
                          tooltip: iconsOnly ? labels[value] : null,
                          // A segment takes no id of its own; its child's
                          // merges into the segment's node.
                          label: iconsOnly
                              ? null
                              : Semantics(
                                  identifier: SemanticsIds.panelMode(
                                    value.name,
                                  ),
                                  child: Text(
                                    labels[value]!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          icon: iconsOnly
                              ? Semantics(
                                  identifier: SemanticsIds.panelMode(
                                    value.name,
                                  ),
                                  label: labels[value],
                                  child: Icon(_iconFor(value)),
                                )
                              : null,
                        ),
                    ],
                    selected: {mode},
                    showSelectedIcon: false,
                    // The icon segments are reached at large text, where a
                    // 48 dp target matters most; the labelled ones keep the
                    // compact row the panel was laid out on.
                    style: iconsOnly
                        ? const ButtonStyle(
                            visualDensity: VisualDensity.standard,
                            tapTargetSize: MaterialTapTargetSize.padded,
                          )
                        : const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                    onSelectionChanged: (selection) =>
                        onChanged(selection.first),
                  ),
                ),
              ),
              IconButton(
                tooltip: expanded ? l10n.panelShowCalendar : l10n.panelExpand,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
                onPressed: onToggleExpanded,
              ),
            ],
          ),
        );
      },
    );
  }
}
