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
