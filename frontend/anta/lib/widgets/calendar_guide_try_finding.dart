import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_grid_filters.dart';
import '../models/calendar_guide_demo.dart';
import '../services/day_summary_resolver.dart';
import '../utils/calendar_week_start.dart';
import '../utils/event_query_matcher.dart';
import '../utils/event_search_query.dart';
import 'calendar_filter_sheet.dart';
import 'calendar_guide_try_card.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'month_dot_matrix.dart';

/// The finding page's card: the practice calendar's six events under the
/// overview's search row, read by the real search grammar and matcher, with
/// the calendar's filter sheet in its sandbox mode and this month's dots
/// showing the days that still match. A word, a category's name and a date
/// all narrow the same list.
class GuideFindingDemo extends GuideCardDemo {
  GuideFindingDemo({DateTime Function() now = DateTime.now})
    : _today = _todayUtc(now());

  static const String slug = 'finding';

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Date-only UTC, read once.
  final DateTime _today;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// The six events and the demo's marks, for Missed only. Null until the
  /// first build, which names them in her language.
  GuideDemoCalendar? _calendar;
  CalendarGridFilters _filters = CalendarGridFilters.none;
  EventQueryMatcher? _matcher;

  /// Each event's days from the first of this month to a year after today,
  /// worked out once: the events never change here, only the query and the
  /// filters, so a keystroke re-reads the days and never expands a rule.
  /// A year, so the yearly birthday is among the matches too.
  final Map<String, List<DateTime>> _days = {};

  @override
  bool get needsAppearance => true;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  DateTime get _monthStart => DateTime.utc(_today.year, _today.month);
  DateTime get _monthEnd => DateTime.utc(_today.year, _today.month + 1, 0);

  /// Every event matches before she types.
  @override
  String idle(AppLocalizations l10n) =>
      l10n.calendarGuideDemoMatches(_calendarFor(l10n).events.length);

  @override
  List<String> candidates(AppLocalizations l10n) => [
    for (var count = 0; count <= _calendarFor(l10n).events.length; count++)
      l10n.calendarGuideDemoMatches(count),
    // The most filters the caption can name.
    for (var count = 0; count <= CalendarGridFilters.axisCount; count++)
      l10n.calendarGuideDemoFiltered(count),
  ];

  GuideDemoCalendar _calendarFor(AppLocalizations l10n) =>
      _calendar ??= GuideDemoCalendar(
        l10n: l10n,
        today: _today,
        categories: CalendarCategories.visible,
      );

  List<DateTime> _daysOf(GuideDemoCalendar calendar, CalendarEvent event) =>
      _days[event.id] ??= [
        for (
          var day = _monthStart;
          !day.isAfter(DateTime.utc(_today.year + 1, _today.month, _today.day));
          day = DateTime.utc(day.year, day.month, day.day + 1)
        )
          if (calendar.occursOn(event, day)) day,
      ];

  /// Whether [event] still shows on [day]: the query, then Missed only over
  /// the demo's own marks — `allowsOccurrence` asks `EventPresence`, which
  /// holds none of them.
  bool _shows(
    GuideDemoCalendar calendar,
    EventQueryMatcher matcher,
    CalendarEvent event,
    DateTime day,
  ) =>
      matcher.matches(event, day) &&
      (!_filters.missedOnly || calendar.isMissed(event, day));

  EventQueryMatcher _matcherFor(AppLocalizations l10n) {
    final calendar = _calendarFor(l10n);
    return _matcher ??= EventQueryMatcher(
      query: EventSearchQuery.parse(_search.text, localeName: l10n.localeName),
      categoryLabels: {
        for (final event in calendar.events)
          event.categoryId: CalendarCategories.labelOf(
            CalendarCategories.resolve(event.categoryId),
            l10n,
          ),
      },
      labelTextOf: (event) => event.title,
    );
  }

  /// The list and the month's days for the query and the filters now,
  /// worked out once per change of either: a keystroke reads them in the
  /// caption and again in the stage.
  ({List<CalendarEvent> events, int monthMask}) _shown(AppLocalizations l10n) {
    final key = (_search.text, _filters, l10n.localeName);
    if (key != _shownKey) {
      _shownKey = key;
      _matcher = null;
      final events = _matches(l10n);
      _shownCache = (events: events, monthMask: _monthMask(l10n, events));
    }
    return _shownCache;
  }

  (String, CalendarGridFilters, String)? _shownKey;
  ({List<CalendarEvent> events, int monthMask}) _shownCache = (
    events: const [],
    monthMask: 0,
  );

