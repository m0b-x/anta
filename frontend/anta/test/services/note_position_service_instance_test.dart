import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/note_position_service.dart';

/// `NotePositionService.getInstance` publishes only a whole service, never
/// one over a database a switch overtook — the `SettingsService` shape. The
/// switches are staged as `settings_service_open_test.dart` stages them: the
/// database each pass opens announces itself, and the announcement makes the
/// next one active.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_note_position_open');
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
    NotePositionService.reset();
  });

  tearDownAll(() async {
    NotePositionService.reset();
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

  const position = NotePositionData(
    isPreviewMode: true,
    previewScrollProgress: 0.5,
    editorLineIndex: 7,
    editorColumnOffset: 2,
  );

  Future<String?> storedIn(String database, String noteId) async {
    final db = await AppDatabase.openInstanceOf(database)!;
    return db.userSettingsDao.getValue(
      '${SettingsKeys.notePositionPrefix}$noteId',
    );
  }

  test('a caller that arrives during the open can use the service in the '
      'turn it is handed out', () async {
    final first = NotePositionService.getInstance();
    // The save reads the database before its first await, so it is used
    // before the first caller's open could have finished.
    final second = await NotePositionService.getInstance().then(
      (service) => service.savePosition('a', position).then((_) => service),
    );

    expect(second, same(await first));
    expect(await storedIn('one', 'a'), isNotNull);
  });

  test('a switch during the open: the service published is over the '
      'database switched to last, its reset registered', () async {
    final announced = switchThrough(['two', 'three']);

    final service = await NotePositionService.getInstance();

    expect(announced, ['two', 'three']);
    expect(await NotePositionService.getInstance(), same(service));
    await service.savePosition('b', position);
    expect(await storedIn('three', 'b'), isNotNull);
    DatabaseLifecycle.notifyDatabaseSwitching();
    expect(await NotePositionService.getInstance(), isNot(same(service)));
  });

  test('a reset during the open: the open hands out a whole service, and '
      'the next reset gives a new one', () async {
    final opening = NotePositionService.getInstance();
    NotePositionService.reset();

    final service = await opening;
    await service.savePosition('c', position);

    expect(await NotePositionService.getInstance(), same(service));
    NotePositionService.reset();
    final next = await NotePositionService.getInstance();
    expect(next, isNot(same(service)));
    expect((await next.getPosition('c')).editorLineIndex, 7);
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

      await expectLater(NotePositionService.getInstance(), throwsA(anything));

      messenger.setMockMethodCallHandler(
        pathProvider,
        (_) async => tempDir.path,
      );
      final service = await NotePositionService.getInstance();
      await service.savePosition('d', position);
      expect(await storedIn('broken', 'd'), isNotNull);
    },
  );
}
