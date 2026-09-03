import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/calendar_colors.dart';
import '../constants/calendar_weekend.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../models/day_bar.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/calendar_week_start.dart';
import '../utils/event_agenda.dart';
import 'agenda_list_view.dart';
import 'calendar_day_bars.dart';
import 'calendar_day_cell.dart';
import 'month_dot_matrix.dart';

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
///   mode and the year overview's *This year* tiles. Those read
///   [_resolvedMonths] and nothing else, including for months the window
///   overlaps, so a month always shows all of itself rather than the window's
///   slice of it.
///
/// Entries for the window arrive pre-resolved in [AgendaDayList] — no
/// `PublicHolidays`, no `FastingCalendar`, no `EventSummaryProvider`. Months
/// outside it come from [resolve], a caller-built closure applying exactly the
/// card's own filters, called **on navigation only** and cached for the life
/// of the sheet: one call per contiguous run of unloaded months, never one per
/// frame. Only its own chrome is localized here.
class AgendaDayListSheet extends StatefulWidget {
  final AgendaDayList list;

  /// Rows for a range the card never counted, resolved with the card's own
  /// filters. Called on navigation, never while building.
  final AgendaDayListResolver resolve;

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

  const AgendaDayListSheet({
    super.key,
    required this.list,
    required this.resolve,
    required this.appearance,
    required this.today,
    required this.windowStart,
    required this.windowEnd,
    this.initialMode = AgendaDayListMode.list,
    this.onModeChanged,
  });

  /// Resolves to what the viewer picked, or null when dismissed.
  static Future<AgendaDayListResult?> show(
    BuildContext context,
    AgendaDayList list, {
    required AgendaDayListResolver resolve,
    required CalendarAppearance appearance,
    required DateTime today,
    required DateTime windowStart,
    required DateTime windowEnd,
    AgendaDayListMode initialMode = AgendaDayListMode.list,
    ValueChanged<AgendaDayListMode>? onModeChanged,
  }) {
    return showModalBottomSheet<AgendaDayListResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        // One height for every mode, so switching presentation never resizes
        // the sheet under the finger that switched it.
        heightFactor: 0.88,
        child: AgendaDayListSheet(
          list: list,
          resolve: resolve,
          appearance: appearance,
          today: today,
          windowStart: windowStart,
          windowEnd: windowEnd,
          initialMode: initialMode,
          onModeChanged: onModeChanged,
        ),
      ),
    );
  }

  @override
  State<AgendaDayListSheet> createState() => _AgendaDayListSheetState();
}

class _AgendaDayListSheetState extends State<AgendaDayListSheet> {
  late final AgendaDayListIndex _index;

  /// Calendar months resolved through `widget.resolve`, keyed
  /// `year * 12 + month - 1`. A month with nothing in it is stored as an empty
  /// bucket rather than left absent, so it is never resolved twice.
  final Map<int, AgendaDayListMonth> _resolvedMonths = {};

  /// How far month mode may page, computed once: a year back from the earlier
  /// of today and the window, forward to the later of the window's end and
  /// December of this year.
  late final DateTime _earliestMonth;
  late final DateTime _latestMonth;

  late AgendaDayListMode _mode;
  late DateTime _month;
  late AgendaDayListMonth _monthBucket;
  DateTime? _selectedDay;
  bool _cameFromYear = false;
  AgendaDayListYearScope _yearScope = AgendaDayListYearScope.upcoming;

  static const double _sectionHeaderHeight = 40;

  /// Side of the square slots that flank the header title and hold the month
  /// nav's today button — a full Material touch target, matching the chevrons
  /// rather than the 40dp a compact `visualDensity` would give.
  static const double _headerSlot = 48;

  final ScrollController _monthScroll = ScrollController();

  List<_DayListRow> _rows = const [];
  List<_YearTile> _yearTiles = const [];

