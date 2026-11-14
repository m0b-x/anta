import 'dart:async';
import 'dart:io';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/core/di/injection.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/push/firebase_push_address_source.dart';
import 'package:anta/services/push/push_address_source.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_message_gate.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/utils/pairing_error.dart';

import '../../services/pairing_support.dart';
import '../../support/fake_push.dart';
import '../../support/fake_shared_refresh_scheduler.dart';
import '../../support/fake_sync_gateway.dart';
import '../../support/scripted_prefs_store.dart';
import '../../support/waiting_note.dart';

/// An address source whose platform refuses the give-up.
class _RefusingAddressSource extends FakePushAddressSource {
  @override
  Future<void> giveUp() async {
    giveUpCalls++;
    throw StateError('the platform refused');
  }
}

/// A pairing gateway that counts how often the server was asked for the
/// account's pair — what a shared read does first.
class _AskedForPairs extends FakePairingGateway {
  int asked = 0;

  @override
  Future<List<PairRecord>> findActivePairs(String uid) {
    asked++;
    return super.findActivePairs(uid);
  }
}

/// A run's steps as a suite scripts them, for the real `fireSharedRefresh`
/// around them: what it does before the trigger, and with the trigger's
/// end.
class _ScriptedSteps implements SharedRefreshRunSteps {
  /// Held by the first step until completed, when set.
  Completer<void>? pause;

  /// Completed as the first step is entered.
  final Completer<void> entered = Completer<void>();

  /// Whether the read reaches its end.
  bool readMade = true;

  /// Whether a counted retry still leaves an attempt.
  bool attemptsLeft = true;
  final List<String> counted = [];

  /// The row of retrying ends, kept as the run's own steps keep it: ended
  /// by any other end, spent at the cap.
  int row = 0;

  /// Held by the close until completed, when set; [closing] completes as
  /// the close is entered.
  Completer<void>? pauseClose;
  final Completer<void> closing = Completer<void>();

  @override
  Future<void> prepare() async {
    if (!entered.isCompleted) entered.complete();
    if (pause case final held?) await held.future;
  }

  @override
  Future<bool?> replacing() async => false;
  @override
  Future<int?> storedSchema() async => schema;
  @override
  int get schema => 7;
  @override
  Future<SharedRefreshOpened> open() async => SharedRefreshOpened.opened;
  @override
  Future<SharedRefreshSharing> shares() async => SharedRefreshSharing.yes;
  @override
  Future<SharedRefreshWorth?> planSuccessor() async =>
      (check: true, poke: true);
  @override
  Future<bool> read() async => readMade;
  @override
  Future<void> stopRead() async {}
  @override
  Future<void> close() async {
    if (!closing.isCompleted) closing.complete();
    if (pauseClose case final held?) await held.future;
  }

  @override
  Future<bool> retryCounted() async {
    counted.add('again');
    if (!attemptsLeft) return false;
    if (++row < kSharedRefreshGiveWayAttempts) return true;
    row = 0;
    return false;
  }

  @override
  Future<void> retriesOver() async {
    counted.add('over');
    row = 0;
  }

  @override
  Future<void> workConsumed() async {}
}

/// A platform that takes a message's work and never answers.
class _SilentPlatform extends FakeSharedRefreshScheduler {
  final Completer<void> never = Completer<void>();

  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  }) async {
    await super.scheduleMessage(
      pairId,
      expedited: expedited,
      behindRunning: behindRunning,
    );
    await never.future;
  }
}

/// The platform an address is ended at, counting what it was asked.
class _AddressPlatform implements PushPlatform {
  final List<String> asked = [];

  @override
  Stream<String> get registered => const Stream<String>.empty();
  @override
  Future<void> register() async => asked.add('register');
  @override
  Future<void> unregister() async => asked.add('unregister');
  @override
  Future<void> deleteInstallation() async => asked.add('delete');
}

