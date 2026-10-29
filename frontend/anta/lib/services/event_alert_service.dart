import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/event_alerts.dart';
import '../constants/json_keys.dart';
import '../database/daos/category_alert_dao.dart';
import '../database/daos/event_alert_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/category_alert.dart';
import '../models/event_alert.dart';

/// Writes one event's complete alert set. The seam `CalendarBloc` holds, so a
/// bloc test can watch the call without standing up a database.
///
/// `knownIds` rides along because the set is built on a surface and written a
/// layer away: see [EventAlertService.replaceForEvent].
typedef AlertWriter =
    Future<void> Function(
      String eventId,
      List<EventAlert> alerts, {
      Set<String>? knownIds,
    });

/// Owns the rows of `calendar_event_alerts` and, since **v42**,
/// `calendar_category_alerts`, and publishes both to the synchronous
/// [EventAlerts] facade — one owner, so one `revision` covers every alert an
/// event can carry, its own or its category's.
///
/// The [EventSkipService] shape verbatim — loaded at [getInstance] and
/// published with it, never configured from a page after the first frame —
/// because the same thing is true here as there: the facade is read
/// synchronously while rows are being built, and an unconfigured read is
/// *silent*. An event with an alarm would simply draw as an event without
/// one, and the scheduler would plan nothing for it.
///
/// That is why this joins the calendar's `Future.wait` rather than sitting in
/// GetIt: GetIt holds the *object*, so after a database switch it would hand
/// back one bound to a closed database, while `getInstance()` is self-healing.
///
/// All CRDT stamping lives in [EventAlertDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live alerts only.
class EventAlertService {
  static EventAlertService? _instance;

  /// The first construction while it is in flight, so callers racing it share
  /// one load rather than each publishing their own — and so
  /// [refreshAfterCategoryRemoval] can wait for an instance that is still
  /// reading the table instead of missing it.
  static Future<EventAlertService>? _initializing;

  late EventAlertDao _dao;
  late CategoryAlertDao _categoryDao;

  EventAlertService._();

  static Future<EventAlertService> getInstance() async {
    if (_instance != null) return _instance!;
    return _createOnce(AppDatabase.getInstance);
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO, the real CRDT stamping and the
  /// real facade against `NativeDatabase.memory()`. Never use it in app code —
  /// the singleton is what the [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<EventAlertService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _createOnce(() async => db);
  }

  static Future<EventAlertService> _createOnce(
    Future<AppDatabase> Function() open,
  ) {
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<EventAlertService> creating;
    creating = () async {
      try {
        return await _create(await open());
      } finally {
        if (identical(_initializing, creating)) _initializing = null;
      }
    }();
    return _initializing = creating;
  }

  static Future<EventAlertService> _create(AppDatabase db) async {
    final service = EventAlertService._();
    service._dao = db.eventAlertDao;
    service._categoryDao = db.categoryAlertDao;
    await service._load();
    await service._loadCategories();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static facade — the category
  /// half included — so alerts from a closed database cannot leak into render
  /// paths — or into a plan — before the next [getInstance] republishes.
  /// Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    _initializing = null;
    EventAlerts.resetCache();
  }

  /// The default [AlertWriter]: resolves the singleton and writes one event's
  /// alerts.
  ///
  /// The `AlertScheduler.reconcileEventById` shape, and the seam
  /// `CalendarBloc` holds for the same reason — a bloc test can watch the call
  /// without standing up a database. Failures are **not** swallowed here: an
  /// alert the user set and the app then dropped in silence is not
  /// best-effort, and the handler logs it next to the event write it belongs
  /// with.
  static Future<void> replaceForEventById(
    String eventId,
    List<EventAlert> alerts, {
    Set<String>? knownIds,
  }) async {
    final service = await getInstance();
    await service.replaceForEvent(eventId, alerts, knownIds: knownIds);
  }

  /// Mutable working copy behind the published facade. A single event's edit
  /// patches this and republishes rather than re-reading the table.
  final Map<String, List<EventAlert>> _byEvent = {};

  /// The category half's working copy, published wholesale on every write —
  /// a handful of rows, and one category alert changes every event in its
  /// category anyway.
  final Map<String, List<CategoryAlert>> _byCategory = {};

  Future<void> reload() async {
    await _load();
    await _loadCategories();
  }

  Future<void> _load() async {
    _byEvent.clear();
    try {
      final rows = await _dao.getAllActive();
      for (final row in rows) {
        (_byEvent[row.eventId] ??= <EventAlert>[]).add(_rowToAlert(row));
      }
    } catch (e) {
      debugPrint('[EventAlertService] Load error: $e');
      _byEvent.clear();
    }
    _publish();
  }

