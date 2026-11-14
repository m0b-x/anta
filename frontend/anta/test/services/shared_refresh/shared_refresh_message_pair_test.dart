import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/shared_refresh/shared_refresh.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../database/support/db_test_support.dart';
import '../../support/fake_port_registry.dart';
import '../../support/fake_shared_refresh_scheduler.dart';
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
      SharedRefreshSharing.yes,
    );
  });

  test('a message for the open database\'s pair reads; one for another '
      'pair does not — told for certain, so nothing retries on it', () async {
    expect(
      await AppSharedRefreshRunSteps(null, pair: 'pair-1').shares(),
      SharedRefreshSharing.yes,
    );
    expect(
      await AppSharedRefreshRunSteps(null, pair: 'pair-9').shares(),
      SharedRefreshSharing.no,
    );
  });

  group('a message\'s read forwarded to the app (case B13)', () {
    late FakeSharedRefreshScheduler platform;
    late SharedRefresh refresh;
    late List<String> did;

    setUp(() {
      platform = FakeSharedRefreshScheduler();
      refresh = SharedRefresh(scheduler: platform, shares: () async => true);
      did = [];
    });

    /// The app's own order, over the open database's real pairing.
    Future<void> forwarded(String? pair) => SharedRefreshApp.forwardedRead(
      null,
      pair: pair,
      refresh: refresh,
      read: () async {
        did.add('read');
        return true;
      },
      alertPass: () async => did.add('pass'),
    );

    test('for the pair the open database is in: the app reads, and its '
        'pass follows', () async {
      await forwarded('pair-1');

      expect(did, ['read', 'pass']);
    });

    test('for another database\'s pair: nothing is read and no pass runs, '
        'and the asker is answered as for a read that is not owed — '
        'nothing thrown, so nothing retries', () async {
      await forwarded('pair-9');

      expect(did, isEmpty);
      expect(platform.calls, isEmpty);
    });

    test(
      'the check\'s own read names no pair and is never held back',
      () async {
        await forwarded(null);

        expect(did, ['read', 'pass']);
      },
    );

    test('a database in no pair holds none', () async {
      await SettingsService.forTesting(
        db,
      ).setPairingSettings(const PairingSettings());

      expect(await SharedRefreshApp.databaseHoldsPair('pair-1'), isFalse);
    });

    group('through the app\'s own read, as the launch wires it (review '
        'item 14)', () {
      late FakePortRegistry registry;

      setUp(() {
        registry = FakePortRegistry();
        SharedRefreshAvailability.debugSupported = true;
        GetIt.I.registerSingleton<SharedRefresh>(refresh);
        // The launch's own step, with the read it wires by default.
        SharedRefreshApp.beginLaunch(registry: registry);
        SharedRefreshApp.launched();
      });

      tearDown(() {
        SharedRefreshApp.resetForTesting();
        SharedRefreshAvailability.debugSupported = null;
      });

      Future<SharedRefreshForward> forwarded({String? pair}) {
        final run = SharedRefreshRunPort(registry: registry)..open();
        addTearDown(run.close);
        return run.forward(limit: const Duration(seconds: 5), pair: pair);
      }

      test('the pair a message named reaches the gate: for another '
          'database\'s pair the app builds no engine, reads nothing, plans '
          'nothing, and answers done', () async {
        expect(await forwarded(pair: 'pair-9'), SharedRefreshForward.done);

        expect(SyncEngine.instanceForTesting, isNull);
        expect(platform.calls, isEmpty);
      });

      test('for this database\'s pair it goes on to the engine — which this '
          'suite cannot open, and that is the answer it gives', () async {
        // No database file can be opened here: the engine's own start
        // throws, where a read held back at the gate answered done.
        expect(await forwarded(pair: 'pair-1'), SharedRefreshForward.failed);
      });

      test(
        'where sync cannot run at all nothing is asked of anything',
        () async {
          await GetIt.I.unregister<SyncGateway>();

          expect(await forwarded(pair: 'pair-1'), SharedRefreshForward.done);
          expect(await forwarded(), SharedRefreshForward.done);
          expect(SyncEngine.instanceForTesting, isNull);
        },
      );
    });
  });

  group('who is signed in (review item 7)', () {
    late FakeAuthService auth;

    setUp(() {
      auth = FakeAuthService();
      GetIt.I
        ..unregister<AuthService>()
        ..registerSingleton<AuthService>(auth);
    });

    test('the identity says nobody is: told for certain', () async {
      final sharing = AppSharedRefreshRunSteps(
        SharedRefreshSlot.first,
      ).shares();
      await pumpEventQueue();
      auth.emitAuth(null);

      expect(await sharing, SharedRefreshSharing.no);
    });

    test('the stored account restored a moment later is the one asked '
        'about', () async {
      final sharing = AppSharedRefreshRunSteps(
        SharedRefreshSlot.first,
      ).shares();
      await pumpEventQueue();
      auth.emitAuth(userA);

      expect(await sharing, SharedRefreshSharing.yes);
    });

    test('the identity says nothing within the wait: not told — never '
        '"not sharing", which ended the chain of checks until the app was '
        'opened', () {
      fakeAsync((async) {
        SharedRefreshSharing? answer;
        AppSharedRefreshRunSteps(
          SharedRefreshSlot.first,
        ).shares().then((told) => answer = told);

        async.elapse(kSharedRefreshAccountWait - const Duration(seconds: 1));
        expect(answer, isNull);
        async.elapse(const Duration(seconds: 2));

        expect(answer, SharedRefreshSharing.unknown);
      });
    });
  });

  group('how often a message\'s work gives way in a row — the platform '
      'hands Dart no attempt count, and its back-off has no end', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// Each work is an isolate of its own: a new object every time.
    AppSharedRefreshRunSteps work() => AppSharedRefreshRunSteps(null);

    Future<bool> counts() async => (await SharedPreferences.getInstance())
        .containsKey(SettingsKeys.sharedRefreshMessageRetries);

    test('three attempts at most: two give-ways leave the platform a '
        'retry, the third does not, and the count starts over', () async {
      expect(kSharedRefreshGiveWayAttempts, 3);

      expect(await work().retryCounted(), isTrue);
      expect(await work().retryCounted(), isTrue);
      expect(await work().retryCounted(), isFalse);
      expect(await counts(), isFalse);

      expect(await work().retryCounted(), isTrue);
    });

    test('a run that ends any other way ends the row', () async {
      await work().retryCounted();
      await work().retryCounted();

      await work().retriesOver();

      expect(await counts(), isFalse);
      expect(await work().retryCounted(), isTrue);
      expect(await work().retryCounted(), isTrue);
    });

    test('an install that never counted one writes nothing', () async {
      await work().retriesOver();

      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test(
      'the count is re-read before it is used (review H11): each work '
      'is an isolate with a copy of its own, and the count another one '
      'wrote since is the one that counts — and the one that is cleared',
      () async {
        final store = SharedPreferencesStorePlatform.instance;
        const key = 'flutter.${SettingsKeys.sharedRefreshMessageRetries}';
        // This isolate's copy is loaded, holding no count.
        expect(await counts(), isFalse);

        await store.setValue('Int', key, 2);
        expect(await work().retryCounted(), isFalse, reason: 'the third');

        await store.setValue('Int', key, 2);
        await work().retriesOver();
        expect((await store.getAll()).containsKey(key), isFalse);
      },
    );

    test('the check\'s work counts apart from a message\'s (review H5): '
        'each is retried by the platform by itself, and the end of one does '
        'not end the other\'s row', () async {
      AppSharedRefreshRunSteps check() =>
          AppSharedRefreshRunSteps(SharedRefreshSlot.first);
      final prefs = await SharedPreferences.getInstance();

      await work().retryCounted();
      await work().retryCounted();
      expect(await check().retryCounted(), isTrue, reason: 'its own first');
      expect(prefs.getInt(SettingsKeys.sharedRefreshCheckGaveWay), 1);

      await check().retriesOver();
      expect(
        prefs.containsKey(SettingsKeys.sharedRefreshCheckGaveWay),
        isFalse,
      );
      expect(await work().retryCounted(), isFalse, reason: 'still its third');

      // Either slot's work is the one check.
      await AppSharedRefreshRunSteps(SharedRefreshSlot.second).retryCounted();
      await check().retryCounted();
      expect(await check().retryCounted(), isFalse);
    });
  });
}
