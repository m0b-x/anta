import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// The colour label across the file boundary, in both directions.
///
/// The label is an **additive** key on the note JSON and on `_folder.json`,
/// carried without an archive-version bump, which means an archive written by
/// any build — including one whose `label` is a number because a hand-edited
/// file said so — has to import. A key that is read with a bare cast is one
/// malformed file away from aborting a whole folder import, and the file that
/// aborts it is the one the user most wants back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late NoteStorageService noteStorage;
  late FolderStorageService folderStorage;
  late ImportExportService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('anta_label_archive');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await openTestDatabase();
    noteStorage = NoteStorageService(repository: NoteRepository(database: db));
    await noteStorage.initialize();
    folderStorage = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderStorage.initialize();
    service = ImportExportService(
      noteStorage: noteStorage,
      folderStorage: folderStorage,
      noteRepository: NoteRepository(database: db),
    );
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<List<Note>> notesIn(String folderId) =>
      db.noteDao.getNotesByFolder(folderId);

  /// A zip written straight to disk, so a file no export would ever produce
  /// can still be handed to [ImportExportService.importArchive].
  Future<String> writeArchive(Map<String, Object?> filesByPath) async {
    final archive = Archive();
    for (final entry in filesByPath.entries) {
      final bytes = utf8.encode(jsonEncode(entry.value));
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    final file = File(p.join(tempDir.path, 'handmade.zip'));
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file.path;
  }

  test('a JSON note export carries the label and imports it back', () async {
    final source = await db.folderDao.createFolder(name: 'Source');
    final target = await db.folderDao.createFolder(name: 'Target');
    final note = await noteStorage.createNote(
      folderId: source.id,
      title: 'Zercher carry',
      content: 'heavy',
    );
    await db.noteDao.updateNoteLabel(id: note.id, label: ItemLabel.red);
    final labelled = await noteStorage.getNoteMetadata(note.id);

    final exported = await service.exportNote(
      metadata: labelled!,
      format: ExportFormat.json,
    );

    final decoded =
        jsonDecode(await File(exported.filePath).readAsString())
            as Map<String, dynamic>;
    expect(decoded[JsonKeys.label], ItemLabel.red.storageName);

    await service.importFile(
      filePath: exported.filePath,
      targetFolderId: target.id,
    );

    final imported = await notesIn(target.id);
    expect(imported, hasLength(1));
    expect(ItemLabel.fromStorage(imported.single.label), ItemLabel.red);
  });

  test('a markdown export carries no label, and imports unlabelled', () async {
    final source = await db.folderDao.createFolder(name: 'Source');
    final target = await db.folderDao.createFolder(name: 'Target');
    final note = await noteStorage.createNote(
      folderId: source.id,
      title: 'Plain',
      content: 'body',
    );
    await db.noteDao.updateNoteLabel(id: note.id, label: ItemLabel.pink);
    final labelled = await noteStorage.getNoteMetadata(note.id);

    final exported = await service.exportNote(
      metadata: labelled!,
      format: ExportFormat.markdown,
    );
    await service.importFile(
      filePath: exported.filePath,
      targetFolderId: target.id,
    );

    final imported = await notesIn(target.id);
    expect(
      ItemLabel.fromStorage(imported.single.label),
      ItemLabel.none,
      reason: 'markdown carries no metadata, so it cannot carry a label',
    );
  });

  test('a folder archive carries the folder label through importArchive', ()
      async {
    final root = await db.folderDao.createFolder(
      name: 'Training',
      label: ItemLabel.blue,
    );
    final note = await noteStorage.createNote(
      folderId: root.id,
      title: 'Session 1',
      content: 'squat',
    );
    await db.noteDao.updateNoteLabel(id: note.id, label: ItemLabel.teal);
    final destination = await db.folderDao.createFolder(name: 'Destination');

    final exported = await service.exportFolder(folderId: root.id);
    final result = await service.importArchive(
      filePath: exported.filePath,
      targetParentFolderId: destination.id,
    );

    expect(result.foldersImported, 1);
    expect(result.notesImported, 1);
    final recreated = await db.folderDao.getFoldersByParent(destination.id);
    expect(recreated, hasLength(1));
    expect(
      ItemLabel.fromStorage(recreated.single.label),
      ItemLabel.blue,
      reason: '`_folder.json` is where a folder\'s colour travels',
    );
    final importedNotes = await notesIn(recreated.single.id);
    expect(
      ItemLabel.fromStorage(importedNotes.single.label),
      ItemLabel.teal,
    );
  });

  test('a note whose label is a number imports unlabelled and does not abort '
      'the archive', () async {
    final destination = await db.folderDao.createFolder(name: 'Destination');
    final path = await writeArchive({
      'manifest.json': {
        JsonKeys.type: 'folderArchive',
        ImportExportService.archiveVersionKey:
            ImportExportService.archiveVersion,
        'rootName': 'Imported',
        'noteFormat': 'json',
      },
      'Imported/_folder.json': {
        JsonKeys.type: 'folder',
        JsonKeys.name: 'Imported',
        JsonKeys.label: 3,
      },
      'Imported/Broken.json': {
        JsonKeys.type: 'note',
        JsonKeys.title: 'Broken',
        JsonKeys.content: 'still worth keeping',
        JsonKeys.label: 3,
      },
      'Imported/Fine.json': {
        JsonKeys.type: 'note',
        JsonKeys.title: 'Fine',
        JsonKeys.content: 'green',
        JsonKeys.label: ItemLabel.green.storageName,
      },
    });

    final result = await service.importArchive(
      filePath: path,
      targetParentFolderId: destination.id,
    );

    expect(
      result.notesImported,
      2,
      reason: 'a bare cast on `label` threw here and took the note with it',
    );
    final recreated = await db.folderDao.getFoldersByParent(destination.id);
    expect(
      ItemLabel.fromStorage(recreated.single.label),
      ItemLabel.none,
      reason: 'an unreadable folder label degrades to none, not to a throw',
    );

    final imported = await notesIn(recreated.single.id);
    final byTitle = {for (final note in imported) note.title: note};
    expect(
      ItemLabel.fromStorage(byTitle['Broken']!.label),
      ItemLabel.none,
    );
    expect(
      ItemLabel.fromStorage(byTitle['Fine']!.label),
      ItemLabel.green,
      reason: 'the good file beside it keeps its colour',
    );
  });
}
