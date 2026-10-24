// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `VocabularyDao.mergeRemoteVocabulary` and
/// `mergeRemoteVocabularyItem`: the shared contract on both tables, and
/// terms stored as received under a vocabulary tombstoned here.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  final created = DateTime.utc(2026, 4, 1).toLocal();

  Future<void> seedVocabulary(AppDatabase db, String id) {
    return db.vocabularyDao.importVocabulary(
      VocabulariesCompanion(
        id: Value(id),
        name: const Value('Exercises'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );
  }

  Future<void> seedItem(AppDatabase db, String id) {
    return db.vocabularyDao.importItem(
      VocabularyItemsCompanion(
        id: Value(id),
        vocabularyId: const Value('v1'),
        term: const Value('Squat'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );
  }

  VocabularyRow remoteVocabulary(
    String id,
    String hlc, {
    bool deleted = false,
  }) {
    return VocabularyRow(
      id: id,
      name: 'Pulled',
      isEnabled: false,
      sortOrder: 4,
      createdAt: DateTime.utc(2026, 5, 1).toLocal(),
      updatedAt: DateTime.utc(2026, 5, 2).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 5, 3).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  VocabularyItemRow remoteItem(String id, String hlc, {bool deleted = false}) {
    return VocabularyItemRow(
      id: id,
      vocabularyId: 'v1',
      term: 'Pulled',
      sortOrder: 2,
      createdAt: DateTime.utc(2026, 5, 1).toLocal(),
      updatedAt: DateTime.utc(2026, 5, 2).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 5, 3).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  runMergeContract(
    MergeContract<VocabularyRow>(
      table: 'vocabularies',
      freshKey: 'pulled',
      seedLocal: (db) async {
        await seedVocabulary(db, 'v1');
        return 'v1';
      },
      remote: remoteVocabulary,
      merge: (db, row, {floor}) =>
          db.vocabularyDao.mergeRemoteVocabulary(row, floor: floor),
      markerColumn: 'name',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  runMergeContract(
    MergeContract<VocabularyItemRow>(
      table: 'vocabulary_items',
      freshKey: 'pulled',
      seedLocal: (db) async {
        await seedItem(db, 'i1');
        return 'i1';
      },
      remote: remoteItem,
      merge: (db, row, {floor}) =>
          db.vocabularyDao.mergeRemoteVocabularyItem(row, floor: floor),
      markerColumn: 'term',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a term under a vocabulary tombstoned here still merges', () async {
    await seedVocabulary(db, 'v1');
    await seedItem(db, 'i1');
    await db.vocabularyDao.softDeleteVocabularyById('v1');

    final inserted = await db.vocabularyDao.mergeRemoteVocabularyItem(
      remoteItem('i2', newerHlc),
    );
    final applied = await db.vocabularyDao.mergeRemoteVocabularyItem(
      remoteItem('i1', newerHlc),
    );

    expect(inserted.result, MergeResult.inserted);
    expect(applied.result, MergeResult.applied);
    final rows = await db.select(db.vocabularyItems).get();
    expect(rows.map((r) => (r.id, r.isDeleted)), [
      ('i1', false),
      ('i2', false),
    ]);
  });

  test('a vocabulary tombstone cascades to no term', () async {
    await seedVocabulary(db, 'v1');
    await seedItem(db, 'i1');

    await db.vocabularyDao.mergeRemoteVocabulary(
      remoteVocabulary('v1', newerHlc, deleted: true),
    );

    final item = await db.select(db.vocabularyItems).getSingle();
    expect(item.isDeleted, isFalse);
    final vocabulary = await db.select(db.vocabularies).getSingle();
    expect(vocabulary.isDeleted, isTrue);
    expect(vocabulary.name, 'Exercises');
  });

  test('a newer vocabulary overwrites every data column', () async {
    await seedVocabulary(db, 'v1');

    await db.vocabularyDao.mergeRemoteVocabulary(
      remoteVocabulary('v1', newerHlc),
    );

    expect(
      await db.select(db.vocabularies).getSingle(),
      remoteVocabulary('v1', newerHlc),
    );
  });
}
