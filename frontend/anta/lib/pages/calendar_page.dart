import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:table_calendar/table_calendar.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/import_export/import_export_state.dart';
import '../constants/app_icon_sizes.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_templates.dart';
import '../constants/calendar_weekend.dart';
import '../constants/event_skips.dart';
import '../constants/fasting_calendar.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_grid_filters.dart';
import '../models/calendar_event.dart';
import '../models/calendar_selection_source.dart';
import '../models/day_bar.dart';
import '../models/day_cell_tint.dart';
import '../models/day_rail_mark.dart';
import '../models/recurrence_rule.dart';
import '../repositories/note_repository.dart';
import '../services/app_navigator.dart';
import '../services/cell_tint_resolver.dart';
import '../services/day_bars_resolver.dart';
import '../services/day_rail_resolver.dart';
import '../services/note_money_ledger_service.dart';
import '../services/public_holiday_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/event_agenda.dart';
import '../utils/keyboard_inset_tracker.dart';
import '../utils/markdown_color_syntax.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/calendar_add_fab.dart';
import '../widgets/calendar_bottom_panel.dart';
import '../widgets/calendar_day_bars.dart';
import '../widgets/calendar_day_cell.dart';
import '../widgets/calendar_filter_chips.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/filter_preset_sheet.dart';
import '../widgets/event_description_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/event_template_picker_sheet.dart';
import '../widgets/keyboard_coupled_size.dart';
import '../widgets/month_year_picker_sheet.dart';

/// Overflow-menu actions on the calendar app bar.
enum _CalendarMenuAction { exportIcs }

/// Days in the grid window [gridDaysForMonth] returns — a fixed six-week
/// span, always a superset of what [TableCalendar] actually shows for one
/// month (4-6 rows depending on the month and week-start), so a prewarm can
/// never miss a day the real page paints.
@visibleForTesting
const int prewarmGridDayCount = 42;

/// Months either side of the focused one that [_CalendarViewState] warms —
/// radius 1, deliberately inside `CalendarBloc`'s radius-3 eviction window.
const List<int> _prewarmMonthOffsets = [-1, 1];

/// Maps the app's week-start setting onto `table_calendar`'s enum. Shared by
/// [_CalendarTable]'s grid and [_CalendarViewState]'s neighbour-month
/// prewarm so the two can never disagree on a month's first visible day.
@visibleForTesting
StartingDayOfWeek startingDayOfWeekFor(CalendarWeekStart weekStart) {
  return switch (weekStart) {
    CalendarWeekStart.monday => StartingDayOfWeek.monday,
    CalendarWeekStart.saturday => StartingDayOfWeek.saturday,
    CalendarWeekStart.sunday => StartingDayOfWeek.sunday,
  };
}

/// The [prewarmGridDayCount]-day window `table_calendar`'s `PageView` pages
/// to for [monthAnchor] — same first-visible-day arithmetic as
/// `CalendarCore._getDaysBefore` (a pub.dev package, not forked; this is a
/// standalone reimplementation of a few lines of ISO-weekday math, not a call
/// into it). A fixed 42-day span from the correct start is always a superset
/// of the real page, whatever its row count.
@visibleForTesting
List<DateTime> gridDaysForMonth(
  DateTime monthAnchor,
  StartingDayOfWeek startingDayOfWeek,
) {
  final firstOfMonth = DateTime.utc(monthAnchor.year, monthAnchor.month);
  final startWeekdayNumber =
      StartingDayOfWeek.values.indexOf(startingDayOfWeek) + 1;
  final daysBefore = (firstOfMonth.weekday + 7 - startWeekdayNumber) % 7;
  final firstVisible = firstOfMonth.subtract(Duration(days: daysBefore));
  return [
    for (var i = 0; i < prewarmGridDayCount; i++)
      firstVisible.add(Duration(days: i)),
  ];
}

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CalendarView();
  }
}

