import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/daos/filter_preset_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/calendar_filter_preset.dart';
import '../models/calendar_grid_filters.dart';

/// Owns `calendar_filter_presets` — the user's saved calendar filters.
///
/// The [EventTemplateService] shape, minus the static facade: nothing renders
/// a preset during a build. The saved-filter sheet and the filter sheet's save
/// action both `await` this service, which is what the calendar's
/// lazily-constructed-services rule asks of a new surface that does not live
/// under `CalendarPageLoaded`. The cache is kept anyway so a reopened sheet
/// costs no query.
///
/// All CRDT stamping lives in [FilterPresetDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live presets only.
class FilterPresetService {
  static FilterPresetService? _instance;
  static const Uuid _uuid = Uuid();

  /// Upper bound on how many presets one database keeps.
  ///
  /// Not a storage concern — it is a *findability* one: the sheet is a flat
  /// searchable list, and past this many the list stops being the fast path
  /// it exists to be. Enforced at [create], which is the only growth path.
  static const int maxPresets = 50;

  late FilterPresetDao _dao;

  FilterPresetService._();

  static Future<FilterPresetService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO and the real CRDT stamping
  /// against `NativeDatabase.memory()`. Never use it in app code — the
  /// singleton is what the [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<FilterPresetService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<FilterPresetService> _create(AppDatabase db) async {
    final service = FilterPresetService._();
    service._dao = db.filterPresetDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active database. Invoked by [DatabaseLifecycle].
  ///
  /// There is no facade to clear — presets are never read synchronously from a
  /// render path — so the cache dies with the instance.
  static void reset() {
    _instance = null;
  }

  List<CalendarFilterPreset> _cache = const [];

  List<CalendarFilterPreset> get presets => _cache;

  bool get isFull => _cache.length >= maxPresets;

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final rows = await _dao.getAll();
      _cache = List.unmodifiable(rows.map(_rowToPreset));
    } catch (e) {
      debugPrint('[FilterPresetService] Load error: $e');
      _cache = const [];
    }
  }

  /// The preset whose filters are exactly [filters], or `null`.
  ///
  /// Value equality, not identity: what makes two presets the same is what
  /// they filter, and the sheet uses this to show the current filter as
  /// already saved rather than offering to save a duplicate.
  CalendarFilterPreset? matching(CalendarGridFilters filters) {
    for (final preset in _cache) {
      if (preset.filters == filters) return preset;
    }
    return null;
  }

  /// Saves [filters] under [name], appended to the end of the display order.
  ///
  /// Returns `null` when the table is already at [maxPresets] — a refusal the
  /// caller reports, rather than a silent no-op or an exception on a path the
  /// user reached by tapping "Save".
  Future<CalendarFilterPreset?> create({
    required String name,
    required CalendarGridFilters filters,
  }) async {
    if (isFull) return null;
    final id = _uuid.v4();
    final preset = CalendarFilterPreset(
      id: id,
      name: name.trim(),
      filters: filters,
      sortOrder: await _dao.nextSortOrder(),
    );
    await _dao.upsertPreset(_toCompanion(preset));
    await _load();
    return _byId(id) ?? preset;
  }

  /// Writes [preset] back in place — a rename, or a re-save over the current
  /// filters. Keeps its `created_at` and its position.
  Future<void> update(CalendarFilterPreset preset) async {
    await _dao.upsertPreset(_toCompanion(preset));
    await _load();
  }

  Future<void> delete(String id) async {
    await _dao.softDeleteById(id);
    await _load();
  }

  CalendarFilterPreset? _byId(String id) {
    for (final preset in _cache) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live presets only, without CRDT identity. Backups are not a sync
  /// channel: identity is regenerated on restore.
  ///
  /// The filter blob is exported **verbatim**, not re-encoded from a decoded
  /// model: round-tripping through the decoder would silently drop any field a
  /// newer build had written, which is exactly what the forward-compatible
  /// codec exists to preserve.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'name': row.name,
          'filters': row.filters,
          'sortOrder': row.sortOrder,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring [EventTemplateService.importData]. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by
  /// the DAO, so a tombstone never round-trips a restore. Malformed rows are
  /// skipped so one bad entry cannot hide the rest.
  ///
  /// A preset whose blob no longer parses is **not** dropped — it is stored as
  /// written and decodes to "nothing filtered" at read time, which keeps the
  /// user's named row alive instead of deleting it on their behalf.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    final companions = <CalendarFilterPresetsCompanion>[];
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
          CalendarFilterPresetsCompanion(
            id: Value(id),
            name: Value(name),
            filters: Value(map['filters'] is String ? map['filters'] : ''),
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
          ),
        );
      } catch (e) {
        debugPrint('[FilterPresetService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _load();
  }

  CalendarFilterPreset _rowToPreset(CalendarFilterPresetRow row) {
    return CalendarFilterPreset(
      id: row.id,
      name: row.name,
      filters: CalendarGridFilters.decode(row.filters),
      sortOrder: row.sortOrder,
    );
  }

  CalendarFilterPresetsCompanion _toCompanion(CalendarFilterPreset preset) {
    return CalendarFilterPresetsCompanion(
      id: Value(preset.id),
      name: Value(preset.name),
      filters: Value(preset.filters.encode()),
      sortOrder: Value(preset.sortOrder),
    );
  }
}
