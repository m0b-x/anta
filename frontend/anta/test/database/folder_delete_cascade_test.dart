import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards the shape of `FolderDao.softDeleteFolderWithDescendants`: the
/// subtree it reads is the subtree it writes, and no statement it issues
/// binds more ids than one batch, however large the tree.
void main() {
  late AppDatabase db;
  late StatementCounter counter;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });
  tearDown(() async => db.close());

  test('a subfolder written while the walk is read is never left live under '
      'the tombstone', () async {
    final parent = await db.folderDao.createFolder(name: 'Training');
    final order = <String>[];
    Future<void>? merge;
    counter.onStatement = (statement, _) {
      if (merge == null && statement.contains('WITH RECURSIVE')) {
        // The merge's write comes from outside the delete's zone, as a sync
        // pull's does.
        merge = Zone.root.run(
          () => db.folderDao
              .createFolder(name: 'Late', parentId: parent.id)
              .then((_) => order.add('insert')),
        );
      }
      return null;
    };

    await db.folderDao
        .softDeleteFolderWithDescendants(parent.id)
        .then((_) => order.add('delete'));
    await merge;

    final child = await (db.select(
      db.folders,
    )..where((f) => f.name.equals('Late'))).getSingle();
    expect(
      child.isDeleted || order.first == 'delete',
      isTrue,
      reason:
          'the subfolder committed before the delete ($order) yet is live '
          'under a tombstoned parent',
    );
  });

  test('a tree past one id batch is written in batches, every row '
      'tombstoned and queued', () async {
    final root = await db.folderDao.createFolder(name: 'Root');
    const count = AppConstants.sqlIdBatch + 1;
    await db.customStatement(
      'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
      'WHERE i < $count) '
      'INSERT INTO folders (id, name, parent_id, created_at, updated_at, '
      "hlc_timestamp, device_id) SELECT 'f' || i, 'f' || i, '${root.id}', "
      "0, 0, 'h', 'd' FROM n",
    );
    final note = await db.noteDao.createNote(
      folderId: 'f$count',
      title: 'Squats',
      preview: '',
      contentLength: 0,
      chunkCount: 0,
    );
    await db.syncOutboxDao.clear();
    counter.reset();

    await db.folderDao.softDeleteFolderWithDescendants(root.id);

    expect(counter.matching('UPDATE folders SET'), hasLength(2));
    expect(counter.matching('UPDATE notes SET'), hasLength(2));
    for (final statement in counter.captured) {
      expect(
        statement.args.length,
        lessThanOrEqualTo(AppConstants.sqlIdBatch + 4),
        reason: statement.sql,
      );
    }
    final folders = await db.select(db.folders).get();
    expect(folders, hasLength(count + 1));
    expect(folders.every((f) => f.isDeleted), isTrue);
    final noteRow = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(note.id))).getSingle();
    expect(noteRow.isDeleted, isTrue);
    final queued = await db.syncOutboxDao.pending(limit: count + 10);
    expect(queued, hasLength(count + 2));
  });
}
