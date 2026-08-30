import 'dart:async';

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
/// Mutations ([create]/[updateCategory]/[setHidden]/[reorder]/[deleteCategory])
/// write through the DAO and then reload so the cache stays authoritative, and
/// every one of them is serialized onto a single chain ([_serialize]) so two
/// writes issued from different callbacks cannot land — or republish the facade
/// — out of order. Deleting a custom category reassigns its events to the
/// built-in fallback so no event is ever orphaned.
class CategoryService {
  static CategoryService? _instance;

  late AppDatabase _db;
  late CalendarCategoryDao _dao;
  List<CalendarCategory> _cache = const [];

  /// Tail of the serialized write chain, or null when nothing is in flight —
  /// see [_serialize].
  Future<void>? _writes;

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
    final existing = _instance;
    if (existing != null) {
      // Returning a singleton bound to some *other* database silently runs the
      // caller against the previous test's data instead of failing.
      assert(
        identical(existing._db, db),
        'CategoryService.forTesting: a singleton bound to a different '
        'AppDatabase is already installed. Call CategoryService.reset() in '
        'tearDown, or this test runs against the previous one.',
      );
      return existing;
    }
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
      // Insert-if-missing only: never rewrite an existing built-in's sort
      // order. On a fresh install every built-in seeds at its catalog index.
      // On an upgrade that inserts a built-in mid-catalog (e.g. `birthday`
      // before `other`), the new row shares an index with the previously-last
      // built-in; the deterministic `(sortOrder, id)` tie-break — applied
      // identically by `CalendarCategoryDao.getAll` and
      // `CalendarCategories._byOrder` — keeps `birthday` ahead of `other`,
      // and customs (always seeded above every built-in index) stay after
      // both. Rewriting orders here would instead collide a re-indexed
      // built-in with existing customs, so we deliberately don't.
      //
      // One batch, not one awaited insert per seed: this runs on the calendar's
      // first touch of every session and again after every backup import.
      await _dao.seedMissing([
        for (var i = 0; i < CalendarCategories.builtInSeeds.length; i++)
          CalendarCategoriesCompanion(
            id: Value(CalendarCategories.builtInSeeds[i].id),
            name: Value(
              CalendarCategories.builtInSeedName(
                CalendarCategories.builtInSeeds[i].kind,
              ),
            ),
            colorValue: Value(CalendarCategories.builtInSeeds[i].colorValue),
            iconKey: Value(CalendarCategories.builtInSeeds[i].iconKey),
            sortOrder: Value(i),
            isBuiltIn: const Value(true),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
      ]);
    } catch (e) {
      debugPrint('[CategoryService] Seed error: $e');
    }
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Runs [write] after every write already issued, and makes the next one
  /// wait for it.
  ///
  /// **Every mutation is serialized, not just reorder.** Nothing about
  /// `await` orders two writes issued from different callbacks, and each of
  /// them ends in a `_load()` that republishes the whole facade — so two
  /// racing mutations can also republish out of order and leave the cache
  /// showing the earlier one. Both the writes and their reloads have to be
  /// sequenced, which is one chain rather than a lock per call site.
  ///
  /// It is also what lets a mutation read [CalendarCategories] *inside* its
  /// own turn ([setHidden], [deleteCategory]) and see the previous write's
  /// result rather than whatever was cached when the user tapped.
  ///
  /// A failed link is swallowed *for the chain only* — the caller's future
  /// still surfaces it — so one error cannot poison every later write.
  ///
  /// **The tail starts null rather than as a completed future**, and an idle
  /// service therefore awaits nothing. That is not a micro-optimization: a
  /// `Future.value()` built in a field initializer captures the zone it was
  /// created in, and `then` on an already-completed future schedules its
  /// continuation on *that* zone. Built during a widget test's `setUp` it
  /// belongs to the root zone, so under the `FakeAsync` the test body runs in,
  /// the first link's continuation is queued somewhere nothing ever drains and
  /// the very first write never completes.
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

  /// Creates a new custom category appended after every existing one. Returns
  /// the persisted category.
  Future<CalendarCategory> create({
    required String name,
    required int colorValue,
    required String iconKey,
  }) {
    return _serialize(
      () =>
          _persistCreate(name: name, colorValue: colorValue, iconKey: iconKey),
    );
  }

