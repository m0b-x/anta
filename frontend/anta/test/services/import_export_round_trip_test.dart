import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show InvalidDataException, Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// What an export followed by an import keeps: a Markdown note's body to the
/// character, the folders' manual order and their `updatedAt`, and a title
/// that collides at the column's limit, which is cut to make room for its
/// number rather than refusing the rest of the archive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late NoteStorageService noteStorage;
  late ImportExportService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('anta_round_trip');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await openTestDatabase();
    final notes = NoteRepository(database: db);
    noteStorage = NoteStorageService(repository: notes);
    await noteStorage.initialize();
    final folderStorage = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderStorage.initialize();
    service = ImportExportService(
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

  /// A `.zip` holding [entries] as UTF-8 text, in the order given.
  String writeZip(Map<String, String> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.add(ArchiveFile.string(entry.key, entry.value));
    }
    final path = p.join(tempDir.path, 'handmade.zip');
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  group('a Markdown note', () {
    final bodies = {
      'four spaces': '    indented code\n- item',
      'a tab': '\tindented\n  - nested item',
      'two blank lines': '\n\nafter two blank lines',
      'ordinary text': 'Plain text\n\n- item',
    };
    for (final MapEntry(key: opening, value: body) in bodies.entries) {
      test('opening with $opening comes back as it left', () async {
        final source = await db.folderDao.createFolder(name: 'Source');
        final target = await db.folderDao.createFolder(name: 'Target');
        final note = await noteStorage.createNote(
          folderId: source.id,
          title: 'Opening',
          content: body,
        );

        final exported = await service.exportNote(
          metadata: note,
          format: ExportFormat.markdown,
        );
        await service.importFile(
          filePath: exported.filePath,
          targetFolderId: target.id,
        );

        final copy = (await db.noteDao.getNotesByFolder(target.id)).single;
        expect(copy.title, 'Opening');
        expect(await noteStorage.loadNoteContent(copy.id), body);
      });
    }

    test('takes a line of spaces or tabs after the title as the one blank '
        'line, and keeps the blank lines past it', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final spaced = File(p.join(tempDir.path, 'spaced.md'))
        ..writeAsStringSync('# Spaced\n \t \nbody');
      final three = File(p.join(tempDir.path, 'three.md'))
        ..writeAsStringSync('# Three\n\n\n\nbody');

      await service.importFile(
        filePath: spaced.path,
        targetFolderId: target.id,
      );
      await service.importFile(filePath: three.path, targetFolderId: target.id);

      final notes = await db.noteDao.getNotesByFolder(target.id);
      Future<String> body(String title) => noteStorage.loadNoteContent(
        notes.firstWhere((n) => n.title == title).id,
      );
      expect(await body('Spaced'), 'body');
      expect(await body('Three'), '\n\nbody');
    });

    test('written by hand without the blank line keeps its body', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final file = File(p.join(tempDir.path, 'by_hand.md'))
        ..writeAsStringSync('# By hand\n    code right under the title');

      await service.importFile(filePath: file.path, targetFolderId: target.id);

      final copy = (await db.noteDao.getNotesByFolder(target.id)).single;
      expect(copy.title, 'By hand');
      expect(
        await noteStorage.loadNoteContent(copy.id),
        '    code right under the title',
      );
    });
  });

  group('a name taken at the column limit', () {
    test('a note title gets its number inside the limit, and the rest of '
        'the archive still imports', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final title = 'x' * AppConstants.maxNoteTitleLength;
      await noteStorage.createNote(
        folderId: target.id,
        title: title,
        content: 'here',
      );
      final path = writeZip({
        'long.json': jsonEncode({
          JsonKeys.title: title,
          JsonKeys.content: 'archived',
        }),
        'later.json': jsonEncode({
          JsonKeys.title: 'Later',
          JsonKeys.content: 'after it',
        }),
      });

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.notesImported, 2);
      final titles = [
        for (final note in await db.noteDao.getNotesByFolder(target.id))
          note.title,
      ];
      final numbered = '${'x' * (AppConstants.maxNoteTitleLength - 4)} (2)';
      expect(titles, unorderedEquals([title, numbered, 'Later']));
      expect(numbered.length, AppConstants.maxNoteTitleLength);
    });

    test('a folder name gets its number inside the limit', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final name = 'f' * AppConstants.maxFolderNameLength;
      await db.folderDao.createFolder(name: name, parentId: target.id);
      final path = writeZip({
        'Long/_folder.json': jsonEncode({JsonKeys.name: name}),
        'Long/inside.json': jsonEncode({JsonKeys.title: 'Inside'}),
      });

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.foldersImported, 1);
      expect(result.notesImported, 1);
      final names = [
        for (final folder in await db.folderDao.getFoldersByParent(target.id))
          folder.name,
      ];
      expect(
        names,
        unorderedEquals([
          name,
          '${'f' * (AppConstants.maxFolderNameLength - 4)} (2)',
        ]),
      );
    });
  });

  group('a folder archive', () {
    /// `Parent` with its children placed by hand in [order] — never the
    /// order of their names — and two notes whose stored order is the
    /// reverse of their creation.
    Future<String> seedOrdered(List<String> order) async {
      final parent = await db.folderDao.importFolder(
        name: 'Parent',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2025, 6, 7, 8, 9, 10),
      );
      final created = <String, String>{};
      for (final name in [...order]..sort()) {
        final child = await db.folderDao.createFolder(
          name: name,
          parentId: parent.id,
        );
        created[name] = child.id;
      }
      for (final (index, name) in order.indexed) {
        await db.customStatement(
          'UPDATE folders SET position = ? WHERE id = ?',
          [index, created[name]],
        );
      }
      final first = await noteStorage.createNote(
        folderId: parent.id,
        title: 'n-first',
        content: 'a',
      );
      final second = await noteStorage.createNote(
        folderId: parent.id,
        title: 'n-second',
        content: 'b',
      );
      await db.customStatement('UPDATE notes SET position = 0 WHERE id = ?', [
        second.id,
      ]);
      await db.customStatement('UPDATE notes SET position = 1 WHERE id = ?', [
        first.id,
      ]);
      return parent.id;
    }

    test('keeps the folders\' manual order, the notes\' order and the '
        'folders\' updatedAt', () async {
      const order = ['Zeta', 'alpha', 'Beta'];
      final parentId = await seedOrdered(order);
      final exported = await service.exportFolder(folderId: parentId);
      final target = await db.folderDao.createFolder(name: 'Target');

      final imported = await service.importArchive(
        filePath: exported.filePath,
        targetParentFolderId: target.id,
      );

      final copy = await db.folderDao.getFolderById(
        imported.createdRootFolderIds.single,
      );
      expect(copy!.updatedAt, DateTime(2025, 6, 7, 8, 9, 10));
      final kids = await db.folderDao.getFoldersByParent(copy.id);
      expect([for (final kid in kids) kid.name], order);
      final notes = (await db.noteDao.getNotesByFolder(copy.id))
        ..sort((a, b) => a.position.compareTo(b.position));
      expect([for (final note in notes) note.title], ['n-second', 'n-first']);
    });

    test('from an older build, without updatedAt, is stamped now and '
        'recreated in its entries\' order', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final path = writeZip({
        'Old/_folder.json': jsonEncode({
          JsonKeys.type: 'folder',
          JsonKeys.name: 'Old',
          JsonKeys.createdAt: DateTime(2023, 3, 4).toIso8601String(),
        }),
        'Old/b/_folder.json': jsonEncode({JsonKeys.name: 'b'}),
        'Old/A/_folder.json': jsonEncode({JsonKeys.name: 'A'}),
        'Old/A/deep/_folder.json': jsonEncode({JsonKeys.name: 'deep'}),
        'Old/C/_folder.json': jsonEncode({JsonKeys.name: 'C'}),
      });

      final imported = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(imported.foldersImported, 5);
      final copy = await db.folderDao.getFolderById(
        imported.createdRootFolderIds.single,
      );
      expect(copy!.createdAt, DateTime(2023, 3, 4));
      expect(copy.updatedAt.isAfter(before), isTrue);
      final kids = await db.folderDao.getFoldersByParent(copy.id);
      expect([for (final kid in kids) kid.name], ['b', 'A', 'C']);
      final a = kids.firstWhere((kid) => kid.name == 'A');
      expect(
        [for (final f in await db.folderDao.getFoldersByParent(a.id)) f.name],
        ['deep'],
      );
    });

    test('rebuilds a directory that has no entry of its own in its place, '
        'beside its first descendant', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final path = writeZip({
        'R/z/deep/x/n.md': '# n1\n\nx',
        'R/z/n.md': '# n2\n\nx',
        'R/a/n.md': '# n3\n\nx',
        'R/n.md': '# n4\n\nx',
      });

      await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      Future<List<String>> names(String parentId) async => [
        for (final f in await db.folderDao.getFoldersByParent(parentId)) f.name,
      ];
      Future<String> idOf(String parentId, String name) async =>
          (await db.folderDao.getFoldersByParent(
            parentId,
          )).firstWhere((f) => f.name == name).id;
      expect(await names(target.id), ['R']);
      final r = await idOf(target.id, 'R');
      expect(await names(r), ['z', 'a']);
      final z = await idOf(r, 'z');
      expect(await names(z), ['deep']);
      final deep = await idOf(z, 'deep');
      expect(await names(deep), ['x']);
      final x = await idOf(deep, 'x');
      expect(
        [for (final n in await db.noteDao.getNotesByFolder(x)) n.title],
        ['n1'],
      );
    });

    test('of several picked folders and loose notes keeps their stored '
        'order, whatever order they were picked in', () async {
      final root = await db.folderDao.createFolder(name: 'Root');
      final ids = <String, String>{};
      for (final name in ['Mmm', 'Aaa', 'Zzz']) {
        ids[name] = (await db.folderDao.createFolder(
          name: name,
          parentId: root.id,
        )).id;
      }
      final l2 = await noteStorage.createNote(
        folderId: root.id,
        title: 'L2',
        content: 'x',
      );
      final l1 = await noteStorage.createNote(
        folderId: root.id,
        title: 'L1',
        content: 'y',
      );
      final exported = await service.exportItems(
        noteIds: {l1.id, l2.id},
        folderIds: {ids['Zzz']!, ids['Mmm']!, ids['Aaa']!},
        noteFormat: ExportFormat.json,
      );
      final target = await db.folderDao.createFolder(name: 'Target');

      await service.importArchive(
        filePath: exported.filePath,
        targetParentFolderId: target.id,
      );

      expect(
        [
          for (final f in await db.folderDao.getFoldersByParent(target.id))
            f.name,
        ],
        ['Mmm', 'Aaa', 'Zzz'],
      );
      final notes = (await db.noteDao.getNotesByFolder(target.id))
        ..sort((a, b) => a.position.compareTo(b.position));
      expect([for (final n in notes) n.title], ['L2', 'L1']);
    });

    test('writes a folder\'s notes in their stored order, position then '
        'id, whatever the query returns', () async {
      final folder = await db.folderDao.createFolder(name: 'Tied');
      // Inserted in the order c, b, a; c and a share a position, as a merge
      // can leave them. The folder's index returns c, a, b (position, then
      // row id), so only the walk's own sort writes a, c, b.
      final now = DateTime(2026, 1, 1);
      await db.batch((batch) {
        for (final (id, position) in [('c', 5), ('b', 9), ('a', 5)]) {
          batch.insert(
            db.notes,
            NotesCompanion.insert(
              id: id,
              folderId: folder.id,
              title: id,
              position: Value(position),
              contentLength: const Value(1),
              chunkCount: const Value(1),
              hlcTimestamp: 'h$id',
              deviceId: 'd',
              createdAt: now,
              updatedAt: now,
            ),
          );
          batch.insert(
            db.contentChunks,
            ContentChunksCompanion.insert(
              id: '${id}_0',
              noteId: id,
              chunkIndex: 0,
              content: id,
              hlcTimestamp: 'h$id',
              deviceId: 'd',
            ),
          );
        }
      });

      final exported = await service.exportFolder(folderId: folder.id);

      final names = [
        for (final file
            in ZipDecoder()
                .decodeBytes(File(exported.filePath).readAsBytesSync())
                .files)
          if (file.name.endsWith('.json') &&
              !file.name.endsWith('_folder.json') &&
              file.name != 'manifest.json')
            p.posix.basenameWithoutExtension(file.name),
      ];
      expect(names, ['a', 'c', 'b']);
    });
  });

  group('a title or name past the column', () {
    test('a Markdown title is cut to fit, and the body keeps the file\'s '
        'whole text', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final title = 'y' * (AppConstants.maxNoteTitleLength + 100);
      final text = '# $title\n\nbody';
      final path = writeZip({'B/long.md': text, 'B/later.md': '# Later\n\nx'});

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.notesImported, 2);
      final folder = (await db.folderDao.getFoldersByParent(target.id)).single;
      final notes = await db.noteDao.getNotesByFolder(folder.id);
      final long = notes.firstWhere((n) => n.title != 'Later');
      expect(long.title, 'y' * AppConstants.maxNoteTitleLength);
      expect(await noteStorage.loadNoteContent(long.id), text);
    });

    test('a JSON title is cut to fit, and the whole title heads the '
        'content', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final title = 'y' * (AppConstants.maxNoteTitleLength + 100);
      final path = writeZip({
        'long.json': jsonEncode({
          JsonKeys.title: title,
          JsonKeys.content: 'body',
        }),
        'later.json': jsonEncode({JsonKeys.title: 'Later'}),
      });

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.notesImported, 2);
      final long = (await db.noteDao.getNotesByFolder(
        target.id,
      )).firstWhere((n) => n.title != 'Later');
      expect(long.title, 'y' * AppConstants.maxNoteTitleLength);
      expect(await noteStorage.loadNoteContent(long.id), '# $title\n\nbody');
    });

    test('a single Markdown file takes the same rule', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final title = 'y' * (AppConstants.maxNoteTitleLength + 1);
      final text = '# $title\n\nbody';
      final file = File(p.join(tempDir.path, 'long.md'))
        ..writeAsStringSync(text);

      await service.importFile(filePath: file.path, targetFolderId: target.id);

      final note = (await db.noteDao.getNotesByFolder(target.id)).single;
      expect(note.title, 'y' * AppConstants.maxNoteTitleLength);
      expect(await noteStorage.loadNoteContent(note.id), text);
    });

    test('a folder name is cut to fit, on a whole character', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      // The limit falls inside the last "é" (e + combining acute).
      final name = '${'f' * (AppConstants.maxFolderNameLength - 1)}étail';
      final path = writeZip({
        'B3/_folder.json': jsonEncode({JsonKeys.name: name}),
        'B3/later.md': '# Later\n\nx',
      });

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.foldersImported, 1);
      expect(result.notesImported, 1);
      expect(
        (await db.folderDao.getFoldersByParent(target.id)).single.name,
        'f' * (AppConstants.maxFolderNameLength - 1),
      );
    });

    test('a folder name that is one enormous character keeps the code '
        'units that fit, and the folder after it still imports', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      // One user-perceived character of 301 code units: no whole one fits.
      final name = 'e${'́' * 300}';
      final path = writeZip({
        'L/_folder.json': jsonEncode({JsonKeys.name: name}),
        'L/n.md': '# n\n\nx',
        'Later/n.md': '# n\n\nx',
      });

      final result = await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      expect(result.foldersImported, 2);
      expect(result.notesImported, 2);
      expect(
        [
          for (final f in await db.folderDao.getFoldersByParent(target.id))
            f.name,
        ],
        [name.substring(0, AppConstants.maxFolderNameLength), 'Later'],
      );
    });

    test('a note title that is one enormous character keeps the code units '
        'that fit, and the body the whole title', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final title = 'e${'́' * AppConstants.maxNoteTitleLength}';
      final path = writeZip({
        'huge.json': jsonEncode({
          JsonKeys.title: title,
          JsonKeys.content: 'body',
        }),
      });

      await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      final note = (await db.noteDao.getNotesByFolder(target.id)).single;
      expect(note.title, title.substring(0, AppConstants.maxNoteTitleLength));
      expect(await noteStorage.loadNoteContent(note.id), '# $title\n\nbody');
    });

    test('a title taken from a long file name is cut, and the body opens '
        'with the whole name', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final text = 'n' * (AppConstants.maxNoteTitleLength + 100);
      final markdown = 'm' * (AppConstants.maxNoteTitleLength + 100);
      final path = writeZip({
        '$text.txt': 'plain body',
        '$markdown.md': 'no heading here',
        'short.txt': 'kept as it is',
      });

      await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      final notes = await db.noteDao.getNotesByFolder(target.id);
      Future<String> body(String title) => noteStorage.loadNoteContent(
        notes.firstWhere((n) => n.title == title).id,
      );
      expect(
        await body('n' * AppConstants.maxNoteTitleLength),
        '# $text\n\nplain body',
      );
      expect(
        await body('m' * AppConstants.maxNoteTitleLength),
        '# $markdown\n\nno heading here',
      );
      expect(await body('short'), 'kept as it is');
    });
  });

  group('an entry path with . or .. segments', () {
    test('builds no folder named . or .., and nothing lands outside the '
        'target', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      final path = writeZip({
        'Z/../evil/n.md': '# n1\n\nx',
        '../up/n.md': '# n2\n\nx',
        'a/./b/n.md': '# n3\n\nx',
      });

      await service.importArchive(
        filePath: path,
        targetParentFolderId: target.id,
      );

      final all = await db.folderDao.getAllFolders();
      expect([for (final f in all) f.name], isNot(contains('..')));
      expect([for (final f in all) f.name], isNot(contains('.')));
      expect(all, hasLength(5), reason: 'Target, evil, up, a and b');
      Future<List<String>> names(String parentId) async => [
        for (final f in await db.folderDao.getFoldersByParent(parentId)) f.name,
      ];
      expect(await names(target.id), ['evil', 'up', 'a']);
      final a = (await db.folderDao.getFoldersByParent(
        target.id,
      )).firstWhere((f) => f.name == 'a');
      expect(await names(a.id), ['b']);
    });
  });

  group('a JSON note whose text is not a string', () {
    for (final (what, note) in [
      ('a number for a title', {JsonKeys.title: 5, JsonKeys.content: 'x'}),
      (
        'a list for its content',
        {
          JsonKeys.title: 'B',
          JsonKeys.content: [1],
        },
      ),
    ]) {
      test('with $what is skipped, and the rest imports', () async {
        final target = await db.folderDao.createFolder(name: 'Target');
        final path = writeZip({
          'A/bad.json': jsonEncode(note),
          'A/good.json': jsonEncode({
            JsonKeys.title: 'Good',
            JsonKeys.content: 'x',
          }),
        });

        final result = await service.importArchive(
          filePath: path,
          targetParentFolderId: target.id,
        );

        expect(result.notesImported, 1);
        final folder = (await db.folderDao.getFoldersByParent(
          target.id,
        )).single;
        expect(
          [
            for (final n in await db.noteDao.getNotesByFolder(folder.id))
              n.title,
          ],
          ['Good'],
        );
      });
    }
  });

  group('the limits match the columns', () {
    test(
      'a note title of exactly the limit inserts, one more is refused',
      () async {
        final folder = await db.folderDao.createFolder(name: 'F');
        await noteStorage.createNote(
          folderId: folder.id,
          title: 'n' * AppConstants.maxNoteTitleLength,
          content: '',
        );
        await expectLater(
          noteStorage.createNote(
            folderId: folder.id,
            title: 'm' * (AppConstants.maxNoteTitleLength + 1),
            content: '',
          ),
          throwsA(isA<InvalidDataException>()),
        );
      },
    );

    test(
      'a folder name of exactly the limit inserts, one more is refused',
      () async {
        await db.folderDao.createFolder(
          name: 'n' * AppConstants.maxFolderNameLength,
        );
        await expectLater(
          db.folderDao.createFolder(
            name: 'm' * (AppConstants.maxFolderNameLength + 1),
          ),
          throwsA(isA<InvalidDataException>()),
        );
      },
    );
  });
}
