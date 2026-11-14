import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/core/di/injection.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';

import '../../database/support/db_test_support.dart';
import '../../services/pairing_support.dart';

/// Share surfaces record §16.9 B3: the census also says whether a pair is
/// stored, so start-up's wiring forgets it on every write of the pairing —
/// on the database opened after a switch too, with nothing re-wired.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Each case opens two in-memory databases, as a switch does.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase first;
  late AppDatabase second;
  late FolderRepository folders;

  setUp(() async {
    first = await openTestDatabase();
    second = await openTestDatabase();
    folders = FolderRepository(database: first);
    GetIt.I.registerSingleton<FolderRepository>(folders);
  });

  tearDown(() async {
    await resetDependencies();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await first.close();
    await second.close();
  });

  /// The pairing service over [db], with a pair stored.
  Future<PairingService> pairedOver(AppDatabase db) async {
    final settings = SettingsService.forTesting(db);
    await settings.setPairingSettings(
      const PairingSettings(pairId: 'pair-1', accountUid: 'me'),
    );
    return PairingService.forTesting(
      auth: FakeAuthService(user: const AppUser(uid: 'me')),
      gateway: FakePairingGateway(),
      settings: settings,
    );
  }

  test(
    'a pairing write forgets the census — the one of the database open '
    'after a switch too — and a reset of the dependencies stops it',
    () async {
      forgetShareCensusOnPairingWrites();

      final pairing = await pairedOver(first);
      expect((await folders.shareCensus.read()).paired, isTrue);
      await pairing.forget();
      await pumpEventQueue();
      expect(folders.shareCensus.known, isNull, reason: 'forgotten');
      expect(
        (await folders.shareCensus.read()).paired,
        isFalse,
        reason: 'read again: the pair is gone',
      );

      // The app's switch: every per-database singleton reset, the
      // repository rebound in place.
      DatabaseLifecycle.notifyDatabaseSwitching();
      rebindRepositoriesTo(second);
      final next = await pairedOver(second);
      expect(identical(next, pairing), isFalse);
      expect((await folders.shareCensus.read()).paired, isTrue);
      await next.forget();
      await pumpEventQueue();
      expect(folders.shareCensus.known, isNull, reason: 'the new database\'s');

      final last = await pairedOver(second);
      await folders.shareCensus.read();
      await resetDependencies();
      await last.forget();
      await pumpEventQueue();
      expect(folders.shareCensus.known, isNotNull, reason: 'nothing follows');
    },
  );

  test('only a write that changes the stored pair forgets the census: an '
      'invite cancelled or a notice dismissed forgets nothing, an unpair '
      'once', () async {
    forgetShareCensusOnPairingWrites();
    var forgets = 0;
    final sub = ShareCensus.of(first).forgotten.listen((_) => forgets++);
    addTearDown(sub.cancel);

    final pairing = await pairedOver(first);
    await pairing.cancelInvite();
    await pumpEventQueue();
    expect(forgets, 0, reason: 'the pair is the same');

    await pairing.unpair();
    await pumpEventQueue();
    expect(forgets, 1, reason: 'the pair ended');
    await pairing.dismissEndedNotice();
    await pumpEventQueue();
    expect(forgets, 1, reason: 'still no pair');
  });
}
