import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';

import '../database/support/db_test_support.dart';

/// The two calls that set a share (`docs/cloud-sharing-foundations.md` §3)
/// — the only way in until a surface exists: each is one write of its
/// root's mark through the layers a surface will use, and neither disturbs
/// what a screen holds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());

  tearDown(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    CalendarEventService.reset();
    await db.close();
  });

  Future<Set<String>> queued() async => {
    for (final entry in await db.syncOutboxDao.pending())
      '${entry.syncedTable}/${entry.rowKey}',
  };

  group('CalendarEventService.setShared', () {
    late CalendarEventService events;
    final day = DateTime.utc(2026, 6, 1);

    setUp(() async {
      events = await CalendarEventService.forTesting(db);
      await events.upsert(
        CalendarEvent(
          id: 'e1',
          title: 'Dinner',
          categoryId: 'general',
          startDate: day,
        ),
      );
      await db.syncOutboxDao.clear();
    });

    Future<String?> markOf(String id) async =>
        (await db.calendarEventDao.getByIdsIncludingDeleted([
          id,
        ])).single.sharedPair;

    test('writes the event\'s mark and queues it; the event a screen holds '
        'is the same one', () async {
      final shown = events.events.single;

      expect(await events.setShared('e1', 'pair-1'), isTrue);

      expect(await markOf('e1'), 'pair-1');
      expect(await queued(), {'calendar_events/e1'});
      expect(events.events.single, shown);
    });

    test('takes it away again, and says when nothing was written', () async {
      await events.setShared('e1', 'pair-1');
      await db.syncOutboxDao.clear();

      expect(await events.setShared('e1', 'pair-1'), isFalse);
      expect(await queued(), isEmpty);
      expect(await events.setShared('missing', 'pair-1'), isFalse);

      expect(await events.setShared('e1', null), isTrue);
      expect(await markOf('e1'), isNull);
    });

    test('an edit of the event afterwards keeps its mark', () async {
      await events.setShared('e1', 'pair-1');

      await events.upsert(
        events.events.single.copyWith(title: 'Dinner at eight'),
      );

      expect(await markOf('e1'), 'pair-1');
    });

    test('a delete keeps the mark on the tombstone, and an undo brings the '
        'event back shared', () async {
      await events.setShared('e1', 'pair-1');
      final event = events.events.single;

      await events.deleteById('e1');
      expect(await markOf('e1'), 'pair-1');

      await events.upsert(event);
      expect(await markOf('e1'), 'pair-1');
      expect(events.events.single.id, 'e1');
    });
  });

  group('FolderStorageService.setFolderShared', () {
    late FolderRepository repository;
    late FolderStorageService folders;
    late String shelf;
    late String box;

    setUp(() async {
      repository = FolderRepository(database: db);
      folders = FolderStorageService(repository: repository);
      await folders.initialize();
      shelf = (await db.folderDao.createFolder(name: 'Shelf')).id;
      box = (await db.folderDao.createFolder(name: 'Box', parentId: shelf)).id;
      await db.syncOutboxDao.clear();
    });

    Future<String?> markOf(String id) async =>
        (await db.folderDao.getByIdsIncludingDeleted([id])).single.sharedPair;

    test('writes the folder\'s mark and queues it with what lies under '
        'it', () async {
      expect(await folders.setFolderShared(shelf, 'pair-1'), isTrue);

      expect(await markOf(shelf), 'pair-1');
      expect(await markOf(box), isNull);
      expect(await queued(), {'folders/$shelf', 'folders/$box'});
    });

    test('takes it away again, and says when nothing was written', () async {
      await folders.setFolderShared(shelf, 'pair-1');
      await db.syncOutboxDao.clear();

      expect(await folders.setFolderShared(shelf, 'pair-1'), isFalse);
      expect(await queued(), isEmpty);
      expect(await folders.setFolderShared('missing', 'pair-1'), isFalse);

      expect(await folders.setFolderShared(shelf, null), isTrue);
      expect(await markOf(shelf), isNull);
    });

    test('the repository hands out the row as written afterwards, never '
        'one it cached before the mark', () async {
      final before = await repository.getFolderById(shelf);
      expect(before!.sharedPair, isNull);

      await folders.setFolderShared(shelf, 'pair-1');

      expect((await repository.getFolderById(shelf))!.sharedPair, 'pair-1');
    });

    test(
      'a rename or a move of the folder afterwards keeps its mark',
      () async {
        await folders.setFolderShared(shelf, 'pair-1');

        await db.folderDao.updateFolder(id: shelf, name: 'Shelf, renamed');
        await db.folderDao.updateFolderLabel(id: shelf, label: ItemLabel.teal);
        final other = (await db.folderDao.createFolder(name: 'Other')).id;
        await db.folderDao.moveFolder(id: shelf, targetParentId: other);

        expect(await markOf(shelf), 'pair-1');
      },
    );
  });
}
