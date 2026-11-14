import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/push/firebase_push_address_source.dart';
import 'package:anta/services/push/push_registry.dart';

import '../../support/fake_push.dart';
import '../../support/scripted_prefs_store.dart';
import '../pairing_support.dart';

/// The platform as the plugins answer: `onRegistered` names the installation
/// id once a registration completes, and only a deleted installation makes
/// the next one new.
class _Platform implements PushPlatform {
  final StreamController<String> _named = StreamController.broadcast();
  int installation = 1;
  int registers = 0;
  int unregisters = 0;
  int deletes = 0;

  /// Whether a registration names its id by itself, at once.
  bool answers = true;
  Object? failDelete;
  Object? failUnregister;

  /// While set, [unregister] or [deleteInstallation] never answers.
  Completer<void>? stallUnregister;
  Completer<void>? stallDelete;

  @override
  Stream<String> get registered => _named.stream;

  void name([String? id]) => _named.add(id ?? 'fid-$installation');

  @override
  Future<void> register() async {
    registers++;
    if (answers) scheduleMicrotask(name);
  }

  @override
  Future<void> unregister() async {
    unregisters++;
    if (stallUnregister case final stall?) await stall.future;
    if (failUnregister case final error?) throw error;
  }

  @override
  Future<void> deleteInstallation() async {
    deletes++;
    if (stallDelete case final stall?) await stall.future;
    if (failDelete case final error?) throw error;
    installation++;
  }
}

