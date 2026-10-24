import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `FolderDao.mergeFolder`, the remote merge a pull applies to every
/// folder row: the shared contract, plus what is particular to folders.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  Folder remote(String id, String hlc, {bool deleted = false}) {
    return Folder(
      id: id,
      name: 'Pulled',
      parentId: 'parent',
      position: 4,
      label: 2,
      createdAt: DateTime.utc(2026, 1, 2).toLocal(),
      updatedAt: DateTime.utc(2026, 1, 3).toLocal(),
      noteSortOrder: 'titleAsc',
      subfolderSortOrder: 'nameDesc',
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 1, 4).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  runMergeContract(
    MergeContract<Folder>(
      table: 'folders',
      freshKey: 'pulled',
      seedLocal: (db) async =>
          (await db.folderDao.createFolder(name: 'Training')).id,
      remote: remote,
      merge: (db, row, {floor}) => db.folderDao.mergeFolder(row, floor: floor),
      markerColumn: 'name',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer remote overwrites every data column', () async {
    final local = await db.folderDao.createFolder(name: 'Training');

    await db.folderDao.mergeFolder(remote(local.id, newerHlc));

    final row = (await db.folderDao.getFolderById(local.id))!;
    final expected = remote(local.id, newerHlc);
    expect(row.name, expected.name);
    expect(row.parentId, expected.parentId);
    expect(row.position, expected.position);
    expect(row.label, expected.label);
    expect(row.noteSortOrder, expected.noteSortOrder);
    expect(row.subfolderSortOrder, expected.subfolderSortOrder);
    expect(row.createdAt, expected.createdAt);
    expect(row.updatedAt, expected.updatedAt);
    expect(row.version, 7);
  });

  test('a tombstone keeps the data columns and cascades nothing', () async {
    final local = await db.folderDao.createFolder(name: 'Training');
    final child = await db.folderDao.createFolder(
      name: 'Legs',
      parentId: local.id,
    );

    await db.folderDao.mergeFolder(remote(local.id, newerHlc, deleted: true));

    final row = (await db.folderDao.getFolderById(local.id))!;
    expect(row.isDeleted, isTrue);
    expect(row.name, 'Training');
    expect((await db.folderDao.getFolderById(child.id))!.isDeleted, isFalse);
  });
}
