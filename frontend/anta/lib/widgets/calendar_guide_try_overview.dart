import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_bounds.dart';
import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../models/overview_period.dart';
import '../utils/agenda_month_store.dart';
import '../utils/event_agenda.dart';
import 'agenda_day_list_rows.dart';
import 'agenda_list_view.dart';
import 'agenda_month_grid.dart';
import 'agenda_period_nav.dart';
import 'agenda_year_grid.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'calendar_guide_try_screen.dart';
import 'form_rows.dart';
import 'overview_mode_chips.dart';
import 'year_month_tile.dart';

/// The screen page's third card: the overview over the screen page's demo —
/// its chip row, its period nav and the mode's body in one slot — drawn by
/// the overview's own widgets over a real [AgendaMonthStore] whose resolvers
/// scan the demo, so the tiles, the mini month and the rows are the ones the
/// overview would draw for these events (D59). Nothing opens: the rows have
/// no tap and no presence button, the search is drawn disabled (D57).
///
/// Year mode draws one year at a time in [AgendaYearGrid], the day list's
/// own year grid, ◄ ► stepping it. The overview page scrolls its years
/// continuously through `AgendaYearScroll`, with its scrubber, its landings
/// and its runs between frames; a card's slot cannot hold that, and a
/// scroll of years inside a scroll of a page would be the hardest of the
/// three modes to read on a phone. Month and List show one month, ◄ ►
/// stepping it (D68): a year of rows in a 360 dp slot held the page
/// mid-screen under a finger that only meant to scroll past it.
class GuideOverviewDemo extends GuideCardDemo {
  GuideOverviewDemo(this.world)
    : super(CalendarGuideTopic.screen.card(GuideCardSpec.screenOverview)) {
    world.addListener(_onWorld);
    _onWorld();
  }

  static const String slug = GuideCardSpec.screenOverview;

  final GuideScreenWorld world;

  @override
  bool get stageFullBleed => true;

  /// Month, on the shared day's month (D68): the page opens on the tiles,
  /// but a card's slot showed nine of them with the seeded month below its
  /// fold.
  AgendaDayListMode _mode = AgendaDayListMode.month;
  int _year = 0;
  DateTime _month = DateTime.utc(0);

  /// The mini month's identity: bumped by every move of the nav, the chips
  /// and the tiles, so the grid is rebuilt on its new page rather than
  /// animating to it — nothing on a card animates — and never by a swipe,
  /// whose page change comes half-way through the drag: a new grid then
  /// would drop the finger's gesture mid-swipe.
  int _navigation = 0;

  /// Month mode lists the whole month while set, the picked day's rows
  /// otherwise — the overview's toggle, a second tap on the picked day. The
  /// shared day itself stays picked: the panel card shows it.
  bool _wholeMonth = false;
  DateTime? _seenPick;

  /// Each resolved month's days with any occurrence, missed or kept, folded
  /// in [_resolve] before the hidden display drops anything: what makes a
  /// day of the mini month a day to pick, as on the overview page
  /// (`_hasOccurrence`).
  final Map<int, int> _occurrenceMask = {};

  /// Built for one demo calendar, one look and one language, and built again
  /// when any of them changes — the categories arriving rebuild the demo.
  AgendaMonthStore? _store;
  Object? _storeKey;

  /// What the shown mode draws, folded on navigation, never in a build.
  List<AgendaYearTile> _tiles = const [];
  int _yearKept = 0;
  int _yearMissed = 0;
  List<AgendaDayListRow> _monthRows = const [];
  List<AgendaDayListRow> _listRows = const [];
  int _listKept = 0;
  int _listMissed = 0;

  /// The nav's title box, measured over the shown year's twelve month
  /// titles in every mode, so the slot below starts at one height whichever
  /// mode is shown.
  List<String> _titleTemplates = const [];
  Object? _templatesKey;

  @override
  void dispose() {
    world.removeListener(_onWorld);
    super.dispose();
  }

  GuideDemoCalendar get _calendar => world.calendar!;

  void _onWorld() {
    final calendar = world.calendar;
    final l10n = world.l10n;
    if (calendar == null || l10n == null) return;
    final key = (calendar, world.appearance, l10n);
    if (key != _storeKey) {
      if (_storeKey == null) {
        _year = calendar.selectedDay.year;
        _month = AgendaMonthStore.monthOf(calendar.selectedDay);
      }
      _storeKey = key;
      _occurrenceMask.clear();
      _store = AgendaMonthStore(
        resolve: _resolve,
        resolveMarks: _resolveMarks,
        maxBars: AgendaMonthGrid.maxBarsFor(world.appearance),
      );
      _seenPick = calendar.selectedDay;
      _resolveShown();
    } else if (calendar.selectedDay != _seenPick) {
      // A new pick, here or on another card: Month lists that day.
      _seenPick = calendar.selectedDay;
      _wholeMonth = false;
      if (_mode == AgendaDayListMode.month) _foldMonthRows();
    }
    notifyListeners();
  }

