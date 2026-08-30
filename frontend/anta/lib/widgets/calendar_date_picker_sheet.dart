import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/calendar_weekend.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';
import 'month_year_picker_sheet.dart';

/// How many days a single [CalendarDatePickerSheet] pass may return.
enum CalendarDatePickerMode { single, multi }

/// Looks up the markers to draw on a picker day. Callers hand in the
/// calendar's own memoized per-day lookup, so the picker shows what is
/// already scheduled without issuing a single extra query. Return an empty
/// list for "nothing on this day".
typedef PickerDayLoad = int Function(DateTime day);

/// In-app calendar for picking one or several dates.
///
/// Replaces `showDatePicker` inside the event editor so date entry happens on
/// the same grid the rest of the app uses — same week start, same accent, same
/// today style, all sourced from [CalendarAppearance]. In [CalendarDatePickerMode.multi]
/// a whole availability set is built in one pass instead of one dialog
/// round-trip per date.
///
/// The multi mode deliberately knows nothing about *why* the dates matter: it
/// takes a set and returns the edited set. That is what lets the same surface
/// later drive per-occurrence skip dates without a UI rewrite.
class CalendarDatePickerSheet extends StatefulWidget {
  final CalendarDatePickerMode mode;

  /// Days selected when the sheet opens (date-only UTC). Single mode uses the
  /// first entry as the initially focused day.
  final Set<DateTime> initialSelection;

  /// Inclusive lower/upper bounds. Days outside are rendered dimmed and
  /// refuse selection. Callers pass `CalendarBounds` unless a field has its
  /// own semantic floor (the Until picker starts at the event's start date).
  final DateTime firstDate;
  final DateTime lastDate;

  /// Optional busy-day lookup used to render markers while picking.
  final PickerDayLoad? dayLoad;

  /// Look & feel, passed in rather than re-read. Resolving
  /// `getCalendarAppearance()` after the first frame would visibly re-lay-out
  /// the grid (week start and row height both move), and the calendar page
  /// already holds a current copy.
  final CalendarAppearance appearance;

  /// Whether confirming with nothing selected is allowed. False for callers
  /// that need at least one date to stay valid (the one-time date set); true
  /// for a set that is legitimately emptied, like the cancelled-days editor.
  final bool allowEmpty;

  const CalendarDatePickerSheet({
    super.key,
    required this.mode,
    required this.initialSelection,
    required this.firstDate,
    required this.lastDate,
    required this.appearance,
    this.dayLoad,
    this.allowEmpty = false,
  });

  /// Picks a single date. Returns null when dismissed.
  static Future<DateTime?> pickSingle(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required CalendarAppearance appearance,
    PickerDayLoad? dayLoad,
  }) async {
    final picked = await _show(
      context,
      mode: CalendarDatePickerMode.single,
      initialSelection: {_dateOnly(initialDate)},
      firstDate: firstDate,
      lastDate: lastDate,
      appearance: appearance,
      dayLoad: dayLoad,
    );
    if (picked == null || picked.isEmpty) return null;
    return picked.first;
  }

  /// Edits a whole set of dates in one pass. Returns null when dismissed.
  ///
  /// By default it also never returns an empty set — clearing everything then
  /// confirming keeps the caller's original selection, because the one-time
  /// date set needs at least one date to stay valid. Pass [allowEmpty] for a
  /// set that can legitimately end up empty, such as the cancelled-days
  /// editor, where clearing it is how the user restores every occurrence.
  static Future<Set<DateTime>?> pickMulti(
    BuildContext context, {
    required Set<DateTime> initialSelection,
    required DateTime firstDate,
    required DateTime lastDate,
    required CalendarAppearance appearance,
    PickerDayLoad? dayLoad,
    bool allowEmpty = false,
  }) async {
    final picked = await _show(
      context,
      mode: CalendarDatePickerMode.multi,
      initialSelection: {for (final d in initialSelection) _dateOnly(d)},
      firstDate: firstDate,
      lastDate: lastDate,
      appearance: appearance,
      dayLoad: dayLoad,
      allowEmpty: allowEmpty,
    );
    if (picked == null) return null;
    if (picked.isEmpty && !allowEmpty) return null;
    return picked;
  }

  static Future<Set<DateTime>?> _show(
    BuildContext context, {
    required CalendarDatePickerMode mode,
    required Set<DateTime> initialSelection,
    required DateTime firstDate,
    required DateTime lastDate,
    required CalendarAppearance appearance,
    PickerDayLoad? dayLoad,
    bool allowEmpty = false,
  }) {
    return showModalBottomSheet<Set<DateTime>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CalendarDatePickerSheet(
        mode: mode,
        initialSelection: initialSelection,
        firstDate: firstDate,
        lastDate: lastDate,
        appearance: appearance,
        dayLoad: dayLoad,
        allowEmpty: allowEmpty,
      ),
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  @override
  State<CalendarDatePickerSheet> createState() =>
      _CalendarDatePickerSheetState();
}

