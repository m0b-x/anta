import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/app_version.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_registry.dart';
import 'package:anta/services/sync/sync_space_service.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_status_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../../database/support/db_test_support.dart';
import '../../support/fake_sync_gateway.dart';

const _uid = 'uid-1';

Matcher _fails(SyncBindFailure failure, {String? holder}) =>
    isA<SyncSpaceException>()
        .having((e) => e.failure, 'failure', failure)
        .having((e) => e.holderDatabase, 'holderDatabase', holder);

/// A registry that sees [holder] hold every space, though nothing is stored —
/// a claim landing between the service's own check and the bind's.
class _HeldRegistry extends SyncSpaceRegistry {
  final String holder;

  _HeldRegistry(super.prefs, this.holder)
    : super(databaseExists: (_) async => true);

  @override
  Future<String?> holderOf(SyncSpaceRef space, {String? except}) async =>
      holder;
}

/// The bind flow below the Sharing page (record §2 D1, D2, D5, D6; §3.6),
/// over an in-memory database bound through the real binding service, the
/// fake gateway, and the real `DatabaseManager` over a temporary directory —
/// which is what the install registry checks a holder's file against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;
  late AppDatabase db;
  late SettingsService settings;
  late SyncBindingService binding;
  late FakeSyncGateway gateway;
  late SyncSpaceService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_space_service');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('training');
    for (final name in ['training', 'errands']) {
      await manager.createDatabase(name);
    }
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    binding = SyncBindingService.detached(
      db,
      settings,
      registry: manager.spaceRegistry,
      databaseName: 'training',
    );
    gateway = FakeSyncGateway();
    service = SyncSpaceService(
      gateway: gateway,
      database: () async => db,
      binding: () async => binding,
      databases: () async => manager,
    );
  });

  tearDown(() async {
    SettingsService.reset();
    await (await SharedPreferences.getInstance()).remove(
      SettingsKeys.syncBoundSpaces,
    );
    await db.close();
  });

  Future<SyncSpaceInfo> createSpace(String name, {String owner = _uid}) =>
      gateway.createSpace(
        ownerUid: owner,
        name: name,
        deviceId: 'other-device',
        schema: DatabaseSchema.currentVersion,
      );

  /// Gives [space] a `lastWriteAt`, as any push does.
  Future<void> touch(SyncSpaceInfo space) => gateway.pushBatch(
    space.ref,
    const [],
    pushedBy: 'other-device',
    schema: DatabaseSchema.currentVersion,
  );

  Future<void> seedBuiltInCategories() {
    final now = DateTime.now();
    return db.calendarCategoryDao.seedMissing([
      for (final (i, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategoriesCompanion(
          id: Value(seed.id),
          name: Value(CalendarCategories.builtInSeedName(seed.kind)),
          colorValue: Value(seed.colorValue),
          iconKey: Value(seed.iconKey),
          sortOrder: Value(i),
          isBuiltIn: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
    ]);
  }

  group('"Sync this database" (D1 A)', () {
    test('with no space yet creates the account\'s first space, named after '
        'this database, and binds it in the tap', () async {
      final start = await service.start(accountUid: _uid);

      final spaces = await gateway.listSpaces(_uid);
      expect(spaces, hasLength(1));
      final created = spaces.single;
      expect(start, SyncBindStartBound(created.ref));
      expect(created.name, 'training');
      expect(created.createdBy, db.deviceId);
      expect(created.schema, DatabaseSchema.currentVersion);
      final bound = await binding.read();
      expect(bound!.spaceId, created.ref.spaceId);
      expect(bound.ownerUid, _uid);
      expect(bound.accountUid, _uid);
      expect(await manager.spaceRegistry.holderOf(created.ref), 'training');
    });

    test('the default database\'s first space takes the app\'s name, not '
        'its file name (review BA-L2)', () async {
      await manager.setActiveDatabaseName('gym_notes');
      addTearDown(() => manager.setActiveDatabaseName('training'));

      await service.start(accountUid: _uid);

      expect((await gateway.listSpaces(_uid)).single.name, kAppName);
    });

    test('a restore in flight creates no space for an upload', () async {
      await SyncSuspension.run(() async {
        await expectLater(
          service.createAndBind(accountUid: _uid),
          throwsA(_fails(SyncBindFailure.suspended)),
        );
      });
      expect(await gateway.listSpaces(_uid), isEmpty);
    });

    test('a database holding only the built-in categories binds the one '
        'space without the picker (D2: an empty database skips it)', () async {
      await seedBuiltInCategories();
      final space = await createSpace('Phone');

      final start = await service.start(accountUid: _uid);

      expect(start, SyncBindStartBound(space.ref));
      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect(await gateway.listSpaces(_uid), hasLength(1), reason: 'none made');
    });

    test(
      'a database holding data gets the picker, even over one space',
      () async {
        await db.folderDao.createFolder(name: 'Errands');
        final space = await createSpace('Phone');

        final start = await service.start(accountUid: _uid);

        expect(start, SyncBindStartPick(spaces: [space], holdsData: true));
        expect(await binding.read(), isNull);
      },
    );

    test('an empty database over two spaces gets the picker, the most '
        'recently written first', () async {
      final old = await createSpace('Old');
      final unwritten = await createSpace('Fresh');
      final recent = await createSpace('Recent');
      await touch(old);
      await touch(recent);

      final start = await service.start(accountUid: _uid) as SyncBindStartPick;

      expect(start.holdsData, isFalse);
      expect(start.spaces.map((space) => space.ref), [
        recent.ref,
        old.ref,
        unwritten.ref,
      ]);
    });

    test('the one space held by another database of this install gets the '
        'picker, which names the holder', () async {
      final space = await createSpace('Phone');
      await manager.spaceRegistry.claim(space.ref, 'errands');

      final start = await service.start(accountUid: _uid);

      expect(
        start,
        SyncBindStartPick(
          spaces: [space],
          holdsData: false,
          heldBy: {space.ref: 'errands'},
        ),
      );
      expect(await binding.read(), isNull);
    });

    test('another account\'s spaces are not this account\'s', () async {
      await createSpace('Partner', owner: 'uid-2');

      final start = await service.start(accountUid: _uid);

      expect(start, isA<SyncBindStartBound>());
      expect(await gateway.listSpaces(_uid), hasLength(1));
    });

    test('a bound database is refused before anything is created', () async {
      await service.start(accountUid: _uid);

      await expectLater(
        service.start(accountUid: _uid),
        throwsA(_fails(SyncBindFailure.alreadyBound)),
      );
      expect(await gateway.listSpaces(_uid), hasLength(1));
    });

    test('a restore in flight is refused before anything is created', () async {
      await SyncSuspension.run(() async {
        await expectLater(
          service.start(accountUid: _uid),
          throwsA(_fails(SyncBindFailure.suspended)),
        );
      });
      expect(await gateway.listSpaces(_uid), isEmpty);
    });

    for (final (gatewayFailure, failure) in [
      (SyncGatewayFailure.offline, SyncBindFailure.offline),
      (SyncGatewayFailure.quotaExhausted, SyncBindFailure.quotaExhausted),
      (SyncGatewayFailure.permissionDenied, SyncBindFailure.permissionDenied),
      (SyncGatewayFailure.unknown, SyncBindFailure.unknown),
    ]) {
      test('a gateway answering ${gatewayFailure.name} fails as '
          '${failure.name}, unbound', () async {
        gateway.failNextWith(gatewayFailure);

        await expectLater(
          service.start(accountUid: _uid),
          throwsA(_fails(failure)),
        );
        expect(await binding.read(), isNull);
      });
    }
  });

  group('does this database hold anything a person made', () {
    test('a fresh database does not', () async {
      expect(await service.databaseHoldsData(), isFalse);
    });

    test('the seeded built-in categories do not', () async {
      await seedBuiltInCategories();
      expect(await service.databaseHoldsData(), isFalse);
    });

    test('a category of the user\'s own does', () async {
      final now = DateTime.now();
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: 'custom-1',
          name: 'Physio',
          colorValue: 0xFF00AA00,
          iconKey: 'healing',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(await service.databaseHoldsData(), isTrue);
    });

    test('a folder does; once deleted, its tombstone does not', () async {
      final folder = await db.folderDao.createFolder(name: 'Errands');
      expect(await service.databaseHoldsData(), isTrue);

      await db.folderDao.softDeleteFolder(folder.id);
      expect(await service.databaseHoldsData(), isFalse);
    });

    /// One row in [table] with every required column filled by its type.
    Future<void> insertRow(String table) async {
      final names = <String>[];
      final values = <Variable<Object>>[];
      for (final column
          in await db.customSelect('PRAGMA table_info($table)').get()) {
        final required =
            column.read<int>('notnull') == 1 &&
            column.readNullable<String>('dflt_value') == null;
        if (!required && column.read<int>('pk') == 0) continue;
        final type = column.read<String>('type').toUpperCase();
        names.add(column.read<String>('name'));
        values.add(
          type.contains('INT')
              ? Variable<int>(0)
              : type.contains('REAL')
              ? Variable<double>(0)
              : Variable<String>('row-1'),
        );
      }
      await db.customInsert(
        'INSERT INTO $table (${names.join(', ')}) '
        'VALUES (${List.filled(names.length, '?').join(', ')})',
        variables: values,
      );
    }

    for (final synced in syncedTables) {
      if (synced.travelsWithParent) continue;
      test(
        'a live row of ${synced.name} does; its tombstone does not',
        () async {
          await insertRow(synced.name);
          expect(await service.databaseHoldsData(), isTrue);

          await db.customUpdate('UPDATE ${synced.name} SET is_deleted = 1');
          expect(await service.databaseHoldsData(), isFalse);
        },
      );
    }
  });

  group('the space name rule', () {
    test('is trimmed before the gateway sees it', () async {
      final created = await service.createAndBind(
        accountUid: _uid,
        name: '  Tablet  ',
      );
      expect(created.name, 'Tablet');
    });

    test('defaults to this database\'s name', () async {
      final created = await service.createAndBind(accountUid: _uid);
      expect(created.name, 'training');
    });

    test('takes 100 code points even when they are 200 UTF-16 units', () async {
      final name = '💪' * SyncSpaceService.maxSpaceNameLength;
      expect(name.length, 200);

      final created = await service.createAndBind(accountUid: _uid, name: name);
      expect(created.name, name);
    });

    for (final (label, name) in [
      ('101 code points', '💪' * (SyncSpaceService.maxSpaceNameLength + 1)),
      ('only spaces', '   '),
    ]) {
      test('refuses $label before the gateway', () async {
        await expectLater(
          service.createAndBind(accountUid: _uid, name: name),
          throwsA(_fails(SyncBindFailure.invalidSpaceName)),
        );
        expect(await gateway.listSpaces(_uid), isEmpty);
        expect(await binding.read(), isNull);
      });
    }
  });

  group('merge into a space (D2 A)', () {
    test('binds this database to it and claims it', () async {
      await db.folderDao.createFolder(name: 'Errands');
      final space = await createSpace('Phone');

      await service.bindExisting(space.ref, accountUid: _uid);

      expect((await binding.read())!.spaceId, space.ref.spaceId);
      expect(
        await db.syncDao.getValue(SyncDao.keyBindMergePending),
        '1',
        reason: 'the initial merge under the floor follows',
      );
      expect(await manager.spaceRegistry.holderOf(space.ref), 'training');
    });

    test('is refused, naming the holder, when another database of this '
        'install holds the space', () async {
      final space = await createSpace('Phone');
      await manager.spaceRegistry.claim(space.ref, 'errands');

      await expectLater(
        service.bindExisting(space.ref, accountUid: _uid),
        throwsA(
          _fails(SyncBindFailure.spaceHeldByAnotherDatabase, holder: 'errands'),
        ),
      );
      expect(await binding.read(), isNull);
    });

    test('binds over a holder whose database file is gone', () async {
      final space = await createSpace('Phone');
      await manager.spaceRegistry.claim(space.ref, 'deleted-elsewhere');

      await service.bindExisting(space.ref, accountUid: _uid);

      expect(await manager.spaceRegistry.holderOf(space.ref), 'training');
    });

    test('a holder only the bind itself sees is refused as held, naming it '
        '(review BA-L4)', () async {
      final space = await createSpace('Phone');
      final held = SyncSpaceService(
        gateway: gateway,
        database: () async => db,
        binding: () async => SyncBindingService.detached(
          db,
          settings,
          registry: _HeldRegistry(
            await SharedPreferences.getInstance(),
            'errands',
          ),
          databaseName: 'training',
        ),
        databases: () async => manager,
      );

      await expectLater(
        held.bindExisting(space.ref, accountUid: _uid),
        throwsA(
          _fails(SyncBindFailure.spaceHeldByAnotherDatabase, holder: 'errands'),
        ),
      );
      expect(await binding.read(), isNull);
    });

    test('this database\'s own stale claim is never in its way', () async {
      final space = await createSpace('Phone');
      await manager.spaceRegistry.claim(space.ref, 'training');

      await service.bindExisting(space.ref, accountUid: _uid);

      expect((await binding.read())!.spaceId, space.ref.spaceId);
    });
  });

  group('stop syncing (D6 A)', () {
    test('unbinds, releases the claim and leaves the space', () async {
      await service.start(accountUid: _uid);

      await service.stopSyncing();

      expect(await binding.read(), isNull);
      expect(manager.spaceRegistry.claims(), isEmpty);
      expect(await gateway.listSpaces(_uid), hasLength(1));
    });

    test('lets another database bind the space it left', () async {
      final space = await createSpace('Phone');
      await service.bindExisting(space.ref, accountUid: _uid);
      await service.stopSyncing();

      expect(await manager.spaceRegistry.holderOf(space.ref), isNull);
    });

    test('on an unbound database writes nothing, the floor included', () async {
      await db.syncDao.setValue(SyncDao.keyBindFloor, 'restored-floor');

      await service.stopSyncing();

      expect(await db.syncDao.getValue(SyncDao.keyBindFloor), 'restored-floor');
    });
  });

  group('D5 A: the binding outlives the account', () {
    test('signed out it stays, paused as signed out; another account sees '
        'the mismatch; stopping works from either', () async {
      await service.start(accountUid: _uid);
      final status = SyncStatusService.detached(db, binding);

      final signedOut = await status.read();
      expect(signedOut.binding, isNotNull);
      expect(signedOut.pause, SyncPause.signedOut);

      final partner = await status.read(user: const AppUser(uid: 'uid-2'));
      expect(partner.binding, isNotNull);
      expect(partner.pause, SyncPause.accountMismatch);

      await service.stopSyncing();
      final after = await status.read(user: const AppUser(uid: 'uid-2'));
      expect(after.binding, isNull);
      expect(after.pause, SyncPause.none);
    });
  });
}
