import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/settings_service.dart';

/// Which surface a note opens on is now two settings — live rendering, and
/// whether the deprecated preview exists at all — and both were outside the
/// backup's settings allow-list. A key that is not in that list is dropped
/// silently: the restore succeeds, nothing warns, and the user finds the
/// editor behaving like a fresh install.
///
/// The wipe between export and import is what makes this a round trip rather
/// than a smoke test — writing the *opposite* values back means an import
/// that never touched these keys leaves the assertions failing rather than
/// passing on leftovers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_editor');
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

  test(
    'live rendering and preview mode survive an export/import round trip',
    () async {
      final settings = await SettingsService.getInstance();
      // Both flipped away from their defaults: the export has to carry the
      // value, not the absence of one.
      await settings.setLiveMarkdownRendering(false);
      await settings.setPreviewModeEnabled(true);

      final backup = await BackupService.getInstance();
      final exported = await backup.exportAllData();
      final exportedSettings = exported['settings'] as Map<String, dynamic>;

      expect(exportedSettings[SettingsKeys.liveMarkdownRendering], 'false');
      expect(exportedSettings[SettingsKeys.previewModeEnabled], 'true');

      final json = jsonEncode(exported);

      await settings.setLiveMarkdownRendering(true);
      await settings.setPreviewModeEnabled(false);

      final result = await backup.importFromJson(json);
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      SettingsService.reset();
      DatabaseLifecycle.notifyDatabaseSwitching();
      final restored = await SettingsService.getInstance();

      expect(await restored.getLiveMarkdownRendering(), isFalse);
      expect(await restored.getPreviewModeEnabled(), isTrue);
    },
  );

  test('a backup written before these keys existed still imports', () async {
    final backup = await BackupService.getInstance();
    final exported = await backup.exportAllData();
    final settingsMap =
        Map<String, dynamic>.from(exported['settings'] as Map<String, dynamic>)
          ..remove(SettingsKeys.liveMarkdownRendering)
          ..remove(SettingsKeys.previewModeEnabled);
    final older = Map<String, dynamic>.from(exported)
      ..['settings'] = settingsMap;

    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    final settings = await SettingsService.getInstance();
    await settings.setPreviewModeEnabled(true);

    final result = await backup.importFromJson(jsonEncode(older));

    expect(result.success, isTrue, reason: 'error: ${result.error}');
    expect(
      await settings.getPreviewModeEnabled(),
      isTrue,
      reason: 'an absent key must leave the current value alone, not reset it',
    );
  });
}
