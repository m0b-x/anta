import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/calendar_categories.dart';
import '../constants/json_keys.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/calendar_category_dao.dart';
import '../database/daos/sync_dao.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/category_delete_impact.dart';
import 'alert_scheduler.dart';
import 'calendar_event_service.dart';
import 'category_profile_service.dart';
import 'event_alert_service.dart';
import 'event_template_service.dart';
import 'settings_service.dart';

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
/// — out of order. Deleting a custom category reassigns its events *and its
/// templates* to the built-in fallback so no event is ever orphaned, the
/// ones a template will go on to build included.
class CategoryService {
  static CategoryService? _instance;

  /// The first construction while it is in flight ([EventAlertService]'s
  /// pair), so two callers racing it do not each seed the catalog, load it
  /// and publish their own facade.
  static Future<CategoryService>? _initializing;

  /// Bumped by every [reset]. With [DatabaseLifecycle.generation] it is how a
  /// construction tells, past each of its awaits, that it has been overtaken:
  /// this counter covers a switch that reached this service (and a restore's
  /// deliberate re-init), the lifecycle's covers a switch that landed before
  /// the construction had registered its handler and so never called [reset]
  /// here at all.
  static int _generation = 0;

  /// Every seeded built-in's id, the fallback `other` among them.
  static final _builtInIds = {
    for (final seed in CalendarCategories.builtInSeeds) seed.id,
    kFallbackCategoryId,
  };

  late AppDatabase _db;
  late CalendarCategoryDao _dao;
  List<CalendarCategory> _cache = const [];

  /// [_cache] without a partner's categories — what [categories] hands out.
  List<CalendarCategory> _own = const [];

  /// Tail of the serialized write chain, or null when nothing is in flight —
  /// see [_serialize].
  Future<void>? _writes;

  CategoryService._();

