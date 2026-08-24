import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants/public_holidays.dart';
import '../../models/calendar_event.dart';
import '../../services/calendar_event_service.dart';
import '../../services/category_service.dart';
import '../../services/event_occurrence_service.dart';
import '../../services/event_presence_service.dart';
import '../../services/event_skip_service.dart';
import '../../services/event_template_service.dart';
import '../../services/note_money_ledger_service.dart';
import '../../services/public_holiday_service.dart';
import '../../utils/event_agenda.dart';
import 'calendar_event.dart';
import 'calendar_state.dart';

export 'calendar_event.dart';
export 'calendar_state.dart';

/// One window's worth of [EventAgenda.partitionForWindow] output, cached by
/// [CalendarBloc._partitionFor] alongside the exact inputs it was built from
/// — an [allEvents] instance and a `[windowStart, windowEndExclusive)` span —
/// so a read can tell a stale entry from a fresh one with one `identical`
/// check and two `DateTime` comparisons, no deep comparison of either
/// collection.
typedef _DayCachePartition = ({
  List<CalendarEvent> allEvents,
  DateTime windowStart,
  DateTime windowEndExclusive,
  List<CalendarEvent> dense,
  Map<DateTime, List<CalendarEvent>> sparseByDay,
  Map<DateTime, List<CalendarEvent>> oneTimeByDay,
});

class CalendarBloc extends Bloc<CalendarPageEvent, CalendarPageState> {
  /// Seed for the first resolution of [CalendarEventService], not a permanent
  /// binding.
  ///
  /// A `FutureOr` because the two callers need different things: DI hands over
  /// `getInstance()` unawaited so `registerFactory` can stay synchronous
  /// (`BlocProvider.create` requires it), while tests pass a
  /// `forTesting`-built instance directly. Every handler that needs the
  /// service is already `async`, and the two synchronous, build-time-callable
  /// methods — [eventsForDay] and [monthNetFor] — read `state`, never the
  /// service.
  final FutureOr<CalendarEventService> _seed;
  CalendarEventService? _service;

  /// Generation of the event store the current state was built from.
  ///
  /// Seeded from the current value rather than a sentinel, so [isStale] is
  /// false at construction and the page's first check cannot double-dispatch
  /// against DI's own `..add(LoadCalendarEvents())`.
  int _seenExternalRevision = CalendarEventService.externalRevision;

  /// True when the event store was replaced wholesale — a backup restore or a
  /// database switch — since this bloc last loaded.
  ///
  /// Read by `CalendarPage` when it appears, so a bloc that outlived the
  /// replacement reloads instead of rendering a store that no longer exists.
  bool get isStale =>
      _seenExternalRevision != CalendarEventService.externalRevision;

  /// Memoizes recurrence expansion per calendar day. The first lookup for a
  /// day runs the scan described at [_dayCandidates]; the result is cached so
  /// subsequent rebuilds (day selection, focus/format changes — none of
  /// which alter the result) are O(1) map lookups. Invalidated only when the
  /// event set or the visible-category filter changes.
  ///
  /// Bounded by [_evictColdDayCacheEntries], never by the lookup itself. A
  /// clear inside [eventsForDay] would fire mid-build — between
  /// `eventLoader`'s and `_buildDayCell`'s lookups of the very day being
  /// painted — forcing a full re-expansion of the page the frame is already
  /// drawing. Eviction instead runs from [_onChangeFocusedDay], on a genuine
  /// month change.
  final Map<DateTime, List<CalendarEvent>> _dayCache = {};
  static const int _maxDayCacheEntries = 512;

  /// Half-width, in months, of the window [_evictColdDayCacheEntries] keeps
  /// warm around the focused month — [_dayCacheWindowFor]'s single
  /// definition, shared with `_CalendarViewState`'s neighbour-month prewarm
  /// *and* [_partitionFor]. The prewarm only ever fills the month immediately
  /// before/after (radius 1), strictly inside this radius, so nothing it just
  /// warmed is evicted — or falls outside the partition — before it can be
  /// read.
  static const int _dayCacheWindowMonths = 3;

