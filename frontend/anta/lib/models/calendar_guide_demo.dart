import 'package:flutter/foundation.dart' show listEquals;
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/calendar_categories.dart';
import '../constants/event_presence.dart' show PresenceStatus;
import '../l10n/app_localizations.dart';
import '../services/day_bars_resolver.dart';
import '../utils/event_agenda.dart';
import 'calendar_category.dart';
import 'calendar_event.dart';
import 'calendar_grid_filters.dart';
import 'calendar_panel_mode.dart';
import 'day_bar.dart';
import 'event_alert.dart';
import 'recurrence_rule.dart';

/// The practice calendar's whole world: six events, their marks and skips,
/// and what the page is showing.
///
/// A plain mutable object the practice page's `State` owns, because the page
/// must save nothing: the real calendar's presence, skip and description
/// caches are static and app-wide, so a demo that wrote them would leak into
/// the owner's calendar. Here every fact lives in this object and dies with
/// the page; the shared widgets are fed from it explicitly.
class GuideDemoCalendar {
  GuideDemoCalendar({
    required AppLocalizations l10n,
    required DateTime today,
    required List<CalendarCategory> categories,
  }) : _l10n = l10n,
       _categories = [
         for (final category in categories)
           if (!category.isHidden) category,
       ],
       today = DateTime.utc(today.year, today.month, today.day) {
    _seedEvents = List.unmodifiable(_seed());
    reset();
  }

  final AppLocalizations _l10n;

  /// The owner's visible categories as `CategoryService` loaded them — never
  /// the static `CalendarCategories` cache, which is still empty when the
  /// app relaunches onto the guide before the calendar has loaded.
  final List<CalendarCategory> _categories;

  /// What [reset] restores and [isDirty] compares against, built once.
  late final List<CalendarEvent> _seedEvents;

  /// Date-only UTC, read once: a practice session does not straddle midnight
  /// in any way that matters, and every seed date is relative to it.
  final DateTime today;

  /// How far the Upcoming panel looks ahead of today: enough for every demo
  /// event to show at least once (the book club fortnightly, rent monthly).
  static const int upcomingDays = 35;

  /// The prefix of every demo id: no stored event carries it, so nothing a
  /// shared widget looks up by id can find the owner's data under it.
  static const String idPrefix = 'guide-demo-';

  List<CalendarEvent> _events = const [];
  final Map<String, Map<DateTime, PresenceStatus>> _presence = {};
  final Map<String, Set<DateTime>> _skips = {};
  final Map<String, Map<DateTime, String>> _descriptions = {};
  final Map<String, List<EventAlert>> _alerts = {};
  int _nextId = 0;

  late DateTime selectedDay;
  late DateTime focusedDay;
  CalendarFormat format = CalendarFormat.month;
  CalendarPanelMode panelMode = CalendarPanelMode.day;
  CalendarGridFilters _filters = CalendarGridFilters.none;

  /// The grid's per-day lists for the months around [focusedDay], built when
  /// the events, the skips or the filters change and when the grid pages —
  /// never inside the grid's `eventLoader`, which only looks a day up.
  Map<DateTime, List<CalendarEvent>> _byDay = const {};
  DateTime? _windowMonth;

  /// Each day's bars as the grid last asked for them, dropped with the
  /// per-day map and with a presence mark: the grid's `markerBuilder` runs
  /// for every cell on every build, and nothing it draws changes in between.
  final Map<DateTime, List<DayBar>> _bars = {};
  DayBarsResolver? _barsResolver;

  /// The Upcoming panel's occurrences, scanned on first ask after a change.
  List<EventOccurrence>? _upcoming;

  List<CalendarEvent> get events => _events;
  CalendarGridFilters get filters => _filters;

  /// Whether what the demo holds differs from the seed — what Start over
  /// offers to undo. Compared by value, never a flag, so a change taken back
  /// (an event added then deleted, a mark then unmarked, the filters applied
  /// unchanged) leaves nothing to undo. Picking a day, a grid format or a
  /// panel mode is looking, not changing, and does not count.
  bool get isDirty =>
      !listEquals(_events, _seedEvents) ||
      _filters != CalendarGridFilters.none ||
      _skips.values.any((days) => days.isNotEmpty) ||
      _descriptions.values.any((days) => days.isNotEmpty) ||
      _alerts.values.any((alerts) => alerts.isNotEmpty) ||
      !_presenceIsSeed();

