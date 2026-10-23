import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/json_keys.dart';
import '../database/daos/overview_view_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/overview_list_options.dart';
import '../models/overview_period.dart';
import '../models/overview_view.dart';

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

  late OverviewViewDao _dao;

  OverviewViewService._();

  static Future<OverviewViewService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase] so tests run the real
  /// DAO against `NativeDatabase.memory()`. Never use it in app code.
  @visibleForTesting
  static Future<OverviewViewService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<OverviewViewService> _create(AppDatabase db) async {
    final service = OverviewViewService._();
    service._dao = db.overviewViewDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active database. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
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
    try {
      final rows = await _dao.getAll();
      final today = DateTime.now();
      _cache = List.unmodifiable(rows.map((row) => _rowToView(row, today)));
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
    Set<String> categoryIds,
  ) {
    for (final view in _cache) {
      if (view.matches(period, options, categoryIds)) return view;
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

  OverviewView _rowToView(OverviewViewRow row, DateTime today) {
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
      sortOrder: row.sortOrder,
    );
  }

  OverviewViewsCompanion _toCompanion(OverviewView view) {
    return OverviewViewsCompanion(
      id: Value(view.id),
      name: Value(view.name),
      payload: Value(jsonEncode(view.toJson(today: DateTime.now()))),
      sortOrder: Value(view.sortOrder),
    );
  }
}
