import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_bar_metrics.dart';
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
import 'calendar_header_menus.dart';

/// The screen page's one demo calendar, which its three cards share (D58):
/// the day the grid picks is the day the panel shows and the overview's
/// month marks. Owned by the page's `State` with the cards' demos, which
/// listen to it, so a pick on one card redraws the other two.
///
/// Nothing here is saved, and nothing on these cards edits: the grid, the
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
  /// cached, so the three stages stand from the first frame; [adopt]
  /// rebuilds it over the owner's categories once `CategoryService` has
  /// answered, since the cache is still empty when the app relaunches onto
  /// the guide. A new language rebuilds the seed in it, keeping her picks:
  /// the cards hold nothing she made, only what she was looking at.
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

  /// One card changed what the others show — the picked day.
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
    // No funnel on these cards: the layers are the unfiltered grid's.
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

/// The screen page's first card: the calendar's bar — its title menu and its
/// ⋮ — over the month grid, the real widgets each. The title menu's formats
/// reshape the grid; a day tap picks the day the other two cards show. No
/// add button, no sheet, no long press: nothing here edits (D57).
class GuideScreenDemo extends GuideCardDemo {
  GuideScreenDemo(this.world)
    : super(CalendarGuideTopic.screen.card(GuideCardSpec.screenGrid)) {
    world.addListener(notifyListeners);
  }

  static const String slug = GuideCardSpec.screenGrid;

  final GuideScreenWorld world;

  @override
  bool get stageFullBleed => true;

  @override
  void dispose() {
    world.removeListener(notifyListeners);
    super.dispose();
  }

  static String _wouldOpenOverview(AppLocalizations l10n) =>
      l10n.calendarGuideWouldOpen(l10n.calendarOverview);

  @override
  List<String> reports(AppLocalizations l10n) => [_wouldOpenOverview(l10n)];

  void _setFormat(CalendarFormat format) {
    world.calendar!.format = format;
    did('title');
  }

  /// The title menu's other page: she used the menu, and the overview card
  /// further down is where it would lead.
  void _openOverview() {
    did('title');
    say(_wouldOpenOverview);
  }

  /// Any row of the ⋮: none opens anything here.
  void _more() => did('more');

  /// The pick reaches every card through [world]; its notification is this
  /// card's redraw too.
  void _pickDay(DateTime day, DateTime focused) {
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

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final calendar = world.calendar!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuideCalendarBar(
          // A bar inside a stage: no status bar above it, nothing to go
          // back to.
          primary: false,
          automaticallyImplyLeading: false,
          format: calendar.format,
          onFormatSelected: _setFormat,
          onPageSelected: (_) => _openOverview(),
          // The calendar's saved filters and funnel, disabled, never
          // hidden: the card shows where they live; the filtering lesson
          // is where they work.
          savedFiltersSlot: AutomationId(
            identifier: SemanticsIds.calendarGuideTryControl(
              slug,
              'saved-filters',
            ),
            child: IconButton(
              tooltip: l10n.filterPresetsTitle,
              iconSize: AppBarMetrics.glyphSize,
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: null,
            ),
          ),
          filterSlot: GuideCalendarBar.filterButton(
            identifier: SemanticsIds.calendarGuideTryControl(slug, 'filter'),
            tooltip: l10n.filterCalendar,
            activeCount: 0,
            onPressed: null,
          ),
          moreSlot: CalendarOverflowMenu(
            identifier: SemanticsIds.calendarGuideTryControl(slug, 'more'),
            onAlerts: _more,
            onExport: _more,
            onGuide: _more,
            onSettings: _more,
          ),
        ),
        GuideCalendarGrid(
          demo: calendar,
          appearance: world.appearance,
          barsResolver: world.barsResolver(l10n),
          monthTitle: world.monthTitle,
          onDaySelected: _pickDay,
          onPageChanged: _turnPage,
          holdsMonthHeight: true,
        ),
      ],
    );
  }
}

/// The screen page's second card: the panel under the grid — the mode bar
/// over the picked day's Day, Timeline or Upcoming body — in a slot of one
/// height that each body scrolls inside. Its rows open nothing and its
/// presence button is not drawn (D57); the mode bar is the lesson.
class GuidePanelDemo extends GuideCardDemo {
  GuidePanelDemo(this.world)
    : super(CalendarGuideTopic.screen.card(GuideCardSpec.screenPanel)) {
    world.addListener(notifyListeners);
  }

  final GuideScreenWorld world;

  @override
  bool get stageFullBleed => true;

  @override
  void dispose() {
    world.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final calendar = world.calendar!;
    return GuideStageSlot(
      height: MediaQuery.textScalerOf(context)
          .clamp(maxScaleFactor: GuideMetrics.panelStageMaxTextScale)
          .scale(GuideMetrics.panelStageHeight),
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
    );
  }
}
