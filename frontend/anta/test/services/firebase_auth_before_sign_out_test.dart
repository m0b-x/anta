import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/firebase_auth_service.dart';

class _User implements User {
  @override
  final String uid;

  _User(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  final List<String> events;
  User? user = _User('uid-a');

  _Auth(this.events);

  @override
  User? get currentUser => user;

  @override
  Future<void> signOut() async {
    events.add('signed out');
    user = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The leave the push registry needs written as the account itself
/// (`docs/cloud-shared-freshness.md` §7) runs before the session ends, and
/// never keeps it from ending.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> events;
  late FirebaseAuthService service;

  setUp(() {
    events = [];
    service = FirebaseAuthService(auth: _Auth(events));
  });

  tearDown(() => FirebaseAuthService.beforeSignOut = null);

  test('the leave runs first, as the account signing out', () async {
    FirebaseAuthService.beforeSignOut = (uid) async => events.add('left $uid');

    await service.signOut();

    expect(events, ['left uid-a', 'signed out']);
  });

  test('a leave that fails still signs out', () async {
    FirebaseAuthService.beforeSignOut = (_) async => throw StateError('no');

    await service.signOut();

    expect(events, ['signed out']);
  });

  test('nobody signed in: no leave is asked for', () async {
    final auth = _Auth(events)..user = null;
    service = FirebaseAuthService(auth: auth);
    FirebaseAuthService.beforeSignOut = (uid) async => events.add('left $uid');

    await service.signOut();

    expect(events, ['signed out']);
  });
}