  /// Day bars per resolved month, keyed the same way as [_resolvedMonths] and
  /// filled the moment a month is cached.
  ///
  /// A mid-swipe frame draws cells of the month being left *and* the one being
  /// entered, so the marker builder has to answer for a month that is not
  /// `_month` — reading one pre-folded map twice is what keeps those bars from
  /// vanishing without folding a bucket per cell per frame.
  final Map<int, Map<int, List<DayBar>>> _barsByMonth = {};

  @override
  void initState() {
    super.initState();
    _index = AgendaDayListIndex.build(
      widget.list.entries,
      windowStart: widget.windowStart,
      windowEnd: widget.windowEnd,
    );
    _mode = widget.initialMode;

    final todayMonth = _monthOf(widget.today);
    final firstWindow = _index.months.first;
    final base = _monthOrder(todayMonth) <= _monthOrder(firstWindow)
        ? todayMonth
        : firstWindow;
    _earliestMonth = DateTime.utc(base.year, base.month - 12, 1);
    final december = DateTime.utc(widget.today.year, 12, 1);
    final lastWindow = _index.months.last;
    _latestMonth = _monthOrder(lastWindow) >= _monthOrder(december)
        ? lastWindow
        : december;

    _month = _initialMonth();
    _monthBucket = AgendaDayListMonth.build(_month, const []);
    if (_mode == AgendaDayListMode.month) _ensureMonths([_month]);
    _recompute();
  }

  @override
  void dispose() {
    _monthScroll.dispose();
    super.dispose();
  }

  static DateTime _monthOf(DateTime day) =>
      DateTime.utc(day.year, day.month, 1);

  static int _monthOrder(DateTime month) => month.year * 12 + month.month;

  static int _monthKeyOf(DateTime day) => day.year * 12 + day.month - 1;

  static DateTime _monthFromKey(int key) =>
      DateTime.utc(key ~/ 12, key % 12 + 1, 1);

  static int _fullMonthMask(int daysInMonth) => (1 << daysInMonth) - 1;

  int get _maxBars => widget.appearance.maxDayBars.clamp(1, 3);

  /// The month a viewer who asked for month mode should land on: today's,
  /// pulled into the **window** first and only then into the browsable bounds.
  ///
  /// Clamping straight into the bounds would open a card pinned to 2020 on
  /// today's month — inside the bounds, but a month that card never covered
  /// and where the sheet has nothing to say. The window's own edge is the
  /// nearest month the card actually stands for.
  DateTime _initialMonth() {
    final todayMonth = _monthOf(widget.today);
    final order = _monthOrder(todayMonth);
    final first = _index.months.first;
    final last = _index.months.last;
    if (order < _monthOrder(first)) return _clampMonth(first);
    if (order > _monthOrder(last)) return _clampMonth(last);
    return _clampMonth(todayMonth);
  }

  DateTime _clampMonth(DateTime month) {
    final order = _monthOrder(month);
    if (order <= _monthOrder(_earliestMonth)) return _earliestMonth;
    if (order >= _monthOrder(_latestMonth)) return _latestMonth;
    return DateTime.utc(month.year, month.month, 1);
  }

  List<DateTime> get _calendarYearMonths => [
    for (var month = 1; month <= 12; month++)
      DateTime.utc(widget.today.year, month, 1),
  ];

  /// Resolves every month in [months] that is not cached yet, coalescing
  /// contiguous ones into a single [AgendaDayListResolver] call. Never called
  /// from `build`.
  void _ensureMonths(List<DateTime> months) {
    final missing = <int>[];
    for (final month in months) {
      final key = _monthKeyOf(month);
      if (_resolvedMonths.containsKey(key) || missing.contains(key)) continue;
      missing.add(key);
    }
    if (missing.isEmpty) return;
    missing.sort();
    var runStart = 0;
    for (var i = 1; i <= missing.length; i++) {
      if (i < missing.length && missing[i] == missing[i - 1] + 1) continue;
      _resolveRun(missing.sublist(runStart, i));
      runStart = i;
    }
  }