  /// The marks against the seed's, each read as what it means: a mark that
  /// says what the event's default already says is no change.
  bool _presenceIsSeed() {
    final seed = _seedPresence();
    final ids = {..._presence.keys, ...seed.keys};
    for (final id in ids) {
      final event = byId(id);
      if (event == null) continue;
      final now = _presence[id] ?? const {};
      final then = seed[id] ?? const {};
      for (final day in {...now.keys, ...then.keys}) {
        final absent = event.assumesAbsentOn(day);
        final missedNow =
            (now[day] ?? _statusOf(absent)) == PresenceStatus.missed;
        final missedThen =
            (then[day] ?? _statusOf(absent)) == PresenceStatus.missed;
        if (missedNow != missedThen) return false;
      }
    }
    return true;
  }

  static PresenceStatus _statusOf(bool missed) =>
      missed ? PresenceStatus.missed : PresenceStatus.present;

  /// Back to the six seed events, today picked, the month shown, no filter.
  void reset() {
    _events = _seedEvents;
    _presence
      ..clear()
      ..addAll(_seedPresence());
    _skips.clear();
    _descriptions.clear();
    _alerts.clear();
    _nextId = 0;
    selectedDay = today;
    focusedDay = today;
    format = CalendarFormat.month;
    panelMode = CalendarPanelMode.day;
    _filters = CalendarGridFilters.none;
    _invalidate();
  }

  /// A fresh id for an event stamped out from a template.
  String newId() => '${idPrefix}new-${_nextId++}';

  /// Adds [event] under a demo id — the editor stamps a bare uuid, which
  /// gets the prefix here — and returns it as stored.
  CalendarEvent add(CalendarEvent event, {List<EventAlert>? alerts}) {
    final stored = event.id.startsWith(idPrefix)
        ? event
        : event.copyWith(id: '$idPrefix${event.id}');
    _events = List.unmodifiable([..._events, stored]);
    if (alerts != null) _setAlerts(stored.id, alerts);
    _invalidate();
    return stored;
  }

  void replace(CalendarEvent event, {List<EventAlert>? alerts}) {
    _events = List.unmodifiable([
      for (final e in _events) e.id == event.id ? event : e,
    ]);
    if (alerts != null) _setAlerts(event.id, alerts);
    _invalidate();
  }

  void remove(String id) {
    _events = List.unmodifiable([
      for (final e in _events)
        if (e.id != id) e,
    ]);
    _presence.remove(id);
    _skips.remove(id);
    _descriptions.remove(id);
    _alerts.remove(id);
    _invalidate();
  }

  /// The event's own alerts as the editor last saved them, fed back to it on
  /// the next open: `EventAlerts` holds nothing for a demo id.
  List<EventAlert> alertsFor(String id) => _alerts[id] ?? const [];

  void _setAlerts(String id, List<EventAlert> alerts) {
    if (alerts.isEmpty) {
      _alerts.remove(id);
    } else {
      _alerts[id] = List.unmodifiable([
        for (final alert in alerts) alert.copyWith(eventId: id),
      ]);
    }
  }

