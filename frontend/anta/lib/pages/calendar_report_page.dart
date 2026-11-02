import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/calendar_report/calendar_report_bloc.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_state.dart';
import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_alerts.dart';
import '../constants/report_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_permission_check.dart';
import '../controllers/calendar_export_controller.dart';
import '../controllers/event_sheets_flow.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/event_digest.dart';
import '../models/export_format.dart';
import '../models/overview_period.dart';
import '../models/report_look.dart';
import '../models/report_period_choice.dart';
import '../services/alert_keep_notice.dart';
import '../services/app_navigator.dart';
import '../services/calendar_report_service.dart';
import '../services/settings_service.dart';
import '../utils/event_agenda.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/report_labels.dart';
import '../utils/report_markdown.dart';
import '../utils/sheet_guard.dart';
import '../widgets/automation_id.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/calendar_header_menus.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/digest_editor_sheet.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/form_rows.dart';
import '../widgets/report_body.dart';
import '../widgets/report_group_stack.dart';
import '../widgets/report_more_categories_sheet.dart';

/// The calendar's third view (A): what happened and what is planned over a
/// period, folded from the app-wide calendar into one `CalendarReport` by the
/// page's own bloc and service (U, D30).
///
/// [look] is the overview's period and allowlist when its view menu opened
/// the report (D35) — for this visit; opened from the calendar or restored at
/// launch, the report reads what it remembers.
class CalendarReportPage extends StatelessWidget {
  const CalendarReportPage({super.key, this.look})
    : _service = null,
      _clock = DateTime.now,
      _nextFrame = null;

  /// Hands the page the [service] it folds through, so a suite can count its
  /// folds; the [clock] today is read from, so no case reads the wall clock;
  /// and what a fold waits on before it runs ([nextFrame]), so a suite can
  /// hold a refold open.
  @visibleForTesting
  const CalendarReportPage.forTesting({
    super.key,
    this.look,
    required CalendarReportService service,
    DateTime Function() clock = DateTime.now,
    Future<void> Function()? nextFrame,
  }) : _service = service,
       _clock = clock,
       _nextFrame = nextFrame;

  final ReportLook? look;
  final CalendarReportService? _service;
  final DateTime Function() _clock;
  final Future<void> Function()? _nextFrame;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final calendar = context.read<CalendarBloc>();
        // Restored at launch, the report may be the first calendar surface
        // to open: the overview's rule.
        if (calendar.isStale) calendar.add(const LoadCalendarEvents());
        return CalendarReportBloc(
          service: _service ?? CalendarReportService(),
          calendar: calendar,
          settings: SettingsService.getInstance(),
          clock: _clock,
          nextFrame: _nextFrame,
        )..add(ReportOpened(look: look));
      },
      child: _ReportView(clock: _clock),
    );
  }
}

class _ReportView extends StatefulWidget {
  const _ReportView({required this.clock});

  final DateTime Function() clock;

