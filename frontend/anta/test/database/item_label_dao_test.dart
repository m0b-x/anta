import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';

import 'support/db_test_support.dart';

/// The write half of colour labels: the CRDT bookkeeping a label write owes,
/// the refusal a tombstone is owed, the single statement a bulk label must
/// stay, and the fact that a merge carries the column in **both** of its
/// branches — the insert one is the easy one to forget, and forgetting it
/// silently repaints every note a sync brings in.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Folder> seedFolder([String name = 'Training']) {
    return db.folderDao.createFolder(name: name);
  }

  Future<Note> seedNote(String folderId, [String title = 'Log']) {
    return db.noteDao.createNote(
      folderId: folderId,
      title: title,
      preview: '',
      contentLength: 0,
      chunkCount: 1,
    );
  }

  group('creating', () {
    test('a note and a folder default to unlabelled', () async {
      final folder = await seedFolder();
      final note = await seedNote(folder.id);

      expect(ItemLabel.fromStorage(folder.label), ItemLabel.none);
      expect(ItemLabel.fromStorage(note.label), ItemLabel.none);
    });

    test('createNote and createFolder carry a label when given one', () async {
      final folder = await db.folderDao.createFolder(
        name: 'Money',
        label: ItemLabel.blue,
      );
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Groceries',
        label: ItemLabel.pink,
      );

      expect(ItemLabel.fromStorage(folder.label), ItemLabel.blue);
      expect(ItemLabel.fromStorage(note.label), ItemLabel.pink);
    });

    test('importNote and importFolder carry a label too', () async {
      final when = DateTime(2025, 3, 4);
      final folder = await db.folderDao.importFolder(
        name: 'Imported',
        createdAt: when,
        label: ItemLabel.green,
      );
      final note = await db.noteDao.importNote(
        folderId: folder.id,
        title: 'Imported note',
        createdAt: when,
        updatedAt: when,
        label: ItemLabel.teal,
      );

      expect(ItemLabel.fromStorage(folder.label), ItemLabel.green);
      expect(ItemLabel.fromStorage(note.label), ItemLabel.teal);
      expect(note.createdAt, when, reason: 'import preserves its timestamps');
    });
  });

  group('updateNoteLabel', () {
    test('writes the label, bumps version and moves the HLC', () async {
      final folder = await seedFolder();
      final note = await seedNote(folder.id);

      final updated = await db.noteDao.updateNoteLabel(
        id: note.id,
        label: ItemLabel.orange,
      );

      expect(updated, isNotNull);
      expect(ItemLabel.fromStorage(updated!.label), ItemLabel.orange);
      expect(updated.version, note.version + 1);
      expect(updated.hlcTimestamp, isNot(note.hlcTimestamp));
      expect(updated.deviceId, db.deviceId);
    });

    test('refuses a tombstone', () async {
      final folder = await seedFolder();
      final note = await seedNote(folder.id);
      await db.noteDao.softDeleteNoteWithChunks(note.id);
      final tombstone = await db.noteDao.getNoteById(note.id);

      final result = await db.noteDao.updateNoteLabel(
        id: note.id,
        label: ItemLabel.red,
      );

      expect(result, isNull);
      final after = await db.noteDao.getNoteById(note.id);
      expect(after!.version, tombstone!.version);
      expect(after.hlcTimestamp, tombstone.hlcTimestamp);
      expect(ItemLabel.fromStorage(after.label), ItemLabel.none);
    });

    test('a missing note is null, not a crash', () async {
      expect(
        await db.noteDao.updateNoteLabel(id: 'nope', label: ItemLabel.red),
        isNull,
      );
    });

    test('leaves updated_at alone, so labelling does not say "edited"',
        () async {
      final folder = await seedFolder();
      final note = await seedNote(folder.id);

      final updated = await db.noteDao.updateNoteLabel(
        id: note.id,
        label: ItemLabel.orange,
      );

      expect(
        updated!.updatedAt,
        note.updatedAt,
        reason:
            'a label edits nothing in the note; carrying it to the top of '
            'the "last updated" sort is what this write must not do',
      );
      final reread = await db.noteDao.getNoteById(note.id);
      expect(reread!.updatedAt, note.updatedAt);
    });

    test('writing the label it already has is a no-op', () async {
      final folder = await seedFolder();
      final note = await seedNote(folder.id);
      final labelled = await db.noteDao.updateNoteLabel(
        id: note.id,
        label: ItemLabel.green,
      );

      final again = await db.noteDao.updateNoteLabel(
        id: note.id,
        label: ItemLabel.green,
      );

      expect(again, isNotNull);
      expect(again!.version, labelled!.version);
      expect(again.hlcTimestamp, labelled.hlcTimestamp);
      expect(again.updatedAt, labelled.updatedAt);
      final reread = await db.noteDao.getNoteById(note.id);
      expect(reread!.version, labelled.version);
      expect(
        reread.hlcTimestamp,
        labelled.hlcTimestamp,
        reason: 'a row that did not change must not travel on the next sync',
      );
    });
  });

  group('updateFolderLabel', () {
    test('writes the label, bumps version and moves the HLC', () async {
      final folder = await seedFolder();

      final updated = await db.folderDao.updateFolderLabel(
        id: folder.id,
        label: ItemLabel.yellow,
      );

      expect(updated, isNotNull);
      expect(ItemLabel.fromStorage(updated!.label), ItemLabel.yellow);
      expect(updated.version, folder.version + 1);
      expect(updated.hlcTimestamp, isNot(folder.hlcTimestamp));
    });

    test('refuses a tombstone', () async {
      final folder = await seedFolder();
      await db.folderDao.softDeleteFolder(folder.id);

      expect(
        await db.folderDao.updateFolderLabel(
          id: folder.id,
          label: ItemLabel.red,
        ),
        isNull,
      );
    });
  });

  group('bulk labelling', () {
    test('labelling 20 notes is one UPDATE, whatever the count', () async {
      await db.close();
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);

      final folder = await counted.folderDao.createFolder(name: 'Training');
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        final note = await counted.noteDao.createNote(
          folderId: folder.id,
          title: 'Note $i',
        );
        ids.add(note.id);
      }

      counter.reset();
      final changed = await counted.noteDao.updateLabelForNotes(
        ids: ids,
        label: ItemLabel.blue,
      );

      expect(changed, 20);
      expect(
        counter.count,
        1,
        reason:
            'updateLabelForNotes must stay one `UPDATE … WHERE id IN (…)`. '
            'SQL does the version + 1 arithmetic itself, so a per-row loop '
            'would be a silent O(rows) regression. Issued:\n'
            '${counter.statements.join('\n')}',
      );

      final rows = await counted.noteDao.getNotesByIds(ids);
      expect(
        rows.every((n) => ItemLabel.fromStorage(n.label) == ItemLabel.blue),
        isTrue,
      );
      expect(rows.every((n) => n.version == 2), isTrue);
    });

    test('labelling folders is one UPDATE as well', () async {
      await db.close();
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);

      final ids = <String>[];
      for (var i = 0; i < 12; i++) {
        final folder = await counted.folderDao.createFolder(name: 'F$i');
        ids.add(folder.id);
      }

      counter.reset();
      final changed = await counted.folderDao.updateLabelForFolders(
        ids: ids,
        label: ItemLabel.pink,
      );

      expect(changed, 12);
      expect(
        counter.count,
        1,
        reason: 'issued:\n${counter.statements.join('\n')}',
      );
    });

    test('an empty id list touches the database not at all', () async {
      await db.close();
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);

      counter.reset();
      expect(
        await counted.noteDao.updateLabelForNotes(
          ids: const [],
          label: ItemLabel.red,
        ),
        0,
      );
      expect(
        await counted.folderDao.updateLabelForFolders(
          ids: const [],
          label: ItemLabel.red,
        ),
        0,
      );
      expect(counter.count, 0);
    });

    test('a tombstoned note in the selection is skipped', () async {
      final folder = await seedFolder();
      final live = await seedNote(folder.id, 'Live');
      final dead = await seedNote(folder.id, 'Dead');
      await db.noteDao.softDeleteNoteWithChunks(dead.id);

      final changed = await db.noteDao.updateLabelForNotes(
        ids: [live.id, dead.id],
        label: ItemLabel.green,
      );

      expect(changed, 1);
      final after = await db.noteDao.getNoteById(dead.id);
      expect(ItemLabel.fromStorage(after!.label), ItemLabel.none);
    });

    test('a tombstoned folder in the selection is skipped', () async {
      final live = await seedFolder('Live');
      final dead = await seedFolder('Dead');
      await db.folderDao.softDeleteFolder(dead.id);
      final tombstone = await db.folderDao.getFolderById(dead.id);

      final changed = await db.folderDao.updateLabelForFolders(
        ids: [live.id, dead.id],
        label: ItemLabel.teal,
      );

      expect(changed, 1);
      final after = await db.folderDao.getFolderById(dead.id);
      expect(ItemLabel.fromStorage(after!.label), ItemLabel.none);
      expect(after.version, tombstone!.version);
      expect(
        after.hlcTimestamp,
        tombstone.hlcTimestamp,
        reason: 'a bulk label must not resurrect a deleted folder on merge',
      );
    });

    test('leaves updated_at alone for every row it does touch', () async {
      final folder = await seedFolder();
      final first = await seedNote(folder.id, 'One');
      final second = await seedNote(folder.id, 'Two');

      final changed = await db.noteDao.updateLabelForNotes(
        ids: [first.id, second.id],
        label: ItemLabel.pink,
      );

      expect(changed, 2);
      final rows = await db.noteDao.getNotesByIds([first.id, second.id]);
      final byId = {for (final row in rows) row.id: row};
      expect(byId[first.id]!.updatedAt, first.updatedAt);
      expect(byId[second.id]!.updatedAt, second.updatedAt);
    });

    test('counts only the rows whose colour actually moves', () async {
      final folder = await seedFolder();
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        final note = await seedNote(folder.id, 'Note $i');
        ids.add(note.id);
      }
      final alreadyBlue = ids.take(5).toList(growable: false);
      await db.noteDao.updateLabelForNotes(
        ids: alreadyBlue,
        label: ItemLabel.blue,
      );
      final before = await db.noteDao.getNotesByIds(alreadyBlue);
      final versionsBefore = {for (final row in before) row.id: row.version};

      final changed = await db.noteDao.updateLabelForNotes(
        ids: ids,
        label: ItemLabel.blue,
      );

      expect(
        changed,
        15,
        reason:
            'the `label <> ?` clause is what keeps a selection that is mostly '
            'that colour already from re-stamping every row',
      );
      final after = await db.noteDao.getNotesByIds(alreadyBlue);
      for (final row in after) {
        expect(row.version, versionsBefore[row.id]);
      }
    });

    test('a duplicated id is one row, not two', () async {
      final folder = await seedFolder();
      final note = await seedNote(folder.id);

      final changed = await db.noteDao.updateLabelForNotes(
        ids: [note.id, note.id],
        label: ItemLabel.yellow,
      );

      expect(changed, 1);
      final after = await db.noteDao.getNoteById(note.id);
      expect(after!.version, note.version + 1);
    });

    test('a duplicated folder id is one row too', () async {
      final folder = await seedFolder();

      final changed = await db.folderDao.updateLabelForFolders(
        ids: [folder.id, folder.id],
        label: ItemLabel.yellow,
      );

      expect(changed, 1);
      final after = await db.folderDao.getFolderById(folder.id);
      expect(after!.version, folder.version + 1);
    });
  });

  group('the label survives the writes around it', () {
    test('a title edit keeps it, and the FTS row finds it', () async {
      final folder = await seedFolder();
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Zercher carry',
        preview: 'heavy',
        contentLength: 5,
        chunkCount: 1,
      );
      await db.noteDao.updateNoteLabel(id: note.id, label: ItemLabel.red);

      final hits = await db.noteDao.fullTextSearch('Zercher');
      expect(hits, hasLength(1));
      expect(
        ItemLabel.fromStorage(hits.single.label),
        ItemLabel.red,
        reason:
            'fullTextSearch hand-builds its Note rows; a column left out of '
            'that list reads as the default on every search result',
      );

      await db.noteDao.updateNote(id: note.id, title: 'Zercher carries');

      final after = await db.noteDao.getNoteById(note.id);
      expect(ItemLabel.fromStorage(after!.label), ItemLabel.red);
      final renamed = await db.noteDao.fullTextSearch('carries');
      expect(ItemLabel.fromStorage(renamed.single.label), ItemLabel.red);
    });

    test('a move to another folder keeps it', () async {
      final source = await seedFolder('Source');
      final target = await seedFolder('Target');
      final note = await seedNote(source.id);
      await db.noteDao.updateNoteLabel(id: note.id, label: ItemLabel.teal);

      final moved = await db.noteDao.moveNote(
        id: note.id,
        targetFolderId: target.id,
      );

      expect(moved!.folderId, target.id);
      expect(ItemLabel.fromStorage(moved.label), ItemLabel.teal);
    });

    test('a reorder keeps it', () async {
      final folder = await seedFolder();
      final first = await seedNote(folder.id, 'One');
      final second = await seedNote(folder.id, 'Two');
      await db.noteDao.updateNoteLabel(id: first.id, label: ItemLabel.orange);
      await db.noteDao.updateNoteLabel(id: second.id, label: ItemLabel.pink);

      // What `MixedReorderService` calls through `NoteRepository`.
      await db.noteDao.setNotePositions({first.id: 1, second.id: 0});

      final rows = await db.noteDao.getNotesByIds([first.id, second.id]);
      final byId = {for (final row in rows) row.id: row};
      expect(byId[first.id]!.position, 1);
      expect(byId[second.id]!.position, 0);
      expect(ItemLabel.fromStorage(byId[first.id]!.label), ItemLabel.orange);
      expect(ItemLabel.fromStorage(byId[second.id]!.label), ItemLabel.pink);
    });

    test('a folder rename keeps it', () async {
      final folder = await seedFolder();
      await db.folderDao.updateFolderLabel(
        id: folder.id,
        label: ItemLabel.green,
      );

      await db.folderDao.updateFolder(id: folder.id, name: 'Renamed');

      final after = await db.folderDao.getFolderById(folder.id);
      expect(after!.name, 'Renamed');
      expect(ItemLabel.fromStorage(after.label), ItemLabel.green);
    });
  });

  group('merging', () {
    test('mergeNote carries the label into a brand-new row', () async {
      final folder = await seedFolder();
      final local = await seedNote(folder.id);
      final remote = local.copyWith(
        id: 'remote-note',
        label: ItemLabel.teal.storageValue,
        hlcTimestamp: 'ffffffffffff:0001:remote',
      );

      await db.noteDao.mergeNote(remote);

      final stored = await db.noteDao.getNoteById('remote-note');
      expect(ItemLabel.fromStorage(stored!.label), ItemLabel.teal);
    });

    test('mergeNote carries the label on the update branch', () async {
      final folder = await seedFolder();
      final local = await seedNote(folder.id);
      final remote = local.copyWith(
        label: ItemLabel.red.storageValue,
        hlcTimestamp: 'ffffffffffff:0001:remote',
        version: local.version + 1,
      );

      await db.noteDao.mergeNote(remote);

      final stored = await db.noteDao.getNoteById(local.id);
      expect(ItemLabel.fromStorage(stored!.label), ItemLabel.red);
    });

    test('mergeFolder carries the label in both branches', () async {
      final local = await seedFolder();

      await db.folderDao.mergeFolder(
        local.copyWith(
          id: 'remote-folder',
          label: ItemLabel.orange.storageValue,
          hlcTimestamp: 'ffffffffffff:0001:remote',
        ),
      );
      await db.folderDao.mergeFolder(
        local.copyWith(
          label: ItemLabel.blue.storageValue,
          hlcTimestamp: 'ffffffffffff:0002:remote',
          version: local.version + 1,
        ),
      );

      final inserted = await db.folderDao.getFolderById('remote-folder');
      final updated = await db.folderDao.getFolderById(local.id);
      expect(ItemLabel.fromStorage(inserted!.label), ItemLabel.orange);
      expect(ItemLabel.fromStorage(updated!.label), ItemLabel.blue);
    });
  });
}
