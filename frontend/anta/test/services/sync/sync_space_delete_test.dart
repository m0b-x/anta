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
const _partner = 'uid-2';

Matcher _fails(SyncBindFailure failure) =>
    isA<SyncSpaceException>().having((e) => e.failure, 'failure', failure);

/// The fake, with the pages a deletion asks for logged as `<table>:<limit>`
/// and the space of each in [spacesPaged], and a hook before every page and
/// around the mark, where a test scripts a failure — or another device's
/// write — mid-job.
class _DeletingGateway extends FakeSyncGateway {
  final List<String> pages = [];
  final List<String> spacesPaged = [];
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
    spacesPaged.add(space.spaceId);
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

  FutureOr<void> Function()? beforeUnbind;

  @override
  Future<void> unbind({bool raiseFloor = true}) async {
    await beforeUnbind?.call();
    await super.unbind(raiseFloor: raiseFloor);
  }
}

/// The install-wide record, with its next [failReads] reads of the
/// deletions throwing — where a run, a status read or a record meets
/// storage that cannot be read — and a hook after every deletion recorded,
/// where a test reads the status the moment the record is written.
class _FailingRegistry extends SyncSpaceRegistry {
  _FailingRegistry(super.prefs, {required super.databaseExists});

  int failReads = 0;
  FutureOr<void> Function()? afterAdd;

  @override
  List<SyncPendingDeletion> pendingDeletions() {
    if (failReads > 0) {
      failReads--;
      throw StateError('the record cannot be read');
    }
    return super.pendingDeletions();
  }

  @override
  Future<void> addPendingDeletion(SyncPendingDeletion deletion) async {
    await super.addPendingDeletion(deletion);
    await afterAdd?.call();
  }
}

/// The real manager, but with [spaceRegistry] the one a test holds.
class _RegistryManager implements DatabaseManager {
  _RegistryManager(this._manager, this.spaceRegistry);

  final DatabaseManager _manager;

  @override
  final SyncSpaceRegistry spaceRegistry;

