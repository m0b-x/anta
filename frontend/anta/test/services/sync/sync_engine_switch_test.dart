import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../support/fake_sync_gateway.dart';

/// The engine after a database switch (S4a review M5): with `autoStart` set
/// the switched-to database gets its own engine, built and started without
/// any page asking for it. Runs the real `getInstance` path, so the database
/// is the app's own singleton over a temporary directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_engine_switch');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<SyncGateway>(FakeSyncGateway());
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDownAll(() async {
    SyncEngine.autoStart = false;
    SyncEngine.reset();
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> switchTo(String name) async {
    await (await DatabaseManager.getInstance()).setActiveDatabaseName(name);
    await AppDatabase.getInstance();
  }

  test('with autoStart set, a switch builds and starts the new database\'s '
      'engine and stops the old one', () async {
    SyncEngine.autoStart = true;
    await switchTo('first');
    final first = await SyncEngine.getInstance();
    await until(() => first.isStarted);
    expect(first.isStarted, isTrue);

    await switchTo('second');
    await until(() => SyncEngine.instanceForTesting?.isStarted ?? false);

    final rebuilt = SyncEngine.instanceForTesting;
    expect(rebuilt, isNotNull);
    expect(identical(rebuilt, first), isFalse);
    expect(rebuilt!.isStarted, isTrue);
    expect(first.isStarted, isFalse);
  });

  test('without autoStart a switch builds no engine', () async {
    SyncEngine.autoStart = false;
    await switchTo('third');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(SyncEngine.instanceForTesting, isNull);
  });

  group('a reset landing while getInstance awaits (S4b-1 review L10)', () {
    /// Swaps the gateway for a factory that runs [onResolve] each time a
    /// build resolves it — once per pass, after the pass noted the lifecycle
    /// generation and before its first await: a reset arriving there is a
    /// switch landing in the middle of the build.
    void resolvingGateway(void Function() onResolve) {
      GetIt.I.unregister<SyncGateway>();
      GetIt.I.registerFactory<SyncGateway>(() {
        onResolve();
        return FakeSyncGateway();
      });
      addTearDown(() {
        GetIt.I.unregister<SyncGateway>();
        GetIt.I.registerSingleton<SyncGateway>(FakeSyncGateway());
      });
    }

    setUp(() async {
      SyncEngine.autoStart = false;
      await switchTo('fourth');
      SyncEngine.reset();
    });

    test('one reset makes the build start over, so what it registers was '
        'read after the reset', () async {
      var passes = 0;
      resolvingGateway(() {
        if (passes++ == 0) DatabaseLifecycle.notifyDatabaseSwitching();
      });

      final engine = await SyncEngine.getInstance();

      expect(passes, 2, reason: 'the first pass was overtaken and redone');
      expect(SyncEngine.instanceForTesting, same(engine));
    });

    test('a reset in the retry too fails the build, registering '
        'nothing', () async {
      var passes = 0;
      resolvingGateway(() {
        passes++;
        DatabaseLifecycle.notifyDatabaseSwitching();
      });

      await expectLater(SyncEngine.getInstance(), throwsStateError);

      expect(passes, 2);
      expect(SyncEngine.instanceForTesting, isNull);
    });
  });
}
