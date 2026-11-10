import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/sync_limits.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_service.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/utils/auth_error.dart';

import '../support/fake_sync_engine.dart';

const _user = AppUser(uid: 'uid-1', displayName: 'Alex', email: 'a@b.c');
const _partner = AppUser(uid: 'uid-2', email: 'p@b.c');

class _FakeAuthService implements AuthService {
  _FakeAuthService({this.available = true, AppUser? user}) : _user = user;

  final bool available;
  AppUser? _user;
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  AppUser? signInResult;
  Object? signInError;
  Completer<AppUser?>? signInGate;
  bool signOutCalled = false;
  Object? signOutError;

  /// When set, a sign-out waits for it.
  Completer<void>? signOutGate;

  @override
  bool get isAvailable => available;

  /// As Firebase's own stream: a new listener hears the account signed in
  /// now first, in a later microtask, then every change (review K2).
  @override
  Stream<AppUser?> get authStateChanges => Stream.multi((listener) {
    var heard = false;
    final subscription = _controller.stream.listen((user) {
      heard = true;
      listener.add(user);
    });
    listener.onCancel = subscription.cancel;
    scheduleMicrotask(() {
      if (!heard) listener.add(_user);
    });
  }, isBroadcast: true);

  @override
  AppUser? get currentUser => _user;

  void emitAuth(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  /// How many Google flows were started.
  int signInCalls = 0;

  @override
  Future<AppUser?> signInWithGoogle() async {
    signInCalls++;
    // Mirrors the real service: a cancelled flow returns null and leaves any
    // existing session untouched; only a completed flow replaces it.
    if (signInGate != null) {
      final result = await signInGate!.future;
      if (result != null) _user = result;
      return result;
    }
    if (signInError != null) throw signInError!;
    if (signInResult != null) _user = signInResult;
    return signInResult;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    if (signOutGate != null) await signOutGate!.future;
    if (signOutError != null) throw signOutError!;
    _user = null;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Answers with [pendingCount] and records the uid of every read, so a test
/// can tell which account a state's status was read for.
class _FakeStatusReader implements SyncStatusReader {
  int pendingCount = 0;
  SyncPause pause = SyncPause.none;
  SyncBinding? binding;
  Object? error;

  /// When set, the next read waits for it, then clears it.
  Completer<void>? gate;

  /// When set, every read waits for it — the load's and the one the auth
  /// stream's first answer asks for alike.
  Completer<void>? stall;
  final List<String?> reads = [];

  @override
  Future<SyncStatus> read({AppUser? user}) async {
    reads.add(user?.uid);
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    if (stall case final stalled?) await stalled.future;
    if (error != null) throw error!;
    return SyncStatus(
      pendingCount: pendingCount,
      pause: pause,
      binding: binding,
    );
  }
}

/// An engine whose stop and start never return — a run's apply hooks that
/// hang.
class _StuckEngine extends FakeSyncEngine {
  @override
  Future<void> stop() {
    calls.add('stop');
    return Completer<void>().future;
  }

  @override
  Future<void> start() {
    calls.add('start');
    return Completer<void>().future;
  }
}

/// Answers each bind step as scripted and records it, so a test reads which
/// step the bloc took and with what.
class _FakeSpaceService implements SyncSpaceService {
  SyncBindStart startResult = const SyncBindStartPick(
    spaces: [],
    holdsData: false,
  );
  String downloadedInto = 'downloaded';
  Object? error;

  /// When set, the next step waits for it, then clears it.
  Completer<void>? gate;
  final List<String> calls = [];

  /// Runs as each step is taken, so a test can see what the engine had been
  /// told by then, or swap the engine a download's switch rebuilds.
  void Function(String call)? onStep;

  Future<void> _step(String call) async {
    calls.add(call);
    onStep?.call(call);
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    if (error != null) throw error!;
  }

  @override
  Future<SyncBindStart> start({required String accountUid}) async {
    await _step('start:$accountUid');
    return startResult;
  }

  @override
  Future<void> bindExisting(SyncSpaceRef space, {required String accountUid}) =>
      _step('merge:${space.spaceId}:$accountUid');

  @override
  Future<String> downloadIntoNewDatabase(
    SyncSpaceInfo space, {
    required String accountUid,
  }) async {
    await _step('download:${space.ref.spaceId}:$accountUid');
    return downloadedInto;
  }

  @override
  Future<SyncSpaceInfo> createAndBind({
    required String accountUid,
    String? name,
  }) async {
    await _step('upload:$name:$accountUid');
    return _space;
  }

  @override
  Future<void> stopSyncing() => _step('stop');

  /// Each account's deletion status, as the service's own stream gives it: a
  /// listener of [deletionStatusOf] hears the current one first — nothing
  /// pending when unset — in a later microtask, then every [publish], never
  /// the same one twice in a row (review G1, H7).
  final Map<String, SyncDeletionStatus> deletions = {};
  final StreamController<SyncDeletionStatus> _deletionChanges =
      StreamController<SyncDeletionStatus>.broadcast(sync: true);

  /// The accounts whose status was followed and whose following ended, each
  /// in order.
  final List<String> followed = [];
  final List<String> unfollowed = [];

  /// [status] as the service's next one for its account.
  void publish(SyncDeletionStatus status) {
    deletions[status.accountUid] = status;
    _deletionChanges.add(status);
  }

  @override
  Future<void> deleteCloudCopy() => _step('delete');

  @override
  Future<void> finishPendingDeletions({required String accountUid}) =>
      _step('finish:$accountUid');

  @override
  void followAccounts(Stream<String?> accounts) =>
      throw StateError('the app\'s start-up follows the accounts, no bloc');

  @override
  Future<List<SyncPendingDeletion>> pendingDeletions(String accountUid) async =>
      deletions[accountUid]?.pending ?? const [];

  @override
  Future<SyncDeletionStatus> deletionStatus(String accountUid) async =>
      deletions[accountUid] ?? SyncDeletionStatus(accountUid: accountUid);

  @override
  Stream<SyncDeletionStatus> deletionStatusOf(String accountUid) =>
      Stream.multi((listener) {
        followed.add(accountUid);
        SyncDeletionStatus? last;
        void add(SyncDeletionStatus status) {
          if (status == last) return;
          last = status;
          listener.add(status);
        }

        final subscription = _deletionChanges.stream
            .where((status) => status.accountUid == accountUid)
            .listen(add);
        listener.onCancel = () {
          unfollowed.add(accountUid);
          return subscription.cancel();
        };
        // A change published since the listen is newer than the first read.
        scheduleMicrotask(() {
          if (last == null) {
            add(
              deletions[accountUid] ??
                  SyncDeletionStatus(accountUid: accountUid),
            );
          }
        });
      }, isBroadcast: true);

  @override
  Future<void> deletionRunsIdle() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<List<SyncSpaceInfo>> listSpaces(String accountUid) async => [_space];

  @override
  Future<bool> databaseHoldsData() async => false;
}

const _space = SyncSpaceInfo(
  ref: SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1'),
  name: 'Phone',
  createdAt: null,
  createdBy: 'phone-device',
  schema: 45,
);

Future<(SyncBloc, _FakeAuthService, List<SyncState>)> _pumpBloc({
  bool available = true,
  AppUser? user,
  SyncStatusReader? reader,
  FakeSyncEngine? engine,
  SyncSpaceService? spaces,
}) async {
  final fake = _FakeAuthService(available: available, user: user);
  final bloc = SyncBloc(
    authService: fake,
    statusReader: reader == null ? null : () => reader,
    engine: engine == null ? null : () async => engine,
    spaces: spaces,
  );
  final states = <SyncState>[];
  bloc.stream.listen(states.add);
  bloc.add(const LoadSyncStatus());
  await pumpEventQueue();
  return (bloc, fake, states);
}

void main() {
  group('availability', () {
    test(
      'no-op binding reads as unavailable, not as a sign-in button',
      () async {
        final (bloc, _, states) = await _pumpBloc(available: false);
        expect(states, [const SyncUnavailable()]);
        await bloc.close();
      },
    );

    test('sign-in on an unavailable binding stays unavailable', () async {
      final (bloc, _, states) = await _pumpBloc(available: false);
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states.last, const SyncUnavailable());
      await bloc.close();
    });

    test('available with no session loads signed out', () async {
      final (bloc, _, states) = await _pumpBloc();
      expect(states, [const SyncSignedOut()]);
      await bloc.close();
    });

    test('a persisted session is restored on load', () async {
      final (bloc, _, states) = await _pumpBloc(user: _user);
      expect(states, [
        const SyncSignedIn(_user),
        const SyncSignedIn(_user, statusRead: true),
      ]);
      await bloc.close();
    });
  });

  group('sign-in', () {
    test('success passes through signing-in to signed-in', () async {
      final (bloc, fake, states) = await _pumpBloc();
      fake.signInResult = _user;
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states, [
        const SyncSignedOut(),
        const SyncSigningIn(),
        const SyncSignedIn(_user, statusRead: true),
      ]);
      await bloc.close();
    });

    test('cancellation returns to signed out without an error', () async {
      final (bloc, fake, states) = await _pumpBloc();
      fake.signInResult = null;
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states, [
        const SyncSignedOut(),
        const SyncSigningIn(),
        const SyncSignedOut(),
      ]);
      await bloc.close();
    });

    test('cancellation keeps an existing session', () async {
      final (bloc, fake, states) = await _pumpBloc(user: _user);
      fake.signInResult = null;
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states.last, const SyncSignedIn(_user, statusRead: true));
      await bloc.close();
    });

    test('failure surfaces as SyncFailure', () async {
      final (bloc, fake, states) = await _pumpBloc();
      fake.signInError = const AuthException(AuthError.unknown);
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states.last, const SyncFailure(AuthError.unknown));
      await bloc.close();
    });

