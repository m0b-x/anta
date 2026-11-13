import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/push/firebase_push_address_source.dart';

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
    if (failUnregister case final error?) throw error;
  }

  @override
  Future<void> deleteInstallation() async {
    deletes++;
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
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _Platform();
    source = build();
  });

  Future<String?> pref(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

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

  test('a delete that fails drops the address at once and is owed: the next '
      'registration pays it first', () async {
    await source.current();
    platform.failDelete = Exception('offline');
    await source.giveUp();
    expect(await pref(SettingsKeys.pushDeleteOwed), '1');
    expect(await source.holds(), isTrue);

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

  test('a name for a registration from before a give-up is not taken', () async {
    platform.answers = false;
    expect(await source.current(), isNull);
    await source.giveUp();
    platform.name('fid-old');
    await pumpEventQueue();

    platform.answers = true;
    expect(await source.current(), 'fid-2');
  });

  test('an install that holds nothing gives up nothing', () async {
    await source.giveUp();
    expect(platform.unregisters + platform.deletes, 0);
  });
}
