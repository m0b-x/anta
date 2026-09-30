import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// `calendar_filter_presets` (**v35**) is a brand-new table, so the two things
/// worth pinning are the ones the v29/v30 tables pin: that the **upgrade path**
/// produces it (the create path is covered generically by
/// `schema_parity_test`), and that its CRDT stamping lives in the DAO — an
/// insert that reached the table without an HLC would leave a row no future
/// merge can order.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Set<String>> tables() => tableNames(db);

  Future<void> dropTable() =>
      db.customStatement('DROP TABLE calendar_filter_presets');

  Future<void> runV35() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v34EventShowInDayRail,
      DatabaseSchema.v35CalendarFilterPresets,
    );
  }

  Future<CalendarFilterPresetRow> only() async {
    final rows = await db.filterPresetDao.getAll();
    expect(rows, hasLength(1));
    return rows.single;
  }

  Future<void> insert(String id, {String name = 'Saved', String? blob}) {
    return db.filterPresetDao.upsertPreset(
      CalendarFilterPresetsCompanion(
        id: Value(id),
        name: Value(name),
        filters: Value(blob ?? '{"trackedOnly":true}'),
      ),
    );
  }

  group('the migration', () {
    test('a fresh install already has the table', () async {
      expect(await tables(), contains('calendar_filter_presets'));
    });

    test('an upgrader gets it', () async {
      await dropTable();
      expect(await tables(), isNot(contains('calendar_filter_presets')));

      await runV35();

      expect(await tables(), contains('calendar_filter_presets'));
    });

    /// `runMigrations` replays every step whose `toVersion` is in range, so a
    /// partial upgrade re-runs this one — which is what makes the
    /// `IF NOT EXISTS` load-bearing rather than decorative.
    test('re-running it neither fails nor drops rows', () async {
      await insert('p1');

      await runV35();

      expect(await tables(), contains('calendar_filter_presets'));
      expect(await db.filterPresetDao.getAll(), hasLength(1));
    });
  });

  group('CRDT stamping', () {
    test('an insert stamps identity and starts at version 1', () async {
      await insert('p1');

      final row = await only();
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, isNotEmpty);
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
    });

    test('an update bumps the version and keeps created_at', () async {
      await insert('p1', name: 'First');
      final before = await only();

      await insert('p1', name: 'Renamed');

      final after = await only();
      expect(after.name, 'Renamed');
      expect(after.version, before.version + 1);
      expect(after.createdAt, before.createdAt);
      expect(
        after.hlcTimestamp,
        isNot(before.hlcTimestamp),
        reason: 'every write takes a fresh HLC',
      );
    });

    test('a delete tombstones rather than removing the row', () async {
      await insert('p1');

      await db.filterPresetDao.softDeleteById('p1');

      // Below the service waterline: `getAll` hides it, the row survives.
      expect(await db.filterPresetDao.getAll(), isEmpty);
      final raw = await db
          .customSelect('SELECT * FROM calendar_filter_presets')
          .get();
      expect(raw, hasLength(1));
      expect(raw.single.read<bool>('is_deleted'), isTrue);
    });

    test('deleting twice is a no-op', () async {
      await insert('p1');
      await db.filterPresetDao.softDeleteById('p1');
      final raw = await db
          .customSelect('SELECT version FROM calendar_filter_presets')
          .get();

      await db.filterPresetDao.softDeleteById('p1');

      final after = await db
          .customSelect('SELECT version FROM calendar_filter_presets')
          .get();
      expect(after.single.read<int>('version'), raw.single.read<int>('version'));
    });

    /// Ids are caller-supplied and a re-imported id must not collide, so an
    /// upsert onto a tombstone brings the row back instead of failing.
    test('an upsert resurrects a tombstoned id', () async {
      await insert('p1', name: 'First');
      await db.filterPresetDao.softDeleteById('p1');

      await insert('p1', name: 'Back');

      final row = await only();
      expect(row.name, 'Back');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
    });
  });

  group('ordering', () {
    Future<List<Map<String, Object?>>> raw() async {
      final rows = await db
          .customSelect(
            'SELECT id, sort_order, version, hlc_timestamp, is_deleted '
            'FROM calendar_filter_presets ORDER BY id',
          )
          .get();
      return [for (final r in rows) r.data];
    }

    test('reorder rewrites dense positions in the order given', () async {
      await insert('p1');
      await insert('p2');
      await insert('p3');

      await db.filterPresetDao.reorder(['p3', 'p1', 'p2']);

      final rows = await db.filterPresetDao.getAll();
      expect(rows.map((r) => r.id), ['p3', 'p1', 'p2']);
      expect(
        rows.map((r) => r.sortOrder),
        [0, 1, 2],
        reason: 'dense: getAll tie-breaks on id, so gaps let rows shuffle',
      );
    });

    /// The reason the position is rewritten in SQL rather than read first:
    /// only a row that actually moves takes a new version and HLC, so a
    /// drag of one row leaves every other row's stamp alone.
    test('a moved row bumps its version and takes a fresh HLC; a row already '
        'in place keeps both', () async {
      await insert('p1');
      await insert('p2');
      final before = {for (final r in await raw()) r['id']: r};

      // Both rows sit at sort_order 0; p1 lands on 0 again, p2 moves to 1.
      await db.filterPresetDao.reorder(['p1', 'p2']);

      final after = {for (final r in await raw()) r['id']: r};
      expect(after['p1']!['version'], before['p1']!['version']);
      expect(after['p1']!['hlc_timestamp'], before['p1']!['hlc_timestamp']);
      expect(after['p2']!['sort_order'], 1);
      expect(after['p2']!['version'], (before['p2']!['version']! as int) + 1);
      expect(
        after['p2']!['hlc_timestamp'],
        isNot(before['p2']!['hlc_timestamp']),
      );
    });

    test('a tombstone and an unknown id are no-ops', () async {
      await insert('p1');
      await insert('p2');
      await db.filterPresetDao.softDeleteById('p2');
      final deadBefore = (await raw()).singleWhere((r) => r['id'] == 'p2');

      await db.filterPresetDao.reorder(['p2', 'p1', 'ghost']);

      final rows = await raw();
      expect(rows, hasLength(2), reason: 'an unknown id inserts nothing');
      final dead = rows.singleWhere((r) => r['id'] == 'p2');
      expect(dead['sort_order'], deadBefore['sort_order']);
      expect(dead['version'], deadBefore['version']);
      expect(rows.singleWhere((r) => r['id'] == 'p1')['sort_order'], 1);
    });

    test('reordering nothing writes nothing', () async {
      await insert('p1');
      final before = await raw();

      await db.filterPresetDao.reorder(const []);

      expect(await raw(), before);
    });

    test('nextSortOrder counts tombstones', () async {
      await db.filterPresetDao.upsertPreset(
        CalendarFilterPresetsCompanion(
          id: const Value('p1'),
          name: const Value('One'),
          filters: const Value('{}'),
          sortOrder: const Value(0),
        ),
      );
      await db.filterPresetDao.softDeleteById('p1');

      // Reusing a dead preset's slot would reorder the list if that preset is
      // ever resurrected.
      expect(await db.filterPresetDao.nextSortOrder(), 1);
    });
  });
}
