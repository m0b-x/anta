import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/counter_service.dart';

/// Pins the pairing and binding keys out of a backup (D3): they are per
/// database, and restoring an archive onto another database must not clone a
/// pair membership or a space binding onto it. The settings export is an
/// allow-list, so this holds by construction — until someone widens it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_sync_keys');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('no pairing or binding key travels in an export', () async {
    const keys = [
      SettingsKeys.pairingPairId,
      SettingsKeys.pairingAccountUid,
      SettingsKeys.pairingPartnerUid,
      SettingsKeys.pairingPartnerName,
      SettingsKeys.pairingPendingCode,
      SettingsKeys.pairingPendingExpiresAt,
      SettingsKeys.pairingEndedNotice,
      SettingsKeys.syncSpaceId,
      SettingsKeys.syncSpaceOwnerUid,
      SettingsKeys.syncSpaceAccountUid,
      SettingsKeys.syncSpaceBoundAt,
    ];
    final db = await AppDatabase.getInstance();
    for (final key in keys) {
      await db.userSettingsDao.setValue(key, 'value-of-$key');
    }

    final exported = await (await BackupService.getInstance()).exportAllData();

    final settings = exported['settings'] as Map<String, dynamic>;
    expect(settings.keys.toSet().intersection(keys.toSet()), isEmpty);
    expect(jsonEncode(exported), isNot(contains('value-of-')));
  });
}