class _CalendarView extends StatefulWidget {
  const _CalendarView();

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> with RouteAware {
  CalendarAppearance _appearance = const CalendarAppearance();

  /// Resolved markdown palette, so an event's description renders with the
  /// user's custom colours in the detail sheet.
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  /// Whether the bottom panel is expanded over the calendar grid. Transient
  /// on purpose: restoring a hidden calendar across app opens would read as
  /// "the calendar disappeared", so every visit starts with the grid shown.
  bool _panelExpanded = false;

  /// Whether the persisted filter set has been pushed into the bloc. See
  /// [_loadSettings] for why this is once-only.
  bool _filtersRestored = false;

  /// Whether the add button shows its day label. Driven by the panel's scroll
  /// through a notifier rather than `setState`, because the only widget that
  /// cares is the button: a page-level rebuild on every scroll tick would
  /// dirty the 42-cell grid and the whole bottom panel, which is exactly what
  /// their `sameGridInputs` / `samePanelInputs` gates exist to avoid.
  final ValueNotifier<bool> _fabExtended = ValueNotifier(true);

  /// Raw bottom view inset, republished once per keyboard animation frame.
  final ValueNotifier<double> _keyboardInset = ValueNotifier(0);

  /// Whether the grid renders as a single week. Flips on as the keyboard
  /// starts to open and off on the first frame it starts to close, so the
  /// grid gives space back while the keyboard is still sliding away.
  final ValueNotifier<bool> _gridCollapsed = ValueNotifier(false);

  /// Progress of the keyboard's own animation, or null when it is not
  /// animating and [KeyboardCoupledSize] should run its own tween.
  final ValueNotifier<double?> _collapseProgress = ValueNotifier(null);

  final KeyboardInsetTracker _insetTracker = KeyboardInsetTracker();

  /// Memoized day-bar resolver. Its providers are stateless and depend only
  /// on the localization and the missed-display setting, both of which change
  /// far less often than the grid rebuilds.
  DayBarsResolver? _barsResolver;
  AppLocalizations? _barsL10n;
  CalendarMissedDisplay? _barsMissedDisplay;

  bool? _barsRailActive;

  /// The three layer flags the bar/tint/summary resolvers are composed from.
  /// A record so one comparison covers all three in every memo key.
  ({bool holidays, bool fasting, bool money})? _barsLayers;

  static ({bool holidays, bool fasting, bool money}) _layersOf(
    CalendarGridFilters filters,
  ) => (
    holidays: filters.showHolidays,
    fasting: filters.showFasting,
    money: filters.showMoney,
  );

  DayBarsResolver _resolverFor(AppLocalizations l10n, CalendarGridFilters f) {
    final missed = _appearance.missedDisplay;
    // A rail event is excluded from the bottom strip, but only while the rail
    // renders — turning the rail off must never silently drop events from the
    // grid — so the style is part of how the bars resolver is built, and
    // therefore part of its memo key. The layer flags are in it for the same
    // reason: they decide which providers exist.
    final railActive = _railStyle != DayRailStyle.none;
    final layers = _layersOf(f);
    if (_barsResolver == null ||
        _barsL10n != l10n ||
        _barsMissedDisplay != missed ||
        _barsRailActive != railActive ||
        _barsLayers != layers) {
      _barsResolver = DayBarsResolver.defaults(
        l10n,
        missedDisplay: missed,
        railActive: railActive,
        showHolidays: layers.holidays,
        showFasting: layers.fasting,
        showMoney: layers.money,
      );
      _barsL10n = l10n;
      _barsMissedDisplay = missed;
      _barsRailActive = railActive;
      _barsLayers = layers;
    }
    return _barsResolver!;
  }

  DayRailStyle get _railStyle => _appearance.dayRailStyle;

  int get _maxRailMarks => _appearance.maxDayRailMarks;

  /// Memoized rail resolver, on the same terms as [_resolverFor]: its one
  /// provider is stateless and reads only the localization and the
  /// missed-display setting. Rail *style* and *max* are paint-side widget
  /// parameters, deliberately not resolver inputs, so neither one reaches
  /// this memo key.
  ///
  /// That is not the same as saying they never clear [_railOutputCache]: both
  /// live in `CalendarAppearance.props`, so with `eventTint` on — the branch
  /// where `CellTintResolver.defaults` allocates rather than returning a
  /// canonicalized `const` — changing the rail's max rebuilds the *tint*
  /// resolver, which is part of the generation record, and all three caches
  /// clear together. One extra recompute on a settings return; not a
  /// correctness problem, and not an invariant to rely on.
  DayRailResolver? _railResolver;
  AppLocalizations? _railL10n;
  CalendarMissedDisplay? _railMissedDisplay;

  DayRailResolver _railResolverFor(AppLocalizations l10n) {
    final missed = _appearance.missedDisplay;
    if (_railResolver == null ||
        _railL10n != l10n ||
        _railMissedDisplay != missed) {
      _railResolver = DayRailResolver.defaults(l10n, missedDisplay: missed);
      _railL10n = l10n;
      _railMissedDisplay = missed;
    }
    return _railResolver!;
  }

  /// Memoized cell-wash resolver, rebuilt only when the appearance or the
  /// fasting layer changes — the wash has no holiday or money source, so the
  /// other two flags are not inputs here.
  CellTintResolver? _tintResolver;
  CalendarAppearance? _tintAppearance;
  bool? _tintShowFasting;

  CellTintResolver _cellTintResolverFor(CalendarGridFilters filters) {
    final showFasting = filters.showFasting;
    if (_tintResolver == null ||
        _tintAppearance != _appearance ||
        _tintShowFasting != showFasting) {
      _tintResolver = CellTintResolver.defaults(
        _appearance,
        showFasting: showFasting,
      );
      _tintAppearance = _appearance;
      _tintShowFasting = showFasting;
    }
    return _tintResolver!;
  }

  /// Per-day memo of resolver **output** — `_resolverFor`/`_cellTintResolver`
  /// above only memoize the resolver *instances*, so a rebuild that changes
  /// nothing they read (a day tap, a format toggle — both ride
  /// `sameGridInputs` for other reasons) still re-ran `.resolve()` for all 42
  /// cells. Cleared wholesale whenever [_outputGeneration] no longer matches
  /// — see [_syncResolverOutputCache].
  final Map<DateTime, List<DayBar>> _barsOutputCache = {};
  final Map<DateTime, DayCellTint> _tintOutputCache = {};
  final Map<DateTime, List<DayRailMark>> _railOutputCache = {};

  /// Generation the three output caches above were last built against, or
  /// `null` before the first grid build.
  ///
  /// One int folding every input a cell's bars/tint can depend on —
  /// recomputed here, once per grid build (never once per cell) — so a
  /// rebuild whose cause is not one of these inputs (day selection, a format
  /// toggle, an unrelated settings-return rebuild) reuses every cached entry,
  /// and one that is drops the whole memo and starts over. Mirrors
  /// `CalendarBloc._syncHolidayGeneration`'s shape: a generation drops a
  /// cache, it never keys one — composing a tuple key per cell instead would
  /// grow the map on every facade tick rather than clearing it.
  ///
  /// `occurrenceRevision` is deliberately absent: no grid resolver reads
  /// `OccurrenceDescriptions`, only the day/timeline panel does
  /// (`EventSummaryProvider`). `selectedDay`/`focusedDay`/`format` are also
  /// absent — none of them is read by `DayBarsResolver`/`CellTintResolver` —
  /// which is exactly what lets a day tap or a month page reuse this memo
  /// instead of invalidating it.
  /// A record, not an `Object.hash` fold: a hash is a *probabilistically*
  /// incomplete key, and the whole failure this memo must not have is a cell
  /// left stale because its inputs changed without the key noticing. Records
  /// compare field by field, and `List`/`Set`/the two resolvers all inherit
  /// identity `==`, so this matches the identity semantics `sameGridInputs`
  /// already relies on while being exact.
  ({
    Object allEvents,
    Object filters,
    int membershipRevision,
    int presenceRevision,
    int holidayRevision,
    int categoryRevision,
    int fastingRevision,
    int? ledgerRevision,
    Object barsResolver,
    Object tintResolver,
    Object railResolver,
  })?
  _outputGeneration;

  void _syncResolverOutputCache(
    CalendarPageLoaded state,
    DayBarsResolver barsResolver,
    CellTintResolver tintResolver,
    DayRailResolver railResolver,
  ) {
    final generation = (
      allEvents: state.allEvents,
      filters: state.filters,
      membershipRevision: state.membershipRevision,
      presenceRevision: state.presenceRevision,
      holidayRevision: PublicHolidays.revision,
      categoryRevision: CalendarCategories.revision,
      fastingRevision: FastingCalendar.revision,
      ledgerRevision: NoteMoneyLedgerService.instanceOrNull?.revision,
      barsResolver: barsResolver,
      tintResolver: tintResolver,
      railResolver: railResolver,
    );
    if (_outputGeneration == generation) return;
    _outputGeneration = generation;
    _barsOutputCache.clear();
    _tintOutputCache.clear();
    _railOutputCache.clear();
  }

  @override
  void initState() {
    super.initState();
    _keyboardInset.addListener(_handleKeyboardInset);
    _loadSettings();
  }

  /// Folds one keyboard animation frame into the format decision and the
  /// grid's height driver. Neither notifier rebuilds this page: the format
  /// flip rebuilds the grid subtree alone, and the progress goes straight to
  /// a render object.
  void _handleKeyboardInset() {
    _insetTracker.update(_keyboardInset.value);
    _collapseProgress.value = _insetTracker.progress;
    _gridCollapsed.value = _insetTracker.collapsed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
    _reloadIfStale();
  }

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    _fabExtended.dispose();
    _keyboardInset.removeListener(_handleKeyboardInset);
    _keyboardInset.dispose();
    _gridCollapsed.dispose();
    _collapseProgress.dispose();
    super.dispose();
  }

  /// Called when a route pushed above the calendar is popped.
  ///
  /// `RouteObserver<PageRoute>` only fires between two page routes, so the
  /// editor, detail, filter and picker sheets — all `PopupRoute`s — do not
  /// reach here. Settings, backup and database pages do.
  @override
  void didPopNext() {
    _loadSettings();
    _reloadIfStale();
  }

  /// Re-reads the event store when it was replaced underneath the bloc.
  ///
  /// `CalendarBloc` lives above `MaterialApp` and is never disposed, so a
  /// backup restore or a database switch leaves it holding events from a store
  /// that no longer exists — and because the day cache is dropped by the
  /// holiday generation check, the result is stale data freshly recomputed
  /// rather than an obvious blank. Gated on the revision so an ordinary
  /// drawer-open of the calendar does not pay for a reload.
  void _reloadIfStale() {
    final bloc = context.read<CalendarBloc>();
    if (bloc.isStale) bloc.add(const LoadCalendarEvents());
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    // One statement, not sixteen sequential single-row reads: every await here
    // is a separate round trip to the drift isolate, so their latencies add,
    // and resolving appearance after the first frame visibly re-lays-out the
    // grid.
    final loaded = await settings.getCalendarPageSettings();
    if (!mounted) return;
    // Static sync facade, mirroring PublicHolidays: configure() is a no-op
    // when unchanged, so the reload-on-settings-return path stays cheap.
    FastingCalendar.configure(
      traditions: loaded.fastingTraditions,
      appearance: loaded.fastingAppearance,
      orthodoxGreatFasts: loaded.fastingGreatFasts,
      schedule: loaded.fastingSchedule,
    );
    // Restored **once**, on the first load only. `_loadSettings` also runs on
    // every settings return, and re-applying the stored set there would race
    // an in-session change whose write has not landed yet — undoing a chip the
    // user just removed. The bloc records the filters even while it is still
    // `CalendarPageInitial`, so this can fire before the first load finishes.
    if (!_filtersRestored) {
      _filtersRestored = true;
      if (!loaded.filters.isEmpty || loaded.filters.panelShowsAll) {
        context.read<CalendarBloc>().add(
          ChangeCalendarFilters(filters: loaded.filters),
        );
      }
    }
    setState(() {
      _appearance = loaded.appearance;
      _colorPalette = loaded.palette;
    });
  }

