import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_status_service.dart';

import '../../database/support/db_test_support.dart';

const _accountA = AppUser(uid: 'uid-a');
const _accountB = AppUser(uid: 'uid-b');

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late SyncStatusService service;

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    service = SyncStatusService.forTesting(
      db,
      SyncBindingService.forTesting(db, settings),
    );
  });

  tearDown(() async {
    SyncStatusService.reset();
    SyncBindingService.reset();
    SettingsService.reset();
    await db.close();
  });

  const binding = SyncBinding(
    spaceId: 'space-1',
    ownerUid: 'uid-a',
    accountUid: 'uid-a',
  );

  test('a fresh database reads as the empty status', () async {
    expect(await service.read(user: _accountA), SyncStatus.empty);
  });

  test('another account on a bound database pauses sync', () async {
    await settings.setSyncBinding(binding);

    final status = await service.read(user: _accountB);

    expect(status.pause, SyncPause.accountMismatch);
    expect(status.binding, binding);
  });

  test('the binding account runs unpaused', () async {
    await settings.setSyncBinding(binding);

    expect((await service.read(user: _accountA)).pause, SyncPause.none);
  });

  test('signed out on a bound database does not pause', () async {
    await settings.setSyncBinding(binding);

    expect((await service.read()).pause, SyncPause.none);
  });

  test('an unbound database never pauses', () async {
    expect((await service.read(user: _accountB)).pause, SyncPause.none);
  });

  test('the pending count follows the outbox', () async {
    await db.folderDao.createFolder(name: 'One');
    await db.folderDao.createFolder(name: 'Two');
    expect((await service.read()).pendingCount, 2);

    await db.syncOutboxDao.clear();
    expect((await service.read()).pendingCount, 0);
  });

  test('a fresh clock is not ahead and has clamped nothing', () async {
    final status = await service.read(user: _accountA);

    expect(status.clockAhead, Duration.zero);
    expect(status.clampedRemotes, 0);
    expect(status.lastPushAt, isNull);
  });
}
