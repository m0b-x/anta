import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/bloc/import_export/import_export_state.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// An archive import that left files out says how many: the bloc carries
/// the importer's skipped count to the page, which would otherwise report
/// a clean import over lost notes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late ImportExportBloc bloc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_import_skipped');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await openTestDatabase();
    final notes = NoteRepository(database: db);
    bloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: db),
        ),
        noteRepository: notes,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('an archive import reports the files it could not read', () async {
    final target = await db.folderDao.createFolder(name: 'Target');
    // "café" in Latin-1, and JSON cut off mid-array.
    const latin1 = [0x63, 0x61, 0x66, 0xE9];
    final archive = Archive()
      ..add(ArchiveFile('A/latin1.txt', latin1.length, latin1))
      ..add(ArchiveFile.string('A/broken.json', '[1, 2'))
      ..add(ArchiveFile.string('A/good.md', '# Good\n\nbody'));
    final path = p.join(tempDir.path, 'skipped.zip');
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    final done = bloc.stream.firstWhere(
      (state) => state is! ImportExportInProgress,
    );

    bloc.add(
      ImportArchiveRequested(filePath: path, targetParentFolderId: target.id),
    );
    final end = await done;

    expect(end, isA<ImportExportImportSuccess>());
    final result = (end as ImportExportImportSuccess).result;
    expect(result.notesImported, 1);
    expect(result.notesSkipped, 2);
  });

  test('two imports that differ only in what was skipped are two states', () {
    ImportExportImportSuccess of(int skipped) => ImportExportImportSuccess(
      operation: ImportExportOperation.importArchive,
      result: ConvertImportResult(
        foldersImported: 1,
        notesImported: 3,
        notesSkipped: skipped,
      ),
    );

    expect(of(0), isNot(of(1)));
    expect(of(1), of(1));
  });
}