  void _resolveRun(List<int> keys) {
    final first = _monthFromKey(keys.first);
    final last = _monthFromKey(keys.last);
    final end = DateTime.utc(last.year, last.month + 1, 0);
    // The widest run the sheet ever asks for is one calendar year, and the
    // resolver's contract caps a call at `EventAgenda.maxRangeDays`. Both are
    // debug guards on *this* side of the call, so a future navigation path
    // that coalesced too much would fail here rather than in a scan.
    assert(keys.length <= 12, 'a resolve run may span at most twelve months');
    assert(
      end.difference(first).inDays + 1 <= EventAgenda.maxRangeDays,
      'a resolve run may span at most EventAgenda.maxRangeDays days',
    );
    final entries = widget.resolve(first, end);
    final buckets = <int, List<AgendaDayListEntry>>{};
    for (final entry in entries) {
      (buckets[_monthKeyOf(entry.day)] ??= <AgendaDayListEntry>[]).add(entry);
    }
    assert(
      buckets.keys.every(keys.contains),
      'resolve returned entries outside the requested months',
    );
    for (final key in keys) {
      final bucket = AgendaDayListMonth.build(
        _monthFromKey(key),
        buckets[key] ?? const <AgendaDayListEntry>[],
      );
      _resolvedMonths[key] = bucket;
      _barsByMonth[key] = _buildMonthBars(bucket);
    }
  }

  AgendaDayListMonth _monthFor(DateTime month) {
    final key = _monthKeyOf(month);
    final cached = _resolvedMonths[key];
    if (cached != null) return cached;
    _ensureMonths([month]);
    return _resolvedMonths[key]!;
  }

  /// Rebuilds everything the current (mode, month, scope, selected day) draws,
  /// so a frame never folds the entries again.
  void _recompute() {
    switch (_mode) {
      case AgendaDayListMode.list:
        _rows = _buildRows(
          _index.days,
          _index.entriesOn,
          groupByDay: true,
          withMonths: true,
          keptCountOf: _index.keptCountForDay,
        );
        _yearTiles = const [];
      case AgendaDayListMode.month:
        final bucket = _monthFor(_month);
        _monthBucket = bucket;
        final selected = _selectedDay;
        _rows = _buildRows(
          selected != null ? [selected] : bucket.days,
          bucket.entriesOn,
          groupByDay: selected == null,
          withMonths: false,
          keptCountOf: bucket.keptCountForDay,
        );
        _yearTiles = const [];
      case AgendaDayListMode.year:
        _rows = const [];
        _yearTiles = _buildYearTiles();
    }
  }

  /// [keptCountOf] rather than the row count: a day header prints how many of
  /// the day's entries were **attended**, so a faded missed occurrence is
  /// visible in the list without being counted as one.
  List<_DayListRow> _buildRows(
    List<DateTime> days,
    List<AgendaDayListEntry> Function(DateTime day) entriesOf, {
    required bool groupByDay,
    required bool withMonths,
    required int Function(DateTime day) keptCountOf,
  }) {
    if (days.isEmpty) return const [];
    final rows = <_DayListRow>[];
    final multiMonth =
        withMonths &&
        (days.first.year != days.last.year ||
            days.first.month != days.last.month);
    final crossesYear = days.first.year != days.last.year;
    int? currentMonth;
    for (final day in days) {
      final entries = entriesOf(day);
      if (entries.isEmpty) continue;
      if (multiMonth) {
        final key = day.year * 12 + day.month;
        if (key != currentMonth) {
          currentMonth = key;
          rows.add(
            _MonthHeaderRow(month: _monthOf(day), showYear: crossesYear),
          );
        }
      }
      if (groupByDay) {
        final kept = keptCountOf(day);
        rows.add(
          _DayHeaderRow(day: day, count: kept, missed: entries.length - kept),
        );
      }
      for (final entry in entries) {
        rows.add(_EntryRow(entry: entry));
      }
    }
    return rows;
  }

