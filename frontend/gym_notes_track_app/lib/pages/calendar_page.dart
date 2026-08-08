import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/import_export/import_export_state.dart';
import '../constants/app_icon_sizes.dart';
import '../constants/app_spacing.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../repositories/note_repository.dart';
import '../services/app_navigator.dart';
import '../services/day_bars_resolver.dart';
import '../services/note_money_ledger_service.dart';
import '../services/public_holiday_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/markdown_color_syntax.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/calendar_bottom_panel.dart';
import '../widgets/calendar_day_bars.dart';
import '../widgets/calendar_day_cell.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/month_year_picker_sheet.dart';

/// Overflow-menu actions on the calendar app bar.
enum _CalendarMenuAction { exportIcs }

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

class _CalendarViewState extends State<_CalendarView> {
  CalendarAppearance _appearance = const CalendarAppearance();

  /// Resolved markdown palette, so an event's description renders with the
  /// user's custom colours in the detail sheet.
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  /// Whether the bottom panel is expanded over the calendar grid. Transient
  /// on purpose: restoring a hidden calendar across app opens would read as
  /// "the calendar disappeared", so every visit starts with the grid shown.
  bool _panelExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final appearance = await settings.getCalendarAppearance();
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    setState(() {
      _appearance = appearance;
      _colorPalette = palette;
    });
  }

  /// Shows an event read-only first, then routes whatever the user chose
  /// there. Tapping a day-panel row used to drop straight into the edit form;
  /// now that descriptions are real content, the first thing a tap does is
  /// show them.
  Future<void> _openDetailSheet(
    BuildContext context,
    CalendarEvent event,
  ) async {
    final action = await EventDetailSheet.show(
      context,
      event: event,
      colorPalette: _colorPalette,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case EventDetailAction.edit:
        await _openEditorSheet(context, initialEvent: event);
      case EventDetailAction.openNote:
        await _openLinkedNote(context, event);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(l10n.calendar),
        actions: [
          BlocBuilder<CalendarBloc, CalendarPageState>(
            builder: (context, state) {
              final loaded = state is CalendarPageLoaded ? state : null;
              final hasFilter =
                  loaded != null && loaded.hiddenCategoryIds.isNotEmpty;
              return IconButton(
                tooltip: l10n.filterCalendar,
                icon: Icon(
                  hasFilter
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                ),
                onPressed: loaded == null
                    ? null
                    : () => _openFilterSheet(context, loaded),
              );
            },
          ),
          IconButton(
            tooltip: l10n.calendarSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
          BlocBuilder<CalendarBloc, CalendarPageState>(
            builder: (context, state) {
              final loaded = state is CalendarPageLoaded ? state : null;
              final hasEvents = loaded != null && loaded.allEvents.isNotEmpty;
              return PopupMenuButton<_CalendarMenuAction>(
                onSelected: (action) => switch (action) {
                  _CalendarMenuAction.exportIcs => _exportCalendar(
                    context,
                    loaded!,
                  ),
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
      body: BlocBuilder<CalendarBloc, CalendarPageState>(
        builder: (context, state) {
          if (state is CalendarPageLoading || state is CalendarPageInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is CalendarPageError) {
            return Center(child: Text(state.message));
          }
          final loaded = state as CalendarPageLoaded;
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
                    : _CalendarTable(state: loaded, appearance: _appearance),
              ),
              const Divider(height: 1),
              Expanded(
                child: CalendarBottomPanel(
                  loaded: loaded,
                  expanded: _panelExpanded,
                  onToggleExpanded: () =>
                      setState(() => _panelExpanded = !_panelExpanded),
                  onEditEvent: (event) =>
                      _openEditorSheet(context, initialEvent: event),
                  onShowEvent: (event) => _openDetailSheet(context, event),
                  onOpenNote: (event) => _openLinkedNote(context, event),
                  colorPalette: _colorPalette,
                  onSuppressHoliday: (day) => _removeHoliday(context, day),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: BlocBuilder<CalendarBloc, CalendarPageState>(
        builder: (context, state) {
          final selectedDay = state is CalendarPageLoaded
              ? state.selectedDay
              : DateTime.now();
          return FloatingActionButton(
            tooltip: l10n.addEvent,
            onPressed: () => _openEditorSheet(context, day: selectedDay),
            child: const Icon(Icons.add_rounded),
          );
        },
      ),
    );

    // Export feedback funnels through one listener so the menu action only
    // has to dispatch. Guarded on the calendar operation because the bloc is
    // app-wide and also serves note/folder exports.
    return BlocListener<ImportExportBloc, ImportExportState>(
      listener: _onImportExportState,
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

  Future<void> _openEditorSheet(
    BuildContext context, {
    CalendarEvent? initialEvent,
    DateTime? day,
  }) async {
    // The bloc's per-day lookup is already memoized and O(1), so handing it
    // to the picker costs nothing and lets the grid show which days are
    // already busy while the user schedules.
    final eventsForDay = context.read<CalendarBloc>().eventsForDay;
    final result = await EventEditorSheet.show(
      context,
      defaultDate: initialEvent?.startDate ?? day ?? DateTime.now(),
      initialEvent: initialEvent,
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
      case EventEditorDeleted(:final id):
        bloc.add(DeleteCalendarEvent(eventId: id));
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

    final holidayService = GetIt.I<PublicHolidayService>();
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
    // Reload the appearance settings and the events so holiday recurrences
    // re-render if the holiday profile changed in settings.
    await _loadSettings();
    if (!mounted) return;
    bloc.add(const LoadCalendarEvents());
  }
}

class _CalendarTable extends StatelessWidget {
  /// Range the grid and the header's date picker both span, so jumping to a
  /// date can never land on a page the calendar refuses to show.
  static final DateTime _firstDay = DateTime.utc(2000, 1, 1);
  static final DateTime _lastDay = DateTime.utc(2100, 12, 31);

  final CalendarPageLoaded state;
  final CalendarAppearance appearance;

  const _CalendarTable({required this.state, required this.appearance});

  StartingDayOfWeek get _startingDayOfWeek {
    return switch (appearance.weekStart) {
      CalendarWeekStart.monday => StartingDayOfWeek.monday,
      CalendarWeekStart.saturday => StartingDayOfWeek.saturday,
      CalendarWeekStart.sunday => StartingDayOfWeek.sunday,
    };
  }

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
    bloc.add(SelectCalendarDay(day: picked, focusedDay: picked));
  }

  void _goToToday(BuildContext context) {
    final today = DateTime.now();
    final normalized = DateTime.utc(today.year, today.month, today.day);
    context.read<CalendarBloc>().add(
      SelectCalendarDay(day: normalized, focusedDay: normalized),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    required bool isOutside,
  }) {
    return CalendarDayCell(
      day: day,
      isToday: isSameDay(day, DateTime.now()),
      isSelected: isSameDay(day, state.selectedDay),
      isOutside: isOutside,
      isWeekend:
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday,
      todayStyle: appearance.todayStyle,
      highlightWeekends: appearance.highlightWeekends,
      accent: appearance.accentOr(Theme.of(context).colorScheme.primary),
    );
  }

  /// Net money change for the focused [month]: the exact sum of what the
  /// visible day cells display. Mirrors the day bar/summary providers on
  /// both axes the two surfaces could diverge on: hidden categories are
  /// excluded (cells only ever see category-filtered events), and dedupe
  /// is per (start day, note) — a note linked from events on two
  /// different days shows on both cells, so it counts twice here too,
  /// while a recurring event still never multiplies its note.
  int _monthNet(NoteMoneyLedgerService ledger, DateTime month) {
    var sum = 0;
    Set<String>? seen;
    for (final event in state.allEvents) {
      final noteId = event.noteId;
      if (noteId == null) continue;
      if (state.hiddenCategoryIds.contains(event.categoryId)) continue;
      final startUtc = DateTime.fromMillisecondsSinceEpoch(
        event.startDate.millisecondsSinceEpoch,
        isUtc: true,
      );
      if (startUtc.year != month.year || startUtc.month != month.month) {
        continue;
      }
      seen ??= <String>{};
      if (!seen.add('${startUtc.day}:$noteId')) continue;
      final entry = ledger.ledgerFor(noteId);
      if (entry == null) continue;
      sum += entry.net;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final calendarBloc = context.read<CalendarBloc>();
    final barsResolver = DayBarsResolver.defaults(l10n);
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
        defaultBuilder: (context, day, focusedDay) =>
            _buildDayCell(context, day, isOutside: false),
        todayBuilder: (context, day, focusedDay) =>
            _buildDayCell(context, day, isOutside: false),
        selectedBuilder: (context, day, focusedDay) =>
            _buildDayCell(context, day, isOutside: false),
        outsideBuilder: (context, day, focusedDay) =>
            _buildDayCell(context, day, isOutside: true),
        headerTitleBuilder: (context, day) {
          final title = DateFormat.yMMMM(l10n.localeName).format(day);
          final ledger = NoteMoneyLedgerService.instanceOrNull;
          final monthNet = ledger == null ? 0 : _monthNet(ledger, day);
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
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
              ],
            ],
          );
        },
        markerBuilder: (context, day, events) {
          final bars = barsResolver.resolve(day, events);
          if (bars.isEmpty) return const SizedBox.shrink();
          // Outside-month fading only applies to the month format; week and
          // two-week rows show every day at full strength.
          final isOutside =
              state.format == CalendarFormat.month &&
              (day.month != state.focusedDay.month ||
                  day.year != state.focusedDay.year);
          Widget child = Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CalendarDayBars(
                bars: bars,
                maxBars: appearance.maxDayBars,
                style: appearance.markerStyle,
              ),
            ),
          );
          if (isOutside) child = Opacity(opacity: 0.35, child: child);
          return child;
        },
      ),
      onDaySelected: (selectedDay, focusedDay) {
        context.read<CalendarBloc>().add(
          SelectCalendarDay(day: selectedDay, focusedDay: focusedDay),
        );
      },
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
