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

/// The restore replays rows the sync merge converges, so it must put back
/// what the archive carries rather than stamping the restore's own time:
/// `created_at`, `updated_at` and a folder's two sort preferences (A3a
/// review R62). `position` is deliberately not among them — a restored row
/// is appended, so it cannot fight the ordering already in the database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_dates');
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

  test('a restored folder and note keep their archived dates and sort '
      'orders', () async {
    final db = await AppDatabase.getInstance();
    // Whole seconds: the columns hold no finer precision.
    final created = DateTime(2024, 3, 4, 5, 6, 7);
    final updated = DateTime(2025, 8, 9, 10, 11, 12);
    final folder = await db.folderDao.importFolder(
      name: 'Dated folder',
      createdAt: created,
      updatedAt: updated,
      noteSortOrder: 'titleAsc',
      subfolderSortOrder: 'createdDesc',
    );
    await db.noteDao.importNote(
      folderId: folder.id,
      title: 'Dated note',
      createdAt: created,
      updatedAt: updated,
      content: 'body',
    );

    final backup = await BackupService.getInstance();
    final exported = await backup.exportAllData();
    final result = await backup.importFromJson(jsonEncode(exported));
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final folders = await db.folderDao.getAllFolders(includeDeleted: false);
    final restoredFolder = folders.firstWhere(
      (f) => f.name == 'Dated folder' && f.id != folder.id,
    );
    expect(restoredFolder.createdAt, created);
    expect(restoredFolder.updatedAt, updated);
    expect(restoredFolder.noteSortOrder, 'titleAsc');
    expect(restoredFolder.subfolderSortOrder, 'createdDesc');
    // The rule the comment above states, asserted: `importFolder` appends as
    // `createFolder` does, so a later session cannot "finish" R62 by
    // preserving the archived position (A6 review R123).
    expect(
      restoredFolder.position,
      greaterThan(folder.position),
      reason: 'a restored folder is appended, never given its old position',
    );

    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final restoredNote = notes.firstWhere(
      (n) => n.title == 'Dated note' && n.folderId == restoredFolder.id,
    );
    expect(restoredNote.createdAt, created);
    expect(restoredNote.updatedAt, updated);
  });

  test(
    'an archive that carries no dates or sort orders still restores',
    () async {
      final db = await AppDatabase.getInstance();
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      final archive = {
        'version': 7,
        'folders': [
          {JsonKeys.id: 'old-folder', JsonKeys.name: 'Undated folder'},
        ],
        'notes': [
          {
            JsonKeys.id: 'old-note',
            JsonKeys.folderId: 'old-folder',
            JsonKeys.title: 'Undated note',
            JsonKeys.content: 'body',
          },
        ],
      };

      final backup = await BackupService.getInstance();
      final result = await backup.importFromJson(jsonEncode(archive));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      final folders = await db.folderDao.getAllFolders(includeDeleted: false);
      final restoredFolder = folders.firstWhere(
        (f) => f.name == 'Undated folder',
      );
      expect(restoredFolder.createdAt.isAfter(before), isTrue);
      expect(restoredFolder.updatedAt.isAfter(before), isTrue);
      expect(restoredFolder.noteSortOrder, isNull);
      expect(restoredFolder.subfolderSortOrder, isNull);

      final notes = await db.noteDao.getAllNotes(includeDeleted: false);
      final restoredNote = notes.firstWhere((n) => n.title == 'Undated note');
      expect(restoredNote.createdAt.isAfter(before), isTrue);
      expect(restoredNote.folderId, restoredFolder.id);
    },
  );
}