  /// Every occurrence of the demo from [start] to [end], in the order the
  /// panels list a day — its rules less its skips, as the grid shows them.
  List<EventOccurrence> _scan(DateTime start, DateTime end) {
    final calendar = _calendar;
    return [
      for (
        var day = start;
        !day.isAfter(end);
        day = DateTime.utc(day.year, day.month, day.day + 1)
      )
        for (final event in calendar.allEventsFor(day))
          EventOccurrence(event: event, day: day),
    ];
  }

  bool _missed(EventOccurrence occurrence) =>
      _calendar.isMissed(occurrence.event, occurrence.day);

  bool get _hidesMissed =>
      world.appearance.missedDisplay == CalendarMissedDisplay.hidden;

  /// The overview's rows for the demo. Converted with nothing dropped, so
  /// the entries stay index for index with the occurrences; whether one was
  /// missed is the demo's marks', which the shared converter cannot read,
  /// and the hidden display drops it here, as the converter would.
  List<AgendaDayListEntry> _resolve(DateTime start, DateTime end) {
    final occurrences = _scan(start, end);
    for (
      var month = AgendaMonthStore.monthOf(start);
      !month.isAfter(end);
      month = DateTime.utc(month.year, month.month + 1)
    ) {
      _occurrenceMask[AgendaMonthStore.keyOf(month)] = 0;
    }
    for (final occurrence in occurrences) {
      final key = AgendaMonthStore.keyOf(occurrence.day);
      _occurrenceMask[key] =
          (_occurrenceMask[key] ?? 0) | (1 << (occurrence.day.day - 1));
    }
    return _converted(occurrences, dropHidden: _hidesMissed);
  }

