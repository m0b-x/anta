import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_registry.dart';
import 'package:anta/services/sync/sync_suspension.dart';

const _uid = 'uid-1';
const _space = SyncSpaceRef(ownerUid: _uid, spaceId: 'space-1');

/// The binding squared with the install registry each time the binding
/// service is built (review BA-H1), on the app's own singletons over a
/// temporary directory: a raw copy of a bound database is the copy and is
/// unbound; a bound database nobody here holds claims its space.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_binding_heal');
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

  setUp(() => switchTo('phone'));

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
  });

  /// `phone` bound to [_space] and claiming it, its rows folded into the
  /// main file so a raw copy of the `.db` carries the binding.
  Future<void> bindPhone() async {
    await (await SyncBindingService.getInstance()).bind(
      space: _space,
      accountUid: _uid,
    );
    await manager.checkpoint('phone');
  }

  /// The Databases page's import: the `.db` copied in as it is.
  Future<void> importCopyOfPhone(String name) async =>
      manager.importDatabase(await manager.getDatabasePath('phone'), name);

  test('a raw copy of a bound database is unbound when it opens, and the '
      'database it was copied from keeps its claim', () async {
    await bindPhone();
    await importCopyOfPhone('copy');

    final copy = await switchTo('copy');
    final binding = await SyncBindingService.getInstance();

    expect(await binding.read(), isNull);
    expect(await copy.syncOutboxDao.count(), 0);
    expect(manager.spaceRegistry.claims(), [
      const SyncSpaceClaim(space: _space, databaseName: 'phone'),
    ]);
    await switchTo('phone');
    expect(
      (await (await SyncBindingService.getInstance()).read())!.spaceId,
      _space.spaceId,
    );
  });

  test('a bound database with no claim — a kill before the claim, a '
      'registry write that failed — claims its space', () async {
    await bindPhone();
    await manager.spaceRegistry.release('phone');
    SyncBindingService.reset();

    await SyncBindingService.getInstance();

    expect(await manager.spaceRegistry.holderOf(_space), 'phone');
  });

  test('a bound database moved in from another install, its space held by '
      'nobody here, claims it and stays bound', () async {
    await bindPhone();
    await importCopyOfPhone('moved');
    await (await SyncBindingService.getInstance()).unbind();

    await switchTo('moved');
    final binding = await SyncBindingService.getInstance();

    expect((await binding.read())!.spaceId, _space.spaceId);
    expect(await manager.spaceRegistry.holderOf(_space), 'moved');
  });

  test('a holder whose file is gone does not count: the bound database '
      'claims the space', () async {
    await bindPhone();
    await manager.spaceRegistry.claim(_space, 'deleted-elsewhere');
    SyncBindingService.reset();

    await SyncBindingService.getInstance();

    expect(await manager.spaceRegistry.holderOf(_space), 'phone');
  });

  test('nothing is healed while a restore holds the suspension', () async {
    await bindPhone();
    await manager.spaceRegistry.release('phone');
    SyncBindingService.reset();

    await SyncSuspension.run(SyncBindingService.getInstance);

    expect(manager.spaceRegistry.claims(), isEmpty);
  });

  test('a claim lands under the name the database has when it is written, '
      'not the one it was built under (review BA-M6)', () async {
    final binding = await SyncBindingService.getInstance();
    // Where a rename of the open file leaves the stored name; Windows cannot
    // rename an open file, so only the name moves here (the tearDown moves
    // it back).
    await manager.setActiveDatabaseName('renamed');

    await binding.bind(space: _space, accountUid: _uid);

    expect(manager.spaceRegistry.claims(), [
      const SyncSpaceClaim(space: _space, databaseName: 'renamed'),
    ]);
  });
}