  /// A missed occurrence's bar carries the same fade the grid gives it
  /// (`day_bars_resolver.dart`), so the mini month and the calendar page say
  /// the same thing about the same day.
  Map<int, List<DayBar>> _buildMonthBars(AgendaDayListMonth bucket) {
    final bars = <int, List<DayBar>>{};
    for (final day in bucket.days) {
      final entries = bucket.entriesOn(day);
      final count = entries.length < _maxBars ? entries.length : _maxBars;
      bars[day.day] = [
        for (var i = 0; i < count; i++)
          DayBar(
            key: 'agendaDayList:$i',
            color: entries[i].missed
                ? entries[i].color.withValues(
                    alpha: CalendarColors.missedEventAlpha,
                  )
                : entries[i].color,
            priority: i,
            semanticLabel: entries[i].title,
          ),
      ];
    }
    return bars;
  }

  /// One tile per month of the active scope. A *This year* tile's window mask
  /// covers every day of its month: a complete month has nothing to fade out.
  ///
  /// `daysInMonth` is folded in here rather than in the grid's item builder:
  /// it is a property of the month, and the builder runs per frame.
  List<_YearTile> _buildYearTiles() {
    switch (_yearScope) {
      case AgendaDayListYearScope.upcoming:
        return [
          for (final month in _index.months)
            _YearTile(
              month: month,
              daysInMonth: DateTime.utc(month.year, month.month + 1, 0).day,
              count: _index.keptCountForMonth(month),
              missedCount:
                  _index.countForMonth(month) - _index.keptCountForMonth(month),
              markedMask: _index.markedMaskForMonth(month),
              missedMask: _index.missedMaskForMonth(month),
              windowMask: _index.windowMaskForMonth(month),
            ),
        ];
      case AgendaDayListYearScope.thisYear:
        return [
          for (final month in _calendarYearMonths)
            if (_monthFor(month) case final bucket)
              _YearTile(
                month: month,
                daysInMonth: bucket.daysInMonth,
                count: bucket.keptCount,
                missedCount: bucket.count - bucket.keptCount,
                markedMask: bucket.markedMask,
                missedMask: bucket.missedMask,
                windowMask: _fullMonthMask(bucket.daysInMonth),
              ),
        ];
    }
  }

  void _selectMode(AgendaDayListMode mode) {
    if (mode == _mode) return;
    final month = mode == AgendaDayListMode.month ? _initialMonth() : _month;
    if (mode == AgendaDayListMode.month) _ensureMonths([month]);
    setState(() {
      _mode = mode;
      _month = month;
      _cameFromYear = false;
      _selectedDay = null;
      _recompute();
    });
    widget.onModeChanged?.call(mode);
  }

  void _selectYearScope(AgendaDayListYearScope scope) {
    if (scope == _yearScope) return;
    if (scope == AgendaDayListYearScope.thisYear) {
      _ensureMonths(_calendarYearMonths);
    }
    setState(() {
      _yearScope = scope;
      _recompute();
    });
  }

  void _openMonthFromYear(DateTime month) {
    final target = _clampMonth(month);
    _ensureMonths([target]);
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
  }