class _CalendarDatePickerSheetState extends State<CalendarDatePickerSheet> {
  late Set<DateTime> _selection;
  late DateTime _focusedDay;

  CalendarAppearance get _appearance => widget.appearance;

  @override
  void initState() {
    super.initState();
    _selection = {...widget.initialSelection};
    final anchor = _selection.isEmpty
        ? CalendarDatePickerSheet._dateOnly(DateTime.now())
        : (_selection.toList()..sort()).first;
    _focusedDay = _clamp(anchor);
  }

  DateTime _clamp(DateTime day) {
    if (day.isBefore(widget.firstDate)) return widget.firstDate;
    if (day.isAfter(widget.lastDate)) return widget.lastDate;
    return day;
  }

  void _jumpToToday() {
    setState(() {
      _focusedDay = _clamp(CalendarDatePickerSheet._dateOnly(DateTime.now()));
    });
  }

  /// Opens the wheel/typed date picker from the header's month title, exactly
  /// like the calendar page's own header. Single mode treats Apply as the
  /// final answer (the wheels carry a full date, so re-tapping it on the grid
  /// would be redundant); multi mode only jumps the grid there — day toggling
  /// stays a grid gesture so a navigation intent can never edit the set.
  Future<void> _openMonthYearJump() async {
    final picked = await MonthYearPickerSheet.show(
      context,
      initialDate: _focusedDay,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      accent: _appearance.accentOr(Theme.of(context).colorScheme.primary),
    );
    if (picked == null || !mounted) return;
    if (widget.mode == CalendarDatePickerMode.single) {
      Navigator.of(context).pop(<DateTime>{_clamp(picked)});
      return;
    }
    setState(() => _focusedDay = _clamp(picked));
  }

