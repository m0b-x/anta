import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_category.dart';
import '../models/calendar_grid_filters.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../services/day_bars_resolver.dart';
import '../services/day_summary_resolver.dart';
import '../utils/guide_locale_format.dart';
import '../utils/markdown_color_syntax.dart';
import 'automation_id.dart';
import 'calendar_guide_bar.dart';
import 'calendar_guide_demo_panel.dart';
import 'calendar_guide_grid.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'calendar_guide_try_overview.dart';
import 'calendar_header_menus.dart';

/// The screen page's one demo calendar, which the stage's views share: the
/// day the grid picks is the day the panel shows and the overview's month
/// marks. Owned by the page's `State` with the stage's demo, which listens
/// to it, so a pick in one view redraws the stage.
///
/// Nothing here is saved, and nothing on the stage edits: the grid, the
/// panel and the overview only show the demo's events (D57).
class GuideScreenWorld extends ChangeNotifier {
  GuideScreenWorld({DateTime Function() now = DateTime.now}) : _now = now;

  final DateTime Function() _now;

  GuideDemoCalendar? _calendar;
  AppLocalizations? _l10n;

  /// The bars and the Day panel's entries depend only on the language, the
  /// look and the demo whose marks they read; kept until one changes.
  DayBarsResolver? _barsResolver;
  DaySummaryResolver? _summaryResolver;
  Object? _resolverKey;

  /// The grid's month title, `table_calendar`'s own format.
  final GuideLocaleFormat monthTitle = GuideLocaleFormat(DateFormat.yMMMM);

  /// Null until the page has a language: the seed's titles are written in
  /// it. The page builds it before its first frame ([ensureCalendar]).
  GuideDemoCalendar? get calendar => _calendar;

  /// The language [calendar] was written in, for what is built from it.
  AppLocalizations? get l10n => _l10n;

  /// The owner's calendar look; the defaults until the page has read it.
  CalendarAppearance get appearance => _appearance;
  CalendarAppearance _appearance = const CalendarAppearance();

  MarkdownColorPalette get palette => _palette;
  MarkdownColorPalette _palette = MarkdownColorPalette.presets;

  /// The visible categories the demo's seed was last built over.
  List<CalendarCategory> _categories = const [];

  /// Builds the demo in [l10n]'s language over the categories the app has
  /// cached, so the stage stands from the first frame; [adopt]
  /// rebuilds it over the owner's categories once `CategoryService` has
  /// answered, since the cache is still empty when the app relaunches onto
  /// the guide. A new language rebuilds the seed in it, keeping her picks:
  /// the stage holds nothing she made, only what she was looking at.
  void ensureCalendar(AppLocalizations l10n) {
    final previous = _calendar;
    if (previous != null && l10n.localeName == _l10n?.localeName) return;
    _l10n = l10n;
    if (previous == null) {
      _categories = _visible(CalendarCategories.visible);
      _calendar = GuideDemoCalendar(
        l10n: l10n,
        today: _now(),
        categories: _categories,
      );
    } else {
      _rebuild(previous);
    }
    notifyListeners();
  }

  /// What the page loaded: her look, her palette and her categories. A new
  /// set of visible categories rebuilds the seed in her colours and keeps
  /// what she was looking at — the picked day, the page, the format, the
  /// panel mode; the same set rebuilds nothing.
  void adopt({
    CalendarAppearance? appearance,
    MarkdownColorPalette? palette,
    List<CalendarCategory>? categories,
  }) {
    if (appearance != null) _appearance = appearance;
    if (palette != null) _palette = palette;
    final previous = _calendar;
    if (categories != null && previous != null) {
      final visible = _visible(categories);
      if (!listEquals(visible, _categories)) {
        _categories = visible;
        _rebuild(previous);
      }
    }
    notifyListeners();
  }

  static List<CalendarCategory> _visible(List<CalendarCategory> categories) =>
      List.unmodifiable([
        for (final category in categories)
          if (!category.isHidden) category,
      ]);

  void _rebuild(GuideDemoCalendar previous) {
    _calendar =
        GuideDemoCalendar(
            l10n: _l10n!,
            today: previous.today,
            categories: _categories,
          )
          ..selectedDay = previous.selectedDay
          ..format = previous.format
          ..panelMode = previous.panelMode
          ..focus(previous.focusedDay);
  }

