import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';

import 'package:anta/database/daos/shared_row_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/movable_item.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/duplicate_name_exception.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// Whose a note is and whether it lies in a folder the person shares, as
/// the browser, All notes, Recent, search and the editor read it
/// (`docs/cloud-share-surfaces-roadmap.md` §6.12–§6.13, D17–D19); the belt on
/// the partner's notes; and "Copy to my notes".
void main() {
  const partner = 'partner';

  late StatementCounter statements;
  late AppDatabase db;
  late NoteRepository repository;
  late NoteStorageService notes;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    repository = NoteRepository(database: db);
    notes = NoteStorageService(repository: repository);
  });
  tearDown(() async => db.close());

  Future<String> folder(String name, {String? under}) async =>
      (await db.folderDao.createFolder(name: name, parentId: under)).id;

  Future<String> note(
    String title,
    String folderId, {
    String text = '',
  }) async => (await db.noteDao.createNote(
    folderId: folderId,
    title: title,
    preview: text,
    content: text,
  )).id;

  /// Hands rows to the partner as the shared reader stores them: their
  /// owner first, then the key that arms the fences.
  Future<void> partners({
    List<String> folders = const [],
    List<String> notes = const [],
  }) async {
    for (final (table, ids) in [('folders', folders), ('notes', notes)]) {
      for (final id in ids) {
        await db.customStatement(
          "UPDATE $table SET owner_id = '$partner' WHERE id = ?",
          [id],
        );
      }
    }
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
  }

  NoteMetadata titled(Iterable<NoteMetadata> list, String title) =>
      list.singleWhere((note) => note.title == title);

  group('with a shared shelf and a folder of the partner\'s', () {
    late String shelf;
    late String box;
    late String plain;
    late String theirs;
    late String theirNote;

    setUp(() async {
      shelf = await folder('Shelf');
      box = await folder('Box', under: shelf);
      plain = await folder('Plain');
      theirs = await folder('Theirs');
      await note('Boxed', box, text: 'in the box');
      await note('Loose', plain, text: 'private');
      theirNote = await note('Their list', theirs, text: 'milk\neggs');
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await partners(folders: [theirs], notes: [theirNote]);
      await db.syncOutboxDao.clear();
    });

    test('a note says whose it is and which folder shares it, on every load '
        'the surfaces read', () async {
      final everything = (await notes.loadNotesPaginated()).notes;
      expect(titled(everything, 'Boxed').sharedThroughFolderId, shelf);
      expect(titled(everything, 'Boxed').inSharedFolder, isTrue);
      expect(titled(everything, 'Loose').inSharedFolder, isFalse);
      expect(titled(everything, 'Their list').fromPartner, isTrue);
      expect(titled(everything, 'Their list').inSharedFolder, isFalse);
      expect(titled(everything, 'Boxed').fromPartner, isFalse);

      expect(
        (await notes.loadAllMetadataForFolder(theirs)).single.fromPartner,
        isTrue,
      );
      expect((await notes.getNoteMetadata(theirNote))!.fromPartner, isTrue);
      final opened = (await notes.loadNoteWithContent(theirNote))!;
      expect(opened.metadata.fromPartner, isTrue);
      expect(opened.content, 'milk\neggs');
      expect(
        (await notes.resolveNoteByTitle('Boxed'))!.sharedThroughFolderId,
        shelf,
      );
      expect(
        titled(
          (await notes.loadNotePickerPage()).notes,
          'Their list',
        ).fromPartner,
        isTrue,
      );
      expect(
        titled(
          (await notes.loadNotesPaginated(folderId: box)).notes,
          'Boxed',
        ).toJson().keys,
        isNot(contains('fromPartner')),
      );
    });

    test('every door into the editor hands flagged metadata: search, and the '
        'repository\'s own mapping the restore, the session chip, a linked '
        'note and the counter page take (§6.13)', () async {
      expect(
        titled(await notes.searchNotes('milk'), 'Their list').fromPartner,
        isTrue,
      );
      expect(
        titled(await notes.searchNotes('box'), 'Boxed').inSharedFolder,
        isTrue,
      );

      final rows = await repository.getNotesByIds([theirNote]);
      final flagged = await repository.flaggedMetadata(rows.single);
      expect(flagged.fromPartner, isTrue);
      expect(flagged.inSharedFolder, isFalse);
      final boxed = (await notes.loadAllMetadataForFolder(box)).single;
      final mine = await repository.flaggedMetadata(
        (await repository.getNotesByIds([boxed.id])).single,
      );
      expect(mine.fromPartner, isFalse);
      expect(mine.sharedThroughFolderId, shelf);
      // Unflagged only when asked against nothing.
      expect(repository.noteToMetadata(rows.single).fromPartner, isFalse);
    });

    test('Recent leaves the partner\'s notes out, in its count too; All notes '
        'keeps them (D17)', () async {
      final recent = await notes.loadNotesPaginated(ownOnly: true);
      expect([
        for (final n in recent.notes) n.title,
      ], unorderedEquals(['Boxed', 'Loose']));
      expect(recent.totalCount, 2);

      final all = await notes.loadNotesPaginated();
      expect(all.notes, hasLength(3));
      expect(all.totalCount, 3);
    });

    test('a paired database pays one census read for a load, never one per '
        'row', () async {
      for (var i = 0; i < 30; i++) {
        await note('Many $i', box);
      }
      repository.shareCensus.forget();
      statements.reset();

      await notes.loadNotesPaginated(pageSize: 50);
      await notes.loadNotesPaginated(folderId: box, pageSize: 50);

      expect(statements.matching('WITH RECURSIVE s(id, root'), hasLength(1));
      expect(statements.matching('owner_id'), hasLength(1));
    });

    test('a save keeps the flags of the metadata it was given, reading no '
        'census: the typing path gains no statement', () async {
      final boxed = titled((await notes.loadNotesPaginated()).notes, 'Boxed');
      repository.shareCensus.forget();
      statements.reset();

      final saved = await notes.updateNote(
        noteId: boxed.id,
        content: 'in the box, edited',
        current: boxed,
      );

      expect(saved!.sharedThroughFolderId, shelf);
      expect(statements.matching('WITH RECURSIVE s(id, root'), isEmpty);
      expect(statements.matching('WHERE owner_id = ?'), isEmpty);
    });

    test('a save from the editor carries the metadata the page holds through '
        'the note bloc: after the census was dropped it reads none', () async {
      final boxed = titled((await notes.loadNotesPaginated()).notes, 'Boxed');
      final bloc = OptimizedNoteBloc(storageService: notes);
      addTearDown(bloc.close);
      repository.shareCensus.forget();
      statements.reset();

      final saved = Completer<void>();
      bloc.add(
        UpdateOptimizedNote(
          noteId: boxed.id,
          content: 'typed in the editor',
          current: boxed,
          completer: saved,
        ),
      );
      await saved.future;

      expect(statements.matching('WITH RECURSIVE s(id, root'), isEmpty);
      expect(statements.matching('WHERE owner_id = ?'), isEmpty);
    });

    test('a save after the census was dropped never answers "not shared" '
        'for a shared note', () async {
      final boxed = titled((await notes.loadNotesPaginated()).notes, 'Boxed');
      repository.shareCensus.forget();

      final saved = await notes.updateNote(
        noteId: boxed.id,
        content: 'in the box, edited again',
      );

      expect(saved!.sharedThroughFolderId, shelf);
      expect(
        saved.copyWith(clearSharedThroughFolderId: true).inSharedFolder,
        isFalse,
        reason: 'copyWith can clear it',
      );
    });

    group('the belt: a write of the partner\'s note', () {
      Future<void> refused(Future<Object?> Function() write) async {
        await expectLater(write(), throwsA(isA<SharedRowException>()));
        expect(await db.syncOutboxDao.count(), 0, reason: 'nothing written');
      }

      test('is refused by name, never answered as done', () async {
        await refused(() => notes.setNoteLabel(theirNote, ItemLabel.teal));
        await refused(
          () => notes.setLabelForNotes([theirNote], ItemLabel.teal),
        );
        await refused(() => notes.deleteNote(theirNote));
        await refused(() => notes.deleteNotes([theirNote]));
        await refused(() => notes.deleteNotesInFolder(theirs));
        await refused(
          () => notes.moveNotes(noteIds: [theirNote], targetFolderId: plain),
        );

        final row = (await db.noteDao.getByIdsIncludingDeleted([
          theirNote,
        ])).single;
        expect(row.isDeleted, isFalse);
        expect(row.label, ItemLabel.none.storageValue);
        expect(row.folderId, theirs);
      });

      test('and so is filing one of mine into their folder', () async {
        final loose = titled((await notes.loadNotesPaginated()).notes, 'Loose');
        await refused(
          () => notes.moveNotes(noteIds: [loose.id], targetFolderId: theirs),
        );
        await refused(
          () => notes.moveNote(noteId: loose.id, targetFolderId: theirs),
        );
        await refused(
          () => notes.createNote(folderId: theirs, title: 'Mine', content: ''),
        );
      });

      test(
        'the save and the move of theirs are refused as they were',
        () async {
          await refused(
            () => notes.updateNote(noteId: theirNote, content: 'changed'),
          );
          await refused(
            () => notes.moveNote(noteId: theirNote, targetFolderId: plain),
          );
        },
      );
    });

    test('a move\'s result says what it did to sharing (§6.11)', () async {
      final loose = titled((await notes.loadNotesPaginated()).notes, 'Loose');

      final into = await notes.moveNotes(
        noteIds: [loose.id],
        targetFolderId: box,
      );
      expect(into.shareChanges, {loose.id: MoveShareChange.nowShared});
      expect(into.shareChange, MoveShareChange.nowShared);

      final within = await notes.moveNotes(
        noteIds: [loose.id],
        targetFolderId: shelf,
      );
      expect(within.shareChange, isNull, reason: 'shared before and after');

      final out = await notes.moveNotes(
        noteIds: [loose.id],
        targetFolderId: plain,
      );
      expect(out.shareChange, MoveShareChange.noLongerShared);
    });

    group('"Copy to my notes" (§6.13)', () {
      test(
        'makes a new note of mine: the partner\'s title and whole text, a '
        'new id stamped now by this device, no label, nothing shared',
        () async {
          final before = DateTime.now().subtract(const Duration(seconds: 1));

          final copy = (await notes.copyToMine(theirNote, plain))!;

          expect(copy.id, isNot(theirNote));
          expect(copy.title, 'Their list');
          expect(copy.folderId, plain);
          expect(copy.fromPartner, isFalse);
          expect(copy.inSharedFolder, isFalse);
          expect(copy.label, ItemLabel.none);
          expect(copy.createdAt.isAfter(before), isTrue);
          expect(await notes.loadNoteContent(copy.id), 'milk\neggs');

          final row = (await db.noteDao.getByIdsIncludingDeleted([
            copy.id,
          ])).single;
          expect(row.ownerId, isNull, reason: 'the person\'s own');
          expect(row.version, 1);
          expect(row.deviceId, db.deviceId);
          expect(
            await db.syncOutboxDao.count(),
            greaterThan(0),
            reason: 'queued like any create',
          );
        },
      );

      test('into a folder I share is shared through it, as any new note '
          'there is', () async {
        final copy = (await notes.copyToMine(theirNote, box))!;

        expect(copy.sharedThroughFolderId, shelf);
      });

      test('refuses a folder of the partner\'s as its target', () async {
        await expectLater(
          notes.copyToMine(theirNote, theirs),
          throwsA(isA<SharedRowException>()),
        );
      });

      test(
        'a title the folder holds already is refused as a create is',
        () async {
          await note('Their list', plain);

          await expectLater(
            notes.copyToMine(theirNote, plain),
            throwsA(isA<DuplicateNameException>()),
          );
        },
      );

      test('copies a note of my own too, and answers null for one that is '
          'gone', () async {
        final loose = titled((await notes.loadNotesPaginated()).notes, 'Loose');

        final copy = (await notes.copyToMine(loose.id, box))!;
        expect(await notes.loadNoteContent(copy.id), 'private');

        expect(await notes.copyToMine('missing', plain), isNull);
      });

      test('refuses a target folder that is deleted or missing, writing '
          'nothing', () async {
        await db.folderDao.softDeleteFolder(plain);
        await db.syncOutboxDao.clear();

        for (final target in [plain, 'nowhere']) {
          await expectLater(
            notes.copyToMine(theirNote, target),
            throwsA(isA<FolderGoneException>()),
          );
        }
        expect(await db.syncOutboxDao.count(), 0);
      });

      test(
        'a source gone before the copy answers null and writes nothing',
        () async {
          final loose = titled(
            (await notes.loadNotesPaginated()).notes,
            'Loose',
          );
          await db.noteDao.softDeleteNote(loose.id);
          await db.syncOutboxDao.clear();

          expect(await notes.copyToMine(loose.id, box), isNull);
          expect(await db.syncOutboxDao.count(), 0);
        },
      );
    });
  });

  test('a database that holds no mark and no shared row runs no statement '
      'for sharing on any load past the census it reads once, and Recent '
      'reads what All notes reads', () async {
    final a = await folder('A');
    await note('One', a);
    await notes.loadNotesPaginated();
    statements.reset();

    await notes.loadNotesPaginated(folderId: a);
    final all = await notes.loadNotesPaginated();
    final recent = await notes.loadNotesPaginated(ownOnly: true);
    await notes.loadAllMetadataForFolder(a);
    await notes.getNoteMetadata(all.notes.single.id);
    await notes.loadNotePickerPage();

    expect(statements.matching('WITH RECURSIVE s(id, root'), isEmpty);
    expect(statements.matching('owner_id'), isEmpty);
    expect(statements.matching('sync_metadata'), isEmpty);
    expect(recent.notes, all.notes);
  });

  // `docs/cloud-shared-freshness.md` §7: a move the census says took a note
  // into or out of a shared folder owes the partner's phone a normal poke;
  // any other move writes nothing for it.
  group('the poke a move owes', () {
    Future<String?> owed() =>
        db.syncDao.getValue(SyncDao.keySharePokeOwed('pair-1'));

    test('a database that shares nothing: a move, one or many, writes '
        'nothing for it', () async {
      final a = await folder('A');
      final b = await folder('B');
      final one = await note('One', a);
      final two = await note('Two', a);
      await notes.loadNotesPaginated();
      statements.reset();

      await notes.moveNote(noteId: one, targetFolderId: b);
      await notes.moveNotes(noteIds: [one, two], targetFolderId: a);

      expect(statements.matching('share_poke_owed'), isEmpty);
    });

    test('into and out of a shared folder, one and many, owes the pair a '
        'normal poke; between two private folders, none', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      final plain = await folder('Plain');
      final other = await folder('Other');
      final one = await note('One', plain);
      final two = await note('Two', plain);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      Future<void> clear() =>
          db.syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);
      await clear();

      await notes.moveNote(noteId: one, targetFolderId: box);
      expect(await owed(), 'normal');
      await clear();
      await notes.moveNote(noteId: one, targetFolderId: plain);
      expect(await owed(), 'normal');
      await clear();

      await notes.moveNotes(noteIds: [one, two], targetFolderId: shelf);
      expect(await owed(), 'normal');
      await clear();
      await notes.moveNotes(noteIds: [one, two], targetFolderId: plain);
      expect(await owed(), 'normal');
      await clear();

      await notes.moveNote(noteId: one, targetFolderId: other);
      expect(await owed(), isNull);
    });

    test('an urgent poke already owed is not lowered', () async {
      final shelf = await folder('Shelf');
      final plain = await folder('Plain');
      final one = await note('One', plain);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await db.syncDao.oweSharePoke(pairId: 'pair-1', urgent: true);

      await notes.moveNote(noteId: one, targetFolderId: shelf);

      expect(await owed(), 'urgent');
    });
  });
}
