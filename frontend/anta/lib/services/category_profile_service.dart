import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/category_kinds.dart';
import '../constants/category_profiles.dart';
import '../database/daos/category_profile_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/category_profile.dart';
import 'sync/sync_table_binding.dart';
import 'sync/tables/category_profile_wire.dart';

/// Owns the rows of `calendar_category_profiles` and publishes them to the
/// synchronous [CategoryProfiles] facade — the [EventAlertService] shape:
/// loaded at [getInstance], published with it, and awaited in the
/// calendar's `Future.wait` rather than held in GetIt, so a database switch
/// can never hand a reader a service bound to the closed database.
///
/// The facade is read while rows and folds are being built, and an
/// unconfigured read is silent — every category would count as unprofiled —
/// which is why the calendar waits for this before its first frame.
///
/// All CRDT stamping and the one-live-row-per-category convergence live in
/// [CategoryProfileDao]; this layer maps rows to [CategoryProfile] and back.
class CategoryProfileService {
  static CategoryProfileService? _instance;

  /// The first construction while it is in flight, so callers racing it
  /// share one load — and so a refresh can wait for an instance that is
  /// still reading the table instead of missing it.
  static Future<CategoryProfileService>? _initializing;

  /// Bumped by every [reset], so a construction can tell it was overtaken
  /// by one that no `DatabaseLifecycle` switch announced — a restore's.
  static int _generation = 0;

  late AppDatabase _db;
  late CategoryProfileDao _dao;

  /// Tail of the serialized write chain, or null when nothing is in flight —
  /// see [_serialize].
  Future<void>? _writes;

  CategoryProfileService._();

  static Future<CategoryProfileService> getInstance() =>
      _createOnce(AppDatabase.getInstance);

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup, so tests run the
  /// real DAO and facade against `NativeDatabase.memory()`. Never use it in
  /// app code.
  @visibleForTesting
  static Future<CategoryProfileService> forTesting(AppDatabase db) {
    final existing = _instance;
    if (existing != null) {
      // Returning a singleton bound to some *other* database silently runs the
      // caller against the previous test's data instead of failing.
      assert(
        identical(existing._db, db),
        'CategoryProfileService.forTesting: a singleton bound to a different '
        'AppDatabase is already installed. Call CategoryProfileService.reset() '
        'in tearDown, or this test runs against the previous one.',
      );
      return Future.value(existing);
    }
    return _createOnce(() async => db);
  }

