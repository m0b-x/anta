import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/database_manager.dart';

/// A download the process died in, between its switch and its bind (review
/// BA-M2): the relaunch must not land on the empty new database. The check
/// runs on the process's first `DatabaseManager.getInstance()`, so this file
/// holds that one launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_download_marker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('a marker left behind puts the database the download came from back '
      'as active, clears itself, and leaves the new file for the Databases '
      'page', () async {
    final newFile = File(p.join(tempDir.path, 'gym_notes', 'Tablet.db'));
    newFile.createSync(recursive: true);
    SharedPreferences.setMockInitialValues({
      'active_database': 'Tablet',
      SettingsKeys.syncDownloadInFlight: jsonEncode({
        'from': 'phone',
        'to': 'Tablet',
      }),
    });

    final manager = await DatabaseManager.getInstance();

    expect(manager.getActiveDatabaseName(), 'phone');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsKeys.syncDownloadInFlight), isNull);
    expect(await manager.databaseExists('Tablet'), isTrue);
    expect(newFile.existsSync(), isTrue);
  });
}
