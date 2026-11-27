import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/database_manager.dart';

/// A switch that asks for a restart ([DatabaseManager.activateAtNextLaunch]):
/// the stored name moves, and the process keeps the database it has open.
///
/// Before it, the Databases page, an alarm of another database and
/// onboarding's restore wrote the active name itself, and the first
/// `AppDatabase.getInstance()` after the write — an alert firing, a resume's
/// reconcile — switched the whole app behind the restart dialog (settings
/// rework review, 2026-11-01). Each case is one process: the manager's memo
/// is dropped before it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const activeKey = 'active_database';

  late Directory tempDir;
  late SharedPreferences prefs;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_next_launch');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  setUp(() async {
    // Closes what the last case opened and empties the directory.
    await AppDatabase.deleteAllData();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    DatabaseManager.resetForTesting();
    manager = await DatabaseManager.getInstance();
    for (final name in ['gym_notes', 'work', 'travel']) {
      await manager.createDatabase(name);
    }
  });

  tearDownAll(() async {
    await AppDatabase.deleteAllData();
    DatabaseManager.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// What a new process reads: a manager built over the same preferences.
  Future<String> activeAtNextLaunch() async {
    DatabaseManager.resetForTesting();
    return (await DatabaseManager.getInstance()).getActiveDatabaseName();
  }

  test('the stored name moves and the process keeps its own; the next '
      'launch opens the new one', () async {
    await manager.activateAtNextLaunch('work');

    expect(prefs.getString(activeKey), 'work');
    expect(manager.getActiveDatabaseName(), 'gym_notes');
    expect(await activeAtNextLaunch(), 'work');
  });

  test('the open database stays open, whoever asks for it', () async {
    final open = await AppDatabase.getInstance();
    var resets = 0;
    void onSwitch() => resets++;
    DatabaseLifecycle.registerResetHandler(onSwitch);

    await manager.activateAtNextLaunch('work');
    final asked = await AppDatabase.getInstance();

    expect(identical(asked, open), isTrue);
    expect(resets, 0, reason: 'nothing was told to drop the open database');
    expect(AppDatabase.openInstanceOf('gym_notes'), isNotNull);
    expect(AppDatabase.openInstanceOf('work'), isNull);
    // Still usable: the connection was never closed under it.
    expect(await open.folderDao.getAllFolders(includeDeleted: true), isEmpty);
  });

  test('a switch made now still switches: only the wait holds the open '
      'database', () async {
    final open = await AppDatabase.getInstance();

    await manager.setActiveDatabaseName('work');
    final asked = await AppDatabase.getInstance();

    expect(identical(asked, open), isFalse);
    expect(AppDatabase.openInstanceOf('work'), isNotNull);
  });

  test('a name with no file is refused and nothing is stored', () async {
    await expectLater(
      manager.activateAtNextLaunch('renamed-away'),
      throwsStateError,
    );

    expect(prefs.getString(activeKey), isNull);
    expect(manager.getActiveDatabaseName(), 'gym_notes');
    expect(await activeAtNextLaunch(), 'gym_notes');
  });

  test('a second switch keeps the name the first one kept', () async {
    await manager.activateAtNextLaunch('work');
    await manager.activateAtNextLaunch('travel');

    expect(prefs.getString(activeKey), 'travel');
    expect(manager.getActiveDatabaseName(), 'gym_notes');
  });

  test('a switch made now ends the wait', () async {
    await manager.activateAtNextLaunch('work');
    await manager.setActiveDatabaseName('travel');

    expect(manager.getActiveDatabaseName(), 'travel');

    // And naming the waiting database itself is a switch like any other.
    await manager.activateAtNextLaunch('work');
    await manager.setActiveDatabaseName('work');

    expect(manager.getActiveDatabaseName(), 'work');
  });

  test('any other write of the stored name ends the wait', () async {
    await manager.activateAtNextLaunch('work');

    await prefs.setString(activeKey, 'travel');
    expect(manager.getActiveDatabaseName(), 'travel');

    await manager.activateAtNextLaunch('work');
    await prefs.remove(activeKey);
    expect(manager.getActiveDatabaseName(), 'gym_notes');
  });

  group('while a switch waits', () {
    test('renaming the database it waits for renames what is stored: the '
        'next launch must not open the old name and create it empty', () async {
      await manager.activateAtNextLaunch('work');

      await manager.renameDatabase('work', 'office');

      expect(prefs.getString(activeKey), 'office');
      expect(manager.getActiveDatabaseName(), 'gym_notes');
      expect(await activeAtNextLaunch(), 'office');
    });

    test('renaming the database this process keeps renames the kept '
        'name', () async {
      await manager.activateAtNextLaunch('work');

      await manager.renameDatabase('gym_notes', 'training');

      expect(manager.getActiveDatabaseName(), 'training');
      expect(prefs.getString(activeKey), 'work');
    });

    test('deleting the database it waits for goes back to the kept one, for '
        'this process and the next', () async {
      await manager.setActiveDatabaseName('travel');
      await manager.activateAtNextLaunch('work');

      await manager.deleteDatabase('work');

      expect(prefs.getString(activeKey), 'travel');
      expect(manager.getActiveDatabaseName(), 'travel');
      expect(await activeAtNextLaunch(), 'travel');
    });
  });

  test('deleting the database this process kept, while a switch waits, '
      'leaves the waiting one as the active name', () async {
    await manager.activateAtNextLaunch('work');

    await manager.deleteDatabase('gym_notes');

    expect(prefs.getString(activeKey), 'work');
    expect(manager.getActiveDatabaseName(), 'work');
  });

  group('renaming the open database', () {
    test('closes it first, tells the singletons, and says so: the caller '
        'asks for a restart', () async {
      final open = await AppDatabase.getInstance();
      await open.folderDao.createFolder(name: 'Kept');
      var resets = 0;
      void onSwitch() => resets++;
      DatabaseLifecycle.registerResetHandler(onSwitch);

      final wasOpen = await manager.renameDatabase('gym_notes', 'training');

      expect(wasOpen, isTrue);
      expect(resets, 1);
      expect(AppDatabase.openInstanceOf('gym_notes'), isNull);
      expect(await manager.databaseExists('gym_notes'), isFalse);
      expect(await manager.databaseExists('training'), isTrue);
      expect(prefs.getString(activeKey), 'training');

      // Whatever asks for the database before the exit opens the renamed
      // file, with everything it held.
      final reopened = await AppDatabase.getInstance();
      expect(AppDatabase.openInstanceOf('training'), isNotNull);
      final folders = await reopened.folderDao.getAllFolders(
        includeDeleted: false,
      );
      expect([for (final folder in folders) folder.name], ['Kept']);
    });

    // The close, the move and the names are one section no caller enters:
    // asked for during the close, a caller was handed the instance being
    // closed; asked for once the file had moved, it opened the old name —
    // an empty database SQLite created there, which took its writes while
    // the rename reported success (review of the database-safety slice,
    // items 1 and 4).
    group('a caller that asks for the database', () {
      tearDown(() {
        AppDatabase.debugGateTaken = null;
        DatabaseManager.debugRenameStep = null;
      });

      Future<void> renameAsking(
        void Function(void Function() ask) install,
      ) async {
        final open = await AppDatabase.getInstance();
        await open.folderDao.createFolder(name: 'Kept');
        Future<AppDatabase>? asked;
        install(() => asked ??= AppDatabase.getInstance());

        final wasOpen = await manager.renameDatabase('gym_notes', 'training');

        expect(wasOpen, isTrue);
        expect(asked, isNotNull, reason: 'the caller was asked for');
        final db = await asked!;
        // Never the closed instance: it answers, with the renamed rows.
        final folders = await db.folderDao.getAllFolders(includeDeleted: true);
        expect([for (final folder in folders) folder.name], ['Kept']);
        expect(identical(await AppDatabase.getInstance(), db), isTrue);
        expect(AppDatabase.openInstanceOf('training'), isNotNull);
        final dir = Directory(p.dirname(await manager.getDatabasePath('x')));
        expect(
          [
            for (final entity in dir.listSync())
              if (p.basename(entity.path).startsWith('gym_notes.db'))
                p.basename(entity.path),
          ],
          isEmpty,
          reason: 'nothing was created under the old name',
        );
        expect([
          for (final info in await manager.listDatabases()) info.name,
        ], unorderedEquals(['training', 'work', 'travel']));
      }

      test('before the close waits, then opens the renamed database', () {
        return renameAsking((ask) {
          AppDatabase.debugGateTaken = () async {
            ask();
          };
        });
      });

      test('during the close waits, then opens the renamed database', () {
        return renameAsking((ask) {
          // The singletons are told while the instance is still the memo's.
          DatabaseLifecycle.registerResetHandler(ask);
        });
      });

      for (final step in RenameStep.values) {
        test('at the rename\'s ${step.name} step waits, then opens the '
            'renamed database', () async {
          Future<AppDatabase>? openedMeanwhile;
          await renameAsking((ask) {
            DatabaseManager.debugRenameStep = (at) async {
              if (at != step) return;
              ask();
              // A turn of the event loop: a caller the gate did not hold
              // would be in the memo by its end.
              await Future<void>.delayed(Duration.zero);
              openedMeanwhile =
                  AppDatabase.openInstanceOf('gym_notes') ??
                  AppDatabase.openInstanceOf('training');
            };
          });
          // The one thing that tells the gate at the last step: the names
          // have moved by then, so a caller let through would open the
          // renamed file all the same (third review, R4).
          expect(
            openedMeanwhile,
            isNull,
            reason: 'the caller was still waiting while the section ran',
          );
        });
      }
    });

    test('a .db that refuses to move changes no name and opens the database '
        'again under its old one', () async {
      final open = await AppDatabase.getInstance();
      await open.folderDao.createFolder(name: 'Kept');
      // A directory where the file must go: [DatabaseManager.databaseExists]
      // looks for a file, and a file is moved onto a directory nowhere.
      final target = await manager.getDatabasePath('training');
      Directory(target).createSync();

      await expectLater(
        manager.renameDatabase('gym_notes', 'training'),
        throwsA(isA<FileSystemException>()),
      );

      expect(prefs.getString(activeKey), isNull);
      expect(manager.getActiveDatabaseName(), 'gym_notes');
      final reopened = AppDatabase.openInstanceOf('gym_notes');
      expect(reopened, isNotNull, reason: 'not left on a closed handle');
      final db = await reopened!;
      final folders = await db.folderDao.getAllFolders(includeDeleted: true);
      expect([for (final folder in folders) folder.name], ['Kept']);
      Directory(target).deleteSync();
    });

    test('a failure once the .db has moved is logged: the call still says '
        'the database was closed, and every name follows', () async {
      await prefs.setStringList('share_notices_kept_in', ['gym_notes']);
      await AppDatabase.getInstance();
      final oldPath = await manager.getDatabasePath('gym_notes');
      final newPath = await manager.getDatabasePath('training');
      // A stray `-shm` beside the closed file, and a directory where its
      // twin must go: the `.db` moves, then the sidecar's move fails.
      DatabaseManager.debugRenameStep = (step) async {
        if (step != RenameStep.closed) return;
        File('$oldPath-shm').writeAsStringSync('stray');
        Directory('$newPath-shm').createSync();
      };
      addTearDown(() {
        DatabaseManager.debugRenameStep = null;
        Directory('$newPath-shm').deleteSync(recursive: true);
      });

      final wasOpen = await manager.renameDatabase('gym_notes', 'training');

      expect(wasOpen, isTrue);
      expect(File(newPath).existsSync(), isTrue);
      expect(prefs.getString(activeKey), 'training');
      expect(manager.getActiveDatabaseName(), 'training');
      expect(prefs.getStringList('share_notices_kept_in'), ['training']);
    });

    test('another database is renamed with nothing closed', () async {
      final open = await AppDatabase.getInstance();
      var resets = 0;
      void onSwitch() => resets++;
      DatabaseLifecycle.registerResetHandler(onSwitch);

      final wasOpen = await manager.renameDatabase('work', 'office');

      expect(wasOpen, isFalse);
      expect(resets, 0);
      expect(identical(await AppDatabase.getInstance(), open), isTrue);
    });
  });

  test('a rename carries the kept notices\' name: they are looked for by '
      'it, and the old one would be pruned as a database gone', () async {
    await prefs.setStringList('share_notices_kept_in', ['work', 'travel']);

    await manager.renameDatabase('work', 'office');

    expect(prefs.getStringList('share_notices_kept_in'), ['office', 'travel']);
  });

  test('with no switch waiting, a rename and a delete of the active '
      'database move the stored name as they always did', () async {
    await manager.setActiveDatabaseName('work');

    await manager.renameDatabase('work', 'office');
    expect(prefs.getString(activeKey), 'office');
    expect(manager.getActiveDatabaseName(), 'office');

    await manager.deleteDatabase('office');
    expect(prefs.getString(activeKey), 'gym_notes');
    expect(manager.getActiveDatabaseName(), 'gym_notes');
  });
}
