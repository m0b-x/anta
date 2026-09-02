import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// Two things are being guarded here.
///
/// The first is the **launch race**: mounting the root page publishes an empty
/// stack, and if that write reached SQLite before restore read the stored
/// value, the app would erase the location it was about to reopen. Recording
/// stays sealed until `beginRecording`, and that seal is the feature's whole
/// safety margin.
///
/// The second is the **legacy migration**. Every existing install has the old
/// three-key location, and it has exactly one chance to become a stack.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late NavigationHistoryService history;

  const debounce = Duration(milliseconds: 10);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    history = NavigationHistoryService(writeDebounce: debounce);
  });

  tearDown(() async {
    history.dispose();
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Future<String?> storedRaw() =>
      db.userSettingsDao.getValue(SettingsKeys.lastLocationStack);

  group('the write seal', () {
    test('nothing is written before recording begins', () async {
      history.onStackChanged([
        const NavDestination(NavDestinationKind.calendar),
      ]);
      await settle();

      expect(await storedRaw(), isNull);
    });

    test('an explicit flush before recording begins is also a no-op', () async {
      history.onStackChanged(const []);
      await history.flush();

      expect(await storedRaw(), isNull);
    });

    test('beginRecording persists what the navigator already holds', () async {
      history.onStackChanged([
        const NavDestination(NavDestinationKind.calendar),
      ]);
      history.beginRecording();
      await settle();

      expect(await settings.getLastLocationStack(), [
        const NavDestination(NavDestinationKind.calendar),
      ]);
    });

    test('beginRecording is idempotent', () async {
      history.beginRecording();
      history.beginRecording();

      expect(history.isRecording, isTrue);
    });
  });

  group('writing', () {
    setUp(() => history.beginRecording());

    test('the debounce coalesces a burst into the final state', () async {
      final folder = NavDestination.folder(folderId: 'f1', title: 'Training');
      final note = NavDestination.note(noteId: 'n1', folderId: 'f1');

      history.onStackChanged([folder]);
      history.onStackChanged([folder, note]);
      history.onStackChanged([folder]);
      await settle();

      expect(await settings.getLastLocationStack(), [folder]);
    });

    test('flush writes immediately, which is what the pause hook relies on',
        () async {
      history.onStackChanged([
        const NavDestination(NavDestinationKind.databaseSettings),
      ]);
      await history.flush();

      expect(await settings.getLastLocationStack(), [
        const NavDestination(NavDestinationKind.databaseSettings),
      ]);
    });

    test('popping back to root persists an empty stack, not a deleted row',
        () async {
      history.onStackChanged([
        const NavDestination(NavDestinationKind.calendar),
      ]);
      await history.flush();

      history.onStackChanged(const []);
      await history.flush();

      expect(await storedRaw(), isNotNull);
      expect(await settings.getLastLocationStack(), isEmpty);
    });

    test('an unchanged stack is not rewritten', () async {
      final stack = [const NavDestination(NavDestinationKind.calendar)];

      history.onStackChanged(stack);
      await history.flush();
      final first = await storedRaw();

      history.onStackChanged(List.of(stack));
      await history.flush();

      expect(await storedRaw(), first);
    });

    test('rapid changes land in order, so the last one wins', () async {
      for (var i = 0; i < 12; i++) {
        history.onStackChanged([
          NavDestination.folder(folderId: 'f$i', title: 'Folder $i'),
        ]);
        unawaitedFlush(history);
      }
      await history.flush();
      await settle();

      expect(await settings.getLastLocationStack(), [
        NavDestination.folder(folderId: 'f11', title: 'Folder 11'),
      ]);
    });
  });

  group('database switch', () {
    test('the in-memory stack is dropped rather than written to the new db',
        () async {
      history.beginRecording();
      history.onStackChanged([
        NavDestination.folder(folderId: 'f1', title: 'Training'),
      ]);

      DatabaseLifecycle.notifyDatabaseSwitching();
      await settle();

      expect(history.stack, isEmpty);
    });

    test('it re-registers, so a second switch is handled too', () async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      history.beginRecording();
      history.onStackChanged([
        NavDestination.folder(folderId: 'f1', title: 'Training'),
      ]);

      DatabaseLifecycle.notifyDatabaseSwitching();

      expect(history.stack, isEmpty);
    });
  });

  group('legacy migration', () {
    Future<void> writeLegacy({
      required String folderId,
      String title = 'Training',
      String? noteId,
    }) async {
      await db.userSettingsDao.setValue(SettingsKeys.lastFolderId, folderId);
      await db.userSettingsDao.setValue(SettingsKeys.lastFolderTitle, title);
      if (noteId != null) {
        await db.userSettingsDao.setValue(SettingsKeys.lastNoteId, noteId);
      }
    }

    test('a folder-and-note location becomes a two-entry stack', () async {
      await writeLegacy(folderId: 'f1', noteId: 'n1');

      expect(await settings.getLastLocationStack(), [
        NavDestination.folder(folderId: 'f1', title: 'Training'),
        NavDestination.note(noteId: 'n1', folderId: 'f1'),
      ]);
    });

    test('a folder-only location becomes a one-entry stack', () async {
      await writeLegacy(folderId: 'f1');

      expect(await settings.getLastLocationStack(), [
        NavDestination.folder(folderId: 'f1', title: 'Training'),
      ]);
    });

    test('the legacy rows are deleted, so it cannot run twice', () async {
      await writeLegacy(folderId: 'f1', noteId: 'n1');
      await settings.getLastLocationStack();

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.lastFolderId),
        isNull,
      );
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.lastNoteId),
        isNull,
      );
    });

    test('a later empty stack is not mistaken for a never-migrated install',
        () async {
      await writeLegacy(folderId: 'f1');
      await settings.getLastLocationStack();
      await settings.saveLastLocationStack(const []);

      await writeLegacy(folderId: 'f2', title: 'Stale');

      expect(await settings.getLastLocationStack(), isEmpty);
    });

    test('an install with no legacy location migrates to an empty stack',
        () async {
      expect(await settings.getLastLocationStack(), isEmpty);
      expect(await storedRaw(), isNotNull);
    });
  });
}

void unawaitedFlush(NavigationHistoryService history) {
  history.flush();
}