  /// Cached [EventAgenda.partitionForWindow] split of the current
  /// [_dayCacheWindowFor] window, consulted by [_dayCandidates] on a
  /// [_dayCache] miss for a day inside that window. `null` before the first
  /// such miss, and whenever anything it depends on changes.
  ///
  /// Built from [CalendarPageLoaded.allEvents] and the window bounds alone —
  /// **never** [CalendarPageLoaded.hiddenCategoryIds] (that filter stays
  /// render-time, applied in [eventsForDay] exactly as before this cache
  /// existed) and never any skip/holiday state (every candidate the
  /// partition returns is still validated fresh through `occursOnUtcDay`,
  /// which is what actually consults those). [_partitionFor] guards every
  /// read with an `identical`-and-window check, so a stale entry cannot
  /// survive a changed [CalendarPageLoaded.allEvents] instance or a moved
  /// window even if some caller forgot to invalidate; [_invalidateDayCache]
  /// additionally drops it outright, piggybacking on the same signal that
  /// already keeps [_dayCache] and [_monthNetCache] honest so a reason to
  /// invalidate one is a reason to invalidate all three.
  _DayCachePartition? _dayCachePartition;

  /// Generation of [PublicHolidays] the memoized days were expanded against.
  ///
  /// `WorkdaysRecurrence` and `PublicHolidaysOnlyRecurrence` consult
  /// `PublicHolidays.isHoliday` from inside `occursOn`, so a profile switch or
  /// a suppression changes which days those events occur on without touching a
  /// single event row — no handler here can see it. Held as one generation
  /// rather than per entry (the shape [_monthNetCache] uses) because a holiday
  /// change invalidates every day at once, and because folding it into the key
  /// instead would grow the cache rather than clear it.
  int _dayCacheHolidayRevision = -1;

  /// Memoizes the header's net money change per month. The scan is O(N) over
  /// the whole event list and the header rebuilds on every day tap, so it
  /// cannot run inline. Keyed by the month's first UTC day and paired with
  /// [NoteMoneyLedgerService.revision]: the ledger's per-note change stream
  /// rewrites entries outside every handler that calls [_invalidateDayCache],
  /// so the event set alone is not enough to keep a cached sum honest.
  final Map<DateTime, ({int revision, int net})> _monthNetCache = {};
  static const int _maxMonthNetEntries = 36;

  CalendarBloc({required FutureOr<CalendarEventService> service})
    : _seed = service,
      super(const CalendarPageInitial()) {
    on<LoadCalendarEvents>(_onLoad);
    on<SelectCalendarDay>(_onSelectDay);
    on<ChangeFocusedDay>(_onChangeFocusedDay);
    on<ChangeCalendarFormat>(_onChangeFormat);
    on<ChangeHiddenCategories>(_onChangeHiddenCategories);
    on<CreateCalendarEvent>(_onCreateEvent);
    on<UpdateCalendarEvent>(_onUpdateEvent);
    on<DeleteCalendarEvent>(_onDeleteEvent);
    on<SetOccurrenceDescription>(_onSetOccurrenceDescription);
    on<ClearOccurrenceDescription>(_onClearOccurrenceDescription);
    on<SetOccurrenceMissed>(_onSetOccurrenceMissed);
    on<ClearOccurrenceMissed>(_onClearOccurrenceMissed);
    on<SetOccurrenceSkipped>(_onSetOccurrenceSkipped);
    on<ClearOccurrenceSkipped>(_onClearOccurrenceSkipped);
  }