    test('a network failure surfaces as AuthError.offline', () async {
      final (bloc, fake, states) = await _pumpBloc();
      fake.signInError = const AuthException(AuthError.offline);
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states.last, const SyncFailure(AuthError.offline));
      await bloc.close();
    });

    test(
      'a null stream emission mid-flow does not clear the spinner',
      () async {
        final (bloc, fake, states) = await _pumpBloc();
        final gate = Completer<AppUser?>();
        fake.signInGate = gate;
        bloc.add(const SignInRequested());
        await pumpEventQueue();
        fake.emitAuth(null);
        await pumpEventQueue();
        expect(states.last, const SyncSigningIn());
        gate.complete(_user);
        await pumpEventQueue();
        expect(states, [
          const SyncSignedOut(),
          const SyncSigningIn(),
          const SyncSignedIn(_user, statusRead: true),
        ]);
        await bloc.close();
      },
    );
  });

  group('auth stream', () {
    test('external sign-in and sign-out move the bloc', () async {
      final (bloc, fake, states) = await _pumpBloc();
      fake.emitAuth(_partner);
      await pumpEventQueue();
      fake.emitAuth(null);
      await pumpEventQueue();
      expect(states, [
        const SyncSignedOut(),
        const SyncSignedIn(_partner, statusRead: true),
        const SyncSignedOut(),
      ]);
      await bloc.close();
    });
  });

  group('sign-out', () {
    test('reaches the service and lands signed out', () async {
      final (bloc, fake, states) = await _pumpBloc(user: _user);
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect(fake.signOutCalled, isTrue);
      expect(states.last, const SyncSignedOut());
      await bloc.close();
    });

    test('failure surfaces as the sign-out\'s SyncFailure: the user is still '
        'signed in', () async {
      final (bloc, fake, states) = await _pumpBloc(user: _user);
      fake.signOutError = const AuthException(AuthError.unknown);
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect(
        states.last,
        const SyncFailure(
          AuthError.unknown,
          action: SyncAccountAction.signOut,
          user: _user,
        ),
      );
      expect(states.last, isNot(const SyncFailure(AuthError.unknown)));
      await bloc.close();
    });

    test('a non-auth throw is the sign-out\'s failure too', () async {
      final (bloc, fake, states) = await _pumpBloc(user: _user);
      fake.signOutError = StateError('boom');
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect(
        states.last,
        const SyncFailure(
          AuthError.unknown,
          action: SyncAccountAction.signOut,
          user: _user,
        ),
      );
      await bloc.close();
    });
  });

  group('sync status', () {
    test('load shows the account at once, then its status', () async {
      final reader = _FakeStatusReader()..pendingCount = 3;
      final (bloc, _, states) = await _pumpBloc(user: _user, reader: reader);

      expect(states, [
        const SyncSignedIn(_user),
        const SyncSignedIn(
          _user,
          status: SyncStatus(pendingCount: 3),
          statusRead: true,
        ),
      ]);
      // The load's read, then the one the auth stream's first answer asks.
      expect(reader.reads, [_user.uid, _user.uid]);
      await bloc.close();
    });

    test(
      'the account shown before its first read says the status is not '
      'read yet, even when the read lands on the same empty status',
      () async {
        final reader = _FakeStatusReader();
        final (bloc, _, states) = await _pumpBloc(user: _user, reader: reader);

        expect(states, [
          const SyncSignedIn(_user),
          const SyncSignedIn(_user, statusRead: true),
        ]);
        await bloc.close();
      },
    );

    test('an account change shows the database\'s status at once, then '
        're-reads it for the new one', () async {
      final reader = _FakeStatusReader()..pendingCount = 1;
      final (bloc, fake, states) = await _pumpBloc(reader: reader);
      reader.pendingCount = 2;

      fake.emitAuth(_partner);
      await pumpEventQueue();

      // The queue belongs to the database and shows with the new account at
      // once; its own read then replaces it (final review U-2).
      expect(states, [
        const SyncSignedOut(),
        const SyncSignedOut(status: SyncStatus(pendingCount: 1)),
        const SyncSignedIn(
          _partner,
          status: SyncStatus(pendingCount: 1),
          statusRead: true,
        ),
        const SyncSignedIn(
          _partner,
          status: SyncStatus(pendingCount: 2),
          statusRead: true,
        ),
      ]);
      expect(reader.reads, [null, null, _partner.uid]);
      await bloc.close();
    });

    test('the same account keeps its status while it is re-read', () async {
      final reader = _FakeStatusReader()..pendingCount = 1;
      final (bloc, fake, states) = await _pumpBloc(user: _user, reader: reader);
      reader.pendingCount = 2;

      fake.emitAuth(_user);
      await pumpEventQueue();

      expect(states, [
        const SyncSignedIn(_user),
        const SyncSignedIn(
          _user,
          status: SyncStatus(pendingCount: 1),
          statusRead: true,
        ),
        const SyncSignedIn(
          _user,
          status: SyncStatus(pendingCount: 2),
          statusRead: true,
        ),
      ]);
      await bloc.close();
    });

    test('a sign-in during load\'s read is not overwritten by it', () async {
      final fake = _FakeAuthService(available: true, user: null)
        ..signInResult = _user;
      final reader = _FakeStatusReader()..gate = Completer<void>();
      final loadGate = reader.gate!;
      final bloc = SyncBloc(authService: fake, statusReader: () => reader);
      final states = <SyncState>[];
      bloc.stream.listen(states.add);

      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();
      reader.pendingCount = 6;
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      loadGate.complete();
      await pumpEventQueue();

      // Read already: the auth stream's first answer asked again, ungated.
      expect(states, [
        const SyncSignedOut(),
        const SyncSigningIn(),
        const SyncSignedIn(_user, statusRead: true),
        const SyncSignedIn(
          _user,
          status: SyncStatus(pendingCount: 6),
          statusRead: true,
        ),
      ]);
      await bloc.close();
    });

    test('a stalled reader times out to the empty status', () {
      fakeAsync((async) {
        final fake = _FakeAuthService(available: true, user: _user);
        final reader = _FakeStatusReader()..stall = Completer<void>();
        final bloc = SyncBloc(authService: fake, statusReader: () => reader);
        final states = <SyncState>[];
        bloc.stream.listen(states.add);

        bloc.add(const LoadSyncStatus());
        async.elapse(SyncBloc.statusTimeout + const Duration(seconds: 1));

        // Timed out, the account is still waiting for its first status.
        expect(states, [const SyncSignedIn(_user)]);
        // A refresh afterwards reads again and lands its status.
        reader
          ..stall = null
          ..pendingCount = 2;
        bloc.add(const RefreshSyncStatus());
        async.flushMicrotasks();
        expect(
          states.last,
          const SyncSignedIn(
            _user,
            status: SyncStatus(pendingCount: 2),
            statusRead: true,
          ),
        );
        bloc.close();
        async.flushMicrotasks();
      });
    });

    test('the reader is not asked for until a status is read', () async {
      var asked = 0;
      final bloc = SyncBloc(
        authService: _FakeAuthService(available: false),
        statusReader: () {
          asked++;
          return _FakeStatusReader();
        },
      );
      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();

      expect(asked, 0);
      await bloc.close();
    });

    test('refresh re-reads and keeps the account', () async {
      final reader = _FakeStatusReader();
      final (bloc, _, states) = await _pumpBloc(user: _user, reader: reader);
      reader.pendingCount = 7;

      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      expect(
        states.last,
        const SyncSignedIn(
          _user,
          status: SyncStatus(pendingCount: 7),
          statusRead: true,
        ),
      );
      await bloc.close();
    });

    test('sign-in and sign-out carry a fresh status', () async {
      final reader = _FakeStatusReader();
      final (bloc, fake, states) = await _pumpBloc(reader: reader);
      fake.signInResult = _user;
      reader.pendingCount = 4;

      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(
        states.last,
        const SyncSignedIn(
          _user,
          status: SyncStatus(pendingCount: 4),
          statusRead: true,
        ),
      );

      reader.pendingCount = 5;
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect(
        states.last,
        const SyncSignedOut(status: SyncStatus(pendingCount: 5)),
      );
      await bloc.close();
    });

    test('a failing reader leaves the account with an empty status', () async {
      final reader = _FakeStatusReader()..error = StateError('closed db');
      final (bloc, _, states) = await _pumpBloc(user: _user, reader: reader);

      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      expect(states, [const SyncSignedIn(_user)]);
      expect(reader.reads, hasLength(3));
      await bloc.close();
    });

    test('a bound database with no one signed in reaches the signed-out '
        'state as the signedOut pause', () async {
      final reader = _FakeStatusReader()..pause = SyncPause.signedOut;
      final (bloc, _, states) = await _pumpBloc(reader: reader);

      expect(
        states.last,
        const SyncSignedOut(status: SyncStatus(pause: SyncPause.signedOut)),
      );
      await bloc.close();
    });
  });

  group('the engine', () {
    const pulling = SyncStatus(activity: SyncActivity.pulling);

    test('its status reaches the signed-in state', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);

      engine.emit(pulling);
      await pumpEventQueue();

      expect(
        states.last,
        const SyncSignedIn(_user, status: pulling, statusRead: true),
      );
      await bloc.close();
    });

    test('its status reaches the signed-out state', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(engine: engine);
      const signedOut = SyncStatus(pause: SyncPause.signedOut);

      engine.emit(signedOut);
      await pumpEventQueue();

      expect(states.last, const SyncSignedOut(status: signedOut));
      await bloc.close();
    });

    test('the cadence switch flips the status shown at once, signed in, and '
        'reaches the engine', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);
      engine.emit(pulling);
      await pumpEventQueue();

      bloc.add(const SyncCadenceChanged(SyncCadence.manual));
      await pumpEventQueue();

      expect(
        states.last,
        SyncSignedIn(
          _user,
          status: pulling.copyWith(cadence: SyncCadence.manual),
          statusRead: true,
        ),
      );
      expect(engine.calls, contains('cadence:manual'));
      expect(engine.cadence, SyncCadence.manual);
      await bloc.close();
    });

    test('the cadence switch flips the signed-out status too', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(engine: engine);
      const signedOut = SyncStatus(pause: SyncPause.signedOut);
      engine.emit(signedOut);
      await pumpEventQueue();

      bloc.add(const SyncCadenceChanged(SyncCadence.manual));
      await pumpEventQueue();

      expect(
        states.last,
        SyncSignedOut(status: signedOut.copyWith(cadence: SyncCadence.manual)),
      );
      expect(engine.calls, contains('cadence:manual'));
      await bloc.close();
    });

    test(
      'a flip the engine could not store goes back to what is stored',
      () async {
        final engine = FakeSyncEngine()..setCadenceError = StateError('closed');
        final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);
        engine.emit(pulling);
        await pumpEventQueue();

        bloc.add(const SyncCadenceChanged(SyncCadence.manual));
        await pumpEventQueue();

        expect(
          states.last,
          const SyncSignedIn(_user, status: pulling, statusRead: true),
        );
        expect(
          states.reversed.skip(1).first,
          SyncSignedIn(
            _user,
            status: pulling.copyWith(cadence: SyncCadence.manual),
            statusRead: true,
          ),
          reason: 'the flip showed, then went back',
        );
        await bloc.close();
      },
    );

    test('the engine\'s cadence lays over a reader\'s status', () async {
      final engine = FakeSyncEngine()
        ..current = const SyncStatus(cadence: SyncCadence.manual);
      final reader = _FakeStatusReader()..pendingCount = 2;
      final (bloc, _, states) = await _pumpBloc(
        user: _user,
        engine: engine,
        reader: reader,
      );

      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      final status = (states.last as SyncSignedIn).status;
      expect(status.pendingCount, 2);
      expect(status.cadence, SyncCadence.manual);
      await bloc.close();
    });

    test('is followed from a sign-in when no load came first', () async {
      final engine = FakeSyncEngine();
      final fake = _FakeAuthService()..signInResult = _user;
      final bloc = SyncBloc(authService: fake, engine: () async => engine);
      final states = <SyncState>[];
      bloc.stream.listen(states.add);

      bloc.add(const SignInRequested());
      await pumpEventQueue();
      engine.emit(pulling);
      await pumpEventQueue();

      expect(
        states.last,
        const SyncSignedIn(_user, status: pulling, statusRead: true),
      );
      await bloc.close();
    });

    test('a status is dropped while a sign-in owns the screen', () async {
      final engine = FakeSyncEngine();
      final (bloc, fake, states) = await _pumpBloc(engine: engine);
      fake.signInGate = Completer<AppUser?>();
      bloc.add(const SignInRequested());
      await pumpEventQueue();

      engine.emit(pulling);
      await pumpEventQueue();

      expect(states.last, const SyncSigningIn());
      fake.signInGate!.complete(null);
      await pumpEventQueue();
      await bloc.close();
    });

    test('a status is dropped once the shown account is no longer the '
        'current one', () async {
      final engine = FakeSyncEngine();
      final (bloc, fake, states) = await _pumpBloc(user: _user, engine: engine);
      // The identity moved on; its stream event has not been handled yet.
      fake.signInResult = _partner;
      await fake.signInWithGoogle();

      engine.emit(pulling);
      await pumpEventQueue();

      expect(states, [
        const SyncSignedIn(_user),
        const SyncSignedIn(_user, statusRead: true),
      ]);
      await bloc.close();
    });

    test('starts from the status the engine already holds', () async {
      final engine = FakeSyncEngine()..current = pulling;
      final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);

      expect(
        states.last,
        const SyncSignedIn(_user, status: pulling, statusRead: true),
      );
      await bloc.close();
    });

    test('a refresh keeps the engine-owned fields over the reader\'s, a '
        'showing noAccess included', () async {
      final reader = _FakeStatusReader()..pendingCount = 4;
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(
        user: _user,
        reader: reader,
        engine: engine,
      );
      final failure = SyncFailureInfo(
        SyncGatewayFailure.permissionDenied,
        at: DateTime.utc(2026, 10, 24, 9),
      );
      engine.emit(
        SyncStatus(
          pendingCount: 4,
          pause: SyncPause.noAccess,
          lastFailure: failure,
          parkedCount: 2,
          downloadedRows: 7,
          updating: true,
          updatingSending: true,
          updatingTotal: 30,
          updatingSent: 12,
          lastPullAt: DateTime.utc(2026, 10, 24, 8),
        ),
      );
      await pumpEventQueue();

      reader.pendingCount = 5;
      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      final status = (states.last as SyncSignedIn).status;
      expect(status.pendingCount, 5, reason: "the reader's own field");
      expect(status.pause, SyncPause.noAccess);
      expect(status.lastFailure, failure);
      expect(status.parkedCount, 2);
      expect(status.downloadedRows, 7);
      expect(status.updating, isTrue);
      expect(status.updatingSending, isTrue);
      expect(status.updatingTotal, 30);
      expect(status.updatingSent, 12);
      expect(status.lastPullAt, DateTime.utc(2026, 10, 24, 8));
      await bloc.close();
    });

    test('a refresh takes the reader\'s account pause when the engine holds '
        'none of its own', () async {
      final reader = _FakeStatusReader();
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(
        user: _user,
        reader: reader,
        engine: engine,
      );
      engine.emit(pulling);
      await pumpEventQueue();

      reader.pause = SyncPause.accountMismatch;
      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      final status = (states.last as SyncSignedIn).status;
      expect(status.pause, SyncPause.accountMismatch);
      expect(status.activity, SyncActivity.pulling);
      await bloc.close();
    });

    test('after a sign-out a stale engine noAccess does not show, neither in '
        'the account state nor on a refresh (S4a review L10)', () async {
      final reader = _FakeStatusReader();
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(
        user: _user,
        reader: reader,
        engine: engine,
      );
      engine.emit(const SyncStatus(pause: SyncPause.noAccess));
      await pumpEventQueue();
      expect((states.last as SyncSignedIn).status.pause, SyncPause.noAccess);

      reader.pause = SyncPause.signedOut;
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect((states.last as SyncSignedOut).status.pause, SyncPause.signedOut);

      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();
      expect((states.last as SyncSignedOut).status.pause, SyncPause.signedOut);
      await bloc.close();
    });

    for (final pause in const [SyncPause.noAccess, SyncPause.spaceDeleted]) {
      test('a showing ${pause.name} survives a re-read of the same '
          'account', () async {
        final reader = _FakeStatusReader();
        final engine = FakeSyncEngine();
        final (bloc, fake, states) = await _pumpBloc(
          user: _user,
          reader: reader,
          engine: engine,
        );
        engine.emit(SyncStatus(pause: pause));
        await pumpEventQueue();

        // The identity re-reports the same account: its status is read anew.
        final before = reader.reads.length;
        fake.emitAuth(_user);
        await pumpEventQueue();

        expect(reader.reads, hasLength(before + 1));
        expect((states.last as SyncSignedIn).status.pause, pause);
        await bloc.close();
      });
    }

    test('a load after a database switch follows the new engine, not the '
        'old', () async {
      final old = FakeSyncEngine();
      final fresh = FakeSyncEngine();
      var engine = old;
      final fake = _FakeAuthService(user: _user);
      final bloc = SyncBloc(authService: fake, engine: () async => engine);
      final states = <SyncState>[];
      bloc.stream.listen(states.add);
      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();

      engine = fresh;
      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();
      old.emit(const SyncStatus(pendingCount: 1));
      await pumpEventQueue();
      expect(states.last, const SyncSignedIn(_user, statusRead: true));
      expect(old.statuses.hasListener, isFalse);

      fresh.emit(pulling);
      await pumpEventQueue();
      expect(
        states.last,
        const SyncSignedIn(_user, status: pulling, statusRead: true),
      );
      await bloc.close();
    });

    test('a refresh after a database switch follows the new engine, not the '
        'old (A1c review R40)', () async {
      final old = FakeSyncEngine();
      final fresh = FakeSyncEngine();
      var engine = old;
      final fake = _FakeAuthService(user: _user);
      final bloc = SyncBloc(authService: fake, engine: () async => engine);
      final states = <SyncState>[];
      bloc.stream.listen(states.add);
      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();

      // The dropped space's own times, which the bloc is showing when the
      // switch happens: laid over the new database's read they would be the
      // other space's sync history (A6 review R112).
      old.emit(SyncStatus(lastPullAt: DateTime.utc(2026, 10, 20)));
      await pumpEventQueue();

      // The Sharing page left mounted under the database settings page: the
      // switch drops the engine, the thunk answers with the new database's,
      // and the page only ever refreshes from here on.
      engine = fresh;
      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      expect(
        (states.last as SyncSignedIn).status.lastPullAt,
        isNull,
        reason: "the first refresh already reads the new engine's status",
      );
      old.emit(const SyncStatus(pendingCount: 1));
      await pumpEventQueue();
      expect(old.statuses.hasListener, isFalse);
      expect(states.last, const SyncSignedIn(_user, statusRead: true));

      fresh.emit(pulling);
      await pumpEventQueue();
      expect(
        states.last,
        const SyncSignedIn(_user, status: pulling, statusRead: true),
      );
      await bloc.close();
    });

    test('a dead engine leaves the account as it is, and the next load '
        'follows it again', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);
      await engine.dispose();
      await pumpEventQueue();
      expect(states.last, const SyncSignedIn(_user, statusRead: true));

      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();

      expect(states.last, const SyncSignedIn(_user, statusRead: true));
      await bloc.close();
    });

    test('"Sync now" runs the engine', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, _) = await _pumpBloc(user: _user, engine: engine);

      bloc.add(const SyncNowRequested());
      await pumpEventQueue();

      expect(engine.calls, ['syncNow']);
      await bloc.close();
    });

    test('"Sync now" without an engine does nothing', () async {
      final (bloc, _, states) = await _pumpBloc(user: _user);

      bloc.add(const SyncNowRequested());
      await pumpEventQueue();

      expect(states, [
        const SyncSignedIn(_user),
        const SyncSignedIn(_user, statusRead: true),
      ]);
      await bloc.close();
    });

    test('closing stops following the status', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, _) = await _pumpBloc(user: _user, engine: engine);
      expect(engine.statuses.hasListener, isTrue);

      await bloc.close();

      expect(engine.statuses.hasListener, isFalse);
    });

    test('is never resolved on an unavailable binding', () async {
      var asked = 0;
      final bloc = SyncBloc(
        authService: _FakeAuthService(available: false),
        engine: () async {
          asked++;
          return FakeSyncEngine();
        },
      );
      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();

      expect(asked, 0);
      await bloc.close();
    });
  });

  group('the bind flow', () {
    final picking = SyncBindPicking(
      spaces: const [_space],
      holdsData: true,
      heldBy: {
        const SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-2'): 'errands',
      },
    );

    /// A bloc signed in as [_user] over [spaces], with an engine and a reader
    /// whose reads it counts — with the picker up when [picking], the only
    /// flow a choice is taken from — reading [binding] and [pause].
    Future<
      (
        SyncBloc,
        _FakeAuthService,
        List<SyncState>,
        FakeSyncEngine,
        _FakeStatusReader,
      )
    >
    pumpBinding(
      _FakeSpaceService spaces, {
      AppUser? user = _user,
      bool picking = false,
      SyncBinding? binding,
      SyncPause pause = SyncPause.none,
    }) async {
      final engine = FakeSyncEngine();
      final reader = _FakeStatusReader()
        ..binding = binding
        ..pause = pause;
      final (bloc, auth, states) = await _pumpBloc(
        user: user,
        reader: reader,
        engine: engine,
        spaces: spaces,
      );
      if (picking) {
        final error = spaces.error;
        spaces.error = null;
        bloc.add(const SyncThisDatabaseRequested());
        await pumpEventQueue();
        expect(bloc.state, isA<SyncSignedIn>());
        expect((bloc.state as SyncSignedIn).flow, isA<SyncBindPicking>());
        spaces
          ..error = error
          ..calls.clear();
        engine.calls.clear();
      }
      states.clear();
      reader.reads.clear();
      return (bloc, auth, states, engine, reader);
    }

    List<SyncBindFlow> flows(List<SyncState> states) => [
      for (final state in states)
        switch (state) {
          SyncSignedIn(:final flow) || SyncSignedOut(:final flow) => flow,
          _ => throw StateError('$state carries no flow'),
        },
    ];

    test('"Sync this database" bound in the tap: checking, then idle, the '
        'engine restarted and the status read again', () async {
      final spaces = _FakeSpaceService()
        ..startResult = SyncBindStartBound(_space.ref);
      final (bloc, _, states, engine, reader) = await pumpBinding(spaces);
      engine.calls.clear();

      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();

      expect(spaces.calls, ['start:uid-1']);
      expect(flows(states).first, const SyncBindChecking());
      expect(flows(states).last, const SyncBindIdle());
      expect(engine.calls, ['stop', 'start']);
      expect(reader.reads, ['uid-1']);
      await bloc.close();
    });

    test('"Sync this database" with a choice to make shows the picker\'s '
        'data', () async {
      final spaces = _FakeSpaceService()
        ..startResult = SyncBindStartPick(
          spaces: [_space],
          holdsData: true,
          heldBy: picking.heldBy,
        );
      final (bloc, _, states, engine, _) = await pumpBinding(spaces);
      engine.calls.clear();

      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();

      expect(flows(states), [const SyncBindChecking(), picking]);
      expect(
        engine.calls,
        ['stop', 'start'],
        reason: 'stopped while the tap could bind, started again after',
      );
      await bloc.close();
    });

    test('the picker survives an engine status and a refresh', () async {
      final spaces = _FakeSpaceService()
        ..startResult = SyncBindStartPick(
          spaces: [_space],
          holdsData: true,
          heldBy: picking.heldBy,
        );
      final (bloc, _, states, engine, _) = await pumpBinding(spaces);
      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();

      engine.emit(const SyncStatus(pendingCount: 3));
      await pumpEventQueue();
      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();

      expect(flows(states).last, picking);
      expect(bloc.state, isA<SyncSignedIn>());
      await bloc.close();
    });

    for (final (label, error, failed) in [
      (
        'a typed failure',
        const SyncSpaceException(SyncBindFailure.offline),
        const SyncBindFailed(SyncBindFailure.offline),
      ),
      (
        'a refusal naming the holder',
        const SyncSpaceException(
          SyncBindFailure.spaceHeldByAnotherDatabase,
          holderDatabase: 'errands',
        ),
        const SyncBindFailed(
          SyncBindFailure.spaceHeldByAnotherDatabase,
          holderDatabase: 'errands',
        ),
      ),
      (
        'an untyped error',
        StateError('boom'),
        const SyncBindFailed(SyncBindFailure.unknown),
      ),
    ]) {
      test('$label fails the tap with its reason, the running engine started '
          'again and the status read', () async {
        final spaces = _FakeSpaceService()..error = error;
        final (bloc, _, states, engine, reader) = await pumpBinding(spaces);
        engine
          ..isStarted = true
          ..calls.clear();

        bloc.add(const SyncThisDatabaseRequested());
        await pumpEventQueue();

        expect(flows(states), [const SyncBindChecking(), failed]);
        expect(engine.calls, ['stop', 'start']);
        expect(reader.reads, ['uid-1']);
        await bloc.close();
      });
    }

    test('a second tap while the first is checking is ignored', () async {
      final spaces = _FakeSpaceService()..gate = Completer<void>();
      final gate = spaces.gate!;
      final (bloc, _, _, _, _) = await pumpBinding(spaces);

      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect(spaces.calls, ['start:uid-1']);
      await bloc.close();
    });

    test('an account change while checking drops the flow with the old '
        'account', () async {
      final spaces = _FakeSpaceService()
        ..gate = Completer<void>()
        ..startResult = SyncBindStartPick(spaces: [_space], holdsData: true);
      final gate = spaces.gate!;
      final (bloc, auth, _, _, _) = await pumpBinding(spaces);

      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      auth.emitAuth(_partner);
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect(bloc.state, isA<SyncSignedIn>());
      final shown = bloc.state as SyncSignedIn;
      expect(shown.user, _partner);
      expect(shown.flow, const SyncBindIdle());
      await bloc.close();
    });

    for (final (label, event, call, done) in [
      (
        'merge into the space',
        const MergeIntoSpaceRequested(_space),
        'merge:space-1:uid-1',
        const SyncBindIdle(),
      ),
      (
        'download the space into a new database',
        const DownloadSpaceRequested(_space),
        'download:space-1:uid-1',
        const SyncBindIdle(switchedToDatabase: 'downloaded'),
      ),
      (
        'upload as a new space under this database\'s name',
        const UploadAsNewSpaceRequested(),
        'upload:null:uid-1',
        const SyncBindIdle(),
      ),
      (
        'upload as a new space under a name',
        const UploadAsNewSpaceRequested(name: 'Tablet'),
        'upload:Tablet:uid-1',
        const SyncBindIdle(),
      ),
    ]) {
      test('the picker\'s "$label": binding, then $done, the engine '
          'restarted', () async {
        final spaces = _FakeSpaceService();
        final (bloc, _, states, engine, reader) = await pumpBinding(
          spaces,
          picking: true,
        );

        bloc.add(event);
        await pumpEventQueue();

        expect(spaces.calls, [call]);
        expect(flows(states).first, const SyncBindBinding());
        expect(flows(states).last, done);
        expect(engine.calls, ['stop', 'start']);
        expect(reader.reads, ['uid-1']);
        await bloc.close();
      });
    }

    test('a failed choice keeps its reason until dismissed', () async {
      final spaces = _FakeSpaceService()
        ..error = const SyncSpaceException(SyncBindFailure.quotaExhausted);
      final (bloc, _, states, _, _) = await pumpBinding(spaces, picking: true);

      bloc.add(const MergeIntoSpaceRequested(_space));
      await pumpEventQueue();
      expect(
        flows(states).last,
        const SyncBindFailed(SyncBindFailure.quotaExhausted),
      );

      bloc.add(const BindFlowDismissed());
      await pumpEventQueue();
      expect(flows(states).last, const SyncBindIdle());
      await bloc.close();
    });

    test('dismissing the picker goes back to idle; dismissing idle emits '
        'nothing', () async {
      final spaces = _FakeSpaceService();
      final (bloc, _, states, _, _) = await pumpBinding(spaces);
      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();

      bloc.add(const BindFlowDismissed());
      await pumpEventQueue();
      expect(flows(states).last, const SyncBindIdle());

      final count = states.length;
      bloc.add(const BindFlowDismissed());
      await pumpEventQueue();
      expect(states, hasLength(count));
      await bloc.close();
    });

    test('dismissing a download\'s notice keeps the database, drops the '
        'notice', () async {
      final spaces = _FakeSpaceService();
      final (bloc, _, states, _, _) = await pumpBinding(spaces, picking: true);
      bloc.add(const DownloadSpaceRequested(_space));
      await pumpEventQueue();

      bloc.add(const BindFlowDismissed());
      await pumpEventQueue();

      expect(flows(states).last, const SyncBindIdle());
      await bloc.close();
    });

    for (final (label, user, pause) in [
      ('signed in', _user, SyncPause.none),
      ('paused on another account (D5 A)', _user, SyncPause.accountMismatch),
      ('signed out (D5 A)', null, SyncPause.signedOut),
    ]) {
      test('"Stop syncing" $label: stopping, then idle, the engine restarted '
          'and the status read again', () async {
        final spaces = _FakeSpaceService();
        final (bloc, _, states, engine, reader) = await pumpBinding(
          spaces,
          user: user,
        );
        reader.pause = pause;
        engine.calls.clear();

        bloc.add(const StopSyncingRequested());
        await pumpEventQueue();

        expect(spaces.calls, ['stop']);
        expect(flows(states).first, const SyncBindStopping());
        expect(flows(states).last, const SyncBindIdle());
        expect(engine.calls, ['stop', 'start']);
        expect(reader.reads, [user?.uid]);
        expect(
          bloc.state,
          user == null ? isA<SyncSignedOut>() : isA<SyncSignedIn>(),
        );
        await bloc.close();
      });
    }

    test('a failed stop signed out shows its reason', () async {
      final spaces = _FakeSpaceService()..error = StateError('disk full');
      final (bloc, _, states, _, _) = await pumpBinding(spaces, user: null);

      bloc.add(const StopSyncingRequested());
      await pumpEventQueue();

      expect(flows(states), [
        const SyncBindStopping(),
        const SyncBindFailed(SyncBindFailure.unknown),
      ]);
      await bloc.close();
    });

    group('deleting the cloud copy (cloud-multi-user-roadmap §5)', () {
      const left = SyncPendingDeletion(
        space: SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1'),
        spaceName: 'Phone',
      );
      const bound = SyncBinding(
        spaceId: 'space-1',
        ownerUid: 'uid-1',
        accountUid: 'uid-1',
      );

      const pendingLeft = SyncDeletionStatus(
        accountUid: 'uid-1',
        pending: [left],
      );

      test('"Delete cloud copy" stops the engine first, ends idle as soon as '
          'the service returns — no count — and starts the engine again on '
          'the status read again', () async {
        final spaces = _FakeSpaceService();
        final (bloc, _, states, engine, reader) = await pumpBinding(
          spaces,
          binding: bound,
        );
        List<String>? toldBeforeChange;
        spaces.onStep = (_) => toldBeforeChange = List.of(engine.calls);

        bloc.add(const DeleteCloudCopyRequested());
        await pumpEventQueue();

        expect(spaces.calls, ['delete']);
        expect(toldBeforeChange, ['stop']);
        expect(engine.calls, ['stop', 'start']);
        expect(flows(states), [const SyncBindDeleting(), const SyncBindIdle()]);
        expect(reader.reads, ['uid-1']);
        expect(bloc.state.stepInFlight, isFalse);
        await bloc.close();
      });

      test('a delete that fails ends failed as a deletion', () async {
        final spaces = _FakeSpaceService()
          ..error = const SyncSpaceException(SyncBindFailure.offline);
        final (bloc, _, states, engine, _) = await pumpBinding(
          spaces,
          binding: bound,
        );
        engine.isStarted = true;

        bloc.add(const DeleteCloudCopyRequested());
        await pumpEventQueue();

        expect(flows(states), [
          const SyncBindDeleting(),
          const SyncBindFailed(SyncBindFailure.offline, deleting: true),
        ]);
        expect(engine.calls, ['stop', 'start']);
        await bloc.close();
      });

      test('"Finish deleting" asks the service with something pending and '
          'nothing running: no step, no engine stop, no emit', () async {
        final spaces = _FakeSpaceService()..deletions['uid-1'] = pendingLeft;
        final (bloc, _, states, engine, reader) = await pumpBinding(spaces);
        expect((bloc.state as SyncSignedIn).deletion, pendingLeft);
        engine.calls.clear();

        bloc.add(const FinishDeletingRequested());
        await pumpEventQueue();

        expect(spaces.calls, ['finish:uid-1']);
        expect(engine.calls, isEmpty);
        expect(reader.reads, isEmpty);
        expect(states, isEmpty);
        await bloc.close();
      });

      for (final (label, deletion) in [
        ('nothing pending', const SyncDeletionStatus(accountUid: 'uid-1')),
        (
          'a run in flight',
          const SyncDeletionStatus(
            accountUid: 'uid-1',
            pending: [left],
            running: true,
          ),
        ),
      ]) {
        test('"Finish deleting" with $label asks nothing', () async {
          final spaces = _FakeSpaceService()..deletions['uid-1'] = deletion;
          final (bloc, _, states, engine, _) = await pumpBinding(spaces);
          expect((bloc.state as SyncSignedIn).deletion, deletion);
          engine.calls.clear();

          bloc.add(const FinishDeletingRequested());
          await pumpEventQueue();

          expect(spaces.calls, isEmpty);
          expect(engine.calls, isEmpty);
          expect(states, isEmpty);
          await bloc.close();
        });
      }

      for (final event in const [
        DeleteCloudCopyRequested(),
        FinishDeletingRequested(),
      ]) {
        test('${event.runtimeType} during another step is refused', () async {
          final spaces = _FakeSpaceService()
            ..gate = Completer<void>()
            ..deletions['uid-1'] = pendingLeft;
          final (bloc, _, _, _, _) = await pumpBinding(spaces);
          final stopping = spaces.gate!;

          bloc.add(const StopSyncingRequested());
          await pumpEventQueue();
          bloc.add(event);
          await pumpEventQueue();
          stopping.complete();
          await pumpEventQueue();

          expect(spaces.calls, ['stop']);
          await bloc.close();
        });

        test('${event.runtimeType} signed out does nothing: only the owner '
            'deletes', () async {
          final spaces = _FakeSpaceService();
          final (bloc, _, states, engine, _) = await pumpBinding(
            spaces,
            user: null,
          );
          engine.calls.clear();

          bloc.add(event);
          await pumpEventQueue();

          expect(spaces.calls, isEmpty);
          expect(engine.calls, isEmpty);
          expect(states, isEmpty);
          await bloc.close();
        });
      }

      // Review S6: by the page's own rule, a request that can do nothing
      // runs no step — the engine is never stopped, so its pause and
      // back-off stand.
      for (final (label, binding, pause) in [
        ('a delete with no binding', null, SyncPause.none),
        for (final pause in const [
          SyncPause.accountMismatch,
          SyncPause.appOutdated,
          SyncPause.spaceDeleted,
        ])
          ('a delete under the ${pause.name} pause', bound, pause),
      ]) {
        test('$label is refused: no step, no engine stop, no emit', () async {
          const event = DeleteCloudCopyRequested();
          final spaces = _FakeSpaceService();
          final (bloc, _, states, engine, _) = await pumpBinding(
            spaces,
            binding: binding,
            pause: pause,
          );
          expect((bloc.state as SyncSignedIn).status.pause, pause);
          engine.calls.clear();

          bloc.add(event);
          await pumpEventQueue();

          expect(spaces.calls, isEmpty);
          expect(engine.calls, isEmpty);
          expect(states, isEmpty);
          await bloc.close();
        });
      }

      for (final pause in const [
        SyncPause.noAccess,
        SyncPause.quotaExhausted,
      ]) {
        test('a delete under the ${pause.name} pause runs: a copy that will '
            'not sync may still be deleted', () async {
          final spaces = _FakeSpaceService();
          final (bloc, _, _, engine, _) = await pumpBinding(
            spaces,
            binding: bound,
            pause: pause,
          );
          engine.calls.clear();

          bloc.add(const DeleteCloudCopyRequested());
          await pumpEventQueue();

          expect(spaces.calls, ['delete']);
          expect(engine.calls, ['stop', 'start']);
          await bloc.close();
        });
      }

      test('from a failed sign-out a refused delete emits nothing: the rule '
          'is judged before the account is put back', () async {
        final spaces = _FakeSpaceService();
        final (bloc, auth, states, engine, _) = await pumpBinding(spaces);
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        await pumpEventQueue();
        expect(bloc.state, isA<SyncFailure>());
        states.clear();
        engine.calls.clear();

        bloc.add(const DeleteCloudCopyRequested());
        await pumpEventQueue();

        expect(states, isEmpty);
        expect(spaces.calls, isEmpty);
        expect(engine.calls, isEmpty);
        await bloc.close();
      });

      test('from a failed sign-out an allowed delete puts the account back '
          'and runs', () async {
        final spaces = _FakeSpaceService();
        final (bloc, auth, states, _, _) = await pumpBinding(
          spaces,
          binding: bound,
        );
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        await pumpEventQueue();
        expect(bloc.state, isA<SyncFailure>());
        states.clear();

        bloc.add(const DeleteCloudCopyRequested());
        await pumpEventQueue();

        expect(spaces.calls, ['delete']);
        expect(states.first, isA<SyncSignedIn>());
        expect(flows(states), contains(const SyncBindDeleting()));
        expect(flows(states).last, const SyncBindIdle());
        await bloc.close();
      });
    });

    group('following the deletion status (cloud-multi-user-roadmap §5)', () {
      const left = SyncPendingDeletion(
        space: SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1'),
        spaceName: 'Phone',
      );

      /// The deletion statuses [states] carried, a repeat dropped.
      List<SyncDeletionStatus?> carried(List<SyncState> states) {
        final seen = <SyncDeletionStatus?>[];
        for (final state in states.whereType<SyncSignedIn>()) {
          if (seen.isEmpty || seen.last != state.deletion) {
            seen.add(state.deletion);
          }
        }
        return seen;
      }

      test(
        'reaches the state in order, for the signed-in account only',
        () async {
          final spaces = _FakeSpaceService()
            ..deletions['uid-1'] = const SyncDeletionStatus(
              accountUid: 'uid-1',
              pending: [left],
            );
          final (bloc, _, states) = await _pumpBloc(
            user: _user,
            reader: _FakeStatusReader(),
            spaces: spaces,
          );
          expect(
            (bloc.state as SyncSignedIn).deletion,
            spaces.deletions['uid-1'],
          );
          states.clear();
          const running = SyncDeletionStatus(
            accountUid: 'uid-1',
            pending: [left],
            running: true,
          );
          const counting = SyncDeletionStatus(
            accountUid: 'uid-1',
            pending: [left],
            running: true,
            removed: 20,
          );
          const ended = SyncDeletionStatus(accountUid: 'uid-1', removed: 31);

          spaces
            ..publish(running)
            ..publish(const SyncDeletionStatus(accountUid: 'uid-2'))
            ..publish(counting)
            ..publish(ended);
          await pumpEventQueue();

          expect(carried(states), [running, counting, ended]);
          await bloc.close();
        },
      );

      test('a status that arrives while the sync status is read never costs '
          'that read: it lands on the state as the deletion left it (review '
          'G1)', () async {
        const waiting = SyncDeletionStatus(
          accountUid: 'uid-1',
          pending: [left],
        );
        final held = Completer<void>();
        final reader = _FakeStatusReader()
          ..pendingCount = 4
          ..stall = held;
        final spaces = _FakeSpaceService()..deletions['uid-1'] = waiting;
        final (bloc, _, _) = await _pumpBloc(
          user: _user,
          reader: reader,
          spaces: spaces,
        );
        // The first status landed while the read is still held.
        expect((bloc.state as SyncSignedIn).deletion, waiting);
        expect((bloc.state as SyncSignedIn).statusRead, isFalse);

        held.complete();
        await pumpEventQueue();

        final shown = bloc.state as SyncSignedIn;
        expect(shown.statusRead, isTrue);
        expect(shown.status.pendingCount, 4);
        expect(shown.deletion, waiting);
        await bloc.close();
      });

      const running = SyncDeletionStatus(
        accountUid: 'uid-1',
        pending: [left],
        running: true,
      );
      const counting = SyncDeletionStatus(
        accountUid: 'uid-1',
        pending: [left],
        running: true,
        removed: 20,
      );
      const pendingLeft = SyncDeletionStatus(
        accountUid: 'uid-1',
        pending: [left],
      );
      const bound = SyncBinding(
        spaceId: 'space-1',
        ownerUid: 'uid-1',
        accountUid: 'uid-1',
      );

      test('a read begun on a state a status re-stamped survives the next '
          're-stamp too: the same account reported again reads on it (review '
          'K2)', () async {
        final reader = _FakeStatusReader()..pendingCount = 1;
        final spaces = _FakeSpaceService();
        final (bloc, auth, _) = await _pumpBloc(
          user: _user,
          reader: reader,
          spaces: spaces,
        );
        spaces.publish(running);
        await pumpEventQueue();
        final held = Completer<void>();
        reader
          ..pendingCount = 9
          ..gate = held;

        // An equal account state is dropped, so the read is begun on the
        // re-stamp still on screen.
        auth.emitAuth(_user);
        await pumpEventQueue();
        spaces.publish(counting);
        await pumpEventQueue();
        held.complete();
        await pumpEventQueue();

        final shown = bloc.state as SyncSignedIn;
        expect(shown.status.pendingCount, 9);
        expect(shown.deletion, counting);
        await bloc.close();
      });

      group('a read begun on a re-stamp still never lands on', () {
        /// The account loaded and re-stamped, a read for it held from a
        /// same-account report, then [moveOn] and another re-stamp; the
        /// held read is released last, answering [stale] pending rows.
        Future<SyncBloc> heldRead(
          Future<void> Function(
            SyncBloc bloc,
            _FakeAuthService auth,
            _FakeSpaceService spaces,
          )
          moveOn, {
          required int stale,
        }) async {
          final reader = _FakeStatusReader()
            ..binding = bound
            ..pendingCount = 1;
          final spaces = _FakeSpaceService();
          final (bloc, auth, _) = await _pumpBloc(
            user: _user,
            reader: reader,
            engine: FakeSyncEngine(),
            spaces: spaces,
          );
          spaces.publish(running);
          await pumpEventQueue();
          final held = Completer<void>();
          reader.gate = held;
          auth.emitAuth(_user);
          await pumpEventQueue();

          await moveOn(bloc, auth, spaces);
          spaces.publish(counting);
          await pumpEventQueue();
          reader.pendingCount = stale;
          held.complete();
          await pumpEventQueue();
          return bloc;
        }

        test('another account\'s state', () async {
          final bloc = await heldRead((bloc, auth, spaces) async {
            auth.emitAuth(_partner);
            await pumpEventQueue();
          }, stale: 9);

          expect((bloc.state as SyncSignedIn).user, _partner);
          await bloc.close();
        });

        test('a newer flow', () async {
          final step = Completer<void>();
          final bloc = await heldRead((bloc, auth, spaces) async {
            spaces.gate = step;
            bloc.add(const DeleteCloudCopyRequested());
            await pumpEventQueue();
            expect((bloc.state as SyncSignedIn).flow, const SyncBindDeleting());
          }, stale: 9);

          final shown = bloc.state as SyncSignedIn;
          expect(shown.flow, const SyncBindDeleting());
          expect(shown.status.pendingCount, 1);
          step.complete();
          await pumpEventQueue();
          await bloc.close();
        });

        test('a closed bloc', () async {
          final states = <SyncState>[];
          final bloc = await heldRead((bloc, auth, spaces) async {
            bloc.stream.listen(states.add);
            await bloc.close();
          }, stale: 9);

          expect(bloc.isClosed, isTrue);
          expect(states, isEmpty);
        });
      });

      test('a failed sign-out carries the account\'s deletion status and '
          'follows it: the run\'s progress and end reach the failure itself '
          '(review K3)', () async {
        final spaces = _FakeSpaceService()..deletions['uid-1'] = pendingLeft;
        final (bloc, auth, states, _, _) = await pumpBinding(spaces);
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        await pumpEventQueue();
        expect((bloc.state as SyncFailure).deletion, pendingLeft);
        states.clear();

        const ended = SyncDeletionStatus(accountUid: 'uid-1', removed: 31);
        spaces
          ..publish(running)
          ..publish(counting)
          ..publish(ended);
        await pumpEventQueue();

        expect(states, [
          for (final deletion in const [running, counting, ended])
            SyncFailure(
              AuthError.unknown,
              action: SyncAccountAction.signOut,
              user: _user,
              deletion: deletion,
            ),
        ]);
        await bloc.close();
      });

      test('"Finish deleting" from a failed sign-out is judged on the live '
          'status: asked while waiting, refused once a run is in flight, and '
          'the failure stays on screen (review K3)', () async {
        final spaces = _FakeSpaceService()..deletions['uid-1'] = pendingLeft;
        final (bloc, auth, states, engine, _) = await pumpBinding(spaces);
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        await pumpEventQueue();
        states.clear();
        engine.calls.clear();

        bloc.add(const FinishDeletingRequested());
        await pumpEventQueue();
        expect(spaces.calls, ['finish:uid-1']);
        expect(states, isEmpty);

        spaces.publish(running);
        await pumpEventQueue();
        bloc.add(const FinishDeletingRequested());
        await pumpEventQueue();

        expect(spaces.calls, ['finish:uid-1']);
        expect(engine.calls, isEmpty);
        expect(bloc.state, isA<SyncFailure>());
        await bloc.close();
      });

      test('the following ends on an account change and on sign-out, and '
          'the next account never shows the last one\'s status', () async {
        const theirs = SyncDeletionStatus(accountUid: 'uid-1', pending: [left]);
        final spaces = _FakeSpaceService()..deletions['uid-1'] = theirs;
        final (bloc, auth, states) = await _pumpBloc(
          user: _user,
          reader: _FakeStatusReader(),
          spaces: spaces,
        );
        expect(spaces.followed, ['uid-1']);
        states.clear();

        auth.emitAuth(_partner);
        await pumpEventQueue();

        expect(spaces.followed, ['uid-1', 'uid-2']);
        expect(spaces.unfollowed, ['uid-1']);
        expect(states, isNotEmpty);
        for (final state in states) {
          expect((state as SyncSignedIn).deletion, isNot(theirs));
        }
        spaces.publish(
          const SyncDeletionStatus(
            accountUid: 'uid-1',
            pending: [left],
            running: true,
          ),
        );
        await pumpEventQueue();
        expect(
          (bloc.state as SyncSignedIn).deletion,
          const SyncDeletionStatus(accountUid: 'uid-2'),
        );

        auth.emitAuth(null);
        await pumpEventQueue();

        expect(bloc.state, isA<SyncSignedOut>());
        expect(spaces.unfollowed, ['uid-1', 'uid-2']);
        expect(spaces.followed, ['uid-1', 'uid-2']);
        await bloc.close();
      });

      test('the following ends on close', () async {
        final spaces = _FakeSpaceService();
        final (bloc, _, _) = await _pumpBloc(
          user: _user,
          reader: _FakeStatusReader(),
          spaces: spaces,
        );

        await bloc.close();

        expect(spaces.followed, ['uid-1']);
        expect(spaces.unfollowed, ['uid-1']);
      });

      test('a second bloc — the drawer\'s beside the page\'s — sees the same '
          'status', () async {
        final spaces = _FakeSpaceService();
        final (first, _, _) = await _pumpBloc(
          user: _user,
          reader: _FakeStatusReader(),
          spaces: spaces,
        );
        final (second, _, _) = await _pumpBloc(
          user: _user,
          reader: _FakeStatusReader(),
          spaces: spaces,
        );
        const running = SyncDeletionStatus(
          accountUid: 'uid-1',
          pending: [left],
          running: true,
          removed: 4,
        );

        spaces.publish(running);
        await pumpEventQueue();

        expect((first.state as SyncSignedIn).deletion, running);
        expect((second.state as SyncSignedIn).deletion, running);
        await first.close();
        await second.close();
      });

      test('the deletions are never followed signed out, and followed at a '
          'sign-in for the account signed in', () async {
        final spaces = _FakeSpaceService();
        final (bloc, auth, _) = await _pumpBloc(
          reader: _FakeStatusReader(),
          spaces: spaces,
        );
        expect(bloc.state, isA<SyncSignedOut>());
        expect(spaces.followed, isEmpty);

        auth.signInResult = _user;
        bloc.add(const SignInRequested());
        await pumpEventQueue();

        expect(spaces.followed, ['uid-1']);
        await bloc.close();
      });
    });

    for (final (label, event, picking, call, busy, done) in [
      (
        '"Sync this database" bound in the tap',
        const SyncThisDatabaseRequested(),
        false,
        'start:uid-1',
        const SyncBindChecking(),
        const SyncBindIdle(),
      ),
      (
        'a merge',
        const MergeIntoSpaceRequested(_space),
        true,
        'merge:space-1:uid-1',
        const SyncBindBinding(),
        const SyncBindIdle(),
      ),
      (
        'a download',
        const DownloadSpaceRequested(_space),
        true,
        'download:space-1:uid-1',
        const SyncBindBinding(),
        const SyncBindIdle(switchedToDatabase: 'downloaded'),
      ),
      (
        'an upload',
        const UploadAsNewSpaceRequested(),
        true,
        'upload:null:uid-1',
        const SyncBindBinding(),
        const SyncBindIdle(),
      ),
      (
        '"Stop syncing"',
        const StopSyncingRequested(),
        false,
        'stop',
        const SyncBindStopping(),
        const SyncBindIdle(),
      ),
    ]) {
      test('$label stops the engine before the binding changes and settles '
          'in one emit, with the status read after the restart', () async {
        final spaces = _FakeSpaceService();
        final (bloc, _, states, engine, reader) = await pumpBinding(
          spaces,
          picking: picking,
        );
        spaces.startResult = SyncBindStartBound(_space.ref);
        List<String>? toldBeforeChange;
        spaces.onStep = (_) => toldBeforeChange = List.of(engine.calls);
        reader.pendingCount = 4;

        bloc.add(event);
        await pumpEventQueue();

        expect(spaces.calls, [call]);
        expect(toldBeforeChange, ['stop']);
        expect(engine.calls, ['stop', 'start']);
        expect(flows(states), [busy, done], reason: 'no idle before the read');
        expect((states.last as SyncSignedIn).status.pendingCount, 4);
        await bloc.close();
      });
    }

    test('a download stops the engine it leaves and starts the one its '
        'switch rebuilt', () async {
      final spaces = _FakeSpaceService();
      final left = FakeSyncEngine();
      final rebuilt = FakeSyncEngine();
      var current = left;
      final bloc = SyncBloc(
        authService: _FakeAuthService(user: _user),
        statusReader: () => _FakeStatusReader(),
        engine: () async => current,
        spaces: spaces,
      );
      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();
      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      left.calls.clear();
      spaces.onStep = (call) {
        if (call.startsWith('download')) current = rebuilt;
      };

      bloc.add(const DownloadSpaceRequested(_space));
      await pumpEventQueue();

      expect(left.calls, ['stop']);
      expect(rebuilt.calls, ['stop', 'start']);
      expect(rebuilt.isStarted, isTrue);
      await bloc.close();
    });

    for (final (running, engineLine) in [
      (true, 'starts the running engine again'),
      (false, 'leaves a stopped engine stopped'),
    ]) {
      test('a failed choice $engineLine and shows its reason over the status '
          'read again', () async {
        final spaces = _FakeSpaceService()
          ..error = const SyncSpaceException(SyncBindFailure.offline);
        final (bloc, _, states, engine, reader) = await pumpBinding(
          spaces,
          picking: true,
        );
        engine.isStarted = running;
        reader.pendingCount = 4;

        bloc.add(const MergeIntoSpaceRequested(_space));
        await pumpEventQueue();

        expect(engine.calls, running ? ['stop', 'start'] : ['stop']);
        expect(flows(states), [
          const SyncBindBinding(),
          const SyncBindFailed(SyncBindFailure.offline),
        ]);
        expect(reader.reads, ['uid-1']);
        expect((states.last as SyncSignedIn).status.pendingCount, 4);
        await bloc.close();
      });
    }

    test('an account change mid-step does not free it: a second step is '
        'ignored until the first ends', () async {
      final spaces = _FakeSpaceService();
      final (bloc, auth, _, _, _) = await pumpBinding(spaces, picking: true);
      final gate = Completer<void>();
      spaces.gate = gate;

      bloc.add(const MergeIntoSpaceRequested(_space));
      await pumpEventQueue();
      auth.emitAuth(null);
      await pumpEventQueue();
      expect((bloc.state as SyncSignedOut).flow, const SyncBindIdle());
      bloc.add(const StopSyncingRequested());
      await pumpEventQueue();
      auth.emitAuth(_user);
      await pumpEventQueue();
      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();

      expect(spaces.calls, ['merge:space-1:uid-1']);

      gate.complete();
      await pumpEventQueue();
      bloc.add(const StopSyncingRequested());
      await pumpEventQueue();

      expect(spaces.calls, ['merge:space-1:uid-1', 'stop']);
      await bloc.close();
    });

    test('a choice with no picker up is ignored, from idle and from a '
        'failure', () async {
      final spaces = _FakeSpaceService();
      final (bloc, _, states, _, _) = await pumpBinding(spaces);

      bloc
        ..add(const MergeIntoSpaceRequested(_space))
        ..add(const DownloadSpaceRequested(_space))
        ..add(const UploadAsNewSpaceRequested());
      await pumpEventQueue();

      expect(spaces.calls, isEmpty);
      expect(states, isEmpty);

      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      spaces.error = const SyncSpaceException(SyncBindFailure.offline);
      bloc.add(const MergeIntoSpaceRequested(_space));
      await pumpEventQueue();
      expect(flows(states).last, const SyncBindFailed(SyncBindFailure.offline));
      spaces
        ..error = null
        ..calls.clear();
      final count = states.length;

      bloc
        ..add(const MergeIntoSpaceRequested(_space))
        ..add(const DownloadSpaceRequested(_space))
        ..add(const UploadAsNewSpaceRequested());
      await pumpEventQueue();

      expect(spaces.calls, isEmpty);
      expect(states, hasLength(count));
      await bloc.close();
    });

    test(
      'signed out, "Sync this database" and the choices are ignored',
      () async {
        final spaces = _FakeSpaceService();
        final (bloc, _, states, _, _) = await pumpBinding(spaces, user: null);

        bloc
          ..add(const SyncThisDatabaseRequested())
          ..add(const MergeIntoSpaceRequested(_space))
          ..add(const UploadAsNewSpaceRequested());
        await pumpEventQueue();

        expect(spaces.calls, isEmpty);
        expect(states, isEmpty);
        await bloc.close();
      },
    );

    test('without a space service (no sync on this platform) every bind '
        'event is ignored', () async {
      final (bloc, _, states) = await _pumpBloc(user: _user);
      states.clear();

      bloc
        ..add(const SyncThisDatabaseRequested())
        ..add(const StopSyncingRequested())
        ..add(const BindFlowDismissed());
      await pumpEventQueue();

      expect(states, isEmpty);
      await bloc.close();
    });

    test('a sign-out asked for mid-download waits for the step: the switch '
        'is shown, then the sign-out runs (final review U-1)', () async {
      final spaces = _FakeSpaceService();
      final (bloc, auth, states, _, _) = await pumpBinding(
        spaces,
        picking: true,
      );
      final gate = Completer<void>();
      spaces.gate = gate;

      bloc.add(const DownloadSpaceRequested(_space));
      await pumpEventQueue();
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect(auth.signOutCalled, isFalse, reason: 'never mid-step');
      expect(bloc.state, isA<SyncSignedIn>());
      expect(bloc.state.stepInFlight, isTrue);

      gate.complete();
      await pumpEventQueue();

      expect(auth.signOutCalled, isTrue, reason: 'deferred, never dropped');
      final switched = states.indexWhere(
        (s) =>
            s is SyncSignedIn &&
            s.flow == const SyncBindIdle(switchedToDatabase: 'downloaded'),
      );
      final signedOut = states.indexWhere((s) => s is SyncSignedOut);
      expect(switched, isNonNegative);
      expect(signedOut, greaterThan(switched));
      expect(bloc.state.stepInFlight, isFalse);
      await bloc.close();
    });

    test('a sign-in asked for mid-step waits for the step too', () async {
      final spaces = _FakeSpaceService()..gate = Completer<void>();
      final gate = spaces.gate!;
      final (bloc, auth, states, _, _) = await pumpBinding(spaces, user: null);
      auth.signInResult = _user;

      bloc.add(const StopSyncingRequested());
      await pumpEventQueue();
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(states.whereType<SyncSigningIn>(), isEmpty);

      gate.complete();
      await pumpEventQueue();

      final settled = states.indexWhere(
        (s) => s is SyncSignedOut && s.flow == const SyncBindIdle(),
      );
      final signingIn = states.indexWhere((s) => s is SyncSigningIn);
      expect(settled, isNonNegative);
      expect(signingIn, greaterThan(settled));
      expect(bloc.state, isA<SyncSignedIn>());
      await bloc.close();
    });

    test('a session ending mid-download still shows the switch, so the '
        'restart prompt comes, and the signed-out rows read busy until the '
        'step ends (final review U-1, U-5)', () async {
      final spaces = _FakeSpaceService();
      final (bloc, auth, states, _, _) = await pumpBinding(
        spaces,
        picking: true,
      );
      final gate = Completer<void>();
      spaces.gate = gate;

      bloc.add(const DownloadSpaceRequested(_space));
      await pumpEventQueue();
      auth.emitAuth(null);
      await pumpEventQueue();

      expect(bloc.state, isA<SyncSignedOut>());
      expect((bloc.state as SyncSignedOut).flow, const SyncBindIdle());
      expect(bloc.state.stepInFlight, isTrue);

      gate.complete();
      await pumpEventQueue();

      expect(
        states,
        contains(
          const SyncSignedOut(
            flow: SyncBindIdle(switchedToDatabase: 'downloaded'),
          ),
        ),
      );
      expect(bloc.state.stepInFlight, isFalse);

      bloc.add(const BindFlowDismissed());
      await pumpEventQueue();
      expect((bloc.state as SyncSignedOut).flow, const SyncBindIdle());
      await bloc.close();
    });

    test('another account\'s step ending clears the flag on the account '
        'shown', () async {
      final spaces = _FakeSpaceService()
        ..gate = Completer<void>()
        ..startResult = SyncBindStartPick(spaces: [_space], holdsData: true);
      final gate = spaces.gate!;
      final (bloc, auth, _, _, _) = await pumpBinding(spaces);

      bloc.add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      auth.emitAuth(_partner);
      await pumpEventQueue();
      expect(bloc.state.stepInFlight, isTrue);

      gate.complete();
      await pumpEventQueue();

      final shown = bloc.state as SyncSignedIn;
      expect(shown.user, _partner);
      expect(shown.flow, const SyncBindIdle());
      expect(shown.stepInFlight, isFalse);
      await bloc.close();
    });

    /// [body] on the fake clock — the limits elapse, never the wall clock;
    /// the bloc runs against fakes, no Drift — over a bloc signed in as
    /// [_user], with the picker up when [picking]. [resolve] replaces the
    /// engine's resolution.
    void onFakeClock(
      _FakeSpaceService spaces,
      void Function(
        FakeAsync async,
        SyncBloc bloc,
        _FakeAuthService auth,
        List<SyncState> states,
        FakeSyncEngine engine,
        _FakeStatusReader reader,
      )
      body, {
      bool picking = false,
      FakeSyncEngine? engine,
      Future<SyncEngine?> Function()? resolve,
    }) {
      fakeAsync((async) {
        final running = engine ?? FakeSyncEngine();
        final reader = _FakeStatusReader();
        final auth = _FakeAuthService(user: _user);
        final bloc = SyncBloc(
          authService: auth,
          statusReader: () => reader,
          engine: resolve ?? () async => running,
          spaces: spaces,
        );
        final states = <SyncState>[];
        bloc.stream.listen(states.add);
        bloc.add(const LoadSyncStatus());
        async.flushMicrotasks();
        if (picking) {
          bloc.add(const SyncThisDatabaseRequested());
          async.flushMicrotasks();
          expect((bloc.state as SyncSignedIn).flow, isA<SyncBindPicking>());
          spaces.calls.clear();
        }
        states.clear();
        reader.reads.clear();
        running.calls.clear();
        body(async, bloc, auth, states, running, reader);
        if (!bloc.isClosed) bloc.close();
        async.flushMicrotasks();
      });
    }

    /// Longer than any bound the bloc owns: a step this slow is the
    /// gateway's to end, and the page holds until it does.
    const aSlowBind = Duration(minutes: 10);

    test('a merge whose bind takes ten minutes holds the page, refuses a '
        'second step and settles once when it lands — the engine started '
        'once, the status read (reviews RC1, RC1b)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, picking: true, (async, bloc, _, states, engine, r) {
        // Made on the fake clock, so its completion is a fake microtask.
        final gate = Completer<void>();
        spaces.gate = gate;
        engine.isStarted = true;
        bloc.add(const MergeIntoSpaceRequested(_space));
        async.flushMicrotasks();
        async.elapse(aSlowBind);

        expect(flows(states), [const SyncBindBinding()]);
        expect(bloc.state.stepInFlight, isTrue, reason: 'still holding');
        expect(engine.calls, ['stop'], reason: 'no restart mid-change');
        expect(r.reads, isEmpty);

        bloc
          ..add(const SyncThisDatabaseRequested())
          ..add(const StopSyncingRequested());
        async.flushMicrotasks();
        expect(spaces.calls, ['merge:space-1:uid-1']);

        gate.complete();
        async.flushMicrotasks();
        expect(engine.calls, ['stop', 'start']);
        expect(r.reads, ['uid-1']);
        expect(flows(states).last, const SyncBindIdle());
        expect(bloc.state.stepInFlight, isFalse);
      });
    });

    test('a download that takes ten minutes holds the page, refuses a second '
        'step, then ends on the switch (reviews RC1, RC1b)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, picking: true, (async, bloc, _, states, _, _) {
        final gate = Completer<void>();
        spaces.gate = gate;
        bloc.add(const DownloadSpaceRequested(_space));
        async.flushMicrotasks();
        async.elapse(aSlowBind);

        expect(flows(states), [const SyncBindBinding()]);
        expect(bloc.state.stepInFlight, isTrue);
        bloc
          ..add(const SyncThisDatabaseRequested())
          ..add(const StopSyncingRequested());
        async.flushMicrotasks();
        expect(spaces.calls, ['download:space-1:uid-1']);

        gate.complete();
        async.flushMicrotasks();
        expect(
          flows(states).last,
          const SyncBindIdle(switchedToDatabase: 'downloaded'),
        );
        expect(bloc.state.stepInFlight, isFalse);
      });
    });

    test('a bloc closed mid-step still starts the engine when the change '
        'settles (review RC1-2)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, picking: true, (async, bloc, _, _, engine, _) {
        final gate = Completer<void>();
        spaces.gate = gate;
        engine.isStarted = true;
        bloc.add(const MergeIntoSpaceRequested(_space));
        async.flushMicrotasks();
        bloc.close();
        async.flushMicrotasks();
        expect(engine.isStarted, isFalse);

        gate.complete();
        async.flushMicrotasks();
        expect(engine.calls, ['stop', 'start']);
        expect(engine.isStarted, isTrue);
      });
    });

    test('a sign-out that hangs is given up on as a failure the user sees, '
        'and steps are no longer refused (review RC1b-4, RC1c-2)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, _, _, _) {
        auth.signOutGate = Completer<void>();
        bloc.add(const SignOutRequested());
        async.flushMicrotasks();
        bloc.add(const StopSyncingRequested());
        async.flushMicrotasks();
        expect(spaces.calls, isEmpty, reason: 'refused while it is pending');

        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));
        expect(auth.signOutCalled, isTrue);
        // The sign-out's, so the page offers Sign out again, not a sign-in;
        // the account still signed in carries its deletion status (K3).
        expect(
          bloc.state,
          const SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: _user,
            deletion: SyncDeletionStatus(accountUid: 'uid-1'),
          ),
        );

        bloc.add(const StopSyncingRequested());
        async.flushMicrotasks();
        expect(spaces.calls, ['stop']);
      });
    });

    test('the engine\'s status is reported seen only once a state carries '
        'it, never on the reader\'s read alone (review RC2-4)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, _, _, engine, _) {
        expect(bloc.engineStatusSeen, isFalse);
        engine.emit(const SyncStatus(pause: SyncPause.quotaExhausted));
        async.flushMicrotasks();
        expect(bloc.engineStatusSeen, isTrue);
        expect(
          (bloc.state as SyncSignedIn).status.pause,
          SyncPause.quotaExhausted,
        );
      });
    });

    test('a sign-in after a sign-out given up on waits for it to land, so it '
        'is never signed out again (review RC2-2)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, states, _, _) {
        auth.signOutGate = Completer<void>();
        auth.signInResult = _user;
        bloc.add(const SignOutRequested());
        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));
        expect(
          bloc.state,
          const SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: _user,
            deletion: SyncDeletionStatus(accountUid: 'uid-1'),
          ),
        );
        states.clear();

        bloc.add(const SignInRequested());
        async.elapse(const Duration(seconds: 1));
        // The spinner is up, hiding Retry, and Google waits for the sign-out.
        expect(states, [const SyncSigningIn()]);
        expect(auth.signInCalls, 0);

        auth.signOutGate!.complete();
        async.flushMicrotasks();
        expect(auth.signInCalls, 1);
        expect((bloc.state as SyncSignedIn).user, _user);
        expect(auth.currentUser, _user, reason: 'signed out, then in');
      });
    });

    test('three sign-ins while a given-up sign-out still runs start one '
        'Google flow once it lands (review RC2b-1)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, _, _, _) {
        auth.signOutGate = Completer<void>();
        auth.signInResult = _user;
        bloc.add(const SignOutRequested());
        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));

        for (var i = 0; i < 3; i++) {
          bloc.add(const SignInRequested());
          async.elapse(const Duration(milliseconds: 100));
        }
        auth.signOutGate!.complete();
        async.flushMicrotasks();

        expect(auth.signInCalls, 1);
        expect((bloc.state as SyncSignedIn).user, _user);
      });
    });

    test('a sign-in waits for every sign-out given up on, the second chained '
        'behind the first (review RC2b-2)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, _, _, _) {
        final first = Completer<void>();
        final second = Completer<void>();
        auth.signOutGate = first;
        bloc.add(const SignOutRequested());
        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));
        auth.signOutGate = second;
        bloc.add(const SignOutRequested());
        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));
        auth.signInResult = _user;

        bloc.add(const SignInRequested());
        async.flushMicrotasks();
        second.complete();
        async.flushMicrotasks();
        expect(auth.signInCalls, 0, reason: 'the first still runs');

        first.complete();
        async.flushMicrotasks();
        expect(auth.signInCalls, 1);
      });
    });

    test('a sign-in while a given-up sign-out still runs past the wait '
        'fails as it did, without signing in; steps then run', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, states, _, _) {
        auth.signOutGate = Completer<void>();
        auth.signInResult = _user;
        bloc.add(const SignOutRequested());
        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));
        states.clear();

        bloc.add(const SignInRequested());
        async.elapse(SyncLimits.engineStop + const Duration(seconds: 1));

        // A new failure after the spinner, so its snackbar shows again.
        expect(states, [
          const SyncSigningIn(),
          const SyncFailure(AuthError.unknown),
        ]);
        expect(auth.signInCalls, 0);
        bloc.add(const StopSyncingRequested());
        async.flushMicrotasks();
        expect(spaces.calls, ['stop']);
      });
    });

    test('a thrown sign-out releases the counter (review RC1c-1)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, _, _, _) {
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        async.flushMicrotasks();
        expect(bloc.state, isA<SyncFailure>());
        bloc.add(const StopSyncingRequested());
        async.flushMicrotasks();
        expect(spaces.calls, ['stop']);
      });
    });

    test('a second failed sign-out emits a second failure: the account goes '
        'back up first, so the failure is a new state (review RC3-1)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, states, _, _) {
        const failure = SyncFailure(
          AuthError.unknown,
          action: SyncAccountAction.signOut,
          user: _user,
          deletion: SyncDeletionStatus(accountUid: 'uid-1'),
        );
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        async.flushMicrotasks();
        expect(bloc.state, failure);
        states.clear();

        bloc.add(const SignOutRequested());
        async.flushMicrotasks();

        expect(states, hasLength(2));
        expect(states.first, isA<SyncSignedIn>());
        expect((states.first as SyncSignedIn).user, _user);
        expect(states.last, failure);
      });
    });

    test('Sync now from a failed sign-out shows the run: the account goes '
        'back up, so the engine\'s status reaches it (review RC3b-1)', () {
      final spaces = _FakeSpaceService();
      onFakeClock(spaces, (async, bloc, auth, _, engine, _) {
        auth.signOutError = const AuthException(AuthError.unknown);
        bloc.add(const SignOutRequested());
        async.flushMicrotasks();
        expect(bloc.state, isA<SyncFailure>());

        bloc.add(const SyncNowRequested());
        async.flushMicrotasks();
        expect(bloc.state, isA<SyncSignedIn>());

        engine.emit(const SyncStatus(activity: SyncActivity.pulling));
        async.flushMicrotasks();
        expect(
          (bloc.state as SyncSignedIn).status.activity,
          SyncActivity.pulling,
        );
      });
    });

    test('after a failed sign-out the user is still signed in: "Sync this '
        'database" runs its step on the account, a failed sign-in\'s does '
        'not (review RC3-4)', () {
      for (final (action, runs) in const [
        (SyncAccountAction.signOut, true),
        (SyncAccountAction.signIn, false),
      ]) {
        final spaces = _FakeSpaceService();
        onFakeClock(spaces, (async, bloc, auth, _, _, _) {
          if (action == SyncAccountAction.signOut) {
            auth.signOutError = const AuthException(AuthError.unknown);
            bloc.add(const SignOutRequested());
          } else {
            auth.signInError = const AuthException(AuthError.unknown);
            bloc.add(const SignInRequested());
          }
          async.flushMicrotasks();
          expect(bloc.state, isA<SyncFailure>());
          expect((bloc.state as SyncFailure).action, action);

          bloc.add(const SyncThisDatabaseRequested());
          async.flushMicrotasks();

          expect(spaces.calls, runs ? ['start:${_user.uid}'] : isEmpty);
          if (runs) {
            expect(bloc.state, isA<SyncSignedIn>());
            expect((bloc.state as SyncSignedIn).flow, isA<SyncBindPicking>());
          }
        });
      }
    });

    test('an engine whose stop and start hang is given up on and the step '
        'goes on (review RC1-4)', () {
      final spaces = _FakeSpaceService()
        ..startResult = SyncBindStartBound(_space.ref);
      onFakeClock(spaces, engine: _StuckEngine(), (
        async,
        bloc,
        _,
        states,
        engine,
        _,
      ) {
        bloc.add(const SyncThisDatabaseRequested());
        async.flushMicrotasks();
        async.elapse(SyncLimits.engineStop * 3);

        expect(spaces.calls, ['start:uid-1']);
        expect(engine.calls, ['stop', 'start']);
        expect(flows(states).last, const SyncBindIdle());
        expect(bloc.state.stepInFlight, isFalse);
      });
    });

    test('an engine that never resolves is given up on and the step goes '
        'on (review RC1-4)', () {
      final spaces = _FakeSpaceService()
        ..startResult = SyncBindStartBound(_space.ref);
      onFakeClock(spaces, resolve: () => Completer<SyncEngine?>().future, (
        async,
        bloc,
        _,
        states,
        _,
        _,
      ) {
        bloc.add(const SyncThisDatabaseRequested());
        async.flushMicrotasks();
        async.elapse(SyncLimits.engineStop * 3);

        expect(spaces.calls, ['start:uid-1']);
        expect(flows(states).last, const SyncBindIdle());
        expect(bloc.state.stepInFlight, isFalse);
      });
    });

    test('no step starts between a settle and the deferred sign-out\'s own '
        'emit (review RC1-5)', () async {
      final spaces = _FakeSpaceService();
      final (bloc, auth, _, _, _) = await pumpBinding(spaces, picking: true);
      final gate = Completer<void>();
      spaces.gate = gate;
      final signOut = Completer<void>();
      auth.signOutGate = signOut;

      bloc.add(const MergeIntoSpaceRequested(_space));
      await pumpEventQueue();
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      expect(bloc.state, isA<SyncSignedIn>(), reason: 'settled, not out yet');
      expect(bloc.state.stepInFlight, isFalse);

      bloc
        ..add(const StopSyncingRequested())
        ..add(const SyncThisDatabaseRequested());
      await pumpEventQueue();
      expect(spaces.calls, ['merge:space-1:uid-1']);

      signOut.complete();
      await pumpEventQueue();
      expect(bloc.state, isA<SyncSignedOut>());
      bloc.add(const StopSyncingRequested());
      await pumpEventQueue();
      expect(spaces.calls, ['merge:space-1:uid-1', 'stop']);
      await bloc.close();
    });

    test('a download\'s switch never wears the old database\'s status, '
        'even when the read after it fails (review RC1-6)', () async {
      final spaces = _FakeSpaceService();
      final (bloc, _, states, _, reader) = await pumpBinding(
        spaces,
        picking: true,
      );
      reader.pendingCount = 4;
      bloc.add(const RefreshSyncStatus());
      await pumpEventQueue();
      expect((bloc.state as SyncSignedIn).status.pendingCount, 4);
      reader.error = StateError('closed db');

      bloc.add(const DownloadSpaceRequested(_space));
      await pumpEventQueue();

      final switched = states.whereType<SyncSignedIn>().firstWhere(
        (s) => s.flow == const SyncBindIdle(switchedToDatabase: 'downloaded'),
      );
      expect(switched.status, SyncStatus.empty);
      await bloc.close();
    });

    test('after a failed sign-in Stop runs, signed out, on the last binding '
        'known (final review U-4)', () async {
      final spaces = _FakeSpaceService();
      final (bloc, auth, states, _, reader) = await pumpBinding(
        spaces,
        user: null,
      );
      auth.signInError = StateError('no network');
      bloc.add(const SignInRequested());
      await pumpEventQueue();
      expect(bloc.state, isA<SyncFailure>());
      states.clear();

      bloc.add(const StopSyncingRequested());
      await pumpEventQueue();

      expect(spaces.calls, ['stop']);
      expect(flows(states).first, const SyncBindIdle());
      expect(flows(states), contains(const SyncBindStopping()));
      expect(flows(states).last, const SyncBindIdle());
      expect(bloc.state, isA<SyncSignedOut>());
      expect(reader.reads, [null]);
      await bloc.close();
    });
  });

  group('a bound database across an account change (final review U-2)', () {
    const binding = SyncBinding(
      spaceId: 'space-1',
      ownerUid: 'uid-1',
      accountUid: 'uid-1',
    );

    SyncStatus? statusOf(SyncState state) => switch (state) {
      SyncSignedIn(:final status) || SyncSignedOut(:final status) => status,
      _ => null,
    };

    test('a sign-in: every account state before the read carries the '
        'binding, paused for no account', () async {
      final reader = _FakeStatusReader()
        ..binding = binding
        ..pause = SyncPause.signedOut;
      final (bloc, auth, states) = await _pumpBloc(reader: reader);
      expect(statusOf(bloc.state)?.binding, binding);
      auth.signInResult = _user;
      reader
        ..pause = SyncPause.none
        ..gate = Completer<void>();
      final read = reader.gate!;
      states.clear();

      bloc.add(const SignInRequested());
      await pumpEventQueue();

      expect(states.first, const SyncSigningIn());
      final beforeRead = states.last as SyncSignedIn;
      expect(beforeRead.user, _user);
      expect(beforeRead.status.binding, binding);
      expect(beforeRead.status.pause, SyncPause.none);

      read.complete();
      await pumpEventQueue();
      for (final state in states.where((s) => s is! SyncSigningIn)) {
        expect(statusOf(state)?.binding, binding, reason: '$state');
      }
      await bloc.close();
    });

    test('another account shows the mismatch at once, and a read that '
        'times out keeps the last status known', () {
      fakeAsync((async) {
        final fake = _FakeAuthService(available: true, user: _user);
        final reader = _FakeStatusReader()
          ..binding = binding
          ..pendingCount = 3;
        final bloc = SyncBloc(authService: fake, statusReader: () => reader);
        final states = <SyncState>[];
        bloc.stream.listen(states.add);
        bloc.add(const LoadSyncStatus());
        async.flushMicrotasks();
        reader.gate = Completer<void>();

        fake.emitAuth(_partner);
        async.elapse(SyncBloc.statusTimeout + const Duration(seconds: 1));

        final shown = states.last as SyncSignedIn;
        expect(shown.user, _partner);
        expect(shown.status.binding, binding);
        expect(shown.status.pendingCount, 3);
        expect(shown.status.pause, SyncPause.accountMismatch);
        bloc.close();
        async.flushMicrotasks();
      });
    });
  });
}
