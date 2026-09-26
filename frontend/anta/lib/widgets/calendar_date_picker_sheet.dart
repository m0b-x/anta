import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/calendar_weekend.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../utils/calendar_week_start.dart';
import '../utils/date_stamp.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';
import 'form_rows.dart';
import 'month_dot_matrix.dart';
import 'month_year_picker_sheet.dart';
import 'year_month_tile.dart';

/// How many days a single [CalendarDatePickerSheet] pass may return.
enum CalendarDatePickerMode { single, multi }

/// The three views multi mode offers over one date set: the month grid where
/// days are picked, a year of dot-matrix tiles for seeing and travelling,
/// and the ordered list for reviewing and removing.
enum CalendarDatePickerView { month, year, list }

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
/// round-trip per date, and the set stays visible the whole time: a summary
/// line under the header, a year view marking every picked day, and a list.
///
/// The multi mode deliberately knows nothing about *why* the dates matter: it
/// takes a set and returns the edited set. That is what lets the same surface
/// drive the one-time date set, per-occurrence skip dates and the fasting
/// exceptions without a UI rewrite.
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

  /// The view multi mode opens on. Month for adding, list for reviewing.
  final CalendarDatePickerView initialView;

  const CalendarDatePickerSheet({
    super.key,
    required this.mode,
    required this.initialSelection,
    required this.firstDate,
    required this.lastDate,
    required this.appearance,
    this.dayLoad,
    this.allowEmpty = false,
    this.initialView = CalendarDatePickerView.month,
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
    CalendarDatePickerView initialView = CalendarDatePickerView.month,
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
      initialView: initialView,
    );
    if (picked == null) return null;
    if (picked.isEmpty && !allowEmpty) return null;
    return picked;
  }

  /// "4 dates · Sep 25 – Oct 16, 2026" — the one grammar for reading a date
  /// set back, shared with the editor's bundled Dates row. [sorted] must be
  /// ascending; both years are named when the span crosses one.
  static String summaryLabel(AppLocalizations l10n, List<DateTime> sorted) {
    if (sorted.isEmpty) return l10n.datePickerSelectedCount(0);
    final localeName = l10n.localeName;
    final count = l10n.recurrenceSpecificDates(sorted.length);
    final first = sorted.first;
    final last = sorted.last;
    if (sorted.length == 1) {
      return l10n.eventDatesSummary(
        count,
        DateFormat.yMMMEd(localeName).format(first),
      );
    }
    final firstLabel = first.year == last.year
        ? DateFormat.MMMd(localeName).format(first)
        : DateFormat.yMMMd(localeName).format(first);
    final lastLabel = DateFormat.yMMMd(localeName).format(last);
    return l10n.eventDatesSummary(count, '$firstLabel – $lastLabel');
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
    CalendarDatePickerView initialView = CalendarDatePickerView.month,
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
        initialView: initialView,
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
  late CalendarDatePickerView _view;
  late int _focusedYear;
  bool _repeatOpen = false;
  DateStampUnit _repeatUnit = DateStampUnit.month;
  int _repeatTimes = 3;

  CalendarAppearance get _appearance => widget.appearance;

  bool get _isMulti => widget.mode == CalendarDatePickerMode.multi;

  List<DateTime> get _sortedSelection => _selection.toList()..sort();

  @override
  void initState() {
    super.initState();
    _selection = {...widget.initialSelection};
    final anchor = _selection.isEmpty
        ? CalendarDatePickerSheet._dateOnly(DateTime.now())
        : (_selection.toList()..sort()).first;
    _focusedDay = _clamp(anchor);
    _focusedYear = _focusedDay.year;
    _view = _isMulti ? widget.initialView : CalendarDatePickerView.month;
  }

  DateTime _clamp(DateTime day) {
    if (day.isBefore(widget.firstDate)) return widget.firstDate;
    if (day.isAfter(widget.lastDate)) return widget.lastDate;
    return day;
  }

  void _jumpToToday() {
    final today = _clamp(CalendarDatePickerSheet._dateOnly(DateTime.now()));
    setState(() {
      _focusedDay = today;
      _focusedYear = today.year;
      if (_view == CalendarDatePickerView.list) {
        _view = CalendarDatePickerView.month;
      }
    });
  }

  void _showMonthOf(DateTime day) {
    setState(() {
      _focusedDay = _clamp(day);
      _view = CalendarDatePickerView.month;
    });
  }

  void _selectView(CalendarDatePickerView view) {
    setState(() {
      _view = view;
      if (view == CalendarDatePickerView.year) {
        _focusedYear = _focusedDay.year;
      }
    });
  }

  /// Single mode answers by popping, and a day cell is a 52px target on a grid
  /// that scrolls — a double tap lands twice before the route is gone and the
  /// second pop takes the page underneath with it. One latch guards every
  /// answering path.
  bool _popped = false;

  void _answer(Set<DateTime>? selection) {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop(selection);
  }

  /// Opens the wheel/typed date picker from the header's month title, exactly
  /// like the calendar page's own header. Single mode treats Apply as the
  /// final answer (the wheels carry a full date, so re-tapping it on the grid
  /// would be redundant); multi mode only jumps the grid there — day toggling
  /// stays a grid gesture so a navigation intent can never edit the set.
  Future<void> _openMonthYearJump() async {
    if (_popped) return;
    final picked = await MonthYearPickerSheet.show(
      context,
      initialDate: _focusedDay,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      accent: _appearance.accentOr(Theme.of(context).colorScheme.primary),
    );
    if (picked == null || !mounted) return;
    if (widget.mode == CalendarDatePickerMode.single) {
      _answer(<DateTime>{_clamp(picked)});
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
      _answer(<DateTime>{day});
      return;
    }
    setState(() {
      _focusedDay = focusedDay;
      if (!_selection.remove(day)) _selection.add(day);
    });
  }

  void _applyRepeat(DateStampResult preview) {
    setState(() {
      _selection.addAll(preview.added);
      _repeatOpen = false;
      _view = CalendarDatePickerView.list;
    });
  }

  StartingDayOfWeek get _startingDayOfWeek =>
      startingDayOfWeekFor(_appearance.weekStart);

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
    final colorScheme = theme.colorScheme;
    final isMulti = _isMulti;
    final accent = _appearance.accentOr(colorScheme.primary);
    final now = DateTime.now();
    final today = CalendarDatePickerSheet._dateOnly(now);
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar. The clearance rides whichever element actually sits on that edge —
    // the multi-mode footer when there is one, the scroll view otherwise —
    // and never the whole body: the sheet's box is a fixed fraction of the
    // screen and does not shrink for the keyboard, so padding the body
    // subtracts the inset from the content and a tall inset collapses the
    // Column to nothing, leaving a blank sheet that hit-tests nothing.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    final sorted = _sortedSelection;
    final body = switch (_view) {
      CalendarDatePickerView.month => _buildMonth(
        l10n,
        theme,
        accent,
        now,
        bottomPadding: isMulti ? 8 : 16 + bottomClearance,
      ),
      CalendarDatePickerView.year => _buildYear(
        l10n,
        theme,
        colorScheme,
        accent,
        today,
      ),
      CalendarDatePickerView.list => _buildList(
        l10n,
        theme,
        colorScheme,
        sorted,
        today,
      ),
    };

    return FractionallySizedBox(
      heightFactor: 0.86,
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
                  onPressed: () => _answer(null),
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
                          : () => _answer({..._selection}),
                      child: Text(l10n.save),
                    ),
                  ),
              ],
            ),
          ),
          if (isMulti) ...[
            _buildSummary(l10n, theme, colorScheme, sorted),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<CalendarDatePickerView>(
                segments: [
                  for (final view in CalendarDatePickerView.values)
                    ButtonSegment<CalendarDatePickerView>(
                      value: view,
                      label: Text(
                        _viewLabel(l10n, view),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => _selectView(selection.first),
              ),
            ),
          ],
          Expanded(child: body),
          if (isMulti) _buildFooter(l10n, theme, colorScheme, bottomClearance),
        ],
      ),
    );
  }

  static String _viewLabel(AppLocalizations l10n, CalendarDatePickerView view) {
    return switch (view) {
      CalendarDatePickerView.month => l10n.dayListModeMonth,
      CalendarDatePickerView.year => l10n.dayListModeYear,
      CalendarDatePickerView.list => l10n.dayListModeList,
    };
  }

  /// Count and span, in every view, so the set is never out of sight while
  /// one month of it is on the grid. Clear lives here rather than in the
  /// footer, which the repeat action owns.
  Widget _buildSummary(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    List<DateTime> sorted,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              CalendarDatePickerSheet.summaryLabel(l10n, sorted),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildMonth(
    AppLocalizations l10n,
    ThemeData theme,
    Color accent,
    DateTime now, {
    required double bottomPadding,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(8, 0, 8, bottomPadding),
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
            final title = DateFormat.yMMMM(l10n.localeName).format(day);
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
                            style: theme.textTheme.titleMedium?.copyWith(
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
        onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
      ),
    );
  }

  /// Twelve tiles with the picked days marked and a count each, paged by
  /// year. Overview and travel only — a square is too small to toggle, so a
  /// tile opens its month on the grid.
  Widget _buildYear(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    Color accent,
    DateTime today,
  ) {
    final firstYear = widget.firstDate.year;
    final lastYear = widget.lastDate.year;
    final marks = List<int>.filled(13, 0);
    final counts = List<int>.filled(13, 0);
    for (final day in _selection) {
      if (day.year != _focusedYear) continue;
      marks[day.month] |= 1 << (day.day - 1);
      counts[day.month]++;
    }
    final tileBackground = colorScheme.surfaceContainerHigh;
    final unmarked = colorScheme.outline.withValues(
      alpha: MonthDotMatrix.unmarkedAlpha,
    );
    final outside = colorScheme.outline.withValues(
      alpha: MonthDotMatrix.outsideAlpha,
    );
    final labelFormat = DateFormat.yMMM(l10n.localeName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.datePickerPreviousYear,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _focusedYear > firstYear
                    ? () => setState(() => _focusedYear--)
                    : null,
              ),
              SizedBox(
                width: 88,
                child: Text(
                  '$_focusedYear',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.datePickerNextYear,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _focusedYear < lastYear
                    ? () => setState(() => _focusedYear++)
                    : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            gridDelegate: YearMonthTile.gridDelegate,
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final first = DateTime.utc(_focusedYear, month, 1);
              final daysInMonth = DateTime.utc(_focusedYear, month + 1, 0).day;
              final count = counts[month];
              final label = labelFormat.format(first);
              return YearMonthTile(
                label: label,
                count: '$count',
                countColor: count > 0 ? accent : colorScheme.onSurfaceVariant,
                semanticsLabel:
                    '$label, ${l10n.datePickerSelectedCount(count)}',
                background: tileBackground,
                onTap: () => _showMonthOf(first),
                matrix: MonthDotMatrix(
                  daysInMonth: daysInMonth,
                  firstWeekdayColumn: weekdayColumnOf(
                    first,
                    _appearance.weekStart,
                  ),
                  markedMask: marks[month],
                  missedMask: 0,
                  windowMask: (1 << daysInMonth) - 1,
                  todayIndex: today.year == _focusedYear && today.month == month
                      ? today.day - 1
                      : null,
                  markedColor: accent,
                  missedColor: accent,
                  unmarkedColor: unmarked,
                  outsideColor: outside,
                  todayColor: accent,
                  backgroundColor: tileBackground,
                  outlineColor: colorScheme.outline,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Every picked date in order, grouped by month, a ✕ each. Past dates read
  /// muted and today in the accent; a row tap opens its month on the grid.
  Widget _buildList(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    List<DateTime> sorted,
    DateTime today,
  ) {
    if (sorted.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.datePickerListEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final monthFormat = DateFormat.yMMMM(l10n.localeName);
    final dayFormat = DateFormat.MMMEd(l10n.localeName);
    final months = <List<DateTime>>[];
    final firstIndex = <int>[];
    for (var i = 0; i < sorted.length; i++) {
      final day = sorted[i];
      final open = months.isEmpty ? null : months.last.first;
      if (open == null || open.year != day.year || open.month != day.month) {
        months.add([day]);
        firstIndex.add(i);
      } else {
        months.last.add(day);
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final days = months[index];
        final offset = firstIndex[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormSectionLabel(text: monthFormat.format(days.first)),
            FormRowGroup(
              children: [
                for (var i = 0; i < days.length; i++)
                  _listRow(
                    l10n,
                    colorScheme,
                    dayFormat,
                    days[i],
                    position: offset + i + 1,
                    count: sorted.length,
                    today: today,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _listRow(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    DateFormat dayFormat,
    DateTime day, {
    required int position,
    required int count,
    required DateTime today,
  }) {
    final Color? labelColor;
    if (day == today) {
      labelColor = colorScheme.primary;
    } else if (day.isBefore(today)) {
      labelColor = colorScheme.onSurfaceVariant;
    } else {
      labelColor = null;
    }
    return FormPickerRow(
      label: dayFormat.format(day),
      value: l10n.datePickerListIndex(position, count),
      labelColor: labelColor,
      dividerIndent: FormMetrics.dividerIndentPlain,
      onTap: () => _showMonthOf(day),
      trailingButton: FormTrailingButton(
        icon: Icons.close_rounded,
        tooltip: l10n.eventRemoveDate,
        onPressed: () => setState(() => _selection.remove(day)),
      ),
    );
  }

  /// The repeat action, and the panel it expands into: a unit, a count, a
  /// caption saying exactly what would be added, and Add. The footer owns the
  /// bottom clearance in multi mode, since it is the element on that edge.
  Widget _buildFooter(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomClearance,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 8 + bottomClearance),
      child: FormRowGroup(
        trailingGap: false,
        children: [
          if (_repeatOpen)
            _buildRepeatPanel(l10n, theme, colorScheme)
          else
            FormActionRow(
              glyph: Icons.repeat_rounded,
              label: l10n.datePickerRepeatPicked,
              onTap: _selection.isEmpty
                  ? null
                  : () => setState(() => _repeatOpen = true),
            ),
        ],
      ),
    );
  }

  Widget _buildRepeatPanel(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final preview = DateStamp.project(
      _selection,
      _repeatUnit,
      _repeatTimes,
      lastDate: widget.lastDate,
    );
    final skipped = preview.skipped > 0
        ? l10n.datePickerRepeatSkipped(preview.skipped)
        : null;
    final String caption;
    if (preview.isEmpty) {
      caption = skipped == null
          ? l10n.datePickerRepeatNothing
          : '${l10n.datePickerRepeatNothing} · $skipped';
    } else {
      final adds = l10n.datePickerRepeatAdds(
        preview.added.length,
        DateFormat.yMMMd(l10n.localeName).format(preview.last!),
      );
      caption = skipped == null ? adds : '$adds · $skipped';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<DateStampUnit>(
            segments: [
              for (final unit in DateStampUnit.values)
                ButtonSegment<DateStampUnit>(
                  value: unit,
                  label: Text(
                    _unitLabel(l10n, unit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            selected: {_repeatUnit},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _repeatUnit = selection.first),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.datePickerRepeatTimes,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              IconButton(
                tooltip: l10n.datePickerRepeatFewer,
                icon: const Icon(Icons.remove_rounded),
                onPressed: _repeatTimes > DateStamp.minTimes
                    ? () => setState(() => _repeatTimes--)
                    : null,
              ),
              SizedBox(
                width: 96,
                child: Text(
                  l10n.datePickerRepeatTimesValue(_repeatTimes),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.datePickerRepeatMore,
                icon: const Icon(Icons.add_rounded),
                onPressed: _repeatTimes < DateStamp.maxTimes
                    ? () => setState(() => _repeatTimes++)
                    : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: preview.isEmpty
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _repeatOpen = false),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: preview.isEmpty ? null : () => _applyRepeat(preview),
                child: Text(l10n.datePickerRepeatApply(preview.added.length)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _unitLabel(AppLocalizations l10n, DateStampUnit unit) {
    return switch (unit) {
      DateStampUnit.week => l10n.datePickerRepeatWeek,
      DateStampUnit.month => l10n.datePickerRepeatMonth,
      DateStampUnit.year => l10n.datePickerRepeatYear,
    };
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
