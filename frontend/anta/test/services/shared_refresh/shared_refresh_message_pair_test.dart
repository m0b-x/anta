import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../database/support/db_test_support.dart';
import '../../support/fake_sync_gateway.dart';
import '../pairing_support.dart';

/// A run a relay message started reads only for the pair it named: a
/// message for another database's pair ends the run before any read
/// (`docs/cloud-shared-freshness.md` §10, case B13).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
    SettingsService.reset();
    final settings = SettingsService.forTesting(db);
    GetIt.I
      ..registerSingleton<SyncGateway>(FakeSyncGateway())
      ..registerSingleton<AuthService>(FakeAuthService(user: userA));
    await settings.setSyncBinding(
      SyncBinding(
        spaceId: 'space-1',
        ownerUid: userA.uid,
        accountUid: userA.uid,
      ),
    );
    await settings.setPairingSettings(
      PairingSettings(pairId: 'pair-1', accountUid: userA.uid),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
    SettingsService.reset();
    await db.close();
  });

  test('the schedule\'s own check reads for the open database', () async {
    expect(
      await AppSharedRefreshRunSteps(SharedRefreshSlot.first).shares(),
      isTrue,
    );
  });

  test('a message for the open database\'s pair reads; one for another '
      'pair does not', () async {
    expect(
      await AppSharedRefreshRunSteps(null, pair: 'pair-1').shares(),
      isTrue,
    );
    expect(
      await AppSharedRefreshRunSteps(null, pair: 'pair-9').shares(),
      isFalse,
    );
  });
}