  void _goToMonth(DateTime month) {
    final target = _clampMonth(month);
    if (_monthOrder(target) == _monthOrder(_month)) return;
    _ensureMonths([target]);
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

  void _popDay(DateTime day) =>
      Navigator.of(context).pop((focusDay: day, edit: null));

  void _popEdit(VoidCallback edit) =>
      Navigator.of(context).pop((focusDay: null, edit: edit));

  bool get _showsBack => _mode == AgendaDayListMode.month && _cameFromYear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar — same fix as `CategoryPickerSheet`.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    // No `PopScope`: the back arrow is the only "back to the year overview"
    // affordance, and the barrier, a drag-down and the system back gesture all
    // dismiss the sheet exactly as they do on every sibling sheet. A modal
    // that swallowed one of those to mean "step back inside me" is a surprise
    // nowhere else in the app pays for.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(l10n, theme, colorScheme),
        Expanded(child: _buildBody(l10n, theme, colorScheme, bottomClearance)),
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
              // A full 48x48 slot, reserved in both states: the arrow is a
              // touch target like the month chevrons beside it, and pinning
              // the *height* too is what keeps the row — and so the segmented
              // button under it — from moving when the arrow appears.
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
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(8, 4, 8, 16 + bottomClearance),
          itemCount: _rows.length,
          itemBuilder: (context, index) =>
              _buildRow(l10n, theme, colorScheme, index),
        );
      case AgendaDayListMode.month:
        return CustomScrollView(
          controller: _monthScroll,
          slivers: [
            SliverToBoxAdapter(child: _buildMonthNav(l10n, theme)),
            SliverToBoxAdapter(child: _buildMonthGrid(l10n, theme)),
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
                    (context, index) =>
                        _buildRow(l10n, theme, colorScheme, index),
                    childCount: _rows.length,
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: 16 + bottomClearance)),
          ],
        );
      case AgendaDayListMode.year:
        return _buildYearBody(l10n, theme, colorScheme, bottomClearance);
    }
  }

  Widget _buildRow(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    int index,
  ) {
    final row = _rows[index];
    switch (row) {
      case _MonthHeaderRow(:final month, :final showYear):
        return Padding(
          padding: EdgeInsets.fromLTRB(8, index == 0 ? 0 : 16, 8, 4),
          child: Row(
            children: [
              Text(
                AgendaListView.monthLabel(
                  l10n.localeName,
                  month,
                  withYear: showYear,
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(height: 1, color: colorScheme.outlineVariant),
              ),
            ],
          ),
        );
      case _DayHeaderRow(:final day, :final count, :final missed):
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            index == 0 || _rows[index - 1] is _MonthHeaderRow ? 4 : 16,
            16,
            4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AgendaListView.dayHeaderLabel(l10n, day, widget.today),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _countLabel(l10n, count, missed),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      case _EntryRow(:final entry):
        final onEdit = entry.onEdit;
        final tile = ListTile(
          leading: CircleAvatar(
            backgroundColor: entry.color.withValues(alpha: 0.16),
            foregroundColor: entry.color,
            child: Icon(entry.icon),
          ),
          title: Text(entry.title),
          subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
          trailing: onEdit == null
              ? null
              : IconButton(
                  tooltip: l10n.upcomingEditEvent,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _popEdit(onEdit),
                ),
          onTap: () => _popDay(entry.day),
        );
        // The agenda card this drills into fades a missed row the same way
        // (`_AgendaCard.missed`), and the row stays tappable: "still there,
        // just not the point".
        if (!entry.missed) return tile;
        return Opacity(opacity: CalendarColors.missedEventAlpha, child: tile);
    }
  }

  /// "3 entries" — or "3 entries · 2 missed" where the attendance count alone
  /// would leave the missed ones unaccounted for.
  ///
  /// Every number the sheet prints is a count of what was **attended**; the
  /// missed tally rides alongside it rather than in it.
  String _countLabel(AppLocalizations l10n, int kept, int missed) {
    final label = l10n.daySummaryEntryCount(kept);
    if (missed == 0) return label;
    return '$label · ${l10n.dayListMissedCount(missed)}';
  }

  Widget _buildMonthNav(AppLocalizations l10n, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final order = _monthOrder(_month);
    final todayMonth = _monthOf(widget.today);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.dayListPreviousMonth,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: order > _monthOrder(_earliestMonth)
                ? () =>
                      _goToMonth(DateTime.utc(_month.year, _month.month - 1, 1))
                : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  AgendaListView.monthLabel(
                    l10n.localeName,
                    _month,
                    withYear: true,
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _countLabel(
                    l10n,
                    _monthBucket.keptCount,
                    _monthBucket.count - _monthBucket.keptCount,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // A fixed slot rather than a conditional child: the button is only
          // ever disabled, so the title beside it never shifts.
          SizedBox(
            width: _headerSlot,
            child: IconButton(
              tooltip: l10n.dayListJumpToToday,
              icon: const Icon(Icons.today_rounded),
              onPressed: order == _monthOrder(todayMonth)
                  ? null
                  : () => _goToMonth(todayMonth),
            ),
          ),
          IconButton(
            tooltip: l10n.dayListNextMonth,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: order < _monthOrder(_latestMonth)
                ? () =>
                      _goToMonth(DateTime.utc(_month.year, _month.month + 1, 1))
                : null,
          ),
        ],
      ),
    );
  }

  double get _rowHeight {
    final strip = CalendarDayBars.stripHeight(
      _maxBars,
      widget.appearance.markerStyle,
    );
    final height = CalendarDayCell.chipZoneHeight + strip + 6;
    return height < 52 ? 52 : height.ceilToDouble();
  }

  Widget _buildMonthGrid(AppLocalizations l10n, ThemeData theme) {
    final appearance = widget.appearance;
    final accent = appearance.accentOr(theme.colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TableCalendar<void>(
        firstDay: _earliestMonth,
        lastDay: DateTime.utc(_latestMonth.year, _latestMonth.month + 1, 0),
        focusedDay: _month,
        headerVisible: false,
        calendarFormat: CalendarFormat.month,
        startingDayOfWeek: startingDayOfWeekFor(appearance.weekStart),
        weekendDays: CalendarWeekend.days,
        weekNumbersVisible: appearance.showWeekNumbers,
        rowHeight: _rowHeight,
        daysOfWeekHeight: 24,
        locale: l10n.localeName,
        availableGestures: AvailableGestures.horizontalSwipe,
        selectedDayPredicate: (day) =>
            _selectedDay != null && isSameDay(day, _selectedDay),
        enabledDayPredicate: _hasEntry,
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: false,
          markersMaxCount: 0,
        ),
        calendarBuilders: CalendarBuilders<void>(
          defaultBuilder: (context, day, _) => _cell(day, accent),
          todayBuilder: (context, day, _) => _cell(day, accent),
          selectedBuilder: (context, day, _) => _cell(day, accent),
          disabledBuilder: (context, day, _) => _cell(day, accent),
          markerBuilder: (context, day, _) => _marker(day, appearance),
        ),
        onDaySelected: (selectedDay, _) => _toggleSelectedDay(
          DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day),
        ),
        onPageChanged: (focusedDay) =>
            _goToMonth(DateTime.utc(focusedDay.year, focusedDay.month, 1)),
      ),
    );
  }

  /// Whether the cell's **own** month — not necessarily `_month`, since a
  /// mid-swipe frame draws two — has anything on this day.
  ///
  /// Cache-only by design: resolving from inside a predicate or a builder
  /// would run a scan while a frame is being built. An uncached month answers
  /// "nothing", which is what a month the sheet has not navigated to is. Tests
  /// the mask bit rather than allocating a `DateTime.utc` per cell per frame,
  /// and a missed-only day still counts — it is openable, so the user can see
  /// that it was missed.
  bool _hasEntry(DateTime day) {
    final mask = _resolvedMonths[_monthKeyOf(day)]?.markedMask ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  /// A day of the month with nothing on it is drawn through the same faded
  /// path as an out-of-month day: it is inert, and a full-strength number
  /// reads as tappable. Today keeps its own styling either way — the one day
  /// the grid must never hide.
  Widget _cell(DateTime day, Color accent) {
    final isToday = isSameDay(day, widget.today);
    return CalendarDayCell(
      day: day,
      isToday: isToday,
      isSelected: _selectedDay != null && isSameDay(day, _selectedDay),
      isOutside: !isToday && !_hasEntry(day),
      isWeekend: CalendarWeekend.isWeekend(day),
      todayStyle: widget.appearance.todayStyle,
      highlightWeekends: widget.appearance.highlightWeekends,
      accent: accent,
    );
  }

  Widget _marker(DateTime day, CalendarAppearance appearance) {
    final bars = _barsByMonth[_monthKeyOf(day)]?[day.day];
    if (bars == null || bars.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: CalendarDayBars(
          bars: bars,
          maxBars: _maxBars,
          style: appearance.markerStyle,
        ),
      ),
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
              _countLabel(l10n, kept, total - kept),
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
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomClearance,
  ) {
    // Inside the year body rather than the fixed header: the other two modes
    // must keep the layout they have, and only this one has scopes.
    //
    // A `SegmentedButton` rather than the chip pair this replaced: two chips
    // measured 336-378dp against the 288-328dp a phone offers, so they wrapped
    // to a second row in every locale. The mode selector above proves this
    // shape fits at 320dp.
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
        Expanded(
          child: _buildYearGrid(l10n, theme, colorScheme, bottomClearance),
        ),
      ],
    );
  }

  static String _yearScopeLabel(
    AppLocalizations l10n,
    AgendaDayListYearScope scope,
  ) {
    return switch (scope) {
      AgendaDayListYearScope.upcoming => l10n.dayListScopeUpcoming,
      AgendaDayListYearScope.thisYear => l10n.dayListScopeThisYear,
    };
  }

  Widget _buildYearGrid(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    double bottomClearance,
  ) {
    final marked = widget.list.color;
    final missed = marked.withValues(alpha: CalendarColors.missedEventAlpha);
    final unmarked = colorScheme.outline.withValues(
      alpha: MonthDotMatrix.unmarkedAlpha,
    );
    final outside = colorScheme.outline.withValues(
      alpha: MonthDotMatrix.outsideAlpha,
    );
    final tileBackground = colorScheme.surfaceContainerHigh;
    final accent = widget.appearance.accentOr(colorScheme.primary);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomClearance),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisExtent: 116,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _yearTiles.length,
      itemBuilder: (context, index) {
        final tile = _yearTiles[index];
        final month = tile.month;
        final label = _yearTileLabel(l10n.localeName, month);
        return Semantics(
          container: true,
          button: true,
          // The tile prints the attendance count alone; the missed tally is
          // announced here so a screen reader is not left with a number that
          // silently excludes days the user knows are in the month.
          label:
              '$label, '
              '${_countLabel(l10n, tile.count, tile.missedCount)}',
          child: Material(
            color: tileBackground,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openMonthFromYear(month),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${tile.count}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: tile.count > 0
                                  ? marked
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          child: MonthDotMatrix(
                            daysInMonth: tile.daysInMonth,
                            firstWeekdayColumn: weekdayColumnOf(
                              month,
                              widget.appearance.weekStart,
                            ),
                            markedMask: tile.markedMask,
                            missedMask: tile.missedMask,
                            windowMask: tile.windowMask,
                            todayIndex:
                                widget.today.year == month.year &&
                                    widget.today.month == month.month
                                ? widget.today.day - 1
                                : null,
                            markedColor: marked,
                            missedColor: missed,
                            unmarkedColor: unmarked,
                            outsideColor: outside,
                            todayColor: accent,
                            backgroundColor: tileBackground,
                            outlineColor: colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static final Map<String, DateFormat> _yearTileFormatCache = {};

  static String _yearTileLabel(String localeName, DateTime month) {
    return (_yearTileFormatCache[localeName] ??= DateFormat.yMMM(
      localeName,
    )).format(month);
  }
}

/// One month of the year overview, resolved on state change so the grid only
/// paints.
class _YearTile {
  final DateTime month;
  final int daysInMonth;

  /// Entries that were attended — the number the tile prints.
  final int count;

  /// Entries that were missed, announced beside the count and never added to
  /// it.
  final int missedCount;

  final int markedMask;
  final int missedMask;
  final int windowMask;

  const _YearTile({
    required this.month,
    required this.daysInMonth,
    required this.count,
    required this.missedCount,
    required this.markedMask,
    required this.missedMask,
    required this.windowMask,
  });
}

sealed class _DayListRow {
  const _DayListRow();
}

class _MonthHeaderRow extends _DayListRow {
  final DateTime month;
  final bool showYear;

  const _MonthHeaderRow({required this.month, required this.showYear});
}

class _DayHeaderRow extends _DayListRow {
  final DateTime day;
  final int count;
  final int missed;

  const _DayHeaderRow({
    required this.day,
    required this.count,
    required this.missed,
  });
}

class _EntryRow extends _DayListRow {
  final AgendaDayListEntry entry;

  const _EntryRow({required this.entry});
}
