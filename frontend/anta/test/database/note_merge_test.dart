import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/body_cut.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';

import '../services/support/body_index_support.dart';
import '../support/scale_fixtures.dart';
import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `NoteDao.mergeNoteDocument`: a note and its whole body arrive as
/// one document (D14), so besides the shared contract the merge rewrites the
/// chunks, keeps the search index in step and names the loser the engine
/// files as a conflict copy (D3).
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  const remoteBody = 'Deadlift 5x5\n\nheavy pull day';

  Note remote(String id, String hlc, {bool deleted = false}) {
    return Note(
      id: id,
      folderId: 'f1',
      title: 'Pulled',
      preview: 'whatever the wire says',
      contentLength: 1,
      chunkCount: 9,
      isCompressed: true,
      position: 3,
      label: 1,
      createdAt: DateTime.utc(2026, 2, 1).toLocal(),
      updatedAt: DateTime.utc(2026, 2, 2).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 2, 3).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  Future<MergeOutcome> merge(Note row, {String? floor, String? body}) {
    return db.noteDao.mergeNoteDocument(
      row,
      row.isDeleted ? null : body ?? remoteBody,
      floor: floor,
    );
  }

  Future<Note> seed({String title = 'Squat log', String body = 'local'}) {
    return db.noteDao.createNote(folderId: 'f1', title: title, content: body);
  }

  runMergeContract(
    MergeContract<Note>(
      table: 'notes',
      freshKey: 'pulled',
      seedLocal: (db) async => (await seed()).id,
      remote: remote,
      merge: (db, row, {floor}) => merge(row, floor: floor),
      markerColumn: 'title',
      markerValue: 'Pulled',
      mergedContent: remoteBody,
      keptRemoteLoses: true,
    ),
    db: () => db,
    statements: () => statements,
  );

  group('the body', () {
    // 20 KiB of one letter finds no cut point, so it is cut once, after the
    // 8,192 target, into two chunks (before S4: 14 KiB in two 10,000
    // slices).
    test('a winning remote replaces the chunks with its text', () async {
      final local = await seed(body: 'old text');
      final long = 'x' * 20 * 1024;

      await merge(remote(local.id, newerHlc), body: long);

      expect(await db.contentChunkDao.loadContent(local.id), long);
      final chunks = await db.contentChunkDao.getChunksForNote(local.id);
      expect(chunks, hasLength(2));
      for (final chunk in chunks) {
        expect(chunk.hlcTimestamp, newerHlc);
        expect(chunk.deviceId, 'remote');
        expect(chunk.version, 7);
      }
    });

    // Before S4 every chunk was rewritten under the remote's stamps; now a
    // chunk whose text the remote body still holds is kept with its own, and
    // only the chunks the merge wrote carry the remote's.
    test('a winning remote writes only the chunks whose text changed, under '
        'its stamps', () async {
      final text = bigBody(60000);
      final local = await seed(body: text);
      final before = {
        for (final c in await db.contentChunkDao.getChunksForNote(local.id))
          c.id: c,
      };
      final edited = editNearTop(text);

      await merge(remote(local.id, newerHlc), body: edited);

      expect(await db.contentChunkDao.loadContent(local.id), edited);
      final chunks = await db.contentChunkDao.getChunksForNote(local.id);
      final written = chunks.where((c) => !before.containsKey(c.id)).toList();
      expect(written, isNotEmpty);
      expect(written.length, lessThan(chunks.length));
      for (final chunk in written) {
        expect(chunk.hlcTimestamp, newerHlc);
        expect(chunk.deviceId, 'remote');
        expect(chunk.version, 7);
      }
      for (final chunk in chunks.where((c) => before.containsKey(c.id))) {
        expect(chunk.hlcTimestamp, before[chunk.id]!.hlcTimestamp);
      }
      final row = (await db.noteDao.getNoteById(local.id))!;
      expect(row.chunkCount, chunks.length);
    });

    // A pull hands every note it reads to the merge, the echo of this
    // device's own push among them: cutting the body is a SHA-256 over all of
    // it, paid only by a merge that stores it.
    test('a remote kept local or unchanged is never cut', () async {
      final local = await seed(body: 'kept');
      final cuts = BodyCut.cutCount;

      await merge(remote(local.id, olderHlc), body: bigBody(100000));
      await merge(remote(local.id, local.hlcTimestamp), body: 'kept');

      expect(BodyCut.cutCount, cuts);
      expect(await db.contentChunkDao.loadContent(local.id), 'kept');
    });

    test('an inserted note gets its chunks, queued as chunks, and the note '
        'itself is not queued', () async {
      await merge(remote('pulled', newerHlc));

      expect(await db.contentChunkDao.loadContent('pulled'), remoteBody);
      expect(
        {
          for (final entry in await db.syncOutboxDao.pending())
            entry.syncedTable,
        },
        {'content_chunks'},
      );
    });

    test('the columns describing the body come from the body', () async {
      final long = 'y' * 20 * 1024;

      await merge(remote('pulled', newerHlc), body: long);

      final row = (await db.noteDao.getNoteById('pulled'))!;
      expect(row.contentLength, long.length);
      expect(row.chunkCount, 2);
      expect(row.isCompressed, isTrue);
      expect(row.preview, isNot('whatever the wire says'));
      expect(row.position, 3);
    });

    test('an empty body leaves no chunks', () async {
      final local = await seed(body: 'old text');

      await merge(remote(local.id, newerHlc), body: '');

      expect(await db.contentChunkDao.getChunksForNote(local.id), isEmpty);
      expect(await db.contentChunkDao.loadContent(local.id), '');
    });

    test('a tombstone deletes the chunks and keeps the note\'s tombstone '
        '(D13)', () async {
      final local = await seed(body: 'gone text');
      final queued = await db.syncOutboxDao.count();

      await merge(remote(local.id, newerHlc, deleted: true));

      final chunks = await (db.select(
        db.contentChunks,
      )..where((c) => c.noteId.equals(local.id))).get();
      expect(chunks, isEmpty);
      expect(await db.contentChunkDao.loadContent(local.id), '');
      final row = (await db.noteDao.getNoteById(local.id))!;
      expect(row.isDeleted, isTrue);
      expect(row.title, 'Squat log', reason: 'a tombstone carries no data');
      expect(
        await db.syncOutboxDao.count(),
        queued - 1,
        reason: 'the note entry retired, no chunk queued, nothing minted',
      );
    });

    test('a kept local row keeps its chunks', () async {
      final local = await seed(body: 'mine');

      await merge(remote(local.id, olderHlc));

      expect(await db.contentChunkDao.loadContent(local.id), 'mine');
    });
  });

  group('the search index', () {
    test('finds the new title and not the old', () async {
      final local = await seed(title: 'Squat log');

      await merge(remote(local.id, newerHlc));

      expect(await indexedHits(db, 'Pulled'), [local.id]);
      expect(await indexedHits(db, 'Squat'), isEmpty);
    });

    test('a tombstone leaves it, a resurrection returns to it', () async {
      final local = await seed(title: 'Squat log');

      await merge(remote(local.id, 'ffffffffffff:0000:remote', deleted: true));
      expect(await indexedHits(db, 'Squat'), isEmpty);

      await merge(remote(local.id, newerHlc));
      expect(await indexedHits(db, 'Pulled'), [local.id]);
    });

    test('a note inserted as a tombstone is not indexed', () async {
      await merge(remote('pulled', newerHlc, deleted: true));

      expect(await indexedHits(db, 'Pulled'), isEmpty);
    });
  });

  group('the loser', () {
    test('is named when the local change was pending and differs', () async {
      final local = await seed(body: 'my unpushed set');

      final outcome = await merge(remote(local.id, newerHlc));

      expect(outcome.result, MergeResult.applied);
      expect(outcome.localHadPendingPush, isTrue);
      expect(outcome.loser!.id, local.id);
      expect(outcome.loser!.title, 'Squat log');
      expect(outcome.loserContent, 'my unpushed set');
    });

    test('is never named on the floor branch', () async {
      // A rebind's requeueAll queued every row: the pending entry here is no
      // unpushed change, and the space wins under the floor.
      final local = await seed(body: 'restored text');

      final outcome = await merge(
        remote(local.id, olderHlc),
        floor: local.hlcTimestamp,
      );

      expect(outcome.result, MergeResult.applied);
      expect(outcome.localHadPendingPush, isTrue);
      expect(outcome.loser, isNull);
      expect(outcome.loserContent, isNull);
      expect(await db.contentChunkDao.loadContent(local.id), remoteBody);
    });

    test('is not named for a strictly newer remote over a local row at the '
        'floor', () async {
      // A restore-then-rebind: the space has this note newer, and the pending
      // entry is requeueAll's, not an unpushed edit.
      final local = await seed(body: 'restored text');

      final outcome = await merge(
        remote(local.id, newerHlc),
        floor: local.hlcTimestamp,
      );

      expect(outcome.result, MergeResult.applied);
      expect(outcome.localHadPendingPush, isTrue);
      expect(outcome.loser, isNull);
      expect(outcome.loserContent, isNull);
      expect(await db.contentChunkDao.loadContent(local.id), remoteBody);
    });

    test('is named above the floor', () async {
      final local = await seed(body: 'edited after the unbind');

      final outcome = await merge(remote(local.id, newerHlc), floor: olderHlc);

      expect(outcome.loserContent, 'edited after the unbind');
    });

    test('is not named when the texts are the same', () async {
      final local = await seed(body: remoteBody);

      final outcome = await merge(remote(local.id, newerHlc));

      expect(outcome.localHadPendingPush, isTrue);
      expect(outcome.loser, isNull);
      expect(outcome.loserContent, isNull);
    });

    test('is not named when the local change was pushed', () async {
      final local = await seed(body: 'pushed text');
      await db.syncOutboxDao.clear();

      final outcome = await merge(remote(local.id, newerHlc));

      expect(
        outcome,
        const MergeOutcome(MergeResult.applied, mergedContent: remoteBody),
      );
    });

    test('is named when a delete overwrites an unpushed edit', () async {
      final local = await seed(body: 'edited offline');

      final outcome = await merge(remote(local.id, newerHlc, deleted: true));

      expect(outcome.loserContent, 'edited offline');
    });

    test('is not named over a local tombstone', () async {
      final local = await seed(body: 'gone');
      await db.noteDao.softDeleteNote(local.id);

      final outcome = await merge(remote(local.id, newerHlc));

      expect(outcome.localHadPendingPush, isTrue);
      expect(outcome.loser, isNull);
    });
  });

  // The note twin of the folder repair in `folder_merge_test.dart`: one
  // device deleted the folder (its notes tombstoned with it), the other edited
  // a note in it later, the edit wins by last-writer-wins and the merge never
  // cascades — so without the repair the live note sits in a tombstone and is
  // findable only by search.
  group('the folder a merge leaves behind', () {
    Note under(String id, String folderId, String hlc) =>
        remote(id, hlc).copyWith(folderId: folderId);

    /// The queued stamp per note row key.
    Future<Map<String, String>> queuedNotes() async => {
      for (final entry in await db.syncOutboxDao.pendingForTable('notes'))
        entry.rowKey: entry.hlc,
    };

    /// Ten minutes ahead of the test clock, as the folder repair's tests
    /// take it: a repair that raised the clock to the edit it repairs is told
    /// apart from one minted below it (R131).
    final editedHlc = HlcTimestamp(
      wallTime: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      logicalCounter: 3,
      nodeId: 'remote',
    ).toString();

    /// A stamp of device `C`, [ahead] of the test clock.
    String stampOfC(Duration ahead) => HlcTimestamp(
      wallTime: DateTime.now().add(ahead).millisecondsSinceEpoch,
      logicalCounter: 0,
      nodeId: 'C',
    ).toString();

    /// The tombstone of a folder device `C` deleted at [hlc], merged here
    /// as the data-less envelope it arrives as.
    Future<void> deletedOnC(String id, String hlc, {String? parentId}) async {
      await db.folderDao.mergeFolder(
        Folder(
          id: id,
          name: id,
          parentId: parentId,
          position: 0,
          label: 0,
          createdAt: DateTime.utc(2026, 2, 1).toLocal(),
          updatedAt: DateTime.utc(2026, 2, 1).toLocal(),
          hlcTimestamp: hlc,
          deviceId: 'C',
          version: 2,
          isDeleted: true,
          deletedAt: DateTime.utc(2026, 2, 3).toLocal(),
          ownerId: 'uid-1',
        ),
      );
    }

    test('a note under another device\'s folder tombstone stamped below it '
        'stands: its own tombstone is still to come (P review PR1)', () async {
      await deletedOnC('gone', stampOfC(const Duration(minutes: 20)));

      final outcome = await merge(under('pulled', 'gone', editedHlc));

      final row = (await db.noteDao.getNoteById('pulled'))!;
      expect(row.folderId, 'gone');
      expect(row.hlcTimestamp, editedHlc);
      expect(outcome.moved, isFalse);
      expect(await queuedNotes(), isNot(contains('pulled')));
    });

    test(
      'a note under this device\'s own folder tombstone stamped below it '
      'stands too: the device id proves nothing (P fix pass PF-H1)',
      () async {
        final folder = await db.folderDao.createFolder(name: 'Legs');
        await db.folderDao.softDeleteFolderWithDescendants(folder.id);

        final outcome = await merge(under('pulled', folder.id, olderHlc));

        expect((await db.noteDao.getNoteById('pulled'))!.folderId, folder.id);
        expect(outcome.moved, isFalse);
        expect(await queuedNotes(), isNot(contains('pulled')));
      },
    );

    test('a tombstoned folder whose parent this device has not received '
        'keeps the note', () async {
      await deletedOnC(
        'gone',
        stampOfC(const Duration(minutes: 1)),
        parentId: 'not-here',
      );

      final outcome = await merge(under('pulled', 'gone', editedHlc));

      expect((await db.noteDao.getNoteById('pulled'))!.folderId, 'gone');
      expect(outcome.moved, isFalse);
      expect(await queuedNotes(), isNot(contains('pulled')));
    });

    test('of two live ancestors the nearest takes the note', () async {
      final top = await db.folderDao.createFolder(name: 'Training');
      final middle = await db.folderDao.createFolder(
        name: 'Strength',
        parentId: top.id,
      );
      final folder = await db.folderDao.createFolder(
        name: 'Legs',
        parentId: middle.id,
      );
      await db.folderDao.softDeleteFolderWithDescendants(folder.id);

      await merge(under('pulled', folder.id, editedHlc));

      expect((await db.noteDao.getNoteById('pulled'))!.folderId, middle.id);
    });

    test('a note the merge moved here from another folder keeps that one as '
        'the folder it left', () async {
      final inbox = await db.folderDao.createFolder(name: 'Inbox');
      final folder = await db.folderDao.createFolder(name: 'Legs');
      final local = await db.noteDao.createNote(
        folderId: inbox.id,
        title: 'Squat log',
        content: 'local',
      );
      await db.folderDao.softDeleteFolderWithDescendants(folder.id);

      final outcome = await merge(under(local.id, folder.id, editedHlc));

      expect((await db.noteDao.getNoteById(local.id))!.folderId, '');
      expect(outcome.moved, isTrue);
      expect(outcome.previousParent, inbox.id);
    });

    test('a live note under a tombstoned folder takes the nearest live '
        'ancestor, stamped above the remote and queued', () async {
      final root = await db.folderDao.createFolder(name: 'Root');
      final folder = await db.folderDao.createFolder(
        name: 'Legs',
        parentId: root.id,
      );
      final local = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Squat log',
        content: 'local',
      );
      await db.folderDao.softDeleteFolderWithDescendants(folder.id);
      await db.syncOutboxDao.clear();

      final outcome = await merge(under(local.id, folder.id, editedHlc));

      final row = (await db.noteDao.getNoteById(local.id))!;
      expect(row.isDeleted, isFalse);
      expect(row.folderId, root.id);
      expect(row.version, 8);
      expect(row.hlcTimestamp.compareTo(editedHlc), greaterThan(0));
      expect((await queuedNotes())[local.id], row.hlcTimestamp);
      expect(outcome.result, MergeResult.applied);
      expect(outcome.moved, isTrue);
      expect(outcome.previousParent, folder.id);
      expect(outcome.mergedContent, remoteBody);
      expect(
        [for (final n in await db.noteDao.getNotesByFolder(root.id)) n.id],
        [local.id],
      );
    });

    test('a note whose folders are all tombstoned goes to the root', () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');
      final folder = await db.folderDao.createFolder(
        name: 'Legs',
        parentId: parent.id,
      );
      await db.folderDao.softDeleteFolderWithDescendants(parent.id);

      final outcome = await merge(under('pulled', folder.id, editedHlc));

      expect((await db.noteDao.getNoteById('pulled'))!.folderId, '');
      expect(outcome.result, MergeResult.inserted);
      expect(outcome.moved, isTrue);
      expect(outcome.previousParent, folder.id);
      expect(await queuedNotes(), contains('pulled'));
    });

    test('a folder this device has not received is kept', () async {
      await merge(under('pulled', 'not-here', editedHlc));

      expect((await db.noteDao.getNoteById('pulled'))!.folderId, 'not-here');
      expect(await queuedNotes(), isNot(contains('pulled')));
    });

    test('the repair stands back while the bind\'s initial merge is pending '
        '(A7 review R130)', () async {
      final folder = await db.folderDao.createFolder(name: 'Legs');
      await db.folderDao.softDeleteFolder(folder.id);
      await db.syncDao.setValue(SyncDao.keyBindMergePending, '1');

      final outcome = await merge(under('pulled', folder.id, editedHlc));

      expect((await db.noteDao.getNoteById('pulled'))!.folderId, folder.id);
      expect(outcome.moved, isFalse);
      expect(await queuedNotes(), isNot(contains('pulled')));
    });

    test('a remote tombstone is never repaired', () async {
      final folder = await db.folderDao.createFolder(name: 'Legs');
      final local = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Squat log',
        content: 'local',
      );
      await db.folderDao.softDeleteFolder(folder.id);
      await db.syncOutboxDao.clear();

      final outcome = await merge(
        remote(
          local.id,
          editedHlc,
          deleted: true,
        ).copyWith(folderId: folder.id),
      );

      final row = (await db.noteDao.getNoteById(local.id))!;
      expect(row.isDeleted, isTrue);
      expect(row.folderId, folder.id);
      expect(row.hlcTimestamp, editedHlc);
      expect(outcome.moved, isFalse);
      expect(await queuedNotes(), isEmpty);
    });

    test('a live folder is left alone', () async {
      final folder = await db.folderDao.createFolder(name: 'Legs');

      final outcome = await merge(under('pulled', folder.id, editedHlc));

      expect((await db.noteDao.getNoteById('pulled'))!.folderId, folder.id);
      expect(outcome.moved, isFalse);
      expect(await queuedNotes(), isNot(contains('pulled')));
    });

    group('the sweep after a complete pull (P review PR5)', () {
      /// A note edited here after `C` deleted its folder, which no merge
      /// ever re-files, and one merged stamped below the delete, which must
      /// stand.
      Future<(Note, Note)> strandedPair() async {
        await deletedOnC('gone', stampOfC(const Duration(hours: -1)));
        final edited = await db.noteDao.createNote(
          folderId: 'gone',
          title: 'Squat log',
          content: 'typed here',
        );
        await merge(
          under('older', 'gone', stampOfC(const Duration(hours: -2))),
        );
        await db.syncOutboxDao.clear();
        return (edited, (await db.noteDao.getNoteById('older'))!);
      }

      test('re-files the note the merge never reached, stamped above it and '
          'queued, and leaves the one stamped below the delete', () async {
        final (edited, older) = await strandedPair();

        final moved = await db.noteDao.refileNotesUnderDeletedFolders();

        expect(moved, [(id: edited.id, folderId: 'gone')]);
        final row = (await db.noteDao.getNoteById(edited.id))!;
        expect(row.folderId, '');
        expect(row.version, edited.version + 1);
        expect(row.hlcTimestamp.compareTo(edited.hlcTimestamp), greaterThan(0));
        expect(await queuedNotes(), {edited.id: row.hlcTimestamp});
        expect(await db.noteDao.getNoteById(older.id), older);
      });

      test('leaves a live note under this device\'s own tombstone stamped '
          'below it, as an old cascade left them (P fix pass PF-H1)', () async {
        final folder = await db.folderDao.createFolder(name: 'Legs');
        final note = await db.noteDao.createNote(
          folderId: folder.id,
          title: 'Squat log',
          content: 'typed before the delete',
        );
        await db.folderDao.softDeleteFolder(folder.id);
        await db.syncOutboxDao.clear();
        final before = await db.noteDao.getNoteById(note.id);

        expect(await db.noteDao.refileNotesUnderDeletedFolders(), isEmpty);
        expect(await db.noteDao.getNoteById(note.id), before);
        expect(await queuedNotes(), isEmpty);
      });

      test('with nothing to re-file it runs one query, through the folder '
          'index, and writes nothing', () async {
        await strandedPair();
        await db.noteDao.refileNotesUnderDeletedFolders();
        await db.syncOutboxDao.clear();
        statements.reset();

        final moved = await db.noteDao.refileNotesUnderDeletedFolders();

        expect(moved, isEmpty);
        expect(statements.count, 1);
        final plan = await explainCaptured(db, statements.captured.single);
        expect(plan, contains(startsWith('SEARCH n USING INDEX')));
        expect(plan, isNot(contains(startsWith('SCAN n'))));
        expect(await queuedNotes(), isEmpty);
      });

      test('stands back while the bind\'s initial merge is pending, and '
          're-files once it is cleared', () async {
        final (edited, _) = await strandedPair();
        await db.syncDao.setValue(SyncDao.keyBindMergePending, '1');

        expect(await db.noteDao.refileNotesUnderDeletedFolders(), isEmpty);
        expect((await db.noteDao.getNoteById(edited.id))!.folderId, 'gone');
        expect(await queuedNotes(), isEmpty);

        await db.syncDao.deleteValue(SyncDao.keyBindMergePending);
        expect(await db.noteDao.refileNotesUnderDeletedFolders(), [
          (id: edited.id, folderId: 'gone'),
        ]);
      });
    });
  });

  // Each chunk is its own document since S6: a merged body's new chunk texts
  // are queued under the merged stamp, so a later manifest of this device
  // never names a chunk the space lacks.
  test(
    'a merge queues the chunks its body brought, and never the note',
    () async {
      final local = await seed();

      await merge(remote(local.id, newerHlc), body: 'z' * 25000);

      final queued = await db.syncOutboxDao.pending();
      expect(queued.where((e) => e.syncedTable == 'notes'), isEmpty);
      expect({
        for (final entry in queued)
          if (entry.hlc == newerHlc) entry.rowKey,
      }, (await db.contentChunkDao.hashesOf(local.id)).toSet());
    },
  );
}
