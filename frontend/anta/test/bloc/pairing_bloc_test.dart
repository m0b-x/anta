import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/pairing_error.dart';

import '../database/support/db_test_support.dart';
import '../services/pairing_support.dart';

/// Binds the singletons the bloc resolves through `PairingService.getInstance`
/// — it returns the existing instance, so seeding it here keeps the real
/// `AppDatabase.getInstance` path_provider lookup out of the test.
Future<PairingService> _bootService(
  FakeAuthService auth,
  FakePairingGateway gateway,
) async {
  DatabaseLifecycle.notifyDatabaseSwitching();
  SettingsService.reset();
  PairingService.reset();
  final settings = SettingsService.forTesting(await openTestDatabase());
  return PairingService.forTesting(
    auth: auth,
    gateway: gateway,
    settings: settings,
  );
}

Future<(PairingBloc, List<PairingState>)> _pumpBloc(
  FakeAuthService auth,
  FakePairingGateway gateway,
) async {
  final bloc = PairingBloc(authService: auth, gateway: gateway);
  final states = <PairingState>[];
  bloc.stream.listen(states.add);
  bloc.add(const LoadPairing());
  await pumpEventQueue();
  return (bloc, states);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
  });

  group('availability', () {
    test(
      'a no-op gateway reads as unavailable, not as a pairing button',
      () async {
        final auth = FakeAuthService(user: userA);
        final gateway = FakePairingGateway(available: false);
        addTearDown(gateway.dispose);
        await _bootService(auth, gateway);

        final (bloc, states) = await _pumpBloc(auth, gateway);
        expect(states, [const PairingUnavailable()]);
        await bloc.close();
      },
    );

    test('signed out reports signed out rather than unpaired', () async {
      final auth = FakeAuthService();
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await _bootService(auth, gateway);

      final (bloc, states) = await _pumpBloc(auth, gateway);
      expect(states, [const PairingSignedOut()]);
      await bloc.close();
    });

    test('signing out after being paired drops back to signed out', () async {
      final auth = FakeAuthService(user: userA);
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);

      auth.emitAuth(null);
      await pumpEventQueue();

      expect(states.last, const PairingSignedOut());
      await bloc.close();
    });
  });

  group('invite', () {
    test('loads unpaired, then holds the generated code', () async {
      final auth = FakeAuthService(user: userA);
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);

      expect(states.last, isA<PairingUnpaired>());

      bloc.add(const GenerateInviteRequested());
      await pumpEventQueue();

      final inviting = states.last;
      expect(inviting, isA<PairingInviting>());
      expect(
        (inviting as PairingInviting).code.length,
        PairingService.codeLength,
      );
      expect(gateway.invites, hasLength(1));
      await bloc.close();
    });

    test('cancelling the invite deletes it and returns to unpaired', () async {
      final auth = FakeAuthService(user: userA);
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);

      bloc.add(const GenerateInviteRequested());
      await pumpEventQueue();
      bloc.add(const CancelInviteRequested());
      await pumpEventQueue();

      expect(states.last, isA<PairingUnpaired>());
      expect(
        gateway.invites,
        isEmpty,
        reason: 'an overheard code must not stay live until it expires',
      );
      await bloc.close();
    });

    test(
      'generating offline keeps the state and attaches the reason',
      () async {
        final auth = FakeAuthService(user: userA);
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        await _bootService(auth, gateway);
        final (bloc, states) = await _pumpBloc(auth, gateway);

        gateway.failNext = PairingError.offline;
        bloc.add(const GenerateInviteRequested());
        await pumpEventQueue();

        final failed = states.last;
        expect(failed, isA<PairingUnpaired>());
        expect(
          (failed as PairingUnpaired).failure,
          const PairingFailure(PairingError.offline, PairingAction.generate),
          reason: 'a failed "create a code" must not accuse the code field',
        );
        expect(failed.busy, isFalse);
        await bloc.close();
      },
    );

    test('a failed cancel keeps the code the user is reading aloud', () async {
      final auth = FakeAuthService(user: userA);
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);

      bloc.add(const GenerateInviteRequested());
      await pumpEventQueue();
      final code = (states.last as PairingInviting).code;

      gateway.failNext = PairingError.offline;
      bloc.add(const CancelInviteRequested());
      await pumpEventQueue();

      final failed = states.last;
      expect(failed, isA<PairingInviting>());
      expect((failed as PairingInviting).code, code);
      expect(
        failed.failure,
        const PairingFailure(PairingError.offline, PairingAction.cancel),
      );
      await bloc.close();
    });
  });

  group('redeem', () {
    test(
      'an invalid code surfaces its own message, not a generic failure',
      () async {
        final auth = FakeAuthService(user: userA);
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        await _bootService(auth, gateway);
        final (bloc, states) = await _pumpBloc(auth, gateway);

        bloc.add(const RedeemCodeRequested('K7M2P4XQ'));
        await pumpEventQueue();

        final failed = states.last;
        expect(failed, isA<PairingUnpaired>());
        final failure = (failed as PairingUnpaired).failure!;
        expect(failure.error, PairingError.codeInvalid);
        expect(
          failure.belongsToCodeField,
          isTrue,
          reason:
              'a redemption failure belongs under the field they typed into',
        );
        await bloc.close();
      },
    );

    test(
      'redeeming your own code is rejected before any pair exists',
      () async {
        final auth = FakeAuthService(user: userA);
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        await _bootService(auth, gateway);
        final (bloc, states) = await _pumpBloc(auth, gateway);

        bloc.add(const GenerateInviteRequested());
        await pumpEventQueue();
        final code = (states.last as PairingInviting).code;

        bloc.add(RedeemCodeRequested(code));
        await pumpEventQueue();

        final failed = states.last;
        expect(failed, isA<PairingInviting>());
        expect(
          (failed as PairingInviting).failure,
          const PairingFailure(PairingError.ownCode, PairingAction.redeem),
        );
        expect(gateway.createPairCalls, 0);
        await bloc.close();
      },
    );

    test('a completed redemption reports the partner', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      // The other device mints the code first.
      final creatorAuth = FakeAuthService(user: userA);
      final creator = await _bootService(creatorAuth, gateway);
      final code = (await creator.generateInvite()).pendingCode!;

      final auth = FakeAuthService(user: userB);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);

      bloc.add(RedeemCodeRequested(PairingService.formatCode(code)));
      await pumpEventQueue();

      final paired = states.last;
      expect(paired, isA<PairingPaired>());
      expect((paired as PairingPaired).partner?.uid, userA.uid);
      await bloc.close();
    });
  });

  group('ending', () {
    test('the partner ending the link raises the ended state', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creatorAuth = FakeAuthService(user: userA);
      final creator = await _bootService(creatorAuth, gateway);
      final code = (await creator.generateInvite()).pendingCode!;

      final auth = FakeAuthService(user: userB);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);
      bloc.add(RedeemCodeRequested(code));
      await pumpEventQueue();
      final pairId = (gateway.pairs.values.first).pairId;

      await gateway.endPair(pairId: pairId, endedBy: userA.uid);
      await pumpEventQueue();

      expect(states.last, isA<PairingEnded>());
      await bloc.close();
    });

    test('acknowledging the notice returns to unpaired', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creatorAuth = FakeAuthService(user: userA);
      final creator = await _bootService(creatorAuth, gateway);
      final code = (await creator.generateInvite()).pendingCode!;

      final auth = FakeAuthService(user: userB);
      await _bootService(auth, gateway);
      final (bloc, states) = await _pumpBloc(auth, gateway);
      bloc.add(RedeemCodeRequested(code));
      await pumpEventQueue();

      await gateway.endPair(
        pairId: gateway.pairs.values.first.pairId,
        endedBy: userA.uid,
      );
      await pumpEventQueue();
      bloc.add(const EndedNoticeDismissed());
      await pumpEventQueue();

      expect(states.last, isA<PairingUnpaired>());
      await bloc.close();
    });

    test(
      'unpairing yourself goes straight to unpaired, with no notice',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final creatorAuth = FakeAuthService(user: userA);
        final creator = await _bootService(creatorAuth, gateway);
        final code = (await creator.generateInvite()).pendingCode!;

        final auth = FakeAuthService(user: userB);
        await _bootService(auth, gateway);
        final (bloc, states) = await _pumpBloc(auth, gateway);
        bloc.add(RedeemCodeRequested(code));
        await pumpEventQueue();

        bloc.add(const UnpairRequested());
        await pumpEventQueue();

        expect(states.last, isA<PairingUnpaired>());
        await bloc.close();
      },
    );
  });
}