  /// Awaits one service's construction, logging rather than rethrowing.
  ///
  /// Lets the seven resolve through a single [Future.wait] without its
  /// fail-fast semantics turning one bad service into an empty calendar.
  static Future<void> _resolveQuietly(
    Future<Object?> init,
    String label,
  ) async {
    try {
      await init;
    } catch (e) {
      debugPrint('[CalendarBloc] $label unavailable: $e');
    }
  }

  /// Whether the constructor's seed has already been consumed.
  ///
  /// Tracked separately from `_service != null` so a seed that **failed** is
  /// never awaited twice: a rejected future stays rejected, so retrying it
  /// would strand the bloc forever — every later create/update/delete silently
  /// no-op, and even a database switch could not recover it.
  bool _seedConsumed = false;

  /// Resolves [CalendarEventService], reporting whether its cache is known to
  /// have just been read from the database.
  ///
  /// `freshlyLoaded` is what lets [_onLoad] skip its `reload()`: building the
  /// service runs `_load()` internally, so reloading on top of that reads
  /// `calendar_events` twice on the pre-first-paint path. Returned per call
  /// rather than held as a field, so a resolution inside a create/update
  /// handler cannot make a later load skip a re-read it genuinely needs.
  ///
  /// Only the **seed** path claims it. `getInstance()` may hand back an
  /// instance somebody else built, whose cache predates writes this bloc
  /// cannot see, so claiming freshness there would trade one redundant read on
  /// a rare path for silently stale events — the worse bargain by far. The
  /// database-switch path therefore still pays for a `reload()`.
  ///
  /// The seed is used for the first resolution only, and only while the store
  /// it came from is still current: [isStale] means a database switch left it
  /// bound to a closed database. After that — and after a seed that threw —
  /// every resolution goes through `getInstance()`, which is self-healing
  /// where a cached GetIt reference would not be.
  Future<({CalendarEventService service, bool freshlyLoaded})>
  _resolveService() async {
    final cached = _service;
    if (cached != null && !isStale) {
      return (service: cached, freshlyLoaded: false);
    }
    if (!_seedConsumed && !isStale) {
      _seedConsumed = true;
      try {
        return (service: _service = await _seed, freshlyLoaded: true);
      } catch (e) {
        debugPrint('[CalendarBloc] Seed resolution failed, retrying: $e');
      }
    }
    _seedConsumed = true;
    return (
      service: _service = await CalendarEventService.getInstance(),
      freshlyLoaded: false,
    );
  }

  Future<CalendarEventService> _svc() async =>
      (await _resolveService()).service;

  /// Amortized O(1) lookup over the in-memory cache populated by
  /// [CalendarEventService]. The first call for a given day validates only
  /// [_dayCandidates]' narrowed list through `occursOnUtcDay` and memoizes
  /// the result in [_dayCache]; later rebuilds reuse it. Stays synchronous so
  /// `TableCalendar.eventLoader` can call it directly during build.
  List<CalendarEvent> eventsForDay(DateTime day) {
    final current = state;
    if (current is! CalendarPageLoaded) return const [];
    _syncHolidayGeneration();
    final key = DateTime.utc(day.year, day.month, day.day);
    final cached = _dayCache[key];
    if (cached != null) return cached;
    // Sorted once, here, on the miss — not by every consumer that reads this
    // memoized list. `DayBarsResolver`/`DaySummaryResolver` used to copy and
    // re-sort by `EventAgenda.compareWithinDay` on every cell/panel build;
    // now that this list is stable for the entry's whole lifetime, they (and
    // every other reader of this method) can trust it arrives pre-sorted.
    final matches = [
      for (final e in _dayCandidates(current, key))
        if (!current.hiddenCategoryIds.contains(e.categoryId) &&
            e.occursOnUtcDay(key))
          e,
    ]..sort(EventAgenda.compareWithinDay);
    final result = List<CalendarEvent>.unmodifiable(matches);
    _dayCache[key] = result;
    return result;
  }

