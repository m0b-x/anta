import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/content_item.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/mixed_reorder_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// A drag persists what the browser showed, and what the browser shows is
/// often only its first pages: these cases drive [MixedReorderService] with
/// the pages the storage services actually serve, in both custom directions,
/// and read the folder back the way the next load will.
void main() {
  late AppDatabase db;
  late NoteRepository noteRepository;
  late FolderRepository folderRepository;
  late NoteStorageService notes;
  late FolderStorageService folders;
  late MixedReorderService service;

  setUp(() async {
    db = await openTestDatabase();
    noteRepository = NoteRepository(database: db);
    folderRepository = FolderRepository(database: db);
    notes = NoteStorageService(repository: noteRepository);
    folders = FolderStorageService(repository: folderRepository);
    service = MixedReorderService(
      folderRepository: folderRepository,
      noteRepository: noteRepository,
    );
  });
  tearDown(() async => db.close());

  /// A folder with [subfolders] subfolders and [count] notes, created in
  /// order, so each kind starts at `0..n-1`.
  Future<String> seed({required int count, int subfolders = 0}) async {
    final parent = await db.folderDao.createFolder(name: 'Training');
    for (var i = 0; i < subfolders; i++) {
      await db.folderDao.createFolder(name: 'Block $i', parentId: parent.id);
    }
    for (var i = 0; i < count; i++) {
      await db.noteDao.createNote(folderId: parent.id, title: 'Session $i');
    }
    return parent.id;
  }

  /// What the browser holds after loading [pages] pages, folders first.
  Future<List<ContentItem>> loaded(
    String parentId, {
    required NotesSortOrder noteOrder,
    FoldersSortOrder folderOrder = FoldersSortOrder.positionAsc,
    int pages = 1,
  }) async {
    final folderPage = await folders.loadFoldersPaginated(
      parentId: parentId,
      pageSize: 1000,
      sortOrder: folderOrder,
    );
    final notePage = await notes.loadNotesPaginated(
      folderId: parentId,
      pageSize: NoteStorageService.defaultPageSize * pages,
      sortOrder: noteOrder,
    );
    return groupFoldersThenNotes(
      folders: folderPage.folders,
      notes: notePage.notes,
    );
  }

  /// Every note title of the folder, in the order a full load serves.
  Future<List<String>> reloadTitles(
    String parentId,
    NotesSortOrder order,
  ) async {
    final page = await notes.loadNotesPaginated(
      folderId: parentId,
      pageSize: 1000,
      sortOrder: order,
    );
    return [for (final note in page.notes) note.title];
  }

  List<String> titlesOf(List<ContentItem> items) => [
    for (final item in items)
      if (item is NoteItem) item.metadata.title,
  ];

  /// Moves the item at [from] to [to] within the notes, as a drag does.
  List<ContentItem> drag(List<ContentItem> items, int from, int to) {
    final noteStart = items.indexWhere((item) => item is NoteItem);
    final result = [...items];
    final moved = result.removeAt(noteStart + from);
    result.insert(noteStart + to, moved);
    return result;
  }

  for (final order in [
    NotesSortOrder.positionAsc,
    NotesSortOrder.positionDesc,
  ]) {
    final descending = order == NotesSortOrder.positionDesc;

    test('a drag in the first page of 50 notes reads back whole '
        '(${order.name})', () async {
      final parentId = await seed(count: 50, subfolders: 2);
      final before = await reloadTitles(parentId, order);
      final shown = await loaded(parentId, noteOrder: order);
      expect(titlesOf(shown), hasLength(NoteStorageService.defaultPageSize));

      final dragged = drag(shown, 15, 0);
      await service.reorderMixed(
        parentId: parentId,
        items: dragged,
        foldersDescending: false,
        notesDescending: descending,
      );

      expect(await reloadTitles(parentId, order), [
        ...titlesOf(dragged),
        ...before.skip(NoteStorageService.defaultPageSize),
      ]);
    });

    test(
      'two loaded pages, the last row dragged to the top (${order.name})',
      () async {
        final parentId = await seed(count: 45);
        final before = await reloadTitles(parentId, order);
        final shown = await loaded(parentId, noteOrder: order, pages: 2);

        final dragged = drag(shown, 39, 0);
        await service.reorderMixed(
          parentId: parentId,
          items: dragged,
          foldersDescending: false,
          notesDescending: descending,
        );

        expect(await reloadTitles(parentId, order), [
          ...titlesOf(dragged),
          ...before.skip(40),
        ]);
      },
    );
  }

  test('a note drag leaves the folders unstamped, and only the moved notes '
      'are announced', () async {
    final parentId = await seed(count: 30, subfolders: 3);
    final foldersBefore = await db.folderDao.getFoldersByParent(parentId);
    final shown = await loaded(parentId, noteOrder: NotesSortOrder.positionAsc);
    final announced = <String>[];
    final sub = noteRepository.noteChanges.listen(
      (c) => announced.add(c.noteId),
    );
    final folderEvents = <String>[];
    final folderSub = folderRepository.folderChanges.listen(
      (c) => folderEvents.add(c.folderId),
    );

    // Swap the first two notes: two rows move, eighteen loaded and ten
    // unloaded stay where they are.
    await service.reorderMixed(
      parentId: parentId,
      items: drag(shown, 1, 0),
      foldersDescending: false,
      notesDescending: false,
    );
    await pumpEventQueue();
    await sub.cancel();
    await folderSub.cancel();

    final noteIds = [
      for (final item in shown)
        if (item is NoteItem) item.id,
    ];
    // A swap moves one of the pair: only that note is announced.
    expect(announced, hasLength(1));
    expect(noteIds.take(2), contains(announced.single));
    expect(folderEvents, isEmpty);
    final foldersAfter = await db.folderDao.getFoldersByParent(parentId);
    expect(
      [for (final folder in foldersAfter) folder.hlcTimestamp],
      [for (final folder in foldersBefore) folder.hlcTimestamp],
    );
  });

  test('two drags fired back to back land in order', () async {
    final parentId = await seed(count: 5);
    final shown = await loaded(parentId, noteOrder: NotesSortOrder.positionAsc);
    final first = drag(shown, 4, 0);
    final second = drag(first, 4, 0);

    // Neither awaited before the other starts, as the page fires them.
    final writes = [
      service.reorderMixed(
        parentId: parentId,
        items: first,
        foldersDescending: false,
        notesDescending: false,
      ),
      service.reorderMixed(
        parentId: parentId,
        items: second,
        foldersDescending: false,
        notesDescending: false,
      ),
    ];
    await Future.wait(writes);

    expect(
      await reloadTitles(parentId, NotesSortOrder.positionAsc),
      titlesOf(second),
    );
  });

  test('folders and notes keep separate sequences', () async {
    final parentId = await seed(count: 3, subfolders: 2);
    final notesBefore = await db.noteDao.getNotesByFolder(parentId);
    final shown = await loaded(parentId, noteOrder: NotesSortOrder.positionAsc);
    final swapped = [shown[1], shown[0], ...shown.skip(2)];

    await service.reorderMixed(
      parentId: parentId,
      items: swapped,
      foldersDescending: false,
      notesDescending: false,
    );

    final subfolders = await db.folderDao.getFoldersByParent(parentId);
    expect([for (final f in subfolders) f.name], ['Block 1', 'Block 0']);
    final notesAfter = await db.noteDao.getNotesByFolder(parentId);
    expect(
      {for (final note in notesAfter) note.id: note.position},
      {for (final note in notesBefore) note.id: note.position},
      reason: 'a folder drag leaves the notes where they were',
    );
  });
}
