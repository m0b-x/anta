import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';

import '../database/support/db_test_support.dart';

/// A browser left mounted under the Settings database page keeps its watches
/// across a database switch: `rebindDatabase` re-points the handle, and the
/// live subscriptions must follow it to the new database rather than stream
/// from the closed one (A6 review R114).
void main() {
  late AppDatabase first;
  late AppDatabase second;

  setUp(() async {
    first = await openTestDatabase();
    second = await openTestDatabase();
  });
  tearDown(() async {
    await first.close();
    await second.close();
  });

  test('a note watch mounted before a switch reads the new database', () async {
    await first.noteDao.createNote(folderId: 'f1', title: 'Before');
    await second.noteDao.createNote(folderId: 'f1', title: 'After');
    final notes = NoteRepository(database: first);
    addTearDown(notes.dispose);
    final seen = <List<String>>[];
    final subscription = notes
        .watchNotesByFolder('f1')
        .listen((rows) => seen.add([for (final n in rows) n.title]));
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen.last, ['Before']);

    notes.rebindDatabase(second);
    await pumpEventQueue();

    expect(seen.last, ['After']);
  });

  test('a folder watch mounted before a switch reads the new database', () async {
    await first.folderDao.createFolder(name: 'Before');
    await second.folderDao.createFolder(name: 'After');
    final folders = FolderRepository(database: first);
    addTearDown(folders.dispose);
    final seen = <List<String>>[];
    final subscription = folders
        .watchFoldersByParent(null)
        .listen((rows) => seen.add([for (final f in rows) f.name]));
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen.last, ['Before']);

    folders.rebindDatabase(second);
    await pumpEventQueue();

    expect(seen.last, ['After']);
  });

  test('a note watch by id mounted before a switch reads the new database',
      () async {
    final note = await first.noteDao.createNote(folderId: 'f1', title: 'Before');
    // The same note on the other database: a synced row keeps its id.
    await second.noteDao.mergeNoteDocument(note.copyWith(title: 'After'), '');
    final notes = NoteRepository(database: first);
    addTearDown(notes.dispose);
    final seen = <String?>[];
    final subscription = notes
        .watchNoteById(note.id)
        .listen((row) => seen.add(row?.title));
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen.last, 'Before');

    notes.rebindDatabase(second);
    await pumpEventQueue();

    expect(seen.last, 'After');
  });

  test('a folder watch by id mounted before a switch reads the new database',
      () async {
    final folder = await first.folderDao.createFolder(name: 'Before');
    await second.folderDao.mergeFolder(folder.copyWith(name: 'After'));
    final folders = FolderRepository(database: first);
    addTearDown(folders.dispose);
    final seen = <String?>[];
    final subscription = folders
        .watchFolderById(folder.id)
        .listen((row) => seen.add(row?.name));
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen.last, 'Before');

    folders.rebindDatabase(second);
    await pumpEventQueue();

    expect(seen.last, 'After');
  });

  test('two pages may watch the same folder at once (A7 review R140)',
      () async {
    await first.noteDao.createNote(folderId: 'f1', title: 'Shared');
    final notes = NoteRepository(database: first);
    addTearDown(notes.dispose);
    final watch = notes.watchNotesByFolder('f1');
    final one = <int>[];
    final two = <int>[];

    // The drift watch underneath is broadcast, and the browser mounts a
    // list per route: a second listen must not throw.
    final a = watch.listen((rows) => one.add(rows.length));
    addTearDown(a.cancel);
    final b = watch.listen((rows) => two.add(rows.length));
    addTearDown(b.cancel);
    await pumpEventQueue();

    expect(one.last, 1);
    expect(two.last, 1);
  });

  test('a note watch keeps following writes on the new database', () async {
    final notes = NoteRepository(database: first);
    addTearDown(notes.dispose);
    final seen = <List<String>>[];
    final subscription = notes
        .watchNotesByFolder('f1')
        .listen((rows) => seen.add([for (final n in rows) n.title]));
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    notes.rebindDatabase(second);
    await pumpEventQueue();
    await second.noteDao.createNote(folderId: 'f1', title: 'Later');
    await pumpEventQueue();

    expect(seen.last, ['Later']);
  });
}
