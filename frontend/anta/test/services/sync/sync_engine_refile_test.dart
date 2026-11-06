import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import 'support/sync_pair.dart';

/// A live note under a folder that is a tombstone here, through the real
/// puller: the merge-time repair re-files it only when no tombstone of the
/// note is coming (P review PR1), and the sweep after a complete pull
/// re-files what the merge never reached (PR5).
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  tearDown(() async => pair.close());

  Future<void> expectConverged() async {
    expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));
  }

  Future<Note> noteOn(SyncDevice device, String id) async =>
      (await device.db.noteDao.getNoteById(id))!;

  /// The notes the run handed to `afterPage` as moved, with the folder each
  /// left.
  Map<String, String?> movedNotes(SyncDevice device) => {
    for (final (table, rows) in device.hooks.pages)
      if (table == 'notes')
        for (final row in rows)
          if (row.moved) row.rowKey: row.previousParent,
  };

  test('a note whose folder\'s tombstone lands a batch before its own stands '
      'on the device pulling between them, and its tombstone then applies '
      '(P review PR1)', () async {
    pair = await SyncPair.open();
    final folder = await a().db.folderDao.createFolder(name: 'Legs');
    await a().sync();
    await b().sync();
    // Pushed while B is away: B holds the folder live and has not pulled
    // the note when the delete reaches it.
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'squats',
    );
    await a().sync();
    await a().db.folderDao.softDeleteFolderWithDescendants(folder.id);
    // One row per batch: the cascade's stamp goes out `folders` first, and
    // B's listener pulls between the folder's tombstone and the note's.
    pair.gateway.maxBatch = 1;
    var pulledBetween = false;
    pair.gateway.onPushBatch = (batch) async {
      if (pulledBetween || batch.single.table != 'folders') return;
      pulledBetween = true;
      b().statements.reset();
      await b().sync();
    };

    await a().sync();

    expect(pulledBetween, isTrue);
    expect((await noteOn(b(), note.id)).folderId, folder.id);
    expect(movedNotes(b()), isEmpty);
    // Nothing stranded that may be re-filed: the sweep's one query.
    expect(b().statements.matching('CROSS JOIN notes'), hasLength(1));
    pair.gateway.onPushBatch = null;
    await b().sync();
    await a().sync();

    expect((await noteOn(b(), note.id)).isDeleted, isTrue);
    expect((await noteOn(a(), note.id)).isDeleted, isTrue);
    expect(
      pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.op,
      OutboxOp.tombstone,
    );
    await expectConverged();
  });

  test('a note moved into a folder another device deleted unseen is '
      're-filed by the deleting device, and both converge', () async {
    pair = await SyncPair.open();
    final inbox = await a().db.folderDao.createFolder(name: 'Inbox');
    final folder = await a().db.folderDao.createFolder(name: 'Legs');
    final note = await writeNote(
      a(),
      folderId: inbox.id,
      title: 'Log',
      body: 'squats',
    );
    await a().sync();
    await b().sync();
    await b().db.noteDao.moveNote(id: note.id, targetFolderId: folder.id);
    await b().sync();
    // A deletes the folder without having pulled the move: its cascade
    // tombstones nothing of the note, and no tombstone of it is coming.
    await a().db.folderDao.softDeleteFolderWithDescendants(folder.id);

    await a().sync();
    await b().sync();

    final onA = await noteOn(a(), note.id);
    expect(onA.isDeleted, isFalse);
    expect(onA.folderId, '');
    // The merge moved the note out of the inbox, so that is the list it
    // left, the repair notwithstanding.
    expect(movedNotes(a()), {note.id: inbox.id});
    expect((await noteOn(b(), note.id)).folderId, '');
    await expectConverged();
  });

  group('the sweep after a complete pull (P review PR5)', () {
    /// B edits the note after A deleted its folder and pushed the delete,
    /// before B pulled it: B merges the folder's tombstone, the note's own
    /// loses to the edit, and no live note ever arrives on B.
    Future<(Folder, Note)> editedAfterTheDelete() async {
      pair = await SyncPair.open();
      final folder = await a().db.folderDao.createFolder(name: 'Legs');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Log',
        body: 'squats',
      );
      await a().sync();
      await b().sync();
      await a().db.folderDao.softDeleteFolderWithDescendants(folder.id);
      await a().sync();
      await editNote(b(), note.id, 'typed on B');
      b().hooks.clear();
      return (folder, note);
    }

    test('the device that edited the note re-files it once it pulled the '
        'tombstone, announces the move and pushes it', () async {
      final (folder, note) = await editedAfterTheDelete();
      final notes = NoteRepository(database: b().db);
      addTearDown(notes.dispose);
      final production = AppSyncApplyHooks(
        notes: () => notes,
        folders: () => FolderRepository(database: b().db),
      );
      b().hooks.onAfterPage = production.afterPage;
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      final report = await b().sync();

      expect(report.failure, isNull);
      final onB = await noteOn(b(), note.id);
      expect(onB.isDeleted, isFalse);
      expect(onB.folderId, '');
      expect(await b().db.contentChunkDao.loadContent(note.id), 'typed on B');
      expect(movedNotes(b()), {note.id: folder.id});
      expect(
        changes
            .where((c) => c.type == NoteChangeType.moved)
            .map((c) => (c.noteId, c.sourceFolderId, c.folderId, c.remote)),
        [(note.id, folder.id, '', true)],
      );
      expect(
        pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.hlc,
        onB.hlcTimestamp,
      );

      await a().sync();

      final onA = await noteOn(a(), note.id);
      expect(onA.isDeleted, isFalse);
      expect(onA.folderId, '');
      await expectConverged();
    });

    test('a pull that fails part-way re-files nothing; the next complete '
        'one does', () async {
      final (folder, note) = await editedAfterTheDelete();
      var failed = false;
      b().hooks.onBeforePage = (table) async {
        if (table != 'notes' || failed) return;
        failed = true;
        throw StateError('the notes page cannot be applied');
      };

      final report = await b().sync();

      expect(report.failure, isNotNull);
      expect((await noteOn(b(), note.id)).folderId, folder.id);
      expect(movedNotes(b()), isEmpty);

      await b().sync();

      expect((await noteOn(b(), note.id)).folderId, '');
      expect(movedNotes(b()), {note.id: folder.id});
    });
  });

  test('nothing is re-filed while the bind\'s initial merge is pending; the '
      'note it skipped is re-filed after the pull that clears it', () async {
    pair = await SyncPair.open(bind: false);
    await pair.bind(a());
    final folder = await a().db.folderDao.createFolder(name: 'Legs');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'squats',
    );
    await a().db.counterDao.insertCounterWithValue(
      CountersCompanion(
        id: const Value('c1'),
        name: const Value('Sets'),
        createdAt: Value(DateTime.utc(2026, 10, 1)),
      ),
      5,
    );
    await a().sync();
    final live = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
    await a().db.folderDao.softDeleteFolderWithDescendants(folder.id);
    await a().sync();
    // A third device edited the note after the delete, and B binds into a
    // space holding the folder's tombstone and that edit.
    final deleted = HlcTimestamp.parse(
      pair.gateway.rowsOf(pair.space, 'folders')[folder.id]!.hlc,
    );
    pair.gateway.plant(
      pair.space,
      SyncEnvelope(
        table: 'notes',
        rowKey: note.id,
        hlc: HlcTimestamp(
          wallTime: deleted.wallTime + 1000,
          logicalCounter: 0,
          nodeId: 'C',
        ).toString(),
        deviceId: 'C',
        version: live.version + 1,
        op: OutboxOp.upsert,
        ownerId: syncUid,
        data: live.data,
      ),
    );
    await pair.bind(b());
    var failed = false;
    b().hooks.onBeforePage = (table) async {
      if (table != 'counters' || failed) return;
      failed = true;
      throw StateError('the counters page cannot be applied');
    };

    await b().sync();

    expect(
      await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
      isNotNull,
    );
    expect((await noteOn(b(), note.id)).folderId, folder.id);
    expect(movedNotes(b()), isEmpty);

    await b().sync();

    expect(await b().db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
    expect((await noteOn(b(), note.id)).folderId, '');
    expect(movedNotes(b()), {note.id: folder.id});
    expect(pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.deviceId, 'B');
  });
}
