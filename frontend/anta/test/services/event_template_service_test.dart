import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_template_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real CRDT stamping and the real facade against
/// `NativeDatabase.memory()`, the way the `test/database` suite does.
///
/// Two things carry the feature and neither is obvious from the UI: the facade
/// must be republished after every mutation (a picker that reads a stale cache
/// offers a template the user just deleted), and `buildEvent` must reproduce
/// every field — a template that silently drops `tracksPresence` produces
/// events that look right and behave wrong.
void main() {
  late AppDatabase db;
  late EventTemplateService service;

  setUp(() async {
    EventTemplateService.reset();
    db = await openTestDatabase();
    service = await EventTemplateService.forTesting(db);
  });

  tearDown(() async {
    EventTemplateService.reset();
    await db.close();
  });

  EventTemplate draft({
    String name = 'Push day',
    String categoryId = 'gym',
    RecurrenceRule rule = const OneTimeRecurrence(),
    EventTime? time,
    String? description,
    String? iconKey,
    int? colorValue,
    int priority = kDefaultEventPriority,
    bool tracksPresence = false,
    bool perOccurrenceDescriptions = false,
    bool countOccurrences = false,
    bool retroactive = false,
  }) {
    return EventTemplate(
      id: '',
      name: name,
      categoryId: categoryId,
      rule: rule,
      time: time,
      description: description,
      iconKey: iconKey,
      colorValue: colorValue,
      priority: priority,
      tracksPresence: tracksPresence,
      perOccurrenceDescriptions: perOccurrenceDescriptions,
      countOccurrences: countOccurrences,
      retroactive: retroactive,
    );
  }

  group('create', () {
    test('mints an id and publishes to the facade', () async {
      final created = await service.create(draft());

      expect(created.id, isNotEmpty);
      expect(CalendarTemplates.byId(created.id), created);
      expect(CalendarTemplates.all, hasLength(1));
    });

    test('ignores the draft id so a form model cannot overwrite a row', () async {
      final first = await service.create(draft(name: 'Push day'));

      final second = await service.create(
        first.copyWith(name: 'Leg day'),
      );

      expect(second.id, isNot(first.id));
      expect(CalendarTemplates.all, hasLength(2));
    });

    test('appends to the end of the display order', () async {
      final first = await service.create(draft(name: 'First'));
      final second = await service.create(draft(name: 'Second'));

      expect(second.sortOrder, greaterThan(first.sortOrder));
      expect(
        [for (final t in CalendarTemplates.all) t.name],
        ['First', 'Second'],
      );
    });

    test('round-trips every field through the database', () async {
      final created = await service.create(
        draft(
          name: 'Leg day',
          categoryId: 'cardio',
          rule: const WeeklyRecurrence(
            weekdays: {DateTime.monday, DateTime.thursday},
            interval: 2,
          ),
          time: const EventTime(startMinute: 18 * 60, durationMinutes: 90),
          description: 'squats, then hinge',
          iconKey: 'directions_run',
          colorValue: 0xFF123456,
          priority: kMinEventPriority,
          tracksPresence: true,
          perOccurrenceDescriptions: true,
          countOccurrences: true,
          retroactive: true,
        ),
      );

      final stored = CalendarTemplates.byId(created.id)!;
      expect(stored.name, 'Leg day');
      expect(stored.categoryId, 'cardio');
      expect(
        stored.rule,
        const WeeklyRecurrence(
          weekdays: {DateTime.monday, DateTime.thursday},
          interval: 2,
        ),
      );
      expect(
        stored.time,
        const EventTime(startMinute: 18 * 60, durationMinutes: 90),
      );
      expect(stored.description, 'squats, then hinge');
      expect(stored.iconKey, 'directions_run');
      expect(stored.colorValue, 0xFF123456);
      expect(stored.priority, kMinEventPriority);
      expect(stored.tracksPresence, isTrue);
      expect(stored.perOccurrenceDescriptions, isTrue);
      expect(stored.countOccurrences, isTrue);
      expect(stored.retroactive, isTrue);
    });

    test('a null time round-trips as all-day', () async {
      final created = await service.create(draft());

      expect(CalendarTemplates.byId(created.id)!.time, isNull);
    });
  });

  group('update and delete', () {
    test('an update republishes the facade', () async {
      final created = await service.create(draft(name: 'Push day'));

      await service.updateTemplate(created.copyWith(name: 'Pull day'));

      expect(CalendarTemplates.byId(created.id)!.name, 'Pull day');
      expect(CalendarTemplates.all, hasLength(1));
    });

    test('a delete drops it from the facade but keeps the tombstone', () async {
      final created = await service.create(draft());

      await service.deleteTemplate(created.id);

      expect(CalendarTemplates.byId(created.id), isNull);
      expect(CalendarTemplates.all, isEmpty);
      // The row survives for a future merge; only the facade forgets it.
      expect(await db.select(db.eventTemplates).get(), hasLength(1));
    });
  });

  group('reset', () {
    test('clears the facade so another database cannot leak in', () async {
      await service.create(draft());
      expect(CalendarTemplates.all, isNotEmpty);

      EventTemplateService.reset();

      expect(CalendarTemplates.all, isEmpty);
    });
  });

  group('backup', () {
    test('export/import round-trips a template', () async {
      final created = await service.create(
        draft(
          name: 'Leg day',
          rule: const DailyRecurrence(interval: 3),
          time: const EventTime(startMinute: 420),
          tracksPresence: true,
        ),
      );
      final exported = await service.exportData();

      await service.clearAllForImport();
      expect(CalendarTemplates.all, isEmpty);
      await service.importData(exported);

      final restored = CalendarTemplates.byId(created.id)!;
      expect(restored.name, 'Leg day');
      expect(restored.rule, const DailyRecurrence(interval: 3));
      expect(restored.time, const EventTime(startMinute: 420));
      expect(restored.tracksPresence, isTrue);
    });

    test('a malformed row is skipped and the rest still imports', () async {
      await service.importData([
        'not a map',
        {'id': 't1'}, // missing name and category
        {'id': 't2', 'name': 'Good', 'category': 'gym'},
      ]);

      expect([for (final t in CalendarTemplates.all) t.id], ['t2']);
    });

    test('an out-of-range priority is clamped rather than stored', () async {
      await service.importData([
        {'id': 't1', 'name': 'Broken', 'category': 'gym', 'priority': 99},
      ]);

      expect(CalendarTemplates.byId('t1')!.priority, kMaxEventPriority);
    });

    test('an unknown count style falls back instead of throwing', () async {
      await service.importData([
        {
          'id': 't1',
          'name': 'Broken',
          'category': 'gym',
          'countStyle': 'spirals',
        },
      ]);

      expect(
        CalendarTemplates.byId('t1')!.countStyle,
        OccurrenceCountStyle.numbered,
      );
    });

    test('import stamps fresh identity, never the backup\'s', () async {
      await service.importData([
        {'id': 't1', 'name': 'Good', 'category': 'gym'},
      ]);

      final row = await (db.select(
        db.eventTemplates,
      )..where((t) => t.id.equals('t1'))).getSingle();
      expect(row.deviceId, 'test-device');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
    });
  });

  group('buildEvent', () {
    test('maps every field onto the created event', () async {
      final template = await service.create(
        draft(
          name: 'Leg day',
          categoryId: 'cardio',
          rule: const DailyRecurrence(interval: 2),
          time: const EventTime(startMinute: 600, durationMinutes: 45),
          description: 'hinge day',
          iconKey: 'directions_run',
          colorValue: 0xFF00FF00,
          priority: kMinEventPriority,
          tracksPresence: true,
          perOccurrenceDescriptions: true,
          countOccurrences: true,
          retroactive: true,
        ),
      );

      final event = template.buildEvent(
        id: 'e1',
        startDate: DateTime.utc(2026, 8, 10),
      );

      expect(event.id, 'e1');
      expect(event.title, 'Leg day');
      expect(event.categoryId, 'cardio');
      expect(event.startDate, DateTime.utc(2026, 8, 10));
      expect(event.rule, const DailyRecurrence(interval: 2));
      expect(
        event.time,
        const EventTime(startMinute: 600, durationMinutes: 45),
      );
      expect(event.description, 'hinge day');
      expect(event.iconKey, 'directions_run');
      expect(event.colorValue, 0xFF00FF00);
      expect(event.priority, kMinEventPriority);
      expect(event.tracksPresence, isTrue);
      expect(event.perOccurrenceDescriptions, isTrue);
      expect(event.countOccurrences, isTrue);
      expect(event.retroactive, isTrue);
      expect(event.allDay, isFalse);
    });

    test('a null time produces an all-day event', () {
      final event = draft().buildEvent(
        id: 'e1',
        startDate: DateTime.utc(2026, 8, 10),
      );

      expect(event.time, isNull);
      expect(event.allDay, isTrue);
    });

    test('normalizes a wall-clock start date to date-only UTC', () {
      final event = draft().buildEvent(
        id: 'e1',
        startDate: DateTime(2026, 8, 10, 21, 30),
      );

      expect(event.startDate, DateTime.utc(2026, 8, 10));
    });

    test('a one-time rule cannot carry the repeat-only flags', () {
      // Captured while recurring, later flipped to one-time: the flags are
      // still stored but must not reach the event, matching the editor's own
      // save guards.
      final template = draft(
        tracksPresence: true,
        perOccurrenceDescriptions: true,
        countOccurrences: true,
        retroactive: true,
      );

      final event = template.buildEvent(
        id: 'e1',
        startDate: DateTime.utc(2026, 8, 10),
      );

      expect(event.tracksPresence, isFalse);
      expect(event.perOccurrenceDescriptions, isFalse);
      expect(event.countOccurrences, isFalse);
      expect(event.retroactive, isFalse);
    });
  });
}
