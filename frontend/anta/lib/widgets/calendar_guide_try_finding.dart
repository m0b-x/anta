import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_grid_filters.dart';
import '../models/calendar_guide_content.dart';
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
    : _today = _todayUtc(now()),
      super(CalendarGuideTopic.finding.cards.single);

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
  /// worked out once per change of either: the stage is drawn again on
  /// every change of the card, and most change neither.
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

  void _onQuery() {
    // An emptied field is no search: the list fills again, and the step
    // stays done.
    if (_search.text.trim().isEmpty) {
      changed();
    } else {
      did('query');
    }
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
    if (picked.activeCount > 0) {
      did('filtered');
    } else {
      changed();
    }
  }

  /// The live list's first row, which the keyboard reveal keeps in view.
  final GlobalKey _firstMatchKey = GlobalKey();

  Widget _row(BuildContext context, CalendarEvent event, {Key? key}) {
    final category = CalendarCategories.resolve(event.categoryId);
    return FormPickerRow(
      key: key,
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

  Widget _rows(
    BuildContext context,
    List<CalendarEvent> events, {
    Key? firstKey,
  }) {
    if (events.isEmpty) return const SizedBox.shrink();
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final (i, event) in events.indexed)
          _row(context, event, key: i == 0 ? firstKey : null),
      ],
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
        _CaptionAboveKeyboard(
          focusNode: _searchFocus,
          caption: captionSlotKey,
          firstMatch: _firstMatchKey,
          child: FormRowGroup(
            children: [
              FormSearchRow(
                controller: _search,
                focusNode: _searchFocus,
                // Not the overview's "Search events": inside the stage, at
                // 2.0, its German and Romanian hints are cut off; one word
                // fits.
                hint: l10n.search,
                clearTooltip: l10n.upcomingClearSearch,
                identifier: control('search'),
                onChanged: (_) => _onQuery(),
              ),
            ],
          ),
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
            _rows(context, matches, firstKey: _firstMatchKey),
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
        // The kinds card's month; what it shows, the coach line and the
        // list above say.
        CalendarGuideStageMatrix(
          matrix: MonthDotMatrix(
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
      ],
    );
  }
}

/// Brings what the search field reports into view once the keyboard a focus
/// on it raised has come to rest: the matches under the field are what she
/// types to see, with the coach line above it where the room allows, and
/// the field's own scroll would leave the matches under the keyboard.
///
/// Once per focus gain, never per keystroke — the field keeps its own caret
/// in view while she types. The inset counts as at rest a frame after it
/// last moved, since a keyboard's rise reaches the app as a run of insets.
/// It is the view's, as the field's own caret tracking reads it: the page's
/// `Scaffold` takes the inset out of its body's `MediaQuery`.
class _CaptionAboveKeyboard extends StatefulWidget {
  const _CaptionAboveKeyboard({
    required this.focusNode,
    required this.caption,
    required this.firstMatch,
    required this.child,
  });

  final FocusNode focusNode;
  final GlobalKey caption;
  final GlobalKey firstMatch;
  final Widget child;

  @override
  State<_CaptionAboveKeyboard> createState() => _CaptionAboveKeyboardState();
}

class _CaptionAboveKeyboardState extends State<_CaptionAboveKeyboard>
    with WidgetsBindingObserver {
  double _inset = 0;

  /// Focus was gained and the caption not yet brought into view.
  bool _waiting = false;

  /// The inset moved since the last frame's check.
  bool _moved = false;

  /// A check is scheduled after the coming frame.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(_CaptionAboveKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  double _viewInset() {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    if (!_waiting) return;
    final inset = _viewInset();
    if (inset == _inset) return;
    _inset = inset;
    _moved = true;
    if (_checking) return;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback(_check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    _waiting = widget.focusNode.hasFocus;
    if (_waiting) _inset = _viewInset();
  }

  void _check(Duration _) {
    if (!mounted || !_waiting) {
      _checking = false;
      return;
    }
    if (_moved) {
      // Still rising: look again after the next frame.
      _moved = false;
      WidgetsBinding.instance.addPostFrameCallback(_check);
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _checking = false;
    _waiting = false;
    if (_inset > 0) _reveal();
  }

  /// Scrolls the coach line, which sits above the field, up to the top, as
  /// `Scrollable.ensureVisible` at alignment 0.0 would, where the line, the
  /// field and the first match all fit above the keyboard; otherwise the
  /// field goes to the top, the matches under it, as before the coach line
  /// (German at 2.0 on a small phone). Never past the field — it keeps its
  /// caret in view on every keystroke, so a page scrolled past it would
  /// jump back under her at the first letter — and never back down.
  void _reveal() {
    final caption = widget.caption.currentContext?.findRenderObject();
    // The node's context is the field's own: its box, and the air above
    // the caret the field keeps when it scrolls itself into view.
    final focused = widget.focusNode.context;
    final field = focused?.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (caption == null || field is! RenderBox || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(field);
    if (viewport == null) return;
    final air =
        focused!
            .findAncestorWidgetOfExactType<EditableText>()
            ?.scrollPadding
            .top ??
        0;
    final lineAtTop = viewport.getOffsetToReveal(caption, 0.0).offset;
    // With no match, the field is the last thing she needs to see.
    final last = widget.firstMatch.currentContext?.findRenderObject() ?? field;
    final fits = viewport.getOffsetToReveal(last, 1.0).offset <= lineAtTop;
    final target = fits
        ? lineAtTop
        : viewport
              .getOffsetToReveal(
                field,
                0.0,
                rect: Rect.fromLTRB(
                  0,
                  -air,
                  field.size.width,
                  field.size.height,
                ),
              )
              .offset;
    if (target <= position.pixels) return;
    position.jumpTo(math.min(target, position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