void main() {
  late _Platform platform;
  late FirebasePushAddressSource source;

  FirebasePushAddressSource build() => FirebasePushAddressSource(
    platform: platform,
    prefs: SharedPreferences.getInstance(),
    deadline: const Duration(milliseconds: 50),
    endDeadline: const Duration(milliseconds: 50),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _Platform();
    source = build();
  });

  Future<String?> pref(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  test('the moment an address is first held is announced, once (closing '
      'review, A3): from then on a message can start a run with no app, '
      'and what it arms under is stored before one comes', () async {
    var announced = 0;
    FirebasePushAddressSource.onAddressFirstHeld = () async {
      // The mark is in place by the time anyone is told.
      expect(await pref(SettingsKeys.pushAddressHeld), '1');
      announced++;
    };
    addTearDown(() => FirebasePushAddressSource.onAddressFirstHeld = null);

    await source.current();
    await pumpEventQueue();
    expect(announced, 1);

    await source.current();
    await build().current();
    await pumpEventQueue();
    expect(announced, 1, reason: 'held already');
  });

  test('a registration names the address and marks it held', () async {
    expect(await source.holds(), isFalse);
    expect(await source.current(), 'fid-1');
    expect(await source.holds(), isTrue);
    expect(await source.current(), 'fid-1');
    expect(platform.registers, 1);
  });

  test('a name that lands after the deadline is taken, and held', () async {
    platform.answers = false;
    expect(await source.current(), isNull);
    platform.name();
    await pumpEventQueue();

    expect(await source.current(), 'fid-1');
    expect(await source.holds(), isTrue);
    await source.giveUp();
    expect(platform.deletes, 1);
  });

  test('giving up unregisters and deletes the installation: the next '
      'address is a new one', () async {
    await source.current();
    await source.giveUp();
    expect(platform.unregisters, 1);
    expect(platform.deletes, 1);
    expect(await source.holds(), isFalse);
    expect(await source.current(), 'fid-2');
  });

  test('a give-up whose delete failed is paid by the next give-up — the '
      'next run that learns the pair ended, with the app still closed '
      '(second look, D4; probe Q1)', () async {
    await source.current();
    platform.failDelete = Exception('offline');
    await source.giveUp();
    expect(await pref(SettingsKeys.pushDeleteOwed), '1');
    expect(await pref(SettingsKeys.pushAddressHeld), isNull);

    // The next run, the network back.
    platform.failDelete = null;
    final deletes = platform.deletes;
    await build().giveUp();

    expect(platform.deletes, deletes + 1);
    expect(await pref(SettingsKeys.pushDeleteOwed), isNull);
  });

  group('"owed" is read off the store wherever it is acted on: the isolate '
      'that acts is not always the one that wrote it, and its copy of the '
      'preferences may be older (review of leg 12, F3)', () {
    /// A run's give-up whose delete failed, written behind this isolate's
    /// copy: the store says nothing is held and a delete is owed, the copy
    /// says neither.
    setUp(() async {
      await SharedPreferences.getInstance();
      await SharedPreferencesStorePlatform.instance.setValue(
        'String',
        'flutter.${SettingsKeys.pushDeleteOwed}',
        '1',
      );
    });

    Future<Object?> owedInStore() async => (await SharedPreferencesStorePlatform
        .instance
        .getAll())['flutter.${SettingsKeys.pushDeleteOwed}'];

    test('a give-up pays it (probe A1)', () async {
      await source.giveUp();

      expect(platform.unregisters, 1);
      expect(platform.deletes, 1);
      expect(await owedInStore(), isNull);
    });

    test('the launch\'s payOwed pays it (probe A2)', () async {
      await source.payOwed();

      expect(platform.deletes, 1);
      expect(await owedInStore(), isNull);
    });

    test('a registration pays it first: the address it names is a new '
        'one, never the installation whose end is owed — which the next '
        'launch would then have deleted in use (probe A2)', () async {
      expect(await source.current(), 'fid-2');

      expect(platform.deletes, 1);
      expect(platform.registers, 1);
      expect(await owedInStore(), isNull);
    });

    test('a store that cannot be read leaves the copy\'s answer: nothing '
        'is owed there, and nothing is asked', () async {
      final store = ScriptedPrefsStore.install();
      await SharedPreferences.getInstance();
      store.onRead = (_) => throw StateError('no store');

      await build().payOwed();

      expect(platform.deletes, 0);
    });
  });

  test('a give-up with nothing held and nothing owed asks the platform '
      'nothing', () async {
    await source.giveUp();

    expect(platform.unregisters, 0);
    expect(platform.deletes, 0);
  });

  test('a give-up asked by an isolate that did not take the address — the '
      'check\'s run, whose read found the pair ended — goes by what the '
      'store holds, past its own copy of the preferences', () async {
    // This isolate's copy, loaded before the app's isolate took an address.
    await SharedPreferences.getInstance();
    await SharedPreferencesStorePlatform.instance.setValue(
      'String',
      'flutter.${SettingsKeys.pushAddressHeld}',
      '1',
    );
    expect(await source.holds(), isFalse, reason: 'the copy, as the app asks');

    await source.giveUp();

    expect(platform.unregisters, 1);
    expect(platform.deletes, 1);
    expect(
      await SharedPreferencesStorePlatform.instance.getAll(),
      isNot(contains('flutter.${SettingsKeys.pushAddressHeld}')),
    );
  });

  test('a delete that fails drops the address at once and is owed: the next '
      'registration pays it first', () async {
    await source.current();
    platform.failDelete = Exception('offline');
    await source.giveUp();
    expect(await pref(SettingsKeys.pushDeleteOwed), '1');
    expect(
      await source.holds(),
      isFalse,
      reason: 'an owed end is no address: nothing listens for it',
    );

    expect(await source.current(), isNull, reason: 'still owed: no address');
    expect(platform.registers, 1);

    platform.failDelete = null;
    expect(await source.current(), 'fid-2');
    expect(await pref(SettingsKeys.pushDeleteOwed), isNull);
  });

  test('a launch pays a delete owed, and asks the platform nothing when '
      'none is', () async {
    await source.payOwed();
    expect(platform.unregisters + platform.deletes, 0);

    SharedPreferences.setMockInitialValues({SettingsKeys.pushDeleteOwed: '1'});
    source = build();
    await source.payOwed();
    expect(platform.deletes, 1);
    expect(await pref(SettingsKeys.pushDeleteOwed), isNull);
  });

  test(
    'a name for a registration from before a give-up is not taken',
    () async {
      platform.answers = false;
      expect(await source.current(), isNull);
      await source.giveUp();
      platform.name('fid-old');
      await pumpEventQueue();

      platform.answers = true;
      expect(await source.current(), 'fid-2');
    },
  );

  test('an empty name from the platform is no address', () async {
    platform.answers = false;
    final asked = source.current();
    await pumpEventQueue();
    platform.name('');
    expect(await asked, isNull);
    platform.name();
    await pumpEventQueue();
    expect(await source.current(), 'fid-1');
  });

  test('an install that holds nothing gives up nothing', () async {
    await source.giveUp();
    expect(platform.unregisters + platform.deletes, 0);
  });

  group('a platform that never answers the end', () {
    test('an unregister that stalls is given up at its bound, and the '
        'installation is deleted all the same', () async {
      await source.current();
      platform.stallUnregister = Completer<void>();
      await source.giveUp().timeout(const Duration(seconds: 2));

      expect(platform.deletes, 1);
      expect(await pref(SettingsKeys.pushDeleteOwed), isNull);
      expect(await source.current(), 'fid-2');
    });

    test('a delete that stalls stays owed past its bound; the next ask '
        'tries again, bounded too, and names nothing meanwhile', () async {
      await source.current();
      platform.stallDelete = Completer<void>();
      await source.giveUp().timeout(const Duration(seconds: 2));
      expect(await pref(SettingsKeys.pushDeleteOwed), '1');

      expect(
        await source.current().timeout(const Duration(seconds: 2)),
        isNull,
      );
      expect(platform.deletes, 2);
      expect(platform.registers, 1);
    });

    test('a stalled end holds no later step of the registry: an answer '
        'after it registers and writes', () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushAddressHeld: '1',
      });
      source = build();
      platform.stallUnregister = Completer<void>();
      final pairs = FakePairingGateway();
      final registry = PushRegistry(
        gateway: pairs,
        addresses: source,
        relay: FakePushRelay()..configured = Uri.parse('https://relay.test'),
        shares: (_) async => true,
        storedPair: () async => null,
        deviceId: () async => 'dev-a',
        signedIn: () => userA.uid,
        prefs: SharedPreferences.getInstance(),
        leaveDeadline: const Duration(milliseconds: 50),
      );
      addTearDown(registry.dispose);
      await registry.leave(userA.uid);
      final pair = pairs.seedPair([userA.uid, userB.uid]);

      await registry
          .heardPairs(userA.uid, [pair])
          .timeout(const Duration(seconds: 2));

      expect(pairs.pushWrites, ['write ${pair.pairId} uid-a dev-a fid-2']);
    });
  });
}
