import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_bar_metrics.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_bounds.dart';
import '../constants/guide_metrics.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_coach.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../models/recurrence_rule.dart';
import '../services/category_service.dart';
import '../services/day_bars_resolver.dart';
import '../services/day_summary_resolver.dart';
import '../services/settings_service.dart';
import '../utils/guide_locale_format.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/sheet_guard.dart';
import '../widgets/automation_id.dart';
import '../widgets/calendar_add_fab.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/calendar_filter_sheet.dart';
import '../widgets/calendar_guide_bar.dart';
import '../widgets/calendar_guide_demo_panel.dart';
import '../widgets/calendar_guide_grid.dart';
import '../widgets/calendar_header_menus.dart';
import '../widgets/event_description_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/event_template_picker_sheet.dart';
import '../widgets/form_rows.dart';

/// The guide's practice calendar: the real calendar's grid, panel, menus and
/// sheets over demo events, where a newcomer can tap, add, change and delete
/// freely because nothing is saved.
///
/// Every sheet it opens is the real one in its sandbox mode, and every
/// answer lands in a [GuideDemoCalendar] this page's `State` owns — never in
/// a bloc, a service or one of the calendar's static caches. A band under the
/// bar says so once, and its second line walks her through the [lesson]'s
/// tour (D42, D56), one tap at a time. One page for both lessons (D54): the
/// lesson picks the seed, the tour and the route's name, never the screen.
class CalendarGuidePracticePage extends StatefulWidget {
  const CalendarGuidePracticePage({
    super.key,
    this.lesson = GuidePracticeLesson.events,
  });

