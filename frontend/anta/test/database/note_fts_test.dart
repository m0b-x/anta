import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/migrations.dart';

import 'support/db_test_support.dart';

/// Guards `notes_fts`, an external-content FTS5 table (`content=notes`):
/// FTS5 removes an entry by re-tokenising the text it is *told* the entry
/// held. Removing it after the row already holds the new text leaves the old
/// tokens behind, and the note keeps matching words it no longer contains.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<String> folderId() async =>
      (await db.folderDao.createFolder(name: 'Training')).id;

  Future<void> expectIndexIntact() {
    return db.customStatement(
      "INSERT INTO notes_fts(notes_fts) VALUES('integrity-check')",
    );
  }

  test('a renamed note stops matching its old title', () async {
    final note = await db.noteDao.createNote(
      folderId: await folderId(),
      title: 'Squat',
      preview: 'heavy day',
    );

    await db.noteDao.updateNote(id: note.id, title: 'Bench');

    expect(await db.noteDao.fullTextSearch('Squat'), isEmpty);
    expect((await db.noteDao.fullTextSearch('Bench')).single.id, note.id);
    expect((await db.noteDao.fullTextSearch('heavy')).single.id, note.id);
    await expectIndexIntact();
  });

  test('a new preview replaces the old one in the index', () async {
    final note = await db.noteDao.createNote(
      folderId: await folderId(),
      title: 'Log',
      preview: 'squat',
    );

    await db.noteDao.updateNote(id: note.id, preview: 'deadlift');

    expect(await db.noteDao.fullTextSearch('squat'), isEmpty);
    expect((await db.noteDao.fullTextSearch('deadlift')).single.id, note.id);
    await expectIndexIntact();
  });

  test(
    'a save that changes neither title nor preview keeps the entry',
    () async {
      final note = await db.noteDao.createNote(
        folderId: await folderId(),
        title: 'Squat',
      );

      await db.noteDao.updateNote(id: note.id, content: 'body');

      expect((await db.noteDao.fullTextSearch('Squat')).single.id, note.id);
      await expectIndexIntact();
    },
  );

  test(
    'the v43 step rebuilds an index the old rename path left stale',
    () async {
      final note = await db.noteDao.createNote(
        folderId: await folderId(),
        title: 'Squat',
      );
      // The rename as builds before v43 ran it: the row rewritten first, then
      // a REPLACE that removes tokens of the *new* text.
      await db.customStatement(
        "UPDATE notes SET title = 'Bench' WHERE id = ?",
        [note.id],
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO notes_fts(rowid, title, preview) '
        'SELECT rowid, title, preview FROM notes WHERE id = ?',
        [note.id],
      );
      expect(
        (await db.noteDao.fullTextSearch('Squat')).single.id,
        note.id,
        reason: 'the corruption the rebuild exists for',
      );

      await DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v42CategoryAlertsAndDigests,
        DatabaseSchema.v43SyncReadiness,
      );

      expect(await db.noteDao.fullTextSearch('Squat'), isEmpty);
      expect((await db.noteDao.fullTextSearch('Bench')).single.id, note.id);
      await expectIndexIntact();
    },
  );

  test('a bulk delete over a tombstone leaves the index intact', () async {
    final folder = await folderId();
    final gone = await db.noteDao.createNote(folderId: folder, title: 'Gone');
    final live = await db.noteDao.createNote(folderId: folder, title: 'Live');
    await db.noteDao.softDeleteNote(gone.id);

    await db.noteDao.softDeleteNotesWithChunks([gone.id, live.id]);

    expect(await db.noteDao.fullTextSearch('Live'), isEmpty);
    await expectIndexIntact();
  });
}
