import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/note_storage_service.dart';

import 'support/db_test_support.dart';

/// Guards the one write that can outlive its note.
///
/// The editor's auto-save is a debounced timer: deleting a note from the
/// browser while its editor is still open (or popping the editor right after
/// the delete) lands an update on a row that is already a tombstone.
/// `getNoteById` does not filter `isDeleted`, so the write used to succeed —
/// stamping the tombstone with a fresh HLC, a bumped version and a new
/// `updatedAt`, which is exactly the shape a merge reads as "resurrect this".
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Note> seedNote({String content = 'hello'}) async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    final note = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Log',
      preview: 'hello',
      contentLength: content.length,
      chunkCount: 1,
    );
    await db.contentChunkDao.saveContent(noteId: note.id, content: content);
    return note;
  }

  Future<Note> rowFor(String id) async {
    final row = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();
    return row;
  }

  test(
    'an update after a soft delete leaves the tombstone untouched',
    () async {
      final note = await seedNote();
      await db.noteDao.softDeleteNoteWithChunks(note.id);
      final tombstone = await rowFor(note.id);

      final result = await db.noteDao.updateNote(
        id: note.id,
        title: 'Log, edited',
        preview: 'hello again',
        contentLength: 11,
        chunkCount: 1,
      );

      expect(result, isNull, reason: 'a tombstone is not updatable');

      final after = await rowFor(note.id);
      expect(after.title, 'Log');
      expect(after.version, tombstone.version);
      expect(after.hlcTimestamp, tombstone.hlcTimestamp);
      expect(after.updatedAt, tombstone.updatedAt);
      expect(after.isDeleted, isTrue);
      expect(
        await db.contentChunkDao.getChunksForNote(note.id),
        isEmpty,
        reason: 'the deleted note has no live content to serve',
      );
    },
  );

  test('a live note still updates', () async {
    final note = await seedNote();

    final result = await db.noteDao.updateNote(
      id: note.id,
      title: 'Log, edited',
      preview: 'hello again',
      contentLength: 11,
      chunkCount: 1,
    );

    expect(result, isNotNull);
    expect(result!.title, 'Log, edited');
    expect(result.version, note.version + 1);
    expect(result.isDeleted, isFalse);
  });

  test('a missing note is still a null, not a throw', () async {
    expect(await db.noteDao.updateNote(id: 'nope', title: 'x'), isNull);
  });

  /// The DAO guard alone is not enough: the repository saves the content
  /// chunks *before* it calls the DAO, so an auto-save flush reaching the
  /// service after a soft delete used to leave a deleted note holding live
  /// content — invisible in the browser, and shipped by every export and
  /// merge that reads chunks. The service is where the refusal has to be.
  test('an auto-save flush through the service writes nothing', () async {
    final service = NoteStorageService(
      repository: NoteRepository(database: db),
    );
    final folder = await db.folderDao.createFolder(name: 'Training');
    final created = await service.createNote(
      folderId: folder.id,
      title: 'Log',
      content: 'hello',
    );
    await service.deleteNote(created.id);
    final tombstone = await rowFor(created.id);

    final result = await service.updateNote(
      noteId: created.id,
      title: 'Log, edited',
      content: 'hello again',
    );

    expect(result, isNull, reason: 'a tombstone is not updatable');
    expect(
      await db.contentChunkDao.getChunksForNote(created.id),
      isEmpty,
      reason: 'the flush must not repopulate a deleted note',
    );

    final after = await rowFor(created.id);
    expect(after.title, 'Log');
    expect(after.version, tombstone.version);
    expect(after.hlcTimestamp, tombstone.hlcTimestamp);
    expect(after.updatedAt, tombstone.updatedAt);
    expect(after.isDeleted, isTrue);
  });
}
