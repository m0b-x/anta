import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_registry.dart';

/// The install-wide registry of record §3.6: one database ↔ one space, a
/// space at most once per install, kept true across a claim, a release, a
/// delete and a rename, and blind to a holder whose file is gone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const gym = SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-gym');
  const home = SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-home');

  group('over the preferences', () {
    late SharedPreferences prefs;
    late Set<String> files;
    late SyncSpaceRegistry registry;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      files = {'training', 'errands', 'tablet'};
      registry = SyncSpaceRegistry(
        prefs,
        databaseExists: (name) async => files.contains(name),
      );
    });

    test('a claim names its holder, except to the holder itself', () async {
      await registry.claim(gym, 'training');

      expect(await registry.holderOf(gym), 'training');
      expect(await registry.holderOf(gym, except: 'training'), isNull);
      expect(await registry.holderOf(home), isNull);
    });

    test(
      'a database holds one space: a second claim replaces its first',
      () async {
        await registry.claim(gym, 'training');
        await registry.claim(home, 'training');

        expect(registry.claims(), [
          const SyncSpaceClaim(space: home, databaseName: 'training'),
        ]);
      },
    );

    test('a space is held once: a second database claiming it takes it '
        'over', () async {
      await registry.claim(gym, 'training');
      await registry.claim(gym, 'tablet');

      expect(registry.claims(), [
        const SyncSpaceClaim(space: gym, databaseName: 'tablet'),
      ]);
    });

    test('the same space id under another account is another space', () async {
      const partners = SyncSpaceRef(ownerUid: 'uid-2', spaceId: 'space-gym');
      await registry.claim(gym, 'training');

      expect(await registry.holderOf(partners), isNull);
    });

    test('a release drops only that database\'s claim', () async {
      await registry.claim(gym, 'training');
      await registry.claim(home, 'errands');

      await registry.release('training');

      expect(await registry.holderOf(gym), isNull);
      expect(await registry.holderOf(home), 'errands');
    });

    test('the last release removes the key', () async {
      await registry.claim(gym, 'training');
      await registry.release('training');

      expect(prefs.containsKey(SettingsKeys.syncBoundSpaces), isFalse);
    });

    test('a rename carries the claim to the new name', () async {
      await registry.claim(gym, 'training');
      await registry.claim(home, 'errands');

      await registry.rename('training', 'gym');

      expect(registry.claims(), [
        const SyncSpaceClaim(space: gym, databaseName: 'gym'),
        const SyncSpaceClaim(space: home, databaseName: 'errands'),
      ]);
    });

    test('a holder whose database file is gone is ignored', () async {
      await registry.claim(gym, 'training');
      files.remove('training');

      expect(await registry.holderOf(gym), isNull);
    });

    test(
      'unreadable stored claims read as none rather than throwing',
      () async {
        await prefs.setString(SettingsKeys.syncBoundSpaces, '{not json');
        expect(registry.claims(), isEmpty);

        await prefs.setString(
          SettingsKeys.syncBoundSpaces,
          '[{"spaceId":"space-gym"},{"spaceId":"space-home",'
          '"ownerUid":"uid-1","databaseName":"errands"}]',
        );
        expect(registry.claims(), [
          const SyncSpaceClaim(space: home, databaseName: 'errands'),
        ]);
      },
    );

    test('the key is not a per-database binding key', () {
      expect(
        SettingsKeys.syncBoundSpaces.startsWith(SettingsKeys.syncSpacePrefix),
        isFalse,
      );
    });

    group('pending deletions', () {
      const gymDeletion = SyncPendingDeletion(space: gym, spaceName: 'Gym');
      const homeDeletion = SyncPendingDeletion(space: home, spaceName: 'Home');

      test('are kept once per space, in the order they began, and '
          'cleared one by one', () async {
        await registry.addPendingDeletion(gymDeletion);
        await registry.addPendingDeletion(homeDeletion);
        await registry.addPendingDeletion(gymDeletion);

        expect(registry.pendingDeletions(), [gymDeletion, homeDeletion]);

        await registry.clearPendingDeletion(home);
        expect(registry.pendingDeletions(), [gymDeletion]);
        await registry.clearPendingDeletion(gym);
        expect(prefs.containsKey(SettingsKeys.syncPendingDeletions), isFalse);
      });

      test('recording a recorded space changes nothing', () async {
        await registry.addPendingDeletion(gymDeletion);
        await registry.addPendingDeletion(homeDeletion);
        final stored = prefs.getString(SettingsKeys.syncPendingDeletions);

        await registry.addPendingDeletion(
          const SyncPendingDeletion(space: gym, spaceName: 'Renamed'),
        );

        expect(prefs.getString(SettingsKeys.syncPendingDeletions), stored);
        expect(registry.pendingDeletions(), [gymDeletion, homeDeletion]);
      });

      test('a malformed entry is dropped, the rest survive', () async {
        await prefs.setString(SettingsKeys.syncPendingDeletions, '{not json');
        expect(registry.pendingDeletions(), isEmpty);

        await prefs.setString(
          SettingsKeys.syncPendingDeletions,
          '[{"spaceId":"space-gym","ownerUid":"uid-1"},7,{"spaceId":'
          '"space-home","ownerUid":"uid-1","spaceName":"Home"}]',
        );
        expect(registry.pendingDeletions(), [homeDeletion]);

        await registry.addPendingDeletion(gymDeletion);
        expect(registry.pendingDeletions(), [homeDeletion, gymDeletion]);
      });

      test('live apart from the claims: a release keeps them', () async {
        await registry.claim(gym, 'training');
        await registry.addPendingDeletion(gymDeletion);

        await registry.release('training');

        expect(registry.pendingDeletions(), [gymDeletion]);
        expect(registry.claims(), isEmpty);
      });

      test('the key is neither a binding key nor the claims\' key', () {
        expect(
          SettingsKeys.syncPendingDeletions.startsWith(
            SettingsKeys.syncSpacePrefix,
          ),
          isFalse,
        );
        expect(
          SettingsKeys.syncPendingDeletions,
          isNot(SettingsKeys.syncBoundSpaces),
        );
      });
    });
  });

  group('through DatabaseManager', () {
    late Directory tempDir;
    late DatabaseManager manager;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_space_registry');
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tempDir.path,
          );
      manager = await DatabaseManager.getInstance();
    });

    tearDownAll(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('deleting a database releases its claim', () async {
      await manager.createDatabase('doomed');
      await manager.spaceRegistry.claim(gym, 'doomed');

      await manager.deleteDatabase('doomed');

      expect(manager.spaceRegistry.claims(), isEmpty);
    });

    test('renaming a database carries its claim along', () async {
      await manager.createDatabase('before');
      await manager.spaceRegistry.claim(home, 'before');

      await manager.renameDatabase('before', 'after');

      expect(await manager.spaceRegistry.holderOf(home), 'after');
      await manager.deleteDatabase('after');
    });

    test('a claim whose file no longer exists holds nothing', () async {
      await manager.spaceRegistry.claim(gym, 'never-created');

      expect(await manager.spaceRegistry.holderOf(gym), isNull);
      await manager.spaceRegistry.release('never-created');
    });
  });
}
