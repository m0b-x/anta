import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/device_state.dart';

import '../support/scripted_prefs_store.dart';

/// `DeviceState` — the preferences that describe this device never outlive
/// it (`docs/cloud-shared-freshness.md`; the push review's F4): Android's
/// backup restores the whole preferences file onto a new phone, and none of
/// the works, the push installation or the device id they speak of.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A phone's preferences as a paired install leaves them: every device
  /// key set, and beside them what describes the databases and the project.
  Map<String, Object> restored({String? stamp}) => {
    SettingsKeys.sharedRefreshStandsFirst: 1794600000000,
    SettingsKeys.sharedRefreshStandsSecond: 1794603600000,
    SettingsKeys.sharedRefreshPlanned: '1',
    SettingsKeys.sharedRefreshMessageRetries: 2,
    SettingsKeys.sharedRefreshCheckGaveWay: 1,
    SettingsKeys.databaseReplacing: '1',
    SettingsKeys.pushAddressHeld: '1',
    SettingsKeys.pushDeleteOwed: '1',
    SettingsKeys.pushWritten: 'pair-1|fid-old|1794600000000',
    SettingsKeys.pushExpeditedWork: '1',
    for (final key in perPair) key: 1794600000000,
    ...stays,
    SettingsKeys.deviceStateOf: ?stamp,
  };

  test('the list is every key that describes this device, and no other', () {
    expect(DeviceState.keys.toSet(), {
      SettingsKeys.sharedRefreshStandsFirst,
      SettingsKeys.sharedRefreshStandsSecond,
      SettingsKeys.sharedRefreshPlanned,
      SettingsKeys.sharedRefreshMessageRetries,
      SettingsKeys.sharedRefreshCheckGaveWay,
      SettingsKeys.databaseReplacing,
      SettingsKeys.pushAddressHeld,
      SettingsKeys.pushDeleteOwed,
      SettingsKeys.pushWritten,
      SettingsKeys.pushExpeditedWork,
    });
    expect(DeviceState.keys, hasLength(DeviceState.keys.toSet().length));
    expect(DeviceState.keys, isNot(contains(SettingsKeys.deviceStateOf)));
    // And what is kept one key per pair, by its prefix.
    expect(DeviceState.prefixes, [
      SettingsKeys.sharedRefreshMessageWaitingPrefix,
    ]);
    for (final key in stays.keys) {
      expect(DeviceState.keys, isNot(contains(key)), reason: key);
    }
  });

  test('a preferences file restored onto another phone — the stamp names '
      'the old device, this one\'s id is new: every device key is cleared, '
      'what describes the databases and the project stays, and the stamp '
      'names this device', () async {
    SharedPreferences.setMockInitialValues(restored(stamp: 'device-old'));

    await DeviceState.keepTo('device-new');

    final prefs = await SharedPreferences.getInstance();
    for (final key in deviceKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
    for (final MapEntry(:key, :value) in stays.entries) {
      expect(prefs.get(key), value, reason: key);
    }
    expect(prefs.getString(SettingsKeys.deviceStateOf), 'device-new');
  });

  test('the same device: nothing is cleared and nothing is written — one '
      'look at the preferences already in memory', () async {
    final store = ScriptedPrefsStore.install(restored(stamp: 'device-here'));
    final prefs = await SharedPreferences.getInstance();
    final loaded = store.reads;
    store.failWrite = (key) => fail('wrote $key');

    await DeviceState.keepTo('device-here');

    for (final key in deviceKeys) {
      expect(prefs.containsKey(key), isTrue, reason: key);
    }
    expect(store.reads, loaded);
  });

  test(
    'no stamp — the first launch of a build that stamps, on a phone '
    'that has the keys: the stamp is written and nothing is cleared',
    () async {
      SharedPreferences.setMockInitialValues(restored());

      await DeviceState.keepTo('device-here');

      final prefs = await SharedPreferences.getInstance();
      for (final key in deviceKeys) {
        expect(prefs.containsKey(key), isTrue, reason: key);
      }
      expect(prefs.getString(SettingsKeys.deviceStateOf), 'device-here');
    },
  );

  test(
    'an install that never paired: the stamp, once, and nothing else',
    () async {
      final store = ScriptedPrefsStore.install();
      final written = <String>[];
      store.failWrite = (key) {
        written.add(key);
        return false;
      };

      await DeviceState.keepTo('device-here');
      await DeviceState.keepTo('device-here');

      expect(written, [SettingsKeys.deviceStateOf]);
    },
  );

  test('a store that cannot be written fails no launch', () async {
    final store = ScriptedPrefsStore.install(restored(stamp: 'device-old'));
    store.failWrite = (_) => true;

    await DeviceState.keepTo('device-new');
  });

  test('a key the store would not give up leaves the old stamp standing: '
      'the next launch clears again', () async {
    final store = ScriptedPrefsStore.install(restored(stamp: 'device-old'));
    store.refuseRemove = (key) => key == SettingsKeys.pushDeleteOwed;

    await DeviceState.keepTo('device-new');

    final kept = await store.getAll();
    expect(kept['flutter.${SettingsKeys.deviceStateOf}'], 'device-old');
    expect(kept, contains('flutter.${SettingsKeys.pushDeleteOwed}'));

    // The next launch, in a new process.
    store.refuseRemove = null;
    SharedPreferences.resetStatic();
    await DeviceState.keepTo('device-new');

    final after = await store.getAll();
    expect(after['flutter.${SettingsKeys.deviceStateOf}'], 'device-new');
    for (final key in deviceKeys) {
      expect(after, isNot(contains('flutter.$key')), reason: key);
    }
  });

  test('the app deleting its own data and device id is the same phone: '
      'the stamp goes with the id, and the launch that makes the next id '
      'clears nothing', () async {
    SharedPreferences.setMockInitialValues(restored(stamp: 'device-here'));

    await DeviceState.idDeleted();
    await DeviceState.keepTo('device-remade');

    final prefs = await SharedPreferences.getInstance();
    for (final key in deviceKeys) {
      expect(prefs.containsKey(key), isTrue, reason: key);
    }
    expect(prefs.getString(SettingsKeys.deviceStateOf), 'device-remade');
  });
}

/// Device state kept per pair (`DeviceState.prefixes`), for two pairs.
const List<String> perPair = [
  '${SettingsKeys.sharedRefreshMessageWaitingPrefix}pair-1',
  '${SettingsKeys.sharedRefreshMessageWaitingPrefix}pair-2',
];

/// Every key a paired install's preferences hold that is device state.
const List<String> deviceKeys = [...DeviceState.keys, ...perPair];

/// What is no device state: it describes the databases and the account's
/// cloud copies, restored with them, or the project.
const Map<String, Object> stays = {
  'active_database': 'main',
  SettingsKeys.syncDownloadInFlight: '{"from":"a","to":"b"}',
  SettingsKeys.syncBoundSpaces: '[]',
  SettingsKeys.syncPendingDeletions: '[]',
  SettingsKeys.syncPendingAccountDeletion: 'uid-1',
  'share_notices_kept_in': ['main'],
  SettingsKeys.pushRelayUrl: 'https://relay.example',
  SettingsKeys.pushRelayReadAt: '1794600000000',
};