  /// Candidates to validate through `occursOnUtcDay` for [key] — never a
  /// membership decision by itself. `occursOnUtcDay` remains the sole arbiter
  /// for every candidate this returns; nothing here reads `event.rule.occursOn`
  /// or applies the hidden-category filter (that stays in [eventsForDay],
  /// exactly where it always was).
  ///
  /// Inside [_dayCacheWindowFor]'s current window this is
  /// [EventAgenda.partitionForWindow]'s `dense` list plus its [key]-keyed
  /// sparse and one-time buckets — the same events a full scan would have
  /// reached, minus the ones whose rule provably cannot fire on [key]
  /// ([RecurrenceRule.candidateDaysIn]) and the one-time events whose single
  /// occurrence falls on some other day. Outside the window (a date picker,
  /// the day or timeline panel, a birthday decades away) this is the full
  /// [CalendarPageLoaded.allEvents] scan [eventsForDay] always ran, because
  /// the partition was never built to cover that day.
  List<CalendarEvent> _dayCandidates(CalendarPageLoaded current, DateTime key) {
    final (start, endExclusive) = _dayCacheWindowFor(current.focusedDay);
    if (key.isBefore(start) || !key.isBefore(endExclusive)) {
      return current.allEvents;
    }
    final partition = _partitionFor(current, start, endExclusive);
    final sparseToday = partition.sparseByDay[key];
    final oneTimeToday = partition.oneTimeByDay[key];
    if (sparseToday == null && oneTimeToday == null) return partition.dense;
    return [...partition.dense, ...?sparseToday, ...?oneTimeToday];
  }

  /// Builds, or reuses, the [EventAgenda.partitionForWindow] split for the
  /// `[windowStart, windowEndExclusive)` window.
  ///
  /// Reuse requires both the window bounds and the
  /// [CalendarPageLoaded.allEvents] instance to match [_dayCachePartition]
  /// exactly; either differing means the cached split no longer describes
  /// the calendar this bloc would compute today, so it is rebuilt rather than
  /// patched. [partitionForWindow] takes an **inclusive** end, so the window's
  /// exclusive bound is converted once here.
  _DayCachePartition _partitionFor(
    CalendarPageLoaded current,
    DateTime windowStart,
    DateTime windowEndExclusive,
  ) {
    final existing = _dayCachePartition;
    if (existing != null &&
        identical(existing.allEvents, current.allEvents) &&
        existing.windowStart == windowStart &&
        existing.windowEndExclusive == windowEndExclusive) {
      return existing;
    }
    final split = EventAgenda.partitionForWindow(
      current.allEvents,
      windowStart,
      windowEndExclusive.subtract(const Duration(days: 1)),
    );
    final built = (
      allEvents: current.allEvents,
      windowStart: windowStart,
      windowEndExclusive: windowEndExclusive,
      dense: split.dense,
      sparseByDay: split.sparseByDay,
      oneTimeByDay: split.oneTimeByDay,
    );
    _dayCachePartition = built;
    return built;
  }

