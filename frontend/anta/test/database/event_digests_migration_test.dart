import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v41 → v42's digest half: `event_digests`, a brand-new table in the
/// `overview_views` shape plus `enabled`, so a v41 database is a fresh one
/// without it. The re-run is what makes `IF NOT EXISTS` load-bearing: a
/// partial upgrade replays the step over a table that already holds a digest.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

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

  Future<void> runV42() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v41OverviewViews,
      DatabaseSchema.v42CategoryAlertsAndDigests,
    );
  }

  Future<int> userVersion() async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test(
    'a v41 database upgrades with the table and a re-run keeps its rows',
    () async {
      await db.customStatement('DROP TABLE event_digests');
      expect(await tableNames(db), isNot(contains('event_digests')));

      await runV42();

      expect(await tableNames(db), contains('event_digests'));
      expect(await userVersion(), DatabaseSchema.v42CategoryAlertsAndDigests);

      await db.eventDigestDao.upsertDigest(
        const EventDigestsCompanion(
          id: Value('d1'),
          payload: Value('{"cadence":"monthly"}'),
        ),
      );
      await runV42();

      final rows = await db.eventDigestDao.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.name, '', reason: 'an unnamed digest is derived');
      expect(rows.single.enabled, isTrue);
    },
  );

  test('the table is column-for-column the created one', () async {
    final created = await columnShape('event_digests');

    await db.customStatement('DROP TABLE event_digests');
    // v43 appends `owner_id`, so a fresh install's shape is the v42 DDL plus
    // every later step that widens it.
    await DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v41OverviewViews,
      DatabaseSchema.currentVersion,
    );

    expect(await columnShape('event_digests'), created);
  });

  test(
    'a raw insert that omits the defaults relies on the frozen DDL',
    () async {
      await db.customStatement('DROP TABLE event_digests');
      await runV42();

      await db.customStatement(
        'INSERT INTO event_digests '
        '(id, payload, created_at, updated_at, hlc_timestamp, device_id) '
        "VALUES ('d1', '{}', 0, 0, 'h', 'd')",
      );

      final row =
          (await db.customSelect('SELECT * FROM event_digests').get()).single;
      expect(row.read<String>('name'), '');
      expect(row.read<int>('enabled'), 1);
      expect(row.read<int>('sort_order'), 0);
      expect(row.read<int>('version'), 1);
      expect(row.read<int>('is_deleted'), 0);
    },
  );
}
