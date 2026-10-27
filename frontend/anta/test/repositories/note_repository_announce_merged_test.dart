import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';

import '../database/support/db_test_support.dart';

/// What a merge's announcement carries on [NoteChange.remoteContent].
///
/// The open editor files its conflict copy from that field instead of
/// re-reading the row — a save already in flight at the event may have
/// overwritten it since (record §3.9) — so the three answers it can give are
/// a contract, not an implementation detail: null means "no body to compare
/// or keep", and the editor returns; `''` means the other device emptied the
/// note, which is a body like any other and must not read as null.
void main() {
  late AppDatabase db;
  late NoteRepository notes;

  setUp(() async {
    db = await openTestDatabase();
    notes = NoteRepository(database: db);
  });
  tearDown(() async => db.close());

  Future<Note> seed({required String folderId, String content = 'body'}) =>
      db.noteDao.createNote(
        folderId: folderId,
        title: 'Log',
        preview: content,
        contentLength: content.length,
        chunkCount: 1,
        content: content,
      );

  /// The changes [announceMerged] emits, in order.
  Future<List<NoteChange>> announced(Future<void> Function() announce) async {
    final changes = <NoteChange>[];
    final subscription = notes.noteChanges.listen(changes.add);
    await announce();
    await pumpEventQueue();
    await subscription.cancel();
    return changes;
  }

  test('a tombstone is announced without a body', () async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    final note = await seed(folderId: folder.id);
    await db.noteDao.softDeleteNoteWithChunks(note.id);

    final changes = await announced(() => notes.announceMerged([note.id]));

    expect(changes, hasLength(1));
    expect(changes.single.type, NoteChangeType.deleted);
    expect(changes.single.remoteContent, isNull);
    expect(changes.single.note, isNull, reason: 'a tombstone carries no data');
  });

  test(
    'an emptied note is announced as an empty body, not as no body',
    () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      final note = await seed(folderId: folder.id, content: '');

      final changes = await announced(() => notes.announceMerged([note.id]));

      expect(changes, hasLength(1));
      expect(changes.single.type, NoteChangeType.updated);
      expect(changes.single.remoteContent, '');
    },
  );

  test(
    'the moved change beside an update carries no body of its own',
    () async {
      final from = await db.folderDao.createFolder(name: 'Training');
      final to = await db.folderDao.createFolder(name: 'Archive');
      final note = await seed(folderId: from.id);
      await db.noteDao.mergeNoteDocument(
        note.copyWith(
          folderId: to.id,
          hlcTimestamp: 'ffffffffffff:0000:remote',
        ),
        'body',
      );

      final changes = await announced(
        () => notes.announceMerged(
          [note.id],
          previousParents: {note.id: from.id},
        ),
      );

      expect(changes.map((c) => c.type), [
        NoteChangeType.updated,
        NoteChangeType.moved,
      ]);
      expect(changes.first.remoteContent, 'body');
      expect(
        changes.last.remoteContent,
        isNull,
        reason: 'the update beside it is the one the editor compares against',
      );
      expect(changes.last.sourceFolderId, from.id);
    },
  );
}
