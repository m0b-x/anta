import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../constants/event_presence.dart';
import '../services/note_money_ledger_service.dart';
import 'calendar_event.dart';
import 'recurrence_rule.dart';
import 'upcoming_agenda_filters.dart';

/// Whether an event carries a time of day — the filterable form of
/// [CalendarEvent.allDay], which is itself derived from `time == null`.
///
/// [all] is the filter off. Parsed by name with a forward-compatible fallback,
/// so a value written by a newer build degrades to "off" rather than throwing.
enum CalendarEventTiming {
  all,
  timed,
  allDay;

  static CalendarEventTiming fromName(String? name) {
    for (final timing in values) {
      if (timing.name == name) return timing;
    }
    return all;
  }
}

/// Everything the calendar grid narrows by — one value object rather than a
/// widening parameter list, so a new axis reaches `CalendarBloc`, the filter
/// sheet and the summary chips through a single field.
///
/// Three kinds of axis live here, and the difference is load-bearing:
///
/// 1. **Event-level narrowing** ([allows]) — a property of the event alone, so
///    `CalendarBloc._visibleEvents` applies it *once per filter change* and
///    builds both the day cache and the window partition over the narrowed
///    list. The 42-cell grid pays nothing for these.
/// 2. **Occurrence-level narrowing** ([allowsOccurrence]) — needs the day as
///    well, so it can only run inside `CalendarBloc.eventsForDay`, per day, on
///    a cache miss. [missedOnly] is the only one, and it is why the presence
///    handlers invalidate the day cache **while it is active**: presence
///    normally changes painting, not membership, and this axis makes it change
///    membership.
/// 3. **Layers** ([showHolidays], [showFasting], [showMoney]) — not event
///    filters at all. They compose the *providers* the bar/tint/summary
///    resolvers are built from, so turning one off removes a day annotation
///    from the grid and the day panel together.
///
/// Filtering stays **render-time only**: nothing here reaches
/// `CalendarEvent.occursOn`, so a filtered event still occurs, still exports,
/// and still counts its occurrences.
class CalendarGridFilters extends Equatable {
  /// Ids of categories hidden from the grid. Empty means "show everything".
  /// A denylist rather than an allowlist so a newly created category is
  /// visible by default and a deleted one leaves a harmless stale id behind.
  final Set<String> hiddenCategoryIds;

  /// Priorities to include. **Empty means every priority** — the filter is
  /// off, not "nothing matches". Mirrors [UpcomingAgendaFilters.priorities].
  final Set<int> priorities;

  /// Which events the grid shows — see [AgendaEventType], shared with the
  /// agenda so the two surfaces can never disagree about what "recurring"
  /// means ([SpecificDatesRecurrence] counts as recurring on both).
  final AgendaEventType eventType;

  /// Whether the grid shows timed events, all-day events, or both.
  final CalendarEventTiming timing;

  /// Keep only events participating in presence tracking
  /// ([EventPresence.appliesTo], so a one-time event never qualifies).
  final bool trackedOnly;

  /// Keep only events carrying a [CalendarEvent.noteId].
  final bool linkedNotesOnly;

  /// Keep only events whose linked note carries ledger entries — the month as
  /// a spending view. Implies [linkedNotesOnly]'s test and then some.
  final bool moneyOnly;

  /// Keep only events carrying description text.
  final bool withDescriptionOnly;

  /// Keep only events rendering an occurrence count label
  /// ([CalendarEvent.countOccurrences]) — the streak-shaped commitments.
  final bool countedOnly;

  /// Keep only occurrences marked missed. **The one day-dependent axis** —
  /// see the class doc.
  final bool missedOnly;

  /// Drop events whose [CalendarEvent.endDate] has already passed — the
  /// commitments that are over but still paint their history on the grid.
  final bool hideEnded;

  /// Whether public holidays are drawn at all (grid badge + day-panel row).
  final bool showHolidays;

