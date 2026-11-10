import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_registry.dart';
import 'package:anta/services/sync/sync_space_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../../database/support/db_test_support.dart';
import '../../support/fake_sync_gateway.dart';

const _uid = 'uid-1';

Matcher _fails(SyncBindFailure failure) =>
    isA<SyncSpaceException>().having((e) => e.failure, 'failure', failure);

/// The fake, with the pages a deletion asks for logged as `<table>:<limit>`
/// and a hook before every page and around the mark, where a test scripts a
/// failure — or another device's write — mid-job.
class _DeletingGateway extends FakeSyncGateway {
  final List<String> pages = [];
  void Function(String table, int limit)? beforePage;
  FutureOr<void> Function()? beforeMark;
  FutureOr<void> Function()? afterMark;

  @override
  Future<void> markSpaceDeleted(SyncSpaceRef space) async {
    await beforeMark?.call();
    await super.markSpaceDeleted(space);
    await afterMark?.call();
  }

  @override
  Future<int> deleteRows(SyncSpaceRef space, String table, {int? limit}) async {
    final take = limit ?? SyncGateway.rowDeleteBatch;
    pages.add('$table:$take');
    beforePage?.call(table, take);
    return super.deleteRows(space, table, limit: limit);
  }

  List<String> pagesOf(String table) => [
    for (final page in pages)
      if (page.startsWith('$table:')) page,
  ];
}

/// The real binding service, with a hook before every unbind — where a test
/// sees what the deletion had done by then, or lets the app die there.
class _WatchedBinding extends SyncBindingService {
  _WatchedBinding(
    super.db,
    super.settings, {
    super.registry,
    super.databaseName,
  }) : super.detached();

  void Function()? beforeUnbind;

  @override
  Future<void> unbind({bool raiseFloor = true}) async {
    beforeUnbind?.call();
    await super.unbind(raiseFloor: raiseFloor);
  }
}

