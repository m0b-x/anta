import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/calendar_bounds.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/agenda_month_store.dart';
import 'agenda_day_list_rows.dart';
import 'agenda_list_view.dart';
import 'agenda_month_grid.dart';
import 'agenda_period_nav.dart';
import 'agenda_year_grid.dart';
import 'agenda_year_pager.dart';
import 'month_year_picker_sheet.dart';

/// Drill-down behind an agenda summary card: every entry the card stands for,
/// in one of three presentations.
///
/// Two time scopes live here, and keeping them apart is what makes every
/// number on screen explainable:
///
/// * The **window** — what the card counts — backs list mode and the year
///   overview's default *Upcoming* tiles. Those read `AgendaDayListIndex` and
///   nothing else.
/// * **Calendar months** — complete months, past days included — back month
///   mode and the year overview's *Calendar year* pages, swiped or paged
///   year by year inside [yearBounds]. Those read the [AgendaMonthStore] and
///   nothing else, including for months the window overlaps, so a month
///   always shows all of itself rather than the window's slice of it.
///
/// Entries for the window arrive pre-resolved in [AgendaDayList] — no
/// `PublicHolidays`, no `FastingCalendar`, no `EventSummaryProvider`. Months
/// outside it come from [resolve] (rows) and [resolveMarks] (a year page's
/// tiles), caller-built closures applying exactly the card's own filters,
/// called **on navigation only** and cached for the life of the sheet. Only
/// its own chrome is localized here.
class AgendaDayListSheet extends StatefulWidget {
  final AgendaDayList list;

  /// Rows for a range the card never counted, resolved with the card's own
  /// filters. Called on navigation, never while building.
  final AgendaDayListResolver resolve;

  /// The marks-only twin of [resolve] behind the year pages. Optional: without
  /// it a page is folded from resolved rows.
  final AgendaDayMarkResolver? resolveMarks;

  /// The years the calendar-year scope may page to. Defaults to the whole
  /// navigable calendar; the agenda passes the years its events can be in.
  final AgendaYearBounds? yearBounds;

  /// Look & feel of the mini month calendar, passed down like every other
  /// calendar surface rather than re-read.
  final CalendarAppearance appearance;

  /// Date-only UTC today, resolved once by the caller.
  final DateTime today;

  /// The agenda window the card summarized. The index extends it to cover a
  /// stray entry rather than dropping one.
  final DateTime windowStart;
  final DateTime windowEnd;

  final AgendaDayListMode initialMode;

  /// Fired when the viewer picks a mode from the segmented button, so the
  /// panel can persist it. Drilling into a month from the year overview is a
  /// navigation step, not a choice of presentation, and does not fire.
  final ValueChanged<AgendaDayListMode>? onModeChanged;

  /// The app's haptic setting, for the year and month jumps.
  final bool hapticFeedback;

  const AgendaDayListSheet({
    super.key,
    required this.list,
    required this.resolve,
    this.resolveMarks,
    this.yearBounds,
    required this.appearance,
    required this.today,
    required this.windowStart,
    required this.windowEnd,
    this.initialMode = AgendaDayListMode.list,
    this.onModeChanged,
    this.hapticFeedback = false,
  });

  /// Resolves to what the viewer picked, or null when dismissed.
  static Future<AgendaDayListResult?> show(
    BuildContext context,
    AgendaDayList list, {
    required AgendaDayListResolver resolve,
    AgendaDayMarkResolver? resolveMarks,
    AgendaYearBounds? yearBounds,
    required CalendarAppearance appearance,
    required DateTime today,
    required DateTime windowStart,
    required DateTime windowEnd,
    AgendaDayListMode initialMode = AgendaDayListMode.list,
    ValueChanged<AgendaDayListMode>? onModeChanged,
    bool hapticFeedback = false,
  }) {
    return showModalBottomSheet<AgendaDayListResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: AgendaDayListSheet(
          list: list,
          resolve: resolve,
          resolveMarks: resolveMarks,
          yearBounds: yearBounds,
          appearance: appearance,
          today: today,
          windowStart: windowStart,
          windowEnd: windowEnd,
          initialMode: initialMode,
          onModeChanged: onModeChanged,
          hapticFeedback: hapticFeedback,
        ),
      ),
    );
  }

  @override
  State<AgendaDayListSheet> createState() => _AgendaDayListSheetState();
}

class _AgendaDayListSheetState extends State<AgendaDayListSheet> {
  late final AgendaDayListIndex _index;
  late final AgendaMonthStore _store;
  late final AgendaYearBounds _years;