  /// [occurrences] as the overview's rows, the missed ones dropped when
  /// [dropHidden].
  List<AgendaDayListEntry> _converted(
    List<EventOccurrence> occurrences, {
    required bool dropHidden,
  }) {
    final converted = AgendaListView.eventDayEntries(
      occurrences,
      world.l10n!,
      false,
      showRecurrenceLabels: world.appearance.showRecurrenceLabels,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    return [
      for (var i = 0; i < occurrences.length; i++)
        if (_missed(occurrences[i]) case final missed
            when !(dropHidden && missed))
          AgendaDayListEntry(
            day: converted[i].day,
            icon: converted[i].icon,
            color: converted[i].color,
            title: converted[i].title,
            subtitle: converted[i].subtitle,
            missed: missed,
            eventId: converted[i].eventId,
            presenceTracked: converted[i].presenceTracked,
          ),
    ];
  }

  /// [_resolve]'s twin for the year tiles: the marks alone.
  List<AgendaDayMark> _resolveMarks(DateTime start, DateTime end) {
    final occurrences = _scan(start, end);
    final marks = AgendaListView.eventDayMarks(
      occurrences,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    final hide = _hidesMissed;
    return [
      for (var i = 0; i < occurrences.length; i++)
        if (_missed(occurrences[i]) case final missed when !(hide && missed))
          AgendaDayMark(
            day: marks[i].day,
            color: marks[i].color,
            missed: missed,
          ),
    ];
  }

  /// Resolves what the shown mode needs and folds it: on navigation only.
  void _resolveShown() {
    final store = _store;
    if (store == null) return;
    switch (_mode) {
      case AgendaDayListMode.year:
        final months = AgendaMonthStore.monthsOfYear(_year);
        store.ensureTallies(months);
        final tallies = [for (final month in months) store.cachedTally(month)!];
        _tiles = [
          for (final tally in tallies)
            AgendaYearTile.ofTally(tally, perDayColors: true),
        ];
        _yearKept = tallies.fold(0, (sum, t) => sum + t.keptCount);
        _yearMissed = tallies.fold(0, (sum, t) => sum + t.count - t.keptCount);
      case AgendaDayListMode.month:
        store.ensure([_month]);
        _foldMonthRows();
      case AgendaDayListMode.list:
        store.ensure([_month]);
        final bucket = store.cached(_month)!;
        _listRows = buildAgendaDayListRows(
          bucket.days,
          bucket.entriesOn,
          groupByDay: true,
          withMonths: true,
          keptCountOf: bucket.keptCountForDay,
          alwaysMonths: true,
        );
        _listKept = bucket.keptCount;
        _listMissed = bucket.count - bucket.keptCount;
    }
  }

  /// The picked day's rows when it is in the shown month and has any, as the
  /// overview lists a picked day — from a one-day scan, so under the hidden
  /// display its missed occurrences are listed faded, as the overview's
  /// `_pickedDayEntries` lists them; the whole month's otherwise.
  void _foldMonthRows() {
    final bucket = _store?.cached(_month);
    if (bucket == null) return;
    final picked = _shownPick;
    final dayEntries = picked == null
        ? const <AgendaDayListEntry>[]
        : _converted(_scan(picked, picked), dropHidden: false);
    if (picked != null && dayEntries.isNotEmpty) {
      _monthRows = buildAgendaDayListRows(
        [picked],
        (_) => dayEntries,
        groupByDay: true,
        withMonths: false,
        keptCountOf: (_) => dayEntries.where((entry) => !entry.missed).length,
      );
      return;
    }
    _monthRows = buildAgendaDayListRows(
      bucket.days,
      bucket.entriesOn,
      groupByDay: true,
      withMonths: false,
      keptCountOf: bucket.keptCountForDay,
    );
  }

  /// The shared day when the shown month holds it and Month is not on the
  /// whole month.
  DateTime? get _shownPick {
    if (_wholeMonth) return null;
    final day = _calendar.selectedDay;
    return day.year == _month.year && day.month == _month.month ? day : null;
  }

  /// A day to pick on the mini month: any occurrence, missed or kept.
  bool _hasOccurrence(DateTime day) {
    if (_store?.hasEntry(day) ?? false) return true;
    final mask = _occurrenceMask[AgendaMonthStore.keyOf(day)] ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  void _selectMode(AgendaDayListMode mode) {
    final toYear = mode == AgendaDayListMode.year;
    if (_mode == AgendaDayListMode.year && !toYear) {
      if (_month.year != _year) {
        final today = _calendar.today;
        _month = DateTime.utc(_year, _year == today.year ? today.month : 1);
      }
    } else if (_mode != AgendaDayListMode.year && toYear) {
      _year = _month.year;
    }
    _mode = mode;
    _navigation++;
    _resolveShown();
    did('mode');
  }

  /// A year tile opens its month, as the overview's do.
  void _openMonth(DateTime month) {
    _mode = AgendaDayListMode.month;
    _month = AgendaMonthStore.monthOf(month);
    _navigation++;
    _resolveShown();
    changed();
  }

  /// Month and List step a month, Year a year.
  bool get _monthly => _mode != AgendaDayListMode.year;

  bool _canStep(int delta) {
    if (_monthly) {
      final next = DateTime.utc(_month.year, _month.month + delta);
      return !next.isBefore(
            AgendaMonthStore.monthOf(CalendarBounds.earliest),
          ) &&
          !next.isAfter(AgendaMonthStore.monthOf(CalendarBounds.latest));
    }
    final next = _year + delta;
    return next >= CalendarBounds.earliest.year &&
        next <= CalendarBounds.latest.year;
  }

  void _step(int delta) {
    if (_monthly) {
      _month = DateTime.utc(_month.year, _month.month + delta);
    } else {
      _year += delta;
    }
    _navigation++;
    _resolveShown();
    did('period');
  }

  bool get _atToday {
    final today = _calendar.today;
    return _monthly
        ? _month == AgendaMonthStore.monthOf(today)
        : _year == today.year;
  }

  void _goToday() {
    final today = _calendar.today;
    _month = AgendaMonthStore.monthOf(today);
    _year = today.year;
    _navigation++;
    _resolveShown();
    did('period');
  }

  /// A swipe on the mini month: its page, not a step of the nav.
  void _turnMonth(DateTime month) {
    _month = month;
    _resolveShown();
    changed();
  }

  /// A day of the mini month picks the demo's day, so the grid and the
  /// panel above show it too — one notification, the shared demo's, which
  /// this card hears as well. The picked day tapped again lists the whole
  /// month, and once more the day again; the shared day stays as it is.
  void _pickDay(DateTime day) {
    final calendar = _calendar;
    if (day == calendar.selectedDay) {
      _wholeMonth = !_wholeMonth;
      _foldMonthRows();
      changed();
      return;
    }
    calendar.selectedDay = day;
    calendar.focus(day);
    dropReport();
    world.touch();
  }

  List<String> _templates(AppLocalizations l10n) {
    final key = (l10n.localeName, _year, _month.year);
    if (key == _templatesKey) return _titleTemplates;
    _templatesKey = key;
    return _titleTemplates = List.unmodifiable([
      for (final year in {_year, _month.year})
        for (final month in AgendaMonthStore.monthsOfYear(year)) ...[
          AgendaListView.monthLabel(l10n.localeName, month, withYear: true),
          _monthSpan(month).menuValue(l10n),
        ],
    ]);
  }

  /// [month] as the period List mode lists, written as the overview writes
  /// a custom span in its nav.
  static OverviewPeriod _monthSpan(DateTime month) => OverviewCustomPeriod(
    DateTime.utc(month.year, month.month),
    DateTime.utc(month.year, month.month + 1, 0),
  );

  String _control(String name) =>
      SemanticsIds.calendarGuideTryControl(slug, name);

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewModeChips(
          mode: _mode,
          onSelected: _selectMode,
          modeIdentifier: (mode) => _control('mode-${mode.name}'),
          // Disabled, never hidden: the demo has nothing to search.
          onSearch: null,
          searchActive: false,
          searchIdentifier: _control('search'),
        ),
        _nav(l10n),
        GuideStageSlot(
          height: GuideMetrics.overviewStageBodyHeight,
          child: switch (_mode) {
            AgendaDayListMode.year => _yearBody(colorScheme),
            AgendaDayListMode.month => _monthBody(l10n),
            AgendaDayListMode.list => _listBody(l10n),
          },
        ),
      ],
    );
  }

