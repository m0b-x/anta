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

  /// Tail of the serialized reorder chain — see [reorder].
  Future<void> _reorderChain = Future<void>.value();

  CategoryService._();

  static Future<CategoryService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO and the real facade against
  /// `NativeDatabase.memory()`, the way the other calendar services already
  /// do. Never use it in app code — the singleton is what the
  /// [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<CategoryService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<CategoryService> _create(AppDatabase db) async {
    final service = CategoryService._();
    service._db = db;
    service._dao = db.calendarCategoryDao;
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
        isHidden: Value(category.isHidden),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _load();
  }

  /// Persists a new display order, given every id in the order it should
  /// appear. Republishes the facade, so the picker, the calendar filter sheet,
  /// the agenda chips and the templates page all follow at once — every one of
  /// them reads `CalendarCategories.all`.
  ///
  /// **Writes are serialized.** Two quick drags start two async reorders, and
  /// nothing about `await` guarantees they land in the order they were issued;
  /// the loser would resurrect the earlier arrangement, which reads as the
  /// second drag having been ignored. Each write is chained onto the previous
  /// one's future, so the last one enqueued is the last one applied — and
  /// because callers pass their *current* full local order rather than a
  /// delta, that last write is the whole truth regardless.
  ///
  /// A failed link is swallowed *for the chain only* (the caller's future
  /// still surfaces it), so one error cannot poison every later drag.
  Future<void> reorder(List<String> idsInOrder) {
    final next = _reorderChain.then((_) => _persistReorder(idsInOrder));
    _reorderChain = next.catchError((_) {});
    return next;
  }

  Future<void> _persistReorder(List<String> idsInOrder) async {
    await _dao.reorder(idsInOrder);
    await _load();
  }

  /// Archives or restores a category. Built-ins can be hidden; they still
  /// cannot be deleted.
  ///
  /// `sort_order` is deliberately left untouched, so unhiding restores the
  /// category to the position it held — the behavioural edge hiding has over
  /// deleting and re-creating. No-op for unknown ids and for a category
  /// already in the requested state, so a repeated tap cannot churn
  /// `updated_at` or the facade revision.
  Future<void> setHidden(String id, bool hidden) async {
    final category = CalendarCategories.byId(id);
    if (category == null || category.isHidden == hidden) return;
    await updateCategory(category.copyWith(isHidden: hidden));
  }

  /// How many live events sit in each category, keyed by category id. Absent
  /// ids have none.
  ///
  /// **One statement for the whole page**, never a count per row — the
  /// management page renders forty of them. `query_count_test` guards the
  /// shape. Advisory data: read once per page entry and after a delete, never
  /// held as live state.
  Future<Map<String, int>> eventCountsByCategory() async {
    try {
      return await _db.calendarEventDao.countByCategory();
    } catch (e) {
      debugPrint('[CategoryService] Count error: $e');
      return const {};
    }
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
          'isHidden': row.isHidden,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Replaces every category with [data], then re-seeds built-ins so the
  /// catalog is always complete even if the backup predates a built-in.
  /// Malformed rows are skipped.
  ///
  /// `isHidden` defaults to visible and the backup version is deliberately
  /// **not** bumped: the key is additive, and a pre-v33 archive — which cannot
  /// describe a hidden category because none existed — restores everything
  /// visible, which is exactly what it recorded. Same precedent as v19 / v20.
  /// It is read by *type test* rather than a cast, so a junk value costs the
  /// flag rather than the whole category row.
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
            isHidden: Value(map['isHidden'] is bool && map['isHidden'] as bool),
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
      isHidden: row.isHidden,
    );
  }
}