  /// The one funnel for a filter change: the bloc renders it, and it is
  /// written back so the next app open sees it. Every surface that can change
  /// a filter — the sheet's Apply and each summary chip's `x` — goes through
  /// here, or the two would drift.
  void _applyFilters(BuildContext context, CalendarGridFilters filters) {
    context.read<CalendarBloc>().add(ChangeCalendarFilters(filters: filters));
    unawaited(_persistFilters(filters));
  }

  Future<void> _persistFilters(CalendarGridFilters filters) async {
    try {
      final settings = await SettingsService.getInstance();
      await settings.setCalendarGridFilters(filters);
    } catch (e) {
      // A preference that failed to save is not worth interrupting the user
      // over: the filter is already applied, it just will not survive a
      // restart.
      debugPrint('[CalendarPage] Filter persist failed: $e');
    }
  }

  /// Shows an event read-only first, then routes whatever the user chose
  /// there. Tapping a day-panel row used to drop straight into the edit form;
  /// now that descriptions are real content, the first thing a tap does is
  /// show them.
  ///
  /// Ticking a description checkbox there rewrites the description in place,
  /// so [current] tracks the latest version and the routed actions carry it —
  /// otherwise "edit" would reopen the form on the pre-tick text. A
  /// per-occurrence tick never touches [current]: it writes one day's row,
  /// leaving the event (and its template) exactly as it was.
  ///
  /// Editing re-enters rather than ending the trip: saving the form or backing
  /// out of it returns here, and so does a quick description edit. The three
  /// exits are the ones where reopening would describe something that is no
  /// longer there or in the way — opening the linked note (a full page), a
  /// delete, and a skip (the occurrence stops existing) — plus dismissing the
  /// sheet itself.
  Future<void> _openDetailSheet(
    BuildContext context,
    CalendarEvent event,
    DateTime day,
  ) async {
    final bloc = context.read<CalendarBloc>();
    var current = event;
    // The occurrence write is dispatched, not awaited, and the sheet pops in
    // the same turn — so the next sheet can mount before it lands. Carry the
    // text forward rather than letting it race the database.
    String? pendingOccurrence;
    while (true) {
      // Every path back to the top of the loop already checks, but the check
      // has to be here for the analyzer to see it across the back edge.
      if (!context.mounted) return;
      final action = await EventDetailSheet.show(
        context,
        event: current,
        day: day,
        colorPalette: _colorPalette,
        pendingOccurrenceDescription: pendingOccurrence,
        onEventChanged: (updated) {
          current = updated;
          bloc.add(UpdateCalendarEvent(event: updated));
        },
        onOccurrenceChanged: (occurrenceDay, description) {
          pendingOccurrence = description;
          bloc.add(
            SetOccurrenceDescription(
              eventId: current.id,
              day: occurrenceDay,
              description: description,
            ),
          );
        },
        onPresenceChanged: (occurrenceDay, missed) =>
            _setOccurrenceMissed(bloc, current.id, occurrenceDay, missed),
      );
      if (action == null || !context.mounted) return;
      switch (action) {
        case EventDetailAction.openNote:
          await _openLinkedNote(context, current);
          return;
        case EventDetailAction.skipOccurrence:
          _skipOccurrence(context, bloc, current.id, day);
          return;
        case EventDetailAction.editDescription:
          final edited = await _quickEditDescription(
            context,
            bloc,
            current,
            day,
            pendingOccurrence,
          );
          current = edited.event;
          pendingOccurrence = edited.pending;
          if (!context.mounted) return;
        case EventDetailAction.edit:
          final result = await _openEditorSheet(
            context,
            initialEvent: current,
            occurrenceDay: day,
            pendingOccurrenceDescription: pendingOccurrence,
            showBack: true,
          );
          if (!context.mounted) return;
          var reopen = false;
          switch (result) {
            case null:
            case EventEditorDeleted():
              break;
            case EventEditorBack():
              reopen = true;
            case EventEditorSaved():
              current = result.event;
              pendingOccurrence = _pendingAfterSave(
                result,
                current,
                day,
                pendingOccurrence,
              );
              reopen = _occurrenceSurvives(result, current, day);
          }
          if (!reopen) return;
      }
    }
  }

  /// What this day's text is after the editor saved, for the detail sheet the
  /// loop is about to reopen.
  ///
  /// Three cases the facade cannot answer in time: the event stopped
  /// separating its days (rows go dormant, the template governs again), the
  /// day's row was **deleted** by a reset (`occurrenceDescription` null against
  /// a non-null day), so the day now follows the template, or it was written.
  /// A null day means the editor left the table alone, and any text carried in
  /// from a checkbox tick still stands.
  static String? _pendingAfterSave(
    EventEditorSaved result,
    CalendarEvent saved,
    DateTime day,
    String? previous,
  ) {
    if (!OccurrenceDescriptions.appliesTo(saved)) return null;
    if (result.occurrenceDay != day) return previous;
    return result.occurrenceDescription ?? saved.description ?? '';
  }

  /// Whether [day] still has an occurrence to show after the save. The form
  /// can move the date, change the rule, pull in the end date, or cancel this
  /// very day in its skip picker — reopening the sheet on any of those would
  /// describe an occurrence that no longer exists.
  ///
  /// The skip set is read from the result rather than from `EventSkips`: it is
  /// dispatched asynchronously, so the facade may not carry it yet.
  static bool _occurrenceSurvives(
    EventEditorSaved result,
    CalendarEvent saved,
    DateTime day,
  ) {
    if (result.skippedDays?.contains(day) ?? false) return false;
    return saved.occursOn(day);
  }

  /// Edits one description from the detail sheet, without the form.
  ///
  /// Writes exactly where a checkbox tick writes — no scope picker, so the two
  /// can never disagree about which text they are editing. A per-occurrence
  /// event therefore edits *this day* here and its template only in the full
  /// editor, which is what the caption says out loud.
  Future<({CalendarEvent event, String? pending})> _quickEditDescription(
    BuildContext context,
    CalendarBloc bloc,
    CalendarEvent event,
    DateTime day,
    String? pending,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final unchanged = (event: event, pending: pending);
    final perOccurrence = OccurrenceDescriptions.appliesTo(event);
    // Seeded from the raw text, never the detail sheet's trimmed render: a
    // Done with no edits must be able to compare equal below.
    final seed = perOccurrence
        ? (pending ?? OccurrenceDescriptions.descriptionFor(event, day) ?? '')
        : (event.description ?? '');
    final settings = await SettingsService.getInstance();
    final limit = await settings.getEventDescriptionLimit();
    if (!context.mounted) return unchanged;
    final edited = await EventDescriptionSheet.show(
      context,
      initialText: seed,
      heading: event.title,
      limit: limit,
      grandfatheredLength: seed.length,
      scopeCaption: perOccurrence
          ? l10n.eventDescriptionScopeThisDayHint
          : (event.rule is OneTimeRecurrence
                ? null
                : l10n.eventDescriptionAppliesAllOccurrences),
      colorPalette: _colorPalette,
    );
    // An unchanged Done must not write. On a day with no row of its own it
    // would materialise one identical to the template, forking that day from
    // the template forever; on the event it would bump the version and the
    // HLC for nothing.
    if (edited == null || edited == seed) return unchanged;
    if (perOccurrence) {
      // Empty is a deliberately blanked day, not a reset: the day stays
      // exactly as the user left it. Returning to the template is what the
      // editor's "reset this day" is for.
      bloc.add(
        SetOccurrenceDescription(
          eventId: event.id,
          day: day,
          description: edited,
        ),
      );
      return (event: event, pending: edited);
    }
    final updated = event.copyWith(
      description: edited,
      clearDescription: edited.isEmpty,
    );
    bloc.add(UpdateCalendarEvent(event: updated));
    return (event: updated, pending: pending);
  }

