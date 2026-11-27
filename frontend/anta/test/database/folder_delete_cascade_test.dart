import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/daos/sync_dao.dart';
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

  test('a live folder a merge left under a tombstoned middle folder goes with '
      'its ancestor, and the tombstone is not stamped again (B8)', () async {
    final top = await db.folderDao.createFolder(name: 'Training');
    final middle = await db.folderDao.createFolder(
      name: 'Legs',
      parentId: top.id,
    );
    final stranded = await db.folderDao.createFolder(
      name: 'Squats',
      parentId: middle.id,
    );
    Future<Note> noteIn(String folderId) => db.noteDao.createNote(
      folderId: folderId,
      title: 'Set',
      preview: '',
      contentLength: 0,
      chunkCount: 0,
    );
    final inStranded = await noteIn(stranded.id);
    final inMiddle = await noteIn(middle.id);
    // Deleted on another device while its child was written here: the merge
    // never cascades, so only a merge leaves this.
    await db.customStatement('UPDATE folders SET is_deleted = 1 WHERE id = ?', [
      middle.id,
    ]);
    final middleBefore = await (db.select(
      db.folders,
    )..where((f) => f.id.equals(middle.id))).getSingle();
    await db.syncOutboxDao.clear();

    final cascade = await db.folderDao.softDeleteFolderWithDescendants(top.id);

    Future<bool> folderDeleted(String id) async => (await (db.select(
      db.folders,
    )..where((f) => f.id.equals(id))).getSingle()).isDeleted;
    Future<bool> noteDeleted(String id) async => (await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle()).isDeleted;
    expect(await folderDeleted(stranded.id), isTrue);
    expect(await noteDeleted(inStranded.id), isTrue);
    expect(await noteDeleted(inMiddle.id), isTrue);
    expect(
      await (db.select(
        db.folders,
      )..where((f) => f.id.equals(middle.id))).getSingle(),
      middleBefore,
      reason: 'a tombstone the delete passes through keeps its own stamp',
    );
    expect(cascade.folderIds, unorderedEquals([top.id, stranded.id]));
    expect(cascade.tombstonesPassed, [middle.id]);
    expect(cascade.noteFolders, {
      inStranded.id: stranded.id,
      inMiddle.id: middle.id,
    });
    final queued = await db.syncOutboxDao.pending(limit: 10);
    expect(
      {for (final row in queued) row.rowKey},
      {top.id, stranded.id, inStranded.id, inMiddle.id},
    );
  });

  group('the walk through tombstones', () {
    /// A folder row as a merge stores it, written beside the DAO.
    Future<void> folder(String id, String? parent, {bool deleted = false}) =>
        db.customStatement(
          'INSERT INTO folders (id, name, parent_id, created_at, updated_at, '
          'hlc_timestamp, device_id, is_deleted) '
          "VALUES (?, ?, ?, 0, 0, 'h', 'd', ?)",
          [id, id, parent, deleted ? 1 : 0],
        );
    Future<Note> noteIn(String folderId) => db.noteDao.createNote(
      folderId: folderId,
      title: 'Set',
      preview: '',
      contentLength: 0,
      chunkCount: 0,
    );
    Future<Folder> row(String id) =>
        (db.select(db.folders)..where((f) => f.id.equals(id))).getSingle();
    Future<List<String>> live(Iterable<String> ids) async => [
      for (final id in ids)
        if (!(await row(id)).isDeleted) id,
    ];
    Future<List<String>> queuedKeys() async => [
      for (final r in await db.syncOutboxDao.pending(limit: 100)) r.rowKey,
    ];

    test('reaches as deep as getAllDescendantIds below the root, tombstones '
        'counted as levels', () async {
      // Two chains of 68 levels; the second has a tombstone at level 30.
      for (final chain in ['a', 'b']) {
        for (var i = 0; i < 68; i++) {
          await folder(
            '$chain$i',
            i == 0 ? null : '$chain${i - 1}',
            deleted: chain == 'b' && i == 30,
          );
        }
      }
      final reached = await db.folderDao.getAllDescendantIds('a0');

      await db.folderDao.softDeleteFolderWithDescendants('a0');
      await db.folderDao.softDeleteFolderWithDescendants('b0');

      final levels = [for (var i = 1; i < 68; i++) i];
      expect(await live([for (final i in levels) 'a$i']), [
        for (final i in levels)
          if (!reached.contains('a$i')) 'a$i',
      ]);
      expect(await live([for (final i in levels) 'a$i']), ['a66', 'a67']);
      expect(await live([for (final i in levels) 'b$i']), ['b66', 'b67']);
    });

    test('the delete confirm counts the notes under a folder deleted '
        'elsewhere, as the delete removes them', () async {
      await folder('top', null);
      await folder('middle', 'top', deleted: true);
      await folder('stranded', 'middle');
      for (final id in ['top', 'middle', 'stranded']) {
        await noteIn(id);
      }

      final counted = await db.folderDao.getNoteCountWithDescendants('top');
      final cascade = await db.folderDao.softDeleteFolderWithDescendants('top');

      expect(counted, 3);
      expect(cascade.noteFolders, hasLength(counted));
    });

    test('ends on a cycle through a deleted folder, each row written and '
        'queued once', () async {
      await folder('l1', null);
      await folder('t', 'l1', deleted: true);
      await folder('l2', 't');
      await db.customStatement(
        "UPDATE folders SET parent_id = 'l2' WHERE id = 'l1'",
      );
      final before = await row('t');
      await db.syncOutboxDao.clear();

      await db.folderDao
          .softDeleteFolderWithDescendants('l1')
          .timeout(const Duration(seconds: 10));

      expect(await live(['l1', 'l2']), isEmpty);
      expect(await row('t'), before);
      expect(await queuedKeys(), unorderedEquals(['l1', 'l2']));
    });

    test('ends on a deleted folder that is its own parent', () async {
      await folder('s', 's', deleted: true);
      await folder('child', 's');
      final before = await row('s');
      await db.syncOutboxDao.clear();

      final cascade = await db.folderDao
          .softDeleteFolderWithDescendants('s')
          .timeout(const Duration(seconds: 10));

      expect(await live(['child']), isEmpty);
      expect(await row('s'), before);
      expect(cascade.tombstonesPassed, ['s']);
      expect(await queuedKeys(), ['child']);
    });

    test('leaves a partner\'s folder and note under a deleted middle folder '
        'alone, the fences armed', () async {
      await folder('top', null);
      await folder('middle', 'top', deleted: true);
      await folder('theirs', 'middle');
      final theirNote = await noteIn('theirs');
      for (final (table, id) in [
        ('folders', 'theirs'),
        ('notes', theirNote.id),
      ]) {
        await db.customStatement(
          "UPDATE $table SET owner_id = 'partner' WHERE id = ?",
          [id],
        );
      }
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      final folderBefore = await row('theirs');
      final noteBefore = await db.noteDao.getNoteById(theirNote.id);
      await db.syncOutboxDao.clear();

      final cascade = await db.folderDao.softDeleteFolderWithDescendants('top');

      expect(await row('theirs'), folderBefore);
      expect(await db.noteDao.getNoteById(theirNote.id), noteBefore);
      expect(cascade.folderIds, ['top']);
      expect(cascade.noteFolders, isEmpty);
      expect(await queuedKeys(), ['top']);
    });
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
