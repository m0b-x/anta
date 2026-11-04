// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v43 → v44: one new table with its index, and nothing else.
///
/// The create path is covered by `schema_parity_test`; this file takes a
/// fresh database back to v43 (dropping the table) and runs the real step
/// against it, then holds the migrated shape column for column against what
/// `createAll` produces.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  const table = 'calendar_category_profiles';
  const index = 'idx_calendar_category_profiles_category';

  Future<List<String>> columnShape() async {
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

  Future<String?> indexSql() async {
    final rows = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable<String>(index)],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('sql');
  }

  Future<void> dropV44() => db.customStatement('DROP TABLE IF EXISTS $table');

  Future<void> runV44() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v43SyncReadiness,
      DatabaseSchema.v44CategoryProfiles,
    );
  }

  test('the step is registered at 44', () {
    expect(DatabaseSchema.v44CategoryProfiles, 44);
    expect(DatabaseSchema.currentVersion, greaterThanOrEqualTo(44));
  });

  test('a fresh install already has the table and its index', () async {
    expect(await tableNames(db), contains(table));
    expect(await indexNames(db), contains(index));
  });

  test('an upgrader gets the table and the index', () async {
    await dropV44();
    expect(await tableNames(db), isNot(contains(table)));
    expect(await indexNames(db), isNot(contains(index)));

    await runV44();

    expect(await tableNames(db), contains(table));
    expect(await indexNames(db), contains(index));
  });

  test('re-running it keeps a populated table', () async {
    await dropV44();
    await runV44();
    await db.customStatement(
      'INSERT INTO $table '
      '(id, category_id, kind, created_at, updated_at, hlc_timestamp, '
      'device_id, version, is_deleted) '
      "VALUES ('p1', 'gym', 'workout', 0, 0, 'h', 'd', 1, 0)",
    );

    await runV44();

    final rows = await db.customSelect('SELECT * FROM $table').get();
    expect(
      rows,
      hasLength(1),
      reason: 'CREATE TABLE IF NOT EXISTS must not replace a populated table',
    );
    expect(rows.single.read<String>('kind'), 'workout');
  });

  test('a write through the DAO stamps the new row as live', () async {
    await dropV44();
    await runV44();

    await db.categoryProfileDao.upsertForCategory(
      const CalendarCategoryProfilesCompanion(
        id: Value('p1'),
        categoryId: Value('gym'),
      ),
    );

    final row = (await db.categoryProfileDao.getAllActive()).single;
    expect(row.categoryId, 'gym');
    expect(row.kind, 'custom');
    expect(row.version, 1);
    expect(row.deviceId, 'test-device');
    expect(row.ownerId, isNull);
  });

  group('create-vs-migrate parity', () {
    test('the table is column-for-column the created one', () async {
      final created = await columnShape();

      await dropV44();
      await runV44();

      expect(await columnShape(), created);
    });

    test('the index definition survives the upgrade verbatim', () async {
      final created = await indexSql();
      expect(created, isNotNull);

      await dropV44();
      await runV44();

      expect(await indexSql(), created);
    });
  });
}
