import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/settings_service.dart';

/// `SettingsService.getInstance` publishes only a service whose database no
/// switch overtook while it was opened (final review X-6). Every pass of the
/// open here is a real switch: the database each pass opens announces itself,
/// and the announcement makes the next database active, so the next pass
/// switches again — a switch landing inside every await, as one requested by
/// another caller would.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_settings_open');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    SharedPreferences.setMockInitialValues({'active_database': 'one'});
    DatabaseManager.resetForTesting();
    manager = await DatabaseManager.getInstance();
  });

  setUp(() async {
    await manager.setActiveDatabaseName('one');
    await AppDatabase.getInstance();
    SettingsService.reset();
  });

  tearDownAll(() async {
    SettingsService.reset();
    await AppDatabase.deleteAllData();
    AppDatabase.resetSwitchAnnouncementForTesting();
    DatabaseManager.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Makes [names] active one after another: the first now, each next one
  /// as the database before it announces itself. Returns the names in the
  /// order they were announced.
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

  // A regression guard for the loop: the single retry before X-6 passes it
  // too. The every-pass case below is the pin.
  test('a switch in each of the first two passes: the third publishes over '
      'the database opened last, its reset registered', () async {
    final announced = switchThrough(['two', 'three']);

    final settings = await SettingsService.getInstance();

    expect(announced, ['two', 'three']);
    expect(identical(await SettingsService.getInstance(), settings), isTrue);
    await settings.setFolderSwipeEnabled(false);
    final three = await AppDatabase.openInstanceOf('three')!;
    expect(
      await three.userSettingsDao.getValue(SettingsKeys.folderSwipeEnabled),
      'false',
    );
    DatabaseLifecycle.notifyDatabaseSwitching();
    expect(identical(await SettingsService.getInstance(), settings), isFalse);
  });

  test('a switch in every pass: it gives up with a StateError and publishes '
      'nothing over a database that is already being left', () async {
    final announced = switchThrough(['two', 'three', 'four']);

    await expectLater(SettingsService.getInstance(), throwsStateError);

    expect(announced, ['two', 'three', 'four']);
    expect(DatabaseLifecycle.registeredHandlerCount, 0);
    SettingsService.reset();
    final settings = await SettingsService.getInstance();
    await settings.setFolderSwipeEnabled(false);
    final four = await AppDatabase.openInstanceOf('four')!;
    expect(
      await four.userSettingsDao.getValue(SettingsKeys.folderSwipeEnabled),
      'false',
    );
  });
}