  /// Whether fasting days are drawn at all (cell wash, day-rail base, and the
  /// day-panel row).
  final bool showFasting;

  /// Whether the money bar and the day panel's money row are drawn.
  final bool showMoney;

  /// Whether the day and timeline panels ignore every narrowing axis and list
  /// the whole day.
  ///
  /// **Widens rather than narrows**, so it is deliberately absent from
  /// [activeCount] and gets no summary chip: it can never be the reason
  /// something is missing. The grid stays filtered either way — that is the
  /// point, "narrow the month, keep the day whole".
  final bool panelShowsAll;

  const CalendarGridFilters({
    this.hiddenCategoryIds = const {},
    this.priorities = const {},
    this.eventType = AgendaEventType.all,
    this.timing = CalendarEventTiming.all,
    this.trackedOnly = false,
    this.linkedNotesOnly = false,
    this.moneyOnly = false,
    this.withDescriptionOnly = false,
    this.countedOnly = false,
    this.missedOnly = false,
    this.hideEnded = false,
    this.showHolidays = true,
    this.showFasting = true,
    this.showMoney = true,
    this.panelShowsAll = false,
  });

  /// The filter off, in every axis.
  static const CalendarGridFilters none = CalendarGridFilters();

  /// True when nothing is narrowing the grid. [panelShowsAll] is excluded for
  /// the same reason it is excluded from [activeCount] — it hides nothing.
  bool get isEmpty => activeCount == 0;

  /// True when no axis needs the *day* to decide — i.e. `eventsForDay` can
  /// trust the pre-filtered list wholesale. Read by `CalendarBloc` to keep the
  /// per-day loop free in the common case.
  bool get hasOccurrenceAxis => missedOnly;

  /// How many axes are currently narrowing the grid — the number the app-bar
  /// badge shows and the summary chips undo one at a time. Categories count
  /// once however many ids are hidden, matching
  /// [UpcomingAgendaFilters.restrictiveFilterCount]'s shape; a layer counts
  /// only when it is **off**, because that is when it removes something.
  int get activeCount {
    var count = 0;
    if (hiddenCategoryIds.isNotEmpty) count++;
    if (priorities.isNotEmpty) count++;
    if (eventType != AgendaEventType.all) count++;
    if (timing != CalendarEventTiming.all) count++;
    if (trackedOnly) count++;
    if (linkedNotesOnly) count++;
    if (moneyOnly) count++;
    if (withDescriptionOnly) count++;
    if (countedOnly) count++;
    if (missedOnly) count++;
    if (hideEnded) count++;
    if (!showHolidays) count++;
    if (!showFasting) count++;
    if (!showMoney) count++;
    return count;
  }

  /// Whether [event] survives every active **event-level** axis. [todayUtc]
  /// must be date-only UTC and is read only by [hideEnded].
  ///
  /// Ordered cheapest-and-most-selective first: field comparisons before the
  /// set probes, and the ledger lookup — the only one touching another
  /// subsystem's cache — last.
  bool allows(CalendarEvent event, {required DateTime todayUtc}) {
    switch (eventType) {
      case AgendaEventType.all:
        break;
      case AgendaEventType.recurring:
        if (event.rule is OneTimeRecurrence) return false;
      case AgendaEventType.oneTime:
        if (event.rule is! OneTimeRecurrence) return false;
      case AgendaEventType.none:
        return false;
    }
    switch (timing) {
      case CalendarEventTiming.all:
        break;
      case CalendarEventTiming.timed:
        if (event.time == null) return false;
      case CalendarEventTiming.allDay:
        if (event.time != null) return false;
    }
    if (countedOnly && !event.countOccurrences) return false;
    if (withDescriptionOnly && (event.description?.isEmpty ?? true)) {
      return false;
    }
    if (trackedOnly && !EventPresence.appliesTo(event)) return false;
    if (hideEnded) {
      final end = event.endDateUtc;
      if (end != null && end.isBefore(todayUtc)) return false;
    }
    if (priorities.isNotEmpty && !priorities.contains(event.priority)) {
      return false;
    }
    if (hiddenCategoryIds.contains(event.categoryId)) return false;
    if (linkedNotesOnly || moneyOnly) {
      final noteId = event.noteId;
      if (noteId == null) return false;
      if (moneyOnly &&
          NoteMoneyLedgerService.instanceOrNull?.ledgerFor(noteId) == null) {
        return false;
      }
    }
    return true;
  }

