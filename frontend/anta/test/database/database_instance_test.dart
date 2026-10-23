import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';

/// Guards [AppDatabase.getInstance]'s memoised open: callers share one open,
/// none is handed an instance before its clock is seeded, and a switch waits
/// for the open in flight instead of closing it under its seed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_db_instance');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance(databaseName: 'second')).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('concurrent first callers share one seeded instance', () async {
    final opened = await Future.wait([
      AppDatabase.getInstance(databaseName: 'first'),
      AppDatabase.getInstance(databaseName: 'first'),
    ]);

    expect(identical(opened[0], opened[1]), isTrue);
    expect(await opened[0].syncDao.getValue(SyncDao.keyLastHlc), isNotNull);
  });

  test('a switch waits for the open in flight, then opens anew', () async {
    final first = AppDatabase.getInstance(databaseName: 'first');
    final second = AppDatabase.getInstance(databaseName: 'second');

    final (a, b) = (await first, await second);

    expect(identical(a, b), isFalse);
    expect(
      identical(await AppDatabase.getInstance(databaseName: 'second'), b),
      isTrue,
    );
    expect(await b.syncDao.getValue(SyncDao.keyLastHlc), isNotNull);
  });

  test(
    'a switch during an open hands the instance out, then closes it',
    () async {
      AppDatabase? handedOut;
      final heldAtNotice = <bool>[];
      var listening = true;
      void onSwitch() {
        heldAtNotice.add(handedOut != null);
        if (listening) DatabaseLifecycle.registerResetHandler(onSwitch);
      }

      DatabaseLifecycle.registerResetHandler(onSwitch);
      // 'third' is still opening when 'fourth' asks for the switch.
      final first = AppDatabase.getInstance(databaseName: 'third')
        ..then((db) => handedOut = db);
      final second = AppDatabase.getInstance(databaseName: 'fourth');
      final (a, b) = (await first, await second);
      listening = false;

      // The notice leaving 'second', then the one leaving 'third', which came
      // only after 'third' had been handed to its caller.
      expect(heldAtNotice, [false, true]);
      expect(identical(a, b), isFalse);
      await expectLater(a.customSelect('SELECT 1').get(), throwsA(anything));
      expect(await b.syncDao.getValue(SyncDao.keyLastHlc), isNotNull);
    },
  );

  test('a failed open clears the memo, so the next call opens anew', () async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // A documents directory that is a file: the device id cannot be written.
    final blocked = File('${tempDir.path}/blocked')..writeAsStringSync('');
    messenger.setMockMethodCallHandler(pathProvider, (_) async => blocked.path);

    await expectLater(
      AppDatabase.getInstance(databaseName: 'fifth'),
      throwsA(anything),
    );

    messenger.setMockMethodCallHandler(pathProvider, (_) async => tempDir.path);
    final reopened = await AppDatabase.getInstance(databaseName: 'fifth');
    expect(await reopened.syncDao.getValue(SyncDao.keyLastHlc), isNotNull);
  });
}
