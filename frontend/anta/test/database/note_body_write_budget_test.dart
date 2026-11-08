import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/utils/compression_utils.dart';

import '../support/scale_fixtures.dart';
import 'support/db_test_support.dart';

/// The `content_chunks` writes one auto-save of a one-character edit costs,
/// in the register of `test/bloc/calendar_occurs_on_budget_test.dart`:
/// statements, not milliseconds, and exact, so a slice that changes how a
/// body is stored shows its cost here in its own diff.
///
/// S4 (`docs/scalability-roadmap.md` §5.2) flipped these numbers: a body is
/// cut into content-defined chunks diffed by hash, so a save writes the
/// chunks the edit reached and nothing else.
///
/// A batch runs one prepared statement per row, which `executions` counts.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });

  tearDown(() async => db.close());

  /// A note holding [body], then one save of [edited] through
  /// `NoteDao.updateNote` with the arguments `NoteStorageService.updateNote`
  /// derives from the text — the auto-save path's own call — counted alone.
  Future<({int updates, int inserts, int deletes})> save(
    String body,
    String edited,
  ) async {
    final folder = await db.folderDao.createFolder(name: 'Log');
    final note = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Training log',
      preview: NoteMetadata.generatePreview(body),
      content: body,
    );
    statements.reset();
    await db.noteDao.updateNote(
      id: note.id,
      title: note.title,
      preview: NoteMetadata.generatePreview(edited),
      contentLength: edited.length,
      isCompressed: CompressionUtils.shouldCompress(edited),
      content: edited,
    );
    expect(await db.contentChunkDao.loadContent(note.id), edited);
    return (
      updates: statements.executions('UPDATE "content_chunks"'),
      inserts: statements.executions('INSERT INTO "content_chunks"'),
      deletes: statements.executions('DELETE FROM "content_chunks"'),
    );
  }

  // (size, where, edit, UPDATEs, INSERTs, DELETEs). Before S4 a body was cut
  // into fixed 10,000-unit slices, every boundary after the edit moved, and
  // the save rewrote every slice from the edit on: 10 / 6 / 1 UPDATEs at
  // 100,000 code units, 30 / 16 / 1 at 300,000, nothing inserted or
  // deleted. Content-defined chunks keep their boundaries away from the
  // edit, so the chunk that holds it is replaced — one DELETE statement, one
  // INSERT — and nothing else is written; no stored chunk is decompressed to
  // compare. Typical, not guaranteed: an edit inside the few code units that
  // decide a cut moves that boundary too, and replaces the chunk beside it.
  for (final (size, where, edit, updates, inserts, deletes) in [
    (100000, 'near the top', editNearTop, 0, 1, 1),
    (100000, 'in the middle', editInMiddle, 0, 1, 1),
    (100000, 'at the end', editAtEnd, 0, 1, 1),
    (300000, 'near the top', editNearTop, 0, 1, 1),
    (300000, 'in the middle', editInMiddle, 0, 1, 1),
    (300000, 'at the end', editAtEnd, 0, 1, 1),
    (3000000, 'near the top', editNearTop, 0, 1, 1),
    (3000000, 'in the middle', editInMiddle, 0, 1, 1),
    (3000000, 'at the end', editAtEnd, 0, 1, 1),
  ]) {
    test('one character $where of a $size-code-unit body replaces only the '
        'chunks it reaches', () async {
      final body = bigBody(size);

      final counts = await save(body, edit(body));

      expect(counts, (updates: updates, inserts: inserts, deletes: deletes));
      expect(
        counts.updates + counts.inserts + counts.deletes,
        lessThanOrEqualTo(4),
      );
    });
  }

  test(
    'a save that changes nothing stamps nothing and queues nothing',
    () async {
      final body = bigBody(100000);
      final folder = await db.folderDao.createFolder(name: 'Log');
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Training log',
        preview: NoteMetadata.generatePreview(body),
        contentLength: body.length,
        isCompressed: CompressionUtils.shouldCompress(body),
        content: body,
      );
      await db.syncOutboxDao.clear();
      statements.reset();

      final saved = await db.noteDao.updateNote(
        id: note.id,
        title: note.title,
        preview: NoteMetadata.generatePreview(body),
        contentLength: body.length,
        isCompressed: CompressionUtils.shouldCompress(body),
        content: body,
      );

      expect(saved!.hlcTimestamp, note.hlcTimestamp);
      expect(saved.version, note.version);
      expect(saved.updatedAt, note.updatedAt);
      expect(await db.syncOutboxDao.count(), 0);
      expect(statements.executions('UPDATE "notes"'), 0);
      expect(statements.executions('"content_chunks" SET'), 0);
      expect(statements.executions('INSERT INTO "content_chunks"'), 0);
      expect(statements.executions('DELETE FROM "content_chunks"'), 0);
    },
  );
}
