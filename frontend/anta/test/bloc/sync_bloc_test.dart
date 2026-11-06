import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/auth_service.dart';
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

  @override
  bool get isAvailable => available;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _user;

  void emitAuth(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<AppUser?> signInWithGoogle() async {
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
  Object? error;

  /// When set, the next read waits for it, then clears it.
  Completer<void>? gate;
  final List<String?> reads = [];

  @override
  Future<SyncStatus> read({AppUser? user}) async {
    reads.add(user?.uid);
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    if (error != null) throw error!;
    return SyncStatus(pendingCount: pendingCount, pause: pause);
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

  Future<void> _step(String call) async {
    calls.add(call);
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
      expect(states, [const SyncSignedIn(_user)]);
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
        const SyncSignedIn(_user),
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
      expect(states.last, const SyncSignedIn(_user));
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
          const SyncSignedIn(_user),
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
        const SyncSignedIn(_partner),
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

    test('failure surfaces as SyncFailure', () async {
      final (bloc, fake, states) = await _pumpBloc(user: _user);
      fake.signOutError = const AuthException(AuthError.unknown);
      bloc.add(const SignOutRequested());
      await pumpEventQueue();
      expect(states.last, const SyncFailure(AuthError.unknown));
      await bloc.close();
    });
  });

  group('sync status', () {
    test('load shows the account at once, then its status', () async {
      final reader = _FakeStatusReader()..pendingCount = 3;
      final (bloc, _, states) = await _pumpBloc(user: _user, reader: reader);

      expect(states, [
        const SyncSignedIn(_user),
        const SyncSignedIn(_user, status: SyncStatus(pendingCount: 3)),
      ]);
      expect(reader.reads, [_user.uid]);
      await bloc.close();
    });

    test('an account change re-reads the status for the new one', () async {
      final reader = _FakeStatusReader()..pendingCount = 1;
      final (bloc, fake, states) = await _pumpBloc(reader: reader);
      reader.pendingCount = 2;

      fake.emitAuth(_partner);
      await pumpEventQueue();

      // The new account shows at once, without the previous account's
      // status: the pause is per account.
      expect(states, [
        const SyncSignedOut(),
        const SyncSignedOut(status: SyncStatus(pendingCount: 1)),
        const SyncSignedIn(_partner),
        const SyncSignedIn(_partner, status: SyncStatus(pendingCount: 2)),
      ]);
      expect(reader.reads, [null, _partner.uid]);
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
        const SyncSignedIn(_user, status: SyncStatus(pendingCount: 1)),
        const SyncSignedIn(_user, status: SyncStatus(pendingCount: 2)),
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

      expect(states, [
        const SyncSignedOut(),
        const SyncSigningIn(),
        const SyncSignedIn(_user),
        const SyncSignedIn(_user, status: SyncStatus(pendingCount: 6)),
      ]);
      await bloc.close();
    });

    test('a stalled reader times out to the empty status', () {
      fakeAsync((async) {
        final fake = _FakeAuthService(available: true, user: _user);
        final reader = _FakeStatusReader()..gate = Completer<void>();
        final bloc = SyncBloc(authService: fake, statusReader: () => reader);
        final states = <SyncState>[];
        bloc.stream.listen(states.add);

        bloc.add(const LoadSyncStatus());
        async.elapse(SyncBloc.statusTimeout + const Duration(seconds: 1));

        expect(states, [const SyncSignedIn(_user)]);
        // A refresh afterwards reads again and lands its status.
        reader.pendingCount = 2;
        bloc.add(const RefreshSyncStatus());
        async.flushMicrotasks();
        expect(
          states.last,
          const SyncSignedIn(_user, status: SyncStatus(pendingCount: 2)),
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
        const SyncSignedIn(_user, status: SyncStatus(pendingCount: 7)),
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
        const SyncSignedIn(_user, status: SyncStatus(pendingCount: 4)),
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
      expect(reader.reads, hasLength(2));
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

      expect(states.last, const SyncSignedIn(_user, status: pulling));
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

      expect(states.last, const SyncSignedIn(_user, status: pulling));
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

      expect(states, [const SyncSignedIn(_user)]);
      await bloc.close();
    });

    test('starts from the status the engine already holds', () async {
      final engine = FakeSyncEngine()..current = pulling;
      final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);

      expect(states.last, const SyncSignedIn(_user, status: pulling));
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

    test('a showing noAccess survives a re-read of the same account', () async {
      final reader = _FakeStatusReader();
      final engine = FakeSyncEngine();
      final (bloc, fake, states) = await _pumpBloc(
        user: _user,
        reader: reader,
        engine: engine,
      );
      engine.emit(const SyncStatus(pause: SyncPause.noAccess));
      await pumpEventQueue();

      // The identity re-reports the same account: its status is read anew.
      fake.emitAuth(_user);
      await pumpEventQueue();

      expect(reader.reads, hasLength(2));
      expect((states.last as SyncSignedIn).status.pause, SyncPause.noAccess);
      await bloc.close();
    });

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
      expect(states.last, const SyncSignedIn(_user));
      expect(old.statuses.hasListener, isFalse);

      fresh.emit(pulling);
      await pumpEventQueue();
      expect(states.last, const SyncSignedIn(_user, status: pulling));
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
      expect(states.last, const SyncSignedIn(_user));

      fresh.emit(pulling);
      await pumpEventQueue();
      expect(states.last, const SyncSignedIn(_user, status: pulling));
      await bloc.close();
    });

    test('a dead engine leaves the account as it is, and the next load '
        'follows it again', () async {
      final engine = FakeSyncEngine();
      final (bloc, _, states) = await _pumpBloc(user: _user, engine: engine);
      await engine.dispose();
      await pumpEventQueue();
      expect(states.last, const SyncSignedIn(_user));

      bloc.add(const LoadSyncStatus());
      await pumpEventQueue();

      expect(states.last, const SyncSignedIn(_user));
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

      expect(states, [const SyncSignedIn(_user)]);
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
    /// whose reads it counts.
    Future<
      (
        SyncBloc,
        _FakeAuthService,
        List<SyncState>,
        FakeSyncEngine,
        _FakeStatusReader,
      )
    >
    pumpBinding(_FakeSpaceService spaces, {AppUser? user = _user}) async {
      final engine = FakeSyncEngine();
      final reader = _FakeStatusReader();
      final (bloc, auth, states) = await _pumpBloc(
        user: user,
        reader: reader,
        engine: engine,
        spaces: spaces,
      );
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
      expect(engine.calls, isEmpty, reason: 'nothing bound yet');
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
      test(
        '$label fails the tap with its reason, the engine left alone',
        () async {
          final spaces = _FakeSpaceService()..error = error;
          final (bloc, _, states, engine, _) = await pumpBinding(spaces);
          engine.calls.clear();

          bloc.add(const SyncThisDatabaseRequested());
          await pumpEventQueue();

          expect(flows(states), [const SyncBindChecking(), failed]);
          expect(engine.calls, isEmpty);
          await bloc.close();
        },
      );
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
        final (bloc, _, states, engine, reader) = await pumpBinding(spaces);
        engine.calls.clear();

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
      final (bloc, _, states, _, _) = await pumpBinding(spaces);

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
      final (bloc, _, states, _, _) = await pumpBinding(spaces);
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
  });
}