  /// Whether [event]'s occurrence on [dayUtc] survives the day-dependent
  /// axes. Called per (event, day) inside `CalendarBloc.eventsForDay`, and
  /// only when [hasOccurrenceAxis] holds.
  ///
  /// [dayUtc] must already be date-only UTC — [EventPresence.isMissed]
  /// debug-asserts it.
  bool allowsOccurrence(CalendarEvent event, DateTime dayUtc) {
    if (!missedOnly) return true;
    return EventPresence.appliesTo(event) &&
        EventPresence.isMissed(event.id, dayUtc);
  }

  /// [events] narrowed to what the grid should render, by the event-level
  /// axes alone.
  ///
  /// Returns **the same list instance** when no event-level axis is active,
  /// which is what keeps the bloc's `identical`-guarded window partition and
  /// its callers' `identical` rebuild gates behaving exactly as they did
  /// before this type existed: with no filter on, there is no new object for
  /// anything to notice.
  List<CalendarEvent> apply(
    List<CalendarEvent> events, {
    required DateTime todayUtc,
  }) {
    if (!_narrowsEvents) return events;
    return List<CalendarEvent>.unmodifiable([
      for (final event in events)
        if (allows(event, todayUtc: todayUtc)) event,
    ]);
  }

  /// Whether [allows] can reject anything. Layers, [panelShowsAll] and
  /// [missedOnly] all leave the event list alone.
  bool get _narrowsEvents =>
      hiddenCategoryIds.isNotEmpty ||
      priorities.isNotEmpty ||
      eventType != AgendaEventType.all ||
      timing != CalendarEventTiming.all ||
      trackedOnly ||
      linkedNotesOnly ||
      moneyOnly ||
      withDescriptionOnly ||
      countedOnly ||
      hideEnded;

  CalendarGridFilters copyWith({
    Set<String>? hiddenCategoryIds,
    Set<int>? priorities,
    AgendaEventType? eventType,
    CalendarEventTiming? timing,
    bool? trackedOnly,
    bool? linkedNotesOnly,
    bool? moneyOnly,
    bool? withDescriptionOnly,
    bool? countedOnly,
    bool? missedOnly,
    bool? hideEnded,
    bool? showHolidays,
    bool? showFasting,
    bool? showMoney,
    bool? panelShowsAll,
  }) {
    return CalendarGridFilters(
      hiddenCategoryIds: hiddenCategoryIds ?? this.hiddenCategoryIds,
      priorities: priorities ?? this.priorities,
      eventType: eventType ?? this.eventType,
      timing: timing ?? this.timing,
      trackedOnly: trackedOnly ?? this.trackedOnly,
      linkedNotesOnly: linkedNotesOnly ?? this.linkedNotesOnly,
      moneyOnly: moneyOnly ?? this.moneyOnly,
      withDescriptionOnly: withDescriptionOnly ?? this.withDescriptionOnly,
      countedOnly: countedOnly ?? this.countedOnly,
      missedOnly: missedOnly ?? this.missedOnly,
      hideEnded: hideEnded ?? this.hideEnded,
      showHolidays: showHolidays ?? this.showHolidays,
      showFasting: showFasting ?? this.showFasting,
      showMoney: showMoney ?? this.showMoney,
      panelShowsAll: panelShowsAll ?? this.panelShowsAll,
    );
  }

  /// Clears every narrowing axis, **keeping [panelShowsAll]**: Reset means
  /// "show me everything again", and the panel preference is not something
  /// being hidden.
  CalendarGridFilters cleared() =>
      CalendarGridFilters(panelShowsAll: panelShowsAll);

