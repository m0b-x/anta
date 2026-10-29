import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_weekend.dart';
import '../constants/guide_metrics.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../models/calendar_panel_mode.dart';
import '../models/day_summary_entry.dart';
import '../models/recurrence_rule.dart';
import '../services/category_service.dart';
import '../services/day_bars_resolver.dart';
import '../services/day_summary_resolver.dart';
import '../services/settings_service.dart';
import '../utils/calendar_days_of_week.dart';
import '../utils/calendar_week_start.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/presence_stats.dart';
import '../utils/sheet_guard.dart';
import '../widgets/agenda_day_list_rows.dart';
import '../widgets/agenda_list_view.dart';
import '../widgets/automation_id.dart';
import '../widgets/calendar_add_fab.dart';
import '../widgets/calendar_bottom_panel.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/calendar_day_bars.dart';
import '../widgets/calendar_day_cell.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/calendar_guide_try_card.dart';
import '../widgets/calendar_header_menus.dart';
import '../widgets/day_summary_panel.dart';
import '../widgets/day_timeline_view.dart';
import '../widgets/event_description_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/event_template_picker_sheet.dart';
import '../widgets/form_rows.dart';

/// The guide's practice calendar: the real calendar's grid, panel, menus and
/// sheets over six demo events, where a newcomer can tap, add, change and
/// delete freely because nothing is saved.
///
/// Every sheet it opens is the real one in its sandbox mode, and every
/// answer lands in a [GuideDemoCalendar] this page's `State` owns — never in
/// a bloc, a service or one of the calendar's static caches. A band under the
/// bar says so once, and its second line says what the last action did, in
/// the words of the real calendar.
class CalendarGuidePracticePage extends StatefulWidget {
  const CalendarGuidePracticePage({super.key});

  @override
  State<CalendarGuidePracticePage> createState() =>
      _CalendarGuidePracticePageState();
}

class _CalendarGuidePracticePageState extends State<CalendarGuidePracticePage> {
  /// The appearance and the palette, read once: the demo grid wears the
  /// owner's look, and nothing here can change it.
  CalendarAppearance _appearance = const CalendarAppearance();
  MarkdownColorPalette _palette = MarkdownColorPalette.presets;

  /// Null until the settings and the categories have loaded: the seed wears
  /// the owner's categories, so it is built after them.
  GuideDemoCalendar? _demo;

  /// Whether a rebuild is already waiting for the end of the frame — see
  /// [_rebuildSoon].
  bool _rebuildScheduled = false;

  /// The band's live line; null is the idle line. A notifier, so a caption
  /// rebuilds the band and nothing else.
  final ValueNotifier<String?> _caption = ValueNotifier<String?>(null);

  /// The add button stays labelled: the demo has no scroll-driven collapse,
  /// because nothing on this page animates.
  final ValueNotifier<bool> _fabExtended = ValueNotifier<bool>(true);

  final SheetGuard _sheets = SheetGuard();

  /// Every caption the band can show at its longest, built once per locale.
  List<String> _candidates = const [];
  Locale? _candidatesLocale;

  DateFormat? _dateFormat;

  /// The bars and the day panel's entries come from resolvers whose
  /// providers depend only on the localization and three filter layers, so
  /// they are kept until one of those changes.
  DayBarsResolver? _barsResolver;
  DaySummaryResolver? _summaryResolver;
  Object? _resolverKey;

