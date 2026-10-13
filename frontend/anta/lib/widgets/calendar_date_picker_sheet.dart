import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_weekend.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/date_range.dart';
import '../utils/calendar_days_of_week.dart';
import '../utils/calendar_week_start.dart';
import '../utils/date_span_label.dart';
import '../utils/date_stamp.dart';
import 'agenda_period_nav.dart';
import 'automation_id.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'month_dot_matrix.dart';
import 'month_year_picker_sheet.dart';
import 'year_month_tile.dart';

/// How many days a single [CalendarDatePickerSheet] pass may return.
/// [range] returns one contiguous span — the overview's period and the
/// agenda's custom range — rather than a set of separate days.
enum CalendarDatePickerMode { single, multi, range }

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

  /// The span range mode opens on (date-only UTC), or null to open with no
  /// start. Kept apart from [initialSelection]: a span is two ends, not a
  /// set, and the set's modes never read it.
  final DateRange? initialRange;

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
    this.initialRange,
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
    final picked = await _show<Set<DateTime>>(
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
    final picked = await _show<Set<DateTime>>(
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

  /// Picks one span of days on the grid. Returns null when dismissed; a
  /// start confirmed without an end comes back as that one day.
  static Future<DateRange?> pickRange(
    BuildContext context, {
    required DateRange? initialRange,
    required DateTime firstDate,
    required DateTime lastDate,
    required CalendarAppearance appearance,
  }) {
    final first = _dateOnly(firstDate);
    final last = _dateOnly(lastDate);
    // A span reaching past the bounds — a rolling period older than the
    // events — opens on the part of it the grid can show (review 8).
    DateTime bounded(DateTime day) {
      final date = _dateOnly(day);
      if (date.isBefore(first)) return first;
      if (date.isAfter(last)) return last;
      return date;
    }

    return _show<DateRange>(
      context,
      mode: CalendarDatePickerMode.range,
      initialSelection: const {},
      initialRange: initialRange == null
          ? null
          : (
              start: bounded(initialRange.start),
              end: bounded(initialRange.end),
            ),
      firstDate: first,
      lastDate: last,
      appearance: appearance,
    );
  }

  /// "4 dates · Sep 25 – Oct 16, 2026" — the one grammar for reading a date
  /// set back, shared with the editor's bundled Dates row. [sorted] must be
  /// ascending; both years are named when the span crosses one.
  static String summaryLabel(AppLocalizations l10n, List<DateTime> sorted) {
    if (sorted.isEmpty) return l10n.datePickerSelectedCount(0);
    final localeName = l10n.localeName;
    final count = l10n.recurrenceSpecificDates(sorted.length);
    if (sorted.length == 1) {
      return l10n.eventDatesSummary(
        count,
        DateFormat.yMMMEd(localeName).format(sorted.first),
      );
    }
    return l10n.eventDatesSummary(
      count,
      dateSpanLabel(l10n, sorted.first, sorted.last),
    );
  }

  /// The bundled Dates row's two-line value — the count and span, then the
  /// next date and how many are still ahead of [today] — shared by the
  /// editor and the detail sheet so the set reads back the same way on both
  /// and neither needs the picker open to say it.
  static String datesValue(
    AppLocalizations l10n,
    List<DateTime> sorted,
    DateTime today,
  ) {
    final summary = summaryLabel(l10n, sorted);
    final ahead = sorted.where((d) => !d.isBefore(today)).toList();
    if (ahead.isEmpty) return '$summary\n${l10n.eventDatesAllPast}';
    final next = l10n.eventDatesNext(
      DateFormat.MMMEd(l10n.localeName).format(ahead.first),
    );
    return '$summary\n$next · ${l10n.eventDatesAhead(ahead.length, sorted.length)}';
  }

  /// One route for every mode; [T] is what the mode answers with — a set of
  /// days, or a [DateRange] in range mode.
  static Future<T?> _show<T>(
    BuildContext context, {
    required CalendarDatePickerMode mode,
    required Set<DateTime> initialSelection,
    required DateTime firstDate,
    required DateTime lastDate,
    required CalendarAppearance appearance,
    PickerDayLoad? dayLoad,
    bool allowEmpty = false,
    CalendarDatePickerView initialView = CalendarDatePickerView.month,
    DateRange? initialRange,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      // The form sheet's fixed box rather than a content-tall sub-sheet: the
      // body fills (a month grid, a year of tiles, a list), and a sheet that
      // changed height between Month, Year and List would move under the
      // finger.
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: CalendarDatePickerSheet(
          mode: mode,
          initialSelection: initialSelection,
          firstDate: firstDate,
          lastDate: lastDate,
          appearance: appearance,
          dayLoad: dayLoad,
          allowEmpty: allowEmpty,
          initialView: initialView,
          initialRange: initialRange,
        ),
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

  /// Range mode's draft (date-only UTC): no start, a start alone, or both
  /// ends with [_rangeEnd] on or after [_rangeStart].
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  CalendarAppearance get _appearance => widget.appearance;

  bool get _isMulti => widget.mode == CalendarDatePickerMode.multi;

  bool get _isRange => widget.mode == CalendarDatePickerMode.range;

  List<DateTime> get _sortedSelection => _selection.toList()..sort();

  @override
  void initState() {
    super.initState();
    _selection = {...widget.initialSelection};
    _rangeStart = widget.initialRange?.start;
    _rangeEnd = widget.initialRange?.end;
    final anchor =
        _rangeStart ??
        (_selection.isEmpty
            ? CalendarDatePickerSheet._dateOnly(DateTime.now())
            : (_selection.toList()..sort()).first);
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

  /// Pops [result] — a set of days, or a [DateRange] in range mode.
  void _answer(Object? result) {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop(result);
  }

  /// Range mode's Apply: the draft, a start alone standing for its one day.
  void _answerRange() {
    final start = _rangeStart;
    if (start == null) return;
    _answer((start: start, end: _rangeEnd ?? start));
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

  bool _isSelected(DateTime day) {
    final date = CalendarDatePickerSheet._dateOnly(day);
    if (_isRange) return date == _rangeStart || date == _rangeEnd;
    return _selection.contains(date);
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    final day = CalendarDatePickerSheet._dateOnly(selectedDay);
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) return;
    if (widget.mode == CalendarDatePickerMode.single) {
      _answer(<DateTime>{day});
      return;
    }
    setState(() {
      _focusedDay = focusedDay;
      if (_isRange) {
        _pickRangeEnds(day, day);
      } else if (!_selection.remove(day)) {
        _selection.add(day);
      }
    });
  }

  /// The day grid's tap rule in range mode: with no start, or with both ends
  /// set, the tap starts a new span on [first] alone; with a start alone, a
  /// tap on or after it ends the span at [last], one before it restarts the
  /// span on [first].
  void _pickRangeEnds(DateTime first, DateTime last) {
    final start = _rangeStart;
    if (start == null || _rangeEnd != null) {
      _rangeStart = first;
      _rangeEnd = first == last ? null : last;
    } else if (last.isBefore(start)) {
      _rangeStart = first;
      _rangeEnd = null;
    } else {
      _rangeEnd = last;
    }
  }

  /// A year tile in range mode picks in whole months: a month after the
  /// span's end extends the span to that month's last day, keeping the start;
  /// any other month — before the start, inside the span, or with no span
  /// yet — becomes the span on its own. January then December is a whole
  /// year in two taps; the grid is a Month tap away for the days.
  void _pickRangeMonth(DateTime firstOfMonth) {
    final last = DateTime.utc(firstOfMonth.year, firstOfMonth.month + 1, 0);
    if (last.isBefore(widget.firstDate) ||
        firstOfMonth.isAfter(widget.lastDate)) {
      return;
    }
    setState(() {
      final start = _rangeStart;
      final end = _rangeEnd ?? start;
      if (start != null && end != null && firstOfMonth.isAfter(end)) {
        _rangeEnd = _clamp(last);
      } else {
        _rangeStart = _clamp(firstOfMonth);
        _rangeEnd = _clamp(last);
      }
      _focusedDay = _clamp(firstOfMonth);
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
    final isRange = _isRange;
    final accent = _appearance.accentOr(colorScheme.primary);
    final now = DateTime.now();
    final today = CalendarDatePickerSheet._dateOnly(now);
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar. The clearance rides whichever element actually sits on that edge —
    // the multi-mode footer when there is one, the scroll view or the year
    // grid otherwise — and never the whole body: the sheet's box is a fixed
    // fraction of the screen and does not shrink for the keyboard, so padding
    // the body subtracts the inset from the content and a tall inset collapses
    // the Column to nothing, leaving a blank sheet that hit-tests nothing.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    // The list is the set's review; a span has nothing to list.
    final views = isRange
        ? const [CalendarDatePickerView.month, CalendarDatePickerView.year]
        : CalendarDatePickerView.values;
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
        bottomPadding: isMulti
            ? FormMetrics.yearViewBottomGap
            : FormMetrics.yearViewBottomGap + bottomClearance,
      ),
      CalendarDatePickerView.list => _buildList(
        l10n,
        theme,
        colorScheme,
        sorted,
        today,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.datePickerCancel,
          onLeading: () => _answer(null),
          title: switch (widget.mode) {
            CalendarDatePickerMode.single => l10n.datePickerSingleTitle,
            CalendarDatePickerMode.multi => l10n.datePickerMultiTitle,
            CalendarDatePickerMode.range => l10n.overviewPeriod,
          },
          trailingInset: FormMetrics.headerActionInset,
          // Single mode answers on the day tap and has nothing to confirm.
          trailing: switch (widget.mode) {
            CalendarDatePickerMode.single => const SizedBox.shrink(),
            CalendarDatePickerMode.multi => FormHeaderTextButton(
              label: l10n.save,
              identifier: SemanticsIds.datePickerSave,
              onPressed: _selection.isEmpty && !widget.allowEmpty
                  ? null
                  : () => _answer({..._selection}),
            ),
            CalendarDatePickerMode.range => FormHeaderTextButton(
              label: l10n.datePickerApply,
              identifier: SemanticsIds.datePickerSave,
              onPressed: _rangeStart == null ? null : _answerRange,
            ),
          },
        ),
        if (isMulti || isRange) ...[
          if (isMulti)
            _buildSummary(l10n, theme, colorScheme, sorted)
          else
            _buildRangeSummary(l10n, theme, colorScheme),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedButton<CalendarDatePickerView>(
              segments: [
                for (final view in views)
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
    );
  }

  /// The tallest of [year]'s twelve month titles in [style] within
  /// [maxWidth], at the ambient text scale: the height the grid's title box
  /// reserves so the navigation row is one height for the whole year
  /// (`docs/calendar-language-tier-1-roadmap.md`, D24 — "size the dependent
  /// area with an invisible template"). Twelve `TextPainter` layouts per
  /// header build, beside the forty-two cells the grid lays out anyway.
  double _monthTitleHeight(
    BuildContext context,
    DateFormat format,
    int year,
    TextStyle? style,
    double maxWidth,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var height = 0.0;
    for (var month = DateTime.january; month <= DateTime.december; month++) {
      final painter = TextPainter(
        text: TextSpan(
          text: format.format(DateTime(year, month)),
          style: style,
        ),
        textDirection: direction,
        textScaler: scaler,
        maxLines: FormMetrics.periodTitleMaxLines,
      )..layout(maxWidth: maxWidth);
      if (painter.height > height) height = painter.height;
      painter.dispose();
    }
    return height;
  }

  /// The Today button in the navigation row of the month grid and the year
  /// view — `AgendaPeriodNav`'s slot, fixed so the title never shifts.
  /// Available in both modes: a single-date pick can wander months too, and
  /// there was no way back without swiping. One id serves both views, which
  /// are never mounted at once; the list view has no Today.
  Widget _todaySlot(AppLocalizations l10n) {
    return SizedBox(
      width: AgendaPeriodNav.slot,
      child: AutomationId(
        identifier: SemanticsIds.datePickerToday,
        child: IconButton(
          tooltip: l10n.datePickerToday,
          icon: const Icon(Icons.today_rounded),
          onPressed: _jumpToToday,
        ),
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

  /// Range mode's line in the summary's slot: the span and its length, or
  /// the prompt while there is no start. The slot is always two lines tall,
  /// so a span that wraps where the prompt did not never moves the grid.
  Widget _buildRangeSummary(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final start = _rangeStart;
    final String text;
    if (start == null) {
      text = l10n.datePickerRangeNone;
    } else {
      final end = _rangeEnd ?? start;
      final span = end == start
          ? DateFormat.yMMMd(l10n.localeName).format(start)
          : dateSpanLabel(l10n, start, end);
      final days = end.difference(start).inDays + 1;
      text = '$span · ${l10n.upcomingPeriodDays(days)}';
    }
    return Padding(
      padding: FormMetrics.rangeSummaryPadding,
      child: FormCaptionSlot(
        candidates: [Text('\n', style: style, maxLines: 2)],
        child: Text(
          text,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
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
        daysOfWeekHeight: CalendarDaysOfWeek.height,
        daysOfWeekStyle: CalendarDaysOfWeek.style(
          theme,
          highlightWeekends: _appearance.highlightWeekends,
        ),
        locale: l10n.localeName,
        availableGestures: AvailableGestures.horizontalSwipe,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          // The package pads its header 8 dp above and below two 48 dp
          // chevrons, a 64 dp row where `AgendaPeriodNav`'s is 48, and
          // margins each chevron 8 dp a side, 64 wide where the nav's stock
          // buttons are 48; both zero, so ‹ title [today] › here is the same
          // row as everywhere else — and the 32 dp the margins gave back is
          // what "September" needs to sit on one line at 200 % on a 360 dp
          // phone, so the title wraps to "September / 2026" and not mid-word.
          headerPadding: EdgeInsets.zero,
          leftChevronMargin: EdgeInsets.zero,
          rightChevronMargin: EdgeInsets.zero,
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
            final format = DateFormat.yMMMM(l10n.localeName);
            final title = format.format(day);
            final titleStyle = theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            );
            // The grid's own chevrons flank this row, so it reads
            // ‹ title [today] › like `AgendaPeriodNav`.
            return Row(
              children: [
                Expanded(
                  child: Center(
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
                                // The title may take two lines rather than
                                // drop the year ("Septem…" at 200 %), and the
                                // box it sits in is as tall as the year's
                                // tallest month title at this width — so
                                // paging from "Juli 2026" to "September
                                // 2026" never grows the row and moves the
                                // grid under the finger. The builder's own
                                // constraints are exactly the text's, which
                                // is why the measure happens here and not
                                // outside the row.
                                child: LayoutBuilder(
                                  builder: (context, constraints) => SizedBox(
                                    height: _monthTitleHeight(
                                      context,
                                      format,
                                      day.year,
                                      titleStyle,
                                      constraints.maxWidth,
                                    ),
                                    child: Center(
                                      widthFactor: 1,
                                      child: Text(
                                        title,
                                        style: titleStyle,
                                        textAlign: TextAlign.center,
                                        softWrap: true,
                                        maxLines:
                                            FormMetrics.periodTitleMaxLines,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
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
                  ),
                ),
                _todaySlot(l10n),
              ],
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
  /// tile opens its month on the grid. In range mode a tile picks its whole
  /// month instead ([_pickRangeMonth]): a past year is then two taps away
  /// without paging the grid month by month.
  Widget _buildYear(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    Color accent,
    DateTime today, {
    required double bottomPadding,
  }) {
    final firstYear = widget.firstDate.year;
    final lastYear = widget.lastDate.year;
    final marks = List<int>.filled(13, 0);
    final counts = List<int>.filled(13, 0);
    if (_isRange) {
      _markRange(marks, counts);
    } else {
      for (final day in _selection) {
        if (day.year != _focusedYear) continue;
        marks[day.month] |= 1 << (day.day - 1);
        counts[day.month]++;
      }
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
              _todaySlot(l10n),
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
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
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
                onTap: _isRange
                    ? () => _pickRangeMonth(first)
                    : () => _showMonthOf(first),
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
                  dayColors: _isRange
                      ? [
                          for (var day = 0; day < daysInMonth; day++)
                            marks[month] & (1 << day) != 0 ? accent : null,
                        ]
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Marks the span's days of [_focusedYear] month by month — the overlap of
  /// the span with each month, never a walk over every day of a long span.
  void _markRange(List<int> marks, List<int> counts) {
    final start = _rangeStart;
    if (start == null) return;
    final end = _rangeEnd ?? start;
    for (var month = DateTime.january; month <= DateTime.december; month++) {
      final first = DateTime.utc(_focusedYear, month, 1);
      final last = DateTime.utc(_focusedYear, month + 1, 0);
      if (end.isBefore(first) || start.isAfter(last)) continue;
      final from = start.isAfter(first) ? start.day : 1;
      final to = end.isBefore(last) ? end.day : last.day;
      for (var day = from; day <= to; day++) {
        marks[month] |= 1 << (day - 1);
      }
      counts[month] = to - from + 1;
    }
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
  ///
  /// In range mode the span's two ends are the selected chips and every day
  /// of the span between them sits on a band behind the chip.
  Widget _cell(
    DateTime day,
    Color accent, {
    required bool isOutside,
    required DateTime now,
  }) {
    final cell = CalendarDayCell(
      day: day,
      isToday: isSameDay(day, now),
      isSelected: _isSelected(day),
      isOutside: isOutside,
      isWeekend: CalendarWeekend.isWeekend(day),
      todayStyle: _appearance.todayStyle,
      highlightWeekends: _appearance.highlightWeekends,
      accent: accent,
    );
    if (!_isRange) return cell;
    return _rangeBand(day, accent, isOutside: isOutside, cell: cell);
  }

  /// The span's band under [cell]: the accent at the avatar's alpha, in two
  /// halves so it runs from an end's centre outwards and is continuous from
  /// cell to cell along a row. Square inside a row; capped only on the row's
  /// outer edges, where the span leaves it — an end's own outer side is the
  /// chip's circle.
  Widget _rangeBand(
    DateTime day,
    Color accent, {
    required bool isOutside,
    required Widget cell,
  }) {
    final start = _rangeStart;
    final end = _rangeEnd;
    if (start == null || end == null || end == start) return cell;
    final date = CalendarDatePickerSheet._dateOnly(day);
    if (date.isBefore(start) || date.isAfter(end)) return cell;
    final column = weekdayColumnOf(date, _appearance.weekStart);
    final band = accent.withValues(
      alpha:
          EventAvatar.backgroundAlpha *
          (isOutside ? CalendarDayCell.outsideAlpha : 1),
    );
    const cap = Radius.circular(CalendarDayCell.chipSize / 2);
    Widget half({required bool painted, required BorderRadius radius}) {
      return Expanded(
        child: painted
            ? DecoratedBox(
                decoration: BoxDecoration(color: band, borderRadius: radius),
              )
            : const SizedBox.shrink(),
      );
    }

    return Stack(
      children: [
        Positioned(
          top: CalendarDayCell.chipTop,
          height: CalendarDayCell.chipSize,
          left: 0,
          right: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              half(
                painted: date != start,
                radius: column == 0
                    ? const BorderRadius.horizontal(left: cap)
                    : BorderRadius.zero,
              ),
              half(
                painted: date != end,
                radius: column == DateTime.daysPerWeek - 1
                    ? const BorderRadius.horizontal(right: cap)
                    : BorderRadius.zero,
              ),
            ],
          ),
        ),
        cell,
      ],
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