  /// Net money change for [month]: the exact sum of what the visible day
  /// cells display. Mirrors the day bar/summary providers on both axes the
  /// two surfaces could diverge on: hidden categories are excluded (cells
  /// only ever see category-filtered events), and dedupe is per (start day,
  /// note) — a note linked from events on two different days shows on both
  /// cells, so it counts twice here too, while a recurring event still never
  /// multiplies its note.
  ///
  /// Memoized in [_monthNetCache]; safe to call from `headerTitleBuilder`.
  int monthNetFor(DateTime month) {
    final current = state;
    if (current is! CalendarPageLoaded) return 0;
    final ledger = NoteMoneyLedgerService.instanceOrNull;
    if (ledger == null) return 0;
    _syncHolidayGeneration();
    final key = DateTime.utc(month.year, month.month, 1);
    final revision = ledger.revision;
    final cached = _monthNetCache[key];
    if (cached != null && cached.revision == revision) return cached.net;

    var sum = 0;
    Set<String>? seen;
    for (final event in current.allEvents) {
      final noteId = event.noteId;
      if (noteId == null) continue;
      if (current.hiddenCategoryIds.contains(event.categoryId)) continue;
      final startUtc = DateTime.fromMillisecondsSinceEpoch(
        event.startDate.millisecondsSinceEpoch,
        isUtc: true,
      );
      if (startUtc.year != month.year || startUtc.month != month.month) {
        continue;
      }
      // Cells attribute money on the start day only when the event actually
      // occurs there; a rule that skips its own anchor (weekly with the
      // anchor's weekday deselected) shows on no cell, so it must not count.
      if (!event.occursOnUtcDay(
        DateTime.utc(startUtc.year, startUtc.month, startUtc.day),
      )) {
        continue;
      }
      seen ??= <String>{};
      if (!seen.add('${startUtc.day}:$noteId')) continue;
      final entry = ledger.ledgerFor(noteId);
      if (entry == null) continue;
      sum += entry.net;
    }

    if (_monthNetCache.length >= _maxMonthNetEntries) _monthNetCache.clear();
    _monthNetCache[key] = (revision: revision, net: sum);
    return sum;
  }

  /// Drops both memos when the holiday set has been republished since they
  /// were built. Called from the two read paths rather than from a handler
  /// because nothing dispatches on a holiday change — `PublicHolidayService`
  /// publishes straight into the static facade, and backup restore and a
  /// database switch reach it with no event in between.
  void _syncHolidayGeneration() {
    final revision = PublicHolidays.revision;
    if (_dayCacheHolidayRevision == revision) return;
    _dayCacheHolidayRevision = revision;
    _invalidateDayCache();
  }

  /// Drops every memoized day so the next [eventsForDay] recomputes against
  /// the current event set / category filter. Called from the handlers that
  /// actually change those inputs — never from day/focus/format changes.
  ///
  /// Also drops [_dayCachePartition]. Most of these call sites do not
  /// actually change the partition's own inputs (a skip, a holiday-generation
  /// bump and the hidden-category filter all leave `allEvents` and the
  /// window untouched — [_partitionFor]'s per-call `occursOnUtcDay`
  /// validation is what makes those correct regardless), but dropping it
  /// here anyway means every existing and future reason to invalidate the day
  /// cache reaches the partition for free, with nothing new to keep in sync.
  void _invalidateDayCache() {
    if (_dayCache.isNotEmpty) _dayCache.clear();
    if (_monthNetCache.isNotEmpty) _monthNetCache.clear();
    _dayCachePartition = null;
  }

  /// Start (inclusive) and end (exclusive) of the months [_dayCache] keeps
  /// warm around [focusedDay]'s month: [_dayCacheWindowMonths] before and
  /// after. Deliberately not extended to [_monthNetCache]: that cache is
  /// keyed by month and already capped at 36 entries — six times this
  /// window's width — and `headerTitleBuilder` reads it exactly once per
  /// build, so the double-lookup-in-one-frame race this method exists to
  /// close cannot happen there. Pruning it to this window on every page turn
  /// would trade a cache that already survives a multi-year paging session
  /// for one that forgets everything past three months, with no matching bug
  /// to justify it.
  static (DateTime start, DateTime endExclusive) _dayCacheWindowFor(
    DateTime focusedDay,
  ) {
    final start = DateTime.utc(
      focusedDay.year,
      focusedDay.month - _dayCacheWindowMonths,
    );
    final endExclusive = DateTime.utc(
      focusedDay.year,
      focusedDay.month + _dayCacheWindowMonths + 1,
    );
    return (start, endExclusive);
  }