  /// The events with a day that still shows, in the seed's order.
  List<CalendarEvent> _matches(AppLocalizations l10n) {
    final calendar = _calendarFor(l10n);
    final matcher = _matcherFor(l10n);
    return [
      for (final event in _filters.apply(calendar.events, todayUtc: _today))
        if (matcher.mayMatch(event) &&
            _daysOf(
              calendar,
              event,
            ).any((day) => _shows(calendar, matcher, event, day)))
          event,
    ];
  }

  void _onQuery(AppLocalizations l10n) {
    final count = _shown(l10n).events.length;
    say((l10n) => l10n.calendarGuideDemoMatches(count));
  }

  Future<void> _openFilters(BuildContext context) async {
    _searchFocus.unfocus();
    final picked = await CalendarFilterSheet.show(
      context,
      filters: _filters,
      sandbox: true,
    );
    if (picked == null) return;
    _filters = picked;
    final active = picked.activeCount;
    say((l10n) => l10n.calendarGuideDemoFiltered(active));
  }

  Widget _row(BuildContext context, CalendarEvent event) {
    final category = CalendarCategories.resolve(event.categoryId);
    return FormPickerRow(
      leading: EventAvatar(
        icon: CalendarCategories.iconFor(event),
        color: EventSummaryProvider.colorFor(event, category),
      ),
      label: event.title,
      onTap: null,
      showChevron: false,
      identifier: SemanticsIds.calendarGuideTryControl(
        slug,
        'match-${event.id.replaceFirst(GuideDemoCalendar.idPrefix, '')}',
      ),
    );
  }

  Widget _rows(BuildContext context, List<CalendarEvent> events) {
    if (events.isEmpty) return const SizedBox.shrink();
    return FormRowGroup(
      trailingGap: false,
      children: [for (final event in events) _row(context, event)],
    );
  }

  /// This month's days as the dot matrix's bits: day 1 is bit 0.
  int _monthMask(AppLocalizations l10n, List<CalendarEvent> matches) {
    final calendar = _calendarFor(l10n);
    final matcher = _matcherFor(l10n);
    var mask = 0;
    for (final event in matches) {
      for (final day in _daysOf(calendar, event)) {
        if (day.month != _today.month || day.year != _today.year) break;
        if (_shows(calendar, matcher, event, day)) mask |= 1 << (day.day - 1);
      }
    }
    return mask;
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final calendar = _calendarFor(l10n);
    final shown = _shown(l10n);
    final matches = shown.events;
    final active = _filters.activeCount;
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRowGroup(
          children: [
            FormSearchRow(
              controller: _search,
              focusNode: _searchFocus,
              // Not the overview's "Search events": inside the stage, at 2.0,
              // its German and Romanian hints are cut off; one word fits.
              hint: l10n.search,
              clearTooltip: l10n.upcomingClearSearch,
              identifier: control('search'),
              onChanged: (_) => _onQuery(l10n),
            ),
          ],
        ),
        Stack(
          children: [
            // The list's height: all six rows laid out unseen, so a query
            // never moves the funnel, the month or the page under her.
            ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: _rows(context, calendar.events),
                  ),
                ),
              ),
            ),
            _rows(context, matches),
          ],
        ),
        const SizedBox(height: RowMetrics.groupGap),
        FormRowGroup(
          children: [
            FormActionRow(
              glyph: active > 0
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
              label: l10n.filterCalendar,
              identifier: control('filter'),
              onTap: () => _openFilters(context),
            ),
          ],
        ),
        // The kinds card's month, drawn as the year tiles draw it; what it
        // shows, the caption and the list above say.
        ExcludeSemantics(
          child: Center(
            child: SizedBox(
              width: MonthDotMatrix.width * GuideMetrics.stageMatrixScale,
              height: MonthDotMatrix.height * GuideMetrics.stageMatrixScale,
              child: FittedBox(
                child: MonthDotMatrix(
                  daysInMonth: _monthEnd.day,
                  firstWeekdayColumn: weekdayColumnOf(
                    _monthStart,
                    appearance.weekStart,
                  ),
                  markedMask: shown.monthMask,
                  missedMask: 0,
                  windowMask: (1 << _monthEnd.day) - 1,
                  todayIndex: _today.day - 1,
                  markedColor: colorScheme.primary,
                  missedColor: colorScheme.primary,
                  unmarkedColor: colorScheme.outline.withValues(
                    alpha: MonthDotMatrix.unmarkedAlpha,
                  ),
                  outsideColor: colorScheme.outline.withValues(
                    alpha: MonthDotMatrix.outsideAlpha,
                  ),
                  todayColor: appearance.accentOr(colorScheme.primary),
                  backgroundColor: colorScheme.pageGround,
                  outlineColor: colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
