import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/core/di/injection.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../../support/fake_sync_gateway.dart';

const _uid = 'uid-1';

Matcher _fails(SyncBindFailure failure, [String? holder]) =>
    isA<SyncSpaceException>()
        .having((e) => e.failure, 'failure', failure)
        .having((e) => e.holderDatabase, 'holderDatabase', holder);

/// "Download the space into a new database" (record §2 D2 A, §3.6) on the
/// app's own singletons over a temporary directory: the new database is
/// really created, made active and switched to in place, then bound — and a
/// failure really switches back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;
  late SharedPreferences prefs;
  late FakeSyncGateway gateway;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_space_download');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
    prefs = await SharedPreferences.getInstance();
  });

  /// The binding service, failing once the download has switched away from
  /// `phone` — the bind's own call, not the holder check before the create.
  Future<SyncBindingService> failingBind() async {
    if (manager.getActiveDatabaseName() != 'phone') {
      throw StateError('scripted');
    }
    return SyncBindingService.getInstance();
  }

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<AppDatabase> switchTo(String name) async {
    await manager.setActiveDatabaseName(name);
    return AppDatabase.getInstance();
  }

  setUp(() async {
    gateway = FakeSyncGateway();
    await switchTo('phone');
  });

  tearDown(() async {
    await switchTo('phone');
    final binding = await SyncBindingService.getInstance();
    if (await binding.read() != null) await binding.unbind();
    await (await SharedPreferences.getInstance()).remove(
      SettingsKeys.syncBoundSpaces,
    );
    for (final info in await manager.listDatabases()) {
      if (info.name != 'phone') await manager.deleteDatabase(info.name);
    }
    // A case fails an open on purpose; its notice must not reach the next.
    AppDatabase.resetSwitchAnnouncementForTesting();
  });

  Future<SyncSpaceInfo> createSpace(String name) => gateway.createSpace(
    ownerUid: _uid,
    name: name,
    deviceId: 'tablet-device',
    schema: DatabaseSchema.currentVersion,
  );

  test('creates a database named after the space, switches to it and binds '
      'it with nothing local; the database left stays as it was', () async {
    final phone = await AppDatabase.getInstance();
    await phone.folderDao.createFolder(name: 'Errands');
    final space = await createSpace('Gym log!');

    final name = await SyncSpaceService(
      gateway: gateway,
    ).downloadIntoNewDatabase(space, accountUid: _uid);

    expect(name, 'Gym_log_');
    expect(manager.getActiveDatabaseName(), name);
    expect(AppDatabase.openInstanceOf(name), isNotNull);
    final fresh = await AppDatabase.getInstance();
    expect(await fresh.folderDao.getFolderCount(null), 0);
    final bound = await (await SyncBindingService.getInstance()).read();
    expect(bound!.spaceId, space.ref.spaceId);
    expect(bound.accountUid, _uid);
    expect(await fresh.syncDao.getValue(SyncDao.keyBindMergePending), '1');
    expect(await manager.spaceRegistry.holderOf(space.ref), name);

    await switchTo('phone');
    expect(await (await SyncBindingService.getInstance()).read(), isNull);
    final back = await AppDatabase.getInstance();
    expect(await back.folderDao.getFolderCount(null), 1);
  });

  test('a name a database already has gets the next free suffix', () async {
    await manager.createDatabase('Gym');
    final space = await createSpace('Gym');

    final name = await SyncSpaceService(
      gateway: gateway,
    ).downloadIntoNewDatabase(space, accountUid: _uid);

    expect(name, 'Gym_1');
  });

  test('a failure after the create switches back to the database the user '
      'started from and deletes the new file', () async {
    final space = await createSpace('Tablet');
    final service = SyncSpaceService(gateway: gateway, binding: failingBind);

    await expectLater(
      service.downloadIntoNewDatabase(space, accountUid: _uid),
      throwsA(
        isA<SyncSpaceException>().having(
          (e) => e.failure,
          'failure',
          SyncBindFailure.unknown,
        ),
      ),
    );

    expect(manager.getActiveDatabaseName(), 'phone');
    expect(AppDatabase.openInstanceOf('phone'), isNotNull);
    expect(await manager.databaseExists('Tablet'), isFalse);
    expect(manager.spaceRegistry.claims(), isEmpty);
  });

  test('a space another database of this install holds is refused before '
      'anything is created', () async {
    final space = await createSpace('Tablet');
    await manager.createDatabase('laptop');
    await manager.spaceRegistry.claim(space.ref, 'laptop');

    await expectLater(
      SyncSpaceService(
        gateway: gateway,
      ).downloadIntoNewDatabase(space, accountUid: _uid),
      throwsA(_fails(SyncBindFailure.spaceHeldByAnotherDatabase, 'laptop')),
    );

    expect(await manager.databaseExists('Tablet'), isFalse);
    expect(manager.getActiveDatabaseName(), 'phone');
  });

  group('one rule for the holder, as Merge has it (review BA-L1)', () {
    test('the active database\'s stale claim, unbound, is not in the '
        'way', () async {
      final space = await createSpace('Tablet');
      await manager.spaceRegistry.claim(space.ref, 'phone');

      final name = await SyncSpaceService(
        gateway: gateway,
      ).downloadIntoNewDatabase(space, accountUid: _uid);

      expect(name, 'Tablet');
      expect(await manager.spaceRegistry.holderOf(space.ref), 'Tablet');
    });

    test('the active database bound to the space holds it', () async {
      final space = await createSpace('Tablet');
      await (await SyncBindingService.getInstance()).bind(
        space: space.ref,
        accountUid: _uid,
      );

      await expectLater(
        SyncSpaceService(
          gateway: gateway,
        ).downloadIntoNewDatabase(space, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.spaceHeldByAnotherDatabase, 'phone')),
      );
      expect(await manager.databaseExists('Tablet'), isFalse);
    });
  });

  test('from a bound database, the database left keeps its binding and its '
      'claim', () async {
    final kept = await createSpace('Phone');
    await (await SyncBindingService.getInstance()).bind(
      space: kept.ref,
      accountUid: _uid,
    );
    final space = await createSpace('Tablet');

    final name = await SyncSpaceService(
      gateway: gateway,
    ).downloadIntoNewDatabase(space, accountUid: _uid);

    expect(await manager.spaceRegistry.holderOf(space.ref), name);
    expect(await manager.spaceRegistry.holderOf(kept.ref), 'phone');
    await switchTo('phone');
    final binding = await (await SyncBindingService.getInstance()).read();
    expect(binding!.spaceId, kept.ref.spaceId);
  });

  test('a restore in flight is refused before any database is '
      'created', () async {
    final space = await createSpace('Tablet');

    await SyncSuspension.run(() async {
      await expectLater(
        SyncSpaceService(
          gateway: gateway,
        ).downloadIntoNewDatabase(space, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.suspended)),
      );
    });

    expect(await manager.databaseExists('Tablet'), isFalse);
    expect(manager.getActiveDatabaseName(), 'phone');
  });

  group('the space is read before anything changes (review BA-M3)', () {
    test('offline fails as offline', () async {
      final space = await createSpace('Tablet');
      gateway.failNextWith(SyncGatewayFailure.offline);

      await expectLater(
        SyncSpaceService(
          gateway: gateway,
        ).downloadIntoNewDatabase(space, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.offline)),
      );

      expect(gateway.readSpaceCalls, 1);
      expect(await manager.databaseExists('Tablet'), isFalse);
      expect(manager.getActiveDatabaseName(), 'phone');
    });

    test('a space gone from the cloud fails as gone, not as no access '
        '(review X-13)', () async {
      final space = await createSpace('Tablet');
      gateway.deleteSpace(space.ref);

      await expectLater(
        SyncSpaceService(
          gateway: gateway,
        ).downloadIntoNewDatabase(space, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.spaceGone)),
      );

      expect(await manager.databaseExists('Tablet'), isFalse);
      expect(manager.getActiveDatabaseName(), 'phone');
    });
  });

  group('the download marker (review BA-M2)', () {
    Map<String, Object?>? marker() {
      final raw = prefs.getString(SettingsKeys.syncDownloadInFlight);
      return raw == null ? null : jsonDecode(raw) as Map<String, Object?>;
    }

    test(
      'is set from the switch to the bind, and cleared once bound',
      () async {
        final space = await createSpace('Tablet');
        Map<String, Object?>? atBind;

        await SyncSpaceService(
          gateway: gateway,
          binding: () {
            atBind = marker();
            return SyncBindingService.getInstance();
          },
        ).downloadIntoNewDatabase(space, accountUid: _uid);

        expect(atBind, {'from': 'phone', 'to': 'Tablet'});
        expect(marker(), isNull);
      },
    );

    test('is cleared by the switch back after a failure', () async {
      final space = await createSpace('Tablet');

      await expectLater(
        SyncSpaceService(
          gateway: gateway,
          binding: failingBind,
        ).downloadIntoNewDatabase(space, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.unknown)),
      );

      expect(marker(), isNull);
      expect(manager.getActiveDatabaseName(), 'phone');
    });
  });

  test('a new database that fails to open after the switch closed the old '
      'one: back on the old one, the switched handlers told, the '
      'repositories answering (review BA-H2)', () async {
    final phone = await AppDatabase.getInstance();
    await phone.folderDao.createFolder(name: 'Errands');
    final folders = await phone.folderDao.getFolderCount(null);
    getIt.registerSingleton<AppDatabase>(phone);
    registerRepositorySingletons();
    addTearDown(getIt.reset);
    final switchedTo = <AppDatabase>[];
    void record(AppDatabase database) => switchedTo.add(database);
    DatabaseLifecycle.registerSwitchedHandler(record);
    addTearDown(() => DatabaseLifecycle.unregisterSwitchedHandler(record));
    final space = await createSpace('Broken');
    final wal = Directory('${await manager.getDatabasePath('Broken')}-wal');
    await wal.create(recursive: true);
    addTearDown(() => wal.delete(recursive: true));

    await expectLater(
      SyncSpaceService(
        gateway: gateway,
      ).downloadIntoNewDatabase(space, accountUid: _uid),
      throwsA(_fails(SyncBindFailure.newDatabaseFailed)),
    );

    expect(manager.getActiveDatabaseName(), 'phone');
    final back = await AppDatabase.getInstance();
    expect(AppDatabase.openInstanceOf('phone'), isNotNull);
    expect(switchedTo, [same(back)]);
    expect(await getIt<FolderRepository>().getFolderCount(null), folders);
    expect(await getIt<NoteRepository>().getNoteCount(null), isNonNegative);
    final after = await getIt<FolderRepository>().createFolder(name: 'After');
    expect((await back.folderDao.getFolderById(after.id))!.name, 'After');
    expect(await manager.databaseExists('Broken'), isFalse);
  });
}
