import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/calendar_templates.dart';
import '../database/daos/event_template_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/calendar_event.dart';
import '../models/event_template.dart';
import '../models/recurrence_rule_codec.dart';

/// Owns `calendar_event_templates` and publishes it to the synchronous
/// [CalendarTemplates] facade.
///
/// Same shape as [CategoryService]: the whole (small) table is loaded once at
/// [getInstance] and republished after every mutation, so the pickers and the
/// editor's chip strip resolve a template during build with no `await`.
///
/// All CRDT stamping lives in [EventTemplateDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live templates only.
class EventTemplateService {
  static EventTemplateService? _instance;
  static const Uuid _uuid = Uuid();

  late EventTemplateDao _dao;

  EventTemplateService._();

  static Future<EventTemplateService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO, the real CRDT stamping and the
  /// real facade against `NativeDatabase.memory()`. Never use it in app code —
  /// the singleton is what the [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<EventTemplateService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<EventTemplateService> _create(AppDatabase db) async {
    final service = EventTemplateService._();
    service._dao = db.eventTemplateDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static facade, so templates
  /// from a closed database cannot leak into the pickers before the next
  /// [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    CalendarTemplates.resetCache();
  }

  List<EventTemplate> _cache = const [];

  List<EventTemplate> get templates => _cache;

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final rows = await _dao.getAll();
      _cache = List.unmodifiable(rows.map(_rowToTemplate));
    } catch (e) {
      debugPrint('[EventTemplateService] Load error: $e');
      _cache = const [];
    }
    CalendarTemplates.updateCache(_cache);
  }

  /// Creates a template, appending it to the end of the display order.
  ///
  /// The id on [draft] is ignored — a create always mints a fresh one, so a
  /// caller reusing a form model cannot overwrite an existing template by
  /// accident. Returns the stored template, read back through [_load] so the
  /// caller sees exactly what persisted.
  Future<EventTemplate> create(EventTemplate draft) async {
    final id = _uuid.v4();
    await _dao.upsertTemplate(
      _toCompanion(draft, idOverride: id, sortOrder: await _dao.nextSortOrder()),
    );
    await _load();
    return CalendarTemplates.byId(id) ?? draft;
  }

  Future<void> updateTemplate(EventTemplate template) async {
    await _dao.upsertTemplate(_toCompanion(template));
    await _load();
  }

  Future<void> deleteTemplate(String id) async {
    await _dao.softDeleteById(id);
    await _load();
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live templates only, without CRDT identity. Backups are not a sync
  /// channel: identity is regenerated on restore.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'name': row.name,
          'category': row.category,
          'sortOrder': row.sortOrder,
          'ruleKind': row.ruleKind,
          'rulePayload': row.rulePayload,
          'startMinute': row.startMinute,
          'durationMinutes': row.durationMinutes,
          'description': row.description,
          'iconKey': row.iconKey,
          'colorValue': row.colorValue,
          'tintIcon': row.tintIcon,
          'priority': row.priority,
          'retroactive': row.retroactive,
          'countOccurrences': row.countOccurrences,
          'countStyle': row.countStyle,
          'tracksPresence': row.tracksPresence,
          'perOccurrenceDescriptions': row.perOccurrenceDescriptions,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring [CalendarEventService.importData]. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by
  /// the DAO, so a tombstone never round-trips a restore. Malformed rows are
  /// skipped so one bad entry cannot hide the rest.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'];
        final name = map['name'];
        final category = map['category'];
        if (id is! String || name is! String || category is! String) continue;
        final now = DateTime.now();
        final createdAtMs = map['createdAtMs'];
        final updatedAtMs = map['updatedAtMs'];
        await _dao.importTemplate(
          EventTemplatesCompanion(
            id: Value(id),
            name: Value(name),
            category: Value(category),
            sortOrder: Value(_intOr(map['sortOrder'], 0)),
            ruleKind: Value(
              map['ruleKind'] is String
                  ? map['ruleKind'] as String
                  : RecurrenceCodec.kOneTime,
            ),
            rulePayload: Value(map['rulePayload'] as String?),
            startMinute: Value(map['startMinute'] as int?),
            durationMinutes: Value(map['durationMinutes'] as int?),
            description: Value(map['description'] as String?),
            iconKey: Value(map['iconKey'] as String?),
            colorValue: Value(map['colorValue'] as int?),
            tintIcon: Value(_boolOr(map['tintIcon'], true)),
            priority: Value(
              _intOr(map['priority'], kDefaultEventPriority).clamp(
                kMinEventPriority,
                kMaxEventPriority,
              ),
            ),
            retroactive: Value(_boolOr(map['retroactive'], false)),
            countOccurrences: Value(_boolOr(map['countOccurrences'], false)),
            countStyle: Value(
              map['countStyle'] is String
                  ? map['countStyle'] as String
                  : OccurrenceCountStyle.numbered.name,
            ),
            tracksPresence: Value(_boolOr(map['tracksPresence'], false)),
            perOccurrenceDescriptions: Value(
              _boolOr(map['perOccurrenceDescriptions'], false),
            ),
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
        debugPrint('[EventTemplateService] Import row error: $e');
      }
    }
    await _load();
  }

  /// Clears every template. Used when restoring a backup that carried
  /// categories but no template key: the category import wipes and reinserts,
  /// so keeping the previous database's templates would strand them against a
  /// category id space that no longer exists.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    await _load();
  }

  static int _intOr(Object? value, int fallback) =>
      value is int ? value : fallback;

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  EventTemplate _rowToTemplate(EventTemplateRow row) {
    return EventTemplate(
      id: row.id,
      name: row.name,
      categoryId: row.category,
      rule: RecurrenceCodec.decode(row.ruleKind, row.rulePayload),
      time: _decodeTime(row.startMinute, row.durationMinutes),
      description: row.description,
      iconKey: row.iconKey,
      colorValue: row.colorValue,
      tintIcon: row.tintIcon,
      priority: row.priority.clamp(kMinEventPriority, kMaxEventPriority),
      retroactive: row.retroactive,
      countOccurrences: row.countOccurrences,
      countStyle: OccurrenceCountStyle.values.firstWhere(
        (style) => style.name == row.countStyle,
        orElse: () => OccurrenceCountStyle.numbered,
      ),
      tracksPresence: row.tracksPresence,
      perOccurrenceDescriptions: row.perOccurrenceDescriptions,
      sortOrder: row.sortOrder,
    );
  }

  /// Mirrors `CalendarEventService._decodeTime`: a null or out-of-range start
  /// minute means all-day, and a non-positive duration means "no end".
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

  EventTemplatesCompanion _toCompanion(
    EventTemplate template, {
    String? idOverride,
    int? sortOrder,
  }) {
    final time = template.time;
    return EventTemplatesCompanion(
      id: Value(idOverride ?? template.id),
      name: Value(template.name),
      category: Value(template.categoryId),
      sortOrder: Value(sortOrder ?? template.sortOrder),
      ruleKind: Value(RecurrenceCodec.kindOf(template.rule)),
      rulePayload: Value(RecurrenceCodec.payloadOf(template.rule)),
      startMinute: Value(time?.startMinute),
      durationMinutes: Value(time?.durationMinutes),
      description: Value(template.description),
      iconKey: Value(template.iconKey),
      colorValue: Value(template.colorValue),
      tintIcon: Value(template.tintIcon),
      priority: Value(template.priority),
      retroactive: Value(template.retroactive),
      countOccurrences: Value(template.countOccurrences),
      countStyle: Value(template.countStyle.name),
      tracksPresence: Value(template.tracksPresence),
      perOccurrenceDescriptions: Value(template.perOccurrenceDescriptions),
    );
  }
}
