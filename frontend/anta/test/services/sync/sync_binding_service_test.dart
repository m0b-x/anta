import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

import '../../database/support/db_test_support.dart';

const _bindingKeys = [
  SettingsKeys.syncSpaceId,
  SettingsKeys.syncSpaceOwnerUid,
  SettingsKeys.syncSpaceAccountUid,
  SettingsKeys.syncSpaceBoundAt,
];

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late SyncBindingService service;

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    service = SyncBindingService.forTesting(db, settings);
  });

  tearDown(() async {
    SyncBindingService.reset();
    SettingsService.reset();
    await db.close();
  });

  final binding = SyncBinding(
    spaceId: 'space-1',
    ownerUid: 'owner-1',
    accountUid: 'account-1',
    boundAt: DateTime.utc(2026, 10, 23, 9, 30),
  );

  test('a binding round-trips as one value', () async {
    await settings.setSyncBinding(binding);

    expect(await service.read(), binding);
  });

  test('a binding missing its account reads as unbound', () async {
    await settings.setSyncBinding(binding);
    await db.userSettingsDao.deleteValue(SettingsKeys.syncSpaceAccountUid);

    expect(await service.read(), isNull);
  });

  test(
    'unbind clears the binding and the queue and writes the floor',
    () async {
      await settings.setSyncBinding(binding);
      await db.folderDao.createFolder(name: 'First');
      final last = await db.folderDao.createFolder(name: 'Last');
      expect(await db.syncOutboxDao.count(), greaterThan(0));

      await service.unbind();

      for (final key in _bindingKeys) {
        expect(await db.userSettingsDao.getValue(key), isNull, reason: key);
      }
      expect(await service.read(), isNull);
      expect(await db.syncOutboxDao.count(), 0);
      expect(await service.bindFloor(), last.hlcTimestamp);
    },
  );

  test('the floor is the clock, never a held row stamp above it', () async {
    final row = await db.folderDao.createFolder(name: 'Row');
    // A merge stored a far-ahead remote stamp the clock held back.
    const held = 'ffffffffffff:0000:elsewhere';
    await db.customStatement(
      'UPDATE folders SET hlc_timestamp = ? WHERE id = ?',
      [held, row.id],
    );

    await service.writeBindFloor();

    final floor = await service.bindFloor();
    expect(floor, await db.syncDao.getValue(SyncDao.keyLastHlc));
    expect(floor!.compareTo(held), lessThan(0));
    final after = await db.folderDao.createFolder(name: 'After');
    expect(after.hlcTimestamp.compareTo(floor), greaterThan(0));
  });

  test('the floor stores the clock first, so it covers every mint', () async {
    await db.folderDao.createFolder(name: 'Row');
    final minted = db.newStamp().hlc;

    await service.writeBindFloor();

    expect(await service.bindFloor(), minted);
    expect(await db.syncDao.getValue(SyncDao.keyLastHlc), minted);
  });

  test('a later floor overwrites an earlier one', () async {
    await db.syncDao.setValue(SyncDao.keyBindFloor, 'ffffffffffff:0000:old');
    final row = await db.folderDao.createFolder(name: 'Row');

    await service.writeBindFloor();

    expect(await service.bindFloor(), row.hlcTimestamp);
  });

  test('an opened database with no rows writes its clock', () async {
    await db.seedClockFromStore();
    final clock = await db.syncDao.getValue(SyncDao.keyLastHlc);
    expect(clock, isNotNull);

    await service.writeBindFloor();

    expect(await service.bindFloor(), clock);
  });
}