  static Future<CategoryService> getInstance() =>
      _createOnce(AppDatabase.getInstance);

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO and the real facade against
  /// `NativeDatabase.memory()`, the way the other calendar services already
  /// do. Never use it in app code — the singleton is what the
  /// [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<CategoryService> forTesting(AppDatabase db) {
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
      return Future.value(existing);
    }
    return _createOnce(() async => db);
  }

  /// One construction at a time, and never one a database switch overtook.
  ///
  /// A construction the switch overtook seeded and read the database that was
  /// just closed, so it discards itself and hands its caller the one the new
  /// database installs — otherwise [_instance] would hold a dead handle for
  /// the rest of the session and every category read and write, the `other`
  /// fallback included, would hit it.
  static Future<CategoryService> _createOnce(
    Future<AppDatabase> Function() open,
  ) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<CategoryService> creating;
    creating = () async {
      final generation = _generation;
      final lifecycle = DatabaseLifecycle.generation;
      bool overtaken() =>
          generation != _generation ||
          lifecycle != DatabaseLifecycle.generation;

      Future<CategoryService> restart() async {
        if (identical(_initializing, creating)) _initializing = null;
        final service = await _createOnce(open);
        // This construction may already have published the closing
        // database's catalog on its way through `_load`.
        CalendarCategories.updateCache(service._cache);
        return service;
      }

      try {
        final db = await open();
        if (overtaken()) return await restart();
        final service = CategoryService._();
        service._db = db;
        service._dao = db.calendarCategoryDao;
        await service._seedBuiltIns();
        if (overtaken()) return await restart();
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

  /// Drops the cached singleton and clears the static [CalendarCategories]
  /// cache so stale categories from a closed database cannot leak into render
  /// paths before the next [getInstance] republishes them.
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
    CalendarCategories.updateCache(const []);
  }

  /// Unmodifiable, ordered view over the person's own categories — the ones
  /// the Categories page lists, reorders and edits. A partner's are in the
  /// facade alone ([CalendarCategories.partner]).
  List<CalendarCategory> get categories => _own;

  /// Re-reads the table, seeding the built-ins first.
  ///
  /// The seed, not only the load: it is where a built-in tombstoned by a
  /// merge is resurrected ([CalendarCategoryDao.seedMissing]), and without
  /// it that built-in is gone from every picker and filter for the rest of
  /// the session, `other` — the fallback every orphaned event resolves to —
  /// included (R80). It is also how the seed this service skipped during a
  /// bind's initial merge ([_seedBuiltIns]) still runs once the space has
  /// been read: the sync hooks reload the calendar after every pulled page.
  ///
  /// On the write chain like every mutation (invariant 12), because it both
  /// writes — [_seedBuiltIns]'s `seedMissing` batch — and republishes the
  /// facade. Issued once per pulled page, so off the chain it could read
  /// before a user's `create` or `reorder` and publish after it, dropping
  /// that category or that order from [CalendarCategories] until the next
  /// mutation while the grid repaints the stale list on the bumped revision.
  Future<void> reload() => _serialize(() async {
    await _seedBuiltIns();
    await _load();
  });

  // ── Cache load / built-in seed ───────────────────────────────────────

  /// Reads every live row and publishes it, each marked
  /// [CalendarCategory.fromPartner] when its owner is the account this
  /// database reads shared rows from — read here, once per load, so every
  /// refresh (a sync run's reload after a shared read, a pair that ended
  /// and took the partner's rows and that account with it) says it anew.
  ///
  /// The account is asked only when some row names an owner at all: a
  /// database that was never bound pays nothing for it, a bound one one
  /// lookup of `sync_metadata`. The partner's categories hidden on this
  /// phone are read only while one of the partner's is held — one more
  /// statement — and published with the catalogue
  /// ([CalendarCategories.partnerShown]).
  Future<void> _load() async {
    var hidden = const <String>{};
    try {
      final rows = await _dao.getAll();
      final partner = rows.any((row) => row.ownerId != null)
          ? await _db.sharedRowDao.owner()
          : null;
      _cache = List.unmodifiable([
        for (final row in rows)
          _rowToModel(
            row,
            fromPartner: partner != null && row.ownerId == partner,
          ),
      ]);
      if (_cache.any((c) => c.fromPartner)) {
        hidden = await SettingsService.shareHiddenCategoriesOf(_db);
      }
    } catch (e) {
      debugPrint('[CategoryService] Load error: $e');
      _cache = const [];
    }
    _own = List.unmodifiable(_cache.where((c) => !c.fromPartner));
    CalendarCategories.updatePartnerHidden(hidden);
    CalendarCategories.updateCache(_cache);
  }

  /// Inserts the built-in catalog, unless a bind's initial merge is still
  /// running.
  ///
  /// The wait was decided when a seed was stamped with the clock (R76): a
  /// stamp minted after `bind_floor` sits above it, so a device that bound
  /// and touched the calendar before the space's `calendar_categories`
  /// landed seeded the catalog defaults over the other device's renamed,
  /// recoloured or reordered built-ins. A seed now carries the seed stamp
  /// ([CalendarCategoryDao.seedMissing]) and loses to any real edit wherever
  /// it meets one (review F-2); the wait stands as the cheaper order — the
  /// space's rows land first and the seed then inserts only what is still
  /// missing. While `bind_merge_pending` is set the space is
  /// authoritative, so the seed waits for [reload] after the merge. The flag
  /// is never set for a database that does not sync, which keeps every
  /// unbound install on the path it had.
  Future<void> _seedBuiltIns() async {
    if (await _initialMergePending()) return;
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

  /// Whether a bind's first complete pull of every table is still running.
  /// A read failure answers "no": the seed is what a fresh install needs,
  /// and skipping it on a database error would leave the calendar without a
  /// fallback category.
  Future<bool> _initialMergePending() async {
    try {
      return await _db.syncDao.getValue(SyncDao.keyBindMergePending) != null;
    } catch (e) {
      debugPrint('[CategoryService] Bind state error: $e');
      return false;
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
  ///
  /// Returns false when the category is no longer there to edit — a pull that
  /// merged another device's delete of it while its editor was open. The DAO
  /// deliberately leaves a tombstoned row alone rather than resurrecting it,
  /// so the edit is lost, and the caller has to be able to say so instead of
  /// handing a dead category on.
  ///
  /// False, too, for a partner's category, refused before anything is
  /// stamped ([CalendarCategoryDao.updateCategory]): the database would turn
  /// the write into nothing, and "saved" would be a lie.
  Future<bool> updateCategory(CalendarCategory category) {
    return _serialize(() => _persistUpdate(category));
  }

  Future<bool> _persistUpdate(CalendarCategory category) async {
    final written = await _dao.updateCategory(
      CalendarCategoriesCompanion(
        id: Value(category.id),
        name: Value(category.name.trim()),
        colorValue: Value(category.colorValue),
        iconKey: Value(category.iconKey),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _load();
    return written;
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
  ///
  /// An order that names a partner's category writes nothing and answers
  /// false: its row would keep the partner's order while the rest were
  /// numbered around a slot it never took. True once the order is written.
  Future<bool> reorder(List<String> idsInOrder) {
    return _serialize(() => _persistReorder(idsInOrder));
  }

  Future<bool> _persistReorder(List<String> idsInOrder) async {
    if (idsInOrder.any(_isPartners)) return false;
    await _dao.reorder(idsInOrder);
    await _load();
    return true;
  }

  /// Whether the catalogue holds [id] as a partner's category — read inside
  /// the chain's turn, after the previous write's reload.
  static bool _isPartners(String id) =>
      CalendarCategories.byId(id)?.fromPartner ?? false;

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
  ///
  /// Archiving the last visible category is a no-op too: with nothing
  /// visible every picker would open empty and a new event would land in an
  /// archived category. The page disables the item; this is the guard
  /// behind it for a menu built before the second-to-last one was archived.
  ///
  /// A partner's category is neither archived nor restored here: its row is
  /// the partner's, and what shows of it is a choice of its own (§6.4 of
  /// `docs/cloud-share-surfaces-roadmap.md`). Returns whether the flag was
  /// written — false for every no-op and refusal above.
  Future<bool> setHidden(String id, bool hidden) {
    return _serialize(() async {
      final category = CalendarCategories.byId(id);
      if (category == null ||
          category.fromPartner ||
          category.isHidden == hidden) {
        return false;
      }
      if (hidden && CalendarCategories.visible.length <= 1) return false;
      final written = await _dao.updateCategory(
        CalendarCategoriesCompanion(
          id: Value(id),
          isHidden: Value(hidden),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _load();
      return written;
    });
  }

  /// Shares the category [id] with the partner of the pair [pairId], or
  /// makes it private again when null (`docs/cloud-share-surfaces-roadmap.md`
  /// §7): one stamped write of the category's mark, which the next push
  /// carries, with every event in it that has no mark of its own — and
  /// their skipped days and per-day texts — following it, now and whenever
  /// one is added later. Its alerts and profile stay a person's own.
  /// Returns whether the mark was written — false for a category that is
  /// gone or carries it already.
  ///
  /// On the chain like every other write, so it cannot interleave with a
  /// delete of the same category. The catalogue is read again whenever the
  /// table may have changed — the mark written, or a mark set, which clears
  /// every other pair's on other categories even when this one stood — so
  /// [CalendarCategory.sharedByMe] says what the table holds.
  ///
  /// The QA seam's and the tests' entry. The app's share acts
  /// (`ShareService`) cannot run on this chain — one transaction over
  /// several rows would wait on a link queued ahead of it that waits on the
  /// database — so they write the DAO's mark in their own transaction, where
  /// SQLite keeps a delete of the same category out, and call
  /// [refreshShareMarks] after it.
  Future<bool> setShared(String id, String? pairId) => _serialize(() async {
    final wrote = await _dao.setSharedPair(id, pairId);
    if (wrote || pairId != null) await _load();
    return wrote;
  });

  /// Reads the catalogue again on the live instance, on the write chain,
  /// after a mark written elsewhere cleared marks of another pair here
  /// (`CalendarEventDao.setSharedPair`, `FolderDao.setSharedPair`, which
  /// clear all three tables). Never constructs one: with none, the next
  /// [getInstance] reads the table as it is. A construction in flight is
  /// waited for — its load may have read the table before the act wrote,
  /// and the instance it publishes is the one every surface reads.
  static Future<void> refreshShareMarks() async {
    var service = _instance;
    final pending = _initializing;
    if (service == null && pending != null) {
      try {
        final built = await pending;
        // A reset retired it while it was awaited: nothing serves it.
        if (identical(_instance, built)) service = built;
      } catch (_) {
        // The construction's failure is its own caller's to report.
      }
    }
    if (service == null) return;
    await service._serialize(service._load);
  }

  /// Deletes a custom category and reassigns its events and templates to
  /// [reassignTo] in one transaction. Built-ins cannot be deleted — by flag
  /// or by id, since an older archive could restore one as custom — and
  /// neither can the DAO tombstone one. Returns whether the category was
  /// deleted: false for a built-in, an unknown id, a partner's category, or
  /// a row the DAO no longer finds live (a pull removed it meanwhile), so a
  /// caller reports only a delete that happened.
  ///
  /// [reassignTo] is checked inside the chain's turn, against the catalogue
  /// the previous write left: a target that is the category itself, unknown
  /// or a partner's falls back to [kFallbackCategoryId] — the database keeps
  /// an event of this person's out of a partner's category, so the move
  /// would leave the events on the dead id. That catalogue can trail a
  /// pull's tombstone, so the guard that no event lands on a dead id is the
  /// DAO's: [CalendarCategoryDao.tombstoneCascade] re-checks the target
  /// against the live table inside its transaction.
  ///
  /// The category's alerts (**v42**) are tombstoned in the same transaction —
  /// the `CalendarEventService.deleteById` cascade's shape, so the category
  /// and its alerts go as one act on this service's own database — and the
  /// alert facade is republished before the write chain moves on.
  ///
  /// **The cascade's SQL is not the whole act.** It rewrites
  /// `calendar_events.category` and `calendar_event_templates.category`
  /// underneath two caches this service does not own, so both are re-read in
  /// the same link: an event left holding the dead id is written back over
  /// the reassignment by the next save of it (the editor seeds its draft from
  /// the cached event), and a template left holding it stamps the dead id
  /// onto every event built from it. [CalendarEventService.notifyExternalChange]
  /// then tells a bloc already showing the calendar, so the moved events
  /// reach the grid and the agenda without a restart — the shape
  /// `AppSyncApplyHooks` uses after a pulled page; announced `cacheCurrent`
  /// when the event cache took the reassignment, so the bloc rebuilds from
  /// it rather than reading the store again.
  ///
  /// The re-plan is only *requested*, once the chain's link has completed and
  /// without being awaited, so no category write ever queues behind a
  /// platform pass: the moved events no longer inherit anything, and a fire
  /// armed for them must go. It plans from the cache the link just refreshed.
  Future<bool> deleteCategory(
    String id, {
    String reassignTo = kFallbackCategoryId,
  }) async {
    // Whether the event cache took the reassignment: only then may a bloc
    // rebuild from it instead of reading the store again.
    var eventsCurrent = false;
    final deleted = await _serialize(() async {
      final category = CalendarCategories.byId(id);
      if (category == null ||
          category.fromPartner ||
          category.isBuiltIn ||
          _builtInIds.contains(id)) {
        return false;
      }
      final target =
          reassignTo != id &&
              CalendarCategories.byId(reassignTo)?.fromPartner == false
          ? reassignTo
          : kFallbackCategoryId;
      if (!await _dao.tombstoneCascade(id, reassignTo: target)) return false;
      // The delete has committed: a refresh that throws past here must not
      // read as "not deleted", or the sheet stays open on an error for a
      // row already gone and a retry finds nothing live to delete.
      try {
        await _load();
        await EventAlertService.refreshAfterCategoryRemoval();
        await CategoryProfileService.refreshAfterCategoryRemoval();
        eventsCurrent =
            await CalendarEventService.refreshAfterCategoryRemoval();
        await EventTemplateService.refreshAfterCategoryRemoval();
      } catch (e, st) {
        debugPrint('[CategoryService] Refresh after delete error: $e\n$st');
      }
      return true;
    });
    if (deleted) {
      CalendarEventService.notifyExternalChange(cacheCurrent: eventsCurrent);
      unawaited(
        AlertScheduler.reconcileAllQuietly(AlertReconcileReason.eventChanged),
      );
    }
    return deleted;
  }

  /// What [deleteCategory] would touch for [id] — its events, its alerts and
  /// its templates — read from the table the cascade writes, for the delete
  /// sheet to say before the user confirms. Outside the write chain: a read
  /// that waited behind a pending write would only hold the sheet's Delete
  /// disabled longer.
  Future<CategoryDeleteImpact> deleteImpact(String id) => _dao.deleteImpact(id);

  // ── Backup export / import ───────────────────────────────────────────

  /// Every category of the person's own, for the archive helper and any
  /// writer built on it: one another account shares with this one is that
  /// account's, and a backup holds what is mine
  /// (`docs/cloud-sharing-foundations.md` §8) — the event export's rule.
  /// Never the share mark.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    final shared = await _db.sharedRowDao.owner();
    return [
      for (final row in rows)
        if (shared == null || row.ownerId != shared)
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
            if (row.ownerId != null) 'ownerId': row.ownerId,
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
            // value costs the flag and not the whole category row. A built-in
            // id is built-in whatever the archive says: restored as custom it
            // could be deleted, and the fallback with it.
            isBuiltIn: Value(
              _builtInIds.contains(id) ||
                  (map['isBuiltIn'] is bool && map['isBuiltIn'] as bool),
            ),
            isHidden: Value(map['isHidden'] is bool && map['isHidden'] as bool),
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
        debugPrint('[CategoryService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _seedBuiltIns();
    await _load();
  }

  // ── Row ↔ Domain ─────────────────────────────────────────────────────

  /// A partner's archive flag is theirs and is not obeyed here
  /// (`docs/cloud-share-surfaces-roadmap.md` §7.5): what shows of theirs is
  /// this person's own choice.
  CalendarCategory _rowToModel(
    CalendarCategoryRow row, {
    required bool fromPartner,
  }) {
    return CalendarCategory(
      id: row.id,
      name: row.name,
      colorValue: row.colorValue,
      iconKey: row.iconKey,
      sortOrder: row.sortOrder,
      isBuiltIn: row.isBuiltIn,
      isHidden: row.isHidden && !fromPartner,
      fromPartner: fromPartner,
      sharedByMe: row.sharedPair != null && !fromPartner,
    );
  }
}
