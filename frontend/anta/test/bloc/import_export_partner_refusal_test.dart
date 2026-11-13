import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/bloc/import_export/import_export_state.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// A partner's rows never leave this phone by file
/// (`docs/cloud-share-surfaces-roadmap.md` D19): "Send a copy" of their note
/// or folder, or a selection holding one, is refused before any file is
/// written, as a failure the page shows plainly; my own exports are as they
/// were.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const partner = 'partner';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppDatabase db;
  late ImportExportService service;
  late NoteStorageService notes;
  late Directory dir;
  late String mine;
  late String myNote;
  late String theirs;
  late String theirNote;

  setUp(() async {
    db = await openTestDatabase();
    final noteRepository = NoteRepository(database: db);
    notes = NoteStorageService(repository: noteRepository);
    service = ImportExportService(
      noteStorage: notes,
      folderStorage: FolderStorageService(
        repository: FolderRepository(database: db),
      ),
      noteRepository: noteRepository,
    );
    dir = await Directory.systemTemp.createTemp('anta_partner_export');
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );

    mine = (await db.folderDao.createFolder(name: 'Mine')).id;
    myNote = (await db.noteDao.createNote(
      folderId: mine,
      title: 'My note',
      preview: 'my text',
      content: 'my text',
    )).id;
    theirs = (await db.folderDao.createFolder(name: 'Theirs')).id;
    theirNote = (await db.noteDao.createNote(
      folderId: theirs,
      title: 'Their note',
      preview: 'their text',
      content: 'their text',
    )).id;
    for (final (table, id) in [('folders', theirs), ('notes', theirNote)]) {
      await db.customStatement(
        "UPDATE $table SET owner_id = '$partner' WHERE id = ?",
        [id],
      );
    }
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
  });

  tearDown(() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  List<FileSystemEntity> written() => dir.listSync(recursive: true);

  Future<ImportExportState> run(ImportExportEvent event) async {
    final bloc = ImportExportBloc(service: service);
    addTearDown(bloc.close);
    final settled = bloc.stream.firstWhere(
      (state) => state is ImportExportFailure || state is ImportExportExportSuccess,
    );
    bloc.add(event);
    return settled;
  }

  test('their note, their folder or a selection holding one is refused '
      'before any file is written', () async {
    final theirMetadata = (await notes.getNoteMetadata(theirNote))!;
    for (final event in <ImportExportEvent>[
      ExportNoteRequested(
        metadata: theirMetadata,
        format: ExportFormat.json,
        share: true,
      ),
      ExportFolderRequested(folderId: theirs, share: true),
      ExportItemsRequested(
        noteIds: {myNote, theirNote},
        folderIds: const {},
        noteFormat: ExportFormat.json,
      ),
      ExportItemsRequested(
        noteIds: const {},
        folderIds: {mine, theirs},
        noteFormat: ExportFormat.json,
      ),
    ]) {
      final state = await run(event);

      expect(state, isA<ImportExportFailure>());
      expect((state as ImportExportFailure).refusedShared, isTrue);
    }
    expect(written(), isEmpty);
  });

  test('my own note exports as it always did', () async {
    final myMetadata = (await notes.getNoteMetadata(myNote))!;

    final state = await run(
      ExportNoteRequested(metadata: myMetadata, format: ExportFormat.markdown),
    );

    expect(state, isA<ImportExportExportSuccess>());
    final file = File((state as ImportExportExportSuccess).result.filePath);
    expect(await file.readAsString(), '# My note\n\nmy text');
  });

  test('a folder of mine never holds a row of theirs, so its archive needs '
      'no filter: the fences keep their note out of it', () async {
    await db.customStatement('UPDATE notes SET folder_id = ? WHERE id = ?', [
      mine,
      theirNote,
    ]);
    expect(
      (await db.noteDao.getByIdsIncludingDeleted([theirNote])).single.folderId,
      theirs,
    );

    final result = await service.exportFolder(folderId: mine);

    expect(result.notesExported, 1);
  });
}
