import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';

import '../database/support/db_test_support.dart';

/// What a folder delete leaves in the caches above the database.
///
/// The cascade tombstones a whole subtree in one statement per table, and
/// every live-folder read after it skips tombstones, so nothing but the ids
/// the delete hands back can say which cached rows went with it. The folder
/// picker and the move coordinator read the folder cache directly, and the
/// editor opens a note from the note cache.
void main() {
  late AppDatabase db;
  late FolderRepository folders;
  late NoteRepository notes;
  late FolderStorageService storage;

  setUp(() async {
    db = await openTestDatabase();
    folders = FolderRepository(database: db);
    notes = NoteRepository(database: db);
    storage = FolderStorageService(repository: folders, noteRepository: notes);
  });
  tearDown(() async => db.close());

  test('the cached descendants of a deleted folder are dropped', () async {
    final a = await storage.createFolder(name: 'A');
    final b = await storage.createFolder(name: 'B', parentId: a.id);
    final c = await storage.createFolder(name: 'C', parentId: b.id);
    await folders.getFolderById(b.id);
    await folders.getFolderById(c.id);
    await folders.getFoldersByParent(b.id);

    await storage.deleteFolder(a.id);

    expect(folders.cachedFolder(b.id), isNull);
    expect(folders.cachedFolder(c.id), isNull);
    expect(await storage.getFolderById(b.id, includeDeleted: false), isNull);
    expect(await storage.getFolderById(c.id, includeDeleted: false), isNull);
    expect(
      (await folders.getFoldersByParent(b.id)).where((f) => !f.isDeleted),
      isEmpty,
    );
  });

  test('the notes a folder delete tombstoned leave every note cache and are '
      'announced as local deletions', () async {
    final a = await storage.createFolder(name: 'A');
    final b = await storage.createFolder(name: 'B', parentId: a.id);
    final note = await notes.createNote(
      folderId: b.id,
      title: 'n',
      content: 'body',
      preview: 'body',
      contentLength: 4,
      isCompressed: false,
    );
    await notes.getNoteById(note.id);
    await notes.getNotesByFolder(b.id);
    await notes.getNoteCount(b.id);
    final changes = <NoteChange>[];
    final subscription = notes.noteChanges.listen(changes.add);

    await storage.deleteFolder(a.id);
    await pumpEventQueue();
    await subscription.cancel();

    expect((await notes.getNoteById(note.id))?.isDeleted, isTrue);
    expect(await notes.getNotesByFolder(b.id), isEmpty);
    expect(await notes.getNoteCount(b.id), 0);
    expect(
      [for (final c in changes) (c.type, c.noteId, c.folderId, c.remote)],
      [(NoteChangeType.deleted, note.id, b.id, false)],
    );
  });

  test(
    'a bulk folder delete announces the notes of every picked subtree',
    () async {
      final a = await storage.createFolder(name: 'A');
      final b = await storage.createFolder(name: 'B');
      final inA = await notes.createNote(
        folderId: a.id,
        title: 'a',
        content: 'a',
        preview: 'a',
        contentLength: 1,
        isCompressed: false,
      );
      final inB = await notes.createNote(
        folderId: b.id,
        title: 'b',
        content: 'b',
        preview: 'b',
        contentLength: 1,
        isCompressed: false,
      );
      await notes.getNoteById(inA.id);
      await notes.getNoteById(inB.id);
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);

      await storage.deleteFolders([a.id, b.id]);
      await pumpEventQueue();
      await subscription.cancel();

      expect((await notes.getNoteById(inA.id))?.isDeleted, isTrue);
      expect((await notes.getNoteById(inB.id))?.isDeleted, isTrue);
      expect(
        [for (final c in changes) (c.type, c.noteId, c.folderId, c.remote)],
        unorderedEquals([
          (NoteChangeType.deleted, inA.id, a.id, false),
          (NoteChangeType.deleted, inB.id, b.id, false),
        ]),
      );
    },
  );
}
