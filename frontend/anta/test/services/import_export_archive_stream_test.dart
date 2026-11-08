import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// The folder archive written and read entry by entry (S18 of
/// `docs/scalability-roadmap.md`): the export streams each entry into the
/// file as the walk reaches it, under a provisional name until it is whole,
/// and the import reads one entry at a time from the file.
///
/// Memory itself is not measured here. What is pinned is the shape that
/// bounds it: every note's entry is in the output before the walk reads the
/// next note, which an archive built in memory and encoded at the end could
/// not do. The archive itself keeps the names, order and decompressed
/// contents it always had; its bytes are not pinned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late _RecordingNoteRepository notes;
  late NoteStorageService noteStorage;
  late _WatchedService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('anta_archive_stream');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await openTestDatabase();
    notes = _RecordingNoteRepository(database: db);
    noteStorage = NoteStorageService(repository: notes);
    await noteStorage.initialize();
    final folderStorage = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderStorage.initialize();
    service = _WatchedService(
      noteStorage: noteStorage,
      folderStorage: folderStorage,
      noteRepository: notes,
    );
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Directory exportDirectory() =>
      Directory(p.join(tempDir.path, ImportExportService.exportDirectoryName));

  /// The archive at [path], read whole — fine for a test's few entries.
  Archive readArchive(String path) =>
      ZipDecoder().decodeBytes(File(path).readAsBytesSync());

  /// `Training` holding two notes and `Training/Week 1` holding one, plus a
  /// loose note elsewhere — returned as (root folder id, loose note id).
  Future<(String, String)> seedTree() async {
    final elsewhere = await db.folderDao.createFolder(name: 'Elsewhere');
    final loose = await noteStorage.createNote(
      folderId: elsewhere.id,
      title: 'Loose',
      content: 'a note picked on its own',
    );
    final root = await db.folderDao.createFolder(name: 'Training');
    await noteStorage.createNote(
      folderId: root.id,
      title: 'Squat',
      content: 'five by five',
    );
    await noteStorage.createNote(
      folderId: root.id,
      title: 'Bench',
      content: 'three by eight',
    );
    final week = await db.folderDao.createFolder(
      name: 'Week 1',
      parentId: root.id,
    );
    await noteStorage.createNote(
      folderId: week.id,
      title: 'Deadlift',
      content: 'one heavy single',
    );
    return (root.id, loose.id);
  }

  group('export', () {
    test('a selection keeps its entry names, their order and their '
        'decompressed contents', () async {
      final (rootId, looseId) = await seedTree();
      final folderNotes = await noteStorage.loadAllMetadataForFolder(rootId);
      final firstTwo = [for (final note in folderNotes) note.title];

      final result = await service.exportItems(
        noteIds: {looseId},
        folderIds: {rootId},
        noteFormat: ExportFormat.json,
      );

      final archive = readArchive(result.filePath);
      expect(
        [for (final file in archive.files) file.name],
        [
          'Loose.json',
          'Training/_folder.json',
          for (final title in firstTwo) 'Training/$title.json',
          'Training/Week 1/_folder.json',
          'Training/Week 1/Deadlift.json',
          'manifest.json',
        ],
      );
      Map<String, dynamic> json(String name) =>
          jsonDecode(utf8.decode(archive.findFile(name)!.content))
              as Map<String, dynamic>;
      expect(json('Loose.json')[JsonKeys.content], 'a note picked on its own');
      expect(json('Training/Squat.json')[JsonKeys.content], 'five by five');
      expect(json('Training/Bench.json')[JsonKeys.content], 'three by eight');
      expect(json('Training/Week 1/Deadlift.json')[JsonKeys.title], 'Deadlift');
      expect(json('Training/Week 1/_folder.json')[JsonKeys.name], 'Week 1');
      final manifest = json('manifest.json');
      expect(
        manifest[ImportExportService.archiveVersionKey],
        ImportExportService.archiveVersion,
      );
      expect(manifest['folderCount'], 2);
      expect(manifest['noteCount'], 4);
      expect(manifest['selection'], isTrue);
      expect(result.foldersExported, 2);
      expect(result.notesExported, 4);
    });

    test('the archive is named once it is whole, after the single item it '
        'holds', () async {
      final (rootId, looseId) = await seedTree();

      final folder = await service.exportItems(
        noteIds: const {},
        folderIds: {rootId},
        noteFormat: ExportFormat.markdown,
      );
      final note = await service.exportItems(
        noteIds: {looseId},
        folderIds: const {},
        noteFormat: ExportFormat.text,
      );
      final both = await service.exportFolder(folderId: rootId);

      expect(p.dirname(folder.filePath), exportDirectory().path);
      expect(p.basename(folder.filePath), startsWith('Training_'));
      expect(p.basename(note.filePath), startsWith('Loose_'));
      expect(p.basename(both.filePath), startsWith('Training_'));
      for (final result in [folder, note, both]) {
        expect(p.extension(result.filePath), '.zip');
      }
      expect(
        [
          for (final file in exportDirectory().listSync())
            p.extension(file.path),
        ],
        everyElement('.zip'),
        reason: 'no provisional file is left once an archive is whole',
      );
    });

    test(
      'every note is in the file before the walk reads the next one',
      () async {
        final root = await db.folderDao.createFolder(name: 'Log');
        // Each note deflates to more than the stream's 1 MB buffer, so its
        // entry has to reach the file itself, not only the buffer, as it is
        // added — which an archive built in memory and encoded at the end
        // would never do before the walk was over.
        final random = Random(18);
        for (var i = 0; i < 3; i++) {
          await noteStorage.createNote(
            folderId: root.id,
            title: 'Scan $i',
            content: base64Encode([
              for (var b = 0; b < 1400000; b++) random.nextInt(256),
            ]),
          );
        }
        notes.onLoad = () => service.handle!.position;

        await service.exportFolder(folderId: root.id);

        final written = notes.observed;
        expect(written, hasLength(3));
        for (var i = 1; i < written.length; i++) {
          expect(
            written[i],
            greaterThan(written[i - 1] + 1000000),
            reason: 'note ${i - 1} reached the file before note $i was read',
          );
        }
      },
    );

    test('entries are deflated at level 1', () async {
      final root = await db.folderDao.createFolder(name: 'Log');
      // Varied enough that level 1 and level 6 deflate it to different sizes.
      final body = [
        for (var i = 0; i < 400; i++) 'set $i: ${i * 7 % 13} reps at ${i % 9}0',
      ].join('\n');
      await noteStorage.createNote(
        folderId: root.id,
        title: 'Session 0',
        content: body,
      );

      final result = await service.exportFolder(folderId: root.id);

      final decoder = ZipDecoder()
        ..decodeBytes(File(result.filePath).readAsBytesSync());
      final header = decoder.directory.fileHeaders.firstWhere(
        (header) => header.filename == 'Log/Session 0.json',
      );
      final entry = readArchive(
        result.filePath,
      ).findFile(header.filename)!.content;
      final levelOne = ZLibCodec(level: 1, raw: true).encode(entry).length;
      final levelSix = ZLibCodec(level: 6, raw: true).encode(entry).length;
      expect(levelOne, isNot(levelSix));
      expect(header.compressedSize, levelOne);
    });

    test('a walk that fails part-way closes the file and deletes the '
        'partial archive', () async {
      final (rootId, _) = await seedTree();
      notes.failOnLoad = notes.loads + 2;

      await expectLater(
        service.exportFolder(folderId: rootId),
        throwsA(isA<StateError>()),
      );

      expect(service.handle!.isOpen, isFalse);
      // On Windows a file still open could not have been deleted.
      expect(exportDirectory().listSync(), isEmpty);
    });

    // A write that fails (a full disk) fails again on the stream's own close,
    // which flushes first; the handle is closed directly instead.
    for (final (failure, wrap)
        in <(String, AbstractFileHandle Function(AbstractFileHandle))>[
          ('a write', (real) => _FailingHandle(real, failWrites: true)),
          ('the close', (real) => _FailingHandle(real, failFirstClose: true)),
        ]) {
      test('$failure that fails closes the file and leaves nothing under the '
          'export folder', () async {
        final (rootId, _) = await seedTree();
        service.wrap = wrap;

        await expectLater(
          service.exportFolder(folderId: rootId),
          throwsA(isA<FileSystemException>()),
        );

        expect(service.handle!.isOpen, isFalse);
        expect(exportDirectory().listSync(), isEmpty);
      });
    }

    test('sibling folders whose names clean up alike get names of their own, '
        'and both import back whole', () async {
      final root = await db.folderDao.createFolder(name: 'Root');
      for (final name in ['A:B', 'A_B']) {
        final folder = await db.folderDao.createFolder(
          name: name,
          parentId: root.id,
        );
        await noteStorage.createNote(
          folderId: folder.id,
          title: 'Note',
          content: 'in $name',
        );
      }

      final exported = await service.exportFolder(folderId: root.id);

      final names = [
        for (final file in readArchive(exported.filePath).files) file.name,
      ];
      expect(names.toSet(), hasLength(names.length), reason: 'no duplicates');
      expect(
        names,
        containsAll(['Root/A_B/Note.json', 'Root/A_B (2)/Note.json']),
      );
      final manifest =
          jsonDecode(
                utf8.decode(
                  readArchive(
                    exported.filePath,
                  ).findFile('manifest.json')!.content,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['folderCount'], 3);
      expect(manifest['noteCount'], 2);

      final target = await db.folderDao.createFolder(name: 'Target');
      final result = await service.importArchive(
        filePath: exported.filePath,
        targetParentFolderId: target.id,
      );

      expect(result.foldersImported, 3);
      expect(result.notesImported, 2);
      final copy = (await db.folderDao.getFoldersByParent(target.id)).single;
      final children = await db.folderDao.getFoldersByParent(copy.id);
      expect({for (final child in children) child.name}, {'A:B', 'A_B'});
      for (final child in children) {
        final note = (await db.noteDao.getNotesByFolder(child.id)).single;
        expect(await notes.loadContent(note.id), 'in ${child.name}');
      }
    });
  });

  group('import', () {
    test('an exported archive imports back whole, and the file is released '
        'after', () async {
      final (rootId, _) = await seedTree();
      final exported = await service.exportFolder(folderId: rootId);
      final target = await db.folderDao.createFolder(name: 'Target');

      final result = await service.importArchive(
        filePath: exported.filePath,
        targetParentFolderId: target.id,
      );

      expect(result.foldersImported, 2);
      expect(result.notesImported, 3);
      final training = (await db.folderDao.getFoldersByParent(
        target.id,
      )).single;
      final week = (await db.folderDao.getFoldersByParent(training.id)).single;
      expect(week.name, 'Week 1');
      final deadlift = (await db.noteDao.getNotesByFolder(week.id)).single;
      expect(await notes.loadContent(deadlift.id), 'one heavy single');
      // The one stream over the file is closed, so it can go.
      File(exported.filePath).deleteSync();
    });

    test('a malformed note is skipped and the rest still import, and an '
        'archive refused part-way still releases the file', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final path = p.join(tempDir.path, 'handmade.zip');
      final archive = Archive()
        ..add(ArchiveFile.string('Kept/_folder.json', '{"name": "Kept"}'))
        ..add(ArchiveFile.string('Kept/broken.json', '[1, 2'))
        ..add(
          ArchiveFile.string(
            'Kept/fine.json',
            jsonEncode({JsonKeys.title: 'Fine', JsonKeys.content: 'body'}),
          ),
        );
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.foldersImported, 1);
      expect(result.notesImported, 1);
      File(path).deleteSync();

      // Loose notes with nowhere to land are refused before any write.
      final loose = Archive()
        ..add(ArchiveFile.string('alone.json', jsonEncode({'title': 'A'})));
      File(path).writeAsBytesSync(ZipEncoder().encode(loose));
      await expectLater(
        service.importArchive(filePath: path),
        throwsA(isA<FormatException>()),
      );
      File(path).deleteSync();
    });
  });

  group('the launch sweep', () {
    File writeFile(String relative, {bool stale = false}) {
      final file = File(p.join(tempDir.path, relative))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      if (stale) {
        file.setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 3)),
        );
      }
      return file;
    }

    test('deletes only what is ANTA\'s own, whatever its age', () async {
      final ours = [
        writeFile('${ImportExportService.exportDirectoryName}/Note.md'),
        writeFile('${ImportExportService.exportDirectoryName}/archive_1.part'),
        writeFile('anta_events_1.ics'),
        writeFile('anta_report_1.md'),
        writeFile('${DatabaseManager.shareSnapshotPrefix}1/gym_notes.db'),
      ];
      final theirs = [
        writeFile('Training_2026.zip'),
        writeFile('notes.md'),
        writeFile('another_app/cache.json'),
        writeFile('anta_unrelated/kept.zip'),
      ];

      // A cutoff in the future makes every entry old enough.
      await service.sweepStaleExports(maxAge: const Duration(seconds: -5));

      for (final file in ours) {
        expect(file.existsSync(), isFalse, reason: file.path);
      }
      expect(
        Directory(
          p.join(tempDir.path, '${DatabaseManager.shareSnapshotPrefix}1'),
        ).existsSync(),
        isFalse,
      );
      for (final file in theirs) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });

    test('keeps what is ANTA\'s own but recent', () async {
      final stale = writeFile(
        '${ImportExportService.exportDirectoryName}/Old.zip',
        stale: true,
      );
      final fresh = writeFile(
        '${ImportExportService.exportDirectoryName}/New.zip',
      );
      final staleIcs = writeFile('anta_events_1.ics', stale: true);

      await service.sweepStaleExports();

      expect(stale.existsSync(), isFalse);
      expect(staleIcs.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });
  });
}