  late AgendaDayListMode _mode;
  late DateTime _month;
  late AgendaDayListMonth _monthBucket;
  DateTime? _selectedDay;
  bool _cameFromYear = false;
  AgendaDayListYearScope _yearScope = AgendaDayListYearScope.upcoming;

  /// The calendar year the year scope shows; opens on today's.
  late int _year;
  late PageController _yearPager;
  final Map<int, List<AgendaYearTile>> _tilesByYear = {};
  int _yearKept = 0;
  int _yearMissed = 0;
  DateTime? _highlightMonth;
  int _highlightToken = 0;
  Timer? _prewarm;

  static const double _sectionHeaderHeight = 40;
  static const double _headerSlot = AgendaPeriodNav.slot;
  static const Duration _pageDuration = Duration(milliseconds: 260);
  static const Duration _prewarmDelay = Duration(milliseconds: 250);

  /// How far month mode may page: the calendar's whole navigable domain, so
  /// a tile of any year opens its month.
  static final DateTime _firstMonth = AgendaMonthStore.monthOf(
    CalendarBounds.earliest,
  );
  static final DateTime _lastMonth = AgendaMonthStore.monthOf(
    CalendarBounds.latest,
  );

  final ScrollController _monthScroll = ScrollController();

  List<AgendaDayListRow> _rows = const [];
  List<AgendaYearTile> _windowTiles = const [];

  @override
  void initState() {
    super.initState();
    _index = AgendaDayListIndex.build(
      widget.list.entries,
      windowStart: widget.windowStart,
      windowEnd: widget.windowEnd,
    );
    _store = AgendaMonthStore(
      resolve: widget.resolve,
      resolveMarks: widget.resolveMarks,
      maxBars: AgendaMonthGrid.maxBarsFor(widget.appearance),
    );
    _years =
        widget.yearBounds ??
        (first: CalendarBounds.earliest.year, last: CalendarBounds.latest.year);
    _mode = widget.initialMode;
    _year = widget.today.year.clamp(_years.first, _years.last);
    _yearPager = PageController(
      initialPage: AgendaYearPager.indexOf(_year, _years.first),
    );
    _month = _initialMonth();
    _monthBucket = AgendaDayListMonth.build(_month, const []);
    if (_mode == AgendaDayListMode.month) _store.ensure([_month]);
    _recompute();
  }

  @override
  void dispose() {
    _prewarm?.cancel();
    _yearPager.dispose();
    _monthScroll.dispose();
    super.dispose();
  }

  /// The month a viewer who asked for month mode should land on: today's,
  /// pulled into the **window** first and only then into the browsable
  /// bounds — the window's own edge is the nearest month the card actually
  /// stands for.
  DateTime _initialMonth() {
    final todayMonth = AgendaMonthStore.monthOf(widget.today);
    final order = AgendaMonthStore.monthOrder(todayMonth);
    final first = _index.months.first;
    final last = _index.months.last;
    if (order < AgendaMonthStore.monthOrder(first)) return _clampMonth(first);
    if (order > AgendaMonthStore.monthOrder(last)) return _clampMonth(last);
    return _clampMonth(todayMonth);
  }

  DateTime _clampMonth(DateTime month) {
    final order = AgendaMonthStore.monthOrder(month);
    if (order <= AgendaMonthStore.monthOrder(_firstMonth)) return _firstMonth;
    if (order >= AgendaMonthStore.monthOrder(_lastMonth)) return _lastMonth;
    return DateTime.utc(month.year, month.month, 1);
  }

  /// Rebuilds everything the current (mode, month, scope, year, selected day)
  /// draws, so a frame never folds the entries again.
  void _recompute() {
    switch (_mode) {
      case AgendaDayListMode.list:
        _rows = buildAgendaDayListRows(
          _index.days,
          _index.entriesOn,
          groupByDay: true,
          withMonths: true,
          keptCountOf: _index.keptCountForDay,
        );
        _windowTiles = const [];
      case AgendaDayListMode.month:
        final bucket = _store.monthFor(_month);
        _monthBucket = bucket;
        final selected = _selectedDay;
        _rows = buildAgendaDayListRows(
          selected != null ? [selected] : bucket.days,
          bucket.entriesOn,
          groupByDay: selected == null,
          withMonths: false,
          keptCountOf: bucket.keptCountForDay,
        );
        _windowTiles = const [];
      case AgendaDayListMode.year:
        _rows = const [];
        switch (_yearScope) {
          case AgendaDayListYearScope.upcoming:
            _windowTiles = [
              for (final month in _index.months)
                AgendaYearTile.ofWindow(_index, month),
            ];
          case AgendaDayListYearScope.calendarYear:
            _windowTiles = const [];
            _tallyYear(_year);
        }
    }
  }