  CalendarEvent? byId(String id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// Cancels one day of a repeating event, as the real skip does: a one-time
  /// event has no day to skip.
  void skip(String id, DateTime day) {
    (_skips[id] ??= {}).add(_dayOf(day));
    _invalidate();
  }

  /// The days of [id] the newcomer cancelled.
  Set<DateTime> skipsFor(String id) => {...?_skips[id]};

  /// The editor's skip picker hands back the whole set.
  void setSkips(String id, Set<DateTime> days) {
    if (days.isEmpty) {
      _skips.remove(id);
    } else {
      _skips[id] = {for (final day in days) _dayOf(day)};
    }
    _invalidate();
  }

  /// An explicit mark, as the day panel's button and the detail sheet's
  /// chips write it.
  void setPresence(String id, DateTime day, {required bool missed}) {
    (_presence[id] ??= {})[_dayOf(day)] = _statusOf(missed);
    _upcoming = null;
    _bars.clear();
    if (_filters.hasOccurrenceAxis) _rebuildWindow();
  }

  /// `EventPresence.isMissed` over the demo's own marks: an explicit mark
  /// wins, else the event's own default. The reader every shared widget the
  /// page draws takes in place of the facade.
  bool isMissed(CalendarEvent event, DateTime day) {
    if (!event.tracksPresence || event.rule is OneTimeRecurrence) return false;
    final utcDay = _dayOf(day);
    final mark = _presence[event.id]?[utcDay];
    if (mark != null) return mark == PresenceStatus.missed;
    return event.assumesAbsentOn(utcDay);
  }

  /// This day's own row, when the event keeps one per day — what the editor
  /// takes as its pending override.
  String? overrideFor(String id, DateTime day) =>
      _descriptions[id]?[_dayOf(day)];

  /// `OccurrenceDescriptions.descriptionFor` over the demo's rows: the day's
  /// own text while the event keeps one per day (an empty row included),
  /// else the event's.
  String? descriptionFor(CalendarEvent event, DateTime day) {
    if (!event.perOccurrenceDescriptions || event.rule is OneTimeRecurrence) {
      return event.description;
    }
    return overrideFor(event.id, day) ?? event.description;
  }

  void setDescription(String id, DateTime day, String? text) {
    final forEvent = _descriptions[id] ??= {};
    if (text == null) {
      forEvent.remove(_dayOf(day));
    } else {
      forEvent[_dayOf(day)] = text;
    }
    if (forEvent.isEmpty) _descriptions.remove(id);
  }

  set filters(CalendarGridFilters value) {
    _filters = value;
    _invalidate();
  }

  /// [resolver]'s bars for [day], resolved once per day until the per-day
  /// map is rebuilt or a mark changes; a new resolver starts over.
  List<DayBar> barsFor(
    DateTime day,
    List<CalendarEvent> events,
    DayBarsResolver resolver,
  ) {
    if (!identical(resolver, _barsResolver)) {
      _barsResolver = resolver;
      _bars.clear();
    }
    return _bars[_dayOf(day)] ??= resolver.resolve(day, events);
  }

  /// Turning the grid's page: the per-day map follows the focused month.
  void focus(DateTime day) {
    focusedDay = day;
    _ensureWindow();
  }

  /// The grid's `eventLoader`: a lookup, nothing more.
  List<CalendarEvent> eventsFor(DateTime day) =>
      _byDay[DateTime.utc(day.year, day.month, day.day)] ?? const [];

  /// Every event on [day] whatever the filters hide: the day and timeline
  /// panels' list when the filters ask the panels to show the whole day.
  List<CalendarEvent> allEventsFor(DateTime day) => [
    for (final event in _events)
      if (occursOn(event, day)) event,
  ]..sort(EventAgenda.compareWithinDay);

  /// Whether [event] really occurs on [day] here — its rule, less the demo's
  /// skips. The grid's filters do not apply: a filter hides, it never
  /// removes.
  bool occursOn(CalendarEvent event, DateTime day) {
    if (!event.occursOnUtcDay(day)) return false;
    return event.rule is OneTimeRecurrence ||
        !(_skips[event.id]?.contains(day) ?? false);
  }

  /// Every unfiltered occurrence from today over [upcomingDays], the order
  /// the real agenda lists them in. The agenda inherits only the hidden
  /// categories from the grid's filters, as the real one does.
  List<EventOccurrence> upcoming() {
    final cached = _upcoming;
    if (cached != null) return cached;
    final hidden = _filters.hiddenCategoryIds;
    final scanned = <EventOccurrence>[];
    for (var offset = 0; offset < upcomingDays; offset++) {
      final day = DateTime.utc(today.year, today.month, today.day + offset);
      final onDay = [
        for (final event in _events)
          if (!hidden.contains(event.categoryId) && occursOn(event, day)) event,
      ]..sort(EventAgenda.compareWithinDay);
      for (final event in onDay) {
        scanned.add(EventOccurrence(event: event, day: day));
      }
    }
    return _upcoming = List.unmodifiable(scanned);
  }

  void _invalidate() {
    _upcoming = null;
    _windowMonth = null;
    _ensureWindow();
  }

  void _ensureWindow() {
    final month = DateTime.utc(focusedDay.year, focusedDay.month);
    if (month == _windowMonth) return;
    _windowMonth = month;
    _rebuildWindow();
  }

  /// The month before, the focused one and the month after, with a week to
  /// spare on each side: every day a six-row grid can show while it pages.
  void _rebuildWindow() {
    final month = _windowMonth!;
    final first = DateTime.utc(month.year, month.month - 1, 1 - 7);
    final last = DateTime.utc(month.year, month.month + 2, 7);
    _bars.clear();
    final visible = _filters.apply(_events, todayUtc: today);
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (
      var day = first;
      !day.isAfter(last);
      day = DateTime.utc(day.year, day.month, day.day + 1)
    ) {
      final onDay = [
        for (final event in visible)
          if (occursOn(event, day) &&
              (!_filters.missedOnly || isMissed(event, day)))
            event,
      ];
      if (onDay.isEmpty) continue;
      byDay[day] = onDay..sort(EventAgenda.compareWithinDay);
    }
    _byDay = byDay;
  }

  static DateTime _dayOf(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day);

  DateTime _offset(int days) =>
      DateTime.utc(today.year, today.month, today.day + days);

  /// The six events of the record's §8.2 table 6, their categories taken
  /// from the visible catalogue in order, cycling, so the bars wear the
  /// owner's own colours; the birthday takes the Birthday built-in when it is
  /// visible.
  List<CalendarEvent> _seed() {
    final visible = _categories;
    String categoryAt(int index) => visible.isEmpty
        ? CalendarCategories.fallback.id
        : visible[index % visible.length].id;
    final birthday = visible.any((c) => c.id == kBirthdayCategoryId)
        ? kBirthdayCategoryId
        : categoryAt(3);
    final thursday = _offset((DateTime.thursday - today.weekday) % 7);
    return [
      CalendarEvent(
        id: '${idPrefix}dentist',
        title: _l10n.calendarGuideDemoEventDentist,
        categoryId: categoryAt(0),
        startDate: _offset(2),
        time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
      ),
      CalendarEvent(
        id: '${idPrefix}yoga',
        title: _l10n.calendarGuideDemoEventYoga,
        categoryId: categoryAt(1),
        startDate: _offset(-28),
        rule: WeeklyRecurrence(weekdays: {today.weekday}),
        time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
        tracksPresence: true,
      ),
      CalendarEvent(
        id: '${idPrefix}rent',
        title: _l10n.calendarGuideDemoEventRent,
        categoryId: categoryAt(2),
        startDate: DateTime.utc(today.year, today.month - 2, 1),
        rule: const MonthlyRecurrence(),
      ),
      CalendarEvent(
        id: '${idPrefix}birthday',
        title: _l10n.calendarGuideDemoEventBirthday,
        categoryId: birthday,
        startDate: DateTime.utc(1964, 5, 12),
        rule: const YearlyRecurrence(),
        countOccurrences: true,
        countStyle: OccurrenceCountStyle.elapsed,
      ),
      CalendarEvent(
        id: '${idPrefix}book-club',
        title: _l10n.calendarGuideDemoEventBookClub,
        categoryId: categoryAt(4),
        startDate: thursday.subtract(const Duration(days: 28)),
        rule: const WeeklyRecurrence(
          weekdays: {DateTime.thursday},
          interval: 2,
        ),
        time: const EventTime(startMinute: 19 * 60),
      ),
      CalendarEvent(
        id: '${idPrefix}flight',
        title: _l10n.calendarGuideDemoEventFlight,
        categoryId: categoryAt(5),
        startDate: _offset(9),
        description: _l10n.calendarGuideDemoEventFlightNote,
      ),
    ];
  }

  /// Yoga's four past weeks: the last one missed, the three before present,
  /// so the attendance count has something to say.
  Map<String, Map<DateTime, PresenceStatus>> _seedPresence() => {
    '${idPrefix}yoga': {
      _offset(-7): PresenceStatus.missed,
      _offset(-14): PresenceStatus.present,
      _offset(-21): PresenceStatus.present,
      _offset(-28): PresenceStatus.present,
    },
  };
}
