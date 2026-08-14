import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/calendar_categories.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/calendar_category_dao.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';

/// Loads and seeds the `calendar_categories` table and publishes a
/// synchronous in-memory cache via [CalendarCategories.updateCache] so calendar
/// render paths resolve categories in O(1) with no `await`.
///
/// On [getInstance] it:
///   1. Seeds the built-in catalog ([CalendarCategories.builtInSeeds]) with
///      insert-if-missing semantics (stable ids == the historical enum names),
///      so existing events link to them with no data migration and user edits
///      to a built-in's color/icon are never clobbered.
///   2. Loads every row into memory and publishes the cache.
///
/// Mutations ([create]/[updateCategory]/[deleteCategory]) write through the DAO
/// and then reload so the cache stays authoritative. Deleting a custom category
/// reassigns its events to the built-in fallback so no event is ever orphaned.
class CategoryService {
  static CategoryService? _instance;

  late AppDatabase _db;
  late CalendarCategoryDao _dao;
  List<CalendarCategory> _cache = const [];

  CategoryService._();

  static Future<CategoryService> getInstance() async {
    if (_instance != null) return _instance!;
    final service = CategoryService._();
    service._db = await AppDatabase.getInstance();
    service._dao = service._db.calendarCategoryDao;
    await service._seedBuiltIns();
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static [CalendarCategories]
  /// cache so stale categories from a closed database cannot leak into render
  /// paths before the next [getInstance] republishes them.
  static void reset() {
    _instance = null;
    CalendarCategories.updateCache(const []);
  }

  /// Unmodifiable, ordered view over the in-memory cache.
  List<CalendarCategory> get categories => _cache;

  Future<void> reload() => _load();

  // ── Cache load / built-in seed ───────────────────────────────────────

  Future<void> _load() async {
    try {
      final rows = await _dao.getAll();
      _cache = List.unmodifiable(rows.map(_rowToModel));
    } catch (e) {
      debugPrint('[CategoryService] Load error: $e');
      _cache = const [];
    }
    CalendarCategories.updateCache(_cache);
  }

  Future<void> _seedBuiltIns() async {
    final now = DateTime.now();
    try {
      await _db.transaction(() async {
        for (var i = 0; i < CalendarCategories.builtInSeeds.length; i++) {
          final seed = CalendarCategories.builtInSeeds[i];
          // Insert-if-missing only: never rewrite an existing built-in's
          // sort order. On a fresh install every built-in seeds at its
          // catalog index. On an upgrade that inserts a built-in mid-catalog
          // (e.g. `birthday` before `other`), the new row shares an index
          // with the previously-last built-in; the deterministic
          // `(sortOrder, id)` tie-break — applied identically by
          // `CalendarCategoryDao.getAll` and `CalendarCategories._byOrder` —
          // keeps `birthday` ahead of `other`, and customs (always seeded
          // above every built-in index) stay after both. Rewriting orders
          // here would instead collide a re-indexed built-in with existing
          // customs, so we deliberately don't.
          await _dao.insertIfMissing(
            CalendarCategoriesCompanion(
              id: Value(seed.id),
              name: Value(CalendarCategories.builtInSeedName(seed.kind)),
              colorValue: Value(seed.colorValue),
              iconKey: Value(seed.iconKey),
              sortOrder: Value(i),
              isBuiltIn: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('[CategoryService] Seed error: $e');
    }
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Creates a new custom category appended after every existing one. Returns
  /// the persisted category.
  Future<CalendarCategory> create({
    required String name,
    required int colorValue,
    required String iconKey,
  }) async {
    final id = const Uuid().v4();
    final order = await _dao.nextSortOrder();
    final now = DateTime.now();
    await _dao.insertCategory(
      CalendarCategoriesCompanion(
        id: Value(id),
        name: Value(name.trim()),
        colorValue: Value(colorValue),
        iconKey: Value(iconKey),
        sortOrder: Value(order),
        isBuiltIn: const Value(false),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await _load();
    return CalendarCategories.byId(id) ??
        CalendarCategory(
          id: id,
          name: name.trim(),
          colorValue: colorValue,
          iconKey: iconKey,
          sortOrder: order,
          isBuiltIn: false,
        );
  }

  /// Persists edits to an existing category (color/icon for built-ins; also
  /// name for customs). `created_at` is preserved by the DAO.
  Future<void> updateCategory(CalendarCategory category) async {
    await _dao.updateCategory(
      CalendarCategoriesCompanion(
        id: Value(category.id),
        name: Value(category.name.trim()),
        colorValue: Value(category.colorValue),
        iconKey: Value(category.iconKey),
        sortOrder: Value(category.sortOrder),
        isBuiltIn: Value(category.isBuiltIn),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _load();
  }

  /// Deletes a custom category and reassigns its events to the built-in
  /// fallback ([kFallbackCategoryId]) in one transaction. Built-ins cannot be
  /// deleted (the seeder would re-add them anyway). No-op for unknown ids.
  Future<void> deleteCategory(String id) async {
    final category = CalendarCategories.byId(id);
    if (category == null || category.isBuiltIn) return;
    await _db.transaction(() async {
      await _db.calendarEventDao.reassignCategory(id, kFallbackCategoryId);
      await _dao.deleteById(id);
    });
    await _load();
  }

  // ── Backup export / import ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'name': row.name,
          'colorValue': row.colorValue,
          'iconKey': row.iconKey,
          'sortOrder': row.sortOrder,
          'isBuiltIn': row.isBuiltIn,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Replaces every category with [data], then re-seeds built-ins so the
  /// catalog is always complete even if the backup predates a built-in.
  /// Malformed rows are skipped.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'] as String?;
        final name = map['name'] as String?;
        final colorValue = map['colorValue'];
        final iconKey = map['iconKey'] as String?;
        if (id == null ||
            name == null ||
            colorValue is! int ||
            iconKey == null) {
          continue;
        }
        final createdMs = map['createdAtMs'] is int
            ? map['createdAtMs'] as int
            : DateTime.now().millisecondsSinceEpoch;
        final updatedMs = map['updatedAtMs'] is int
            ? map['updatedAtMs'] as int
            : createdMs;
        await _dao.insertCategory(
          CalendarCategoriesCompanion(
            id: Value(id),
            name: Value(name),
            colorValue: Value(colorValue),
            iconKey: Value(iconKey),
            sortOrder: Value(
              map['sortOrder'] is int ? map['sortOrder'] as int : 0,
            ),
            isBuiltIn: Value(map['isBuiltIn'] as bool? ?? false),
            createdAt: Value(
              DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true),
            ),
            updatedAt: Value(
              DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true),
            ),
          ),
        );
      } catch (e) {
        debugPrint('[CategoryService] Import row error: $e');
      }
    }
    await _seedBuiltIns();
    await _load();
  }

  // ── Row ↔ Domain ─────────────────────────────────────────────────────

  CalendarCategory _rowToModel(CalendarCategoryRow row) {
    return CalendarCategory(
      id: row.id,
      name: row.name,
      colorValue: row.colorValue,
      iconKey: row.iconKey,
      sortOrder: row.sortOrder,
      isBuiltIn: row.isBuiltIn,
    );
  }
}