/// "Delete cloud copy" (cloud-multi-user-roadmap §5): the service's mark →
/// re-read → record → unbind → empty → remove, the pending record that makes
/// an interrupted deletion finishable, and the bind flow that never offers a
/// dying space — over an in-memory database bound through the real binding
/// service and the real `DatabaseManager` over a temporary directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;
  late AppDatabase db;
  late SettingsService settings;
  late _WatchedBinding binding;
  late _DeletingGateway gateway;
  late SyncSpaceService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_space_delete');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('training');
    await manager.createDatabase('training');
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    binding = _WatchedBinding(
      db,
      settings,
      registry: manager.spaceRegistry,
      databaseName: 'training',
    );
    gateway = _DeletingGateway();
    service = SyncSpaceService(
      gateway: gateway,
      database: () async => db,
      binding: () async => binding,
      databases: () async => manager,
    );
  });

  tearDown(() async {
    SettingsService.reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SettingsKeys.syncBoundSpaces);
    await prefs.remove(SettingsKeys.syncPendingDeletions);
    await db.close();
  });

  SyncSpaceRegistry registry() => manager.spaceRegistry;

  Future<SyncSpaceInfo> createSpace(
    String name, {
    String owner = _uid,
    int schema = DatabaseSchema.syncSchemaVersion,
  }) => gateway.createSpace(
    ownerUid: owner,
    name: name,
    deviceId: 'other-device',
    schema: schema,
  );

  Future<SyncSpaceInfo> boundSpace(String name, {int? schema}) async {
    final space = await createSpace(
      name,
      schema: schema ?? DatabaseSchema.syncSchemaVersion,
    );
    await binding.bind(space: space.ref, accountUid: _uid);
    return space;
  }

  /// [count] documents of [table] in [space], as other devices pushed them.
  void plantRows(SyncSpaceInfo space, String table, int count) {
    for (var i = 0; i < count; i++) {
      gateway.plant(
        space.ref,
        SyncEnvelope(
          table: table,
          rowKey: '$table-${i.toString().padLeft(4, '0')}',
          hlc: '000000000001:0000:other-device',
          deviceId: 'other-device',
          version: 1,
          op: OutboxOp.upsert,
          ownerId: space.ref.ownerUid,
          data: const {'name': 'row'},
        ),
      );
    }
  }

  int rowsLeft(SyncSpaceInfo space) => [
    for (final synced in syncedTables)
      gateway.rowsOf(space.ref, synced.name).length,
  ].fold(0, (a, b) => a + b);

  group('deleteCloudCopy', () {
    test('removes every row of every table, chunks included, then the '
        'space; unbound, nothing pending, every local row kept', () async {
      await db.folderDao.createFolder(name: 'Errands');
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      plantRows(space, 'notes', 2);
      plantRows(space, 'content_chunks', 120);
      plantRows(space, 'calendar_events', 4);
      plantRows(space, 'vocabulary_items', 1);

      await service.deleteCloudCopy();

      expect(await gateway.readSpace(space.ref), isNull);
      expect(rowsLeft(space), 0);
      expect(await binding.read(), isNull);
      expect(registry().claims(), isEmpty);
      expect(registry().pendingDeletions(), isEmpty);
      expect(await db.folderDao.getFolderCount(null), 1);
      expect(gateway.calls.first, 'mark');
      expect(gateway.calls.last, 'deleteSpace');
      for (final synced in syncedTables) {
        expect(
          gateway.calls,
          contains('deleteRows:${synced.name}'),
          reason: 'the registry is the walk',
        );
      }
    });

    test('reports the documents removed so far after every page, every '
        'table chunks included asked for in pages of twenty', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      plantRows(space, 'content_chunks', 120);
      plantRows(space, 'calendar_events', 4);
      final progress = <int>[];

      await service.deleteCloudCopy(onProgress: progress.add);

      expect(progress, [3, 23, 43, 63, 83, 103, 123, 127]);
      expect(gateway.pagesOf('content_chunks'), [
        for (var i = 0; i < 7; i++) 'content_chunks:20',
      ]);
      expect(gateway.pagesOf('folders'), ['folders:20', 'folders:20']);
      expect(
        gateway.deleteLimits,
        everyElement(SyncGateway.rowDeleteBatch),
        reason: 'asked for explicitly, never left to a default',
      );
      expect(SyncGateway.rowDeleteBatch, 20);
    });

    test('unbound, does nothing at all', () async {
      await service.deleteCloudCopy();

      expect(gateway.calls, isEmpty);
      expect(gateway.readSpaceCalls, 0);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('a restore in flight is refused before anything is read', () async {
      final space = await boundSpace('Phone');

      await SyncSuspension.run(() async {
        await expectLater(
          service.deleteCloudCopy(),
          throwsA(_fails(SyncBindFailure.suspended)),
        );
      });

      expect(gateway.readSpaceCalls, 0);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
    });

    test('a space gone already: unbound as "Stop syncing" does, nothing '
        'marked or recorded', () async {
      final space = await boundSpace('Phone');
      gateway.consoleDeleteSpace(space.ref);

      await service.deleteCloudCopy();

      expect(await binding.read(), isNull);
      expect(registry().claims(), isEmpty);
      expect(gateway.calls, isEmpty);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('a space a newer build wrote to is refused before the mark, '
        'still bound', () async {
      final space = await boundSpace(
        'Phone',
        schema: DatabaseSchema.syncSchemaVersion + 1,
      );
      plantRows(space, 'folders', 2);

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.appOutdated)),
      );

      expect(gateway.calls, isEmpty);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isFalse);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect(registry().pendingDeletions(), isEmpty);
      expect(rowsLeft(space), 2);
    });

    for (final (gatewayFailure, failure) in [
      (SyncGatewayFailure.offline, SyncBindFailure.offline),
      (SyncGatewayFailure.quotaExhausted, SyncBindFailure.quotaExhausted),
    ]) {
      test('${gatewayFailure.name} at the mark changes nothing: still bound, '
          'nothing recorded, nothing deleted', () async {
        final space = await boundSpace('Phone');
        plantRows(space, 'folders', 2);
        gateway.beforeMark = () =>
            throw SyncGatewayException(gatewayFailure, 'scripted');

        await expectLater(service.deleteCloudCopy(), throwsA(_fails(failure)));

        expect((await binding.read())!.spaceId, space.ref.spaceId);
        expect(await registry().holderOf(space.ref), 'training');
        expect(registry().pendingDeletions(), isEmpty);
        expect(
          (await gateway.readSpace(space.ref))!.markedForDeletion,
          isFalse,
        );
        expect(rowsLeft(space), 2);
      });
    }

    test('the quota running out while emptying leaves the database unbound '
        'and the deletion recorded; finishing it completes the job', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      plantRows(space, 'calendar_events', 2);
      gateway.beforePage = (table, _) {
        if (table == 'calendar_events') {
          throw const SyncGatewayException(
            SyncGatewayFailure.quotaExhausted,
            'scripted',
          );
        }
      };

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.quotaExhausted)),
      );

      expect(await binding.read(), isNull);
      expect(registry().claims(), isEmpty);
      expect(registry().pendingDeletions(), [
        SyncPendingDeletion(space: space.ref, spaceName: 'Phone'),
      ]);
      expect(await service.pendingDeletions(_uid), hasLength(1));
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect(gateway.rowsOf(space.ref, 'folders'), isEmpty);
      expect(gateway.rowsOf(space.ref, 'calendar_events'), hasLength(2));

      gateway.beforePage = null;
      final progress = <int>[];
      await service.finishPendingDeletions(
        accountUid: _uid,
        onProgress: progress.add,
      );

      expect(progress, [2]);
      expect(await gateway.readSpace(space.ref), isNull);
      expect(rowsLeft(space), 0);
      expect(registry().pendingDeletions(), isEmpty);
      expect(await service.pendingDeletions(_uid), isEmpty);
    });

    test('a page that times out halves that table\'s page for the rest of '
        'the job; the other tables keep theirs', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'content_chunks', 30);
      plantRows(space, 'folders', 3);
      var foldersTimedOut = false;
      gateway.beforePage = (table, limit) {
        if (table == 'content_chunks' && limit > 5) {
          throw const SyncGatewayException.timedOut();
        }
        if (table == 'folders' && !foldersTimedOut) {
          foldersTimedOut = true;
          throw const SyncGatewayException.timedOut();
        }
      };

      await service.deleteCloudCopy();

      expect(gateway.pagesOf('content_chunks'), [
        'content_chunks:20',
        'content_chunks:10',
        for (var i = 0; i < 7; i++) 'content_chunks:5',
      ]);
      expect(gateway.pagesOf('folders'), [
        'folders:20',
        'folders:10',
        'folders:10',
      ]);
      expect(gateway.pagesOf('notes'), ['notes:20']);
      expect(await gateway.readSpace(space.ref), isNull);
      expect(rowsLeft(space), 0);
    });

    test('a page that times out at a single document fails as offline, '
        'the deletion left pending', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'content_chunks', 3);
      gateway.beforePage = (table, _) {
        if (table == 'content_chunks') {
          throw const SyncGatewayException.timedOut();
        }
      };

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.offline)),
      );

      expect(gateway.pagesOf('content_chunks'), [
        for (final limit in [20, 10, 5, 2, 1]) 'content_chunks:$limit',
      ]);
      expect(await binding.read(), isNull);
      expect(registry().pendingDeletions(), hasLength(1));
    });

    test('mark, then record, then unbind: an app that dies at the unbind '
        'leaves the marked space recorded (review F6)', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 2);
      final record = SyncPendingDeletion(space: space.ref, spaceName: 'Phone');
      List<String>? callsAtUnbind;
      List<SyncPendingDeletion>? recordedAtUnbind;
      binding.beforeUnbind = () {
        callsAtUnbind = [...gateway.calls];
        recordedAtUnbind = registry().pendingDeletions();
        throw StateError('the app died');
      };

      await expectLater(service.deleteCloudCopy(), throwsA(anything));

      expect(callsAtUnbind, ['mark']);
      expect(recordedAtUnbind, [record]);
      expect(registry().pendingDeletions(), [record]);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect(rowsLeft(space), 2);
    });

    test('a second call on a database still bound to its marked space '
        'carries the deletion to the end, recorded once', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      plantRows(space, 'notes', 2);
      await gateway.markSpaceDeleted(space.ref);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: space.ref, spaceName: 'Phone'),
      );
      List<SyncPendingDeletion>? recordedAtUnbind;
      binding.beforeUnbind = () =>
          recordedAtUnbind = registry().pendingDeletions();
      final progress = <int>[];

      await service.deleteCloudCopy(onProgress: progress.add);

      expect(recordedAtUnbind, hasLength(1));
      expect(progress.last, 5);
      expect(await gateway.readSpace(space.ref), isNull);
      expect(rowsLeft(space), 0);
      expect(await binding.read(), isNull);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('a space gone between the mark and the re-read: unbound, any '
        'record cleared, nothing emptied (review F3)', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 2);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: space.ref, spaceName: 'Phone'),
      );
      gateway.afterMark = () => gateway.consoleDeleteSpace(space.ref);

      await service.deleteCloudCopy();

      expect(gateway.calls, ['mark']);
      expect(await binding.read(), isNull);
      expect(registry().claims(), isEmpty);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('a newer build that wrote between the first read and the mark is '
        'found by the re-read: the mark stands, nothing recorded, still '
        'bound, nothing emptied (review F3)', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 2);
      gateway.beforeMark = () => gateway.pushBatch(
        space.ref,
        const [],
        pushedBy: 'newer-device',
        schema: DatabaseSchema.syncSchemaVersion + 1,
      );

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.appOutdated)),
      );

      expect(gateway.calls, ['push:newer-device', 'mark']);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect(registry().pendingDeletions(), isEmpty);
      expect(rowsLeft(space), 2);
    });

    test('a page refused because another device removed the space meanwhile '
        'means the deletion is done (review F4)', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 2);
      plantRows(space, 'notes', 3);
      // The other device's last step lands between this page's read and its
      // write: the space document goes, the rows this page read are still
      // there to be refused.
      gateway.beforePage = (table, _) {
        if (table == 'notes') unawaited(gateway.deleteSpace(space.ref));
      };

      await service.deleteCloudCopy();

      expect(await gateway.readSpace(space.ref), isNull);
      expect(await binding.read(), isNull);
      expect(registry().pendingDeletions(), isEmpty);
      expect(
        gateway.calls.where((call) => call == 'deleteSpace'),
        hasLength(1),
        reason: 'the other device\'s only',
      );
    });

    test('a page refused while the space still reads marked fails, the '
        'deletion left pending', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 2);
      gateway.beforePage = (table, _) {
        if (table == 'folders') {
          throw const SyncGatewayException(
            SyncGatewayFailure.permissionDenied,
            'scripted',
          );
        }
      };

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.permissionDenied)),
      );

      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect(registry().pendingDeletions(), hasLength(1));
      expect(rowsLeft(space), 2);
    });
  });

  group('finishPendingDeletions', () {
    test('a record whose space reads unmarked is cleared, the space never '
        'marked or emptied (review F8)', () async {
      final space = await createSpace('Live');
      plantRows(space, 'folders', 2);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: space.ref, spaceName: 'Live'),
      );
      final progress = <int>[];

      await service.finishPendingDeletions(
        accountUid: _uid,
        onProgress: progress.add,
      );

      expect(registry().pendingDeletions(), isEmpty);
      expect(gateway.calls, isEmpty);
      expect(progress, isEmpty);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isFalse);
      expect(rowsLeft(space), 2);
    });

    test('leaves another account\'s record and space alone', () async {
      final partners = await createSpace('Partner', owner: 'uid-2');
      await gateway.markSpaceDeleted(partners.ref);
      plantRows(partners, 'folders', 2);
      final record = SyncPendingDeletion(
        space: partners.ref,
        spaceName: 'Partner',
      );
      await registry().addPendingDeletion(record);
      gateway.calls.clear();

      await service.finishPendingDeletions(accountUid: _uid);

      expect(registry().pendingDeletions(), [record]);
      expect(await service.pendingDeletions(_uid), isEmpty);
      expect(await service.pendingDeletions('uid-2'), [record]);
      expect(await gateway.readSpace(partners.ref), isNotNull);
      expect(rowsLeft(partners), 2);
      expect(gateway.calls, isEmpty);
    });

    test('a record whose space is already gone is only cleared', () async {
      const gone = SyncSpaceRef(ownerUid: _uid, spaceId: 'space-gone');
      await registry().addPendingDeletion(
        const SyncPendingDeletion(space: gone, spaceName: 'Gone'),
      );

      await service.finishPendingDeletions(accountUid: _uid);

      expect(registry().pendingDeletions(), isEmpty);
      expect(gateway.calls, isEmpty);
    });

    test(
      'a space a newer build wrote to is refused, its record kept',
      () async {
        final space = await createSpace(
          'Phone',
          schema: DatabaseSchema.syncSchemaVersion + 1,
        );
        await gateway.markSpaceDeleted(space.ref);
        plantRows(space, 'folders', 1);
        await registry().addPendingDeletion(
          SyncPendingDeletion(space: space.ref, spaceName: 'Phone'),
        );

        await expectLater(
          service.finishPendingDeletions(accountUid: _uid),
          throwsA(_fails(SyncBindFailure.appOutdated)),
        );

        expect(registry().pendingDeletions(), hasLength(1));
        expect(rowsLeft(space), 1);
      },
    );
  });

  group('the bind flow never offers a dying space', () {
    test('start() finishes a marked space first, then offers only the '
        'live ones', () async {
      await db.folderDao.createFolder(name: 'Errands');
      final dying = await createSpace('Old');
      plantRows(dying, 'notes', 3);
      await gateway.markSpaceDeleted(dying.ref);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: dying.ref, spaceName: 'Old'),
      );
      final live = await createSpace('Live');

      final start = await service.start(accountUid: _uid);

      expect(start, SyncBindStartPick(spaces: [live], holdsData: true));
      expect(await gateway.readSpace(dying.ref), isNull);
      expect(rowsLeft(dying), 0);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('start() reports what its pass removed, the count running on '
        'across the marked spaces (review F7)', () async {
      final first = await createSpace('Old');
      final second = await createSpace('Older');
      plantRows(first, 'folders', 3);
      plantRows(second, 'folders', 3);
      await gateway.markSpaceDeleted(first.ref);
      await gateway.markSpaceDeleted(second.ref);
      gateway.calls.clear();
      final progress = <int>[];

      await service.start(accountUid: _uid, onProgress: progress.add);

      expect(progress, [3, 6]);
      expect(gateway.calls, isNot(contains('mark')), reason: 'never marks');
      expect(await gateway.readSpace(first.ref), isNull);
      expect(await gateway.readSpace(second.ref), isNull);
    });

    test('start() with only a marked space left creates the first space '
        'and binds it', () async {
      final dying = await createSpace('Old');
      await gateway.markSpaceDeleted(dying.ref);

      final start = await service.start(accountUid: _uid);

      final spaces = await gateway.listSpaces(_uid);
      expect(spaces, hasLength(1));
      expect(start, SyncBindStartBound(spaces.single.ref));
      expect(spaces.single.ref, isNot(dying.ref));
      expect(spaces.single.name, 'training');
      expect(spaces.single.markedForDeletion, isFalse);
      expect((await binding.read())!.spaceId, spaces.single.ref.spaceId);
    });

    test('start() goes on when finishing a marked space fails, and still '
        'never offers it', () async {
      await db.folderDao.createFolder(name: 'Errands');
      final dying = await createSpace('Old');
      plantRows(dying, 'notes', 2);
      await gateway.markSpaceDeleted(dying.ref);
      final live = await createSpace('Live');
      gateway.beforePage = (table, _) {
        if (table == 'notes') {
          throw const SyncGatewayException(
            SyncGatewayFailure.offline,
            'scripted',
          );
        }
      };

      final start = await service.start(accountUid: _uid);

      expect(start, SyncBindStartPick(spaces: [live], holdsData: true));
      expect((await gateway.readSpace(dying.ref))!.markedForDeletion, isTrue);
    });

    test('Merge refuses a marked space as gone', () async {
      final dying = await createSpace('Old');
      await gateway.markSpaceDeleted(dying.ref);

      await expectLater(
        service.bindExisting(dying.ref, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.spaceGone)),
      );
      expect(await binding.read(), isNull);
    });

    test('Download refuses a marked space as gone, creating no '
        'database', () async {
      final dying = await createSpace('Old');
      await gateway.markSpaceDeleted(dying.ref);

      await expectLater(
        service.downloadIntoNewDatabase(dying, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.spaceGone)),
      );
      expect(await manager.databaseExists('Old'), isFalse);
      expect(manager.getActiveDatabaseName(), 'training');
    });
  });
}