  /// One construction at a time, and never one a database switch overtook —
  /// [CategoryService]'s guard.
  ///
  /// A construction the switch overtook read the database that is closing,
  /// so it discards itself and hands its caller the one the new database
  /// installs. Its read is published only once it is known not to be
  /// overtaken, so the closing database's profiles never reach the facade
  /// after the reset cleared it.
  static Future<CategoryProfileService> _createOnce(
    Future<AppDatabase> Function() open,
  ) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<CategoryProfileService> creating;
    creating = () async {
      final generation = _generation;
      final lifecycle = DatabaseLifecycle.generation;
      bool overtaken() =>
          generation != _generation ||
          lifecycle != DatabaseLifecycle.generation;

      Future<CategoryProfileService> restart() {
        if (identical(_initializing, creating)) _initializing = null;
        return _createOnce(open);
      }

      try {
        final db = await open();
        if (overtaken()) return await restart();
        final service = CategoryProfileService._();
        service._db = db;
        service._dao = db.categoryProfileDao;
        final read = await service._read();
        if (overtaken()) return await restart();
        service._adopt(read);
        _instance = service;
        DatabaseLifecycle.registerResetHandler(reset);
        return service;
      } finally {
        if (identical(_initializing, creating)) _initializing = null;
      }
    }();
    return _initializing = creating;
  }

  /// Drops the cached singleton and clears the facade, so a profile from a
  /// closed database cannot count a category of the next one before the
  /// next [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
    CategoryProfiles.resetCache();
  }

  /// The working copy behind the facade, one profile per category. Replaced
  /// whole, never cleared in place, so no reader or write between a load's
  /// awaits sees it half-built.
  Map<String, CategoryProfile> _byCategory = const {};

  /// Re-reads the table and republishes, on the write chain: a reload's
  /// read must not land before a save and its publish after it.
  Future<void> reload() => _serialize(_load);

  Future<void> _load() async => _adopt(await _read());

  Future<Map<String, CategoryProfile>> _read() async {
    final byCategory = <String, CategoryProfile>{};
    try {
      for (final row in await _dao.getAllActive()) {
        // Last wins: the DAO orders a category's rows by stamp, so a second
        // live row a merge left behind yields to the newer one.
        byCategory[row.categoryId] = _rowToProfile(row);
      }
    } catch (e) {
      debugPrint('[CategoryProfileService] Load error: $e');
      return const {};
    }
    return byCategory;
  }

  void _adopt(Map<String, CategoryProfile> byCategory) {
    _byCategory = byCategory;
    CategoryProfiles.updateCache(byCategory);
  }

  /// Runs [write] after every write issued before it, [CategoryService]'s
  /// chain: a save, a clear, a reload or a restore never interleaves with
  /// another, so each publishes from the table as the one before left it.
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

  /// Makes [draft] its category's profile and returns it as stored.
  ///
  /// Profile ids are this service's: callers never mint one, and the id
  /// [draft] carries is ignored. An existing profile keeps its own, so an
  /// edit moves one row forward on every device; a first profile — or one
  /// after a [clear] — takes a fresh id, so it can never land on a row
  /// another category holds. An unchanged save writes nothing.
  Future<CategoryProfile> save(CategoryProfile draft) {
    return _serialize(() async {
      final current = await _dao.getActiveForCategory(draft.categoryId);
      final companion = _toCompanion(
        draft,
      ).copyWith(id: Value(current?.id ?? const Uuid().v4()));
      await _dao.upsertForCategory(companion);
      final row = await _dao.getActiveForCategory(draft.categoryId);
      final stored = row == null ? draft : _rowToProfile(row);
      _adopt({..._byCategory, draft.categoryId: stored});
      return stored;
    });
  }

  /// Removes [categoryId]'s profile, so it counts as unprofiled again. A
  /// tombstone, not a delete: another device must learn of it.
  Future<void> clear(String categoryId) {
    return _serialize(() async {
      await _dao.tombstoneForCategory(categoryId);
      _adopt({..._byCategory}..remove(categoryId));
    });
  }

  /// Republishes after `CategoryService.deleteCategory` tombstoned the
  /// category's profile inside its own transaction.
  ///
  /// The [EventAlertService.refreshAfterCategoryRemoval] rule: touches only
  /// a live or loading instance. With neither, nothing has been published,
  /// and resolving one here would bind it to whatever database
  /// [AppDatabase.getInstance] opens, not the one the category service
  /// holds.
  static Future<void> refreshAfterCategoryRemoval() => _reloadLive();

  /// Republishes after a sync pull merged profile rows, on the same terms as
  /// [refreshAfterCategoryRemoval]: the sync path never creates the
  /// service, since the next [getInstance] reads the merged table anyway.
  static Future<void> refreshAfterSync() => _reloadLive();

  static Future<void> _reloadLive() async {
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
    await service?.reload();
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// One live profile per category — the one the facade serves — as its
  /// [CategoryProfileWire] map, the sync push's byte for byte: a value this
  /// build cannot read leaves as it was stored. The CRDT identity stays
  /// behind: a backup is not a sync channel.
  Future<List<Map<String, dynamic>>> exportCategoryProfiles() async {
    final newest = <String, CategoryProfileRow>{};
    for (final row in await _dao.getAllActive()) {
      newest[row.categoryId] = row;
    }
    return [for (final row in newest.values) CategoryProfileWire.encode(row)];
  }

  /// Wipe-then-reinsert, the category alerts' shape: audit timestamps
  /// preserved, identity stamped fresh by the DAO, every column as the
  /// archive holds it.
  ///
  /// Every row is decoded before anything is wiped, and the wipe and the
  /// insert are one transaction, so a failure leaves this database's
  /// profiles as they were. A row whose category is not in
  /// [knownCategoryIds] is dropped rather than kept as an orphan a later
  /// category could never claim, and so is a row with no usable identity or
  /// a column of the wrong type. The archive is still the authority when
  /// every row is dropped: the table ends empty, as an archive without
  /// profiles leaves it, because the restore replaced the categories they
  /// were keyed to. Returns how many were dropped, for the restore's log.
  Future<int> importCategoryProfiles(
    List<dynamic> rows, {
    required Set<String> knownCategoryIds,
  }) {
    return _serialize(() async {
      final companions = <CalendarCategoryProfilesCompanion>[];
      var dropped = 0;
      for (final raw in rows) {
        try {
          if (raw is! Map) {
            dropped++;
            continue;
          }
          // An archive written by hand or by an older build may carry no
          // dates; the restore stamps now, the category alerts' rule.
          final map = Map<String, Object?>.of(raw.cast<String, Object?>());
          map[CategoryProfileKeys.createdAt] ??=
              DateTime.now().millisecondsSinceEpoch;
          map[CategoryProfileKeys.updatedAt] ??=
              map[CategoryProfileKeys.createdAt];
          final companion = CategoryProfileWire.decode(
            WireFields.row(CategoryProfileWire.table, map),
          );
          if (companion.id.value.isEmpty ||
              !knownCategoryIds.contains(companion.categoryId.value)) {
            dropped++;
            continue;
          }
          companions.add(companion);
        } catch (e) {
          debugPrint('[CategoryProfileService] Import row error: $e');
          dropped++;
        }
      }
      await _dao.replaceAll(companions);
      await _load();
      return dropped;
    });
  }

  /// Clears every profile, tombstones included, for a restore whose
  /// categories replace this database's: a profile kept from here would
  /// attach to whatever category now holds its id.
  Future<void> clearCategoryProfilesForImport() {
    return _serialize(() async {
      await _dao.deleteAll();
      await _load();
    });
  }

  // ── Row ↔ Domain ─────────────────────────────────────────────────────

  static CategoryProfile _rowToProfile(CategoryProfileRow row) {
    final nominal = row.nominalMinutes;
    return CategoryProfile(
      id: row.id,
      categoryId: row.categoryId,
      kind: CategoryKind.parse(row.kind) ?? CategoryKind.custom,
      area: LifeArea.parse(row.area),
      measure: ReportMeasure.parse(row.measure),
      nominalMinutes: nominal != null && nominal > 0 ? nominal : null,
      markVerb: row.markVerb,
      marksNew: row.marksNew,
      assumeAbsentNew: row.assumeAbsentNew,
      countsHours: row.countsHours,
      target: ReportTarget.fromJson({
        CategoryProfileKeys.targetKind: row.targetKind,
        CategoryProfileKeys.targetValue: row.targetValue,
        CategoryProfileKeys.targetPeriod: row.targetPeriod,
      }),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Every override as an explicit value, `null` included: the DAO's
  /// in-place update writes only present columns, so an absent one would
  /// keep an override the owner just cleared.
  static CalendarCategoryProfilesCompanion _toCompanion(
    CategoryProfile profile,
  ) {
    final target = profile.target;
    return CalendarCategoryProfilesCompanion(
      id: Value(profile.id),
      categoryId: Value(profile.categoryId),
      kind: Value(profile.kind.name),
      area: Value(profile.area?.name),
      measure: Value(profile.measure?.name),
      nominalMinutes: Value(profile.nominalMinutes),
      markVerb: Value(profile.markVerb),
      marksNew: Value(profile.marksNew),
      assumeAbsentNew: Value(profile.assumeAbsentNew),
      countsHours: Value(profile.countsHours),
      targetKind: Value(target?.kind.name),
      targetValue: Value(target?.value),
      targetPeriod: Value(target?.period?.name),
    );
  }
}
