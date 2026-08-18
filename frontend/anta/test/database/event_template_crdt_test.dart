// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// Guards the columns nothing renders — the CRDT block `calendar_event_templates`
/// was born with in v29.
///
/// Unlike `calendar_events` (v27) and `calendar_event_occurrences` (v28), this
/// table never had to grow the block by ALTER, so its identity columns carry no
/// `DEFAULT ''` and there is nothing to backfill. Every assertion here is
/// invisible from the app — a deleted template and a tombstoned one both vanish
/// from the picker, and a version that never increments changes nothing on
/// screen. They are the properties a merge will depend on, and by then the
/// history they protect is already gone.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<EventTemplateRow> rowFor(String id) {
    return (db.select(
      db.eventTemplates,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  group('stamping', () {
    test('a first write is a live version-1 row stamped with this device', () async {
      await db.eventTemplateDao.upsertTemplate(_entry('t1', 'Push day'));

      final row = await rowFor('t1');
      expect(row.name, 'Push day');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });

    test('an edit bumps the version, keeps createdAt and moves the HLC', () async {
      await db.eventTemplateDao.upsertTemplate(_entry('t1', 'Push day'));
      final before = await rowFor('t1');

      await db.eventTemplateDao.upsertTemplate(
        _entry('t1', 'Pull day', createdAt: DateTime.utc(2030, 1, 1)),
      );
      final after = await rowFor('t1');

      expect(after.name, 'Pull day');
      expect(after.version, before.version + 1);
      // The caller's companion always carries a `createdAt`, and on an update
      // it is always wrong — a template keeps the date it was made.
      expect(after.createdAt, before.createdAt);
      // A version bump with a stale HLC would order two edits arbitrarily.
      expect(after.hlcTimestamp, isNot(before.hlcTimestamp));
    });

    test('a delete tombstones rather than removing the row', () async {
      await db.eventTemplateDao.upsertTemplate(_entry('t1', 'Push day'));
      await db.eventTemplateDao.softDeleteById('t1');

      final row = await rowFor('t1');
      expect(row.isDeleted, isTrue);
      expect(row.deletedAt, isNotNull);
      expect(row.version, 2);
      expect(await db.eventTemplateDao.getAll(), isEmpty);
    });

    test('deleting twice does not churn the version', () async {
      await db.eventTemplateDao.upsertTemplate(_entry('t1', 'Push day'));
      await db.eventTemplateDao.softDeleteById('t1');
      final once = await rowFor('t1');

      await db.eventTemplateDao.softDeleteById('t1');

      expect((await rowFor('t1')).version, once.version);
    });

    test('deleting a missing template is a no-op', () async {
      await db.eventTemplateDao.softDeleteById('ghost');

      expect(await db.select(db.eventTemplates).get(), isEmpty);
    });

    test('writing a tombstoned id resurrects it instead of colliding', () async {
      await db.eventTemplateDao.upsertTemplate(_entry('t1', 'Push day'));
      await db.eventTemplateDao.softDeleteById('t1');

      await db.eventTemplateDao.upsertTemplate(_entry('t1', 'Push day v2'));

      final row = await rowFor('t1');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.name, 'Push day v2');
      expect(await db.eventTemplateDao.getAll(), hasLength(1));
    });

    test('an import stamps fresh identity but keeps the audit fields', () async {
      final created = DateTime.utc(2020, 5, 4);

      await db.eventTemplateDao.importTemplate(
        _entry('t1', 'Push day', createdAt: created).copyWith(
          // A backup is not a sync channel: whatever identity it claims is
          // ignored and replaced with this device's.
          hlcTimestamp: const Value('foreign-hlc'),
          deviceId: const Value('other-device'),
          version: const Value(9),
          isDeleted: const Value(true),
        ),
      );

      final row = await rowFor('t1');
      // Drift stores unix seconds and hands the column back as a *local*
      // DateTime, so the instant is what round-trips, not the wall clock.
      expect(
        row.createdAt.millisecondsSinceEpoch,
        created.millisecondsSinceEpoch,
      );
      expect(row.hlcTimestamp, isNot('foreign-hlc'));
      expect(row.deviceId, 'test-device');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
    });
  });

  group('ordering', () {
    test('lists by sort order, then id for a tie', () async {
      await db.eventTemplateDao.upsertTemplate(
        _entry('zzz', 'Later', sortOrder: 0),
      );
      await db.eventTemplateDao.upsertTemplate(
        _entry('aaa', 'Tie', sortOrder: 0),
      );
      await db.eventTemplateDao.upsertTemplate(
        _entry('mmm', 'First', sortOrder: -1),
      );

      final ids = [for (final row in await db.eventTemplateDao.getAll()) row.id];
      expect(ids, ['mmm', 'aaa', 'zzz']);
    });

    test('nextSortOrder counts tombstones so a slot is never reused', () async {
      await db.eventTemplateDao.upsertTemplate(
        _entry('t1', 'Push day', sortOrder: 0),
      );
      await db.eventTemplateDao.upsertTemplate(
        _entry('t2', 'Leg day', sortOrder: 1),
      );
      await db.eventTemplateDao.softDeleteById('t2');

      // Handing out 1 again would reorder the list if `t2` is ever restored.
      expect(await db.eventTemplateDao.nextSortOrder(), 2);
    });

    test('nextSortOrder starts at zero on an empty table', () async {
      expect(await db.eventTemplateDao.nextSortOrder(), 0);
    });
  });

  group('the v29 migration', () {
    /// Rebuilds the pre-v29 world: the table simply does not exist.
    Future<void> dropTemplates() async {
      await db.customStatement('DROP TABLE IF EXISTS calendar_event_templates');
    }

    Future<void> runV29() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v28DescriptionScope,
        DatabaseSchema.v29EventTemplates,
      );
    }

    /// Reads untyped. The generated mapper expects every column the *current*
    /// schema declares, so each later migration would otherwise break this
    /// group for reasons that have nothing to do with v29.
    Future<List<QueryRow>> templateRows() {
      return db.customSelect('SELECT * FROM calendar_event_templates').get();
    }

    test('creates the table on an upgrader', () async {
      await dropTemplates();
      await runV29();

      expect(await templateRows(), isEmpty);
    });

    test('re-running it is a no-op and keeps existing rows', () async {
      await dropTemplates();
      await runV29();
      await db.customStatement(
        'INSERT INTO calendar_event_templates '
        '(id, name, category, created_at, updated_at, hlc_timestamp, device_id) '
        "VALUES ('t1', 'Push day', 'gym', 0, 0, 'hlc', 'dev')",
      );

      await runV29();

      final rows = await templateRows();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('name'), 'Push day');
    });

    test('the defaults an insert relies on are the frozen ones', () async {
      await dropTemplates();
      await runV29();
      await db.customStatement(
        'INSERT INTO calendar_event_templates '
        '(id, name, category, created_at, updated_at, hlc_timestamp, device_id) '
        "VALUES ('t1', 'Push day', 'gym', 0, 0, 'hlc', 'dev')",
      );

      final row = (await templateRows()).single;
      expect(row.read<int>('sort_order'), 0);
      expect(row.read<String>('rule_kind'), 'oneTime');
      expect(row.read<int>('tint_icon'), 1);
      expect(row.read<int>('priority'), 3);
      expect(row.read<int>('version'), 1);
      expect(row.read<int>('is_deleted'), 0);
      expect(row.read<String>('count_style'), 'numbered');
    });
  });
}

EventTemplatesCompanion _entry(
  String id,
  String name, {
  DateTime? createdAt,
  int sortOrder = 0,
}) {
  final stamp = createdAt ?? DateTime.utc(2026, 1, 1);
  return EventTemplatesCompanion(
    id: Value(id),
    name: Value(name),
    category: const Value('gym'),
    sortOrder: Value(sortOrder),
    createdAt: Value(stamp),
    updatedAt: Value(stamp),
  );
}