  /// Evicts [_dayCache] entries outside [_dayCacheWindowFor] — eviction, not
  /// invalidation: the entries kept are still correct, just unlikely to be
  /// read again soon, whereas [_invalidateDayCache] drops everything because
  /// the event set itself changed. Called only from [_onChangeFocusedDay],
  /// after its no-op guard, so a genuine month change pays for this and the
  /// page-settle re-report of the same month does not.
  ///
  /// [_maxDayCacheEntries] stays a backstop rather than disappearing: the
  /// date pickers and the day/timeline panels also call [eventsForDay], on
  /// days that can land far outside the window with no focus change at all.
  /// The window prune runs first; the wholesale clear only fires if the
  /// cache is still over the cap afterwards, and — like the prune — only
  /// from here, never from the lookup.
  void _evictColdDayCacheEntries(DateTime focusedDay) {
    final (start, endExclusive) = _dayCacheWindowFor(focusedDay);
    _dayCache.removeWhere(
      (day, _) => day.isBefore(start) || !day.isBefore(endExclusive),
    );
    if (_dayCache.length >= _maxDayCacheEntries) _dayCache.clear();
  }

  /// Resolves every calendar service, then publishes the event set.
  ///
  /// This is where the calendar's first load lives now that the services are
  /// no longer constructed before `runApp`. Two properties it must keep:
  ///
  /// The seven `getInstance()` calls run through one [Future.wait] rather than
  /// sequentially — each is a separate round trip to the Drift isolate, so
  /// awaiting them in order makes the latencies add rather than overlap. That
  /// was the roadmap's complaint about the old DI block, and it applies just
  /// as much here.
  ///
  /// And no [CalendarPageLoaded] is ever emitted before all of them resolve.
  /// The static facades those services publish into are read synchronously
  /// from render paths and from `occursOn`, and an unconfigured read is silent
  /// — a skipped occurrence reappears, every category goes grey, and
  /// `PublicHolidays` falls back to fixed dates, which changes *which days a
  /// `Workdays` event occurs on*. Until then the page shows its spinner.
  Future<void> _onLoad(
    LoadCalendarEvents event,
    Emitter<CalendarPageState> emit,
  ) async {
    final today = _dateOnly(DateTime.now());
    CalendarEventService? service;
    final resolving = _resolveService();
    // Resolved in parallel but independently. `Future.wait` fails fast, so a
    // single bad service would otherwise reject the whole batch and blank the
    // calendar; each of these already degrades to an empty published cache on
    // its own, which is a far smaller lie than showing no events at all.
    await Future.wait<void>([
      _resolveQuietly(resolving, 'events'),
      _resolveQuietly(PublicHolidayService.getInstance(), 'holidays'),
      _resolveQuietly(CategoryService.getInstance(), 'categories'),
      _resolveQuietly(EventOccurrenceService.getInstance(), 'descriptions'),
      _resolveQuietly(EventPresenceService.getInstance(), 'presence'),
      _resolveQuietly(EventSkipService.getInstance(), 'skips'),
      _resolveQuietly(EventTemplateService.getInstance(), 'templates'),
    ]);
    try {
      final resolved = await resolving;
      service = resolved.service;
      // Constructing the service loaded the table already — on the first load
      // and again after a database switch. Reloading on top of that would read
      // `calendar_events` twice on the pre-first-paint path.
      if (!resolved.freshlyLoaded) await service.reload();
    } catch (e) {
      debugPrint('[CalendarBloc] Load error: $e');
    }
    _seenExternalRevision = CalendarEventService.externalRevision;
    _invalidateDayCache();
    final events = service?.events ?? const <CalendarEvent>[];
    try {
      await (await NoteMoneyLedgerService.getInstance()).refresh(events);
    } catch (e) {
      debugPrint('[CalendarBloc] Money ledger refresh error: $e');
    }
    emit(
      CalendarPageLoaded(
        allEvents: List.unmodifiable(events),
        focusedDay: today,
        selectedDay: today,
      ),
    );
  }

  void _onSelectDay(SelectCalendarDay event, Emitter<CalendarPageState> emit) {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    emit(
      current.copyWith(
        selectedDay: _dateOnly(event.day),
        focusedDay: _dateOnly(event.focusedDay),
        selectionSource: event.source,
      ),
    );
  }

