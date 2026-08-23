// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// Guards the columns nothing renders — the CRDT block `vocabularies` and
/// `vocabulary_items` were born with in v32 — plus the one behaviour the whole
/// feature leans on: **saving a list must preserve term identity**.
///
/// A vocabulary is edited as a block of text, so every save re-submits every
/// term. If that wiped and reinserted, each save would fork every row's id and
/// bump every version, which turns one edited word into a full-list conflict
/// the moment two devices merge. The diff is what keeps a save proportional to
/// what actually changed.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<VocabularyRow> vocabularyFor(String id) {
    return (db.select(
      db.vocabularies,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<List<VocabularyItemRow>> allItems() {
    return (db.select(db.vocabularyItems)..orderBy([
          (t) => OrderingTerm(expression: t.sortOrder),
        ]))
        .get();
  }

  group('stamping', () {
    test(
      'a first write is a live version-1 row stamped with this device',
      () async {
        await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises'));

        final row = await vocabularyFor('v1');
        expect(row.name, 'Exercises');
        expect(row.isEnabled, isTrue);
        expect(row.version, 1);
        expect(row.isDeleted, isFalse);
        expect(row.deletedAt, isNull);
        expect(row.hlcTimestamp, isNotEmpty);
        expect(row.deviceId, 'test-device');
      },
    );

    test('an edit bumps the version, keeps createdAt and moves the HLC', () async {
      await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises'));
      final before = await vocabularyFor('v1');

      await db.vocabularyDao.upsertVocabulary(
        _entry('v1', 'Lifts', createdAt: DateTime.utc(2030, 1, 1)),
      );
      final after = await vocabularyFor('v1');

      expect(after.name, 'Lifts');
      expect(after.version, before.version + 1);
      expect(after.createdAt, before.createdAt);
      expect(after.hlcTimestamp, isNot(before.hlcTimestamp));
    });

    test('a delete tombstones the list and every term in it', () async {
      await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises'));
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );

      await db.vocabularyDao.softDeleteVocabularyById('v1');

      final row = await vocabularyFor('v1');
      expect(row.isDeleted, isTrue);
      expect(row.deletedAt, isNotNull);
      expect(await db.vocabularyDao.getAllVocabularies(), isEmpty);
      // A live term under a dead list would keep suggesting itself.
      expect(await db.vocabularyDao.getAllItems(), isEmpty);
      expect((await allItems()).every((item) => item.isDeleted), isTrue);
    });

    test('deleting twice does not churn the version', () async {
      await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises'));
      await db.vocabularyDao.softDeleteVocabularyById('v1');
      final once = await vocabularyFor('v1');

      await db.vocabularyDao.softDeleteVocabularyById('v1');

      expect((await vocabularyFor('v1')).version, once.version);
    });

    test('deleting a missing list is a no-op', () async {
      await db.vocabularyDao.softDeleteVocabularyById('ghost');

      expect(await db.select(db.vocabularies).get(), isEmpty);
    });

    test('writing a tombstoned id resurrects it instead of colliding', () async {
      await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises'));
      await db.vocabularyDao.softDeleteVocabularyById('v1');

      await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises v2'));

      final row = await vocabularyFor('v1');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.name, 'Exercises v2');
      expect(await db.vocabularyDao.getAllVocabularies(), hasLength(1));
    });

    test('an import stamps fresh identity but keeps the audit fields', () async {
      final created = DateTime.utc(2020, 5, 4);

      await db.vocabularyDao.importVocabulary(
        _entry('v1', 'Exercises', createdAt: created).copyWith(
          hlcTimestamp: const Value('foreign-hlc'),
          deviceId: const Value('other-device'),
          version: const Value(9),
          isDeleted: const Value(true),
        ),
      );

      final row = await vocabularyFor('v1');
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

  group('saving a term list', () {
    setUp(() async {
      await db.vocabularyDao.upsertVocabulary(_entry('v1', 'Exercises'));
    });

    test('inserts the terms in the order given', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift', 'Squat'],
      );

      final items = await db.vocabularyDao.getAllItems();
      expect([for (final item in items) item.term], [
        'Bench Press',
        'Deadlift',
        'Squat',
      ]);
      expect([for (final item in items) item.sortOrder], [0, 1, 2]);
    });

    test('re-saving an unchanged list writes nothing', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );
      final before = await allItems();

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );
      final after = await allItems();

      expect([for (final item in after) item.version], [
        for (final item in before) item.version,
      ]);
      expect([for (final item in after) item.hlcTimestamp], [
        for (final item in before) item.hlcTimestamp,
      ]);
    });

    test('a surviving term keeps its id when a neighbour is added', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press'],
      );
      final originalId = (await db.vocabularyDao.getAllItems()).single.id;

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );

      final items = await db.vocabularyDao.getAllItems();
      expect(items, hasLength(2));
      expect(items.first.id, originalId);
      expect(items.first.version, 1);
    });

    test('a removed term is tombstoned, not deleted', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press'],
      );

      expect(await db.vocabularyDao.getAllItems(), hasLength(1));
      final rows = await allItems();
      expect(rows, hasLength(2));
      final dead = rows.firstWhere((row) => row.term == 'Deadlift');
      expect(dead.isDeleted, isTrue);
      expect(dead.deletedAt, isNotNull);
      expect(dead.version, 2);
    });

    test('re-adding a removed term resurrects its original row', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );
      final deadliftId = (await db.vocabularyDao.getAllItems())
          .firstWhere((item) => item.term == 'Deadlift')
          .id;

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press'],
      );
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );

      final revived = (await db.vocabularyDao.getAllItems()).firstWhere(
        (item) => item.term == 'Deadlift',
      );
      expect(revived.id, deadliftId);
      expect(revived.isDeleted, isFalse);
      expect(revived.deletedAt, isNull);
      expect(await allItems(), hasLength(2));
    });

    test('reordering rewrites sort order without forking ids', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );
      final idsByTerm = {
        for (final item in await db.vocabularyDao.getAllItems())
          item.term: item.id,
      };

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Deadlift', 'Bench Press'],
      );

      final items = await db.vocabularyDao.getAllItems();
      expect([for (final item in items) item.term], [
        'Deadlift',
        'Bench Press',
      ]);
      expect(items.first.id, idsByTerm['Deadlift']);
      expect(items.last.id, idsByTerm['Bench Press']);
    });

    test('a repeated term is stored once', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Bench Press'],
      );

      expect(await db.vocabularyDao.getAllItems(), hasLength(1));
    });

    test('clearing the list tombstones everything', () async {
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press', 'Deadlift'],
      );

      await db.vocabularyDao.saveItems(vocabularyId: 'v1', terms: const []);

      expect(await db.vocabularyDao.getAllItems(), isEmpty);
      expect(await allItems(), hasLength(2));
    });

    test('another list is untouched', () async {
      await db.vocabularyDao.upsertVocabulary(_entry('v2', 'Meals'));
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v2',
        terms: const ['Oats'],
      );

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: const ['Bench Press'],
      );

      final items = await db.vocabularyDao.getAllItems();
      expect(items.map((item) => item.term), containsAll(['Oats', 'Bench Press']));
    });
  });

  group('ordering', () {
    test('lists by sort order, then id for a tie', () async {
      await db.vocabularyDao.upsertVocabulary(
        _entry('zzz', 'Later', sortOrder: 0),
      );
      await db.vocabularyDao.upsertVocabulary(_entry('aaa', 'Tie', sortOrder: 0));
      await db.vocabularyDao.upsertVocabulary(
        _entry('mmm', 'First', sortOrder: -1),
      );

      final ids = [
        for (final row in await db.vocabularyDao.getAllVocabularies()) row.id,
      ];
      expect(ids, ['mmm', 'aaa', 'zzz']);
    });

    test('nextSortOrder counts tombstones so a slot is never reused', () async {
      await db.vocabularyDao.upsertVocabulary(
        _entry('v1', 'Exercises', sortOrder: 0),
      );
      await db.vocabularyDao.upsertVocabulary(
        _entry('v2', 'Meals', sortOrder: 1),
      );
      await db.vocabularyDao.softDeleteVocabularyById('v2');

      expect(await db.vocabularyDao.nextSortOrder(), 2);
    });

    test('nextSortOrder starts at zero on an empty table', () async {
      expect(await db.vocabularyDao.nextSortOrder(), 0);
    });

    test('reorder rewrites positions and skips rows already in place', () async {
      await db.vocabularyDao.upsertVocabulary(
        _entry('v1', 'Exercises', sortOrder: 0),
      );
      await db.vocabularyDao.upsertVocabulary(
        _entry('v2', 'Meals', sortOrder: 1),
      );
      await db.vocabularyDao.upsertVocabulary(
        _entry('v3', 'Clients', sortOrder: 2),
      );
      final untouched = await vocabularyFor('v3');

      await db.vocabularyDao.reorderVocabularies(['v2', 'v1', 'v3']);

      final ids = [
        for (final row in await db.vocabularyDao.getAllVocabularies()) row.id,
      ];
      expect(ids, ['v2', 'v1', 'v3']);
      expect((await vocabularyFor('v3')).version, untouched.version);
    });
  });

  group('the v32 migration', () {
    Future<void> dropVocabularies() async {
      await db.customStatement('DROP TABLE IF EXISTS vocabulary_items');
      await db.customStatement('DROP TABLE IF EXISTS vocabularies');
    }

    Future<void> runV32() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v31CalendarDeltaIndexes,
        DatabaseSchema.v32Vocabularies,
      );
    }

    /// Reads untyped, so a later migration cannot break this group for reasons
    /// that have nothing to do with v32.
    Future<List<QueryRow>> vocabularyRows() {
      return db.customSelect('SELECT * FROM vocabularies').get();
    }

    test('creates both tables on an upgrader', () async {
      await dropVocabularies();
      await runV32();

      expect(await vocabularyRows(), isEmpty);
      expect(
        await db.customSelect('SELECT * FROM vocabulary_items').get(),
        isEmpty,
      );
    });

    test('re-running it is a no-op and keeps existing rows', () async {
      await dropVocabularies();
      await runV32();
      await db.customStatement(
        'INSERT INTO vocabularies '
        '(id, name, created_at, updated_at, hlc_timestamp, device_id) '
        "VALUES ('v1', 'Exercises', 0, 0, 'hlc', 'dev')",
      );

      await runV32();

      final rows = await vocabularyRows();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('name'), 'Exercises');
    });

    test('the defaults an insert relies on are the frozen ones', () async {
      await dropVocabularies();
      await runV32();
      await db.customStatement(
        'INSERT INTO vocabularies '
        '(id, name, created_at, updated_at, hlc_timestamp, device_id) '
        "VALUES ('v1', 'Exercises', 0, 0, 'hlc', 'dev')",
      );
      await db.customStatement(
        'INSERT INTO vocabulary_items '
        '(id, vocabulary_id, term, created_at, updated_at, hlc_timestamp, '
        'device_id) '
        "VALUES ('i1', 'v1', 'Bench Press', 0, 0, 'hlc', 'dev')",
      );

      final vocabulary = (await vocabularyRows()).single;
      expect(vocabulary.read<int>('is_enabled'), 1);
      expect(vocabulary.read<int>('sort_order'), 0);
      expect(vocabulary.read<int>('version'), 1);
      expect(vocabulary.read<int>('is_deleted'), 0);

      final item = (await db
              .customSelect('SELECT * FROM vocabulary_items')
              .get())
          .single;
      expect(item.read<int>('sort_order'), 0);
      expect(item.read<int>('version'), 1);
      expect(item.read<int>('is_deleted'), 0);
    });
  });
}

VocabulariesCompanion _entry(
  String id,
  String name, {
  DateTime? createdAt,
  int sortOrder = 0,
}) {
  return VocabulariesCompanion(
    id: Value(id),
    name: Value(name),
    sortOrder: Value(sortOrder),
    createdAt: Value(createdAt ?? DateTime.utc(2024, 1, 1)),
    updatedAt: Value(createdAt ?? DateTime.utc(2024, 1, 1)),
  );
}
