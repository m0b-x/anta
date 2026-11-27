import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/dev_options_service.dart';

/// `DevOptionsService.getInstance` publishes only a service whose options are
/// loaded, never one over a database a switch overtook — the
/// `SettingsService` shape. The switches are staged as
/// `settings_service_open_test.dart` stages them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storeKey = 'dev_options';
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_dev_options_open');
    messenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues({'active_database': 'one'});
    DatabaseManager.resetForTesting();
    manager = await DatabaseManager.getInstance();
  });

  setUp(() async {
    // A case that fails an open on purpose must not hand its notice on.
    AppDatabase.resetSwitchAnnouncementForTesting();
    await manager.setActiveDatabaseName('one');
    await AppDatabase.getInstance();
    DevOptionsService.reset();
    DevOptions.instance.lockDeveloperMode();
  });

  tearDownAll(() async {
    DevOptionsService.reset();
    DevOptions.instance.lockDeveloperMode();
    await AppDatabase.deleteAllData();
    AppDatabase.resetSwitchAnnouncementForTesting();
    DatabaseManager.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Makes [names] active one after another: the first now, each next one
  /// as the database before it announces itself.
  List<String> switchThrough(List<String> names) {
    final announced = <String>[];
    void onSwitched(AppDatabase _) {
      announced.add(manager.getActiveDatabaseName());
      if (announced.length < names.length) {
        unawaited(manager.setActiveDatabaseName(names[announced.length]));
      }
    }

    DatabaseLifecycle.registerSwitchedHandler(onSwitched);
    addTearDown(() => DatabaseLifecycle.unregisterSwitchedHandler(onSwitched));
    unawaited(manager.setActiveDatabaseName(names.first));
    return announced;
  }

  Future<Map<String, dynamic>?> storedIn(String database) async {
    final db = await AppDatabase.openInstanceOf(database)!;
    final json = await db.userSettingsDao.getValue(storeKey);
    return json == null ? null : jsonDecode(json) as Map<String, dynamic>;
  }

  test('a caller that arrives during the open gets the options loaded and '
      'can save them in the turn it is handed out', () async {
    final one = await AppDatabase.openInstanceOf('one')!;
    await one.userSettingsDao.setValue(
      storeKey,
      jsonEncode({'showWhitespace': true}),
    );

    final first = DevOptionsService.getInstance();
    final second = await DevOptionsService.getInstance().then((service) {
      expect(DevOptions.instance.showWhitespace, isTrue);
      // The save reads the database before its first await.
      return service.saveOptions().then((_) => service);
    });

    expect(second, same(await first));
    expect((await storedIn('one'))?['showWhitespace'], isTrue);
  });

  test('a switch during the open: the service published is over the '
      'database switched to last, its reset registered', () async {
    final announced = switchThrough(['two', 'three']);

    final service = await DevOptionsService.getInstance();

    expect(announced, ['two', 'three']);
    expect(await DevOptionsService.getInstance(), same(service));
    DevOptions.instance.showFpsCounter = true;
    await service.saveOptions();
    expect((await storedIn('three'))?['showFpsCounter'], isTrue);
    DatabaseLifecycle.notifyDatabaseSwitching();
    expect(await DevOptionsService.getInstance(), isNot(same(service)));
  });

  test('a reset during the open: the open hands out a whole service, and '
      'the next reset gives a new one', () async {
    final opening = DevOptionsService.getInstance();
    DevOptionsService.reset();

    final service = await opening;
    DevOptions.instance.showRenderTime = true;
    await service.saveOptions();

    expect(await DevOptionsService.getInstance(), same(service));
    DevOptionsService.reset();
    DevOptions.instance.resetAll();
    final next = await DevOptionsService.getInstance();
    expect(next, isNot(same(service)));
    expect(DevOptions.instance.showRenderTime, isTrue);
  });

  test(
    'a failed open publishes nothing: the next caller opens again',
    () async {
      // A documents directory that is a file: the database cannot be opened.
      final blocked = File('${tempDir.path}/blocked')..writeAsStringSync('');
      messenger.setMockMethodCallHandler(
        pathProvider,
        (_) async => blocked.path,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          pathProvider,
          (_) async => tempDir.path,
        ),
      );
      await manager.setActiveDatabaseName('broken');
      // The switch away from 'one' fails here, so the service's own open fails
      // with no reset behind it to drop what that open left.
      await expectLater(AppDatabase.getInstance(), throwsA(anything));

      await expectLater(DevOptionsService.getInstance(), throwsA(anything));

      messenger.setMockMethodCallHandler(
        pathProvider,
        (_) async => tempDir.path,
      );
      final service = await DevOptionsService.getInstance();
      DevOptions.instance.showNoteSize = true;
      await service.saveOptions();
      expect((await storedIn('broken'))?['showNoteSize'], isTrue);
    },
  );
}
