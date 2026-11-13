import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v51 → v52 → v53: the share mark and its stamp on `calendar_events` and
/// `folders`, and the two partial indexes over the marked rows
/// (`docs/cloud-sharing-foundations.md` §3). A v51 database is a fresh one
/// without the four columns and the two indexes; the steps add them over the
/// rows that are there and write nothing else. v55 → v56 does the same for
/// `calendar_categories` (`docs/cloud-share-surfaces-roadmap.md` §7.1).
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  const tables = ['calendar_events', 'folders'];
  const indexes = [
    'idx_folders_shared_pair',
    'idx_calendar_events_shared_pair',
  ];
  const categoryIndex = 'idx_calendar_categories_shared_pair';

  Future<Set<String>> columns(String table) async => {
    for (final row in await db.customSelect('PRAGMA table_info($table)').get())
      row.read<String>('name'),
  };

  Future<Set<String>> indexNames() async => {
    for (final row
        in await db
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
    ).runMigrations(db.createMigrator(), from, DatabaseSchema.v53ShareStamp);
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
      'any of the three tables', () async {
    final counter = StatementCounter();
    final counted = await openTestDatabase(interceptor: counter);
    addTearDown(counted.close);
    counter.reset();

    expect(await counted.syncDao.anyShareMark(), isFalse);

    expect(counter.count, 1);
    final detail = await explainCaptured(counted, counter.captured.single);
    for (final index in [...indexes, categoryIndex]) {
      expect(
        detail.where((line) => line.contains(index)),
        isNotEmpty,
        reason: '$index: $detail',
      );
    }
  });

  test('a category\'s mark is a mark like the others', () async {
    await db.calendarCategoryDao.insertCategory(
      CalendarCategoriesCompanion.insert(
        id: 'c1',
        name: 'Climb',
        colorValue: 0xFF336699,
        iconKey: 'event',
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      ),
    );
    expect(await db.syncDao.anyShareMark(), isFalse);

    await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');

    expect(await db.syncDao.anyShareMark(), isTrue);
  });

  test('what a person is told they share counts live rows alone: a deleted '
      'row\'s mark, on any of the three tables, is still a mark to clear and '
      'send, and shares nothing', () async {
    final day = DateTime.utc(2026, 6, 1);
    final folder = await db.folderDao.createFolder(name: 'Shelf');
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'e1',
        title: 'Climb',
        category: 'general',
        startDate: day,
        ruleKind: 'weekly',
        createdAt: day,
        updatedAt: day,
      ),
    );
    await db.calendarCategoryDao.insertCategory(
      CalendarCategoriesCompanion.insert(
        id: 'c1',
        name: 'Climb',
        colorValue: 0xFF336699,
        iconKey: 'event',
        createdAt: day,
        updatedAt: day,
      ),
    );
    final rows = {
      'folders': folder.id,
      'calendar_events': 'e1',
      'calendar_categories': 'c1',
    };

    for (final MapEntry(key: table, value: id) in rows.entries) {
      await db.customStatement(
        "UPDATE $table SET shared_pair = 'pair-1' WHERE id = ?",
        [id],
      );
      expect(await db.syncDao.anyLiveShareMark(), isTrue, reason: table);

      await db.customStatement(
        'UPDATE $table SET is_deleted = 1 WHERE id = ?',
        [id],
      );
      expect(await db.syncDao.anyLiveShareMark(), isFalse, reason: table);
      expect(await db.syncDao.anyShareMark(), isTrue, reason: table);

      await db.customStatement(
        'UPDATE $table SET shared_pair = NULL WHERE id = ?',
        [id],
      );
    }

    final counter = StatementCounter();
    final counted = await openTestDatabase(interceptor: counter);
    addTearDown(counted.close);
    counter.reset();
    expect(await counted.syncDao.anyLiveShareMark(), isFalse);
    final detail = await explainCaptured(counted, counter.captured.single);
    for (final index in [...indexes, categoryIndex]) {
      expect(
        detail.where((line) => line.contains(index)),
        isNotEmpty,
        reason: '$index: $detail',
      );
    }
  });

  group('v55 → v56', () {
    Future<void> upgrade() => DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v55FencesAgain,
      DatabaseSchema.v56CategorySharedPair,
    );

    /// Takes the categories back to v55: no index, no stamp, no mark.
    Future<void> asV55() async {
      await db.customStatement('DROP INDEX $categoryIndex');
      await db.customStatement(
        'ALTER TABLE calendar_categories DROP COLUMN shared_stamp',
      );
      await db.customStatement(
        'ALTER TABLE calendar_categories DROP COLUMN shared_pair',
      );
    }

    test('a v55 database gains the category\'s mark, its stamp and its '
        'index, with every row left as it was: unmarked, at its own stamp, '
        'and nothing queued', () async {
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: 'c1',
          name: 'Climb',
          colorValue: 0xFF336699,
          iconKey: 'event',
          createdAt: DateTime.utc(2026, 6, 1),
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );
      final before = await db
          .customSelect(
            'SELECT hlc_timestamp, version FROM calendar_categories',
          )
          .getSingle();
      await db.syncOutboxDao.clear();
      await asV55();
      expect(
        await columns('calendar_categories'),
        isNot(contains('shared_pair')),
      );

      await upgrade();

      expect(
        await columns('calendar_categories'),
        containsAll(['shared_pair', 'shared_stamp']),
      );
      expect(await indexNames(), contains(categoryIndex));
      expect(await userVersion(), DatabaseSchema.v56CategorySharedPair);
      final after = (await db.calendarCategoryDao.getByIdsIncludingDeleted([
        'c1',
      ])).single;
      expect(after.sharedPair, isNull);
      expect(after.sharedStamp, isNull);
      expect(after.hlcTimestamp, before.read<String>('hlc_timestamp'));
      expect(after.version, before.read<int>('version'));
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('runs again over a database that has it and changes nothing',
        () async {
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: 'c1',
          name: 'Climb',
          colorValue: 0xFF336699,
          iconKey: 'event',
          createdAt: DateTime.utc(2026, 6, 1),
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      final before = (await db.calendarCategoryDao.getByIdsIncludingDeleted([
        'c1',
      ])).single;

      await upgrade();
      await upgrade();

      expect(
        (await db.calendarCategoryDao.getByIdsIncludingDeleted(['c1'])).single,
        before,
      );
    });
  });
}
