// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v41 → v42's category half: one new table with its index, and two guarded
/// columns on populated tables — the opt-out on `calendar_events` and the
/// registry's `source`.
///
/// The create path is covered by `schema_parity_test`; this file takes a
/// fresh database back to v41 (dropping the table and both columns) and runs
/// the real step against it, then holds the migrated shape column for column
/// against what `createAll` produces. `event_digests_migration_test` covers
/// the step's other table.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Set<String>> columnNames(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<List<String>> columnShape(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return [
      for (final row in rows)
        [
          row.read<String>('name'),
          row.read<String>('type'),
          row.read<int>('notnull'),
          row.readNullable<String>('dflt_value') ?? '-',
          row.read<int>('pk'),
        ].join('|'),
    ];
  }

  Future<String?> indexSql(String name) async {
    final rows = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable<String>(name)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('sql');
  }

  Future<void> dropV42() async {
    await db.customStatement('DROP TABLE IF EXISTS calendar_category_alerts');
    await db.customStatement('DROP TABLE IF EXISTS event_digests');
    await db.customStatement(
      'ALTER TABLE calendar_events DROP COLUMN category_alerts',
    );
    await db.customStatement(
      'ALTER TABLE alert_registrations DROP COLUMN source',
    );
  }

  Future<void> runV42() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v41OverviewViews,
      DatabaseSchema.v42CategoryAlertsAndDigests,
    );
  }

  Future<void> insertLegacyEvent(String id) {
    return db.customStatement(
      'INSERT INTO calendar_events '
      '(id, title, category, start_date, all_day, rule_kind, '
      'created_at, updated_at, hlc_timestamp, device_id, version, is_deleted) '
      "VALUES ('$id', '$id', 'birthday', 0, 1, 'yearly', 0, 0, 'h', 'd', 1, 0)",
    );
  }

  Future<void> insertLegacyRegistration(int osId) {
    return db.customStatement(
      'INSERT INTO alert_registrations '
      '(os_id, alert_id, event_id, day, fire_at, kind, state, backend, '
      'created_at, updated_at) '
      "VALUES ($osId, 'a1', 'e1', 0, 0, 'scheduled', 'pending', 'alarm', 0, 0)",
    );
  }

  test('the step is registered at 42', () {
    expect(DatabaseSchema.v42CategoryAlertsAndDigests, 42);
    expect(DatabaseSchema.currentVersion, greaterThanOrEqualTo(42));
  });

  test('a fresh install already has everything v42 adds', () async {
    expect(await tableNames(db), contains('calendar_category_alerts'));
    expect(await columnNames('calendar_events'), contains('category_alerts'));
    expect(await columnNames('alert_registrations'), contains('source'));
    expect(
      await indexNames(db),
      contains('idx_calendar_category_alerts_category'),
    );
  });

  test('an upgrader gets the table, both columns and the index', () async {
    await dropV42();
    expect(await tableNames(db), isNot(contains('calendar_category_alerts')));
    expect(
      await indexNames(db),
      isNot(contains('idx_calendar_category_alerts_category')),
    );

    await runV42();

    expect(await tableNames(db), contains('calendar_category_alerts'));
    expect(await columnNames('calendar_events'), contains('category_alerts'));
    expect(await columnNames('alert_registrations'), contains('source'));
    expect(
      await indexNames(db),
      contains('idx_calendar_category_alerts_category'),
    );
  });

  test(
    'an existing event upgrades to inheriting its category\'s alerts',
    () async {
      await dropV42();
      await insertLegacyEvent('legacy');

      await runV42();

      final rows = await db.customSelect('SELECT * FROM calendar_events').get();
      expect(
        rows.single.read<int>('category_alerts'),
        1,
        reason:
            'no category had an alert before v42, so inheriting changes '
            'nothing an existing event did — the default needs no backfill',
      );
    },
  );

  test('an existing registration upgrades as an event\'s own', () async {
    await dropV42();
    await insertLegacyRegistration(7);

    await runV42();

    final rows = await db
        .customSelect('SELECT * FROM alert_registrations')
        .get();
    expect(rows.single.read<String>('source'), 'event');
    expect(rows.single.read<int>('os_id'), 7);
  });

  test('re-running it changes nothing it already wrote', () async {
    await dropV42();
    await insertLegacyEvent('legacy');
    await insertLegacyRegistration(7);
    await runV42();
    await db.customStatement('UPDATE calendar_events SET category_alerts = 0');
    await db.customStatement(
      "UPDATE alert_registrations SET source = 'category'",
    );
    await db.customStatement(
      'INSERT INTO calendar_category_alerts '
      '(id, category_id, mode, offset_minutes, days_before, enabled, '
      'created_at, updated_at, hlc_timestamp, device_id, version, is_deleted) '
      "VALUES ('c1', 'birthday', 'ring', 0, 1, 1, 0, 0, 'h', 'd', 1, 0)",
    );

    await runV42();

    final events = await db.customSelect('SELECT * FROM calendar_events').get();
    expect(
      events.single.read<int>('category_alerts'),
      0,
      reason: 'the PRAGMA guard must skip the ALTER, not re-add the column',
    );
    final registrations = await db
        .customSelect('SELECT * FROM alert_registrations')
        .get();
    expect(registrations.single.read<String>('source'), 'category');
    final alerts = await db
        .customSelect('SELECT * FROM calendar_category_alerts')
        .get();
    expect(
      alerts,
      hasLength(1),
      reason: 'CREATE TABLE IF NOT EXISTS must not replace a populated table',
    );
  });

  test(
    'a partial upgrade — the table there, the columns not — completes',
    () async {
      await db.customStatement(
        'ALTER TABLE calendar_events DROP COLUMN category_alerts',
      );
      await db.customStatement(
        'ALTER TABLE alert_registrations DROP COLUMN source',
      );

      await runV42();

      expect(await columnNames('calendar_events'), contains('category_alerts'));
      expect(await columnNames('alert_registrations'), contains('source'));
    },
  );

  test('a write through the DAO stamps the new row as live', () async {
    await dropV42();
    await runV42();

    await db.categoryAlertDao.replaceForCategory('birthday', [
      CalendarCategoryAlertsCompanion(
        id: const Value('c1'),
        daysBefore: const Value(1),
      ),
    ]);

    final row = (await db.categoryAlertDao.getAllActive()).single;
    expect(row.categoryId, 'birthday');
    expect(row.version, 1);
    expect(row.deviceId, 'test-device');
  });

  group('create-vs-migrate parity', () {
    test(
      'the category alert table is column-for-column the created one',
      () async {
        final created = await columnShape('calendar_category_alerts');

        await dropV42();
        // v43 appends `owner_id`, so a fresh install's shape is the v42 DDL
        // plus every later step that widens it.
        await DatabaseMigrations(db).runMigrations(
          db.createMigrator(),
          DatabaseSchema.v41OverviewViews,
          DatabaseSchema.currentVersion,
        );

        expect(await columnShape('calendar_category_alerts'), created);
      },
    );

    test('the registration table, `source` last, is the created one', () async {
      final created = await columnShape('alert_registrations');

      await dropV42();
      await runV42();

      expect(await columnShape('alert_registrations'), created);
    });

    test('the migrated opt-out matches the declared one', () async {
      String flag(List<String> shape) =>
          shape.firstWhere((c) => c.startsWith('category_alerts|'));
      final created = flag(await columnShape('calendar_events'));

      await dropV42();
      await runV42();

      expect(flag(await columnShape('calendar_events')), created);
    });

    test('the index definition survives the upgrade verbatim', () async {
      const name = 'idx_calendar_category_alerts_category';
      final created = await indexSql(name);
      expect(created, isNotNull);

      await dropV42();
      await runV42();

      expect(await indexSql(name), created);
    });
  });
}
