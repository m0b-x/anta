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
import '../constants/event_skips.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_selection_source.dart';
import '../models/day_bar.dart';
import '../models/day_cell_tint.dart';
import '../repositories/note_repository.dart';
import '../services/app_navigator.dart';
import '../services/cell_tint_resolver.dart';
import '../services/day_bars_resolver.dart';
import '../services/note_money_ledger_service.dart';
import '../services/public_holiday_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/event_agenda.dart';
import '../utils/markdown_color_syntax.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/calendar_add_fab.dart';
import '../widgets/calendar_bottom_panel.dart';
import '../widgets/calendar_day_bars.dart';
import '../widgets/calendar_day_cell.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/event_template_picker_sheet.dart';
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

  /// Whether the add button shows its day label. Driven by the panel's scroll
  /// through a notifier rather than `setState`, because the only widget that
  /// cares is the button: a page-level rebuild on every scroll tick would
  /// dirty the 42-cell grid and the whole bottom panel, which is exactly what
  /// their `sameGridInputs` / `samePanelInputs` gates exist to avoid.
  final ValueNotifier<bool> _fabExtended = ValueNotifier(true);

  /// Memoized day-bar resolver. Its providers are stateless and depend only
  /// on the localization and the missed-display setting, both of which change
  /// far less often than the grid rebuilds.
  DayBarsResolver? _barsResolver;
  AppLocalizations? _barsL10n;
  CalendarMissedDisplay? _barsMissedDisplay;

  DayBarsResolver _resolverFor(AppLocalizations l10n) {
    final missed = _appearance.missedDisplay;
    if (_barsResolver == null ||
        _barsL10n != l10n ||
        _barsMissedDisplay != missed) {
      _barsResolver = DayBarsResolver.defaults(l10n, missedDisplay: missed);
      _barsL10n = l10n;
      _barsMissedDisplay = missed;
    }
    return _barsResolver!;
  }

  /// Memoized cell-wash resolver, rebuilt only when the appearance changes.
  CellTintResolver? _tintResolver;
  CalendarAppearance? _tintAppearance;

  CellTintResolver get _cellTintResolver {
    if (_tintResolver == null || _tintAppearance != _appearance) {
      _tintResolver = CellTintResolver.defaults(_appearance);
      _tintAppearance = _appearance;
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

  /// Generation the two output caches above were last built against, or
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
    Object hiddenCategoryIds,
    int membershipRevision,
    int presenceRevision,
    int holidayRevision,
    int categoryRevision,
    int fastingRevision,
    int? ledgerRevision,
    Object barsResolver,
    Object tintResolver,
  })?
  _outputGeneration;

  void _syncResolverOutputCache(
    CalendarPageLoaded state,
    DayBarsResolver barsResolver,
    CellTintResolver tintResolver,
  ) {
    final generation = (
      allEvents: state.allEvents,
      hiddenCategoryIds: state.hiddenCategoryIds,
      membershipRevision: state.membershipRevision,
      presenceRevision: state.presenceRevision,
      holidayRevision: PublicHolidays.revision,
      categoryRevision: CalendarCategories.revision,
      fastingRevision: FastingCalendar.revision,
      ledgerRevision: NoteMoneyLedgerService.instanceOrNull?.revision,
      barsResolver: barsResolver,
      tintResolver: tintResolver,
    );
    if (_outputGeneration == generation) return;
    _outputGeneration = generation;
    _barsOutputCache.clear();
    _tintOutputCache.clear();
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    setState(() {
      _appearance = loaded.appearance;
      _colorPalette = loaded.palette;
    });
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
  Future<void> _openDetailSheet(
    BuildContext context,
    CalendarEvent event,
    DateTime day,
  ) async {
    final bloc = context.read<CalendarBloc>();
    var current = event;
    // The occurrence write is dispatched, not awaited, and the sheet pops in
    // the same turn — so the editor can mount before it lands. Carry the text
    // forward rather than letting the editor race the database for it.
    String? pendingOccurrence;
    final action = await EventDetailSheet.show(
      context,
      event: event,
      day: day,
      colorPalette: _colorPalette,
      onEventChanged: (updated) {
        current = updated;
        bloc.add(UpdateCalendarEvent(event: updated));
      },
      onOccurrenceChanged: (occurrenceDay, description) {
        pendingOccurrence = description;
        bloc.add(
          SetOccurrenceDescription(
            eventId: event.id,
            day: occurrenceDay,
            description: description,
          ),
        );
      },
      onPresenceChanged: (occurrenceDay, missed) =>
          _setOccurrenceMissed(bloc, event.id, occurrenceDay, missed),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case EventDetailAction.edit:
        await _openEditorSheet(
          context,
          initialEvent: current,
          occurrenceDay: day,
          pendingOccurrenceDescription: pendingOccurrence,
        );
      case EventDetailAction.openNote:
        await _openLinkedNote(context, current);
      case EventDetailAction.skipOccurrence:
        _skipOccurrence(context, bloc, current.id, day);
    }
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

  static bool _hasHiddenCategories(CalendarPageState state) =>
      state is CalendarPageLoaded && state.hiddenCategoryIds.isNotEmpty;

  static bool _hasEvents(CalendarPageState state) =>
      state is CalendarPageLoaded && state.allEvents.isNotEmpty;

  static DateTime? _selectedDayOf(CalendarPageState state) =>
      state is CalendarPageLoaded ? state.selectedDay : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(l10n.calendar),
        actions: [
          BlocBuilder<CalendarBloc, CalendarPageState>(
            buildWhen: (previous, current) =>
                _isLoaded(previous) != _isLoaded(current) ||
                _hasHiddenCategories(previous) != _hasHiddenCategories(current),
            builder: (context, state) {
              final isLoaded = _isLoaded(state);
              return IconButton(
                tooltip: l10n.filterCalendar,
                icon: Icon(
                  _hasHiddenCategories(state)
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
                          child: BlocBuilder<CalendarBloc, CalendarPageState>(
                            buildWhen: (previous, current) =>
                                previous is! CalendarPageLoaded ||
                                current is! CalendarPageLoaded ||
                                !previous.sameGridInputs(current),
                            builder: (context, state) {
                              if (state is! CalendarPageLoaded) {
                                return const SizedBox(width: double.infinity);
                              }
                              final barsResolver = _resolverFor(l10n);
                              final tintResolver = _cellTintResolver;
                              _syncResolverOutputCache(
                                state,
                                barsResolver,
                                tintResolver,
                              );
                              return _CalendarTable(
                                state: state,
                                appearance: _appearance,
                                barsResolver: barsResolver,
                                tintResolver: tintResolver,
                                barsOutputCache: _barsOutputCache,
                                tintOutputCache: _tintOutputCache,
                                onDayLongPressed: (day) =>
                                    _quickAddFromTemplate(context, day),
                              );
                            },
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
      child: scaffold,
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

  Future<void> _openEditorSheet(
    BuildContext context, {
    CalendarEvent? initialEvent,
    DateTime? day,
    DateTime? occurrenceDay,
    String? pendingOccurrenceDescription,
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
    );
    if (result == null || !context.mounted) return;
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
    }
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
      hiddenCategoryIds: state.hiddenCategoryIds,
    );
    if (result == null || !context.mounted) return;
    final bloc = context.read<CalendarBloc>();
    if (result.format != state.format) {
      bloc.add(ChangeCalendarFormat(format: result.format));
    }
    bloc.add(
      ChangeHiddenCategories(hiddenCategoryIds: result.hiddenCategoryIds),
    );
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
  final CalendarAppearance appearance;

  /// Built once by [_CalendarViewState] and rebuilt only when its inputs
  /// change — the providers are stateless, and the grid rebuilds far more
  /// often than the localization or the missed-display setting does.
  final DayBarsResolver barsResolver;

  /// Same deal for the cell wash: its providers depend only on the
  /// appearance, which the page already reloads when settings change.
  final CellTintResolver tintResolver;

  /// Per-day memo of [barsResolver]/[tintResolver] **output**, owned by
  /// [_CalendarViewState] and kept valid by its
  /// `_syncResolverOutputCache` — this widget only reads and populates it,
  /// never decides when to drop it. Passed down (rather than rebuilt here)
  /// because this widget is reconstructed on every grid build, while the
  /// memo needs to survive across builds whose generation has not changed.
  final Map<DateTime, List<DayBar>> barsOutputCache;
  final Map<DateTime, DayCellTint> tintOutputCache;

  /// Long-press quick-add. The grid only reports the day; deciding what to do
  /// with it (pick a template, create, undo) belongs to the page, which owns
  /// the sheets and the bloc.
  final ValueChanged<DateTime> onDayLongPressed;

  const _CalendarTable({
    required this.state,
    required this.appearance,
    required this.barsResolver,
    required this.tintResolver,
    required this.barsOutputCache,
    required this.tintOutputCache,
    required this.onDayLongPressed,
  });

  StartingDayOfWeek get _startingDayOfWeek =>
      startingDayOfWeekFor(appearance.weekStart);

  /// Row height that guarantees the day-number chip zone and the marker
  /// strip never overlap, whatever the marker style and density.
  double get _rowHeight {
    final strip = CalendarDayBars.stripHeight(
      appearance.maxDayBars,
      appearance.markerStyle,
    );
    final height = CalendarDayCell.chipZoneHeight + strip + 6;
    return height < 52 ? 52 : height.ceilToDouble();
  }

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
  }) {
    // Both lookups are O(1): the fasting style is memoized inside the engine
    // and the day's events come from the bloc's day cache — the same
    // memoized call `eventLoader` makes for this cell.
    final fasting = FastingCalendar.cellStyleFor(day);
    final key = DateTime.utc(day.year, day.month, day.day);
    // Resolver output memo (3.3): valid for as long as `_outputGeneration`
    // says it is, so a rebuild the generation is unaffected by (a day tap, a
    // format toggle) serves this from cache instead of re-running
    // `tintResolver.resolve` for all 42 cells.
    final tint = tintOutputCache[key] ??= tintResolver.resolve(
      day,
      bloc.eventsForDay(day),
    );
    return CalendarDayCell(
      day: day,
      isToday: isSameDay(day, now),
      isSelected: isSameDay(day, state.selectedDay),
      isOutside: isOutside,
      isWeekend:
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday,
      todayStyle: appearance.todayStyle,
      highlightWeekends: appearance.highlightWeekends,
      accent: accent,
      tint: tint,
      fastingNumberColor: fasting.numberColor,
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
    final dowStyle = theme.textTheme.labelMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );

    return TableCalendar<CalendarEvent>(
      firstDay: _firstDay,
      lastDay: _lastDay,
      focusedDay: state.focusedDay,
      selectedDayPredicate: (day) => isSameDay(state.selectedDay, day),
      calendarFormat: state.format,
      eventLoader: calendarBloc.eventsForDay,
      startingDayOfWeek: _startingDayOfWeek,
      weekNumbersVisible: appearance.showWeekNumbers,
      rowHeight: _rowHeight,
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
        ),
        todayBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: false,
          now: now,
          accent: accent,
          bloc: calendarBloc,
        ),
        selectedBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: false,
          now: now,
          accent: accent,
          bloc: calendarBloc,
        ),
        outsideBuilder: (context, day, focusedDay) => _buildDayCell(
          day,
          isOutside: true,
          now: now,
          accent: accent,
          bloc: calendarBloc,
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
              state.format == CalendarFormat.month &&
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
      onFormatChanged: (format) {
        context.read<CalendarBloc>().add(ChangeCalendarFormat(format: format));
      },
    );
  }
}
