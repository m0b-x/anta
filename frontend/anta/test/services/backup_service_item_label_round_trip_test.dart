import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/counter_service.dart';

/// Colour labels ride into the backup as an **additive** key on the existing
/// note and folder maps, so the backup version does not move. That buys two
/// obligations this file holds: a label written today comes back out of an
/// export, and a backup made before labels existed — no `label` key at all —
/// still imports, with everything unlabelled rather than red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_label');
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

  test('a labelled note and folder survive export and re-import', () async {
    final db = await AppDatabase.getInstance();
    final folder = await db.folderDao.createFolder(
      name: 'Labelled folder',
      label: ItemLabel.teal,
    );
    final note = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Labelled note',
      label: ItemLabel.pink,
    );
    await db.contentChunkDao.saveContent(noteId: note.id, content: 'body');

    final backup = await BackupService.getInstance();
    final exported = await backup.exportAllData();

    final exportedFolder = (exported['folders'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((f) => f[JsonKeys.name] == 'Labelled folder');
    final exportedNote = (exported['notes'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((n) => n[JsonKeys.title] == 'Labelled note');
    expect(exportedFolder[JsonKeys.label], 'teal');
    expect(
      exportedNote[JsonKeys.label],
      'pink',
      reason: 'the label travels as its name, not its index',
    );

    final result = await backup.importFromJson(jsonEncode(exported));
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final folders = await db.folderDao.getAllFolders(includeDeleted: false);
    final restoredFolders = folders.where(
      (f) => f.name == 'Labelled folder',
    );
    expect(restoredFolders, hasLength(2), reason: 'import appends a copy');
    expect(
      restoredFolders.every(
        (f) => ItemLabel.fromStorage(f.label) == ItemLabel.teal,
      ),
      isTrue,
    );

    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final restoredNotes = notes.where((n) => n.title == 'Labelled note');
    expect(restoredNotes, hasLength(2));
    expect(
      restoredNotes.every(
        (n) => ItemLabel.fromStorage(n.label) == ItemLabel.pink,
      ),
      isTrue,
    );
  });

  test('a backup written before labels existed imports unlabelled', () async {
    final archive = jsonEncode({
      'version': 1,
      'folders': <Map<String, dynamic>>[
        {JsonKeys.name: 'Legacy folder', JsonKeys.parentId: null},
      ],
      'notes': <Map<String, dynamic>>[
        {
          JsonKeys.folderId: 'root',
          JsonKeys.title: 'Legacy note',
          JsonKeys.content: 'nothing colourful here',
        },
      ],
      'settings': const <String, dynamic>{},
    });

    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(archive);
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final db = await AppDatabase.getInstance();
    final folder = (await db.folderDao.getAllFolders(
      includeDeleted: false,
    )).firstWhere((f) => f.name == 'Legacy folder');
    final note = (await db.noteDao.getAllNotes(
      includeDeleted: false,
    )).firstWhere((n) => n.title == 'Legacy note');

    expect(ItemLabel.fromStorage(folder.label), ItemLabel.none);
    expect(ItemLabel.fromStorage(note.label), ItemLabel.none);
  });

  test('an unknown colour name in a backup imports as none', () async {
    final archive = jsonEncode({
      'version': 7,
      'folders': <Map<String, dynamic>>[
        {
          JsonKeys.name: 'Future folder',
          JsonKeys.parentId: null,
          JsonKeys.label: 'chartreuse',
        },
      ],
      'notes': const <Map<String, dynamic>>[],
      'settings': const <String, dynamic>{},
    });

    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(archive);
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final db = await AppDatabase.getInstance();
    final folder = (await db.folderDao.getAllFolders(
      includeDeleted: false,
    )).firstWhere((f) => f.name == 'Future folder');
    expect(ItemLabel.fromStorage(folder.label), ItemLabel.none);
  });
}