  Future<CalendarCategory> _persistCreate({
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
  ///
  /// **`sort_order`, `is_built_in` and `is_hidden` are deliberately left
  /// absent**, so this path writes only what an editor can actually change.
  /// Callers hand over a whole model captured at some earlier moment — the
  /// editor sheet's when it opened — and the three fields it does not own are
  /// not theirs to carry back:
  ///
  ///   * order belongs to the drag. A reorder landing between the capture and
  ///     the save would be undone by a stale `sortOrder` riding along, which
  ///     also breaks the dense `0..N-1` invariant `reorder` maintains and lets
  ///     unrelated rows shuffle on `_byOrder`'s id tie-break.
  ///   * the archive flag belongs to [setHidden], for exactly the same reason
  ///     and by exactly the same route: the categories page fires its hide
  ///     un-awaited from a menu, so a save that started before that write
  ///     landed carries `isHidden: false` and silently un-archives a category
  ///     the user just retired. The editor sheet has no control for the flag,
  ///     so it can only ever echo a value it read — never one it was told.
  ///   * `is_built_in` is immutable by definition.
  Future<void> updateCategory(CalendarCategory category) {
    return _serialize(() => _persistUpdate(category));
  }

  Future<void> _persistUpdate(CalendarCategory category) async {
    await _dao.updateCategory(
      CalendarCategoriesCompanion(
        id: Value(category.id),
        name: Value(category.name.trim()),
        colorValue: Value(category.colorValue),
        iconKey: Value(category.iconKey),
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
  /// **Writes are serialized** ([_serialize]). Two quick drags start two async
  /// reorders, and nothing about `await` guarantees they land in the order
  /// they were issued; the loser would resurrect the earlier arrangement,
  /// which reads as the second drag having been ignored. Because callers pass
  /// their *current* full local order rather than a delta, the last one
  /// enqueued is the whole truth regardless.
  Future<void> reorder(List<String> idsInOrder) {
    return _serialize(() => _persistReorder(idsInOrder));
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
  ///
  /// Writes **only** the flag rather than a whole row: this is fired from a
  /// menu against a model captured when that menu was built, and a rename or
  /// a drag that lands in between is not this call's to undo. The read of the
  /// current state happens inside the serialized turn for the same reason.
  Future<void> setHidden(String id, bool hidden) {
    return _serialize(() async {
      final category = CalendarCategories.byId(id);
      if (category == null || category.isHidden == hidden) return;
      await _dao.updateCategory(
        CalendarCategoriesCompanion(
          id: Value(id),
          isHidden: Value(hidden),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _load();
    });
  }

  /// Deletes a custom category and reassigns its events to the built-in
  /// fallback ([kFallbackCategoryId]) in one transaction. Built-ins cannot be
  /// deleted (the seeder would re-add them anyway). No-op for unknown ids.
  Future<void> deleteCategory(String id) {
    return _serialize(() async {
      final category = CalendarCategories.byId(id);
      if (category == null || category.isBuiltIn) return;
      await _db.transaction(() async {
        await _db.calendarEventDao.reassignCategory(id, kFallbackCategoryId);
        await _dao.deleteById(id);
      });
      await _load();
    });
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
  ///
  /// Serialized like every other mutation, and this is the one where it counts
  /// most: it opens by wiping the table, and the management page fires its
  /// mutations un-awaited, so an in-flight `create` landing mid-restore would
  /// leave an orphan row and a stale `_load()` could publish a half-imported
  /// catalog to the facade every render path reads.
  Future<void> importData(List<dynamic> data) {
    return _serialize(() => _persistImport(data));
  }

  Future<void> _persistImport(List<dynamic> data) async {
    await _dao.deleteAll();
    // Parsed first, written once — the shape `EventTemplateService.importData`
    // established. The per-row `try` still costs a malformed row and nothing
    // else, but the write is one batched commit rather than one awaited insert
    // per archived category, and a throw while parsing can no longer leave the
    // table half-restored.
    final companions = <CalendarCategoriesCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'];
        final name = map['name'];
        final colorValue = map['colorValue'];
        final iconKey = map['iconKey'];
        if (id is! String ||
            name is! String ||
            colorValue is! int ||
            iconKey is! String) {
          continue;
        }
        final createdMs = map['createdAtMs'] is int
            ? map['createdAtMs'] as int
            : DateTime.now().millisecondsSinceEpoch;
        final updatedMs = map['updatedAtMs'] is int
            ? map['updatedAtMs'] as int
            : createdMs;
        companions.add(
          CalendarCategoriesCompanion(
            id: Value(id),
            name: Value(name),
            colorValue: Value(colorValue),
            iconKey: Value(iconKey),
            sortOrder: Value(
              map['sortOrder'] is int ? map['sortOrder'] as int : 0,
            ),
            // Every flag is read by *type test* rather than a cast, so a junk
            // value costs the flag and not the whole category row.
            isBuiltIn: Value(
              map['isBuiltIn'] is bool && map['isBuiltIn'] as bool,
            ),
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
    await _dao.importAll(companions);
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