  /// Cancels one occurrence, with an undo. Routed through the page rather
  /// than written from the sheet so every skip — this one and the editor's
  /// bulk picker — lands on the same path.
  void _skipOccurrence(
    BuildContext context,
    CalendarBloc bloc,
    String eventId,
    DateTime day,
  ) {
    final l10n = AppLocalizations.of(context)!;
    bloc.add(SetOccurrenceSkipped(eventId: eventId, day: day));
    CustomSnackbar.showWithAction(
      context,
      message: l10n.eventOccurrenceSkipped,
      actionLabel: l10n.undo,
      onAction: () =>
          bloc.add(ClearOccurrenceSkipped(eventId: eventId, day: day)),
    );
  }

  /// Narrow projections of the bloc state, one per app-bar/FAB `buildWhen`.
  ///
  /// Each of those builders renders a single icon or button that depends on
  /// one bit of the state; without a `buildWhen` they all rebuilt on every
  /// emission, including the occurrence and presence ticks that only concern
  /// the day panel.
  static bool _isLoaded(CalendarPageState state) => state is CalendarPageLoaded;

  /// How many filters are narrowing the grid — the app-bar badge's count, and
  /// the signal its `buildWhen` watches. Zero means the icon shows unfilled
  /// and no chip row is mounted.
  static int _activeFilterCount(CalendarPageState state) =>
      state is CalendarPageLoaded ? state.filters.activeCount : 0;

  static bool _hasEvents(CalendarPageState state) =>
      state is CalendarPageLoaded && state.allEvents.isNotEmpty;