/// The service with the archive's real file handle kept for the test to
/// read, and handed to the archive through [wrap] when one is set.
class _WatchedService extends ImportExportService {
  _WatchedService({
    required super.noteStorage,
    required super.folderStorage,
    required super.noteRepository,
  });

  AbstractFileHandle? handle;
  AbstractFileHandle Function(AbstractFileHandle real)? wrap;

  @override
  AbstractFileHandle openArchiveHandle(String path) {
    final real = handle = super.openArchiveHandle(path);
    return wrap?.call(real) ?? real;
  }
}

/// A real file handle whose writes fail like a full disk's, or whose first
/// close fails before it closes anything.
class _FailingHandle extends AbstractFileHandle {
  _FailingHandle(
    this._real, {
    this.failWrites = false,
    this.failFirstClose = false,
  });

  final AbstractFileHandle _real;
  final bool failWrites;
  bool failFirstClose;

  @override
  int get position => _real.position;

  @override
  set position(int p) => _real.position = p;

  @override
  int get length => _real.length;

  @override
  bool get isOpen => _real.isOpen;

  @override
  Future<void> close() async {
    if (failFirstClose) {
      failFirstClose = false;
      throw const FileSystemException('close failed');
    }
    await _real.close();
  }

  @override
  void closeSync() => _real.closeSync();

  @override
  int readInto(Uint8List buffer, [int? length]) =>
      _real.readInto(buffer, length);

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    if (failWrites) throw const FileSystemException('No space left on device');
    _real.writeFromSync(buffer, start, end);
  }
}

/// The repository with a probe on every body read: [onLoad]'s answer is
/// recorded before the body is returned, and the read that brings [loads] to
/// [failOnLoad] throws.
class _RecordingNoteRepository extends NoteRepository {
  _RecordingNoteRepository({required super.database});

  int Function()? onLoad;
  int? failOnLoad;
  final observed = <int>[];
  var loads = 0;

  @override
  Future<String> loadContent(String noteId, {bool forceRefresh = false}) {
    loads++;
    if (loads == failOnLoad) {
      throw StateError('read $loads failed');
    }
    final probe = onLoad;
    if (probe != null) observed.add(probe());
    return super.loadContent(noteId, forceRefresh: forceRefresh);
  }
}
