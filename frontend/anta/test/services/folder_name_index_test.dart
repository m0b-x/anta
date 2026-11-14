import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart' hide Folder;
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/folder.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_name_index.dart';
import 'package:anta/services/folder_storage_service.dart';

import '../database/support/db_test_support.dart';

/// The folder picker's search index: built once, marked dirty by what can
/// change a name or a share flag. A share act announces no folder change —
/// it forgets the share census — so the index listens to that too
/// (`docs/cloud-share-surfaces-roadmap.md` §16.9 B4).
void main() {
  // The switch case opens a second in-memory database on its own executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FolderRepository repository;
  late FolderStorageService folders;
  late FolderNameIndex index;

  setUp(() async {
    db = await openTestDatabase();
    repository = FolderRepository(database: db);
    folders = FolderStorageService(repository: repository);
    await folders.initialize();
    index = FolderNameIndex(folderService: folders);
  });

  tearDown(() async {
    index.dispose();
    await db.close();
  });

  Future<bool> sharedInSearch(String name) async =>
      (await index.search(name)).single.share.isShared;

  test('a share act marks it dirty: the next search reads the flag, both '
      'ways', () async {
    final id = (await db.folderDao.createFolder(name: 'Training')).id;
    expect(await sharedInSearch('Training'), isFalse);
    expect(index.isBuilt, isTrue);

    await db.folderDao.setSharedPair(id, 'pair-1');
    folders.invalidateCache();
    await pumpEventQueue();
    expect(index.isBuilt, isFalse, reason: 'marked dirty, not rebuilt');
    expect(await sharedInSearch('Training'), isTrue);

    await db.folderDao.setSharedPair(id, null);
    folders.invalidateCache();
    await pumpEventQueue();
    expect(await sharedInSearch('Training'), isFalse);
  });

  test('after a database switch, the census of the new one still reaches '
      'it', () async {
    final other = await openTestDatabase();
    addTearDown(other.close);
    final id = (await other.folderDao.createFolder(name: 'Lisbon')).id;

    repository.rebindDatabase(other);
    await pumpEventQueue();
    expect(await sharedInSearch('Lisbon'), isFalse);

    await other.folderDao.setSharedPair(id, 'pair-1');
    folders.invalidateCache();
    await pumpEventQueue();
    expect(await sharedInSearch('Lisbon'), isTrue);
  });

  test('built on one database, then a switch: the search finds only the new '
      'one\'s folders', () async {
    await db.folderDao.createFolder(name: 'Training');
    final other = await openTestDatabase();
    addTearDown(other.close);
    await other.folderDao.createFolder(name: 'Lisbon');
    expect(await index.search('Training'), hasLength(1));
    expect(index.isBuilt, isTrue);

    repository.rebindDatabase(other);
    await pumpEventQueue();

    expect(index.isBuilt, isFalse, reason: 'a switch empties it');
    expect(index.folderCount, 0);
    expect(await index.search('Training'), isEmpty);
    expect((await index.search('Lisbon')).single.name, 'Lisbon');
  });

  test('marked dirty while a build is in flight: that build does not '
      'publish, and the next search reads again', () async {
    final held = _HeldFolders(repository);
    final heldIndex = FolderNameIndex(folderService: held);
    addTearDown(heldIndex.dispose);
    final id = (await db.folderDao.createFolder(name: 'Training')).id;

    held.hold = Completer<void>();
    final inFlight = heldIndex.ensureBuilt();
    await pumpEventQueue();
    // The act lands after the build read its folders, before it published.
    await db.folderDao.setSharedPair(id, 'pair-1');
    held.invalidateCache();
    await pumpEventQueue();
    held.hold!.complete();
    held.hold = null;
    await inFlight;

    expect(heldIndex.isBuilt, isFalse, reason: 'it read before the act');
    expect((await heldIndex.search('Training')).single.share.isShared, isTrue);
    expect(heldIndex.isBuilt, isTrue);
  });

  // Re-check finding 3: the search whose build a switch overtook read the
  // emptied index and answered "no folders" for that keystroke.
  test('a switch while a search\'s build is in flight: that search answers '
      'from the new database, not empty', () async {
    await db.folderDao.createFolder(name: 'Training');
    final other = await openTestDatabase();
    addTearDown(other.close);
    await other.folderDao.createFolder(name: 'Lisbon');

    final training = index.search('Training');
    final lisbon = index.search('Lisbon');
    repository.rebindDatabase(other);

    expect(await training, isEmpty, reason: 'the old database\'s name');
    expect((await lisbon).map((folder) => folder.name), ['Lisbon']);
  });

  test('its build overtaken, and the build after it too: the search serves '
      'what the last build read, never an empty answer', () async {
    final held = _HeldFolders(repository);
    final heldIndex = FolderNameIndex(folderService: held);
    addTearDown(heldIndex.dispose);
    await db.folderDao.createFolder(name: 'Training');

    final first = held.hold = Completer<void>();
    final search = heldIndex.search('Training');
    await pumpEventQueue();
    await held.createFolder(name: 'Legs');
    await pumpEventQueue();
    final second = held.hold = Completer<void>();
    first.complete();
    await pumpEventQueue();
    await held.createFolder(name: 'Arms');
    await pumpEventQueue();
    held.hold = null;
    second.complete();

    expect((await search).map((folder) => folder.name), ['Training']);
  });

  // Last review, finding 4: the fallback served the closed database's
  // names, and a build that finished late could put an older read back.
  test('the second overtaking a database switch: the search answers empty, '
      'never the closed database\'s names, and the next reads the new '
      'one', () async {
    final held = _HeldFolders(repository);
    final heldIndex = FolderNameIndex(folderService: held);
    addTearDown(heldIndex.dispose);
    await db.folderDao.createFolder(name: 'Training');
    final other = await openTestDatabase();
    addTearDown(other.close);
    await other.folderDao.createFolder(name: 'Lisbon');

    final first = held.hold = Completer<void>();
    final search = heldIndex.search('Training');
    await pumpEventQueue();
    await held.createFolder(name: 'Legs');
    await pumpEventQueue();
    final second = held.hold = Completer<void>();
    first.complete();
    await pumpEventQueue();
    // The second build has read the database the repository now leaves.
    repository.rebindDatabase(other);
    await pumpEventQueue();
    held.hold = null;
    second.complete();

    expect(await search, isEmpty);
    expect(heldIndex.folderCount, 0, reason: 'nothing of it is held');
    expect((await heldIndex.search('Lisbon')).map((folder) => folder.name), [
      'Lisbon',
    ]);
    expect(await heldIndex.search('Training'), isEmpty);
  });

  // Leg 9 verification, finding 2: the database generation moves when a
  // switch begins and the repository is rebound later — a build begun in
  // between was stamped new and read the old database.
  test('a build begun between the switch\'s start and the rebind: its read '
      'is the old database\'s, and no search gets it', () async {
    final held = _HeldFolders(repository);
    final heldIndex = FolderNameIndex(folderService: held);
    addTearDown(heldIndex.dispose);
    await db.folderDao.createFolder(name: 'Training');
    final other = await openTestDatabase();
    addTearDown(other.close);
    await other.folderDao.createFolder(name: 'Lisbon');

    final first = held.hold = Completer<void>();
    final search = heldIndex.search('Training');
    await pumpEventQueue();
    await held.createFolder(name: 'Legs');
    await pumpEventQueue();
    DatabaseLifecycle.notifyDatabaseSwitching();
    final second = held.hold = Completer<void>();
    first.complete();
    await pumpEventQueue();
    repository.rebindDatabase(other);
    await pumpEventQueue();
    held.hold = null;
    second.complete();

    expect(await search, isEmpty);
    expect((await heldIndex.search('Lisbon')).map((folder) => folder.name), [
      'Lisbon',
    ]);
  });

  test('a build that ends after the rebind, before its mark-dirty is heard: '
      'it publishes nothing a search can get', () async {
    final held = _HeldFolders(repository);
    final heldIndex = FolderNameIndex(folderService: held);
    addTearDown(heldIndex.dispose);
    await db.folderDao.createFolder(name: 'Training');
    final other = await openTestDatabase();
    addTearDown(other.close);
    await other.folderDao.createFolder(name: 'Lisbon');

    final first = held.hold = Completer<void>();
    final built = heldIndex.ensureBuilt();
    await pumpEventQueue();
    held.hold = null;
    // In one turn: the build's end is queued, then the rebind — the build
    // ends before the stream that marks the index dirty has delivered.
    first.complete();
    repository.rebindDatabase(other);
    await built;

    expect(heldIndex.folderCount, 0, reason: 'the old database published');
    expect(await heldIndex.search('Training'), isEmpty);
    expect((await heldIndex.search('Lisbon')).map((folder) => folder.name), [
      'Lisbon',
    ]);
  });

  test('of two overtaken builds, an older one finishing last does not put '
      'its read back over the newer one\'s', () async {
    final held = _HeldFolders(repository);
    final heldIndex = FolderNameIndex(folderService: held);
    addTearDown(heldIndex.dispose);
    await db.folderDao.createFolder(name: 'Training');

    // The search's first build is overtaken; its second reads before Legs
    // and is held to the end.
    final first = held.hold = Completer<void>();
    final search = heldIndex.search('Legs');
    await pumpEventQueue();
    await held.createFolder(name: 'Arms');
    await pumpEventQueue();
    final older = held.hold = Completer<void>();
    first.complete();
    await pumpEventQueue();
    await held.createFolder(name: 'Legs');
    await pumpEventQueue();
    // A newer build, another caller's, reads Legs and is overtaken too.
    final newer = held.hold = Completer<void>();
    unawaited(heldIndex.ensureBuilt());
    await pumpEventQueue();
    await held.createFolder(name: 'Calves');
    await pumpEventQueue();
    held.hold = null;
    newer.complete();
    await pumpEventQueue();
    older.complete();

    expect((await search).map((folder) => folder.name), ['Legs']);
  });

  // Leg 11: a rebind between the built index's `ensureBuilt` and the read
  // of its entries, before the rebind's mark-dirty is delivered.
  test('built, then a rebind in the search\'s own gap: the closed '
      'database\'s names are never served', () async {
    await db.folderDao.createFolder(name: 'Training');
    final other = await openTestDatabase();
    addTearDown(other.close);
    await index.ensureBuilt();
    expect(index.isBuilt, isTrue);

    // Queued ahead of the search's resumption after its `ensureBuilt`.
    scheduleMicrotask(() => repository.rebindDatabase(other));
    expect(await index.search('Training'), isEmpty);
  });
}

/// The storage service with its full load held after it has read, so a
/// mark-dirty can land while a build is in flight.
class _HeldFolders extends FolderStorageService {
  _HeldFolders(FolderRepository repository) : super(repository: repository);

  Completer<void>? hold;

  @override
  Future<List<Folder>> loadAllFolders() async {
    // The hold this load was called under, whatever is set meanwhile.
    final held = hold;
    final folders = await super.loadAllFolders();
    await held?.future;
    return folders;
  }
}
