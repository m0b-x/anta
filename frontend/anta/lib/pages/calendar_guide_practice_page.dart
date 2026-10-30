import 'dart:math' as math;

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
import '../models/calendar_guide_coach.dart';
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
/// bar says so once, and its second line walks her through a five-step tour
/// (D42), one tap at a time.
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

  /// The band's tour: its line is the next tap to make, or the report of an
  /// action the page cannot show (D47).
  final GuideCoach _coach = GuideCoach(
    calendarGuideTourSteps,
    closing: calendarGuideTourDone,
  );

  /// Bumped on every change to [_coach]: the band and Start over listen to
  /// it, so a new line rebuilds them and nothing else.
  final ValueNotifier<int> _coachRevision = ValueNotifier<int>(0);

  /// The add button stays labelled: the demo has no scroll-driven collapse,
  /// because nothing on this page animates.
  final ValueNotifier<bool> _fabExtended = ValueNotifier<bool>(true);

  final SheetGuard _sheets = SheetGuard();

  /// Every line the band can show, built once per locale.
  List<String> _candidates = const [];
  Locale? _candidatesLocale;

  /// The grid's month title, `table_calendar`'s own format.
  final GuideLocaleFormat _monthTitle = GuideLocaleFormat(DateFormat.yMMMM);

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
    _candidates = _coach.candidates(l10n, _reports(l10n));
  }

  @override
  void dispose() {
    _coachRevision.dispose();
    _fabExtended.dispose();
    super.dispose();
  }

  static String _formatLabel(AppLocalizations l10n, CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
  }

  /// The reports of the actions that show nothing on the page (D47): the
  /// rows that would leave for another page or share a file. Every other
  /// action's result is on the grid, the panel or the bar.
  static List<String> _reports(AppLocalizations l10n) => [
    for (final what in [
      l10n.calendarOverview,
      l10n.alertsTitle,
      l10n.calendarSettingsRow,
      l10n.quickAlarmTitle,
    ])
      l10n.calendarGuideWouldOpen(what),
    l10n.calendarGuideWouldShare,
    l10n.calendarGuideYouAreHere,
  ];

  /// [action], a tour step's, just happened: the band moves on.
  void _did(String action) {
    _coach.did(action);
    _coachRevision.value++;
  }

  /// An action that shows nothing on the page: its report is the band's
  /// line until the next action.
  void _say(GuideLine report) {
    _coach.say(report);
    _coachRevision.value++;
  }

  /// An action that is no tour step: a standing report belonged to the one
  /// before it, so the band goes back to the instruction.
  void _clearReport() {
    _coach.clearReport();
    _coachRevision.value++;
  }

  void _skip() {
    _coach.skip();
    _coachRevision.value++;
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
          onPageSelected: (_) => _say(
            (l10n) => l10n.calendarGuideWouldOpen(l10n.calendarOverview),
          ),
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
          // disabled, never hidden, until there is something to undo — a
          // change to the demo or a step of the tour.
          ValueListenableBuilder<int>(
            valueListenable: _coachRevision,
            builder: (context, _, _) => AutomationId(
              identifier: SemanticsIds.practiceReset,
              child: IconButton(
                tooltip: l10n.calendarGuideDemoReset,
                iconSize: AppBarMetrics.glyphSize,
                icon: const Icon(Icons.restart_alt_rounded),
                onPressed:
                    demo == null || !(demo.isDirty || _coach.advanced)
                    ? null
                    : _reset,
              ),
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
            onAlerts: () => _say(
              (l10n) => l10n.calendarGuideWouldOpen(l10n.alertsTitle),
            ),
            onExport: demo == null || demo.events.isEmpty
                ? null
                : () => _say((l10n) => l10n.calendarGuideWouldShare),
            onGuide: () => _say((l10n) => l10n.calendarGuideYouAreHere),
            onSettings: () => _say(
              (l10n) => l10n.calendarGuideWouldOpen(l10n.calendarSettingsRow),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _PracticeBand(
            coach: _coach,
            revision: _coachRevision,
            candidates: _candidates,
            onSkip: _skip,
          ),
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
    final monthly = demo.format == CalendarFormat.month;
    final fadesOutside = monthly;
    final barsResolver = _barsResolver!;
    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w600,
    );

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
        titleTextStyle: titleStyle,
        headerPadding: const EdgeInsets.symmetric(
          horizontal: GuideMetrics.practiceHeaderInset,
        ),
        leftChevronMargin: EdgeInsets.zero,
        rightChevronMargin: EdgeInsets.zero,
        leftChevronPadding: const EdgeInsets.all(
          GuideMetrics.practiceChevronPadding,
        ),
        rightChevronPadding: const EdgeInsets.all(
          GuideMetrics.practiceChevronPadding,
        ),
        // The chevrons are bare ink wells: the tooltip on the glyph is
        // what names each one.
        leftChevronIcon: Tooltip(
          message: monthly
              ? l10n.dayListPreviousMonth
              : l10n.overviewPeriodPrevious,
          child: Icon(
            Icons.chevron_left_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        rightChevronIcon: Tooltip(
          message: monthly ? l10n.dayListNextMonth : l10n.overviewPeriodNext,
          child: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
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
        // Plain text: the stock title is a gesture detector with no
        // callback, which still reads as a button that does nothing.
        headerTitleBuilder: (context, day) => Text(
          _monthTitle.of(l10n).format(day),
          style: titleStyle,
          textAlign: TextAlign.center,
        ),
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
        // A day without a bar leaves nothing to open: the band keeps
        // asking for one with.
        if (demo.eventsFor(day).isNotEmpty) {
          _did('picked');
        } else {
          _clearReport();
        }
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
            onChanged: (mode) {
              setState(() => demo.panelMode = mode);
              _clearReport();
            },
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
          onToggleMissed: (event, missed) {
            setState(() => demo.setPresence(event.id, day, missed: missed));
            _clearReport();
          },
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
    setState(() => demo.format = format);
    _clearReport();
  }

  /// Start over: the seed back, and the tour from its first step.
  void _reset() {
    setState(demo.reset);
    _coach.reset();
    _coachRevision.value++;
  }

  Future<void> _openFilters() => _sheets.run<void>(() async {
    final picked = await CalendarFilterSheet.show(
      context,
      filters: demo.filters,
      sandbox: true,
    );
    if (picked == null || !mounted) return;
    setState(() => demo.filters = picked);
    if (picked.activeCount > 0) {
      _did('filtered');
    } else {
      _clearReport();
    }
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
    final event = demo.add(result.event, alerts: result.alerts);
    final skipped = result.skippedDays;
    if (skipped != null) demo.setSkips(event.id, skipped);
    setState(() {});
    _did('added');
  }

  /// The add button's long press: the owner's own templates, read only, the
  /// one picked stamped out into the demo.
  Future<void> _addFromTemplate(DateTime day) async {
    final choice = await EventTemplatePickerSheet.show(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case EventTemplatePicked(:final template):
        final event = template.buildEvent(id: demo.newId(), startDate: day);
        setState(() => demo.add(event));
        _did('added');
      case EventTemplateBlank():
        await _addEvent(day);
      case EventTemplateQuickAlarm():
        _say((l10n) => l10n.calendarGuideWouldOpen(l10n.quickAlarmTitle));
    }
  }

  void _openEvent(CalendarEvent event, DateTime day) =>
      _sheets.run<void>(() => _eventTrip(event, day));

  /// The calendar's trip through an event's sheets — detail, editor,
  /// description, dates, skip — with every answer written to the demo.
  ///
  /// The tour steps the trip makes reach the band only when it returns: a
  /// sheet's barrier blocks the page's semantics, so a line changed under
  /// it would never be announced.
  Future<void> _eventTrip(CalendarEvent event, DateTime day) async {
    final steps = ['opened'];
    try {
      await _eventSheets(event, day, steps);
    } finally {
      if (mounted) {
        for (final step in steps) {
          _did(step);
        }
      }
    }
  }

  /// The trip's sheets; each tour step made is added to [steps].
  Future<void> _eventSheets(
    CalendarEvent event,
    DateTime day,
    List<String> steps,
  ) async {
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
          demo.setPresence(current.id, occurrenceDay, missed: missed);
          _rebuildSoon();
        },
      );
      if (mounted) setState(() {});
      if (action == null || !mounted) return;
      switch (action) {
        case EventDetailAction.openNote:
          // A demo event carries no note: the sandboxed editor has no
          // Linked note row.
          return;
        case EventDetailAction.skipOccurrence:
          setState(() => demo.skip(current.id, day));
          _clearReport();
          return;
        case EventDetailAction.editDescription:
          final edited = await _editDescription(current, day);
          if (edited == null || !mounted) continue;
          current = edited;
          setState(() {});
          steps.add('changed');
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
          setState(() => demo.replace(current));
          steps.add('changed');
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
              setState(() => demo.remove(current.id));
              _clearReport();
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
              setState(() {});
              steps.add('changed');
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
/// under it the tour's line — the next tap, or what an action that shows
/// nothing would have done — with the skip at the row's end. Its height is
/// the tallest line's, so a line changes words, never the layout.
class _PracticeBand extends StatelessWidget {
  const _PracticeBand({
    required this.coach,
    required this.revision,
    required this.candidates,
    required this.onSkip,
  });

  final GuideCoach coach;

  /// Bumped on every change to [coach].
  final ValueListenable<int> revision;
  final List<String> candidates;
  final VoidCallback onSkip;

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
            child: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (context, _, _) => Row(
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
                        FormCaptionSlot(
                          candidates: [
                            for (final candidate in candidates)
                              Text(candidate, style: captionStyle),
                          ],
                          // A node of its own: merged into the band, the
                          // live region was the band, and every line
                          // re-read "Nothing here is saved." first.
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            child: Text(coach.line(l10n), style: captionStyle),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // No coachGap, unlike a card's line: the target's own
                  // inset keeps the glyph off the text, and the gap's 8 dp
                  // wrapped the German line to a fifth row at 1.3 (137 dp,
                  // past D39).
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: _skipInset(MediaQuery.textScalerOf(context)),
                    ),
                    child: FormTrailingButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: l10n.calendarGuideSkipStep,
                      identifier: SemanticsIds.practiceSkip,
                      color: ink,
                      disabledColor: ink.withValues(
                        alpha: FormMetrics.disabledOpacity,
                      ),
                      // Disabled, never hidden, once the tour is done.
                      onPressed: coach.finished ? null : onSkip,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The band's skip sits this far down: its 48 dp target, and so its
  /// glyph, centred on the first row of the tour's line under the title,
  /// not across the two. It never adds height — the inset plus the target
  /// stays under the title plus the line's two-row slot at every [scaler]
  /// the band's clamp allows.
  static double _skipInset(TextScaler scaler) {
    final titleLine = scaler.scale(GuideMetrics.bannerTitleLineHeight);
    final captionLine = scaler.scale(FormMetrics.captionLineHeight);
    return math.max(
      0,
      titleLine - (FormMetrics.trailingButtonSize - captionLine) / 2,
    );
  }
}
