import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/json_keys.dart';
import '../database/daos/overview_view_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/calendar_appearance.dart';
import '../models/overview_list_options.dart';
import '../models/overview_period.dart';
import '../models/overview_view.dart';
import 'settings_service.dart';

/// Owns `overview_views` — the overview's saved lists (D17 · A).
///
/// [FilterPresetService] cloned on purpose, one for one: no facade (the
/// overview awaits it once and holds it), a cache of live views so the bar
/// button's match costs no query on a rebuild, one serialized write chain,
/// the same cap. All CRDT stamping lives in [OverviewViewDao].
class OverviewViewService {
  static OverviewViewService? _instance;
  static const Uuid _uuid = Uuid();

  /// Upper bound on how many views one database keeps — a findability
  /// limit, [FilterPresetService.maxPresets]'s reasoning: past this many the
  /// flat searchable sheet stops being the one-tap path it exists to be.
  /// Enforced at [create], the only growth path.
  static const int maxViews = 50;

  /// The first construction while it is in flight ([EventAlertService]'s
  /// pair), so two callers racing it share one load rather than each caching
  /// its own view list.
  static Future<OverviewViewService>? _initializing;

  /// Bumped by every [reset]. With [DatabaseLifecycle.generation] it is how a
  /// construction tells, past each of its awaits, that it has been overtaken:
  /// this counter covers a switch that reached this service (and a restore's
  /// deliberate re-init), the lifecycle's covers a switch that landed before
  /// the construction had registered its handler and so never called [reset]
  /// here at all.
  static int _generation = 0;

  late OverviewViewDao _dao;

  /// Clock seam: what a view's period is decoded against and written back
  /// against are two different days whenever a write crosses New Year, which
  /// is exactly the case a test has to be able to stage ([_load],
  /// [_toCompanion]).
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Where a view saved on "this week" learns which day the calendar's week
  /// starts on, read on every [_load] so a reload follows the setting.
  final Future<CalendarWeekStart> Function() _weekStart;

  OverviewViewService._(this._weekStart);

  static Future<OverviewViewService> getInstance() =>
      _createOnce(AppDatabase.getInstance, _settingsWeekStart);

  /// Binds the singleton to an arbitrary [AppDatabase] so tests run the real
  /// DAO against `NativeDatabase.memory()`. Never use it in app code.
  /// [weekStart] stands in for the calendar setting, which this seam does
  /// not read so a test needs no settings singleton; [weekStartReader], when
  /// given, replaces it, so a test can stage a read that fails.
  @visibleForTesting
  static Future<OverviewViewService> forTesting(
    AppDatabase db, {
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    Future<CalendarWeekStart> Function()? weekStartReader,
  }) => _createOnce(() async => db, weekStartReader ?? () async => weekStart);

  static Future<CalendarWeekStart> _settingsWeekStart() async =>
      (await SettingsService.getInstance()).getCalendarWeekStart();

