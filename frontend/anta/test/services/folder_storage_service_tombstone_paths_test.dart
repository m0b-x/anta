import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_storage_service.dart';

import '../database/support/db_test_support.dart';

/// A live folder can sit under a deleted one while the sync folder repair
/// waits, and a note under a deleted folder until the notes repair re-files
/// it. The paths search and All notes show, and the crumbs the browser and the
/// picker build, must never show a tombstone — by its name, or by the id a
/// data-less tombstone carries for one (P review PR2, PR3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FolderStorageService folders;

  // Training (live) > Block (a data-less tombstone) > Legs (live) > Gone
  // (deleted here, its real name kept).
  late String trainingId;
  late String blockId;
  late String legsId;
  late String goneId;

  setUp(() async {
    db = await openTestDatabase();
    folders = FolderStorageService(repository: FolderRepository(database: db));
    await folders.initialize();
    trainingId = (await db.folderDao.createFolder(name: 'Training')).id;
    blockId = (await db.folderDao.createFolder(
      name: 'Block',
      parentId: trainingId,
    )).id;
    legsId = (await db.folderDao.createFolder(
      name: 'Legs',
      parentId: blockId,
    )).id;
    goneId = (await db.folderDao.createFolder(
      name: 'Gone',
      parentId: legsId,
    )).id;
    await db.customStatement(
      'UPDATE folders SET name = id, is_deleted = 1 WHERE id = ?',
      [blockId],
    );
    await db.customStatement('UPDATE folders SET is_deleted = 1 WHERE id = ?', [
      goneId,
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  group('folderPathSegments', () {
    test('cuts the path where the crumbs cut it: nothing above the last '
        'tombstone (P fix pass PF-L9)', () async {
      final paths = await folders.folderPathSegments([legsId]);

      expect(paths[legsId], ['Legs']);
    });

    test("leaves the folder's own tombstone out: the path is the nearest "
        'live folder\'s', () async {
      final paths = await folders.folderPathSegments([goneId, blockId]);

      expect(paths[goneId], ['Legs']);
      expect(paths[blockId], ['Training']);
    });

    test('a live chain is unchanged', () async {
      final paths = await folders.folderPathSegments([trainingId]);

      expect(paths[trainingId], ['Training']);
    });
  });

  group('getAncestors', () {
    test('keeps tombstones by default', () async {
      final ancestors = await folders.getAncestors(goneId);

      expect([for (final f in ancestors) f.id], [trainingId, blockId, legsId]);
    });

    test('stopAtDeleted cuts the chain at the first tombstone', () async {
      final ancestors = await folders.getAncestors(goneId, stopAtDeleted: true);

      expect([for (final f in ancestors) f.id], [legsId]);
    });

    test('stopAtDeleted keeps a chain with no tombstone whole', () async {
      final ancestors = await folders.getAncestors(
        blockId,
        stopAtDeleted: true,
      );

      expect([for (final f in ancestors) f.id], [trainingId]);
    });
  });
}