  /// The year's tiles, folded from marks and kept for the pager: a page that
  /// slides in under a finger reads them without folding anything. The whole
  /// year is ensured first, so an unresolved year is one resolver call.
  List<AgendaYearTile> _tilesFor(int year) {
    final cached = _tilesByYear[year];
    if (cached != null) return cached;
    final months = AgendaMonthStore.monthsOfYear(year);
    _store.ensureTallies(months);
    return _tilesByYear[year] = [
      for (final month in months) AgendaYearTile.ofTally(_store.tallyFor(month)),
    ];
  }

  void _tallyYear(int year) {
    var kept = 0;
    var missed = 0;
    for (final tile in _tilesFor(year)) {
      kept += tile.count;
      missed += tile.missedCount;
    }
    _yearKept = kept;
    _yearMissed = missed;
  }

  /// Warms the neighbouring years once the page has settled, so the next
  /// swipe or chevron finds its tiles ready. Cache-only work: nothing to
  /// repaint.
  void _schedulePrewarm() {
    _prewarm?.cancel();
    _prewarm = Timer(_prewarmDelay, () {
      if (!mounted || _mode != AgendaDayListMode.year) return;
      if (_yearScope != AgendaDayListYearScope.calendarYear) return;
      for (final year in [_year - 1, _year + 1]) {
        if (year < _years.first || year > _years.last) continue;
        _tilesFor(year);
      }
    });
  }

  void _click() {
    if (widget.hapticFeedback) HapticFeedback.selectionClick();
  }

  void _selectMode(AgendaDayListMode mode) {
    if (mode == _mode) return;
    final month = mode == AgendaDayListMode.month ? _initialMonth() : _month;
    if (mode == AgendaDayListMode.month) _store.ensure([month]);
    setState(() {
      _mode = mode;
      _month = month;
      _cameFromYear = false;
      _selectedDay = null;
      _recompute();
    });
    if (mode == AgendaDayListMode.year) _schedulePrewarm();
    widget.onModeChanged?.call(mode);
  }

  void _selectYearScope(AgendaDayListYearScope scope) {
    if (scope == _yearScope) return;
    setState(() {
      _yearScope = scope;
      _recompute();
    });
    _schedulePrewarm();
  }

  /// A year the pager settled on — a swipe, or the end of an animated jump.
  void _onYearPaged(int year) {
    if (year == _year) return;
    setState(() {
      _year = year;
      _recompute();
    });
    _schedulePrewarm();
  }

  /// Animates the pager to [year]; the page change lands in [_onYearPaged].
  void _goToYear(int year) {
    final target = year.clamp(_years.first, _years.last);
    if (target == _year) return;
    _click();
    if (_yearPager.hasClients) {
      _yearPager.animateToPage(
        AgendaYearPager.indexOf(target, _years.first),
        duration: _pageDuration,
        curve: Curves.easeOutCubic,
      );
    } else {
      _onYearPaged(target);
    }
  }

  /// The jump control behind both period titles: a picked date lands the
  /// year pages on its year with its month flashed, or month mode on its
  /// month.
  Future<void> _pickDate() async {
    final inMonthMode = _mode == AgendaDayListMode.month;
    final initial = inMonthMode
        ? _month
        : DateTime.utc(_year, _year == widget.today.year ? widget.today.month : 1, 1);
    final picked = await MonthYearPickerSheet.show(
      context,
      initialDate: initial,
      firstDate: inMonthMode
          ? CalendarBounds.earliest
          : DateTime.utc(_years.first, 1, 1),
      lastDate: inMonthMode
          ? CalendarBounds.latest
          : DateTime.utc(_years.last, 12, 31),
      accent: widget.appearance.accentOr(Theme.of(context).colorScheme.primary),
    );
    if (picked == null || !mounted) return;
    _click();
    if (inMonthMode) {
      _goToMonth(AgendaMonthStore.monthOf(picked));
      return;
    }
    setState(() {
      _highlightMonth = AgendaMonthStore.monthOf(picked);
      _highlightToken++;
    });
    _goToYear(picked.year);
  }

  void _openMonthFromYear(DateTime month) {
    final target = _clampMonth(month);
    _store.ensure([target]);
    setState(() {
      _mode = AgendaDayListMode.month;
      _month = target;
      _selectedDay = null;
      _cameFromYear = true;
      _recompute();
    });
  }