  /// One view changed what the others show — the picked day.
  void touch() => notifyListeners();

  DayBarsResolver barsResolver(AppLocalizations l10n) {
    _resolversFor(l10n);
    return _barsResolver!;
  }

  DaySummaryResolver summaryResolver(AppLocalizations l10n) {
    _resolversFor(l10n);
    return _summaryResolver!;
  }

  void _resolversFor(AppLocalizations l10n) {
    final calendar = _calendar!;
    final key = (
      l10n,
      _appearance.missedDisplay,
      _appearance.showRecurrenceLabels,
      calendar,
    );
    if (key == _resolverKey) return;
    _resolverKey = key;
    // No funnel on the stage: the layers are the unfiltered grid's.
    const filters = CalendarGridFilters.none;
    _barsResolver = DayBarsResolver.defaults(
      l10n,
      missedDisplay: _appearance.missedDisplay,
      showHolidays: filters.showHolidays,
      showFasting: filters.showFasting,
      showMoney: filters.showMoney,
      isMissed: calendar.isMissed,
    );
    _summaryResolver = DaySummaryResolver.defaults(
      l10n,
      showRecurrence: _appearance.showRecurrenceLabels,
      showHolidays: filters.showHolidays,
      showFasting: filters.showFasting,
      showMoney: filters.showMoney,
    );
  }
}

/// The screen page's one stage (D73), shaped like the screen: a view's own
/// bar — the title menu live and switching the body, as in the app — over
/// the Calendar (the grid in its formats over the panel), the Overview
/// ([GuideOverviewView]) or, once it is built, the Report, all at one
/// height ([GuideMetrics.screenStageHeight]). The real widgets each; no add
/// button, no sheet, no long press: nothing here edits (D57).
///
/// What she did stays for the page's life (D83): the picked day, the month,
/// the format and the panel mode in [world], the Overview's mode and period
/// in its view. The stage opens on the Calendar every time the page opens
/// (D84).
class GuideScreenDemo extends GuideCardDemo {
  GuideScreenDemo(this.world) : super(CalendarGuideTopic.screen.cards.single) {
    _overview = GuideOverviewView(
      world,
      onStep: did,
      onPick: (day) => _pick(day, day),
    )..addListener(changed);
    world.addListener(_onWorld);
  }

  static final String slug = CalendarGuideTopic.screen.slug;

  final GuideScreenWorld world;

  late final GuideOverviewView _overview;

  /// The view the stage shows, as the title names it.
  CalendarViewPage _view = CalendarViewPage.calendar;

  @override
  bool get stageFullBleed => true;

  @override
  bool get stageFlush => true;

  @override
  void dispose() {
    world.removeListener(_onWorld);
    _overview.dispose();
    super.dispose();
  }

  void _onWorld() {
    _overview.syncWorld();
    notifyListeners();
  }

  static String _wouldOpenReport(AppLocalizations l10n) =>
      l10n.calendarGuideWouldOpen(l10n.reportTitle);

  @override
  List<String> reports(AppLocalizations l10n) => [_wouldOpenReport(l10n)];

  void _setFormat(CalendarFormat format) {
    world.calendar!.format = format;
    changed();
  }

  /// The title menu switches the body in one frame, as the app's does; the
  /// menu never hands back the view shown. The Report says where it would
  /// lead until its view is built, and the stage stays where it is.
  void _openPage(CalendarViewPage page) {
    if (page == CalendarViewPage.report) {
      say(_wouldOpenReport);
      return;
    }
    if (_view == CalendarViewPage.overview) _overview.leave();
    _view = page;
    if (page == CalendarViewPage.overview) {
      _overview.enter();
      did('overview');
    } else {
      changed();
    }
  }

  /// Any row of the ⋮: none opens anything here.
  void _more() => did('more');

  /// The pick reaches every view through [world]; its notification is this
  /// stage's redraw too.
  void _pick(DateTime day, DateTime focused) {
    final calendar = world.calendar!;
    calendar.selectedDay = day;
    calendar.focus(focused);
    dropReport();
    world.touch();
  }

