import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/daos/folder_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// The two recursive folder walks — `getAllDescendantIds` and
/// `noteCountsWithDescendants` — had no depth bound, so a `parent_id` cycle
/// spun the CTE until SQLite ran out of memory. The UI cannot make one; a
/// merge or a hand-edited database can, and the browser runs both queries on
/// every folder page.
///
/// The cycle is written with raw SQL because the DAO deliberately refuses to
/// build one. Every assertion carries a timeout: the failure mode under test
/// is "never returns", which a plain `await` would express as a hung suite.
void main() {
  late AppDatabase db;
  const budget = Duration(seconds: 10);

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<(String, String)> seedCycle() async {
    final a = await db.folderDao.createFolder(name: 'A');
    final b = await db.folderDao.createFolder(name: 'B', parentId: a.id);
    await db.customStatement('UPDATE folders SET parent_id = ? WHERE id = ?', [
      b.id,
      a.id,
    ]);
    return (a.id, b.id);
  }

  test('a two-folder cycle returns rather than hangs', () async {
    final (rootId, childId) = await seedCycle();

    final ids = await db.folderDao
        .getAllDescendantIds(rootId)
        .timeout(budget);

    expect(ids, contains(childId));
    expect(
      ids.length,
      lessThanOrEqualTo(FolderDao.maxFolderDepth + 1),
      reason:
          'the walk must stop at the depth guard, not enumerate the cycle '
          'until SQLite gives up',
    );
  });

  test('the counts CTE returns on a cycle too', () async {
    final (rootId, childId) = await seedCycle();
    await db.noteDao.createNote(
      folderId: childId,
      title: 'In the cycle',
      preview: '',
      contentLength: 0,
      chunkCount: 1,
    );

    final counts = await db.folderDao
        .noteCountsWithDescendants([rootId, childId])
        .timeout(budget);

    expect(counts.keys, containsAll(<String>[rootId, childId]));
    expect(counts[rootId], greaterThan(0));
  });

  test('an acyclic tree is unaffected by the guard', () async {
    final a = await db.folderDao.createFolder(name: 'A');
    final b = await db.folderDao.createFolder(name: 'B', parentId: a.id);
    final c = await db.folderDao.createFolder(name: 'C', parentId: b.id);
    await db.noteDao.createNote(
      folderId: c.id,
      title: 'Deep note',
      preview: '',
      contentLength: 0,
      chunkCount: 1,
    );

    expect(await db.folderDao.getAllDescendantIds(a.id), [b.id, c.id]);
    expect(await db.folderDao.noteCountsWithDescendants([a.id]), {a.id: 1});
  });
}
