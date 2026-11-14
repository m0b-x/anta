import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/core/di/injection.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/firebase_auth_service.dart';
import 'package:anta/services/push/firebase_push_address_source.dart';
import 'package:anta/services/push/push_address_source.dart';
import 'package:anta/services/push/push_pairing_gateway.dart';
import 'package:anta/services/push/push_receiver.dart';
import 'package:anta/services/push/push_registry.dart';
import 'package:anta/services/push/push_relay.dart';
import 'package:anta/services/sync/account_closer.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

import '../../services/pairing_support.dart';

/// Which push bindings the app's launch picks (`docs/cloud-shared-freshness.md`
/// §7): the no-ops off Android and the QA build's no-op address source; on a
/// phone the relay flushed as the app leaves the screen and the leave hooks
/// reaching the registry. Nothing here reaches a plugin or the network: a
/// Firebase call on the host fails at once, and is logged.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakePairingGateway pairing;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_push_di');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pairing = FakePairingGateway();
    getIt.registerSingleton<AuthService>(FakeAuthService(user: userA));
  });

  tearDown(() async {
    debugCloudForTesting = false;
    await resetDependencies();
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('off Android: the no-ops, the pairing as it is, no hook set', () {
    final bound = registerPushForTesting(pairing);

    expect(bound, same(pairing));
    expect(getIt<PushAddressSource>(), isA<NoOpPushAddressSource>());
    expect(getIt<PushRelay>(), isA<NoOpPushRelay>());
    expect(getIt.isRegistered<PushRegistry>(), isFalse);
    expect(getIt.isRegistered<PushReceiver>(), isFalse);
    expect(FirebaseAuthService.beforeSignOut, isNull);
    expect(PairedAccountCloser.beforeAccountGone, isNull);
    expect(SyncBindingService.onUnbound, isNull);
  });

  test('the QA build on Android: no address source of FCM\'s — nothing '
      'registers against the live project', () {
    debugCloudForTesting = true;
    final bound = registerPushForTesting(pairing, qa: true);

    expect(bound, isA<PushPairingGateway>());
    expect(getIt<PushAddressSource>(), isA<NoOpPushAddressSource>());
  });

  test('on Android: FCM\'s source, the relay, the registry — and sign-out, '
      'an account closed and sync stopped all reach its leave', () async {
    debugCloudForTesting = true;
    final bound = registerPushForTesting(pairing);

    expect(bound, isA<PushPairingGateway>());
    expect(getIt<PushAddressSource>(), isA<FirebasePushAddressSource>());
    expect(getIt<PushRelay>(), isA<HttpPushRelay>());
    final registry = getIt<PushRegistry>();
    expect(FirebaseAuthService.beforeSignOut, registry.leave);
    expect(PairedAccountCloser.beforeAccountGone, registry.leave);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SettingsKeys.pushAddressHeld, '1');
    SyncBindingService.onUnbound!(userA.uid);
    for (var i = 0; i < 200; i++) {
      if (prefs.getString(SettingsKeys.pushAddressHeld) == null) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(prefs.getString(SettingsKeys.pushAddressHeld), isNull);
    expect(
      prefs.getString(SettingsKeys.pushDeleteOwed),
      '1',
      reason: 'given up; the platform is not there to end it',
    );
  });

  test('on Android, a poke waiting for its minute goes as the app leaves '
      'the screen', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.pushRelayUrl: 'https://relay.test',
    });
    debugCloudForTesting = true;
    registerPushForTesting(pairing);
    final relay = getIt<PushRelay>();
    await pumpEventQueue();
    final logged = <String>[];
    final printer = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add('$message');
    addTearDown(() => debugPrint = printer);
    int sent() => logged.where((l) => l.contains('poke failed')).length;

    relay.poke('pair-1', urgent: false);
    relay.poke('pair-1', urgent: true);
    await pumpEventQueue();
    expect(sent(), 1, reason: 'the second waits for its minute');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    addTearDown(() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await pumpEventQueue();
    expect(sent(), 2);
  });
}