  void _turnPage(DateTime focused) {
    world.calendar!.focus(focused);
    changed();
  }

  String _control(String name) =>
      SemanticsIds.calendarGuideTryControl(slug, name);

  /// The stage's height (D77): only the panel's share grows with the text,
  /// and only to [GuideMetrics.screenStageMaxTextScale].
  static double heightFor(TextScaler scaler) =>
      GuideMetrics.screenStageHeight -
      GuideMetrics.screenStagePanelShare +
      scaler
          .clamp(maxScaleFactor: GuideMetrics.screenStageMaxTextScale)
          .scale(GuideMetrics.screenStagePanelShare);

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final view = _view;
    return GuideStageSlot(
      height: heightFor(MediaQuery.textScalerOf(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(l10n, colorScheme, view),
          Expanded(
            child: Semantics(
              container: true,
              identifier: SemanticsIds.calendarGuideScreenView(view.name),
              child: switch (view) {
                CalendarViewPage.overview => _overview.build(context),
                CalendarViewPage.calendar ||
                CalendarViewPage.report => _calendarBody(l10n, colorScheme),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Each view's own bar (D81): the Calendar's on `surface` with its
  /// formats, the Overview's on the page's ground without them. Their
  /// buttons other than the ⋮ are drawn disabled, never hidden: the stage
  /// shows where they live; the lessons are where they work.
  Widget _bar(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    CalendarViewPage view,
  ) {
    final more = CalendarOverflowMenu(
      identifier: _control('more'),
      onAlerts: _more,
      onCategories: _more,
      onExport: _more,
      onGuide: _more,
      onSettings: _more,
    );
    final calendar = view == CalendarViewPage.calendar;
    return GuideCalendarBar(
      // A bar inside a stage: no status bar above it, nothing to go back to.
      primary: false,
      automaticallyImplyLeading: false,
      page: view,
      format: calendar ? world.calendar!.format : null,
      onFormatSelected: calendar ? _setFormat : null,
      onPageSelected: _openPage,
      backgroundColor: calendar ? colorScheme.surface : colorScheme.pageGround,
      actions: calendar
          ? [
              _disabledAction(
                identifier: _control('saved-filters'),
                tooltip: l10n.filterPresetsTitle,
                icon: Icons.bookmarks_outlined,
              ),
              GuideCalendarBar.filterButton(
                identifier: _control('filter'),
                tooltip: l10n.filterCalendar,
                activeCount: 0,
                onPressed: null,
              ),
              more,
            ]
          : [
              _disabledAction(
                identifier: _control('overview-options'),
                tooltip: l10n.overviewListOptions,
                icon: Icons.tune_rounded,
              ),
              _disabledAction(
                identifier: _control('overview-views'),
                tooltip: l10n.overviewViewsTitle,
                icon: Icons.bookmarks_outlined,
              ),
              more,
            ],
    );
  }

  static Widget _disabledAction({
    required String identifier,
    required String tooltip,
    required IconData icon,
  }) {
    return AutomationId(
      identifier: identifier,
      child: IconButton(
        tooltip: tooltip,
        iconSize: AppBarMetrics.glyphSize,
        icon: Icon(icon),
        onPressed: null,
      ),
    );
  }

  /// The grid on the calendar's `surface`, pinned at its own height, and
  /// the panel taking the rest (D78): a week or two weeks give the panel
  /// more, as on the real page. The panel's rows open nothing and its
  /// presence button is not drawn (D57); its mode bar is the lesson.
  Widget _calendarBody(AppLocalizations l10n, ColorScheme colorScheme) {
    final calendar = world.calendar!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colorScheme.surface,
          child: GuideCalendarGrid(
            demo: calendar,
            appearance: world.appearance,
            barsResolver: world.barsResolver(l10n),
            monthTitle: world.monthTitle,
            onDaySelected: _pick,
            onPageChanged: _turnPage,
          ),
        ),
        Expanded(
          child: GuideDemoPanel(
            demo: calendar,
            appearance: world.appearance,
            palette: world.palette,
            summaryResolver: world.summaryResolver(l10n),
            onModeChanged: (mode) {
              calendar.panelMode = mode;
              did('panel');
            },
          ),
        ),
      ],
    );
  }
}