  @override
  String getActiveDatabaseName() => _manager.getActiveDatabaseName();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// "Delete cloud copy" (cloud-multi-user-roadmap §5): the service's local
/// phase — mark → re-read → record → unbind — and the background run that
/// empties and removes the space, the pending record that makes an
/// interrupted deletion finishable, the status that reports it, and the bind
/// flow that never offers a dying space — over an in-memory database bound
/// through the real binding service and the real `DatabaseManager` over a
/// temporary directory.
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
    // No run may outlive its case into the next one's records.
    await service.deletionRunsIdle();
    SettingsService.reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SettingsKeys.syncBoundSpaces);
    await prefs.remove(SettingsKeys.syncPendingDeletions);
    await db.close();
  });

  SyncSpaceRegistry registry() => manager.spaceRegistry;

  Future<SyncDeletionStatus> status([String account = _uid]) =>
      service.deletionStatus(account);

  /// Every run ended, and what [follow]'s streams were sent delivered.
  Future<void> settled() async {
    await service.deletionRunsIdle();
    await pumpEventQueue();
  }

  /// Every status [deletionStatusOf] sends for [account] from now on.
  Future<List<SyncDeletionStatus>> follow([String account = _uid]) async {
    final statuses = <SyncDeletionStatus>[];
    final subscription = service.deletionStatusOf(account).listen(statuses.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    return statuses;
  }

  /// How many runs [statuses] show starting.
  int runsStarted(List<SyncDeletionStatus> statuses) {
    var started = 0;
    var running = false;
    for (final status in statuses) {
      if (status.running && !running) started++;
      running = status.running;
    }
    return started;
  }

  /// The account stream [SyncSpaceService.followAccounts] follows, as the
  /// app's start-up hands it the identity's.
  StreamController<String?> followedAccounts() {
    final accounts = StreamController<String?>();
    addTearDown(accounts.close);
    service.followAccounts(accounts.stream);
    return accounts;
  }

  /// [uid] signed in — null, signed out — and whatever it resumed ended.
  Future<void> becomes(StreamController<String?> accounts, String? uid) async {
    accounts.add(uid);
    await pumpEventQueue();
    await settled();
  }

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

  /// A space of [owner] marked for deletion and recorded, as a deletion
  /// interrupted after its unbind leaves it.
  Future<SyncSpaceInfo> recordedSpace(
    String name, {
    String owner = _uid,
    int rows = 0,
  }) async {
    final space = await createSpace(name, owner: owner);
    plantRows(space, 'folders', rows);
    await gateway.markSpaceDeleted(space.ref);
    await registry().addPendingDeletion(
      SyncPendingDeletion(space: space.ref, spaceName: name),
    );
    return space;
  }

  /// A second service, over the same gateway and binding, whose record is a
  /// [_FailingRegistry] over the same preferences.
  Future<(SyncSpaceService, _FailingRegistry)> overFailingRecord() async {
    final failing = _FailingRegistry(
      await SharedPreferences.getInstance(),
      databaseExists: manager.databaseExists,
    );
    final over = SyncSpaceService(
      gateway: gateway,
      database: () async => db,
      binding: () async => binding,
      databases: () async => _RegistryManager(manager, failing),
    );
    addTearDown(over.deletionRunsIdle);
    return (over, failing);
  }

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
      await settled();

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

    test('returns once unbound while the emptying is still held; the run '
        'then completes and the status shows it', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      final record = SyncPendingDeletion(space: space.ref, spaceName: 'Phone');
      final hold = gateway.holdDeleteRows = Completer<void>();

      await service.deleteCloudCopy();

      expect(await binding.read(), isNull);
      expect(registry().claims(), isEmpty);
      expect(rowsLeft(space), 3, reason: 'the emptying is still held');
      expect(
        await status(),
        SyncDeletionStatus(accountUid: _uid, pending: [record], running: true),
      );

      hold.complete();
      await settled();

      expect(await gateway.readSpace(space.ref), isNull);
      expect(rowsLeft(space), 0);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 3),
      );
    });

    test('the status runs from recorded and running with a rising count to '
        'finished with nothing pending', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 25);
      final record = SyncPendingDeletion(space: space.ref, spaceName: 'Phone');
      final statuses = await follow();

      await service.deleteCloudCopy();
      await settled();

      expect(statuses, [
        const SyncDeletionStatus(accountUid: _uid),
        SyncDeletionStatus(accountUid: _uid, pending: [record], running: true),
        SyncDeletionStatus(
          accountUid: _uid,
          pending: [record],
          running: true,
          removed: 20,
        ),
        SyncDeletionStatus(
          accountUid: _uid,
          pending: [record],
          running: true,
          removed: 25,
        ),
        const SyncDeletionStatus(accountUid: _uid, running: true, removed: 25),
        const SyncDeletionStatus(accountUid: _uid, removed: 25),
      ]);
    });

    test('reports the documents removed so far after every page, every '
        'table chunks included asked for in pages of twenty', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      plantRows(space, 'content_chunks', 120);
      plantRows(space, 'calendar_events', 4);
      final statuses = await follow();

      await service.deleteCloudCopy();
      await settled();

      final counts = <int>[];
      for (final status in statuses) {
        if (status.removed > 0 && !counts.contains(status.removed)) {
          counts.add(status.removed);
        }
      }
      expect(counts, [3, 23, 43, 63, 83, 103, 123, 127]);
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
      expect((await status()).running, isFalse);
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
      expect((await status()).running, isFalse);
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
        expect((await status()).running, isFalse);
      });
    }

    test('another account signed in is refused at the first read: nothing '
        'marked, recorded or unbound', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 2);
      gateway.actingAccount = _partner;

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.permissionDenied)),
      );

      expect(gateway.calls, isEmpty);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect(registry().pendingDeletions(), isEmpty);
      gateway.actingAccount = _uid;
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isFalse);
      expect(rowsLeft(space), 2);
    });

    test('the quota running out while emptying leaves the database unbound, '
        'the deletion recorded and the failure in the status; finishing it '
        'completes the job', () async {
      final space = await boundSpace('Phone');
      plantRows(space, 'folders', 3);
      plantRows(space, 'calendar_events', 2);
      final record = SyncPendingDeletion(space: space.ref, spaceName: 'Phone');
      gateway.beforePage = (table, _) {
        if (table == 'calendar_events') {
          throw const SyncGatewayException(
            SyncGatewayFailure.quotaExhausted,
            'scripted',
          );
        }
      };

      await service.deleteCloudCopy();
      await settled();

      expect(await binding.read(), isNull);
      expect(registry().claims(), isEmpty);
      expect(registry().pendingDeletions(), [record]);
      expect(await service.pendingDeletions(_uid), [record]);
      expect(
        await status(),
        SyncDeletionStatus(
          accountUid: _uid,
          pending: [record],
          removed: 3,
          failure: SyncBindFailure.quotaExhausted,
        ),
      );
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect(gateway.rowsOf(space.ref, 'folders'), isEmpty);
      expect(gateway.rowsOf(space.ref, 'calendar_events'), hasLength(2));

      gateway.beforePage = null;
      await service.finishPendingDeletions(accountUid: _uid);
      await settled();

      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 2),
      );
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
      await settled();

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
      expect((await status()).failure, isNull);
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

      await service.deleteCloudCopy();
      await settled();

      expect(gateway.pagesOf('content_chunks'), [
        for (final limit in [20, 10, 5, 2, 1]) 'content_chunks:$limit',
      ]);
      expect(await binding.read(), isNull);
      expect(registry().pendingDeletions(), hasLength(1));
      expect((await status()).failure, SyncBindFailure.offline);
    });

    test('mark, then record, then unbind: an app that dies at the unbind '
        'leaves the marked space recorded and no run (review F6)', () async {
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
      await settled();

      expect(callsAtUnbind, ['mark']);
      expect(recordedAtUnbind, [record]);
      expect(registry().pendingDeletions(), [record]);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect(rowsLeft(space), 2);
      expect((await status()).running, isFalse);
    });

    test('from the record on the status reads running with the last run\'s '
        'failure cleared; a failed unbind settles it pending, not running, '
        'with no failure (review G4)', () async {
      final old = await recordedSpace('Old', rows: 1);
      final oldRecord = SyncPendingDeletion(space: old.ref, spaceName: 'Old');
      gateway.beforePage = (table, _) => throw const SyncGatewayException(
        SyncGatewayFailure.quotaExhausted,
        'scripted',
      );
      await service.finishPendingDeletions(accountUid: _uid);
      await settled();
      gateway.beforePage = null;
      final failed = SyncDeletionStatus(
        accountUid: _uid,
        pending: [oldRecord],
        failure: SyncBindFailure.quotaExhausted,
      );
      expect(await status(), failed);
      final space = await boundSpace('Phone');
      final record = SyncPendingDeletion(space: space.ref, spaceName: 'Phone');
      final statuses = await follow();
      List<SyncDeletionStatus>? heardAtUnbind;
      SyncDeletionStatus? readAtUnbind;
      binding.beforeUnbind = () async {
        await pumpEventQueue();
        heardAtUnbind = [...statuses];
        readAtUnbind = await status();
        throw StateError('the unbind failed');
      };

      await expectLater(
        service.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.unknown)),
      );
      await settled();

      expect(heardAtUnbind, [
        failed,
        SyncDeletionStatus(
          accountUid: _uid,
          pending: [oldRecord, record],
          running: true,
        ),
      ]);
      expect(readAtUnbind, heardAtUnbind!.last);
      expect(statuses, [
        ...heardAtUnbind!,
        SyncDeletionStatus(accountUid: _uid, pending: [oldRecord, record]),
      ]);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect(gateway.spacesPaged, everyElement(old.ref.spaceId));
    });

    test('a record that cannot be written puts the last run\'s state back, '
        'its failure included, and leaves the database bound (review '
        'K7)', () async {
      final old = await recordedSpace('Old', rows: 1);
      final (over, failing) = await overFailingRecord();
      gateway.beforePage = (table, _) => throw const SyncGatewayException(
        SyncGatewayFailure.quotaExhausted,
        'scripted',
      );
      await over.finishPendingDeletions(accountUid: _uid);
      await over.deletionRunsIdle();
      gateway.beforePage = null;
      final failed = SyncDeletionStatus(
        accountUid: _uid,
        pending: [SyncPendingDeletion(space: old.ref, spaceName: 'Old')],
        failure: SyncBindFailure.quotaExhausted,
      );
      expect(await over.deletionStatus(_uid), failed);
      final space = await boundSpace('Phone');
      failing.failReads = 1;

      await expectLater(
        over.deleteCloudCopy(),
        throwsA(_fails(SyncBindFailure.unknown)),
      );
      await over.deletionRunsIdle();

      expect(await over.deletionStatus(_uid), failed);
      expect((await binding.read())!.spaceId, space.ref.spaceId);
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

      await service.deleteCloudCopy();
      await settled();

      expect(recordedAtUnbind, hasLength(1));
      expect((await status()).removed, 5);
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
      await settled();

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
      await settled();

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
      await settled();

      expect(await gateway.readSpace(space.ref), isNull);
      expect(await binding.read(), isNull);
      expect(registry().pendingDeletions(), isEmpty);
      expect((await status()).failure, isNull);
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

      await service.deleteCloudCopy();
      await settled();

      expect((await status()).failure, SyncBindFailure.permissionDenied);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isTrue);
      expect(registry().pendingDeletions(), hasLength(1));
      expect(rowsLeft(space), 2);
    });
  });

  group('the run', () {
    test('asking again for an account whose run is in flight starts no '
        'second run', () async {
      final space = await recordedSpace('Old', rows: 3);
      final statuses = await follow();
      final accounts = followedAccounts();
      final hold = gateway.holdDeleteRows = Completer<void>();

      await service.finishPendingDeletions(accountUid: _uid);
      await service.finishPendingDeletions(accountUid: _uid);
      accounts.add(_uid);
      await pumpEventQueue();
      hold.complete();
      await settled();

      expect(runsStarted(statuses), 1);
      expect(await gateway.readSpace(space.ref), isNull);
      expect(gateway.pagesOf('folders'), ['folders:20', 'folders:20']);
      expect(
        gateway.calls.where((call) => call == 'deleteSpace'),
        hasLength(1),
      );
    });

    test('a request for another account waits for the run in flight to '
        'end', () async {
      final mine = await recordedSpace('Mine', rows: 2);
      final theirs = await recordedSpace('Theirs', owner: _partner, rows: 2);
      final hold = gateway.holdDeleteRows = Completer<void>();

      await service.finishPendingDeletions(accountUid: _uid);
      await service.finishPendingDeletions(accountUid: _partner);
      await pumpEventQueue();

      expect((await status()).running, isTrue);
      expect((await status(_partner)).running, isTrue, reason: 'waiting');
      expect(gateway.spacesPaged, everyElement(mine.ref.spaceId));
      expect(rowsLeft(theirs), 2);

      hold.complete();
      await settled();

      final firstOfTheirs = gateway.spacesPaged.indexOf(theirs.ref.spaceId);
      expect(firstOfTheirs, greaterThan(0));
      expect(
        gateway.spacesPaged.sublist(0, firstOfTheirs),
        everyElement(mine.ref.spaceId),
      );
      expect(
        gateway.spacesPaged.sublist(firstOfTheirs),
        everyElement(theirs.ref.spaceId),
      );
      expect(await gateway.readSpace(mine.ref), isNull);
      expect(await gateway.readSpace(theirs.ref), isNull);
      expect((await status()).running, isFalse);
      expect((await status(_partner)).running, isFalse);
    });

    test('takes every record of its account in turn and stops at the first '
        'failure, leaving that record and the later ones', () async {
      final first = await recordedSpace('First', rows: 1);
      final second = await recordedSpace('Second', rows: 1);
      final third = await recordedSpace('Third', rows: 1);
      gateway.beforePage = (table, _) {
        if (gateway.spacesPaged.last == second.ref.spaceId) {
          throw const SyncGatewayException(
            SyncGatewayFailure.offline,
            'scripted',
          );
        }
      };

      await service.finishPendingDeletions(accountUid: _uid);
      await settled();

      expect(await gateway.readSpace(first.ref), isNull);
      expect(gateway.spacesPaged, isNot(contains(third.ref.spaceId)));
      expect(
        [for (final pending in registry().pendingDeletions()) pending.space],
        [second.ref, third.ref],
      );
      expect((await status()).failure, SyncBindFailure.offline);
    });

    test('a deletion recorded while its account\'s run is in flight is '
        'taken by that run', () async {
      final first = await recordedSpace('First', rows: 1);
      final hold = gateway.holdDeleteRows = Completer<void>();
      await service.finishPendingDeletions(accountUid: _uid);
      await pumpEventQueue();

      final bound = await boundSpace('Phone');
      plantRows(bound, 'folders', 1);
      await service.deleteCloudCopy();
      hold.complete();
      await settled();

      expect(await gateway.readSpace(first.ref), isNull);
      expect(await gateway.readSpace(bound.ref), isNull);
      expect(rowsLeft(bound), 0);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('the account\'s replay at launch resumes its deletion, with no '
        'bloc and no page in existence (review G3)', () async {
      final space = await recordedSpace('Old', rows: 2);
      final statuses = await follow();
      final accounts = followedAccounts();

      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 1);
      expect(await gateway.readSpace(space.ref), isNull);
      expect(rowsLeft(space), 0);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('a run cut by an account change is resumed when the account '
        'returns (review G2)', () async {
      final space = await recordedSpace('Old', rows: 25);
      final statuses = await follow();
      final accounts = followedAccounts();
      final hold = gateway.holdDeleteRows = Completer<void>();
      accounts.add(_uid);
      await pumpEventQueue();
      expect((await status()).running, isTrue);

      gateway.actingAccount = _partner;
      accounts.add(_partner);
      await pumpEventQueue();
      hold.complete();
      await settled();

      expect((await status()).failure, SyncBindFailure.permissionDenied);
      expect(
        rowsLeft(space),
        5,
        reason: 'the held page was sent before the change, the next after',
      );

      gateway.actingAccount = _uid;
      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 2);
      expect(await gateway.readSpace(space.ref), isNull);
      expect((await status()).failure, isNull);
    });

    test('an account that returns while its run is still ending on the '
        'refusal is resumed once that run ends (review K4)', () async {
      final space = await recordedSpace('Old', rows: 2);
      final statuses = await follow();
      final accounts = followedAccounts();
      gateway.actingAccount = _uid;
      final first = gateway.holdDeleteRows = Completer<void>();
      accounts.add(_uid);
      await pumpEventQueue();

      gateway.actingAccount = _partner;
      accounts.add(_partner);
      await pumpEventQueue();
      // The next page goes out under the other account and is refused; its
      // answer is still on the way when the account comes back.
      final second = gateway.holdDeleteRows = Completer<void>();
      first.complete();
      await pumpEventQueue();
      expect(rowsLeft(space), 0, reason: 'the first page landed');
      gateway.actingAccount = _uid;
      accounts.add(_uid);
      await pumpEventQueue();
      expect((await status()).running, isTrue);

      second.complete();
      await settled();

      expect(runsStarted(statuses), 2);
      expect(await gateway.readSpace(space.ref), isNull);
      expect(registry().pendingDeletions(), isEmpty);
      expect((await status()).failure, isNull);
    });

    test('a resume owed to a run that ends on anything but the moment is '
        'not made (review K4)', () async {
      final space = await recordedSpace('Old', rows: 2);
      final statuses = await follow();
      final accounts = followedAccounts();
      final hold = gateway.holdDeleteRows = Completer<void>();
      accounts.add(_uid);
      await pumpEventQueue();
      accounts.add(null);
      await pumpEventQueue();
      accounts.add(_uid);
      await pumpEventQueue();
      gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

      hold.complete();
      await settled();

      expect(runsStarted(statuses), 1);
      expect((await status()).failure, SyncBindFailure.quotaExhausted);
      expect(rowsLeft(space), 2);
    });

    test('a disposed service ends its run at the next call and publishes '
        'nothing after (review K8)', () async {
      final space = await recordedSpace('Old', rows: 25);
      final statuses = await follow();
      final hold = gateway.holdDeleteRows = Completer<void>();
      await service.finishPendingDeletions(accountUid: _uid);
      await pumpEventQueue();
      final heard = statuses.length;

      await service.dispose();
      hold.complete();
      await settled();

      expect(gateway.pagesOf('folders'), ['folders:20']);
      expect(rowsLeft(space), 5, reason: 'the page in flight landed');
      expect(gateway.calls, isNot(contains('deleteSpace')));
      expect(registry().pendingDeletions(), hasLength(1));
      expect(statuses, hasLength(heard));
    });

    test('a run cut by a sign-out, or offline, is resumed at the next '
        'sign-in (review G2)', () async {
      final space = await recordedSpace('Old', rows: 2);
      final statuses = await follow();
      final accounts = followedAccounts();
      gateway.signedOut = true;

      await becomes(accounts, _uid);

      expect((await status()).failure, SyncBindFailure.permissionDenied);
      gateway
        ..signedOut = false
        ..failNextWith(SyncGatewayFailure.offline);
      await becomes(accounts, null);
      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 2);
      expect((await status()).failure, SyncBindFailure.offline);
      expect(rowsLeft(space), 2);

      await becomes(accounts, null);
      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 3);
      expect(await gateway.readSpace(space.ref), isNull);
    });

    test('a run that ended on the quota is not resumed by the account\'s '
        'return: it waits for "Finish deleting"', () async {
      final space = await recordedSpace('Old', rows: 2);
      gateway.beforePage = (table, _) => throw const SyncGatewayException(
        SyncGatewayFailure.quotaExhausted,
        'scripted',
      );
      final statuses = await follow();
      final accounts = followedAccounts();

      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 1);
      expect((await status()).failure, SyncBindFailure.quotaExhausted);

      gateway.beforePage = null;
      await becomes(accounts, null);
      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 1, reason: 'waits for "Finish deleting"');
      expect((await status()).failure, SyncBindFailure.quotaExhausted);
      expect(rowsLeft(space), 2);

      await service.finishPendingDeletions(accountUid: _uid);
      await settled();

      expect(runsStarted(statuses), 2);
      expect(await gateway.readSpace(space.ref), isNull);
    });

    test('an account known with nothing pending requests nothing; another '
        'account\'s records are not its own', () async {
      final theirs = await recordedSpace('Theirs', owner: _partner, rows: 1);
      final statuses = await follow();
      final accounts = followedAccounts();
      gateway.readSpaceCalls = 0;

      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 0);
      expect(gateway.calls, ['mark'], reason: 'the setup\'s only');
      expect(gateway.readSpaceCalls, 0, reason: 'no network call');
      expect(rowsLeft(theirs), 1);
    });

    test('the same account heard twice in a row is known once', () async {
      final space = await recordedSpace('Old', rows: 1);
      gateway.beforePage = (table, _) => throw const SyncGatewayException(
        SyncGatewayFailure.offline,
        'scripted',
      );
      final statuses = await follow();
      final accounts = followedAccounts();
      await becomes(accounts, _uid);
      gateway.beforePage = null;

      await becomes(accounts, _uid);

      expect(runsStarted(statuses), 1);
      expect(rowsLeft(space), 1);
    });

    test('a throw in a run\'s tail ends that account\'s run with the '
        'failure, and the account waiting behind it still runs (review '
        'G6)', () async {
      final mine = await recordedSpace('Mine', rows: 1);
      final theirs = await recordedSpace('Theirs', owner: _partner, rows: 1);
      final (over, failing) = await overFailingRecord();
      var armed = true;
      // The page's status read fails inside the job, the run's last one in
      // its tail.
      gateway.beforePage = (table, _) {
        if (armed && gateway.spacesPaged.last == mine.ref.spaceId) {
          armed = false;
          failing.failReads = 2;
        }
      };

      await over.finishPendingDeletions(accountUid: _uid);
      await over.finishPendingDeletions(accountUid: _partner);
      await over.deletionRunsIdle();

      expect(
        await over.deletionStatus(_uid),
        SyncDeletionStatus(
          accountUid: _uid,
          pending: [SyncPendingDeletion(space: mine.ref, spaceName: 'Mine')],
          removed: 1,
          failure: SyncBindFailure.unknown,
        ),
      );
      expect(
        await over.deletionStatus(_partner),
        const SyncDeletionStatus(accountUid: _partner, removed: 1),
      );
      expect(await gateway.readSpace(theirs.ref), isNull);
    });

    test('a new listener hears the current status first', () async {
      final space = await recordedSpace('Old');

      final statuses = await follow();

      expect(statuses, [
        SyncDeletionStatus(
          accountUid: _uid,
          pending: [SyncPendingDeletion(space: space.ref, spaceName: 'Old')],
        ),
      ]);
    });

    test('a first status read that fails is heard as the status with '
        'nothing pending, and the next change corrects it (review '
        'G7)', () async {
      final space = await recordedSpace('Old', rows: 1);
      final record = SyncPendingDeletion(space: space.ref, spaceName: 'Old');
      final (over, failing) = await overFailingRecord();
      failing.failReads = 1;
      final statuses = <SyncDeletionStatus>[];
      final subscription = over.deletionStatusOf(_uid).listen(statuses.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(statuses, [const SyncDeletionStatus(accountUid: _uid)]);

      await over.finishPendingDeletions(accountUid: _uid);
      await over.deletionRunsIdle();
      await pumpEventQueue();

      expect(
        statuses[1],
        SyncDeletionStatus(accountUid: _uid, pending: [record], running: true),
      );
      expect(
        statuses.last,
        const SyncDeletionStatus(accountUid: _uid, removed: 1),
      );
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

      await service.finishPendingDeletions(accountUid: _uid);
      await settled();

      expect(registry().pendingDeletions(), isEmpty);
      expect(gateway.calls, isEmpty);
      expect((await status()).removed, 0);
      expect((await gateway.readSpace(space.ref))!.markedForDeletion, isFalse);
      expect(rowsLeft(space), 2);
    });

    test('leaves another account\'s record and space alone', () async {
      final partners = await recordedSpace('Partner', owner: _partner, rows: 2);
      final record = SyncPendingDeletion(
        space: partners.ref,
        spaceName: 'Partner',
      );
      gateway.calls.clear();

      await service.finishPendingDeletions(accountUid: _uid);
      await settled();

      expect(registry().pendingDeletions(), [record]);
      expect(await service.pendingDeletions(_uid), isEmpty);
      expect(await service.pendingDeletions(_partner), [record]);
      expect((await status(_partner)).pending, [record]);
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
      await settled();

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

        await service.finishPendingDeletions(accountUid: _uid);
        await settled();

        expect((await status()).failure, SyncBindFailure.appOutdated);
        expect(registry().pendingDeletions(), hasLength(1));
        expect(rowsLeft(space), 1);
      },
    );

    test('a space a newer build wrote to is passed over: the later records '
        'are finished, and the run ends as appOutdated with that record '
        'left', () async {
      final newer = await createSpace(
        'Newer',
        schema: DatabaseSchema.syncSchemaVersion + 1,
      );
      plantRows(newer, 'folders', 1);
      await gateway.markSpaceDeleted(newer.ref);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: newer.ref, spaceName: 'Newer'),
      );
      final later = await recordedSpace('Later', rows: 2);
      final statuses = await follow();

      await service.finishPendingDeletions(accountUid: _uid);
      await settled();

      expect(await gateway.readSpace(later.ref), isNull);
      expect(rowsLeft(later), 0);
      expect(rowsLeft(newer), 1);
      expect(registry().pendingDeletions(), [
        SyncPendingDeletion(space: newer.ref, spaceName: 'Newer'),
      ]);
      expect(runsStarted(statuses), 1);
      final ended = await status();
      expect(ended.failure, SyncBindFailure.appOutdated);
      expect(ended.running, isFalse);
      expect(ended.removed, 2);
      expect(
        statuses.where((status) => status.failure != null),
        hasLength(1),
        reason: 'the failure is the run\'s end, never said mid-run',
      );
    });
  });

  group('the bind flow never offers a dying space', () {
    test('start() records a marked space, requests the run and returns its '
        'decision without waiting for it, offering only the live '
        'ones', () async {
      await db.folderDao.createFolder(name: 'Errands');
      final dying = await createSpace('Old');
      plantRows(dying, 'notes', 3);
      await gateway.markSpaceDeleted(dying.ref);
      final live = await createSpace('Live');
      final hold = gateway.holdDeleteRows = Completer<void>();

      final start = await service.start(accountUid: _uid);

      expect(start, SyncBindStartPick(spaces: [live], holdsData: true));
      expect(registry().pendingDeletions(), [
        SyncPendingDeletion(space: dying.ref, spaceName: 'Old'),
      ]);
      expect((await status()).running, isTrue);
      expect(rowsLeft(dying), 3, reason: 'the emptying is still held');

      hold.complete();
      await settled();

      expect(await gateway.readSpace(dying.ref), isNull);
      expect(rowsLeft(dying), 0);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('start() takes every marked space of the account through the run, '
        'never marking (review F7, F8)', () async {
      final first = await createSpace('Old');
      final second = await createSpace('Older');
      plantRows(first, 'folders', 3);
      plantRows(second, 'folders', 3);
      await gateway.markSpaceDeleted(first.ref);
      await gateway.markSpaceDeleted(second.ref);
      gateway.calls.clear();

      await service.start(accountUid: _uid);
      await settled();

      expect((await status()).removed, 6);
      expect(gateway.calls, isNot(contains('mark')), reason: 'never marks');
      expect(await gateway.readSpace(first.ref), isNull);
      expect(await gateway.readSpace(second.ref), isNull);
    });

    test('start() with only a marked space left creates the first space '
        'and binds it', () async {
      final dying = await createSpace('Old');
      await gateway.markSpaceDeleted(dying.ref);

      final start = await service.start(accountUid: _uid);
      await settled();

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
      await settled();

      expect(start, SyncBindStartPick(spaces: [live], holdsData: true));
      expect((await gateway.readSpace(dying.ref))!.markedForDeletion, isTrue);
      expect((await status()).failure, SyncBindFailure.offline);
      expect(registry().pendingDeletions(), hasLength(1));
    });

    test('start() records a marked space by the same path as a delete: from '
        'the record on the status reads running with the last run\'s failure '
        'cleared (review K7)', () async {
      final old = await recordedSpace('Old', rows: 1);
      final (over, failing) = await overFailingRecord();
      gateway.beforePage = (table, _) => throw const SyncGatewayException(
        SyncGatewayFailure.quotaExhausted,
        'scripted',
      );
      await over.finishPendingDeletions(accountUid: _uid);
      await over.deletionRunsIdle();
      gateway.beforePage = null;
      expect(
        (await over.deletionStatus(_uid)).failure,
        SyncBindFailure.quotaExhausted,
      );
      final dying = await createSpace('Dying');
      await gateway.markSpaceDeleted(dying.ref);
      final atRecord = <SyncDeletionStatus>[];
      failing.afterAdd = () async =>
          atRecord.add(await over.deletionStatus(_uid));

      await over.start(accountUid: _uid);
      await over.deletionRunsIdle();

      expect(atRecord, isNotEmpty);
      expect(
        atRecord,
        everyElement(
          isA<SyncDeletionStatus>()
              .having((status) => status.running, 'running', isTrue)
              .having((status) => status.failure, 'failure', isNull),
        ),
      );
      expect(registry().pendingDeletions(), isEmpty);
      expect(await gateway.readSpace(old.ref), isNull);
      expect(await gateway.readSpace(dying.ref), isNull);
    });

    test('start() binds all the same when a marked space cannot be recorded, '
        'and still never offers it', () async {
      final dying = await createSpace('Old');
      await gateway.markSpaceDeleted(dying.ref);
      final live = await createSpace('Live');
      final (over, failing) = await overFailingRecord();
      failing.failReads = 1;

      final start = await over.start(accountUid: _uid);
      await over.deletionRunsIdle();

      expect(start, SyncBindStartBound(live.ref));
      expect((await binding.read())!.spaceId, live.ref.spaceId);
      expect(registry().pendingDeletions(), isEmpty);
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