  static DateTime? _selectedDayOf(CalendarPageState state) =>
      state is CalendarPageLoaded ? state.selectedDay : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l10n.calendar),
        actions: [
          // Saved filters sit **left of** the filter button, in reading order:
          // you reach for a filter you already have before you build a new
          // one. It has no badge — a saved filter is not itself a restriction,
          // and a second count beside the filter badge would only compete
          // with it.
          BlocBuilder<CalendarBloc, CalendarPageState>(
            buildWhen: (previous, current) =>
                _isLoaded(previous) != _isLoaded(current),
            builder: (context, state) {
              return IconButton(
                tooltip: l10n.filterPresetsTitle,
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: !_isLoaded(state)
                    ? null
                    : () {
                        // Read at press time: this buildWhen tracks only
                        // whether the page has loaded, so a captured state
                        // would carry stale filters.
                        final current = context.read<CalendarBloc>().state;
                        if (current is! CalendarPageLoaded) return;
                        _openPresetSheet(context, current);
                      },
              );
            },
          ),
          BlocBuilder<CalendarBloc, CalendarPageState>(
            buildWhen: (previous, current) =>
                _isLoaded(previous) != _isLoaded(current) ||
                _activeFilterCount(previous) != _activeFilterCount(current),
            builder: (context, state) {
              final isLoaded = _isLoaded(state);
              final active = _activeFilterCount(state);
              return Badge.count(
                count: active,
                isLabelVisible: active > 0,
                child: IconButton(
                  tooltip: l10n.filterCalendar,
                  isSelected: active > 0,
                  icon: Icon(
                    active > 0
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                  ),
                  onPressed: !isLoaded
                      ? null
                      : () {
                          // Read at press time, not from the builder's state:
                          // this buildWhen ignores `format`, which the sheet
                          // needs, so a captured state could be stale.
                          final current = context.read<CalendarBloc>().state;
                          if (current is! CalendarPageLoaded) return;
                          _openFilterSheet(context, current);
                        },
                ),
              );
            },
          ),
          IconButton(
            tooltip: l10n.calendarSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
          BlocBuilder<CalendarBloc, CalendarPageState>(
            buildWhen: (previous, current) =>
                _hasEvents(previous) != _hasEvents(current),
            builder: (context, state) {
              final hasEvents = _hasEvents(state);
              return PopupMenuButton<_CalendarMenuAction>(
                onSelected: (action) {
                  // Read at selection time: this buildWhen only tracks
                  // whether the list is empty, so a captured state could
                  // carry a stale event list.
                  final current = context.read<CalendarBloc>().state;
                  if (current is! CalendarPageLoaded) return;
                  switch (action) {
                    case _CalendarMenuAction.exportIcs:
                      _exportCalendar(context, current);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<_CalendarMenuAction>(
                    value: _CalendarMenuAction.exportIcs,
                    enabled: hasEvents,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.ios_share_rounded),
                      title: Text(l10n.exportEventsIcs),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      // Three nested builders rather than one. The outer switches between
      // loading/error/loaded and so only rebuilds when that changes; the grid
      // and the panel then subscribe separately, because the panel needs
      // every emission while the grid needs none of the occurrence-description
      // ticks the panel generates. Each half sits under its own
      // RepaintBoundary so a panel repaint cannot dirty the 42-cell grid's
      // layer.
      // Catches scrolls from whichever panel mode is mounted, so the add
      // button's collapse needs no plumbing through the panel. `fabExtendedFor`
      // owns the rules — notably that horizontal scrollables (the agenda's
      // chip row, the timeline's hour track) are ignored.
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          final extended = fabExtendedFor(notification);
          if (extended != null) _fabExtended.value = extended;
          // Never swallow it: the panel's own scroll machinery listens too.
          return false;
        },
        child: BlocBuilder<CalendarBloc, CalendarPageState>(
          buildWhen: (previous, current) =>
              previous.runtimeType != current.runtimeType ||
              (previous is CalendarPageError &&
                  current is CalendarPageError &&
                  previous.message != current.message),
          builder: (context, state) {
            if (state is CalendarPageLoading || state is CalendarPageInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is CalendarPageError) {
              return Center(child: Text(state.message));
            }
            return Column(
              children: [
                // Its own builder, gated on the filter set alone: the row is
                // mounted only while something is being hidden, and neither
                // the grid nor the panel rebuilds when a chip is removed —
                // that reaches them through the bloc, as any other filter
                // change does. The grid's height is fixed (rows are sized
                // from the cell metrics, not from what is left over), so the
                // row costs the bottom panel a few pixels and shifts nothing
                // above it.
                BlocBuilder<CalendarBloc, CalendarPageState>(
                  buildWhen: (previous, current) =>
                      previous is! CalendarPageLoaded ||
                      current is! CalendarPageLoaded ||
                      !identical(previous.filters, current.filters),
                  builder: (context, state) {
                    if (state is! CalendarPageLoaded) {
                      return const SizedBox.shrink();
                    }
                    return CalendarFilterChips(
                      filters: state.filters,
                      onChanged: (filters) => _applyFilters(context, filters),
                      // Read at press time for the same reason the app-bar
                      // button does: this buildWhen ignores `format`, which
                      // the sheet needs.
                      onOpenFilters: () {
                        final current = context.read<CalendarBloc>().state;
                        if (current is! CalendarPageLoaded) return;
                        _openFilterSheet(context, current);
                      },
                    );
                  },
                ),
                // AnimatedSize collapses the grid to zero height when the
                // panel is expanded — the grid keeps its own state either way
                // and no manual layout math is involved.
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _panelExpanded
                      ? const SizedBox(width: double.infinity)
                      : RepaintBoundary(
                          child: KeyboardCoupledSize(
                            progress: _collapseProgress,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _gridCollapsed,
                              builder: (context, keyboardVisible, _) =>
                                  BlocBuilder<CalendarBloc, CalendarPageState>(
                                    buildWhen: (previous, current) =>
                                        previous is! CalendarPageLoaded ||
                                        current is! CalendarPageLoaded ||
                                        !previous.sameGridInputs(current),
                                    builder: (context, state) {
                                      if (state is! CalendarPageLoaded) {
                                        return const SizedBox(
                                          width: double.infinity,
                                        );
                                      }
                                      final barsResolver = _resolverFor(l10n, state.filters);
                                      final tintResolver = _cellTintResolverFor(
                                          state.filters,
                                        );
                                      final railResolver = _railResolverFor(
                                        l10n,
                                      );
                                      _syncResolverOutputCache(
                                        state,
                                        barsResolver,
                                        tintResolver,
                                        railResolver,
                                      );
                                      return _CalendarTable(
                                        state: state,
                                        format: keyboardVisible
                                            ? CalendarFormat.week
                                            : state.format,
                                        formatLocked: keyboardVisible,
                                        appearance: _appearance,
                                        barsResolver: barsResolver,
                                        tintResolver: tintResolver,
                                        railResolver: railResolver,
                                        railStyle: _railStyle,
                                        railBasePosition:
                                            _appearance.dayRailBasePosition,
                                        maxRailMarks: _maxRailMarks,
                                        barsOutputCache: _barsOutputCache,
                                        tintOutputCache: _tintOutputCache,
                                        railOutputCache: _railOutputCache,
                                        onDayLongPressed: (day) =>
                                            _quickAddFromTemplate(context, day),
                                      );
                                    },
                                  ),
                            ),
                          ),
                        ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: RepaintBoundary(
                    child: BlocBuilder<CalendarBloc, CalendarPageState>(
                      // The panel ignores focus/format, so month paging and a
                      // format toggle must not rebuild it — that is what used to
                      // re-run the agenda scan on every grid page turn.
                      buildWhen: (previous, current) =>
                          previous is! CalendarPageLoaded ||
                          current is! CalendarPageLoaded ||
                          !previous.samePanelInputs(current),
                      builder: (context, state) {
                        if (state is! CalendarPageLoaded) {
                          return const SizedBox.shrink();
                        }
                        return CalendarBottomPanel(
                          loaded: state,
                          expanded: _panelExpanded,
                          onToggleExpanded: () =>
                              setState(() => _panelExpanded = !_panelExpanded),
                          onEditEvent: (event, day) => _openEditorSheet(
                            context,
                            initialEvent: event,
                            occurrenceDay: day,
                          ),
                          onShowEvent: (event, day) =>
                              _openDetailSheet(context, event, day),
                          onOpenNote: (event) =>
                              _openLinkedNote(context, event),
                          colorPalette: _colorPalette,
                          showRecurrenceLabels:
                              _appearance.showRecurrenceLabels,
                          missedDisplay: _appearance.missedDisplay,
                          onSuppressHoliday: (day) =>
                              _removeHoliday(context, day),
                          onToggleMissed: (event, day, missed) =>
                              _setOccurrenceMissed(
                                context.read<CalendarBloc>(),
                                event.id,
                                day,
                                missed,
                              ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: BlocBuilder<CalendarBloc, CalendarPageState>(
        buildWhen: (previous, current) =>
            _selectedDayOf(previous) != _selectedDayOf(current),
        builder: (context, state) {
          return CalendarAddFab(
            // Inert until the calendar services have resolved. The editor
            // reads `CalendarCategories`, which stays empty until then, so an
            // early tap would open a picker showing no categories and default
            // the event to the `other` fallback.
            selectedDay: _selectedDayOf(state),
            appearance: _appearance,
            extended: _fabExtended,
            onPressed: (day) => _openEditorSheet(context, day: day),
          );
        },
      ),
    );

    // Export feedback and the neighbour-month prewarm each funnel through
    // their own listener: the first so the menu action only has to dispatch
    // (guarded on the calendar operation, since the bloc is app-wide and also
    // serves note/folder exports), the second so the grid never has to know
    // it is being kept warm.
    return MultiBlocListener(
      listeners: [
        BlocListener<ImportExportBloc, ImportExportState>(
          listener: _onImportExportState,
        ),
        BlocListener<CalendarBloc, CalendarPageState>(
          // Month-level, not day-level: the neighbours only move when the
          // focused month does, so a day tap inside the same month would
          // re-warm a window that is already warm.
          listenWhen: (previous, current) =>
              current is CalendarPageLoaded &&
              (previous is! CalendarPageLoaded ||
                  previous.focusedDay.year != current.focusedDay.year ||
                  previous.focusedDay.month != current.focusedDay.month),
          listener: (context, state) {
            if (state is CalendarPageLoaded) {
              _schedulePrewarm(state.focusedDay);
            }
          },
        ),
      ],
      child: _KeyboardInsetProbe(inset: _keyboardInset, child: scaffold),
    );
  }

  /// Hands the loaded event list to [ImportExportBloc] for `.ics` export.
  /// The share sheet (and the temp-file cleanup behind it) is the service's
  /// job — pages never touch `SharePlus` directly.
  void _exportCalendar(BuildContext context, CalendarPageLoaded state) {
    context.read<ImportExportBloc>().add(
      ExportCalendarRequested(events: state.allEvents, share: true),
    );
  }

  void _onImportExportState(BuildContext context, ImportExportState state) {
    final l10n = AppLocalizations.of(context)!;
    if (state is ImportExportFailure) {
      if (state.operation != ImportExportOperation.exportCalendar) return;
      CustomSnackbar.showError(
        context,
        '${l10n.eventsExportError}: ${state.message}',
      );
    } else if (state is ImportExportExportSuccess) {
      if (state.operation != ImportExportOperation.exportCalendar) return;
      CustomSnackbar.showSuccess(
        context,
        l10n.eventsExported(state.result.eventsExported),
      );
    } else {
      return;
    }
    context.read<ImportExportBloc>().add(const ImportExportReset());
  }

  /// Opens the event form. [occurrenceDay] is the day the user came from —
  /// only set when editing an existing event from a dated surface, which is
  /// what lets the sheet offer "this day" vs "all days". The FAB path leaves
  /// it null: a brand-new event has no occurrence yet.
  /// Long-press quick-add: pick a template, stamp it onto [day] immediately.
  ///
  /// Immediate creation is right *here specifically* because the two things
  /// that normally need confirming are already decided — the title is the
  /// template's name and the date is the day under the finger — so the whole
  /// interaction is press, tap, done. An undo action covers the mistake.
  ///
  /// With no templates yet, this falls through to the normal editor rather
  /// than showing an empty sheet: a long-press that appears to do nothing is
  /// worse than one that does the obvious thing.
  Future<void> _quickAddFromTemplate(BuildContext context, DateTime day) async {
    final normalized = DateTime.utc(day.year, day.month, day.day);
    if (CalendarTemplates.isEmpty) {
      await _openEditorSheet(context, day: normalized);
      return;
    }

    final choice = await EventTemplatePickerSheet.show(context);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case EventTemplateBlank():
        await _openEditorSheet(context, day: normalized);
      case EventTemplatePicked(:final template):
        final l10n = AppLocalizations.of(context)!;
        final bloc = context.read<CalendarBloc>();
        final event = template.buildEvent(
          id: const Uuid().v4(),
          startDate: normalized,
        );
        bloc.add(CreateCalendarEvent(event: event));
        // A rule can legitimately skip its own anchor (a weekly template whose
        // weekday set excludes the pressed day), so the confirmation names the
        // day it will actually land on rather than letting it look like
        // nothing happened.
        final firstDay = _firstOccurrenceOf(event, from: normalized);
        CustomSnackbar.showWithAction(
          context,
          message: firstDay == null || firstDay == normalized
              ? l10n.eventCreatedFromTemplate(event.title)
              : l10n.eventCreatedFromTemplateOn(
                  event.title,
                  DateFormat.MMMEd(l10n.localeName).format(firstDay),
                ),
          actionLabel: l10n.undo,
          onAction: () => bloc.add(DeleteCalendarEvent(eventId: event.id)),
        );
    }
  }

  /// First day at or after [from] that [event] occurs on, or `null` if it does
  /// not fire within the agenda's usual range. Bounded so a rule that never
  /// matches cannot spin.
  static DateTime? _firstOccurrenceOf(
    CalendarEvent event, {
    required DateTime from,
  }) {
    for (var i = 0; i < EventAgenda.maxRangeDays; i++) {
      final day = from.add(Duration(days: i));
      if (event.occursOn(day)) return day;
    }
    return null;
  }

  /// Opens the form and dispatches whatever it reports, then hands the result
  /// back so a caller that owns a sheet behind this one can decide what to do
  /// next. Every caller still gets the dispatch for free; only the detail
  /// sheet's loop reads the return value.
  Future<EventEditorResult?> _openEditorSheet(
    BuildContext context, {
    CalendarEvent? initialEvent,
    DateTime? day,
    DateTime? occurrenceDay,
    String? pendingOccurrenceDescription,
    bool showBack = false,
  }) async {
    // The bloc's per-day lookup is already memoized and O(1), so handing it
    // to the picker costs nothing and lets the grid show which days are
    // already busy while the user schedules.
    final eventsForDay = context.read<CalendarBloc>().eventsForDay;
    final result = await EventEditorSheet.show(
      context,
      defaultDate: initialEvent?.startDate ?? day ?? DateTime.now(),
      initialEvent: initialEvent,
      occurrenceDay: occurrenceDay,
      pendingOccurrenceDescription: pendingOccurrenceDescription,
      dayLoad: (day) => eventsForDay(day).length,
      appearance: _appearance,
      showBack: showBack,
    );
    if (result == null || !context.mounted) return result;
    final bloc = context.read<CalendarBloc>();
    switch (result) {
      case EventEditorSaved(:final event):
        if (initialEvent == null) {
          bloc.add(CreateCalendarEvent(event: event));
        } else {
          bloc.add(UpdateCalendarEvent(event: event));
        }
        // The event write lands first so a day override can never reference an
        // event the bloc has not seen yet.
        _dispatchOccurrenceResult(bloc, event.id, result);
      case EventEditorDeleted(:final id):
        bloc.add(DeleteCalendarEvent(eventId: id));
      // Nothing was decided, so there is nothing to write.
      case EventEditorBack():
        break;
    }
    return result;
  }

  /// Single funnel for presence marks, whichever surface produced them — the
  /// detail sheet's segmented control or the day panel's quick toggle. Both
  /// write through the bloc, which bumps `occurrenceRevision` and deliberately
  /// leaves the day cache warm: a missed occurrence still occurs.
  void _setOccurrenceMissed(
    CalendarBloc bloc,
    String eventId,
    DateTime day,
    bool missed,
  ) {
    bloc.add(
      missed
          ? SetOccurrenceMissed(eventId: eventId, day: day)
          : ClearOccurrenceMissed(eventId: eventId, day: day),
    );
  }

  /// Routes the editor's occurrence outcome. The sheet never writes; it
  /// reports what the user did and the page dispatches it, so persistence
  /// stays on one path.
  void _dispatchOccurrenceResult(
    CalendarBloc bloc,
    String eventId,
    EventEditorSaved result,
  ) {
    _dispatchSkipResult(bloc, eventId, result);
    final occurrenceDay = result.occurrenceDay;
    if (occurrenceDay == null) return;
    final description = result.occurrenceDescription;
    if (description == null) {
      bloc.add(
        ClearOccurrenceDescription(eventId: eventId, day: occurrenceDay),
      );
    } else {
      bloc.add(
        SetOccurrenceDescription(
          eventId: eventId,
          day: occurrenceDay,
          description: description,
        ),
      );
    }
  }

  /// Applies the editor's cancelled-days set as a diff against what is
  /// persisted, so an unchanged day costs no write and no version bump.
  ///
  /// A null set means the picker was never opened — leave the table alone.
  void _dispatchSkipResult(
    CalendarBloc bloc,
    String eventId,
    EventEditorSaved result,
  ) {
    final next = result.skippedDays;
    if (next == null) return;
    final current = EventSkips.daysFor(eventId);
    for (final day in next.difference(current)) {
      bloc.add(SetOccurrenceSkipped(eventId: eventId, day: day));
    }
    for (final day in current.difference(next)) {
      bloc.add(ClearOccurrenceSkipped(eventId: eventId, day: day));
    }
  }

  /// Open the workout note linked to [event]. The folder is resolved from
  /// the note at tap time (not stored on the event), so the link survives
  /// the note being moved. The note opens in the standard editor, which
  /// restores its own persisted view (code-editing or markdown preview).
  ///
  /// Uses [NoteRepository.getNotesByIds] (not `getNoteById`) because only it
  /// filters out soft-deleted notes, so a deleted linked note reads as
  /// missing and surfaces a non-blocking error instead of opening a ghost.
  Future<void> _openLinkedNote(
    BuildContext context,
    CalendarEvent event,
  ) async {
    final noteId = event.noteId;
    if (noteId == null) return;
    final l10n = AppLocalizations.of(context)!;
    final repository = GetIt.I<NoteRepository>();
    final notes = await repository.getNotesByIds([noteId]);
    if (!context.mounted) return;
    final note = notes.isEmpty ? null : notes.first;
    if (note == null) {
      CustomSnackbar.showError(context, l10n.eventLinkedNoteMissing);
      return;
    }
    // Pass the metadata mapped from the row we already fetched: the editor
    // seeds its title bar from it, so a metadata-less push showed
    // "New note" instead of the note's real title.
    AppNavigator.toNoteEditor(
      context,
      folderId: note.folderId,
      noteId: note.id,
      metadata: repository.noteToMetadata(note),
    );
  }

  /// Removes the public holiday resolved for [day] for this occurrence
  /// only, after a confirmation dialog. Built-in removals are reversible —
  /// either immediately via the snackbar's Undo action or later from the
  /// "Removed holidays" list in Calendar Settings — since suppressing a
  /// specific dated row (rather than deleting it) is exactly what makes
  /// the removal survive an app restart or a backup restore.
  Future<void> _removeHoliday(BuildContext context, DateTime day) async {
    final info = PublicHolidays.holidayOn(day);
    if (info == null) return;
    final l10n = AppLocalizations.of(context)!;
    final label = PublicHolidays.labelOf(info, l10n);
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.removeHoliday,
      content: l10n.removeHolidayConfirm(label),
      confirmText: l10n.removeHoliday,
      isDestructive: true,
      icon: Icons.celebration_rounded,
    );
    if (!confirmed || !context.mounted) return;

    final holidayService = await PublicHolidayService.getInstance();
    await holidayService.removeOn(day);
    if (!context.mounted) return;
    context.read<CalendarBloc>().add(const LoadCalendarEvents());

    final builtIn = info.builtIn;
    CustomSnackbar.showWithAction(
      context,
      message: l10n.holidayRemoved,
      actionLabel: l10n.undo,
      onAction: () async {
        if (builtIn != null) {
          await holidayService.restoreSuppressed(day, builtIn);
        } else {
          await holidayService.addCustom(day, info.customLabel ?? '');
        }
        if (!context.mounted) return;
        context.read<CalendarBloc>().add(const LoadCalendarEvents());
      },
    );
  }

  Future<void> _openFilterSheet(
    BuildContext context,
    CalendarPageLoaded state,
  ) async {
    final result = await CalendarFilterSheet.show(
      context,
      format: state.format,
      filters: state.filters,
    );
    if (result == null || !context.mounted) return;
    if (result.format != state.format) {
      context.read<CalendarBloc>().add(
        ChangeCalendarFormat(format: result.format),
      );
    }
    _applyFilters(context, result.filters);
  }

  /// Opens the saved-filter list. Applying one goes through the same
  /// [_applyFilters] funnel a sheet Apply does, so a preset is persisted as
  /// the live filter exactly like any other change — pick it today, reopen the
  /// app tomorrow, still filtered.
  Future<void> _openPresetSheet(
    BuildContext context,
    CalendarPageLoaded state,
  ) async {
    final picked = await FilterPresetSheet.show(
      context,
      current: state.filters,
    );
    if (picked == null || !context.mounted) return;
    _applyFilters(context, picked);
  }

  Future<void> _openSettings(BuildContext context) async {
    final bloc = context.read<CalendarBloc>();
    await AppNavigator.toCalendarSettings(context);
    if (!mounted) return;
    // `didPopNext` already re-read the appearance settings. The reload stays
    // unconditional rather than going through `_reloadIfStale`: Settings ->
    // Categories can delete a category, which reassigns its events to `other`
    // in a transaction behind the service's cache — an event-row change that
    // bumps no revision.
    bloc.add(const LoadCalendarEvents());
  }

  /// Warms [CalendarBloc.eventsForDay] for the month before and after
  /// [focusedDay], so the first drag onto either neighbour is a cache hit
  /// instead of a cold scan across all its visible days. Read-only —
  /// dispatches nothing, calls `setState` on nothing — so, unlike the
  /// memoized lookup itself, it is safe to run outside build.
  ///
  /// **One task per month, at [Priority.idle], and both halves of that
  /// matter.** A post-frame callback would run on the UI thread before the
  /// next vsync, so paying 84 cold lookups there during a continuous swipe
  /// relocates jank rather than removing it. But idle priority alone only
  /// governs when a task *starts*: `SchedulerBinding` runs one queued task to
  /// completion per event-loop turn, so a single task covering both months
  /// would still block for both once it began. Queuing them separately halves
  /// that worst case and — because the scheduling strategy is re-consulted
  /// per task — lets the second month defer if a fling starts after the
  /// first. The default strategy skips idle tasks while transient callbacks
  /// are pending, so they wait out the drag and stay queued, never dropped.
  ///
  /// Each task re-checks [mounted] and the state independently: they land at
  /// least a frame apart, and either could change in between (a pop, a
  /// database switch, a fast page-to-page swipe).
  void _schedulePrewarm(DateTime focusedDay) {
    for (final monthOffset in _prewarmMonthOffsets) {
      SchedulerBinding.instance.scheduleTask(() {
        if (!mounted) return;
        if (context.read<CalendarBloc>().state is! CalendarPageLoaded) return;
        _prewarmMonth(focusedDay, monthOffset);
      }, Priority.idle);
    }
  }

  /// The window this fills — radius 1 month around [focusedDay] — is
  /// strictly inside [CalendarBloc]'s day-cache eviction window (radius 3):
  /// same "months relative to focus" definition, different radii, so nothing
  /// warmed here is ever evicted before the grid gets to read it.
  void _prewarmMonth(DateTime focusedDay, int monthOffset) {
    final bloc = context.read<CalendarBloc>();
    final monthAnchor = DateTime.utc(
      focusedDay.year,
      focusedDay.month + monthOffset,
    );
    final startingDayOfWeek = startingDayOfWeekFor(_appearance.weekStart);
    for (final day in gridDaysForMonth(monthAnchor, startingDayOfWeek)) {
      bloc.eventsForDay(day);
    }
  }
}

class _CalendarTable extends StatelessWidget {
  /// Range the grid and the header's date picker both span, so jumping to a
  /// date can never land on a page the calendar refuses to show. Shared with
  /// the event editor's day pickers via [CalendarBounds] — a date the user
  /// can anchor an event on must also be a date they can browse to.
  static final DateTime _firstDay = CalendarBounds.earliest;
  static final DateTime _lastDay = CalendarBounds.latest;

  final CalendarPageLoaded state;
  final CalendarFormat format;
  final bool formatLocked;
  final CalendarAppearance appearance;

  /// Built once by [_CalendarViewState] and rebuilt only when its inputs
  /// change — the providers are stateless, and the grid rebuilds far more
  /// often than the localization or the missed-display setting does.
  final DayBarsResolver barsResolver;

  /// Same deal for the cell wash: its providers depend only on the
  /// appearance, which the page already reloads when settings change.
  final CellTintResolver tintResolver;

  /// And for the left-edge rail. [railStyle], [railBasePosition] and
  /// [maxRailMarks] are paint-side
  /// parameters the resolver never sees, so changing either repaints without
  /// dropping [railOutputCache].
  final DayRailResolver railResolver;
  final DayRailStyle railStyle;
  final DayRailBasePosition railBasePosition;
  final int maxRailMarks;

  /// Per-day memo of [barsResolver]/[tintResolver] **output**, owned by
  /// [_CalendarViewState] and kept valid by its
  /// `_syncResolverOutputCache` — this widget only reads and populates it,
  /// never decides when to drop it. Passed down (rather than rebuilt here)
  /// because this widget is reconstructed on every grid build, while the
  /// memo needs to survive across builds whose generation has not changed.
  final Map<DateTime, List<DayBar>> barsOutputCache;
  final Map<DateTime, DayCellTint> tintOutputCache;
  final Map<DateTime, List<DayRailMark>> railOutputCache;

  /// Long-press quick-add. The grid only reports the day; deciding what to do
  /// with it (pick a template, create, undo) belongs to the page, which owns
  /// the sheets and the bloc.
  final ValueChanged<DateTime> onDayLongPressed;

  const _CalendarTable({
    required this.state,
    required this.format,
    required this.formatLocked,
    required this.appearance,
    required this.barsResolver,
    required this.tintResolver,
    required this.railResolver,
    required this.railStyle,
    required this.railBasePosition,
    required this.maxRailMarks,
    required this.barsOutputCache,
    required this.tintOutputCache,
    required this.railOutputCache,
    required this.onDayLongPressed,
  });

  StartingDayOfWeek get _startingDayOfWeek =>
      startingDayOfWeekFor(appearance.weekStart);

  /// Row height that guarantees the day-number chip zone and the marker
  /// strip never overlap, whatever the marker style and density.
  /// Row height for a grid whose marker strip is [stripHeight] tall.
  ///
  /// Takes the strip rather than computing it, because [build] needs the same
  /// number twice — once for the row and once for the rail's lane — and
  /// `_buildDayCell` runs 42 times per rebuild. Deriving it in both getters
  /// meant recomputing it per cell on the very path that dropping the rail's
  /// `LayoutBuilder` was meant to lighten.
  static double _rowHeightFor(double stripHeight) {
    final height = CalendarDayCell.chipZoneHeight + stripHeight + 6;
    return height < 52 ? 52 : height.ceilToDouble();
  }

  /// The lane the left-edge rail gets, which differs per style — see
  /// [CalendarDayCell.railLaneHeight], the one definition the settings
  /// preview shares. Passing it down also spares the rail a `LayoutBuilder`
  /// per visible cell.
  static double _railHeightFor(
    double rowHeight,
    double stripHeight,
    DayRailStyle railStyle,
  ) => CalendarDayCell.railLaneHeight(
    rowHeight: rowHeight,
    stripHeight: stripHeight,
    railStyle: railStyle,
  );

  /// Jumps to a date picked from the header title. The picker's wheels
  /// carry a day too, so this both focuses the month and selects the day —
  /// dispatching [SelectCalendarDay] so the panel below moves with it. Opens
  /// on the currently selected day.
  Future<void> _openMonthYearPicker(BuildContext context) async {
    final bloc = context.read<CalendarBloc>();
    final picked = await MonthYearPickerSheet.show(
      context,
      initialDate: state.selectedDay,
      firstDate: _firstDay,
      lastDate: _lastDay,
      accent: appearance.accentOr(Theme.of(context).colorScheme.primary),
    );
    if (picked == null) return;
    bloc.add(
      SelectCalendarDay(
        day: picked,
        focusedDay: picked,
        source: CalendarSelectionSource.navigation,
      ),
    );
  }

  void _goToToday(BuildContext context) {
    final today = DateTime.now();
    final normalized = DateTime.utc(today.year, today.month, today.day);
    context.read<CalendarBloc>().add(
      SelectCalendarDay(
        day: normalized,
        focusedDay: normalized,
        source: CalendarSelectionSource.navigation,
      ),
    );
  }

  /// Builds one day cell. [now] and [accent] are resolved once per grid
  /// build and threaded in: a month shows ~42 cells, and re-deriving either
  /// per cell allocated a `Color` and read the clock 42 times a frame.
  Widget _buildDayCell(
    DateTime day, {
    required bool isOutside,
    required DateTime now,
    required Color accent,
    required CalendarBloc bloc,
    required double railHeight,
  }) {
    // Both lookups are O(1): the fasting style is memoized inside the engine
    // and the day's events come from the bloc's day cache — the same
    // memoized call `eventLoader` makes for this cell.
    final key = DateTime.utc(day.year, day.month, day.day);
    // The normalized key is needed for the output memo below anyway, so the
    // fasting lookup takes it directly rather than re-deriving it (**5.4**).
    //
    // The filter's fasting layer gates it here as well as in the three
    // resolver factories: the strong display style paints the **day number**,
    // which reaches the cell down this path rather than through a provider, so
    // composing the providers out does not silence it. Skipping the lookup
    // outright rather than discarding its result also spares the probe.
    final fastingNumberColor = state.filters.showFasting
        ? FastingCalendar.cellStyleForUtcDay(key).numberColor
        : null;
    // Resolver output memo (3.3): valid for as long as `_outputGeneration`
    // says it is, so a rebuild the generation is unaffected by (a day tap, a
    // format toggle) serves this from cache instead of re-running
    // `tintResolver.resolve` for all 42 cells.
    final tint = tintOutputCache[key] ??= tintResolver.resolve(
      day,
      bloc.eventsForDay(day),
    );
    // The rail renders inside the cell, so it resolves here rather than in
    // `markerBuilder` where the bars do. With the rail off it never runs at
    // all — the resolver's cost is not worth paying for a channel that paints
    // nothing.
    final railMarks = railStyle == DayRailStyle.none
        ? const <DayRailMark>[]
        : railOutputCache[key] ??= railResolver.resolve(
            day,
            bloc.eventsForDay(day),
          );
    return CalendarDayCell(
      day: day,
      isToday: isSameDay(day, now),
      isSelected: isSameDay(day, state.selectedDay),
      isOutside: isOutside,
      isWeekend: CalendarWeekend.isWeekend(day),
      todayStyle: appearance.todayStyle,
      highlightWeekends: appearance.highlightWeekends,
      accent: accent,
      tint: tint,
      fastingNumberColor: fastingNumberColor,
      railMarks: railMarks,
      railStyle: railStyle,
      railBasePosition: railBasePosition,
      maxRailMarks: maxRailMarks,
      railHeight: railHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final calendarBloc = context.read<CalendarBloc>();
    final now = DateTime.now();
    final accent = appearance.accentOr(colorScheme.primary);
    // Once per build, not once per cell: the row and the rail's lane are two
    // views of the same marker-strip height, and `_buildDayCell` runs 42
    // times per rebuild.
    final stripHeight = CalendarDayBars.stripHeight(
      appearance.maxDayBars,
      appearance.markerStyle,
    );
    final rowHeight = _rowHeightFor(stripHeight);
    final railHeight = _railHeightFor(rowHeight, stripHeight, railStyle);
    final dowStyle = theme.textTheme.labelMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );

    return TableCalendar<CalendarEvent>(
      firstDay: _firstDay,
      lastDay: _lastDay,
      focusedDay: state.focusedDay,
      selectedDayPredicate: (day) => isSameDay(state.selectedDay, day),
      calendarFormat: format,
      // The height animation belongs to `KeyboardCoupledSize` above, so the
      // package's own one is collapsed to a single frame. Not `Duration.zero`:
      // a zero-duration `AnimationController` publishes its end value
      // synchronously from inside `RenderAnimatedSize.performLayout`, which
      // then re-dirties itself mid-layout and throws.
      formatAnimationDuration: const Duration(milliseconds: 1),
      eventLoader: calendarBloc.eventsForDay,
      startingDayOfWeek: _startingDayOfWeek,
      weekendDays: CalendarWeekend.days,
      weekNumbersVisible: appearance.showWeekNumbers,
      rowHeight: rowHeight,
      daysOfWeekHeight: 24,
      locale: l10n.localeName,
      availableCalendarFormats: {
        CalendarFormat.month: l10n.calendarFormatMonth,
        CalendarFormat.twoWeeks: l10n.calendarFormatTwoWeeks,
        CalendarFormat.week: l10n.calendarFormatWeek,
      },
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        // The default chevrons claim 64dp each — a third of a phone's width
        // spent on two arrows the user can also swipe. Tightened to 40dp
        // touch targets so the month title and the Today button fit on the
        // same row without either of them shrinking.
        headerPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        leftChevronMargin: EdgeInsets.zero,
        rightChevronMargin: EdgeInsets.zero,
        leftChevronPadding: AppSpacing.allSm,
        rightChevronPadding: AppSpacing.allSm,
        leftChevronIcon: Icon(
          Icons.chevron_left_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
        rightChevronIcon: Icon(
          Icons.chevron_right_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: dowStyle,
        weekendStyle: appearance.highlightWeekends
            ? dowStyle.copyWith(
                color: colorScheme.error.withValues(alpha: 0.85),
              )
            : dowStyle,
      ),
      calendarStyle: CalendarStyle(
        // Show leading/trailing days from adjacent months, faded so the
        // focused month still reads as the primary content (the fade itself
        // is applied by the cell/marker builders).
        outsideDaysVisible: true,
        weekNumberTextStyle: theme.textTheme.labelSmall!.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        // Default dot markers are replaced by markerBuilder bars below.
        markersMaxCount: 0,
      ),
      calendarBuilders: CalendarBuilders<CalendarEvent>(
        defaultBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: false,
          now: now,
          accent: accent,
          bloc: calendarBloc,
          railHeight: railHeight,
        ),
        todayBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: false,
          now: now,
          accent: accent,
          bloc: calendarBloc,
          railHeight: railHeight,
        ),
        selectedBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: false,
          now: now,
          accent: accent,
          bloc: calendarBloc,
          railHeight: railHeight,
        ),
        outsideBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: true,
          now: now,
          accent: accent,
          bloc: calendarBloc,
          railHeight: railHeight,
        ),
        headerTitleBuilder: (context, day) {
          final title = DateFormat.yMMMM(l10n.localeName).format(day);
          final ledger = NoteMoneyLedgerService.instanceOrNull;
          final monthNet = calendarBloc.monthNetFor(day);
          // Today sits to the left of the title, and the whole cluster
          // (button, title, net) centers as a block via mainAxisAlignment —
          // matching the original layout's feel rather than pinning the
          // title dead-center of the full header or the button flush right.
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.goToToday,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.today_rounded, size: 20),
                onPressed: () => _goToToday(context),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Tooltip(
                  message: l10n.monthYearPickerTitle,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                    onTap: () => _openMonthYearPicker(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: AppIconSizes.small,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (ledger != null && monthNet != 0) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Δ ${ledger.formatNetSigned(monthNet)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: monthNet > 0
                        ? CalendarColors.moneyPositive
                        : CalendarColors.moneyNegative,
                  ),
                ),
              ],
            ],
          );
        },
        markerBuilder: (context, day, events) {
          // Resolver output memo (3.3) — see `_buildDayCell`'s tint lookup
          // for the identical reasoning.
          final key = DateTime.utc(day.year, day.month, day.day);
          final bars = barsOutputCache[key] ??= barsResolver.resolve(
            day,
            events,
          );
          if (bars.isEmpty) return const SizedBox.shrink();
          // Outside-month fading only applies to the month format; week and
          // two-week rows show every day at full strength.
          final isOutside =
              format == CalendarFormat.month &&
              (day.month != state.focusedDay.month ||
                  day.year != state.focusedDay.year);
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CalendarDayBars(
                bars: bars,
                maxBars: appearance.maxDayBars,
                style: appearance.markerStyle,
                opacity: isOutside ? CalendarDayCell.outsideAlpha : 1.0,
              ),
            ),
          );
        },
      ),
      onDaySelected: (selectedDay, focusedDay) {
        context.read<CalendarBloc>().add(
          SelectCalendarDay(
            day: selectedDay,
            focusedDay: focusedDay,
            source: CalendarSelectionSource.grid,
          ),
        );
      },
      onDayLongPressed: (selectedDay, focusedDay) =>
          onDayLongPressed(selectedDay),
      onPageChanged: (focusedDay) {
        context.read<CalendarBloc>().add(
          ChangeFocusedDay(focusedDay: focusedDay),
        );
      },
      onFormatChanged: formatLocked
          ? null
          : (next) {
              context.read<CalendarBloc>().add(
                ChangeCalendarFormat(format: next),
              );
            },
    );
  }
}

class _KeyboardInsetProbe extends StatefulWidget {
  const _KeyboardInsetProbe({required this.inset, required this.child});

  final ValueNotifier<double> inset;
  final Widget child;

  @override
  State<_KeyboardInsetProbe> createState() => _KeyboardInsetProbeState();
}

class _KeyboardInsetProbeState extends State<_KeyboardInsetProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.inset.value = MediaQuery.viewInsetsOf(context).bottom;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
