import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/calendar_cache_limits.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_presence.dart';
import '../constants/json_keys.dart';
import '../constants/occurrence_descriptions.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/calendar_event_dao.dart';
import '../database/daos/shared_row_dao.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';
import '../models/recurrence_rule_codec.dart';
import 'alert_scheduler.dart';
import 'event_alert_service.dart';
import 'event_occurrence_service.dart';
import 'event_presence_service.dart';
import 'event_skip_service.dart';
import 'sync/sync_binding_service.dart';

/// One [CalendarEventService.notifyExternalChange]: the
/// [CalendarEventService.externalRevision] it moved to, so a listener can
/// tell whether it saw every change before it, and whether the service's
/// cache already holds it, and whether event rows themselves came in.
typedef CalendarExternalChange = ({
  int revision,
  bool cacheCurrent,
  bool eventsMerged,
});

/// Persists custom calendar events via Drift and exposes a synchronous
/// in-memory cache so `CalendarBloc.eventsForDay` stays O(N) over a
/// pre-loaded list without async hops in the table-calendar event loader.
class CalendarEventService {
  static CalendarEventService? _instance;

  late AppDatabase _db;
  late CalendarEventDao _dao;
  List<CalendarEvent> _cache = const [];

  CalendarEventService._();

  static Future<CalendarEventService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(AppDatabase.getInstance);
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO against
  /// `NativeDatabase.memory()` — including through a `QueryInterceptor`, which
  /// is the only way to assert how many times the event table is read. Never
  /// use it in app code: the singleton is what the [DatabaseLifecycle] reset
  /// contract is built on.
  @visibleForTesting
  static Future<CalendarEventService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(() async => db);
  }

  /// The construction [_create] has in flight, so concurrent callers share
  /// one load and a refresh can reach an instance still reading the table.
  static Future<CalendarEventService>? _creating;

  /// Bumped by every [reset], so a construction can tell it was overtaken by
  /// one that no `DatabaseLifecycle` switch announced — a restore's.
  static int _generation = 0;

  /// One construction at a time, and never one a database switch overtook —
  /// `CategoryProfileService`'s guard. A construction still reading when
  /// [reset] ran read the closing database, and publishing it would hand the
  /// bloc that database's events as the new one's; it discards itself and
  /// hands its caller the instance the new database installs.
  ///
  /// [_creating] is set before the body runs, so the body's own `finally`
  /// always has its future to compare — even when [open] throws before the
  /// first await.
  static Future<CalendarEventService> _create(
    Future<AppDatabase> Function() open,
  ) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _creating;
    if (pending != null) return pending;
    final completer = Completer<CalendarEventService>();
    final creating = _creating = completer.future;
    completer.complete(_construct(open, creating));
    return creating;
  }

  static Future<CalendarEventService> _construct(
    Future<AppDatabase> Function() open,
    Future<CalendarEventService> creating,
  ) async {
    final generation = _generation;
    final lifecycle = DatabaseLifecycle.generation;
    // A reset nulls [_creating], so a construction that no longer holds it
    // was overtaken even where no generation moved.
    bool overtaken() =>
        generation != _generation ||
        lifecycle != DatabaseLifecycle.generation ||
        !identical(_creating, creating);

    Future<CalendarEventService> restart() {
      if (identical(_creating, creating)) _creating = null;
      return _create(open);
    }

    try {
      final db = await open();
      if (overtaken()) return await restart();
      final service = CalendarEventService._();
      service._db = db;
      service._dao = db.calendarEventDao;
      await service._load();
      if (overtaken()) return await restart();
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    } finally {
      if (identical(_creating, creating)) _creating = null;
    }
  }

  /// Counts wholesale replacements of the event store that no dispatch can
  /// observe — a backup restore and a database switch.
  ///
  /// `CalendarBloc` lives above `MaterialApp` and is never disposed, so after
  /// either of those its `allEvents` and day cache describe a store that no
  /// longer exists. Neither path can dispatch into a bloc without inverting
  /// the layering rule, so they publish a generation instead and the page
  /// re-dispatches when it next appears — the same shape
  /// `PublicHolidays.revision` uses for holidays.
  ///
  /// Deliberately **not** bumped by [upsert], [deleteById], [tombstoneAll] or
  /// [reload]: a bloc that drove one of those has already emitted. A caller
  /// that did *not* come through a bloc owns the bump itself —
  /// `CalendarSettingsPage`'s "Delete all events" is the one such caller, and
  /// without its [notifyExternalChange] a loaded bloc kept serving the wiped
  /// events and saving one resurrected it. Static so it survives [reset]
  /// nulling the instance.
  static int externalRevision = 0;

  static final StreamController<CalendarExternalChange> _externalChanges =
      StreamController<CalendarExternalChange>.broadcast();

  /// Fires when the store changed behind every bloc's back — a restore, or
  /// rows a pull merged — so a bloc already showing the calendar reloads at
  /// once instead of waiting for the page to reappear. [reset] does not fire
  /// it: a switched database is picked up through [externalRevision].
  static Stream<CalendarExternalChange> get externalChanges =>
      _externalChanges.stream;

  /// Bumps [externalRevision] and tells [externalChanges]'s listeners.
  ///
  /// [cacheCurrent] says the caller already brought this service's cache up
  /// to date — the sync hooks after their own events step succeeded, the
  /// category delete after [refreshAfterCategoryRemoval] — so a bloc may
  /// rebuild from [events] instead of reading the store a second time. Left
  /// off, every listener re-reads: a restore and "Delete all events" change
  /// the store wholesale, and nothing here vouches for the cache.
  ///
  /// [eventsMerged] says rows of `calendar_events` itself came in, so an
  /// event may now link a note it did not: a bloc trusting the cache still
  /// refreshes the money ledger over it. A full re-read always does.
  static void notifyExternalChange({
    bool cacheCurrent = false,
    bool eventsMerged = false,
  }) {
    externalRevision++;
    _externalChanges.add((
      revision: externalRevision,
      cacheCurrent: cacheCurrent,
      eventsMerged: eventsMerged,
    ));
  }

  /// Re-reads a loaded cache after `CategoryService.deleteCategory`'s cascade
  /// rewrote `calendar_events.category` in SQL behind it
  /// ([EventAlertService.refreshAfterCategoryRemoval]'s pair).
  ///
  /// Without it every event of the deleted category keeps the dead id in
  /// memory, and the next save of one — the editor seeds its draft from the
  /// cached event and writes the id back verbatim — undoes the reassignment
  /// on a synced column, while the agenda's allowlist drops those events
  /// until then even with Other ticked.
  ///
  /// Only a live or half-built instance is refreshed, never constructed: with
  /// neither there is no cache to be stale, and a service must not open the
  /// database from inside another service's write chain.
  ///
  /// True when the cache is current afterwards — reloaded, or absent — which
  /// is what lets the caller announce the change with `cacheCurrent`.
  static Future<bool> refreshAfterCategoryRemoval() => _reloadLive();

  /// Re-reads a loaded cache after a pull merged event rows behind it, on
  /// [refreshAfterCategoryRemoval]'s terms: the next [getInstance] reads the
  /// merged table, so constructing one here would load the whole store for a
  /// calendar nobody opened. The sync hooks' fallback when they do not know
  /// which rows merged; [applyMerged] when they do.
  static Future<bool> refreshAfterSync() => _reloadLive();

  /// Patches the events a pull merged into a loaded cache by id: one keyed
  /// read of [ids] instead of the whole store, on [refreshAfterSync]'s terms.
  ///
  /// A cached event whose start day held is replaced where it stands; one
  /// that moved, and one new here, is merged in by start in one sorted pass;
  /// a tombstone leaves. [getAll]'s order is the start date alone, so events
  /// sharing a start may sit in another order than a reload would give them
  /// — the one difference from a reload, and one no reader depends on.
  ///
  /// Falls back to the whole read when the patch cannot be trusted: more
  /// than [CalendarCacheLimits.maxKeyedPatchIds] ids, a read or a row that
  /// fails, or a load that started or landed while the rows were in flight.
  /// True when the cache is current afterwards.
  ///
  /// [getAll]: CalendarEventDao.getAll
  static Future<bool> applyMerged(Set<String> ids) async {
    final service = await _liveOrCreating();
    if (service == null) return true;
    return service._applyMerged(ids);
  }

  /// Reloads the live instance, or the one [_create] is still reading: that
  /// read may have begun before the rows behind it changed, and the instance
  /// it publishes is the one the bloc seeds from without a reload.
  static Future<bool> _reloadLive() async {
    final service = await _liveOrCreating();
    return service == null || await service._load();
  }

  /// The live instance, or the one [_create] is still reading; never a new
  /// one, and never one a [reset] retired while it was awaited — reading
  /// through that one would read a closing database into a cache nobody
  /// serves.
  static Future<CalendarEventService?> _liveOrCreating() async {
    final service = _instance;
    final pending = _creating;
    if (service != null || pending == null) return service;
    try {
      final built = await pending;
      return identical(_instance, built) ? built : null;
    } catch (_) {
      // The construction's failure is its own caller's to report; with no
      // instance there is nothing to refresh.
      return null;
    }
  }

  /// Whether an instance is live — the seam that proves a refresh above
  /// never constructs one.
  @visibleForTesting
  static bool get isLive => _instance != null;

  static void reset() {
    _generation++;
    _instance = null;
    _creating = null;
    externalRevision++;
  }

  List<CalendarEvent> get events => _cache;

  /// How many live events sit in each category, keyed by category id.
  /// Categories with none are absent rather than zero.
  ///
  /// **One statement for the whole page**, never a count per row — the
  /// category management page renders forty of them, and
  /// `test/database/query_count_test.dart` guards the shape. Advisory data:
  /// read once per page entry and after a delete, never held as live state,
  /// so it does not ride the cache or bump any revision.
  Future<Map<String, int>> countByCategory() async {
    try {
      return await _dao.countByCategory();
    } catch (e) {
      debugPrint('[CalendarEventService] Count error: $e');
      return const {};
    }
  }

  /// Bumped by each single-event write once it has committed, so [_load] can
  /// tell that the rows it is holding predate one.
  int _writes = 0;

  /// Re-reads the whole store; false when the read failed and the cache
  /// kept what it held.
  Future<bool> reload() => _load();

  /// Whether the last whole read failed, so the cache may predate the store.
  ///
  /// A bloc told the cache is current trusts it only while this is false;
  /// otherwise it pays for the read itself, which is what an announcement
  /// without the flag would have cost anyway.
  bool get lastLoadFailed => _lastLoadFailed;
  bool _lastLoadFailed = false;

  /// Whole reads started, so [_applyMerged] can tell one began under its
  /// keyed read; [_loadsInFlight] says whether one is still running.
  int _loadsStarted = 0;
  int _loadsInFlight = 0;

  /// Re-reads the whole store into [_cache], twice at most.
  ///
  /// A write that commits while the rows are in flight is not in them, and
  /// replacing the cache with them reads the user's own save back out of it —
  /// `AlertScheduler.reconcileAll` plans from this very list, so a just-saved
  /// event could be planned out of the pass that saving it provoked. The
  /// second read is issued after that write, so it holds it; a write racing
  /// the second read is left to the next reload.
  ///
  /// A failed read keeps the cache as it was and returns false. It used to
  /// publish an empty store, which a caller could not tell from a calendar
  /// with no events — and a bloc trusting the cache would have drawn it.
  Future<bool> _load() async {
    _loadsStarted++;
    _loadsInFlight++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final writes = _writes;
        try {
          final rows = await _dao.getAll();
          final partner = await _partnerOf(rows);
          _cache = List.unmodifiable(
            rows.map((row) => _rowToEvent(row, partner)),
          );
          _lastLoadFailed = false;
        } catch (e, st) {
          debugPrint('[CalendarEventService] Load error: $e\n$st');
          _lastLoadFailed = true;
          return false;
        }
        if (_writes == writes) break;
      }
      return true;
    } finally {
      _loadsInFlight--;
    }
  }

  /// The partner's account when one of [rows] names an owner, else null
  /// without a statement: a database that was never bound holds no owned
  /// row, and must pay nothing for sharing on every load and patch.
  Future<String?> _partnerOf(List<CalendarEventRow> rows) async {
    if (!rows.any((row) => row.ownerId != null)) return null;
    return _db.sharedRowDao.owner();
  }

  Future<bool> _applyMerged(Set<String> ids) async {
    if (ids.isEmpty) return !_lastLoadFailed;
    if (ids.length > CalendarCacheLimits.maxKeyedPatchIds ||
        _loadsInFlight > 0 ||
        _lastLoadFailed) {
      return _load();
    }
    final cache = _cache;
    final loads = _loadsStarted;
    final Map<String, CalendarEvent?> merged;
    try {
      final rows = await _dao.getByIdsIncludingDeleted(ids.toList());
      final partner = await _partnerOf(rows);
      merged = {
        for (final row in rows)
          row.id: row.isDeleted ? null : _rowToEvent(row, partner),
      };
    } catch (e, st) {
      debugPrint('[CalendarEventService] Merged rows error: $e\n$st');
      return _load();
    }
    if (!identical(cache, _cache) || loads != _loadsStarted) return _load();
    _cache = List.unmodifiable(_patched(cache, ids, merged));
    return true;
  }

  /// [cache] with the events under [ids] as [merged] holds them: replaced in
  /// place while their start holds, merged in by start otherwise, dropped
  /// when [merged] has no live row for them.
  static List<CalendarEvent> _patched(
    List<CalendarEvent> cache,
    Set<String> ids,
    Map<String, CalendarEvent?> merged,
  ) {
    final kept = <CalendarEvent>[];
    final placed = <String>{};
    for (final event in cache) {
      if (!ids.contains(event.id)) {
        kept.add(event);
        continue;
      }
      final fresh = merged[event.id];
      if (fresh != null && fresh.startDate == event.startDate) {
        kept.add(fresh);
        placed.add(event.id);
      }
    }
    final moved = [
      for (final MapEntry(key: id, value: fresh) in merged.entries)
        if (fresh != null && !placed.contains(id)) fresh,
    ]..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (moved.isEmpty) return kept;
    // One merge of two sorted runs; a moved event goes after the ones it
    // ties with, as [_insertByStart] places a saved one.
    final next = <CalendarEvent>[];
    var i = 0;
    for (final event in moved) {
      while (i < kept.length && !kept[i].startDate.isAfter(event.startDate)) {
        next.add(kept[i++]);
      }
      next.add(event);
    }
    while (i < kept.length) {
      next.add(kept[i++]);
    }
    return next;
  }

  /// Inserts [event] where the store's start-date order puts it, after the
  /// events it ties with.
  ///
  /// [CalendarEventDao.getAll] documents that order as the store's contract
  /// ("live events, in start-date order ... the single read path for the whole
  /// feature") and the cache is what every reader sees between two loads, so
  /// appending would have made the contract hold only until the next reload.
  static void _insertByStart(List<CalendarEvent> events, CalendarEvent event) {
    var index = events.length;
    for (var i = 0; i < events.length; i++) {
      if (events[i].startDate.isAfter(event.startDate)) {
        index = i;
        break;
      }
    }
    events.insert(index, event);
  }

  /// Saves [event] and caches it as stored.
  ///
  /// A model without `createdAt` (a new event's draft), or one whose id the
  /// cache did not hold, takes the row's back after the write: the insert
  /// stamps `created_at`, at the column's whole-second precision, and an
  /// existing row keeps its own, so neither the model's `null`, the date a
  /// `copyWith(id:)` carried over from another event, nor this call's clock
  /// would match what a reload reads.
  ///
  /// Throws `SharedRowException` for an event put into a category another
  /// account shares with this one ([CalendarEventDao.upsert]), with nothing
  /// written and the cache as it was.
  Future<void> upsert(CalendarEvent event) async {
    _ensureOwn(event.id, fromPartner: event.fromPartner);
    var normalized = _normalized(event);
    final cached = _cache.any((e) => e.id == normalized.id);
    final now = DateTime.now();
    await _dao.upsert(_eventToCompanion(normalized, updatedAt: now));
    if (normalized.createdAt == null || !cached) {
      final rows = await _dao.getByIdsIncludingDeleted([normalized.id]);
      normalized = normalized.copyWith(createdAt: rows.single.createdAt);
    }
    _writes++;
    _cacheWritten(normalized);
  }

  /// Throws [SharedRowException] for an event a partner shares — [id] as
  /// the cache holds it, or a model that says so — before anything is
  /// written or cached.
  ///
  /// The database fences already turn such a write into nothing, but this
  /// layer would still cache the edit, drop a deleted event, forget its
  /// children and hard-delete its registrations — a calendar showing a
  /// change that the next load takes back, and a caller with no way to tell
  /// it from a save. Read from the cache, so a database that never read a
  /// shared row pays no statement for it.
  void _ensureOwn(String id, {bool fromPartner = false}) {
    if (fromPartner || _cache.any((e) => e.id == id && e.fromPartner)) {
      throw SharedRowException('calendar_events', id);
    }
  }

  /// Both date bounds as date-only UTC, so equality and ordering are
  /// calendar-day stable across timezones.
  static CalendarEvent _normalized(CalendarEvent event) {
    final normalizedEnd = event.endDate == null
        ? event
        : event.copyWith(endDate: _dateOnlyUtc(event.endDate!));
    return normalizedEnd.copyWith(
      startDate: _dateOnlyUtc(event.startDate),
      assumeAbsentFrom: event.assumeAbsentFrom == null
          ? null
          : _dateOnlyUtc(event.assumeAbsentFrom!),
    );
  }

  void _cacheWritten(CalendarEvent normalized) {
    final next = [
      for (final e in _cache)
        if (e.id != normalized.id) e,
    ];
    _insertByStart(next, normalized);
    _cache = List.unmodifiable(next);
  }

  /// Everything [deleteById]'s cascade is about to tombstone for [id]: the
  /// capture A3 takes before the delete, so its Undo has the four child row
  /// sets to hand to [restoreCascade].
  ///
  /// Read from the four tables rather than from their facades, which is the
  /// cheaper read but the wrong one here: A3 runs from an alarm page over a
  /// calendar that was never built, or in a process the alarm itself launched,
  /// and on that path nobody has published them — the scheduler's warm-up does
  /// not load presence at all, and the only other publisher is
  /// `CalendarBloc`'s load. A facade read answered `{}` and every attendance
  /// mark stayed tombstoned, here and — through its own HLC — on every paired
  /// device. A table read is the one capture whose answer does not depend on
  /// who happened to load first.
  ///
  /// **Live rows only**, as the facades held: a tombstone older than the
  /// delete is a day the user had already cleared, reset or un-skipped, and
  /// [restoreCascade] must not resurrect it. **That event's rows only**, one
  /// keyed read per table: the capture used to read all four tables whole
  /// and keep one event's rows.
  Future<
    ({
      List<EventAlert> alerts,
      Map<DateTime, PresenceStatus> marks,
      Map<DateTime, String> descriptions,
      Set<DateTime> skips,
    })
  >
  captureCascade(String id) async {
    final alerts = await _db.eventAlertDao.getActiveForEvent(id);
    final marks = await _db.eventAbsenceDao.getActiveForEvent(id);
    final descriptions = await _db.eventOccurrenceDao.getActiveForEvent(id);
    final skips = await _db.eventSkipDao.getActiveForEvent(id);
    return (
      alerts: [for (final row in alerts) EventAlertService.alertFrom(row)],
      marks: {
        for (final row in marks)
          _dateOnlyUtc(row.day): PresenceStatus.fromName(row.status),
      },
      descriptions: {
        for (final row in descriptions) _dateOnlyUtc(row.day): row.description,
      },
      skips: {for (final row in skips) _dateOnlyUtc(row.day)},
    );
  }

  /// Puts back the event an acknowledged alarm deleted, with everything the
  /// cascade took with it (**A3**'s Undo): [deleteById]'s inverse, one HLC for
  /// the five tables, and the four child sets handed in rather than re-read —
  /// the delete tombstoned them, so there is nothing live left here to read.
  ///
  /// Without the three sets beside [alerts] the Undo restored an event that
  /// had lost its attendance marks, its per-day descriptions and its cancelled
  /// days for good, here and on every paired device.
  Future<void> restoreCascade(
    CalendarEvent event, {
    required Map<DateTime, PresenceStatus> marks,
    required Map<DateTime, String> descriptions,
    required Set<DateTime> skips,
    required List<EventAlert> alerts,
  }) async {
    assert(
      alerts.every((alert) => alert.categoryId == null),
      'restoreCascade was handed an inherited alert',
    );
    _ensureOwn(event.id, fromPartner: event.fromPartner);
    final normalized = _normalized(event);
    await _dao.restoreEventCascade(
      _eventToCompanion(normalized, updatedAt: DateTime.now()),
      marks: marks,
      descriptions: descriptions,
      skips: skips,
      alerts: [
        for (final alert in alerts)
          if (alert.categoryId == null)
            EventAlertService.companionFor(
              alert.eventId == normalized.id
                  ? alert
                  : alert.copyWith(eventId: normalized.id),
            ),
      ],
    );
    _writes++;
    _cacheWritten(normalized);
    // Patched from the sets just written, never re-read: the facades gain
    // this event's rows and nothing else moves.
    await _patchChildren('restore', [
      () => EventOccurrenceService.restoreEvent(normalized.id, descriptions),
      () => EventPresenceService.restoreEvent(normalized.id, marks),
      () => EventSkipService.restoreEvent(normalized.id, skips),
      () => EventAlertService.restoreEvent(normalized.id, alerts),
    ]);
  }

  /// Deletes the event and cascades to its per-occurrence description and
  /// absence rows in one transaction — nothing else references an event id, so
  /// leaving them behind would strand rows no surface can reach or clean up.
  /// Composed here rather than in the bloc, mirroring
  /// `CategoryService.deleteCategory`.
  ///
  /// Since v28 all three tables **tombstone together**: the event (v27), its
  /// absence marks (v27) and its per-day descriptions (v28), one statement
  /// each, so the delete carries a single merge order instead of the children
  /// outliving the parent or vanishing without one. Nothing above this method
  /// can tell a tombstone from a delete — the cache patch, the two facade
  /// refreshes and the bloc's own cache removal are unchanged.
  ///
  /// Deleting an event is the **only** thing that removes absence or
  /// description rows in bulk: turning either flag off or changing the rule
  /// leaves them dormant, because the stored delta is the durable record of a
  /// deliberate act and flipping the toggle back on must restore every one.
  ///
  /// Since **v40** the cascade also covers the event's alerts — tombstoned,
  /// like every other CRDT child — and its OS registrations, which are **hard
  /// deleted** instead. That asymmetry is the device-local rule: an alert is
  /// the user's data and merges, a registration describes this phone's
  /// scheduler and is rebuilt by the next reconcile. Both matter more than the
  /// rows above: a stranded alert does not draw a stale badge, it wakes the
  /// phone up for an event that no longer exists.
  ///
  /// The tombstones are one DAO call (**v43**) so the whole delete shares one
  /// merge order, which only the DAO can give it.
  Future<void> deleteById(String id) async {
    _ensureOwn(id);
    await _db.transaction(() async {
      await _dao.tombstoneEventCascade(id);
      await _db.alertRegistrationDao.deleteForEvent(id);
    });
    _writes++;
    _cache = List.unmodifiable(_cache.where((e) => e.id != id));
    // The cascade touched this event's rows alone, so the four facades drop
    // them in place rather than reading four tables whole for one delete.
    await _patchChildren('delete', [
      () => EventOccurrenceService.forgetEvent(id),
      () => EventPresenceService.forgetEvent(id),
      () => EventSkipService.forgetEvent(id),
      () => EventAlertService.forgetEvent(id),
    ]);
  }

  /// "Copy to my calendar" (§6.9, D19): a new event of the person's own from
  /// a partner's [event] as its read sheet shows it on [day] — the one act
  /// that makes a shared event the person's own. Returns the stored copy,
  /// for the editor to open.
  ///
  /// The facts shown and nothing else: title, time, repeat, priority, the
  /// event's own colour and icon, the description of [day] (a per-day text
  /// for a series that keeps one), and the category when this database has
  /// that id as a category of the person's own — a shared built-in such as
  /// `gym` — else Other. A partner's own category is never the copy's: an
  /// event of the person's own cannot take one, and the save would be
  /// refused by name. A create, never an import: a new id stamped now, no
  /// share mark, and none of the person's alerts on the shared event, no
  /// linked note (it would open the partner's), no skipped days and no
  /// presence settings come along — the copy starts clean.
  Future<CalendarEvent> copyToMine(CalendarEvent event, DateTime day) async {
    final description = OccurrenceDescriptions.descriptionFor(event, day);
    final category = CalendarCategories.byId(event.categoryId);
    final copy = CalendarEvent(
      id: const Uuid().v4(),
      title: event.title,
      categoryId: category == null || category.fromPartner
          ? kFallbackCategoryId
          : event.categoryId,
      startDate: event.startDate,
      rule: event.rule,
      endDate: event.endDate,
      retroactive: event.retroactive,
      time: event.time,
      description: description == null || description.isEmpty
          ? null
          : description,
      priority: event.priority,
      colorValue: event.colorValue,
      iconKey: event.iconKey,
      tintIcon: event.tintIcon,
    );
    await upsert(copy);
    return _cache.firstWhere((cached) => cached.id == copy.id);
  }

  /// Shares the event [id] with the partner of the pair [pairId], or makes
  /// it private again when null (`docs/cloud-sharing-foundations.md` §3):
  /// one stamped write of the event's mark, which the next push carries,
  /// with the event's skipped days and per-day texts following it. Its
  /// presence marks and alerts stay a person's own. Returns whether the
  /// mark was written — false for an event that is gone or carries it
  /// already.
  ///
  /// The mark is no part of the event a screen holds, so the cache stays as
  /// it is. `ShareService.setEventShared` is its one caller in the app, so
  /// no surface ever holds a pair id; tests and the QA seam reach it
  /// directly.
  Future<bool> setShared(String id, String? pairId) =>
      _dao.setSharedPair(id, pairId);

  /// Runs the four child patches of one event's delete or restore, each on
  /// its own guard: the rows are written either way, and a facade that fails
  /// to take its patch is read whole by its next load. The children patch
  /// only a live or loading instance — with neither, nothing is published,
  /// and the next `getInstance` reads the table the cascade left.
  static Future<void> _patchChildren(
    String what,
    List<Future<void> Function()> patches,
  ) async {
    for (final patch in patches) {
      try {
        await patch();
      } catch (e, st) {
        debugPrint('[CalendarEventService] $what patch error: $e\n$st');
      }
    }
  }

  /// "Delete all events": tombstones every event this device may delete,
  /// with its absence marks, day descriptions, skips and alerts, under one
  /// HLC (D13) — the bound account's rows and the unowned ones, never another
  /// account's. Public holidays live in a separate table and are untouched.
  ///
  /// The OS registrations of the tombstoned events are hard deleted, as
  /// [deleteById]'s are: they describe this phone's scheduler, and the next
  /// reconcile rebuilds them. A surviving event keeps its own.
  ///
  /// The cache is re-read rather than emptied: another account's events
  /// survive the wipe (a restored archive on an unbound device), and an empty
  /// cache would hide them until the next load. A re-read that fails keeps
  /// the cache from before the wipe, with [lastLoadFailed] set: a bloc's
  /// light and refresh paths refuse it and read, and the caller's un-flagged
  /// announcement reads again — only a second failure in a row, on that
  /// read, would leave the wiped events on screen.
  ///
  /// The platform pass at the end is what [deleteById]'s caller does for one
  /// event: the registry rows are gone, but the phone still holds the entries
  /// they described, and cancelling them is exactly what the pass is for —
  /// without it an alarm rings for an event that no longer exists. Requested
  /// unawaited after the facades, the shape `CategoryService.deleteCategory`
  /// uses.
  Future<void> tombstoneAll() async {
    final binding = await (await SyncBindingService.getInstance()).read();
    await _db.transaction(() async {
      final ids = await _dao.tombstoneAll(ownerUid: binding?.accountUid);
      await _db.alertRegistrationDao.deleteForEvents(ids);
    });
    await _load();
    await _refreshOccurrences();
    await _refreshPresence();
    await _refreshSkips();
    await _refreshAlerts();
    unawaited(
      AlertScheduler.reconcileAllQuietly(AlertReconcileReason.eventChanged),
    );
  }

  /// Republishes the occurrence facade after a cascade. Tolerates the service
  /// not being constructed yet — the cascade already hit the table, and the
  /// facade populates from it on first load either way.
  Future<void> _refreshOccurrences() async {
    try {
      final service = await EventOccurrenceService.getInstance();
      await service.refreshAfterEventRemoval();
    } catch (e) {
      debugPrint('[CalendarEventService] Occurrence refresh error: $e');
    }
  }

  /// The presence twin of [_refreshOccurrences], with the same tolerance.
  Future<void> _refreshPresence() async {
    try {
      final service = await EventPresenceService.getInstance();
      await service.refreshAfterEventRemoval();
    } catch (e) {
      debugPrint('[CalendarEventService] Presence refresh error: $e');
    }
  }

  /// The skip twin, and the one with teeth: a stale skip does not just render
  /// wrong, it **hides** occurrences of whatever event later takes the id.
  Future<void> _refreshSkips() async {
    try {
      final service = await EventSkipService.getInstance();
      await service.refreshAfterEventRemoval();
    } catch (e) {
      debugPrint('[CalendarEventService] Skip refresh error: $e');
    }
  }

  /// The alert twin, with the same tolerance — and the loudest consequence if
  /// it is skipped: a facade still holding a deleted event's alerts is what
  /// the planner would plan from.
  Future<void> _refreshAlerts() async {
    try {
      final service = await EventAlertService.getInstance();
      await service.refreshAfterEventRemoval();
    } catch (e) {
      debugPrint('[CalendarEventService] Alert refresh error: $e');
    }
  }

  // ── Backup export / import ────────────────────────────────────────────

  /// Snapshot of every event row for inclusion in a full-app backup.
  /// Each entry mirrors the on-disk row shape so the import path can
  /// round-trip without re-deriving any value.
  ///
  /// The person's own events only: one another account shares with this one
  /// is a copy of that account's, and a backup holds what is mine
  /// (`docs/cloud-sharing-foundations.md` §8). Never the share mark.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    final shared = await _db.sharedRowDao.owner();
    return [
      for (final row in rows)
        if (shared == null || row.ownerId != shared)
          {
            'id': row.id,
            'title': row.title,
            'category': row.category,
            'startDateMs': row.startDate.millisecondsSinceEpoch,
            'allDay': row.allDay,
            'iconKey': row.iconKey,
            'ruleKind': row.ruleKind,
            'rulePayload': row.rulePayload,
            'endDateMs': row.endDate?.millisecondsSinceEpoch,
            'startMinute': row.startMinute,
            'durationMinutes': row.durationMinutes,
            'description': row.description,
            'noteId': row.noteId,
            'colorValue': row.colorValue,
            'tintIcon': row.tintIcon,
            'priority': row.priority,
            'retroactive': row.retroactive,
            'countOccurrences': row.countOccurrences,
            'countStyle': row.countStyle,
            'tracksPresence': row.tracksPresence,
            'assumeAbsent': row.assumeAbsent,
            'assumeAbsentFromMs': row.assumeAbsentFrom?.millisecondsSinceEpoch,
            'perOccurrenceDescriptions': row.perOccurrenceDescriptions,
            'showInDayRail': row.showInDayRail,
            'removeAfterAlert': row.removeAfterAlert,
            'categoryAlerts': row.categoryAlerts,
            'createdAtMs': row.createdAt.millisecondsSinceEpoch,
            'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
            if (row.ownerId != null) 'ownerId': row.ownerId,
          },
    ];
  }

  /// Replaces every persisted event with the contents of [data] (the list
  /// produced by [exportData]). Tolerates missing/malformed entries: bad
  /// rows are skipped, the rest still imports.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    // Parsed first, written once (**5.1**). The per-row `try` still guards
    // *parsing* — one malformed archive row is skipped, never fatal — but the
    // write is a single batched transaction instead of one nested transaction
    // and one guaranteed-miss `SELECT` per event.
    final companions = <CalendarEventsCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'] as String?;
        final title = map['title'] as String?;
        final category = map['category'] as String?;
        final startMs = map['startDateMs'];
        final ruleKind = map['ruleKind'] as String?;
        if (id == null ||
            title == null ||
            category == null ||
            startMs is! int ||
            ruleKind == null) {
          continue;
        }
        final createdMs = map['createdAtMs'] is int
            ? map['createdAtMs'] as int
            : startMs;
        final updatedMs = map['updatedAtMs'] is int
            ? map['updatedAtMs'] as int
            : createdMs;
        final endMs = map['endDateMs'];
        companions.add(
          CalendarEventsCompanion(
            id: Value(id),
            title: Value(title),
            category: Value(category),
            startDate: Value(
              DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
            ),
            allDay: Value(map['allDay'] as bool? ?? true),
            iconKey: Value(map['iconKey'] as String?),
            ruleKind: Value(ruleKind),
            rulePayload: Value(map['rulePayload'] as String?),
            endDate: endMs is int
                ? Value(DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true))
                : const Value.absent(),
            startMinute: map['startMinute'] is int
                ? Value(map['startMinute'] as int)
                : const Value.absent(),
            durationMinutes: map['durationMinutes'] is int
                ? Value(map['durationMinutes'] as int)
                : const Value.absent(),
            description: map['description'] is String
                ? Value(map['description'] as String)
                : const Value.absent(),
            noteId: map['noteId'] is String
                ? Value(map['noteId'] as String)
                : const Value.absent(),
            colorValue: map['colorValue'] is int
                ? Value(map['colorValue'] as int)
                : const Value.absent(),
            tintIcon: map['tintIcon'] is bool
                ? Value(map['tintIcon'] as bool)
                : const Value.absent(),
            priority: map['priority'] is int
                ? Value(map['priority'] as int)
                : const Value.absent(),
            // Absent in pre-v19 backups: the column default (false) is
            // exactly the forward-only behaviour those events had.
            retroactive: map['retroactive'] is bool
                ? Value(map['retroactive'] as bool)
                : const Value.absent(),
            // Absent in pre-v20 backups: default false = no count shown,
            // which is what those events displayed.
            countOccurrences: map['countOccurrences'] is bool
                ? Value(map['countOccurrences'] as bool)
                : const Value.absent(),
            countStyle: map['countStyle'] is String
                ? Value(
                    OccurrenceCountStyle.fromName(
                      map['countStyle'] as String,
                    ).name,
                  )
                : const Value.absent(),
            // Absent in pre-v26 backups: default false = presence untracked,
            // which is the only state those events could have been in.
            tracksPresence: map['tracksPresence'] is bool
                ? Value(map['tracksPresence'] as bool)
                : const Value.absent(),
            // Absent in pre-v37 backups: default false = the implicit
            // attendance those events were tracked under, and a NULL
            // from-date is the only thing "no from-date" could have meant.
            assumeAbsent: map['assumeAbsent'] is bool
                ? Value(map['assumeAbsent'] as bool)
                : const Value.absent(),
            assumeAbsentFrom: map['assumeAbsentFromMs'] is int
                ? Value(
                    DateTime.fromMillisecondsSinceEpoch(
                      map['assumeAbsentFromMs'] as int,
                      isUtc: true,
                    ),
                  )
                : const Value.absent(),
            // Absent in pre-v28 backups: no archive ever carried the intent,
            // because the global setting it replaced was never in
            // `BackupService._exportSettings`'s allowlist. Default false means
            // those events restore with one shared description and their
            // imported day rows dormant — enabling an event brings them back.
            perOccurrenceDescriptions: map['perOccurrenceDescriptions'] is bool
                ? Value(map['perOccurrenceDescriptions'] as bool)
                : const Value.absent(),
            // Absent in pre-v34 backups, and absent is exactly right: the
            // column is nullable and NULL means *auto*, so a v33 archive
            // restores every event to the rail membership its presence flag
            // already implied. Only an explicit override round-trips.
            showInDayRail: map['showInDayRail'] is bool
                ? Value(map['showInDayRail'] as bool)
                : const Value.absent(),
            // Absent in pre-v40 backups: default false, because an event that
            // could not carry an alarm could not be removed by one either.
            // The alerts themselves ride the separate `eventAlerts` key, which
            // is why this one needs no version bump.
            removeAfterAlert: map['removeAfterAlert'] is bool
                ? Value(map['removeAfterAlert'] as bool)
                : const Value.absent(),
            // Absent in pre-v42 backups: default on, which is what every
            // event of those installs meant — no category had an alert to
            // inherit. The category alerts ride their own `categoryAlerts`
            // key at the top of the archive.
            categoryAlerts: map['categoryAlerts'] is bool
                ? Value(map['categoryAlerts'] as bool)
                : const Value.absent(),
            createdAt: Value(
              DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true),
            ),
            updatedAt: Value(
              DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true),
            ),
            ownerId: Value(JsonKeys.ownerIdOf(map)),
          ),
        );
      } catch (e) {
        debugPrint('[CalendarEventService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _load();
    // Only the revision: the restore that called this still has skips,
    // descriptions and alerts to import, and tells the blocs once it has.
    externalRevision++;
  }

  // ── Row ↔ Domain mapping ──────────────────────────────────────────────

  /// [partner] is `shared_owner` as the caller read it, once for all its
  /// rows: null on a database that reads no shared rows.
  CalendarEvent _rowToEvent(CalendarEventRow row, String? partner) {
    return CalendarEvent(
      id: row.id,
      title: row.title,
      categoryId: row.category,
      startDate: _dateOnlyUtc(row.startDate),
      iconKey: row.iconKey,
      endDate: row.endDate == null ? null : _dateOnlyUtc(row.endDate!),
      time: _decodeTime(row.startMinute, row.durationMinutes),
      description: row.description,
      noteId: row.noteId,
      colorValue: row.colorValue,
      tintIcon: row.tintIcon,
      priority: row.priority.clamp(kMinEventPriority, kMaxEventPriority),
      retroactive: row.retroactive,
      countOccurrences: row.countOccurrences,
      countStyle: OccurrenceCountStyle.fromName(row.countStyle),
      tracksPresence: row.tracksPresence,
      assumeAbsent: row.assumeAbsent,
      assumeAbsentFrom: row.assumeAbsentFrom == null
          ? null
          : _dateOnlyUtc(row.assumeAbsentFrom!),
      perOccurrenceDescriptions: row.perOccurrenceDescriptions,
      showInDayRail: row.showInDayRail,
      removeAfterAlert: row.removeAfterAlert,
      categoryAlerts: row.categoryAlerts,
      rule: _decodeRule(row.ruleKind, row.rulePayload),
      createdAt: row.createdAt,
      fromPartner: partner != null && row.ownerId == partner,
    );
  }

  /// Reconstructs an [EventTime] from the persisted columns. The stored
  /// `all_day` boolean is intentionally ignored — [CalendarEvent.allDay]
  /// is derived from the presence of [EventTime] so we can never end up
  /// with an inconsistent pair on read.
  static EventTime? _decodeTime(int? startMinute, int? durationMinutes) {
    if (startMinute == null) return null;
    if (startMinute < EventTime.minStartMinute ||
        startMinute >= EventTime.minutesPerDay) {
      return null;
    }
    final duration = (durationMinutes != null && durationMinutes > 0)
        ? durationMinutes
        : null;
    return EventTime(startMinute: startMinute, durationMinutes: duration);
  }

  /// Drift returns `DateTime` in local time when reading an int-epoch
  /// column, so naive `.year/.month/.day` extraction after we wrote
  /// `DateTime.utc(...)` can shift the date by one day in non-UTC zones.
  /// Recover the original UTC date via the epoch milliseconds.
  static DateTime _dateOnlyUtc(DateTime value) {
    final asUtc = DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
    return DateTime.utc(asUtc.year, asUtc.month, asUtc.day);
  }

  CalendarEventsCompanion _eventToCompanion(
    CalendarEvent event, {
    required DateTime updatedAt,
  }) {
    final time = event.time;
    return CalendarEventsCompanion(
      id: Value(event.id),
      title: Value(event.title),
      category: Value(event.categoryId),
      startDate: Value(event.startDate),
      // `all_day` is a denormalized mirror of `time == null`, kept around
      // so SQL filters like `WHERE all_day = 0` stay cheap. Never read
      // back as truth — see [_decodeTime].
      allDay: Value(event.allDay),
      iconKey: Value(event.iconKey),
      ruleKind: Value(_ruleKind(event.rule)),
      rulePayload: Value(_rulePayload(event.rule)),
      endDate: Value(event.endDate),
      startMinute: Value(time?.startMinute),
      durationMinutes: Value(time?.durationMinutes),
      description: Value(event.description),
      noteId: Value(event.noteId),
      colorValue: Value(event.colorValue),
      tintIcon: Value(event.tintIcon),
      priority: Value(event.priority),
      retroactive: Value(event.retroactive),
      countOccurrences: Value(event.countOccurrences),
      countStyle: Value(event.countStyle.name),
      tracksPresence: Value(event.tracksPresence),
      assumeAbsent: Value(event.assumeAbsent),
      assumeAbsentFrom: Value(event.assumeAbsentFrom),
      perOccurrenceDescriptions: Value(event.perOccurrenceDescriptions),
      showInDayRail: Value(event.showInDayRail),
      removeAfterAlert: Value(event.removeAfterAlert),
      categoryAlerts: Value(event.categoryAlerts),
      createdAt: Value(updatedAt),
      updatedAt: Value(updatedAt),
    );
  }

  // ── Recurrence serialization ──────────────────────────────────────────
  //
  // Delegated to `RecurrenceCodec` so event templates, which persist the same
  // `rule_kind` / `rule_payload` pair, cannot encode a rule differently from
  // the events they stamp out.

  String _ruleKind(RecurrenceRule rule) => RecurrenceCodec.kindOf(rule);

  String? _rulePayload(RecurrenceRule rule) => RecurrenceCodec.payloadOf(rule);

  RecurrenceRule _decodeRule(String kind, String? payload) =>
      RecurrenceCodec.decode(kind, payload);
}