  void _backToYear() {
    setState(() {
      _mode = AgendaDayListMode.year;
      _cameFromYear = false;
      _selectedDay = null;
      _recompute();
    });
    _schedulePrewarm();
  }

  void _goToMonth(DateTime month) {
    final target = _clampMonth(month);
    if (AgendaMonthStore.monthOrder(target) ==
        AgendaMonthStore.monthOrder(_month)) {
      return;
    }
    _store.ensure([target]);
    setState(() {
      _month = target;
      _selectedDay = null;
      _recompute();
    });
    _scrollMonthToTop();
  }

  void _toggleSelectedDay(DateTime day) {
    if (_monthBucket.countForDay(day) == 0) return;
    setState(() {
      _selectedDay = _selectedDay == day ? null : day;
      _recompute();
    });
    _scrollMonthToTop();
  }

  void _scrollMonthToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _monthScroll.hasClients) _monthScroll.jumpTo(0);
    });
  }

  /// Guards the exit against a second tap landing while the route is still
  /// animating out: a second `pop` would take the page underneath with it.
  bool _popped = false;

  void _popDay(DateTime day) {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop((focusDay: day, edit: null));
  }

  void _popEdit(VoidCallback edit) {
    if (_popped) return;
    _popped = true;
    Navigator.of(context).pop((focusDay: null, edit: edit));
  }

  bool get _showsBack => _mode == AgendaDayListMode.month && _cameFromYear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(l10n, theme, colorScheme),
        // The keyboard inset is read under its own builder, so a frame of the
        // keyboard's dismissal re-lays the body out without rebuilding the
        // header above it.
        Expanded(
          child: Builder(
            builder: (context) {
              final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
              final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
              return _buildBody(
                l10n,
                theme,
                colorScheme,
                viewInsets > viewPadding ? viewInsets : viewPadding,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: _headerSlot,
                height: _headerSlot,
                child: _showsBack
                    ? IconButton(
                        tooltip: l10n.dayListBackToYear,
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: _backToYear,
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.list.title,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.list.subtitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _headerSlot, height: _headerSlot),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<AgendaDayListMode>(
            segments: [
              ButtonSegment<AgendaDayListMode>(
                value: AgendaDayListMode.list,
                icon: const Icon(Icons.format_list_bulleted_rounded),
                label: Text(
                  l10n.dayListModeList,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment<AgendaDayListMode>(
                value: AgendaDayListMode.month,
                icon: const Icon(Icons.calendar_view_month_rounded),
                label: Text(
                  l10n.dayListModeMonth,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment<AgendaDayListMode>(
                value: AgendaDayListMode.year,
                icon: const Icon(Icons.grid_view_rounded),
                label: Text(
                  l10n.dayListModeYear,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _selectMode(selection.first),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomClearance,
  ) {
    switch (_mode) {
      case AgendaDayListMode.list:
        if (_rows.isEmpty) {
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 32, 16, 16 + bottomClearance),
            children: [
              Text(
                l10n.dayListEmptyRange,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(8, 4, 8, 16 + bottomClearance),
          itemCount: _rows.length,
          itemBuilder: (context, index) => _buildRow(index),
        );
      case AgendaDayListMode.month:
        return CustomScrollView(
          controller: _monthScroll,
          slivers: [
            SliverToBoxAdapter(child: _buildMonthNav(l10n)),
            SliverToBoxAdapter(child: _buildMonthGrid()),
            SliverToBoxAdapter(
              child: _buildSectionHeader(l10n, theme, colorScheme),
            ),
            if (_rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    l10n.dayListEmptyMonth,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildRow(index),
                    childCount: _rows.length,
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: 16 + bottomClearance)),
          ],
        );
      case AgendaDayListMode.year:
        return _buildYearBody(l10n, colorScheme, bottomClearance);
    }
  }

  Widget _buildRow(int index) {
    return AgendaDayListRowView(
      rows: _rows,
      index: index,
      today: widget.today,
      onEntryTap: (entry) => _popDay(entry.day),
      onEntryEdit: (entry) => _popEdit(entry.onEdit!),
    );
  }

  Widget _buildMonthNav(AppLocalizations l10n) {
    final order = AgendaMonthStore.monthOrder(_month);
    final todayMonth = AgendaMonthStore.monthOf(widget.today);
    return AgendaPeriodNav(
      title: AgendaListView.monthLabel(l10n.localeName, _month, withYear: true),
      subtitle: agendaDayListCountLabel(
        l10n,
        _monthBucket.keptCount,
        _monthBucket.count - _monthBucket.keptCount,
      ),
      previousTooltip: l10n.dayListPreviousMonth,
      nextTooltip: l10n.dayListNextMonth,
      todayTooltip: l10n.dayListJumpToToday,
      titleTooltip: l10n.monthYearPickerTitle,
      onTitleTap: _pickDate,
      onPrevious: order > AgendaMonthStore.monthOrder(_firstMonth)
          ? () => _goToMonth(DateTime.utc(_month.year, _month.month - 1, 1))
          : null,
      onNext: order < AgendaMonthStore.monthOrder(_lastMonth)
          ? () => _goToMonth(DateTime.utc(_month.year, _month.month + 1, 1))
          : null,
      onToday: order == AgendaMonthStore.monthOrder(todayMonth)
          ? null
          : () => _goToMonth(todayMonth),
    );
  }

  Widget _buildMonthGrid() {
    return AgendaMonthGrid(
      month: _month,
      firstDay: _firstMonth,
      lastDay: DateTime.utc(_lastMonth.year, _lastMonth.month + 1, 0),
      today: widget.today,
      selectedDay: _selectedDay,
      appearance: widget.appearance,
      hasEntry: _store.hasEntry,
      barsFor: (day) => _store.barsFor(day)?[day.day],
      onDaySelected: _toggleSelectedDay,
      onPageChanged: _goToMonth,
    );
  }

  Widget _buildSectionHeader(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final selected = _selectedDay;
    final label = selected == null
        ? AgendaListView.monthLabel(l10n.localeName, _month, withYear: false)
        : AgendaListView.dayHeaderLabel(l10n, selected, widget.today);
    final total = selected == null
        ? _monthBucket.count
        : _monthBucket.countForDay(selected);
    final kept = selected == null
        ? _monthBucket.keptCount
        : _monthBucket.keptCountForDay(selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: SizedBox(
        height: _sectionHeaderHeight,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              agendaDayListCountLabel(l10n, kept, total - kept),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
            Visibility(
              visible: selected != null,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(
                onPressed: selected == null
                    ? null
                    : () => _toggleSelectedDay(selected),
                child: Text(l10n.dayListWholeMonth),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearBody(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    double bottomClearance,
  ) {
    final padding = EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomClearance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<AgendaDayListYearScope>(
            segments: [
              for (final scope in AgendaDayListYearScope.values)
                ButtonSegment<AgendaDayListYearScope>(
                  value: scope,
                  label: Text(
                    _yearScopeLabel(l10n, scope),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            selected: {_yearScope},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                _selectYearScope(selection.first),
          ),
        ),
        if (_yearScope == AgendaDayListYearScope.upcoming)
          Expanded(
            child: AgendaYearGrid(
              tiles: _windowTiles,
              color: widget.list.color,
              appearance: widget.appearance,
              today: widget.today,
              onOpenMonth: _openMonthFromYear,
              padding: padding,
            ),
          )
        else ...[
          AgendaPeriodNav(
            title: '$_year',
            subtitle: agendaDayListCountLabel(l10n, _yearKept, _yearMissed),
            previousTooltip: l10n.datePickerPreviousYear,
            nextTooltip: l10n.datePickerNextYear,
            todayTooltip: l10n.dayListScopeThisYear,
            titleTooltip: l10n.monthYearPickerTitle,
            onTitleTap: _pickDate,
            onPrevious: _year > _years.first
                ? () => _goToYear(_year - 1)
                : null,
            onNext: _year < _years.last ? () => _goToYear(_year + 1) : null,
            onToday: _year == widget.today.year
                ? null
                : () => _goToYear(widget.today.year),
          ),
          Expanded(
            child: AgendaYearPager(
              controller: _yearPager,
              firstYear: _years.first,
              lastYear: _years.last,
              tilesFor: _tilesFor,
              color: widget.list.color,
              appearance: widget.appearance,
              today: widget.today,
              onOpenMonth: _openMonthFromYear,
              onYearChanged: _onYearPaged,
              padding: padding,
              highlightMonth: _highlightMonth,
              highlightToken: _highlightToken,
            ),
          ),
        ],
      ],
    );
  }

  static String _yearScopeLabel(
    AppLocalizations l10n,
    AgendaDayListYearScope scope,
  ) {
    return switch (scope) {
      AgendaDayListYearScope.upcoming => l10n.dayListScopeUpcoming,
      AgendaDayListYearScope.calendarYear => l10n.dayListScopeCalendarYear,
    };
  }
}
