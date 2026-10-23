import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/utils/auth_error.dart';

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
    return SyncStatus(pendingCount: pendingCount);
  }
}

Future<(SyncBloc, _FakeAuthService, List<SyncState>)> _pumpBloc({
  bool available = true,
  AppUser? user,
  SyncStatusReader? reader,
}) async {
  final fake = _FakeAuthService(available: available, user: user);
  final bloc = SyncBloc(
    authService: fake,
    statusReader: reader == null ? null : () => reader,
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
  });
}