  final GuidePracticeLesson lesson;

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
  late final GuideCoach _coach = GuideCoach(
    widget.lesson.steps,
    closing: widget.lesson.closing,
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
        lesson: widget.lesson,
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

  /// The reports of the actions that show nothing on the page (D47): the
  /// rows that would leave for another page or share a file. Every other
  /// action's result is on the grid, the panel or the bar.
  static List<String> _reports(AppLocalizations l10n) => [
    for (final what in [
      l10n.calendarOverview,
      l10n.reportTitle,
      l10n.alertsTitle,
      l10n.calendarSettingsRow,
      l10n.quickAlarmTitle,
    ])
      l10n.calendarGuideWouldOpen(what),
    l10n.calendarGuideWouldShare,
    l10n.calendarGuideYouAreHere,
  ];

  /// [action] just happened: the band moves on when it is a step of this
  /// lesson's tour.
  void _did(String action) => _mark([action]);

  /// [actions] happened together (one Apply can hide a category and set a
  /// trait): every one that is a step of this lesson's tour is done. The
  /// page reports its actions whatever the lesson, so one that is no step
  /// here counts as any other action: it clears a standing report.
  void _mark(Iterable<String> actions) {
    final steps = actions.where(_coach.hasStep).toList();
    if (steps.isEmpty) {
      _clearReport();
      return;
    }
    for (final step in steps) {
      _coach.did(step);
    }
    _coachRevision.value++;
  }

  /// An action that shows nothing on the page: its report is the band's
  /// line until the next action.
  void _say(GuideLine report) {
    _coach.say(report);
    _coachRevision.value++;
  }

  /// The title menu's other pages: each says the page it would open. The
  /// menu never hands back the page it is on, and this page is the
  /// calendar.
  void _openPage(CalendarViewPage page) {
    switch (page) {
      case CalendarViewPage.calendar:
        return;
      case CalendarViewPage.overview:
        _say((l10n) => l10n.calendarGuideWouldOpen(l10n.calendarOverview));
      case CalendarViewPage.report:
        _say((l10n) => l10n.calendarGuideWouldOpen(l10n.reportTitle));
    }
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
    final demo = _demo;
    if (demo != null) _resolversFor(l10n);
    final active = demo?.filters.activeCount ?? 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: GuideCalendarBar(
        format: demo?.format ?? CalendarFormat.month,
        onFormatSelected: demo == null ? null : (format) => _setFormat(format),
        onPageSelected: _openPage,
        // In the saved filters' slot, which the demo has no use for;
        // disabled, never hidden, until there is something to undo — a
        // change to the demo or a step of the tour.
        savedFiltersSlot: ValueListenableBuilder<int>(
          valueListenable: _coachRevision,
          builder: (context, _, _) => AutomationId(
            identifier: SemanticsIds.practiceReset,
            child: IconButton(
              tooltip: l10n.calendarGuideDemoReset,
              iconSize: AppBarMetrics.glyphSize,
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: demo == null || !(demo.isDirty || _coach.advanced)
                  ? null
                  : _reset,
            ),
          ),
        ),
        filterSlot: GuideCalendarBar.filterButton(
          identifier: SemanticsIds.practiceFilterOpen,
          tooltip: l10n.filterCalendar,
          activeCount: active,
          onPressed: demo == null ? null : _openFilters,
        ),
        moreSlot: CalendarOverflowMenu(
          identifier: SemanticsIds.practiceMore,
          onAlerts: () =>
              _say((l10n) => l10n.calendarGuideWouldOpen(l10n.alertsTitle)),
          onExport: demo == null || demo.events.isEmpty
              ? null
              : () => _say((l10n) => l10n.calendarGuideWouldShare),
          onGuide: () => _say((l10n) => l10n.calendarGuideYouAreHere),
          onSettings: () => _say(
            (l10n) => l10n.calendarGuideWouldOpen(l10n.calendarSettingsRow),
          ),
        ),
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
              identifier: switch (widget.lesson) {
                GuidePracticeLesson.events =>
                  SemanticsIds.calendarGuidePractice,
                GuidePracticeLesson.filtering =>
                  SemanticsIds.calendarGuidePracticeFiltering,
              },
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: widget.lesson.title(l10n),
              child: demo == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        RepaintBoundary(
                          child: GuideCalendarGrid(
                            demo: demo,
                            appearance: _appearance,
                            barsResolver: _barsResolver!,
                            monthTitle: _monthTitle,
                            onDaySelected: _pickDay,
                            onPageChanged: (focused) =>
                                setState(() => demo.focus(focused)),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: GuideDemoPanel(
                            demo: demo,
                            appearance: _appearance,
                            palette: _palette,
                            summaryResolver: _summaryResolver!,
                            bottomClearance: AppSpacing.fabClearance,
                            onModeChanged: (mode) {
                              setState(() => demo.panelMode = mode);
                              _clearReport();
                            },
                            onEventTap: _openEvent,
                            onToggleMissed: (event, day, missed) {
                              setState(
                                () => demo.setPresence(
                                  event.id,
                                  day,
                                  missed: missed,
                                ),
                              );
                              _clearReport();
                            },
                          ),
                        ),
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

  void _pickDay(DateTime day, DateTime focused) {
    setState(() {
      demo.selectedDay = day;
      demo.focus(focused);
    });
    // A day without a bar leaves nothing to open: the band keeps asking for
    // one with.
    if (demo.eventsFor(day).isNotEmpty) {
      _did('picked');
    } else {
      _clearReport();
    }
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

  /// The funnel: the sandboxed filter sheet, its answer the demo's filters.
  ///
  /// The tours' steps are read from what the sheet returns — it reports
  /// only on Apply — and reach the band once it is closed, as the event
  /// trip's do. A dismissal is an action too (D49): it marks only the
  /// opening, and clears a standing report in either lesson.
  Future<void> _openFilters() => _sheets.run<void>(() async {
    final before = demo.filters;
    final picked = await CalendarFilterSheet.show(
      context,
      filters: before,
      sandbox: true,
    );
    if (!mounted) return;
    if (picked == null) {
      _did('funnel');
      return;
    }
    setState(() => demo.filters = picked);
    final hidesCategories = picked.hiddenCategoryIds.isNotEmpty;
    // Every axis but the categories, a layer turned off included: the
    // badge's count less the one the categories add.
    final traits = picked.activeCount - (hidesCategories ? 1 : 0);
    // Taking the filters off counts only once both kinds were put on: the
    // closing line says everything is back, which must be true when read.
    final cleared =
        picked.activeCount == 0 &&
        before.activeCount > 0 &&
        _coach.hasDone('category') &&
        _coach.hasDone('trait');
    _mark([
      'funnel',
      if (picked.activeCount > 0) 'filtered',
      if (hidesCategories) 'category',
      if (traits > 0) 'trait',
      if (cleared) 'reset',
    ]);
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
      if (mounted) _mark(steps);
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