  bool _isSelected(DateTime day) =>
      _selection.contains(CalendarDatePickerSheet._dateOnly(day));

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final day = CalendarDatePickerSheet._dateOnly(selectedDay);
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) return;
    if (widget.mode == CalendarDatePickerMode.single) {
      Navigator.of(context).pop(<DateTime>{day});
      return;
    }
    setState(() {
      _focusedDay = focusedDay;
      if (!_selection.remove(day)) _selection.add(day);
    });
  }

  StartingDayOfWeek get _startingDayOfWeek {
    return switch (_appearance.weekStart) {
      CalendarWeekStart.monday => StartingDayOfWeek.monday,
      CalendarWeekStart.saturday => StartingDayOfWeek.saturday,
      CalendarWeekStart.sunday => StartingDayOfWeek.sunday,
    };
  }

  /// Same collision-free geometry the real grid uses, so the picker cannot
  /// drift from it. Markers here are a single "busy" bar, so one slot.
  double get _rowHeight {
    final strip = widget.dayLoad == null
        ? 0.0
        : CalendarDayBars.stripHeight(1, _appearance.markerStyle);
    final height = CalendarDayCell.chipZoneHeight + strip + 6;
    return height < 52 ? 52 : height.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isMulti = widget.mode == CalendarDatePickerMode.multi;
    final accent = _appearance.accentOr(theme.colorScheme.primary);
    final now = DateTime.now();
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar. The whole sheet is padded rather than just the scroll view,
    // because the multi-select footer is a fixed row below it — same fix as
    // `CalendarFilterSheet`, whose Cancel/Apply row has the same problem.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomClearance),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.cancel,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      isMulti
                          ? l10n.datePickerMultiTitle
                          : l10n.datePickerSingleTitle,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Available in both modes: a single-date pick can wander
                  // months too, and there was no way back without swiping.
                  IconButton(
                    tooltip: l10n.datePickerToday,
                    icon: const Icon(Icons.today_rounded),
                    onPressed: _jumpToToday,
                  ),
                  if (isMulti)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: FilledButton(
                        onPressed: _selection.isEmpty && !widget.allowEmpty
                            ? null
                            : () => Navigator.of(context).pop({..._selection}),
                        child: Text(l10n.save),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: TableCalendar<void>(
                  firstDay: widget.firstDate,
                  lastDay: widget.lastDate,
                  focusedDay: _focusedDay,
                  selectedDayPredicate: _isSelected,
                  calendarFormat: CalendarFormat.month,
                  startingDayOfWeek: _startingDayOfWeek,
                  weekendDays: CalendarWeekend.days,
                  weekNumbersVisible: _appearance.showWeekNumbers,
                  rowHeight: _rowHeight,
                  daysOfWeekHeight: 24,
                  locale: l10n.localeName,
                  availableGestures: AvailableGestures.horizontalSwipe,
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    leftChevronIcon: Icon(
                      Icons.chevron_left_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    rightChevronIcon: Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  calendarStyle: const CalendarStyle(
                    outsideDaysVisible: true,
                    markersMaxCount: 0,
                  ),
                  calendarBuilders: CalendarBuilders<void>(
                    headerTitleBuilder: (context, day) {
                      final title = DateFormat.yMMMM(
                        l10n.localeName,
                      ).format(day);
                      return Center(
                        child: Tooltip(
                          message: l10n.monthYearPickerTitle,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _openMonthYearJump,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    defaultBuilder: (context, day, _) =>
                        _cell(day, accent, isOutside: false, now: now),
                    todayBuilder: (context, day, _) =>
                        _cell(day, accent, isOutside: false, now: now),
                    selectedBuilder: (context, day, _) =>
                        _cell(day, accent, isOutside: false, now: now),
                    outsideBuilder: (context, day, _) =>
                        _cell(day, accent, isOutside: true, now: now),
                    markerBuilder: (context, day, _) => _marker(
                      day,
                      l10n: l10n,
                      busyColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onDaySelected: _onDaySelected,
                  onPageChanged: (focusedDay) =>
                      setState(() => _focusedDay = focusedDay),
                ),
              ),
            ),
            if (isMulti)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.datePickerSelectedCount(_selection.length),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _selection.isEmpty
                          ? null
                          : () => setState(_selection.clear),
                      child: Text(l10n.datePickerClear),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds one day cell. [now] and [accent] are resolved once per grid
  /// build and threaded in: a month shows ~42 cells, and re-deriving either
  /// per cell allocated a `Color` and read the clock 42 times a frame.
  Widget _cell(
    DateTime day,
    Color accent, {
    required bool isOutside,
    required DateTime now,
  }) {
    return CalendarDayCell(
      day: day,
      isToday: isSameDay(day, now),
      isSelected: _isSelected(day),
      isOutside: isOutside,
      isWeekend: CalendarWeekend.isWeekend(day),
      todayStyle: _appearance.todayStyle,
      highlightWeekends: _appearance.highlightWeekends,
      accent: accent,
    );
  }

  /// A single neutral bar marking a day that already carries events, so the
  /// user can see a day is busy before scheduling onto it. Deliberately not
  /// category-coloured: this is a "taken" signal, not a second calendar.
  Widget _marker(
    DateTime day, {
    required AppLocalizations l10n,
    required Color busyColor,
  }) {
    final load = widget.dayLoad;
    if (load == null) return const SizedBox.shrink();
    final count = load(CalendarDatePickerSheet._dateOnly(day));
    if (count <= 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Semantics(
          label: l10n.datePickerBusyDay,
          child: Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: busyColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
