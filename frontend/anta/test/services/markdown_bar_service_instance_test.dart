import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/markdown_bar_profile.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/markdown_bar_service.dart';

import '../database/support/db_test_support.dart';

/// `MarkdownBarService.getInstance` publishes only a bar whose profiles are
/// loaded, never one over a database a switch overtook or one a reset
/// overtook — the `SettingsService` shape, with `CounterService`'s reset
/// counter. The switches are staged as `settings_service_open_test.dart`
/// stages them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The restore case opens an in-memory database beside the file-backed one.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const profilesKey = 'markdown_bar_profiles';
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_markdown_bar_open');
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
    MarkdownBarService.reset();
  });

  tearDownAll(() async {
    MarkdownBarService.reset();
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

  Future<List<String>> profileNamesIn(String database) async {
    final db = await AppDatabase.openInstanceOf(database)!;
    final raw = await db.userSettingsDao.getValue(profilesKey);
    if (raw == null) return const [];
    return [for (final p in MarkdownBarProfile.decodeList(raw)) p.name];
  }

  test('a caller that arrives during the open gets the profiles loaded in the '
      'turn it is handed out', () async {
    final first = MarkdownBarService.getInstance();
    final second = await MarkdownBarService.getInstance().then((service) {
      expect(service.profiles, isNotEmpty);
      expect(service.activeProfile.id, MarkdownBarProfile.defaultProfileId);
      return service;
    });

    expect(second, same(await first));
  });

  test('a switch during the open: the bar published is over the database '
      'switched to last, its reset registered', () async {
    final announced = switchThrough(['two', 'three']);

    final service = await MarkdownBarService.getInstance();

    expect(announced, ['two', 'three']);
    expect(await MarkdownBarService.getInstance(), same(service));
    await service.addProfile('Switched');
    expect(await profileNamesIn('three'), contains('Switched'));
    DatabaseLifecycle.notifyDatabaseSwitching();
    expect(await MarkdownBarService.getInstance(), isNot(same(service)));
  });

  test('a reset during the open: the open hands out the bar every later '
      'caller gets, whole, and the next reset gives a new one', () async {
    final opening = MarkdownBarService.getInstance();
    MarkdownBarService.reset();

    final service = await opening;
    await service.addProfile('Kept');

    expect(await MarkdownBarService.getInstance(), same(service));
    MarkdownBarService.reset();
    final next = await MarkdownBarService.getInstance();
    expect(next, isNot(same(service)));
    expect([for (final p in next.profiles) p.name], contains('Kept'));
  });

  test('a reset after a restore lands mid-load: the bar published reads the '
      'restored profiles, never the ones read before it', () async {
    final hook = _ActiveProfileReadHook();
    final db = await openTestDatabase(interceptor: hook);
    addTearDown(db.close);
    // A whole load first, so the open below writes nothing of its own.
    final before = await MarkdownBarService.forTesting(db);
    final restored = [
      ...before.profiles,
      before.profiles.first.copyWith(
        id: 'restored',
        name: 'Restored',
        isDefault: false,
      ),
    ];
    MarkdownBarService.reset();
    // As `BackupService` does: the restored rows are written, then the bar
    // is reset — here once the open has read the profiles from before.
    hook.onRead = () {
      unawaited(
        db.userSettingsDao.setValue(
          profilesKey,
          MarkdownBarProfile.encodeList(restored),
        ),
      );
      MarkdownBarService.reset();
    };

    final service = await MarkdownBarService.forTesting(db);

    expect(hook.onRead, isNull);
    expect([for (final p in service.profiles) p.name], contains('Restored'));
    expect(await MarkdownBarService.forTesting(db), same(service));
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

      await expectLater(MarkdownBarService.getInstance(), throwsA(anything));

      messenger.setMockMethodCallHandler(
        pathProvider,
        (_) async => tempDir.path,
      );
      final service = await MarkdownBarService.getInstance();
      await service.addProfile('Reopened');
      expect(await profileNamesIn('broken'), contains('Reopened'));
    },
  );
}

/// Runs [onRead] once, right after the bar's load has read the active
/// profile — past its profiles read, before the open publishes.
class _ActiveProfileReadHook extends QueryInterceptor {
  void Function()? onRead;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    if (args.contains('active_markdown_bar')) {
      final hook = onRead;
      onRead = null;
      hook?.call();
    }
    return rows;
  }
}
