import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/tag_catalog.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/tag_catalog_service.dart';

/// `TagCatalogService.getInstance` over the real database manager: one whole
/// instance for every first caller, and none published over a database a
/// switch is leaving — the `SettingsService` open's rules, which
/// `settings_service_open_test.dart` pins for that service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_tag_catalog_open');
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
    TagCatalogService.reset();
  });

  tearDownAll(() async {
    TagCatalogService.reset();
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

  test('two first callers get one whole instance', () async {
    final both = await Future.wait([
      TagCatalogService.getInstance(),
      TagCatalogService.getInstance(),
    ]);

    expect(identical(both.first, both.last), isTrue);
    expect(
      identical(await TagCatalogService.getInstance(), both.first),
      isTrue,
    );
    expect(both.first.tags, TagCatalog.all);
  });

  test('an open a reset left running and the open after it publish one '
      'instance between them', () async {
    final first = TagCatalogService.getInstance();
    TagCatalogService.reset();
    final second = TagCatalogService.getInstance();

    final (a, b) = (await first, await second);

    expect(identical(a, b), isTrue);
    expect(identical(await TagCatalogService.getInstance(), a), isTrue);
  });

  test('a switch in each of the first two passes: the third publishes, its '
      'reset registered', () async {
    final announced = switchThrough(['two', 'three']);

    final catalog = await TagCatalogService.getInstance();

    expect(announced, ['two', 'three']);
    expect(identical(await TagCatalogService.getInstance(), catalog), isTrue);
    DatabaseLifecycle.notifyDatabaseSwitching();
    expect(identical(await TagCatalogService.getInstance(), catalog), isFalse);
  });

  test('a switch in every pass: it gives up with a StateError and publishes '
      'nothing', () async {
    final announced = switchThrough(['two', 'three', 'four']);

    await expectLater(TagCatalogService.getInstance(), throwsStateError);

    expect(announced, ['two', 'three', 'four']);
    expect(DatabaseLifecycle.registeredHandlerCount, 0);
    TagCatalogService.reset();
    expect(await TagCatalogService.getInstance(), isA<TagCatalogService>());
  });
}