  /// One construction at a time, and never one a database switch overtook.
  ///
  /// A construction the switch overtook read the database that was just
  /// closed, so it discards itself and hands its caller the one the new
  /// database installs — otherwise the overview would hold a service bound to
  /// a dead handle for the rest of the session.
  static Future<OverviewViewService> _createOnce(
    Future<AppDatabase> Function() open,
    Future<CalendarWeekStart> Function() weekStart,
  ) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<OverviewViewService> creating;
    creating = () async {
      final generation = _generation;
      final lifecycle = DatabaseLifecycle.generation;
      bool overtaken() =>
          generation != _generation ||
          lifecycle != DatabaseLifecycle.generation;

      Future<OverviewViewService> restart() async {
        if (identical(_initializing, creating)) _initializing = null;
        return await _createOnce(open, weekStart);
      }

      try {
        final db = await open();
        if (overtaken()) return await restart();
        final service = OverviewViewService._(weekStart);
        service._dao = db.overviewViewDao;
        await service._load();
        if (overtaken()) return await restart();
        _instance = service;
        DatabaseLifecycle.registerResetHandler(reset);
        return service;
      } finally {
        if (identical(_initializing, creating)) _initializing = null;
      }
    }();
    return _initializing = creating;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active database. Invoked by [DatabaseLifecycle].
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
  }

  List<OverviewView> _cache = const [];

  /// The tail of the write chain — `null` while idle (see [_serialize]).
  Future<void>? _writes;

  List<OverviewView> get views => _cache;

  bool get isFull => _cache.length >= maxViews;

  Future<void> reload() => _load();

  /// [FilterPresetService]'s write chain: every mutation waits for the one
  /// before it, so two quick drags cannot land out of order; a failed link
  /// is swallowed for the chain only; the tail starts `null` so no future is
  /// built in a widget test's `FakeAsync` zone.
  Future<T> _serialize<T>(Future<T> Function() write) async {
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Already surfaced to whoever issued it; one failure must not stop
        // the queue.
      }
    }
    try {
      return await write();
    } finally {
      done.complete();
    }
  }

  Future<void> _load() async {
    var weekStart = CalendarWeekStart.monday;
    try {
      weekStart = await _weekStart();
    } catch (e) {
      // The views still load: only one saved on "this week" can differ, by
      // the day its week starts on.
      debugPrint('[OverviewViewService] Week start read error: $e');
    }
    try {
      final rows = await _dao.getAll();
      final today = clock();
      _cache = List.unmodifiable(
        rows.map((row) => _rowToView(row, today, weekStart)),
      );
    } catch (e) {
      debugPrint('[OverviewViewService] Load error: $e');
      _cache = const [];
    }
  }

  /// The view whose list is exactly the one shown, or `null` — what lights
  /// the overview's bar button and puts the ✓ on the sheet's row.
  OverviewView? matching(
    OverviewPeriod period,
    OverviewListOptions options,
    Set<String> categoryIds, {
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) {
    for (final view in _cache) {
      if (view.matches(
        period,
        options,
        categoryIds,
        today: today,
        weekStart: weekStart,
      )) {
        return view;
      }
    }
    return null;
  }

  /// Saves the list under [name], appended to the end of the display order.
  ///
  /// Returns `null` when the table is already at [maxViews] — a refusal the
  /// caller reports.
  Future<OverviewView?> create({
    required String name,
    required OverviewPeriod period,
    required OverviewListOptions options,
    required Set<String> categoryIds,
  }) {
    return _serialize(() async {
      if (isFull) return null;
      final id = _uuid.v4();
      final view = OverviewView(
        id: id,
        name: name.trim(),
        period: period,
        options: options,
        categoryIds: categoryIds,
        sortOrder: await _dao.nextSortOrder(),
      );
      await _dao.upsertView(_toCompanion(view));
      await _load();
      return _byId(id) ?? view;
    });
  }

  /// Writes [view] back in place — a rename, or an update to the current
  /// list. Keeps its `created_at` and its position.
  Future<void> update(OverviewView view) {
    return _serialize(() async {
      await _dao.upsertView(_toCompanion(view));
      await _load();
    });
  }

  Future<void> delete(String id) {
    return _serialize(() async {
      await _dao.softDeleteById(id);
      await _load();
    });
  }

  /// Persists a new display order, given every live id in the order it
  /// should appear — the whole list, never a delta (see [_serialize]).
  Future<void> reorder(List<String> idsInOrder) {
    return _serialize(() async {
      await _dao.reorder(idsInOrder);
      await _load();
    });
  }

  OverviewView? _byId(String id) {
    for (final view in _cache) {
      if (view.id == id) return view;
    }
    return null;
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live views only, without CRDT identity — a backup is not a sync
  /// channel. The payload is exported **verbatim**, never re-encoded from a
  /// decoded model, so a field a newer build wrote survives the trip.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'name': row.name,
          'payload': row.payload,
          'sortOrder': row.sortOrder,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
          if (row.ownerId != null) 'ownerId': row.ownerId,
        },
    ];
  }

  /// Wipe-then-reinsert, [FilterPresetService.importData]'s shape: audit
  /// timestamps preserved, identity stamped fresh by the DAO, malformed rows
  /// skipped. A payload that no longer parses is stored as written and reads
  /// as this year's unfiltered list, which keeps the user's named row alive.
  Future<void> importData(List<dynamic> data) {
    return _serialize(() => _importData(data));
  }

  Future<void> _importData(List<dynamic> data) async {
    await _dao.deleteAll();
    final companions = <OverviewViewsCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'];
        final name = map['name'];
        if (id is! String || name is! String) continue;
        final now = DateTime.now();
        final createdAtMs = map['createdAtMs'];
        final updatedAtMs = map['updatedAtMs'];
        companions.add(
          OverviewViewsCompanion(
            id: Value(id),
            name: Value(name),
            payload: Value(map['payload'] is String ? map['payload'] : ''),
            sortOrder: Value(map['sortOrder'] is int ? map['sortOrder'] : 0),
            createdAt: Value(
              createdAtMs is int
                  ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
                  : now,
            ),
            updatedAt: Value(
              updatedAtMs is int
                  ? DateTime.fromMillisecondsSinceEpoch(updatedAtMs)
                  : now,
            ),
            ownerId: Value(JsonKeys.ownerIdOf(map)),
          ),
        );
      } catch (e) {
        debugPrint('[OverviewViewService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _load();
  }

  OverviewView _rowToView(
    OverviewViewRow row,
    DateTime today,
    CalendarWeekStart weekStart,
  ) {
    Object? json;
    try {
      json = row.payload.isEmpty ? null : jsonDecode(row.payload);
    } catch (e) {
      debugPrint('[OverviewViewService] Malformed view payload: $e');
    }
    return OverviewView.fromJson(
      json,
      id: row.id,
      name: row.name,
      today: today,
      weekStart: weekStart,
      sortOrder: row.sortOrder,
    );
  }

  OverviewViewsCompanion _toCompanion(OverviewView view) {
    return OverviewViewsCompanion(
      id: Value(view.id),
      name: Value(view.name),
      payload: Value(jsonEncode(view.toJson(today: clock()))),
      sortOrder: Value(view.sortOrder),
    );
  }
}
