import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v51 → v52 → v53: the share mark and its stamp on `calendar_events` and
/// `folders`, and the two partial indexes over the marked rows
/// (`docs/cloud-sharing-foundations.md` §3). A v51 database is a fresh one
/// without the four columns and the two indexes; the steps add them over the
/// rows that are there and write nothing else.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  const tables = ['calendar_events', 'folders'];
  const indexes = [
    'idx_folders_shared_pair',
    'idx_calendar_events_shared_pair',
  ];

  Future<Set<String>> columns(String table) async => {
    for (final row in await db.customSelect('PRAGMA table_info($table)').get())
      row.read<String>('name'),
  };

  Future<Set<String>> indexNames() async => {
    for (final row in await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get())
      row.read<String>('name'),
  };

  /// Takes the database back to v51: no index, no stamp, no mark.
  Future<void> asV51() async {
    for (final index in indexes) {
      await db.customStatement('DROP INDEX $index');
    }
    for (final table in tables) {
      await db.customStatement('ALTER TABLE $table DROP COLUMN shared_stamp');
      await db.customStatement('ALTER TABLE $table DROP COLUMN shared_pair');
    }
  }

  Future<void> upgrade({int from = DatabaseSchema.v51OutboxRepublish}) {
    return DatabaseMigrations(
      db,
    ).runMigrations(db.createMigrator(), from, DatabaseSchema.currentVersion);
  }

  Future<int> userVersion() async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test('a v51 database gains the mark, its stamp and the two indexes, with '
      'every row it held left as it was: unmarked, at its own stamp, and '
      'nothing queued', () async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    final before = (await db.folderDao.getByIdsIncludingDeleted([
      folder.id,
    ])).single;
    await db.syncOutboxDao.clear();
    await asV51();
    for (final table in tables) {
      expect(await columns(table), isNot(contains('shared_pair')));
    }

    await upgrade();

    for (final table in tables) {
      expect(
        await columns(table),
        containsAll(['shared_pair', 'shared_stamp']),
        reason: table,
      );
    }
    expect(await indexNames(), containsAll(indexes));
    expect(await userVersion(), DatabaseSchema.v53ShareStamp);
    final after = (await db.folderDao.getByIdsIncludingDeleted([
      folder.id,
    ])).single;
    expect(after.sharedPair, isNull);
    expect(after.sharedStamp, isNull);
    expect(after.hlcTimestamp, before.hlcTimestamp);
    expect(after.version, before.version);
    expect(await db.syncOutboxDao.count(), 0);
  });

  test('a database a v52 build left — the mark and no stamp — gains the '
      'stamp and the indexes, and a mark it carries stays, never '
      'stamped', () async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    for (final index in indexes) {
      await db.customStatement('DROP INDEX $index');
    }
    for (final table in tables) {
      await db.customStatement('ALTER TABLE $table DROP COLUMN shared_stamp');
    }
    await db.customStatement(
      "UPDATE folders SET shared_pair = 'pair-1' WHERE id = ?",
      [folder.id],
    );

    await upgrade(from: DatabaseSchema.v52SharedPair);

    final after = (await db.folderDao.getByIdsIncludingDeleted([
      folder.id,
    ])).single;
    expect(after.sharedPair, 'pair-1');
    expect(after.sharedStamp, isNull);
    expect(await indexNames(), containsAll(indexes));
  });

  test('both steps run again over a database that has them and change '
      'nothing: a half-upgraded file is upgraded like any other', () async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    await db.folderDao.setSharedPair(folder.id, 'pair-1');
    final before = (await db.folderDao.getByIdsIncludingDeleted([
      folder.id,
    ])).single;

    await upgrade();
    await upgrade();

    expect(
      (await db.folderDao.getByIdsIncludingDeleted([folder.id])).single,
      before,
    );
  });

  test('the marked rows are found through the partial indexes: a database '
      'that shares nothing answers "is anything shared" without reading '
      'either table', () async {
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN '
          'SELECT EXISTS(SELECT 1 FROM folders WHERE shared_pair IS NOT NULL) '
          'OR EXISTS(SELECT 1 FROM calendar_events '
          'WHERE shared_pair IS NOT NULL) AS marked',
        )
        .get();
    final detail = [for (final row in plan) row.read<String>('detail')];

    expect(
      detail.where((line) => line.contains('idx_folders_shared_pair')),
      isNotEmpty,
      reason: '$detail',
    );
    expect(
      detail.where((line) => line.contains('idx_calendar_events_shared_pair')),
      isNotEmpty,
      reason: '$detail',
    );
    expect(await db.syncDao.anyShareMark(), isFalse);
  });
}
