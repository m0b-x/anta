// An isolate-backed file database, as the other backup round trips.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/counter_service.dart';

/// A restore appends copies and re-ids every folder it carries, so a note
/// whose archived folder the archive did not carry keeps that folder only if
/// it is a live folder of this database; under any other id it would be filed
/// somewhere that exists nowhere, invisible in the browser, and a bound
/// database would copy it to every device (P review PR7).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_folders');
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

  Map<String, dynamic> note(String title, String folderId) => {
    JsonKeys.id: 'archived-$title',
    JsonKeys.folderId: folderId,
    JsonKeys.title: title,
    JsonKeys.content: '',
  };

  test('a note whose folder exists nowhere restores at the root; one whose '
      'folder is a live folder here stays in it; one whose folder is a '
      'tombstone here restores at the root', () async {
    final db = await AppDatabase.getInstance();
    final live = await db.folderDao.createFolder(name: 'Here');
    final gone = await db.folderDao.createFolder(name: 'Gone');
    await db.folderDao.softDeleteFolder(gone.id);

    final result = await (await BackupService.getInstance()).importFromJson(
      jsonEncode({
        'version': 7,
        'folders': <Map<String, dynamic>>[
          {
            JsonKeys.id: 'archived-folder',
            JsonKeys.name: 'Carried',
            JsonKeys.createdAt: DateTime(2026, 11, 1).toIso8601String(),
          },
        ],
        'notes': <Map<String, dynamic>>[
          note('Nowhere', 'missing-folder'),
          note('Local', live.id),
          note('Tombstoned', gone.id),
          note('Carried', 'archived-folder'),
          note('Root', ''),
        ],
        'settings': const <String, dynamic>{},
      }),
    );
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    String folderOf(String title) =>
        notes.singleWhere((n) => n.title == title).folderId;
    final carried = (await db.folderDao.getAllFolders()).singleWhere(
      (f) => f.name == 'Carried',
    );

    expect(folderOf('Nowhere'), '');
    expect(folderOf('Local'), live.id);
    expect(folderOf('Tombstoned'), '');
    expect(folderOf('Carried'), carried.id);
    expect(folderOf('Root'), '');
  });
}
