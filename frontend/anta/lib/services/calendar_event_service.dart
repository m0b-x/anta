import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/calendar_event_dao.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';
import 'event_occurrence_service.dart';
import 'event_presence_service.dart';

/// Persists custom calendar events via Drift and exposes a synchronous
/// in-memory cache so `CalendarBloc.eventsForDay` stays O(N) over a
/// pre-loaded list without async hops in the table-calendar event loader.
class CalendarEventService {
  static CalendarEventService? _instance;

  late AppDatabase _db;
  late CalendarEventDao _dao;
  List<CalendarEvent> _cache = const [];

  CalendarEventService._();

  static Future<CalendarEventService> getInstance() async {
    if (_instance != null) return _instance!;
    final service = CalendarEventService._();
    service._db = await AppDatabase.getInstance();
    service._dao = service._db.calendarEventDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  static void reset() {
    _instance = null;
  }

  List<CalendarEvent> get events => _cache;

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final rows = await _dao.getAll();
      _cache = List.unmodifiable(rows.map(_rowToEvent));
    } catch (e) {
      debugPrint('[CalendarEventService] Load error: $e');
      _cache = const [];
    }
  }

  Future<void> upsert(CalendarEvent event) async {
    // Normalize both bounds to date-only UTC so equality and ordering are
    // calendar-day stable across timezones.
    final normalizedEnd = event.endDate == null
        ? event
        : event.copyWith(endDate: _dateOnlyUtc(event.endDate!));
    final normalized = normalizedEnd.copyWith(
      startDate: _dateOnlyUtc(event.startDate),
    );
    final now = DateTime.now();
    await _dao.upsert(_eventToCompanion(normalized, updatedAt: now));
    _cache = List.unmodifiable([
      for (final e in _cache)
        if (e.id != normalized.id) e,
      normalized,
    ]);
  }

  /// Deletes the event and cascades to its per-occurrence description and
  /// absence rows in one transaction — nothing else references an event id, so
  /// leaving them behind would strand rows no surface can reach or clean up.
  /// Composed here rather than in the bloc, mirroring
  /// `CategoryService.deleteCategory`.
  ///
  /// Since v28 all three tables **tombstone together**: the event (v27), its
  /// absence marks (v27) and its per-day descriptions (v28), one statement
  /// each, so the delete carries a single merge order instead of the children
  /// outliving the parent or vanishing without one. Nothing above this method
  /// can tell a tombstone from a delete — the cache patch, the two facade
  /// refreshes and the bloc's own cache removal are unchanged.
  ///
  /// Deleting an event is the **only** thing that removes absence or
  /// description rows in bulk: turning either flag off or changing the rule
  /// leaves them dormant, because the stored delta is the durable record of a
  /// deliberate act and flipping the toggle back on must restore every one.
  Future<void> deleteById(String id) async {
    await _db.transaction(() async {
      await _dao.softDeleteById(id);
      await _db.eventAbsenceDao.tombstoneForEvent(id);
      await _db.eventOccurrenceDao.tombstoneForEvent(id);
    });
    _cache = List.unmodifiable(_cache.where((e) => e.id != id));
    await _refreshOccurrences();
    await _refreshPresence();
  }

  /// Removes every custom calendar event, cascading to their occurrence
  /// overrides and absence marks. Public holidays live in a separate table and
  /// are untouched.
  Future<void> deleteAll() async {
    await _db.transaction(() async {
      await _dao.deleteAll();
      await _db.eventOccurrenceDao.deleteAll();
      await _db.eventAbsenceDao.deleteAll();
    });
    _cache = const [];
    await _refreshOccurrences();
    await _refreshPresence();
  }

  /// Republishes the occurrence facade after a cascade. Tolerates the service
  /// not being constructed yet — the cascade already hit the table, and the
  /// facade populates from it on first load either way.
  Future<void> _refreshOccurrences() async {
    try {
      final service = await EventOccurrenceService.getInstance();
      await service.refreshAfterEventRemoval();
    } catch (e) {
      debugPrint('[CalendarEventService] Occurrence refresh error: $e');
    }
  }

  /// The presence twin of [_refreshOccurrences], with the same tolerance.
  Future<void> _refreshPresence() async {
    try {
      final service = await EventPresenceService.getInstance();
      await service.refreshAfterEventRemoval();
    } catch (e) {
      debugPrint('[CalendarEventService] Presence refresh error: $e');
    }
  }

  // ── Backup export / import ────────────────────────────────────────────

  /// Snapshot of every event row for inclusion in a full-app backup.
  /// Each entry mirrors the on-disk row shape so the import path can
  /// round-trip without re-deriving any value.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'title': row.title,
          'category': row.category,
          'startDateMs': row.startDate.millisecondsSinceEpoch,
          'allDay': row.allDay,
          'iconKey': row.iconKey,
          'ruleKind': row.ruleKind,
          'rulePayload': row.rulePayload,
          'endDateMs': row.endDate?.millisecondsSinceEpoch,
          'startMinute': row.startMinute,
          'durationMinutes': row.durationMinutes,
          'description': row.description,
          'noteId': row.noteId,
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

  /// Replaces every persisted event with the contents of [data] (the list
  /// produced by [exportData]). Tolerates missing/malformed entries: bad
  /// rows are skipped, the rest still imports.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'] as String?;
        final title = map['title'] as String?;
        final category = map['category'] as String?;
        final startMs = map['startDateMs'];
        final ruleKind = map['ruleKind'] as String?;
        if (id == null ||
            title == null ||
            category == null ||
            startMs is! int ||
            ruleKind == null) {
          continue;
        }
        final createdMs = map['createdAtMs'] is int
            ? map['createdAtMs'] as int
            : startMs;
        final updatedMs = map['updatedAtMs'] is int
            ? map['updatedAtMs'] as int
            : createdMs;
        final endMs = map['endDateMs'];
        await _dao.upsert(
          CalendarEventsCompanion(
            id: Value(id),
            title: Value(title),
            category: Value(category),
            startDate: Value(
              DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true),
            ),
            allDay: Value(map['allDay'] as bool? ?? true),
            iconKey: Value(map['iconKey'] as String?),
            ruleKind: Value(ruleKind),
            rulePayload: Value(map['rulePayload'] as String?),
            endDate: endMs is int
                ? Value(DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true))
                : const Value.absent(),
            startMinute: map['startMinute'] is int
                ? Value(map['startMinute'] as int)
                : const Value.absent(),
            durationMinutes: map['durationMinutes'] is int
                ? Value(map['durationMinutes'] as int)
                : const Value.absent(),
            description: map['description'] is String
                ? Value(map['description'] as String)
                : const Value.absent(),
            noteId: map['noteId'] is String
                ? Value(map['noteId'] as String)
                : const Value.absent(),
            colorValue: map['colorValue'] is int
                ? Value(map['colorValue'] as int)
                : const Value.absent(),
            tintIcon: map['tintIcon'] is bool
                ? Value(map['tintIcon'] as bool)
                : const Value.absent(),
            priority: map['priority'] is int
                ? Value(map['priority'] as int)
                : const Value.absent(),
            // Absent in pre-v19 backups: the column default (false) is
            // exactly the forward-only behaviour those events had.
            retroactive: map['retroactive'] is bool
                ? Value(map['retroactive'] as bool)
                : const Value.absent(),
            // Absent in pre-v20 backups: default false = no count shown,
            // which is what those events displayed.
            countOccurrences: map['countOccurrences'] is bool
                ? Value(map['countOccurrences'] as bool)
                : const Value.absent(),
            countStyle: map['countStyle'] is String
                ? Value(
                    OccurrenceCountStyle.fromName(
                      map['countStyle'] as String,
                    ).name,
                  )
                : const Value.absent(),
            // Absent in pre-v26 backups: default false = presence untracked,
            // which is the only state those events could have been in.
            tracksPresence: map['tracksPresence'] is bool
                ? Value(map['tracksPresence'] as bool)
                : const Value.absent(),
            // Absent in pre-v28 backups: no archive ever carried the intent,
            // because the global setting it replaced was never in
            // `BackupService._exportSettings`'s allowlist. Default false means
            // those events restore with one shared description and their
            // imported day rows dormant — enabling an event brings them back.
            perOccurrenceDescriptions:
                map['perOccurrenceDescriptions'] is bool
                ? Value(map['perOccurrenceDescriptions'] as bool)
                : const Value.absent(),
            createdAt: Value(
              DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true),
            ),
            updatedAt: Value(
              DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true),
            ),
          ),
        );
      } catch (e) {
        debugPrint('[CalendarEventService] Import row error: $e');
      }
    }
    await _load();
  }

  // ── Row ↔ Domain mapping ──────────────────────────────────────────────

  CalendarEvent _rowToEvent(CalendarEventRow row) {
    return CalendarEvent(
      id: row.id,
      title: row.title,
      categoryId: row.category,
      startDate: _dateOnlyUtc(row.startDate),
      iconKey: row.iconKey,
      endDate: row.endDate == null ? null : _dateOnlyUtc(row.endDate!),
      time: _decodeTime(row.startMinute, row.durationMinutes),
      description: row.description,
      noteId: row.noteId,
      colorValue: row.colorValue,
      tintIcon: row.tintIcon,
      priority: row.priority.clamp(kMinEventPriority, kMaxEventPriority),
      retroactive: row.retroactive,
      countOccurrences: row.countOccurrences,
      countStyle: OccurrenceCountStyle.fromName(row.countStyle),
      tracksPresence: row.tracksPresence,
      perOccurrenceDescriptions: row.perOccurrenceDescriptions,
      rule: _decodeRule(row.ruleKind, row.rulePayload),
    );
  }

  /// Reconstructs an [EventTime] from the persisted columns. The stored
  /// `all_day` boolean is intentionally ignored — [CalendarEvent.allDay]
  /// is derived from the presence of [EventTime] so we can never end up
  /// with an inconsistent pair on read.
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

  /// Drift returns `DateTime` in local time when reading an int-epoch
  /// column, so naive `.year/.month/.day` extraction after we wrote
  /// `DateTime.utc(...)` can shift the date by one day in non-UTC zones.
  /// Recover the original UTC date via the epoch milliseconds.
  static DateTime _dateOnlyUtc(DateTime value) {
    final asUtc = DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
    return DateTime.utc(asUtc.year, asUtc.month, asUtc.day);
  }

  CalendarEventsCompanion _eventToCompanion(
    CalendarEvent event, {
    required DateTime updatedAt,
  }) {
    final time = event.time;
    return CalendarEventsCompanion(
      id: Value(event.id),
      title: Value(event.title),
      category: Value(event.categoryId),
      startDate: Value(event.startDate),
      // `all_day` is a denormalized mirror of `time == null`, kept around
      // so SQL filters like `WHERE all_day = 0` stay cheap. Never read
      // back as truth — see [_decodeTime].
      allDay: Value(event.allDay),
      iconKey: Value(event.iconKey),
      ruleKind: Value(_ruleKind(event.rule)),
      rulePayload: Value(_rulePayload(event.rule)),
      endDate: Value(event.endDate),
      startMinute: Value(time?.startMinute),
      durationMinutes: Value(time?.durationMinutes),
      description: Value(event.description),
      noteId: Value(event.noteId),
      colorValue: Value(event.colorValue),
      tintIcon: Value(event.tintIcon),
      priority: Value(event.priority),
      retroactive: Value(event.retroactive),
      countOccurrences: Value(event.countOccurrences),
      countStyle: Value(event.countStyle.name),
      tracksPresence: Value(event.tracksPresence),
      perOccurrenceDescriptions: Value(event.perOccurrenceDescriptions),
      createdAt: Value(updatedAt),
      updatedAt: Value(updatedAt),
    );
  }

  // ── Recurrence serialization ──────────────────────────────────────────

  static const String _kOneTime = 'oneTime';
  static const String _kSpecificDates = 'specificDates';
  static const String _kDaily = 'daily';
  static const String _kWeekly = 'weekly';
  static const String _kMonthly = 'monthly';
  static const String _kYearly = 'yearly';
  static const String _kWorkdays = 'workdays';
  static const String _kWeekends = 'weekends';
  static const String _kHolidaysOnly = 'holidaysOnly';

  String _ruleKind(RecurrenceRule rule) {
    return switch (rule) {
      OneTimeRecurrence() => _kOneTime,
      SpecificDatesRecurrence() => _kSpecificDates,
      DailyRecurrence() => _kDaily,
      WeeklyRecurrence() => _kWeekly,
      MonthlyRecurrence() => _kMonthly,
      YearlyRecurrence() => _kYearly,
      WorkdaysRecurrence() => _kWorkdays,
      WeekendsRecurrence() => _kWeekends,
      PublicHolidaysOnlyRecurrence() => _kHolidaysOnly,
    };
  }

  String? _rulePayload(RecurrenceRule rule) {
    final map = <String, Object>{};
    if (rule is WeeklyRecurrence) {
      final days = rule.weekdays.toList()..sort();
      map['weekdays'] = days;
    }
    if (rule is SpecificDatesRecurrence) {
      final ms = rule.dates.map((d) => d.millisecondsSinceEpoch).toList()
        ..sort();
      map['dates'] = ms;
    }
    final interval = _intervalOf(rule);
    if (interval > 1) map['interval'] = interval;
    return map.isEmpty ? null : jsonEncode(map);
  }

  int _intervalOf(RecurrenceRule rule) => switch (rule) {
    DailyRecurrence(:final interval) => interval,
    WeeklyRecurrence(:final interval) => interval,
    MonthlyRecurrence(:final interval) => interval,
    YearlyRecurrence(:final interval) => interval,
    _ => 1,
  };

  /// Reads the optional `interval` from a rule payload, defaulting to 1 for
  /// legacy payloads (which never carried it) or any malformed value.
  int _decodeInterval(String? payload) {
    if (payload == null || payload.isEmpty) return 1;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['interval'] is int) {
        final value = decoded['interval'] as int;
        if (value >= 1) return value;
      }
    } catch (e) {
      debugPrint('[CalendarEventService] Bad interval payload: $e');
    }
    return 1;
  }

  RecurrenceRule _decodeRule(String kind, String? payload) {
    switch (kind) {
      case _kSpecificDates:
        final dates = _decodeDates(payload);
        if (dates.isEmpty) return const OneTimeRecurrence();
        return SpecificDatesRecurrence(dates: dates);
      case _kDaily:
        return DailyRecurrence(interval: _decodeInterval(payload));
      case _kWeekly:
        final days = <int>{};
        if (payload != null && payload.isNotEmpty) {
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map && decoded['weekdays'] is List) {
              for (final raw in decoded['weekdays'] as List) {
                if (raw is int && raw >= 1 && raw <= 7) days.add(raw);
              }
            }
          } catch (e) {
            debugPrint('[CalendarEventService] Bad weekly payload: $e');
          }
        }
        return WeeklyRecurrence(
          weekdays: days,
          interval: _decodeInterval(payload),
        );
      case _kMonthly:
        return MonthlyRecurrence(interval: _decodeInterval(payload));
      case _kYearly:
        return YearlyRecurrence(interval: _decodeInterval(payload));
      case _kWorkdays:
        return const WorkdaysRecurrence();
      case _kWeekends:
        return const WeekendsRecurrence();
      case _kHolidaysOnly:
        return const PublicHolidaysOnlyRecurrence();
      case _kOneTime:
      default:
        return const OneTimeRecurrence();
    }
  }

  /// Parses the explicit one-off date set from a `specificDates` payload,
  /// normalizing each entry to date-only UTC. Malformed/missing entries are
  /// skipped; an empty result lets [_decodeRule] fall back to one-time.
  Set<DateTime> _decodeDates(String? payload) {
    final dates = <DateTime>{};
    if (payload == null || payload.isEmpty) return dates;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['dates'] is List) {
        for (final raw in decoded['dates'] as List) {
          if (raw is int) {
            dates.add(
              _dateOnlyUtc(
                DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[CalendarEventService] Bad specificDates payload: $e');
    }
    return dates;
  }
}