  /// The title per mode as the overview writes it: the year, the month, the
  /// listed period — here always the shown month, as a span. No period menu
  /// on the title.
  Widget _nav(AppLocalizations l10n) {
    final templates = _templates(l10n);
    final previous = _canStep(-1) ? () => _step(-1) : null;
    final next = _canStep(1) ? () => _step(1) : null;
    final today = _atToday ? null : _goToday;
    final previousId = _control('previous');
    final nextId = _control('next');
    final todayId = _control('today');
    switch (_mode) {
      case AgendaDayListMode.year:
        return AgendaPeriodNav(
          title: '$_year',
          titleTemplates: templates,
          subtitle: agendaDayListCountLabel(l10n, _yearKept, _yearMissed),
          previousTooltip: l10n.datePickerPreviousYear,
          nextTooltip: l10n.datePickerNextYear,
          todayTooltip: l10n.dayListScopeThisYear,
          onPrevious: previous,
          onNext: next,
          onToday: today,
          previousIdentifier: previousId,
          nextIdentifier: nextId,
          todayIdentifier: todayId,
        );
      case AgendaDayListMode.month:
        final bucket = _store?.cached(_month);
        return AgendaPeriodNav(
          title: AgendaListView.monthLabel(
            l10n.localeName,
            _month,
            withYear: true,
          ),
          month: _month,
          titleTemplates: templates,
          subtitle: agendaDayListCountLabel(
            l10n,
            bucket?.keptCount ?? 0,
            bucket == null ? 0 : bucket.count - bucket.keptCount,
          ),
          previousTooltip: l10n.dayListPreviousMonth,
          nextTooltip: l10n.dayListNextMonth,
          todayTooltip: l10n.dayListJumpToToday,
          onPrevious: previous,
          onNext: next,
          onToday: today,
          previousIdentifier: previousId,
          nextIdentifier: nextId,
          todayIdentifier: todayId,
        );
      case AgendaDayListMode.list:
        final home = _monthSpan(_calendar.today);
        return AgendaPeriodNav(
          title: _monthSpan(_month).menuValue(l10n),
          titleTemplates: templates,
          subtitle: agendaDayListCountLabel(l10n, _listKept, _listMissed),
          previousTooltip: l10n.overviewPeriodPrevious,
          nextTooltip: l10n.overviewPeriodNext,
          todayTooltip: l10n.overviewPeriodHome(home.menuValue(l10n)),
          onPrevious: previous,
          onNext: next,
          onToday: today,
          previousIdentifier: previousId,
          nextIdentifier: nextId,
          todayIdentifier: todayId,
        );
    }
  }

  /// The month whose row Year mode opens on: the month Month and List last
  /// showed, while it is in the shown year; this month in this year; else
  /// January.
  int get _yearFocusMonth {
    if (_month.year == _year) return _month.month;
    final today = _calendar.today;
    return today.year == _year ? today.month : 1;
  }