  Future<void> _loadCategories() async {
    _byCategory.clear();
    try {
      final rows = await _categoryDao.getAllActive();
      for (final row in rows) {
        (_byCategory[row.categoryId] ??= <CategoryAlert>[]).add(
          _rowToCategoryAlert(row),
        );
      }
    } catch (e) {
      debugPrint('[EventAlertService] Category load error: $e');
      _byCategory.clear();
    }
    _publishCategories();
  }

  void _publishCategories() {
    EventAlerts.updateCategoryCache(
      byCategory: {
        for (final entry in _byCategory.entries)
          entry.key: List.unmodifiable(entry.value),
      },
    );
  }

  /// The snapshot the facade is currently serving. Held so [_publishFor] can
  /// **share** the entries it did not touch: every inner list here is already
  /// unmodifiable and is never rebuilt in place, so handing the same instance
  /// to the next snapshot is safe.
  Map<String, List<EventAlert>> _published = const {};

  /// The full rebuild, for [_load] and the bulk paths — where every event
  /// changed anyway, so a targeted republish would be strictly more work.
  void _publish() {
    _published = {
      for (final entry in _byEvent.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    EventAlerts.updateCache(byEvent: _published);
  }

  /// Republish after a change confined to one event: only [eventId]'s list is
  /// rebuilt and the outer map is a pointer copy, so the cost follows the
  /// event that changed rather than the size of the store.
  void _publishFor(String eventId) {
    final next = Map<String, List<EventAlert>>.of(_published);
    final alerts = _byEvent[eventId];
    if (alerts == null || alerts.isEmpty) {
      next.remove(eventId);
    } else {
      next[eventId] = List.unmodifiable(alerts);
    }
    _published = next;
    EventAlerts.updateCache(byEvent: next);
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Makes [alerts] the complete set for [eventId]: removed alerts are
  /// tombstoned, kept ones re-stamped, new ones inserted — one transaction in
  /// the DAO, one republish here.
  ///
  /// The single write path for the editor, so there is exactly one place a
  /// saved event's alerts can diverge from what the sheet showed.
  ///
  /// An alert projected from a category (`categoryId != null`) is never
  /// stored as the event's own: it lives on the category, and a copy here
  /// would keep ringing after the category dropped it. Such an alert is
  /// filtered out — and asserted against in debug, since a caller handing one
  /// in has mixed `EventAlerts.effectiveFor` into an own-alert list.
  ///
  /// [knownIds] are the alerts the caller was looking at when it built
  /// [alerts] — the editor's seed, read in its `initState`. Only those may be
  /// tombstoned, so an alert that arrived by sync under the open sheet is not
  /// removed by a Save that never showed it; `null` keeps the plain whole-set
  /// meaning. Passed straight to the DAO, which owns the removal.
  Future<void> replaceForEvent(
    String eventId,
    List<EventAlert> alerts, {
    Set<String>? knownIds,
  }) async {
    assert(
      alerts.every((alert) => alert.categoryId == null),
      'replaceForEvent was handed an inherited alert',
    );
    final owned = [
      for (final alert in alerts)
        if (alert.categoryId == null)
          alert.eventId == eventId ? alert : alert.copyWith(eventId: eventId),
    ];
    await _dao.replaceForEvent(eventId, [
      for (final alert in owned) _toCompanion(alert),
    ], knownIds: knownIds);
    // The rows the DAO spared are still this event's alerts, so the cache
    // keeps them rather than waiting for the next full load to find them
    // again. Appended after the saved set: they arrived later than everything
    // the caller was shown, which is where `_load`'s `created_at` order puts
    // them too.
    final next = [...owned, ..._unseenAlerts(eventId, owned, knownIds)];
    if (next.isEmpty) {
      _byEvent.remove(eventId);
    } else {
      _byEvent[eventId] = next;
    }
    _publishFor(eventId);
  }

  /// The cached alerts of [eventId] that [knownIds] does not cover and [saved]
  /// does not carry: the rows the DAO spared because the caller never saw
  /// them. Empty when the caller claimed the whole set.
  List<EventAlert> _unseenAlerts(
    String eventId,
    List<EventAlert> saved,
    Set<String>? knownIds,
  ) {
    if (knownIds == null) return const [];
    final savedIds = {for (final alert in saved) alert.id};
    return [
      for (final alert in _byEvent[eventId] ?? const <EventAlert>[])
        if (!knownIds.contains(alert.id) && !savedIds.contains(alert.id)) alert,
    ];
  }

  /// Cascade for a deleted event. Called after the event service's delete
  /// transaction, so this only refreshes the published cache.
  Future<void> refreshAfterEventRemoval() => _load();

  Future<void> deleteAll() async {
    await _dao.deleteAll();
    await _load();
  }

  // ── Category alerts (v42) ────────────────────────────────────────────

  /// Every alert of [categoryId], enabled or not — the facade's list.
  List<CategoryAlert> categoryAlertsFor(String categoryId) =>
      EventAlerts.categoryAlertsFor(categoryId);

  /// Makes [alerts] the complete set for [categoryId] — [replaceForEvent]'s
  /// contract, [knownIds] included: removed alerts tombstoned, kept ones
  /// re-stamped only if they changed, new ones inserted, an alert the caller
  /// never saw left alone, one transaction in the DAO, one republish.
  Future<void> replaceForCategory(
    String categoryId,
    List<CategoryAlert> alerts, {
    Set<String>? knownIds,
  }) async {
    final owned = [
      for (final alert in alerts)
        alert.categoryId == categoryId
            ? alert
            : alert.copyWith(categoryId: categoryId),
    ];
    await _categoryDao.replaceForCategory(categoryId, [
      for (final alert in owned) _toCategoryCompanion(alert),
    ], knownIds: knownIds);
    final next = [
      ...owned,
      ..._unseenCategoryAlerts(categoryId, owned, knownIds),
    ];
    if (next.isEmpty) {
      _byCategory.remove(categoryId);
    } else {
      _byCategory[categoryId] = next;
    }
    _publishCategories();
  }

  /// [_unseenAlerts] for the category half.
  List<CategoryAlert> _unseenCategoryAlerts(
    String categoryId,
    List<CategoryAlert> saved,
    Set<String>? knownIds,
  ) {
    if (knownIds == null) return const [];
    final savedIds = {for (final alert in saved) alert.id};
    return [
      for (final alert in _byCategory[categoryId] ?? const <CategoryAlert>[])
        if (!knownIds.contains(alert.id) && !savedIds.contains(alert.id)) alert,
    ];
  }

  /// Tombstones every alert of [categoryId] — what a category delete means
  /// for them — and republishes.
  Future<void> tombstoneForCategory(String categoryId) async {
    await _categoryDao.tombstoneForCategory(categoryId);
    _byCategory.remove(categoryId);
    _publishCategories();
  }

  /// Republishes the category half after `CategoryService.deleteCategory`
  /// tombstoned a category's alerts inside its own transaction.
  ///
  /// Touches only a live or loading instance — one still loading may have
  /// read the table before the cascade, so it is awaited and reloaded. With
  /// neither, nothing has been published yet and the next [getInstance] reads
  /// the table as the cascade left it; resolving one here would bind it to
  /// whatever database [AppDatabase.getInstance] opens, not the one the
  /// category service holds.
  static Future<void> refreshAfterCategoryRemoval() async {
    var service = _instance;
    final pending = _initializing;
    if (service == null && pending != null) {
      try {
        service = await pending;
      } catch (_) {
        // That construction's failure is its own caller's to report; with no
        // instance there is nothing published to refresh.
      }
    }
    await service?._loadCategories();
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live category alerts only, without CRDT identity — [exportData]'s rule.
  Future<List<Map<String, dynamic>>> exportCategoryAlerts() async {
    final rows = await _categoryDao.getAllActive();
    return [
      for (final row in rows)
        {
          ..._rowToCategoryAlert(row).toJson(),
          EventAlertKeys.createdAtMs: row.createdAt.millisecondsSinceEpoch,
          EventAlertKeys.updatedAtMs: row.updatedAt.millisecondsSinceEpoch,
          if (row.ownerId != null) EventAlertKeys.ownerId: row.ownerId,
        },
    ];
  }

  /// Wipe-then-reinsert, [importData]'s shape: audit timestamps preserved,
  /// identity stamped fresh by the DAO, a malformed row skipped.
  Future<void> importCategoryAlerts(List<dynamic> data) async {
    await _categoryDao.deleteAll();
    final companions = <CalendarCategoryAlertsCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final alert = CategoryAlert.fromJson(map);
        if (alert == null) continue;
        final now = DateTime.now();
        final createdMs = map[EventAlertKeys.createdAtMs];
        final updatedMs = map[EventAlertKeys.updatedAtMs];
        companions.add(
          _toCategoryCompanion(
            alert,
            createdAt: createdMs is int
                ? DateTime.fromMillisecondsSinceEpoch(createdMs)
                : now,
            updatedAt: updatedMs is int
                ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
                : now,
          ).copyWith(ownerId: Value(JsonKeys.ownerIdOf(map))),
        );
      } catch (e) {
        debugPrint('[EventAlertService] Category import row error: $e');
      }
    }
    await _categoryDao.importAll(companions);
    await _loadCategories();
  }

  /// Clears every category alert, tombstones included, for an import that
  /// replaces them.
  Future<void> clearCategoryAlertsForImport() async {
    await _categoryDao.deleteAll();
    await _loadCategories();
  }

  /// Live alerts only, without CRDT identity. Backups are not a sync channel:
  /// identity is regenerated on restore, exactly as it is for notes, folders
  /// and skips.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAllActive();
    return [
      for (final row in rows)
        {
          ..._rowToAlert(row).toJson(),
          EventAlertKeys.createdAtMs: row.createdAt.millisecondsSinceEpoch,
          EventAlertKeys.updatedAtMs: row.updatedAt.millisecondsSinceEpoch,
          if (row.ownerId != null) EventAlertKeys.ownerId: row.ownerId,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring `CalendarEventService.importData`. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by
  /// the DAO, so a tombstone never round-trips a restore.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    // Parsed first, written once: the per-row guard still skips one malformed
    // archive row, but the write is a single batched transaction rather than
    // one awaited insert — and one WAL commit — per restored alert.
    final companions = <EventAlertsCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final alert = EventAlert.fromJson(map);
        if (alert == null) continue;
        final now = DateTime.now();
        final createdMs = map[EventAlertKeys.createdAtMs];
        final updatedMs = map[EventAlertKeys.updatedAtMs];
        companions.add(
          _toCompanion(
            alert,
            createdAt: createdMs is int
                ? DateTime.fromMillisecondsSinceEpoch(createdMs)
                : now,
            updatedAt: updatedMs is int
                ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
                : now,
          ).copyWith(ownerId: Value(JsonKeys.ownerIdOf(map))),
        );
      } catch (e) {
        debugPrint('[EventAlertService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _load();
  }

  /// Clears every alert. Used when restoring a backup that carried events but
  /// no alert key: the event import wipes and reinserts, so keeping the
  /// previous database's alerts would strand them against unrelated event ids
  /// — and a stranded alert does not merely render wrong, it *rings*.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    await _load();
  }

  // ── Row ↔ Domain mapping ─────────────────────────────────────────────

  static EventAlert _rowToAlert(EventAlertRow row) {
    return EventAlert(
      id: row.id,
      eventId: row.eventId,
      mode: AlertMode.fromName(row.mode),
      offsetMinutes: row.offsetMinutes,
      daysBefore: row.daysBefore,
      dayMinute: row.dayMinute,
      sound: row.sound,
      enabled: row.enabled,
    );
  }

  /// [row] as every reader of the facade sees it. Public for the one capture
  /// that reads `calendar_event_alerts` from outside this service —
  /// `CalendarEventService.captureCascade`, which runs where this service may
  /// never have been constructed, so the facade cannot answer for it
  /// ([companionFor]'s inverse).
  static EventAlert alertFrom(EventAlertRow row) => _rowToAlert(row);

  /// [alert] as the row a write stores. Public so the one cascade that writes
  /// `calendar_event_alerts` from outside this service —
  /// `CalendarEventService.restoreCascade`, which needs the alerts under the
  /// restore's shared stamp — maps an alert the one way this service does.
  static EventAlertsCompanion companionFor(EventAlert alert) =>
      _toCompanion(alert);

  static EventAlertsCompanion _toCompanion(
    EventAlert alert, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EventAlertsCompanion(
      id: Value(alert.id),
      eventId: Value(alert.eventId),
      mode: Value(alert.mode.name),
      offsetMinutes: Value(alert.offsetMinutes),
      daysBefore: Value(alert.daysBefore),
      dayMinute: Value(alert.dayMinute),
      sound: Value(alert.sound),
      enabled: Value(alert.enabled),
      createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
      updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
    );
  }

  static CategoryAlert _rowToCategoryAlert(CategoryAlertRow row) {
    return CategoryAlert(
      id: row.id,
      categoryId: row.categoryId,
      mode: AlertMode.fromName(row.mode),
      offsetMinutes: row.offsetMinutes,
      daysBefore: row.daysBefore,
      dayMinute: row.dayMinute,
      sound: row.sound,
      enabled: row.enabled,
    );
  }

  static CalendarCategoryAlertsCompanion _toCategoryCompanion(
    CategoryAlert alert, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarCategoryAlertsCompanion(
      id: Value(alert.id),
      categoryId: Value(alert.categoryId),
      mode: Value(alert.mode.name),
      offsetMinutes: Value(alert.offsetMinutes),
      daysBefore: Value(alert.daysBefore),
      dayMinute: Value(alert.dayMinute),
      sound: Value(alert.sound),
      enabled: Value(alert.enabled),
      createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
      updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
    );
  }
}