  @override
  State<_ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<_ReportView>
    with WidgetsBindingObserver, RouteAware {
  /// The ⋮ menu's `.ics` export, answered only when this page started it.
  final CalendarExportController _export = CalendarExportController();

  PageRoute<dynamic>? _route;
  bool _pickerOpen = false;

  /// Whether a page covers this one: a resume underneath asks nothing, and
  /// [didPopNext] asks once on the way back (the overview's rule).
  bool _covered = false;

  /// The body's scroll: "Show less" moves it so "n more" stays under the
  /// finger (S), and a presence mark's refold rebuilds around the same
  /// object, so the offset holds.
  final ScrollController _scroll = ScrollController();

  /// Which groups are open and which show every row, per visit (X).
  final ReportGroupFolds _folds = ReportGroupFolds();

  /// Guards the detail sheet a row opens, the trip from it and the "n more
  /// categories" sheet against a double tap — one slot, so the cap row and
  /// a row never stack two sheets.
  final SheetGuard _sheetGuard = SheetGuard();

  /// How many Keeps this page has heard of; a detail-sheet trip compares it
  /// at its start and after each step, as on the calendar.
  int _keepsHeard = 0;

  /// The trip through a row's sheets, as the overview's: the appearance and
  /// the palette are the shown state's, read when a sheet needs them.
  late final EventSheetsFlow _sheets = EventSheetsFlow(
    guard: _sheetGuard,
    appearance: () => switch (context.read<CalendarReportBloc>().state) {
      ReportShown(:final appearance) => appearance,
      _ => const CalendarAppearance(),
    },
    palette: () => switch (context.read<CalendarReportBloc>().state) {
      ReportShown(:final palette) => palette,
      _ => MarkdownColorPalette.presets,
    },
    keepsHeard: () => _keepsHeard,
  );

  /// Missed rows marked and not yet folded away, by `(eventId, day)`: a
  /// second tap on the same row before the refold lands would write the
  /// mark twice. A key leaves only with its row — the first report whose
  /// Missed no longer lists it — so neither an unrelated Ready nor a failed
  /// write (the calendar bloc logs it and emits nothing; the row stays
  /// quiet) speaks for a mark it did not fold (D42).
  final Set<(String, DateTime)> _marking = {};

  /// How many times the page has armed and released its [EndSlackSliver];
  /// the sliver acts on a count that moved, so a build only reads them. A
  /// notifier, so a fold rebuilds the slack and not every card.
  final ValueNotifier<({int arms, int releases})> _slack = ValueNotifier((
    arms: 0,
    releases: 0,
  ));

  /// The report and the look the bloc last showed, which a new state is
  /// compared with before it is drawn, and that report's Missed rows by
  /// `(eventId, day)`.
  CalendarReport? _heardReport;
  ({OverviewPeriod period, Set<String> categoryIds})? _heardLook;
  Set<(String, DateTime)> _heardMissed = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The alarm page's Keep, as the overview hears it: this page reads the
    // same bloc, and may be the only one open when Keep is pressed.
    AlertKeepNotice.instance.addListener(_serveKeepNotice);
    if (AlertKeepNotice.instance.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _serveKeepNotice());
    }
    // A report digest's tap collapses onto a live report rather than
    // pushing a second one, so its look arrives through the notifier.
    AppNavigator.pendingReportLook.addListener(_serveReportLook);
    if (AppNavigator.pendingReportLook.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _serveReportLook());
    }
  }

  /// Serves — and clears — the look `AppNavigator.toCalendarReportLook`
  /// published for the report it collapsed onto, as the overview serves a
  /// digest's look; the bloc's events run one at a time, so a look heard
  /// while the settings load still lands after them.
  void _serveReportLook() {
    if (!mounted) return;
    final look = AppNavigator.pendingReportLook.value;
    if (look == null) return;
    final route = ModalRoute.of(context);
    if (route != null && !AppNavigator.servesReportLook(route)) return;
    // Cleared before it is acted on, so a page mounting later cannot replay
    // a trip already made.
    AppNavigator.pendingReportLook.value = null;
    context.read<CalendarReportBloc>().add(ReportLookArrived(look));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && !identical(route, _route)) {
      if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
      _route = route;
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  /// The larger of the keyboard and the system inset, which the body pads
  /// its bottom by.
  double get _bottomClearance => math.max(
    MediaQuery.viewInsetsOf(context).bottom,
    MediaQuery.viewPaddingOf(context).bottom,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlertKeepNotice.instance.removeListener(_serveKeepNotice);
    AppNavigator.pendingReportLook.removeListener(_serveReportLook);
    if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
    _scroll.dispose();
    _slack.dispose();
    super.dispose();
  }

  /// The alarm page's Keep changed an event behind the bloc's back: counted,
  /// so a detail sheet open here learns of it, and the events reloaded while
  /// the notice still stands.
  ///
  /// Never takes the notice (the overview's rule): a calendar beneath this
  /// page has taken it already when the flag is down, and with none beneath,
  /// the calendar an Open event pushes over this page must still find it
  /// standing to defer its sheet to the reload.
  void _serveKeepNotice() {
    if (!mounted) return;
    _keepsHeard++;
    if (!AlertKeepNotice.instance.hasPending) return;
    context.read<CalendarBloc>().add(const LoadCalendarEvents());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_covered) _askAgain();
  }

  @override
  void didPushNext() => _covered = true;

  @override
  void didPopNext() {
    _covered = false;
    _askAgain();
  }

  /// Back in front: a new day moves the periods holding today and asks the
  /// rest too; otherwise the report asks again for what changes with no
  /// calendar event (D32).
  void _askAgain() {
    final bloc = context.read<CalendarReportBloc>();
    final today = EventAgenda.dateOnly(widget.clock());
    final state = bloc.state;
    if (state is ReportShown && state.today != today) {
      bloc.add(ReportDayChanged(today));
    } else {
      bloc.add(const ReportResumed());
    }
  }

  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  /// Calendar settings can delete a category, which reassigns its events
  /// behind the service's cache without a revision, so the events reload
  /// after the trip — as the calendar and the overview do.
  Future<void> _openSettings() async {
    final calendar = context.read<CalendarBloc>();
    await AppNavigator.toCalendarSettings(context);
    if (!mounted) return;
    calendar.add(const LoadCalendarEvents());
  }

  /// One export at a time, the share's included (D46): share_plus answers a
  /// pending share as unavailable when a second starts, and the controller
  /// remembers one operation.
  void _exportEvents() {
    if (_export.isPending) return;
    final state = context.read<CalendarBloc>().state;
    if (state is! CalendarPageLoaded) return;
    _export.start(context, state.allEvents);
  }

  void _switchPage(CalendarViewPage page) {
    switch (page) {
      case CalendarViewPage.calendar:
        unawaited(AppNavigator.switchToCalendar(context));
      case CalendarViewPage.overview:
        unawaited(AppNavigator.switchToCalendarOverview(context));
      case CalendarViewPage.report:
        break;
    }
  }

  /// The multi picker over the allowlist, as the overview's: an empty
  /// allowlist opens with every offered row ticked, and a pick covering
  /// every offered row collapses back to empty, so a category created later
  /// is in scope too.
  Future<void> _pickCategories() async {
    if (_pickerOpen || _sheetGuard.isOpen) return;
    final bloc = context.read<CalendarReportBloc>();
    final state = bloc.state;
    if (state is! ReportShown) return;
    _pickerOpen = true;
    try {
      _blur();
      final current = state.categoryIds;
      final offered = {
        for (final category in CalendarCategories.visiblePlus(current))
          category.id,
      };
      final picked = await CategoryPickerSheet.pickMulti(
        context,
        selected: current.isEmpty ? offered : current,
      );
      if (picked == null || !mounted) return;
      final next = picked.containsAll(offered) ? const <String>{} : picked;
      if (setEquals(next, current)) return;
      bloc.add(ReportCategoriesPicked(next));
    } finally {
      _pickerOpen = false;
    }
  }

  static IconData _choiceIcon(ReportPeriodChoice c) {
    return switch (c) {
      ReportPeriodChoice.thisWeek ||
      ReportPeriodChoice.lastWeek ||
      ReportPeriodChoice.nextWeek => Icons.view_week_rounded,
      ReportPeriodChoice.thisMonth ||
      ReportPeriodChoice.lastMonth ||
      ReportPeriodChoice.nextMonth => Icons.calendar_view_month_rounded,
      ReportPeriodChoice.thisYear => Icons.today_rounded,
      ReportPeriodChoice.last12Months ||
      ReportPeriodChoice.last90Days => Icons.history_rounded,
      ReportPeriodChoice.custom => Icons.date_range_rounded,
    };
  }

  static String _choiceId(ReportPeriodChoice c) {
    return switch (c) {
      ReportPeriodChoice.thisWeek => SemanticsIds.reportPeriodThisWeek,
      ReportPeriodChoice.lastWeek => SemanticsIds.reportPeriodLastWeek,
      ReportPeriodChoice.nextWeek => SemanticsIds.reportPeriodNextWeek,
      ReportPeriodChoice.thisMonth => SemanticsIds.reportPeriodThisMonth,
      ReportPeriodChoice.lastMonth => SemanticsIds.reportPeriodLastMonth,
      ReportPeriodChoice.nextMonth => SemanticsIds.reportPeriodNextMonth,
      ReportPeriodChoice.thisYear => SemanticsIds.reportPeriodThisYear,
      ReportPeriodChoice.last12Months => SemanticsIds.reportPeriodLast12Months,
      ReportPeriodChoice.last90Days => SemanticsIds.reportPeriodLast90Days,
      ReportPeriodChoice.custom => SemanticsIds.reportPeriodCustom,
    };
  }

  /// The band's title as the Period menu, centred under the title (the
  /// overview's D33). Custom range… asks the Dates sheet and changes
  /// nothing when it is cancelled.
  Future<void> _openPeriodMenu(BuildContext anchor) async {
    final bloc = context.read<CalendarReportBloc>();
    final state = bloc.state;
    if (state is! ReportShown) return;
    final l10n = AppLocalizations.of(context)!;
    _blur();
    final choice = await showFormMenu<ReportPeriodChoice>(
      anchor,
      items: [
        for (final choice in ReportPeriodChoice.values)
          FormMenuItem(
            value: choice,
            label: ReportBand.choiceLabel(l10n, choice),
            icon: _choiceIcon(choice),
            identifier: _choiceId(choice),
          ),
      ],
      selected: ReportPeriodChoice.checkedFor(
        state.period,
        today: state.today,
        weekStart: state.weekStart,
        years: state.years,
      ),
      menuWidth: FormMetrics.menuWidth,
      alignment: FormMenuAlignment.center,
    );
    if (choice == null || !mounted) return;
    final current = bloc.state;
    if (current is! ReportShown) return;
    if (choice == ReportPeriodChoice.custom) {
      final picked = await _pickRange(current);
      if (picked == null) return;
      bloc.add(ReportPeriodPicked(picked));
      return;
    }
    bloc.add(
      ReportPeriodPicked(
        choice.periodFor(
          today: current.today,
          weekStart: current.weekStart,
          years: current.years,
        ),
      ),
    );
  }

  /// The Dates sheet's range mode, seeded with the span shown; null when it
  /// is cancelled, already open, or the page has gone. The bloc clamps a
  /// span past 366 days (D33).
  Future<OverviewCustomPeriod?> _pickRange(ReportShown state) async {
    if (_pickerOpen || _sheetGuard.isOpen) return null;
    _pickerOpen = true;
    try {
      final picked = await CalendarDatePickerSheet.pickRange(
        context,
        initialRange: state.period.resolve(
          today: state.today,
          yearBounds: state.years,
        ),
        firstDate: DateTime.utc(state.years.first, 1, 1),
        lastDate: DateTime.utc(state.years.last, 12, 31),
        appearance: state.appearance,
      );
      if (picked == null || !mounted) return null;
      return OverviewCustomPeriod(picked.start, picked.end);
    } finally {
      _pickerOpen = false;
    }
  }

  /// The period and allowlist the report [state] draws was folded for: the
  /// pick itself once Ready, the one before it while a refold runs — so the
  /// caption and Show as list never pair the new pick with the old numbers
  /// (D36.9); null before the first report.
  static ({OverviewPeriod period, Set<String> categoryIds})? _foldedFor(
    ReportShown state,
  ) => switch (state) {
    ReportReady(:final period, :final categoryIds) => (
      period: period,
      categoryIds: categoryIds,
    ),
    ReportFolding(:final previousPeriod?, :final previousCategoryIds) => (
      period: previousPeriod,
      categoryIds: previousCategoryIds,
    ),
    ReportFolding() => null,
  };

  /// The bloc's [state], heard before it is drawn — every arm and release
  /// of the slack is set here or in a handler, never in a build (D40).
  ///
  /// A new report of the look on screen arms the slack only when it folds
  /// away a mark of this page — a marked row the last report listed as
  /// missed and this one does not: that shrink is under the finger. Any
  /// other refold of the same look — an event deleted or re-categorised on
  /// a sheet's trip, a category deleted in settings — may remove rows above
  /// the leading edge, and slack held for it would jump every visible row
  /// up and open blank ground below; the clamp's small slide on return from
  /// such a trip is the lesser harm. Keyed, not counted (D42): a pending
  /// mark whose write failed never arms another refold, and an unrelated
  /// Ready between the tap and the mark's refold never disarms it. A new
  /// look — a step, a pick — is another report: it never arms, and releases
  /// what the old one held, so its footer never sits above blank ground.
  void _heard(ReportState state) {
    final shown = state is ReportShown ? state : null;
    final folded = shown == null ? null : _foldedFor(shown);
    final report = folded == null ? null : shown?.shown;
    if (report == null || folded == null || identical(report, _heardReport)) {
      return;
    }
    final missed = {
      for (final group in report.missed)
        for (final row in group.rows.whereType<ReportDatedRow>())
          (row.eventId, row.day),
    };
    final landed = [
      for (final key in _marking)
        if (!missed.contains(key)) key,
    ];
    final heard = _heardLook;
    if (heard != null) {
      final sameLook =
          heard.period == folded.period &&
          setEquals(heard.categoryIds, folded.categoryIds);
      final slack = _slack.value;
      if (!sameLook) {
        _slack.value = (arms: slack.arms, releases: slack.releases + 1);
      } else if (landed.any(_heardMissed.contains)) {
        _slack.value = (arms: slack.arms + 1, releases: slack.releases);
      }
    }
    _marking.removeAll(landed);
    _heardReport = report;
    _heardLook = folded;
    _heardMissed = missed;
  }

  /// Arms the slack before a frame that may shrink the content under the
  /// finger: a header close, "Show less".
  void _armSlack() {
    final slack = _slack.value;
    _slack.value = (arms: slack.arms + 1, releases: slack.releases);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final labels = ReportLabels(l10n);
    final hasEvents = context.select<CalendarBloc, bool>(
      (bloc) => switch (bloc.state) {
        CalendarPageLoaded(:final allEvents) => allEvents.isNotEmpty,
        _ => false,
      },
    );
    return MultiBlocListener(
      listeners: [
        BlocListener<ImportExportBloc, ImportExportState>(
          listener: _export.onState,
        ),
        BlocListener<CalendarReportBloc, ReportState>(
          listener: (_, state) => _heard(state),
        ),
      ],
      child: BlocBuilder<CalendarReportBloc, ReportState>(
        builder: (context, state) {
          final shown = state is ReportShown ? state : null;
          return Scaffold(
            backgroundColor: colorScheme.pageGround,
            // The body pads itself by the larger of the keyboard and the
            // system inset, so it must see the keyboard's.
            resizeToAvoidBottomInset: false,
            appBar: _buildBar(l10n, colorScheme, shown, hasEvents),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBand(labels, state),
                Expanded(
                  child: _RefoldDim(
                    folding: state is ReportFolding && state.previous != null,
                    child: _buildBody(labels, state),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildBar(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    ReportShown? shown,
    bool hasEvents,
  ) {
    final ids = shown?.categoryIds ?? const <String>{};
    final narrowed = ids.isNotEmpty;
    return AppBar(
      titleSpacing: CalendarViewMenu.titleSpacing,
      excludeHeaderSemantics: true,
      title: CalendarViewMenu(
        page: CalendarViewPage.report,
        onPageSelected: _switchPage,
      ),
      toolbarHeight: AppBarMetrics.toolbarHeight,
      iconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      actionsIconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [
        AutomationId(
          identifier: SemanticsIds.reportCategoriesOpen,
          child: IconButton(
            tooltip: l10n.calendarCategories,
            isSelected: narrowed,
            iconSize: AppBarMetrics.glyphSize,
            // The count rides the glyph and stays out of the button's node
            // (the ui-language badge rule): the tooltip stays what is read.
            icon: ExcludeSemantics(
              child: Badge.count(
                count: ids.length,
                isLabelVisible: narrowed,
                child: Icon(
                  narrowed
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                ),
              ),
            ),
            onPressed: shown == null ? null : _pickCategories,
          ),
        ),
        CalendarOverflowMenu(
          identifier: SemanticsIds.reportMore,
          onAlerts: () => AppNavigator.toAlertsFromCalendar(context),
          onCategories: () => AppNavigator.toCalendarCategories(context),
          onExport: hasEvents ? _exportEvents : null,
          onGuide: () => AppNavigator.toCalendarGuide(context),
          onSettings: _openSettings,
        ),
      ],
    );
  }

  Widget _buildBand(ReportLabels labels, ReportState state) {
    final shown = state is ReportShown ? state : null;
    final period = switch (state) {
      ReportShown(:final period) => period,
      ReportLoading(:final period) => period,
    };
    final bloc = context.read<CalendarReportBloc>();
    return ReportBand(
      period: period,
      home: shown?.home,
      report: shown?.shown,
      folding: state is ReportFolding,
      today: shown?.today ?? EventAgenda.dateOnly(widget.clock()),
      years: shown?.years,
      labels: labels,
      onTitleTap: shown == null ? null : _openPeriodMenu,
      onStep: shown == null
          ? null
          : (direction) => bloc.add(ReportStepped(direction)),
      onHome: shown == null ? null : () => bloc.add(const ReportHomePressed()),
    );
  }

  Widget _buildBody(ReportLabels labels, ReportState state) {
    final shown = state is ReportShown ? state : null;
    final folded = shown == null ? null : _foldedFor(shown);
    final report = folded == null ? null : shown?.shown;
    final today = shown?.today ?? EventAgenda.dateOnly(widget.clock());
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    return ReportBody(
      report: report,
      period: folded?.period,
      categoryIds: folded?.categoryIds ?? const {},
      // Today, the years and the week start are read only beside a report,
      // which comes with a shown state: the fallbacks are never drawn.
      today: today,
      years: shown?.years ?? (first: today.year, last: today.year),
      weekStart: shown?.weekStart ?? const CalendarAppearance().weekStart,
      labels: labels,
      folds: _folds,
      scroll: _scroll,
      slack: _slack,
      bottomClearance: _bottomClearance,
      use24Hour: use24Hour,
      onDatedTap: _openDated,
      onRoutineTap: _openRoutine,
      onPresence: _markPresence,
      onShowAsList: AppNavigator.toCalendarOverviewLook,
      onMoreCategories: shown == null
          ? null
          : (report, {required largest, required spansMonths}) =>
                _openMoreCategories(
                  labels,
                  report,
                  shown,
                  largest: largest,
                  spansMonths: spansMonths,
                  use24Hour: use24Hour,
                ),
      onShare: (report, {required periodName, required against}) =>
          _shareReport(
            report,
            labels,
            periodName: periodName,
            against: against,
          ),
      onSend: (period, categoryIds) =>
          unawaited(_sendReport(period, categoryIds)),
      onShrink: _armSlack,
    );
  }

  /// The rest of the Categories card in a sheet over the page, through the
  /// page's one [SheetGuard] slot: a row picked there opens its detail sheet
  /// here, in place, on the pop's future — while the sheet is still
  /// animating out, as the upcoming agenda opens its own; a group's Show as
  /// list hands the overview the folded span and that one category, as on
  /// the page. The meters read against the card's largest group, which
  /// leads the card, so a bar in the sheet compares with one on the page,
  /// and the folds are the page's, so a group closed there stays closed for
  /// the visit (X).
  Future<void> _openMoreCategories(
    ReportLabels labels,
    CalendarReport report,
    ReportShown shown, {
    required int largest,
    required bool spansMonths,
    required bool use24Hour,
  }) async {
    _blur();
    final result = await _sheetGuard.run<ReportSheetResult?>(
      () => ReportMoreCategoriesSheet.show(
        context,
        groups: report.categories.skip(ReportMetrics.maxCategoryRows).toList(),
        events: report.events,
        labels: labels,
        today: shown.today,
        spansMonths: spansMonths,
        use24Hour: use24Hour,
        largest: largest,
        folds: _folds,
      ),
    );
    if (!mounted) return;
    switch (result) {
      case ReportSheetPick(:final eventId, :final day):
        _openOn(eventId, day);
      case ReportSheetShowList(:final categoryId):
        unawaited(
          AppNavigator.toCalendarOverviewLook(
            start: report.span.start,
            end: report.span.end,
            categoryIds: {categoryId},
          ),
        );
      case null:
        break;
    }
  }

  /// A dated row's tap: the occurrence's detail sheet, in place.
  void _openDated(ReportDatedRow row) => _openOn(row.eventId, row.day);

  /// A routine aggregate's tap: the detail sheet on the latest day it
  /// counts, the most recent of what the row sums.
  void _openRoutine(ReportRoutineRow row) =>
      _openOn(row.eventId, row.latestDay);

  /// The detail sheet over the report through [_sheets] (§5): no calendar is
  /// pushed, so back closes the sheet onto the row it came from. The event
  /// is read from the calendar's loaded events at the tap, not from the
  /// report drawn — the report may still be the one folded before a delete,
  /// and a row whose event has gone opens nothing (the overview's rule).
  /// Nothing is parked while the trip runs: the bloc folds the calendar's
  /// newest state and coalesces a burst, and a refold under the sheet only
  /// dims the body beneath it (D36).
  void _openOn(String eventId, DateTime day) {
    _blur();
    final calendar = context.read<CalendarBloc>().state;
    if (calendar is! CalendarPageLoaded) return;
    for (final event in calendar.allEvents) {
      if (event.id != eventId) continue;
      unawaited(_sheets.openDetail(context, event, day));
      return;
    }
  }

  /// The overview's click, behind the haptics setting.
  void _click() {
    final state = context.read<CalendarReportBloc>().state;
    if (state is ReportShown && state.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
  }

  /// A Missed row's mark, written as every surface writes one; the report
  /// refolds from the calendar's next state, and the body keeps its offset.
  /// A row already marked waits for that refold: a second tap is dropped.
  void _markPresence(ReportDatedRow row, bool missed) {
    if (!_marking.add((row.eventId, row.day))) return;
    _click();
    EventSheetsFlow.setOccurrencePresence(
      context.read<CalendarBloc>(),
      row.eventId,
      row.day,
      missed,
    );
  }

  /// Share report (K): [report] as Markdown through the import/export bloc
  /// — the share sheet and the temp file are the service's — answered by
  /// this page's export snackbars. A second tap while an export is pending
  /// does nothing (D46).
  void _shareReport(
    CalendarReport report,
    ReportLabels labels, {
    required String periodName,
    required String? against,
  }) {
    if (_export.isPending) return;
    _blur();
    _export.startText(
      context,
      fileName: ReportMarkdown.fileName(report.span),
      text: ReportMarkdown.render(
        report,
        labels,
        use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
        periodName: periodName,
        against: against,
      ),
      format: ExportFormat.markdown,
    );
  }

  /// Send me this report (J): the digest editor pre-filled as the report
  /// digest of this page — a week period's weekly report fired on the week's
  /// first day, any other period's monthly report on the 1st, over the
  /// report's categories — and saved as the Alerts hub saves one, at the
  /// alerts' default time. A picker already up wins the frame: one frame's
  /// two fingers never stack it and the sheet.
  Future<void> _sendReport(
    OverviewPeriod period,
    Set<String> categoryIds,
  ) async {
    if (_pickerOpen) return;
    final state = context.read<CalendarReportBloc>().state;
    if (state is! ReportShown) return;
    final calendar = context.read<CalendarBloc>();
    final events = switch (calendar.state) {
      CalendarPageLoaded(:final allEvents) => allEvents,
      _ => const <CalendarEvent>[],
    };
    final weekly = period is OverviewWeekPeriod;
    _blur();
    final result = await _sheetGuard.run<DigestEditorResult?>(
      () => DigestEditorSheet.show(
        context,
        initial: EventDigest(
          id: '',
          cadence: weekly
              ? DigestCadence.weeklyReport
              : DigestCadence.monthlyReport,
          anchor: weekly ? state.weekStart.weekday : 1,
          minute: kDefaultAlertDayMinute,
          categoryIds: categoryIds,
        ),
        events: events,
        weekStart: state.weekStart,
      ),
    );
    if (!mounted) return;
    if (result case DigestEditorSaved(:final digest)) {
      calendar.add(SaveEventDigest(digest));
      // A digest is a notification: the first one may need the permission
      // to post, which only a save can ask for in context.
      if (digest.enabled) unawaited(AlertPermissionCheck.afterSave(context));
    }
  }
}

/// The refold (§4.2, R): while a fold runs over a report already shown,
/// the body keeps it and dims after [ReportMetrics.refoldDimDelay] — a
/// quick fold lands before that and never flickers — absorbing taps while
/// dim, and un-dims at once. The bar and the band are not inside it.
class _RefoldDim extends StatefulWidget {
  const _RefoldDim({required this.folding, required this.child});

  final bool folding;
  final Widget child;

  @override
  State<_RefoldDim> createState() => _RefoldDimState();
}

class _RefoldDimState extends State<_RefoldDim> {
  Timer? _timer;
  bool _dim = false;

  @override
  void initState() {
    super.initState();
    if (widget.folding) _arm();
  }

  @override
  void didUpdateWidget(_RefoldDim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.folding && !oldWidget.folding) {
      _arm();
    } else if (!widget.folding) {
      _timer?.cancel();
      _timer = null;
      _dim = false;
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(ReportMetrics.refoldDimDelay, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _dim,
      child: Opacity(
        opacity: _dim ? ReportMetrics.refoldOpacity : 1,
        child: widget.child,
      ),
    );
  }
}