  /// The shown year's tiles, opened with [_yearFocusMonth]'s row at the
  /// slot's top — as far as the grid scrolls — so the month she was on is
  /// in view at once: the slot shows three rows of four. Laid out from the
  /// grid's own delegate, and placed by the scroll's initial offset rather
  /// than a jump after the first frame; keyed on [_navigation], so every
  /// entry and every step opens on that row again.
  Widget _yearBody(ColorScheme colorScheme) => LayoutBuilder(
    builder: (context, constraints) {
      final delegate = YearMonthTile.gridDelegate;
      final columns = YearMonthTile.columnsFor(constraints.maxWidth);
      final rowExtent = delegate.mainAxisExtent! + delegate.mainAxisSpacing;
      final rows = (_tiles.length / columns).ceil();
      final reach = math.max(
        0.0,
        rows * rowExtent - delegate.mainAxisSpacing - constraints.maxHeight,
      );
      final offset = math.min(
        (_yearFocusMonth - 1) ~/ columns * rowExtent,
        reach,
      );
      return _YearScrollHost(
        key: ValueKey((_navigation, columns)),
        initialOffset: offset,
        builder: (controller) => AgendaYearGrid(
          tiles: _tiles,
          color: world.appearance.accentOr(colorScheme.primary),
          appearance: world.appearance,
          today: _calendar.today,
          onOpenMonth: _openMonth,
          padding: EdgeInsets.zero,
          // The page's groups' role, as the overview's tiles.
          tileBackground: colorScheme.rowGroup,
          controller: controller,
        ),
      );
    },
  );

  /// The overview's rows, with nothing to tap. Their titles and captions
  /// wrap: the overview holds them to one line for its exact extents, which
  /// a slot this short has no use for, and a cut caption is a clipped label.
  /// List's one month section carries no count: the nav above says the same
  /// number, and beside a German month at 2.0 the count ran off the row,
  /// which the overview's measured header slots wrap and a card has none of.
  AgendaDayListRowBuilder _rowsOf(List<AgendaDayListRow> rows) =>
      AgendaDayListRowBuilder(rows: rows, today: _calendar.today);

  /// The mini month over the picked day's rows, in one scroll as Month mode
  /// lays them out; keyed on [_navigation].
  Widget _monthBody(AppLocalizations l10n) {
    final store = _store!;
    final rows = _rowsOf(_monthRows);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AgendaMonthGrid(
            key: ValueKey(_navigation),
            month: _month,
            firstDay: CalendarBounds.earliest,
            lastDay: CalendarBounds.latest,
            today: _calendar.today,
            selectedDay: _shownPick,
            appearance: world.appearance,
            hasEntry: _hasOccurrence,
            barsFor: (day) => store.barsFor(day)?[day.day],
            onDaySelected: _pickDay,
            onPageChanged: _turnMonth,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            RowMetrics.groupInset,
            RowMetrics.groupGap,
            RowMetrics.groupInset,
            FormMetrics.bodyBottom,
          ),
          sliver: _monthRows.isEmpty
              ? SliverToBoxAdapter(
                  child: FormCaption(
                    text: l10n.dayListEmptyMonth,
                    padding: FormMetrics.groupCaptionPadding,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    rows.build,
                    childCount: _monthRows.length,
                  ),
                ),
        ),
      ],
    );
  }

  /// The shown year's rows, grouped by day under their months.
  Widget _listBody(AppLocalizations l10n) {
    const padding = EdgeInsets.fromLTRB(
      RowMetrics.groupInset,
      FormMetrics.bodyTop,
      RowMetrics.groupInset,
      FormMetrics.bodyBottom,
    );
    if (_listRows.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          FormCaption(
            text: l10n.dayListEmptyRange,
            padding: FormMetrics.groupCaptionPadding,
          ),
        ],
      );
    }
    final rows = _rowsOf(_listRows);
    return ListView.builder(
      padding: padding,
      itemCount: _listRows.length,
      itemBuilder: rows.build,
    );
  }
}

/// Owns the year grid's controller, made once with [initialOffset] — the
/// card rebuilds the grid on every redraw, and a controller made in a build
/// would be a new scroll position each time.
class _YearScrollHost extends StatefulWidget {
  const _YearScrollHost({
    super.key,
    required this.initialOffset,
    required this.builder,
  });

  final double initialOffset;
  final Widget Function(ScrollController controller) builder;

  @override
  State<_YearScrollHost> createState() => _YearScrollHostState();
}

class _YearScrollHostState extends State<_YearScrollHost> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: widget.initialOffset,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
