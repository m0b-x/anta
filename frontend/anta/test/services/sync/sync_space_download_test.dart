import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_service.dart';

import '../../support/fake_sync_gateway.dart';

const _uid = 'uid-1';

/// "Download the space into a new database" (record §2 D2 A, §3.6) on the
/// app's own singletons over a temporary directory: the new database is
/// really created, made active and switched to in place, then bound — and a
/// failure really switches back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;
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
  });

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
    await (await SharedPreferences.getInstance()).remove(
      SettingsKeys.syncBoundSpaces,
    );
    for (final info in await manager.listDatabases()) {
      if (info.name != 'phone') await manager.deleteDatabase(info.name);
    }
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
    final service = SyncSpaceService(
      gateway: gateway,
      binding: () async => throw StateError('scripted'),
    );

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
    await manager.spaceRegistry.claim(space.ref, 'phone');

    await expectLater(
      SyncSpaceService(
        gateway: gateway,
      ).downloadIntoNewDatabase(space, accountUid: _uid),
      throwsA(
        isA<SyncSpaceException>()
            .having(
              (e) => e.failure,
              'failure',
              SyncBindFailure.spaceHeldByAnotherDatabase,
            )
            .having((e) => e.holderDatabase, 'holder', 'phone'),
      ),
    );

    expect(await manager.databaseExists('Tablet'), isFalse);
    expect(manager.getActiveDatabaseName(), 'phone');
  });
}
