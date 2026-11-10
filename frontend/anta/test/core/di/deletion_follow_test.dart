import 'package:flutter_test/flutter_test.dart';

import 'package:anta/core/di/injection.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../services/pairing_support.dart';
import '../../support/fake_sync_gateway.dart';

/// Start-up's half of resuming a deletion (review G3): where sync runs, the
/// space service follows the account stream from launch, and a reset of the
/// dependencies ends that following.
void main() {
  late FakeAuthService auth;

  /// How many times the service read the install's deletion records — once
  /// per account it was told of.
  late int recordReads;

  setUp(() {
    recordReads = 0;
  });

  tearDown(() async {
    await getIt.reset();
    await auth.dispose();
  });

  /// Registers what [followAccountsForDeletions] reads, the identity
  /// [available] or not, the space service through the app's own
  /// registration — so the release on a reset is the app's (review K8). The
  /// identity is left out of the reset, so a test can still speak on its
  /// stream afterwards.
  void register({required bool available}) {
    auth = FakeAuthService(available: available);
    getIt.registerSingleton<AuthService>(auth);
    getIt.registerSingleton<SyncGateway>(FakeSyncGateway());
    registerSyncSpaceService(
      databases: () {
        recordReads++;
        return Future<DatabaseManager>.error(StateError('no records here'));
      },
    );
  }

  test('where sync runs, start-up follows the account stream', () async {
    register(available: true);

    followAccountsForDeletions();
    auth.emitAuth(userA);
    await pumpEventQueue();

    expect(recordReads, 1);
  });

  test('where it does not, nothing follows it', () async {
    register(available: false);

    followAccountsForDeletions();
    auth.emitAuth(userA);
    await pumpEventQueue();

    expect(recordReads, 0);
  });

  test('a reset of the dependencies ends the following', () async {
    register(available: true);
    followAccountsForDeletions();
    auth.emitAuth(userA);
    await pumpEventQueue();

    await resetDependencies();
    auth.emitAuth(userB);
    await pumpEventQueue();

    expect(recordReads, 1);
  });
}