  void _onChangeFocusedDay(
    ChangeFocusedDay event,
    Emitter<CalendarPageState> emit,
  ) {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final focused = _dateOnly(event.focusedDay);
    // Mirrors `_onChangeFormat`'s no-op guard. A `SelectCalendarDay` already
    // moved `focusedDay`; the page settle that follows re-reports the same
    // month, and without this that second, equal-but-for-nothing emit rebuilds
    // the grid again (the panel is protected separately by `samePanelInputs`).
    if (focused == current.focusedDay) return;
    // Past the guard, this is a genuine month change — the only point that
    // pays for day-cache eviction.
    _evictColdDayCacheEntries(focused);
    emit(current.copyWith(focusedDay: focused));
  }

  void _onChangeFormat(
    ChangeCalendarFormat event,
    Emitter<CalendarPageState> emit,
  ) {
    final current = state;
    if (current is! CalendarPageLoaded || current.format == event.format) {
      return;
    }
    emit(current.copyWith(format: event.format));
  }

  void _onChangeHiddenCategories(
    ChangeHiddenCategories event,
    Emitter<CalendarPageState> emit,
  ) {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final next = Set<String>.unmodifiable(event.hiddenCategoryIds);
    if (next.length == current.hiddenCategoryIds.length &&
        next.containsAll(current.hiddenCategoryIds)) {
      return;
    }
    _invalidateDayCache();
    emit(current.copyWith(hiddenCategoryIds: next));
  }

  Future<void> _onCreateEvent(
    CreateCalendarEvent event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final normalized = event.event.copyWith(
      startDate: _dateOnly(event.event.startDate),
    );
    final CalendarEventService service;
    try {
      service = await _svc();
      await service.upsert(normalized);
    } catch (e) {
      debugPrint('[CalendarBloc] Create error: $e');
      return;
    }
    _invalidateDayCache();
    try {
      await (await NoteMoneyLedgerService.getInstance()).refresh(
        service.events,
      );
    } catch (e) {
      debugPrint('[CalendarBloc] Money ledger refresh error: $e');
    }
    emit(
      current.copyWith(
        allEvents: List.unmodifiable(service.events),
        selectedDay: normalized.startDate,
        focusedDay: normalized.startDate,
      ),
    );
  }

  Future<void> _onUpdateEvent(
    UpdateCalendarEvent event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final normalized = event.event.copyWith(
      startDate: _dateOnly(event.event.startDate),
    );
    final CalendarEventService service;
    try {
      service = await _svc();
      await service.upsert(normalized);
    } catch (e) {
      debugPrint('[CalendarBloc] Update error: $e');
      return;
    }
    _invalidateDayCache();
    try {
      await (await NoteMoneyLedgerService.getInstance()).refresh(
        service.events,
      );
    } catch (e) {
      debugPrint('[CalendarBloc] Money ledger refresh error: $e');
    }
    emit(current.copyWith(allEvents: List.unmodifiable(service.events)));
  }

  Future<void> _onDeleteEvent(
    DeleteCalendarEvent event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final hasEvent = current.allEvents.any((e) => e.id == event.eventId);
    if (!hasEvent) return;
    final CalendarEventService service;
    try {
      service = await _svc();
      await service.deleteById(event.eventId);
    } catch (e) {
      debugPrint('[CalendarBloc] Delete error: $e');
      return;
    }
    _invalidateDayCache();
    emit(current.copyWith(allEvents: List.unmodifiable(service.events)));
  }