  GuideDemoCalendar get demo => _demo!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await SettingsService.getInstance();
      final loaded = await settings.getCalendarPageSettings();
      if (!mounted) return;
      _appearance = loaded.appearance;
      _palette = loaded.palette;
    } catch (e, st) {
      // The demo still works on the default look.
      debugPrint('[CalendarGuidePracticePage] Settings load failed: $e\n$st');
    }
    var categories = const <CalendarCategory>[];
    try {
      categories = (await CategoryService.getInstance()).categories;
    } catch (e, st) {
      // The seed falls back to the default category.
      debugPrint('[CalendarGuidePracticePage] Categories load failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _demo = GuideDemoCalendar(
        l10n: AppLocalizations.of(context)!,
        today: DateTime.now(),
        categories: categories,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    if (locale == _candidatesLocale) return;
    _candidatesLocale = locale;
    _dateFormat = DateFormat.yMMMMEEEEd(l10n.localeName);
    _candidates = _captionCandidates(l10n);
  }

  @override
  void dispose() {
    _caption.dispose();
    _fabExtended.dispose();
    super.dispose();
  }

  String _date(DateTime day) => _dateFormat!.format(day);

  static String _formatLabel(AppLocalizations l10n, CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
  }

  /// Every caption the page can say, each filled with its longest value: a
  /// title stand-in at the cut, the longest date this locale writes, every
  /// count form. The band's slot is as tall as the tallest of them, so a
  /// caption changes its words and never the band's height.
  List<String> _captionCandidates(AppLocalizations l10n) {
    final title = '${'W' * GuideMetrics.captionTitleMaxChars}…';
    var date = '';
    for (var day = 0; day < 365; day++) {
      final text = _date(DateTime.utc(2027, 1, 1 + day));
      if (text.length > date.length) date = text;
    }
    const counts = [0, 1, 2, 22];
    return [
      l10n.calendarGuidePracticeIdle,
      for (final count in counts) l10n.calendarGuidePickedDay(date, count),
      l10n.calendarGuideDemoAddedShort(title, date),
      l10n.calendarGuideDemoChanged(title),
      l10n.calendarGuideDemoDeleted(title),
      l10n.calendarGuideDemoSkipped(date, title),
      l10n.calendarGuideDemoTemplate(title),
      for (final count in counts) l10n.calendarGuideDemoFiltered(count),
      for (final format in CalendarFormat.values)
        l10n.calendarGuideDemoFormat(_formatLabel(l10n, format)),
      l10n.calendarGuideDemoPanelDay(l10n.panelModeDay),
      l10n.calendarGuideDemoPanelTimeline(l10n.panelModeTimeline),
      l10n.calendarGuideDemoPanelUpcoming(l10n.upcomingEvents),
      for (final what in [
        l10n.calendarOverview,
        l10n.alertsTitle,
        l10n.calendarSettingsRow,
        l10n.quickAlarmTitle,
      ])
        l10n.calendarGuideWouldOpen(what),
      l10n.calendarGuideWouldShare,
      l10n.calendarGuideYouAreHere,
      // A window holds at most one occurrence a day.
      l10n.eventAdherenceSummary(
        PresenceAdherence.windowDays,
        PresenceAdherence.windowDays,
        PresenceAdherence.windowDays,
      ),
    ];
  }

  void _say(String text) => _caption.value = text;

  /// A presence mark, from the day panel's button or the detail sheet's
  /// chips: written to the demo, then the band says how the event is going
  /// over the demo's own marks, as the sheet's stats line does.
  void _markPresence(
    CalendarEvent event,
    DateTime day, {
    required bool missed,
  }) {
    demo.setPresence(event.id, day, missed: missed);
    final stats = PresenceAdherence.compute(
      demo.byId(event.id) ?? event,
      today: demo.today,
      isMissed: demo.isMissed,
    );
    if (stats == null) return;
    _say(
      AppLocalizations.of(context)!.eventAdherenceSummary(
        stats.attended,
        stats.total,
        PresenceAdherence.windowDays,
      ),
    );
  }

  /// A rebuild at the end of the current frame. The detail sheet hands a
  /// pending tick over from its `dispose`, inside the framework's locked
  /// finalize pass, where `setState` throws; its callbacks write the demo
  /// and ask for this instead.
  void _rebuildSoon() {
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      })
      ..scheduleFrame();
  }

  /// A change to the demo's data: the page rebuilds, then the band says it.
  void _changed(String caption) {
    setState(() {});
    _say(caption);
  }

  void _resolversFor(AppLocalizations l10n) {
    final filters = demo.filters;
    final key = (
      l10n,
      _appearance.missedDisplay,
      _appearance.showRecurrenceLabels,
      filters.showHolidays,
      filters.showFasting,
      filters.showMoney,
    );
    if (key == _resolverKey) return;
    _resolverKey = key;
    _barsResolver = DayBarsResolver.defaults(
      l10n,
      missedDisplay: _appearance.missedDisplay,
      showHolidays: filters.showHolidays,
      showFasting: filters.showFasting,
      showMoney: filters.showMoney,
      isMissed: demo.isMissed,
    );
    _summaryResolver = DaySummaryResolver.defaults(
      l10n,
      showRecurrence: _appearance.showRecurrenceLabels,
      showHolidays: filters.showHolidays,
      showFasting: filters.showFasting,
      showMoney: filters.showMoney,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final demo = _demo;
    if (demo != null) _resolversFor(l10n);
    final active = demo?.filters.activeCount ?? 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        titleSpacing: CalendarViewMenu.titleSpacing,
        excludeHeaderSemantics: true,
        title: CalendarViewMenu(
          page: CalendarViewPage.calendar,
          onPageSelected: (_) =>
              _say(l10n.calendarGuideWouldOpen(l10n.calendarOverview)),
          format: demo?.format ?? CalendarFormat.month,
          onFormatSelected: demo == null
              ? null
              : (format) => _setFormat(format),
          // The body names the route "Practice calendar"; the title only
          // quotes the real calendar's.
          namesRoute: false,
        ),
        // The calendar page's bar, so the practice reads as the real thing.
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        toolbarHeight: AppBarMetrics.toolbarHeight,
        iconTheme: IconThemeData(
          size: AppBarMetrics.glyphSize,
          color: colorScheme.onSurface,
        ),
        actionsIconTheme: IconThemeData(
          size: AppBarMetrics.glyphSize,
          color: colorScheme.onSurface,
        ),
        actions: [
          // In the saved filters' slot, which the demo has no use for;
          // disabled, never hidden, until there is something to undo.
          AutomationId(
            identifier: SemanticsIds.practiceReset,
            child: IconButton(
              tooltip: l10n.calendarGuideDemoReset,
              iconSize: AppBarMetrics.glyphSize,
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: demo == null || !demo.isDirty ? null : _reset,
            ),
          ),
          AutomationId(
            identifier: SemanticsIds.practiceFilterOpen,
            child: IconButton(
              tooltip: l10n.filterCalendar,
              isSelected: active > 0,
              iconSize: AppBarMetrics.glyphSize,
              // The calendar page's badge: on the glyph, out of the
              // button's merged node.
              icon: ExcludeSemantics(
                child: Badge.count(
                  count: active,
                  isLabelVisible: active > 0,
                  child: Icon(
                    active > 0
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                  ),
                ),
              ),
              onPressed: demo == null ? null : _openFilters,
            ),
          ),
          CalendarOverflowMenu(
            identifier: SemanticsIds.practiceMore,
            onAlerts: () => _say(l10n.calendarGuideWouldOpen(l10n.alertsTitle)),
            onExport: demo == null || demo.events.isEmpty
                ? null
                : () => _say(l10n.calendarGuideWouldShare),
            onGuide: () => _say(l10n.calendarGuideYouAreHere),
            onSettings: () =>
                _say(l10n.calendarGuideWouldOpen(l10n.calendarSettingsRow)),
          ),
        ],
      ),
      body: Column(
        children: [
          _PracticeBand(caption: _caption, candidates: _candidates),
          Expanded(
            child: Semantics(
              container: true,
              identifier: SemanticsIds.calendarGuidePractice,
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: l10n.calendarGuidePagePractice,
              child: demo == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        RepaintBoundary(child: _grid(context, l10n)),
                        const Divider(height: 1),
                        Expanded(child: _panel(context, l10n)),
                      ],
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: CalendarAddFab(
        identifier: SemanticsIds.practiceAddEvent,
        selectedDay: demo?.selectedDay,
        appearance: _appearance,
        extended: _fabExtended,
        onPressed: (day) => _sheets.run<void>(() => _addEvent(day)),
        onLongPressed: (day) => _sheets.run<void>(() => _addFromTemplate(day)),
      ),
    );
  }

  /// The calendar page's `TableCalendar`, its arguments copied, over the
  /// demo's per-day map.
  Widget _grid(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _appearance.accentOr(colorScheme.primary);
    final rowHeight = CalendarDayCell.rowHeightFor(
      CalendarDayBars.stripHeight(
        _appearance.maxDayBars,
        _appearance.markerStyle,
      ),
    );
    final cellStyle = _appearance.cellStyleFor(theme.brightness);
    final fadesOutside = demo.format == CalendarFormat.month;
    final barsResolver = _barsResolver!;

    Widget cell(DateTime day, {required bool isOutside}) => CalendarDayCell(
      day: day,
      isToday: isSameDay(day, demo.today),
      isSelected: isSameDay(day, demo.selectedDay),
      isOutside: isOutside,
      isWeekend: CalendarWeekend.isWeekend(day),
      todayStyle: _appearance.todayStyle,
      highlightWeekends: _appearance.highlightWeekends,
      accent: accent,
      cellStyle: cellStyle,
    );

    return TableCalendar<CalendarEvent>(
      firstDay: CalendarBounds.earliest,
      lastDay: CalendarBounds.latest,
      focusedDay: demo.focusedDay,
      selectedDayPredicate: (day) => isSameDay(demo.selectedDay, day),
      calendarFormat: demo.format,
      formatAnimationDuration: const Duration(milliseconds: 1),
      pageAnimationEnabled: false,
      availableGestures: AvailableGestures.horizontalSwipe,
      eventLoader: demo.eventsFor,
      startingDayOfWeek: startingDayOfWeekFor(_appearance.weekStart),
      weekendDays: CalendarWeekend.days,
      weekNumbersVisible: _appearance.showWeekNumbers,
      rowHeight: rowHeight,
      daysOfWeekHeight: CalendarDaysOfWeek.height,
      locale: l10n.localeName,
      availableCalendarFormats: {
        for (final format in CalendarFormat.values)
          format: _formatLabel(l10n, format),
      },
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: theme.textTheme.titleMedium!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        headerPadding: const EdgeInsets.all(GuideMetrics.practiceHeaderInset),
        leftChevronMargin: EdgeInsets.zero,
        rightChevronMargin: EdgeInsets.zero,
        leftChevronPadding: const EdgeInsets.all(
          GuideMetrics.practiceChevronPadding,
        ),
        rightChevronPadding: const EdgeInsets.all(
          GuideMetrics.practiceChevronPadding,
        ),
        leftChevronIcon: Icon(
          Icons.chevron_left_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
        rightChevronIcon: Icon(
          Icons.chevron_right_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      daysOfWeekStyle: CalendarDaysOfWeek.style(
        theme,
        highlightWeekends: _appearance.highlightWeekends,
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: true,
        weekNumberTextStyle: theme.textTheme.labelSmall!.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        markersMaxCount: 0,
      ),
      calendarBuilders: CalendarBuilders<CalendarEvent>(
        defaultBuilder: (context, day, _) => cell(day, isOutside: false),
        todayBuilder: (context, day, _) => cell(day, isOutside: false),
        selectedBuilder: (context, day, _) => cell(day, isOutside: false),
        outsideBuilder: (context, day, _) => cell(day, isOutside: fadesOutside),
        markerBuilder: (context, day, events) {
          final bars = demo.barsFor(day, events, barsResolver);
          if (bars.isEmpty) return const SizedBox.shrink();
          final isOutside =
              fadesOutside &&
              (day.month != demo.focusedDay.month ||
                  day.year != demo.focusedDay.year);
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: GuideMetrics.practiceMarkerInset,
              ),
              child: CalendarDayBars(
                bars: bars,
                maxBars: _appearance.maxDayBars,
                style: _appearance.markerStyle,
                opacity: isOutside ? CalendarDayCell.outsideAlpha : 1.0,
              ),
            ),
          );
        },
      ),
      onDaySelected: (selected, focused) {
        final day = DateTime.utc(selected.year, selected.month, selected.day);
        setState(() {
          demo.selectedDay = day;
          demo.focus(focused);
        });
        _say(
          l10n.calendarGuidePickedDay(_date(day), demo.eventsFor(day).length),
        );
      },
      onPageChanged: (focused) => setState(() => demo.focus(focused)),
    );
  }

  /// The panel on the page ground under the mode switch, as the calendar's
  /// bottom panel draws it.
  Widget _panel(BuildContext context, AppLocalizations l10n) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.pageGround,
      child: Column(
        children: [
          PanelModeBar(
            mode: demo.panelMode,
            onChanged: (mode) => _setPanelMode(l10n, mode),
            onTouched: () {},
            // The demo panel never covers the grid: the grid is what the
            // page is for.
            expanded: false,
            onToggleExpanded: null,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: RepaintBoundary(child: _panelBody(l10n)),
            ),
          ),
        ],
      ),
    );
  }

  List<CalendarEvent> _panelEvents(DateTime day) =>
      demo.filters.panelShowsAll ? demo.allEventsFor(day) : demo.eventsFor(day);

  Widget _panelBody(AppLocalizations l10n) {
    final day = demo.selectedDay;
    switch (demo.panelMode) {
      case CalendarPanelMode.day:
        return DaySummaryPanel(
          day: day,
          entries: _dayEntries(day),
          onEventTap: (event) => _openEvent(event, day),
          onToggleMissed: (event, missed) =>
              setState(() => _markPresence(event, day, missed: missed)),
          colorPalette: _palette,
        );
      case CalendarPanelMode.timeline:
        return DayTimelineView(
          day: day,
          events: _panelEvents(day),
          onEventTap: (event) => _openEvent(event, day),
          missedDisplay: _appearance.missedDisplay,
          isMissed: demo.isMissed,
        );
      case CalendarPanelMode.upcoming:
        return _upcoming(l10n);
    }
  }

  /// The day's entries with each one's presence and description read from
  /// the demo's own marks and rows: the shared resolver reads the real
  /// calendar's caches, which hold nothing for a demo event.
  List<DaySummaryEntry> _dayEntries(DateTime day) {
    final entries = _summaryResolver!.resolve(day, _panelEvents(day));
    return [
      for (final entry in entries)
        if (entry.event case final event?)
          DaySummaryEntry(
            key: entry.key,
            icon: entry.icon,
            color: entry.color,
            stripeAccent: entry.stripeAccent,
            title: entry.title,
            subtitle: entry.subtitle,
            description: _rowDescription(demo.descriptionFor(event, day)),
            priority: entry.priority,
            event: event,
            presenceTracked: entry.presenceTracked,
            missed: entry.presenceTracked && demo.isMissed(event, day),
          )
        else
          entry,
    ];
  }

  /// The resolver's rule for a row: trimmed, and a blank day shows none.
  static String? _rowDescription(String? raw) {
    final trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// What is coming over the demo's next weeks, drawn by the overview's and
  /// the day list's row builder, with presence from the demo's marks.
  Widget _upcoming(AppLocalizations l10n) {
    final occurrences = demo.upcoming();
    // Converted with nothing dropped, so the entries stay index for index
    // with the occurrences; the missed display is applied below, from the
    // demo's marks.
    final converted = AgendaListView.eventDayEntries(
      occurrences,
      l10n,
      false,
      showRecurrenceLabels: _appearance.showRecurrenceLabels,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    final hideMissed =
        _appearance.missedDisplay == CalendarMissedDisplay.hidden;
    final byDay = <DateTime, List<AgendaDayListEntry>>{};
    for (var i = 0; i < occurrences.length; i++) {
      final occurrence = occurrences[i];
      final entry = converted[i];
      final missed =
          entry.presenceTracked &&
          demo.isMissed(occurrence.event, occurrence.day);
      if (hideMissed && missed) continue;
      (byDay[occurrence.day] ??= []).add(
        AgendaDayListEntry(
          day: entry.day,
          icon: entry.icon,
          color: entry.color,
          title: entry.title,
          subtitle: entry.subtitle,
          missed: missed,
          eventId: entry.eventId,
          presenceTracked: entry.presenceTracked,
        ),
      );
    }
    final rows = buildAgendaDayListRows(
      byDay.keys.toList(),
      (day) => byDay[day]!,
      groupByDay: true,
      withMonths: true,
      keptCountOf: (day) => byDay[day]!.where((e) => !e.missed).length,
    );
    final padding = EdgeInsets.fromLTRB(
      RowMetrics.groupInset,
      FormMetrics.bodyTop,
      RowMetrics.groupInset,
      AppSpacing.fabClearance,
    );
    if (rows.isEmpty) {
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
    final builder = AgendaDayListRowBuilder(
      rows: rows,
      today: demo.today,
      onEntryTap: (entry) {
        final event = demo.byId(entry.eventId ?? '');
        if (event != null) _openEvent(event, entry.day);
      },
    );
    return ListView.builder(
      padding: padding,
      itemCount: rows.length,
      itemBuilder: builder.build,
    );
  }

  void _setFormat(CalendarFormat format) {
    final l10n = AppLocalizations.of(context)!;
    setState(() => demo.format = format);
    _say(l10n.calendarGuideDemoFormat(_formatLabel(l10n, format)));
  }

  void _setPanelMode(AppLocalizations l10n, CalendarPanelMode mode) {
    setState(() => demo.panelMode = mode);
    _say(switch (mode) {
      CalendarPanelMode.day => l10n.calendarGuideDemoPanelDay(
        l10n.panelModeDay,
      ),
      CalendarPanelMode.timeline => l10n.calendarGuideDemoPanelTimeline(
        l10n.panelModeTimeline,
      ),
      CalendarPanelMode.upcoming => l10n.calendarGuideDemoPanelUpcoming(
        l10n.upcomingEvents,
      ),
    });
  }

  void _reset() {
    setState(demo.reset);
    _caption.value = null;
  }

  Future<void> _openFilters() => _sheets.run<void>(() async {
    final picked = await CalendarFilterSheet.show(
      context,
      filters: demo.filters,
      sandbox: true,
    );
    if (picked == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    demo.filters = picked;
    _changed(l10n.calendarGuideDemoFiltered(picked.activeCount));
  });

  /// The add button: the sandboxed editor, its event joining the demo.
  Future<void> _addEvent(DateTime day) async {
    final result = await EventEditorSheet.show(
      context,
      defaultDate: day,
      appearance: _appearance,
      sandbox: true,
    );
    if (!mounted || result is! EventEditorSaved) return;
    final l10n = AppLocalizations.of(context)!;
    final event = demo.add(result.event, alerts: result.alerts);
    final skipped = result.skippedDays;
    if (skipped != null) demo.setSkips(event.id, skipped);
    _changed(
      l10n.calendarGuideDemoAddedShort(
        calendarGuideQuote(event.title),
        _date(event.startDate),
      ),
    );
  }

  /// The add button's long press: the owner's own templates, read only, the
  /// one picked stamped out into the demo.
  Future<void> _addFromTemplate(DateTime day) async {
    final choice = await EventTemplatePickerSheet.show(context);
    if (!mounted || choice == null) return;
    final l10n = AppLocalizations.of(context)!;
    switch (choice) {
      case EventTemplatePicked(:final template):
        final event = template.buildEvent(id: demo.newId(), startDate: day);
        demo.add(event);
        _changed(l10n.calendarGuideDemoTemplate(calendarGuideQuote(event.title)));
      case EventTemplateBlank():
        await _addEvent(day);
      case EventTemplateQuickAlarm():
        _say(l10n.calendarGuideWouldOpen(l10n.quickAlarmTitle));
    }
  }

  void _openEvent(CalendarEvent event, DateTime day) =>
      _sheets.run<void>(() => _eventTrip(event, day));

  /// The calendar's trip through an event's sheets — detail, editor,
  /// description, dates, skip — with every answer written to the demo.
  Future<void> _eventTrip(CalendarEvent event, DateTime day) async {
    var current = event;
    while (mounted) {
      final action = await EventDetailSheet.show(
        context,
        event: current,
        day: day,
        colorPalette: _palette,
        // Only while the event keeps one text per day, as the real flow
        // passes it: a dormant row must not show as the event's text.
        pendingOccurrenceDescription: OccurrenceDescriptions.appliesTo(current)
            ? demo.overrideFor(current.id, day)
            : null,
        isMissed: demo.isMissed,
        // The sheet may fire these from its `dispose` (a pending tick on
        // dismissal), where `setState` throws: they write the demo and
        // leave the rebuild to [_rebuildSoon] and to the return below.
        onEventChanged: (updated) {
          current = updated;
          demo.replace(updated);
          _rebuildSoon();
        },
        onOccurrenceChanged: (occurrenceDay, description) {
          demo.setDescription(current.id, occurrenceDay, description);
          _rebuildSoon();
        },
        onPresenceChanged: (occurrenceDay, missed) {
          _markPresence(current, occurrenceDay, missed: missed);
          _rebuildSoon();
        },
      );
      if (mounted) setState(() {});
      if (action == null || !mounted) return;
      final l10n = AppLocalizations.of(context)!;
      switch (action) {
        case EventDetailAction.openNote:
          // A demo event carries no note: the sandboxed editor has no
          // Linked note row.
          return;
        case EventDetailAction.skipOccurrence:
          demo.skip(current.id, day);
          _changed(
            l10n.calendarGuideDemoSkipped(_date(day), calendarGuideQuote(current.title)),
          );
          return;
        case EventDetailAction.editDescription:
          final edited = await _editDescription(current, day);
          if (edited == null || !mounted) continue;
          current = edited;
          _changed(l10n.calendarGuideDemoChanged(calendarGuideQuote(current.title)));
        case EventDetailAction.addDate:
        case EventDetailAction.showDates:
          final dates = current.explicitDates;
          if (dates == null) continue;
          final picked = await CalendarDatePickerSheet.pickMulti(
            context,
            initialSelection: dates,
            firstDate: CalendarBounds.earliest,
            lastDate: CalendarBounds.latest,
            dayLoad: (d) => demo.allEventsFor(d).length,
            appearance: _appearance,
            initialView: action == EventDetailAction.showDates
                ? CalendarDatePickerView.list
                : CalendarDatePickerView.month,
          );
          if (!mounted) return;
          if (picked == null || setEquals(picked, dates)) continue;
          current = current.withExplicitDates(picked);
          demo.replace(current);
          _changed(l10n.calendarGuideDemoChanged(calendarGuideQuote(current.title)));
          if (!demo.occursOn(current, day)) return;
        case EventDetailAction.edit:
          final result = await EventEditorSheet.show(
            context,
            defaultDate: day,
            initialEvent: current,
            occurrenceDay: day,
            pendingOccurrenceDescription:
                OccurrenceDescriptions.appliesTo(current)
                ? demo.overrideFor(current.id, day)
                : null,
            appearance: _appearance,
            showBack: true,
            sandbox: true,
            initialSkippedDays: demo.skipsFor(current.id),
            initialAlerts: demo.alertsFor(current.id),
          );
          if (!mounted) return;
          switch (result) {
            case null:
              return;
            case EventEditorBack():
              continue;
            case EventEditorDeleted():
              demo.remove(current.id);
              _changed(l10n.calendarGuideDemoDeleted(calendarGuideQuote(current.title)));
              return;
            case EventEditorSaved():
              current = result.event;
              demo.replace(current, alerts: result.alerts);
              final skipped = result.skippedDays;
              if (skipped != null) demo.setSkips(current.id, skipped);
              final occurrenceDay = result.occurrenceDay;
              if (occurrenceDay != null) {
                demo.setDescription(
                  current.id,
                  occurrenceDay,
                  result.occurrenceDescription,
                );
              }
              _changed(l10n.calendarGuideDemoChanged(calendarGuideQuote(current.title)));
              if (!demo.occursOn(current, day)) return;
          }
      }
    }
  }

  /// The detail sheet's quick description edit: the day's own text for an
  /// event that keeps one per day, else the event's. Null when nothing
  /// changed.
  Future<CalendarEvent?> _editDescription(
    CalendarEvent event,
    DateTime day,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final perDay =
        event.perOccurrenceDescriptions && event.rule is! OneTimeRecurrence;
    final seed = perDay
        ? (demo.descriptionFor(event, day) ?? '')
        : (event.description ?? '');
    final settings = await SettingsService.getInstance();
    final limit = await settings.getEventDescriptionLimit();
    if (!mounted) return null;
    final edited = await EventDescriptionSheet.show(
      context,
      initialText: seed,
      heading: event.title,
      limit: limit,
      grandfatheredLength: seed.length,
      scopeCaption: perDay
          ? l10n.eventDescriptionScopeThisDayHint
          : (event.rule is OneTimeRecurrence
                ? null
                : l10n.eventDescriptionAppliesAllOccurrences),
      colorPalette: _palette,
    );
    if (edited == null || edited == seed) return null;
    if (perDay) {
      demo.setDescription(event.id, day, edited);
      return event;
    }
    final updated = event.copyWith(
      description: edited,
      clearDescription: edited.isEmpty,
    );
    demo.replace(updated);
    return updated;
  }
}

/// The band under the bar: "Nothing here is saved." that never changes, and
/// under it the live line that says what the last action did. Its height is
/// the tallest caption's, so a caption changes words, never the layout.
class _PracticeBand extends StatelessWidget {
  const _PracticeBand({required this.caption, required this.candidates});

  final ValueListenable<String?> caption;
  final List<String> candidates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final ink = colorScheme.onPrimaryContainer;
    final captionStyle = TextStyle(
      fontSize: FormMetrics.captionSize,
      height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
      color: ink,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: GuideMetrics.bannerMaxTextScale,
      child: Semantics(
        container: true,
        identifier: SemanticsIds.calendarGuidePracticeBanner,
        child: ColoredBox(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RowMetrics.groupInset,
              vertical: GuideMetrics.bannerVerticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    calendarGuidePracticeIcon,
                    size: GuideMetrics.bannerGlyphSize,
                    color: ink,
                  ),
                ),
                const SizedBox(width: GuideMetrics.bannerGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.calendarGuidePracticeBanner,
                        style: TextStyle(
                          fontSize: GuideMetrics.bannerTitleFontSize,
                          fontWeight: GuideMetrics.bannerTitleFontWeight,
                          height:
                              GuideMetrics.bannerTitleLineHeight /
                              GuideMetrics.bannerTitleFontSize,
                          color: ink,
                        ),
                      ),
                      ValueListenableBuilder<String?>(
                        valueListenable: caption,
                        builder: (context, text, _) => FormCaptionSlot(
                          candidates: [
                            for (final candidate in candidates)
                              Text(candidate, style: captionStyle),
                          ],
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              text ?? l10n.calendarGuidePracticeIdle,
                              style: captionStyle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