  /// JSON, under one settings key rather than fifteen rows — the shape
  /// `calendar_fasting_schedule` already established for a compound setting.
  ///
  /// **Only non-default values are written**, so an absent field decodes to
  /// its default and a build that adds an axis reads an older blob correctly.
  String encode() {
    final map = <String, Object>{};
    if (hiddenCategoryIds.isNotEmpty) {
      map['hiddenCategories'] = (hiddenCategoryIds.toList()..sort()).join(',');
    }
    if (priorities.isNotEmpty) {
      map['priorities'] = (priorities.toList()..sort()).join(',');
    }
    if (eventType != AgendaEventType.all) map['eventType'] = eventType.name;
    if (timing != CalendarEventTiming.all) map['timing'] = timing.name;
    if (trackedOnly) map['trackedOnly'] = true;
    if (linkedNotesOnly) map['linkedNotesOnly'] = true;
    if (moneyOnly) map['moneyOnly'] = true;
    if (withDescriptionOnly) map['withDescriptionOnly'] = true;
    if (countedOnly) map['countedOnly'] = true;
    if (missedOnly) map['missedOnly'] = true;
    if (hideEnded) map['hideEnded'] = true;
    if (!showHolidays) map['showHolidays'] = false;
    if (!showFasting) map['showFasting'] = false;
    if (!showMoney) map['showMoney'] = false;
    if (panelShowsAll) map['panelShowsAll'] = true;
    if (map.isEmpty) return '';
    return jsonEncode(map);
  }

  /// Inverse of [encode]. Anything malformed — junk, a truncated write, a
  /// field holding the wrong type — degrades to [none] or to that field's
  /// default rather than throwing: a corrupt preference must never be able to
  /// stop the calendar from painting.
  static CalendarGridFilters decode(String? raw) {
    if (raw == null || raw.isEmpty) return none;
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return none;
      map = decoded;
    } catch (e) {
      debugPrint('[CalendarGridFilters] Malformed stored filters: $e');
      return none;
    }
    bool flag(String key, {bool orElse = false}) {
      final value = map[key];
      return value is bool ? value : orElse;
    }

    return CalendarGridFilters(
      hiddenCategoryIds: _decodeIds(map['hiddenCategories']),
      priorities: _decodePriorities(map['priorities']),
      eventType: AgendaEventType.fromName(
        map['eventType'] is String ? map['eventType'] as String : null,
      ),
      timing: CalendarEventTiming.fromName(
        map['timing'] is String ? map['timing'] as String : null,
      ),
      trackedOnly: flag('trackedOnly'),
      linkedNotesOnly: flag('linkedNotesOnly'),
      moneyOnly: flag('moneyOnly'),
      withDescriptionOnly: flag('withDescriptionOnly'),
      countedOnly: flag('countedOnly'),
      missedOnly: flag('missedOnly'),
      hideEnded: flag('hideEnded'),
      showHolidays: flag('showHolidays', orElse: true),
      showFasting: flag('showFasting', orElse: true),
      showMoney: flag('showMoney', orElse: true),
      panelShowsAll: flag('panelShowsAll'),
    );
  }

  static Set<String> _decodeIds(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    return {
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
  }

  static Set<int> _decodePriorities(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    final values = <int>{};
    for (final part in raw.split(',')) {
      final value = int.tryParse(part.trim());
      if (value != null &&
          value >= kMinEventPriority &&
          value <= kMaxEventPriority) {
        values.add(value);
      }
    }
    return values;
  }

  @override
  List<Object?> get props => [
    hiddenCategoryIds,
    priorities,
    eventType,
    timing,
    trackedOnly,
    linkedNotesOnly,
    moneyOnly,
    withDescriptionOnly,
    countedOnly,
    missedOnly,
    hideEnded,
    showHolidays,
    showFasting,
    showMoney,
    panelShowsAll,
  ];
}