  /// Writes one occurrence's description override.
  ///
  /// Deliberately does **not** invalidate the day cache: that cache answers
  /// "which events occur on this day", and description text is not one of its
  /// inputs. Ticking a checkbox therefore no longer wipes 512 memoized days,
  /// which is what the whole-event update path used to do. It also skips the
  /// money-ledger refresh — descriptions never feed the ledger.
  ///
  /// Bumping `occurrenceRevision` is what makes the emit survive: the state is
  /// `Equatable`, so an otherwise-identical copy would be dropped, and the
  /// agenda's identity-based row memo would keep serving stale text.
  Future<void> _onSetOccurrenceDescription(
    SetOccurrenceDescription event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventOccurrenceService.getInstance();
      await service.setDescription(event.eventId, event.day, event.description);
    } catch (e) {
      debugPrint('[CalendarBloc] Occurrence write error: $e');
      return;
    }
    emit(current.copyWith(occurrenceRevision: current.occurrenceRevision + 1));
  }

  /// Deletes one occurrence's override, returning that day to the event's
  /// template. Same cache reasoning as [_onSetOccurrenceDescription].
  Future<void> _onClearOccurrenceDescription(
    ClearOccurrenceDescription event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventOccurrenceService.getInstance();
      await service.clearDescription(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Occurrence clear error: $e');
      return;
    }
    emit(current.copyWith(occurrenceRevision: current.occurrenceRevision + 1));
  }

  /// Marks one occurrence missed.
  ///
  /// Same cache reasoning as [_onSetOccurrenceDescription], and for a stronger
  /// reason: presence is a **rendering** concern, never a membership one. A
  /// missed day still occurs, so "which events occur on this day" is unchanged
  /// and invalidating would wipe 512 memoized days for nothing. Hiding missed
  /// occurrences is a render-time filter — the moment a presence check lands in
  /// [eventsForDay], `EventAgenda` or `.ics`, those surfaces start disagreeing
  /// about what exists.
  Future<void> _onSetOccurrenceMissed(
    SetOccurrenceMissed event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventPresenceService.getInstance();
      await service.markMissed(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Presence write error: $e');
      return;
    }
    emit(
      current.copyWith(
        occurrenceRevision: current.occurrenceRevision + 1,
        presenceRevision: current.presenceRevision + 1,
      ),
    );
  }

  /// Returns one occurrence to present. Same cache reasoning as
  /// [_onSetOccurrenceMissed].
  Future<void> _onClearOccurrenceMissed(
    ClearOccurrenceMissed event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventPresenceService.getInstance();
      await service.unmark(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Presence clear error: $e');
      return;
    }
    emit(
      current.copyWith(
        occurrenceRevision: current.occurrenceRevision + 1,
        presenceRevision: current.presenceRevision + 1,
      ),
    );
  }

  /// Cancels one occurrence.
  ///
  /// The **inverse** of [_onSetOccurrenceMissed] on the one axis that matters:
  /// a skip changes membership, so it *must* invalidate the day cache. Leaving
  /// it warm would keep serving an occurrence `occursOn` now denies, and the
  /// two would disagree for up to 512 memoized days.
  ///
  /// It bumps [CalendarPageLoaded.membershipRevision] rather than
  /// `occurrenceRevision`, because the agenda has to rescan rather than
  /// repaint — see the field's own note.
  Future<void> _onSetOccurrenceSkipped(
    SetOccurrenceSkipped event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventSkipService.getInstance();
      await service.markSkipped(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Skip write error: $e');
      return;
    }
    _invalidateDayCache();
    emit(current.copyWith(membershipRevision: current.membershipRevision + 1));
  }

  /// Restores one cancelled occurrence. Same cache reasoning as
  /// [_onSetOccurrenceSkipped], in the other direction: the occurrence comes
  /// back, so the memoized days that omit it are just as wrong.
  Future<void> _onClearOccurrenceSkipped(
    ClearOccurrenceSkipped event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventSkipService.getInstance();
      await service.unskip(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Skip clear error: $e');
      return;
    }
    _invalidateDayCache();
    emit(current.copyWith(membershipRevision: current.membershipRevision + 1));
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }
}