/// The run without the app over its real steps
/// (`AppSharedRefreshRunSteps`, `fireSharedRefresh`, `stopSharedRefresh`,
/// `SyncEngine.awayFromApp`): what the fakes of the trigger's own suite
/// stand in for, on a real database file — review item 14's uncovered
/// pieces. One order, because the last case closes the database as a run
/// does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_refresh_run_steps');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // The file a run looks at before it opens anything, at this build's
    // schema.
    await AppDatabase.getInstance();
  });

  tearDown(() async {
    AlertScheduler.awayFromApp = false;
    DatabaseManager.recoversAtStart = true;
    AppDatabase.opensExistingOnly = false;
    await resetDependencies();
  });

  tearDownAll(() async {
    try {
      await (await AppDatabase.getInstance()).close();
    } catch (_) {}
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  bool runNameHeld() =>
      IsolateNameServer.lookupPortByName(kSharedRefreshRunPort) != null;

  group('the alert pass a run plans from (planSuccessor)', () {
    test('an empty calendar is no refusal: nothing can arm, nothing is '
        'worth a check or a read', () async {
      final steps = AppSharedRefreshRunSteps(null);
      await steps.open();

      expect(await steps.planSuccessor(), (check: false, poke: false));
    });

    test('something could arm and the app has stored nothing to arm '
        'under: no pass runs, and the step says so with null', () async {
      final steps = AppSharedRefreshRunSteps(null);
      await steps.open();
      final db = getIt<AppDatabase>();
      await db.syncDao.setValue(SyncDao.keyAlertStraysPending, 'marker');
      addTearDown(() => db.syncDao.deleteValue(SyncDao.keyAlertStraysPending));

      expect(await steps.planSuccessor(), isNull);
      expect(
        await db.syncDao.getValue(SyncDao.keyAlertStraysPending),
        'marker',
        reason: 'a refused pass swept nothing',
      );
    });
  });

  group('the engine a run reads with (SyncEngine.awayFromApp)', () {
    test('is outside the singleton, never started, and away from its first '
        'moment by its own making: the page\'s read asks the server '
        'nothing, the read while away does', () async {
      final steps = AppSharedRefreshRunSteps(null);
      await steps.open();
      // Where sync can run the run's registration binds these three; here
      // they are the suites' own.
      final pairing = _AskedForPairs();
      addTearDown(pairing.dispose);
      await getIt.unregister<AuthService>();
      await getIt.unregister<PairingGateway>();
      getIt
        ..registerSingleton<AuthService>(FakeAuthService(user: userB))
        ..registerSingleton<PairingGateway>(pairing)
        ..registerSingleton<SyncGateway>(FakeSyncGateway());
      final settings = await SettingsService.getInstance();
      await settings.setSyncBinding(
        SyncBinding(
          spaceId: 'space-1',
          ownerUid: userB.uid,
          accountUid: userB.uid,
        ),
      );
      await settings.setPairingSettings(
        PairingSettings(pairId: 'pair-1', accountUid: userB.uid),
      );
      addTearDown(() async {
        await settings.setSyncBinding(null);
        await settings.setPairingSettings(const PairingSettings());
      });

      final engine = await SyncEngine.awayFromApp(notify: (_) {});
      addTearDown(engine.stop);

      expect(SyncEngine.instanceForTesting, isNull);
      expect(engine.isStarted, isFalse);

      final page = await engine.readSharedNow();
      expect(page.skipped, isNull);
      expect(pairing.asked, 0, reason: 'not in front: the page reads nothing');

      final away = await engine.readSharedWhileAway();
      expect(away.skipped, isNull);
      expect(pairing.asked, 1);
      expect(engine.awayReadOwed, isFalse);
      expect(engine.isStarted, isFalse);

      // And the run's own step over such an engine: the read is made, and
      // answered as made.
      expect(await steps.read(), isTrue);
      expect(pairing.asked, 2);
      await steps.stopRead();
    });

    /// A run's steps, open on a database that says it is paired as `pair-1`
    /// and bound to [userB], over the suites' own identity and gateways —
    /// and [addresses] in place of the source the run binds, when given.
    Future<(AppSharedRefreshRunSteps, _AskedForPairs)> pairedRun([
      PushAddressSource? addresses,
    ]) async {
      final steps = AppSharedRefreshRunSteps(null);
      await steps.open();
      addTearDown(steps.stopRead);
      final pairing = _AskedForPairs();
      addTearDown(pairing.dispose);
      await getIt.unregister<AuthService>();
      await getIt.unregister<PairingGateway>();
      getIt
        ..registerSingleton<AuthService>(FakeAuthService(user: userB))
        ..registerSingleton<PairingGateway>(pairing)
        ..registerSingleton<SyncGateway>(FakeSyncGateway());
      if (addresses != null) {
        await getIt.unregister<PushAddressSource>();
        getIt.registerSingleton<PushAddressSource>(addresses);
      }
      final settings = await SettingsService.getInstance();
      await settings.setSyncBinding(
        SyncBinding(
          spaceId: 'space-1',
          ownerUid: userB.uid,
          accountUid: userB.uid,
        ),
      );
      await settings.setPairingSettings(
        PairingSettings(pairId: 'pair-1', accountUid: userB.uid),
      );
      addTearDown(() async {
        await settings.setSyncBinding(null);
        await settings.setPairingSettings(const PairingSettings());
      });
      return (steps, pairing);
    }

    test('a run whose read finds the pair ended gives the install\'s '
        'address up at the platform, once — the app that would do it at '
        'its next open is closed (push review F6)', () async {
      final addresses = FakePushAddressSource()..held = true;
      final (steps, pairing) = await pairedRun(addresses);

      expect(await steps.read(), isTrue);

      expect(pairing.asked, 1);
      expect(addresses.giveUpCalls, 1);
      expect(addresses.held, isFalse);
      expect(addresses.registrations, 0, reason: 'the run names no address');
    });

    test('a run whose pair stands asks the address source nothing', () async {
      final addresses = FakePushAddressSource()..held = true;
      final (steps, pairing) = await pairedRun(addresses);
      pairing.pairs['pair-1'] = PairRecord(
        pairId: 'pair-1',
        members: [userA.uid, userB.uid],
        isActive: true,
        createdAt: DateTime.utc(2026, 11, 1),
      );

      await steps.read();

      expect(pairing.asked, 1);
      expect(addresses.giveUpCalls, 0);
      expect(addresses.holdsCalls, 0);
      expect(addresses.registrations, 0);
    });

    test('a run that could not ask for the pair gives nothing up', () async {
      final addresses = FakePushAddressSource()..held = true;
      final (steps, pairing) = await pairedRun(addresses);
      pairing.failAlways = PairingError.offline;

      await steps.read();

      expect(pairing.asked, 1);
      expect(addresses.giveUpCalls, 0);
    });

    test('a give-up the platform fails is the next run\'s to make again: '
        'the read still ends as made', () async {
      final addresses = _RefusingAddressSource();
      final (steps, _) = await pairedRun(addresses);

      expect(await steps.read(), isTrue);
      expect(addresses.giveUpCalls, 1);
    });

    test('where no address can be held — the no-op source the run binds '
        'off Android and under QA — an ended pair costs nothing', () async {
      final (steps, pairing) = await pairedRun();

      expect(getIt<PushAddressSource>(), isA<NoOpPushAddressSource>());
      expect(await steps.read(), isTrue);
      expect(pairing.asked, 1);
    });
  });

  group('a message\'s work is always a fresh one (review of leg 12, F1)', () {
    late FakeSharedRefreshScheduler platform;
    late _ScriptedSteps steps;

    setUp(() {
      platform = FakeSharedRefreshScheduler();
      steps = _ScriptedSteps();
    });

    Future<bool> fire({
      SharedRefreshCause cause = SharedRefreshCause.message,
      String? pair = 'pair-1',
    }) => fireSharedRefresh(
      cause: cause,
      pair: pair,
      steps: steps,
      messageScheduler: platform,
    );

    test('an end that still owes the read is not handed back to the '
        'platform — it would run the work again plain, on a back-off: the '
        'run hands a fresh work over behind itself, expedited as the app '
        'stored, and answers done', () async {
      final prefs = await SharedPreferences.getInstance();
      addTearDown(() => prefs.remove(SettingsKeys.pushExpeditedWork));
      steps.readMade = false;

      expect(await fire(), isTrue);
      expect(platform.calls, ['message:pair-1:behind']);
      expect(steps.counted, ['again']);

      await prefs.setString(SettingsKeys.pushExpeditedWork, '1');
      expect(await fire(), isTrue);
      expect(platform.calls.last, 'message:pair-1:expedited:behind');
      expect(await waits('pair-1'), isFalse, reason: 'no note is written');
    });

    test('the third such end in a row ends the row: done, and nothing more '
        'is handed over', () async {
      steps
        ..readMade = false
        ..attemptsLeft = false;

      expect(await fire(), isTrue);
      expect(platform.calls, isEmpty);
    });

    test('a hand-over the platform refuses leaves the platform\'s own '
        'retry, so something stands', () async {
      steps.readMade = false;
      platform.failNext = true;

      expect(await fire(), isFalse);
      expect(platform.calls, isEmpty);
    });

    test('a read that was made hands nothing over', () async {
      expect(await fire(), isTrue);
      expect(platform.calls, isEmpty);
      expect(steps.counted, ['over']);
    });

    test('the check\'s own work keeps the platform\'s retry: nothing is '
        'handed over for it', () async {
      steps.readMade = false;

      expect(await fire(cause: SharedRefreshCause.check, pair: null), isFalse);
      expect(platform.calls, isEmpty);
    });

    test('a run the platform stopped hands nothing over and counts '
        'nothing: a newer message\'s work took its place, or the platform '
        'runs it again itself', () async {
      steps.pause = Completer<void>();
      final fired = fire();
      await steps.entered.future;

      final stopped = stopSharedRefresh();
      steps.pause!.complete();
      await stopped;

      expect(await fired, isFalse);
      expect(platform.calls, isEmpty);
      expect(steps.counted, isEmpty);
    });

    test('the waiting note is off before the trigger\'s first step: a '
        'message that arrives while the run reads hands a work over again '
        '(F2)', () async {
      await SharedRefreshMessageGate.mark('pair-1');
      steps.pause = Completer<void>();
      final fired = fire();
      await steps.entered.future;

      expect(await waits('pair-1'), isFalse);

      steps.pause!.complete();
      await fired;
    });

    test('a note store that never answers holds the trigger back for its '
        'bound and no longer (F4)', () async {
      final store = ScriptedPrefsStore.install();
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      await SharedPreferences.getInstance();
      final never = Completer<void>();
      addTearDown(never.complete);
      store.onRead = (_) => never.future;

      final fired = fireSharedRefresh(
        cause: SharedRefreshCause.message,
        pair: 'pair-1',
        steps: steps,
        messageScheduler: platform,
        startBound: const Duration(milliseconds: 50),
      );
      await steps.entered.future.timeout(const Duration(seconds: 2));

      expect(await fired, isTrue);
    });

    test('a run whose read was made and which the platform stopped while '
        'it closed — what a newer message\'s hand-over does to any running '
        'work — still ends the row of retries: only a retrying end of a '
        'stopped run is left uncounted (verification of leg 13, P4)', () async {
      steps
        ..row = 2
        ..pauseClose = Completer<void>();
      final fired = fire();
      await steps.closing.future;

      final stopped = stopSharedRefresh();
      steps.pauseClose!.complete();
      await stopped;

      expect(await fired, isTrue);
      expect(steps.counted, ['over']);
      expect(steps.row, 0);

      // The next work's first failed read is the first of a row: counted
      // one, and a fresh work handed over — not the row's end.
      steps
        ..readMade = false
        ..pauseClose = null;
      expect(await fire(), isTrue);
      expect(steps.row, 1);
      expect(platform.calls, ['message:pair-1:behind']);
    });

    test('a hand-over the platform never answers is waited on for its '
        'bound and no longer: the platform\'s own retry is asked, so '
        'something stands', () async {
      steps.readMade = false;
      final silent = _SilentPlatform();
      addTearDown(silent.never.complete);

      final answer = await fireSharedRefresh(
        cause: SharedRefreshCause.message,
        pair: 'pair-1',
        steps: steps,
        messageScheduler: silent,
        handOverBound: const Duration(milliseconds: 50),
      ).timeout(const Duration(seconds: 2));

      expect(answer, isFalse);
      expect(silent.calls, ['message:pair-1:behind']);
    });

    test('what the app stored cannot be read: the fresh work is handed '
        'over plain, the direction that costs no notification', () async {
      final store = ScriptedPrefsStore.install({
        SettingsKeys.pushExpeditedWork: '1',
      });
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      await SharedPreferences.getInstance();
      steps.readMade = false;

      expect(await fire(), isTrue);
      expect(platform.calls, ['message:pair-1:expedited:behind']);

      store.onRead = (_) => throw StateError('no store');
      expect(await fire(), isTrue);
      expect(platform.calls.last, 'message:pair-1:behind');
    });
  });

  group('a message\'s run that finds this database not sharing pays a '
      'delete that is owed (review of leg 12, F5)', () {
    late _AddressPlatform platform;

    /// A run, open, over the suites' identity and a real address source:
    /// nobody is bound, so the database does not share.
    Future<AppSharedRefreshRunSteps> notSharingRun({String? pair}) async {
      final steps = AppSharedRefreshRunSteps(null, pair: pair);
      await steps.open();
      await getIt.unregister<AuthService>();
      await getIt.unregister<PushAddressSource>();
      getIt
        ..registerSingleton<AuthService>(FakeAuthService(user: userB))
        ..registerSingleton<SyncGateway>(FakeSyncGateway())
        ..registerSingleton<PushAddressSource>(
          FirebasePushAddressSource(platform: platform),
        );
      return steps;
    }

    setUp(() => platform = _AddressPlatform());

    Future<void> stored(Map<String, String> values) async {
      final prefs = await SharedPreferences.getInstance();
      for (final MapEntry(:key, :value) in values.entries) {
        await prefs.setString(key, value);
      }
      addTearDown(() async {
        for (final key in values.keys) {
          await prefs.remove(key);
        }
      });
    }

    test('owed: the delete is asked once, and the end is the same', () async {
      await stored({SettingsKeys.pushDeleteOwed: '1'});
      final steps = await notSharingRun(pair: 'pair-1');

      expect(await steps.shares(), SharedRefreshSharing.no);

      expect(platform.asked, ['unregister', 'delete']);
    });

    test('an address that is held, nothing owed: the platform is asked '
        'nothing — the open database may be another than the paired', () async {
      await stored({SettingsKeys.pushAddressHeld: '1'});
      final steps = await notSharingRun(pair: 'pair-1');

      expect(await steps.shares(), SharedRefreshSharing.no);

      expect(platform.asked, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SettingsKeys.pushAddressHeld), '1');
    });

    test('the database shares, but not in the pair the message named: the '
        'run ends not sharing all the same, and the owed delete is paid '
        'there too (verification of leg 13)', () async {
      await stored({SettingsKeys.pushDeleteOwed: '1'});
      final steps = await notSharingRun(pair: 'pair-9');
      final settings = await SettingsService.getInstance();
      await settings.setSyncBinding(
        SyncBinding(
          spaceId: 'space-1',
          ownerUid: userB.uid,
          accountUid: userB.uid,
        ),
      );
      await settings.setPairingSettings(
        PairingSettings(pairId: 'pair-1', accountUid: userB.uid),
      );
      addTearDown(() async {
        await settings.setSyncBinding(null);
        await settings.setPairingSettings(const PairingSettings());
      });

      expect(await steps.shares(), SharedRefreshSharing.no);
      expect(platform.asked, ['unregister', 'delete']);

      // The pair it does hold, named: sharing, and nothing more is asked.
      final holding = AppSharedRefreshRunSteps(null, pair: 'pair-1');
      expect(await holding.shares(), SharedRefreshSharing.yes);
      expect(platform.asked, ['unregister', 'delete']);
    });

    test(
      'the check\'s own work, which no message woke, pays nothing',
      () async {
        await stored({SettingsKeys.pushDeleteOwed: '1'});
        final steps = await notSharingRun();

        expect(await steps.shares(), SharedRefreshSharing.no);

        expect(platform.asked, isEmpty);
      },
    );
  });

  group('a whole trigger over the real steps (fireSharedRefresh)', () {
    test('a stop with nothing firing is nothing', () async {
      await stopSharedRefresh();

      expect(runNameHeld(), isFalse);
    });

    test('the platform\'s stop reaches the trigger that is firing: it ends '
        'before it opens anything, gives its name up, and asks to be run '
        'again', () async {
      final fired = fireSharedRefresh();
      expect(runNameHeld(), isTrue, reason: 'the name first, in its own turn');

      await stopSharedRefresh();

      expect(await fired, isFalse);
      expect(runNameHeld(), isFalse);
      expect(getIt.isRegistered<AppDatabase>(), isFalse);
    });

    test('every start of a message\'s work takes its pair\'s waiting note '
        'off before anything else — a fresh work, and one the count takes '
        'for a retry (second look, D2) — and leaves another pair\'s', () async {
      final prefs = await SharedPreferences.getInstance();
      addTearDown(() async {
        await prefs.remove(SettingsKeys.sharedRefreshMessageRetries);
        await SharedRefreshMessageGate.unmark('pair-other');
      });
      await SharedRefreshMessageGate.mark('pair-note');
      await SharedRefreshMessageGate.mark('pair-other');

      var fired = fireSharedRefresh(
        cause: SharedRefreshCause.message,
        pair: 'pair-note',
      );
      await stopSharedRefresh();
      expect(await fired, isFalse, reason: 'cut: the platform runs it again');

      expect(await waits('pair-note'), isFalse);
      expect(await waits('pair-other'), isTrue);
      expect(getIt.isRegistered<AppDatabase>(), isFalse);

      // A work the platform stopped counted nothing. One that owed its
      // read did — and a message has arrived since.
      expect(
        prefs.containsKey(SettingsKeys.sharedRefreshMessageRetries),
        isFalse,
      );
      await prefs.setInt(SettingsKeys.sharedRefreshMessageRetries, 1);
      await SharedRefreshMessageGate.mark('pair-note');

      fired = fireSharedRefresh(
        cause: SharedRefreshCause.message,
        pair: 'pair-note',
      );
      await stopSharedRefresh();
      await fired;

      expect(await waits('pair-note'), isFalse);
    });

    test('the check\'s own work touches no waiting note', () async {
      addTearDown(() => SharedRefreshMessageGate.unmark('pair-note'));
      await SharedRefreshMessageGate.mark('pair-note');

      final fired = fireSharedRefresh();
      await stopSharedRefresh();
      await fired;

      expect(await waits('pair-note'), isTrue);
    });

    test('left alone it takes every real step to its end: on a host where '
        'sync cannot run that is "not sharing" — the file read at this '
        'build\'s schema, the run\'s own dependencies registered with the '
        'isolate marked as a run, the database closed, the name given up, '
        'and nothing asked for again', () async {
      final db = await AppDatabase.getInstance();

      expect(await fireSharedRefresh(), isTrue);

      expect(runNameHeld(), isFalse);
      expect(getIt.isRegistered<AppDatabase>(), isTrue);
      expect(AlertScheduler.awayFromApp, isTrue);
      expect(DatabaseManager.recoversAtStart, isFalse);
      // Closed, as the isolate that held it is about to end.
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
    });
  });
}
