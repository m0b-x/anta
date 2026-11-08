import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../database/support/db_test_support.dart';
import 'support/sync_pair.dart';

/// The conflict copy in the direction D3 left open (scalability record S8,
/// D4 A): two devices edit one note offline and the older edit is pushed
/// first, so the device holding the newer one keeps it and the older text is
/// overwritten everywhere — unless that device files it as a copy, once per
/// lost version (`NoteDao._keptOver`, `note_seen`).
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  /// A note written on A and pulled by B, both devices past the initial
  /// merge, the recorders cleared.
  Future<Note> sharedNote() async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );
    await a().sync();
    await b().sync();
    a().hooks.clear();
    b().hooks.clear();
    return note;
  }

  Future<String?> seenOn(SyncDevice device, String noteId) =>
      device.db.syncDao.getValue(SyncDao.keyNoteSeen(noteId));

  Future<void> expectBody(String noteId, String body) async {
    for (final device in [a(), b()]) {
      expect(
        await device.db.contentChunkDao.loadContent(noteId),
        body,
        reason: device.id,
      );
    }
  }

  test(
    'the older edit pushed first is filed as a copy on exactly one device, '
    'the newer one, and a later re-read of the window files no second',
    () async {
      final note = await sharedNote();
      await editNote(a(), note.id, 'typed on A');
      await editNote(b(), note.id, 'typed on B');
      final older = (await a().db.noteDao.getNoteById(note.id))!.hlcTimestamp;

      await a().sync();
      // B's push fails, so the window still holds A's version when B reads
      // it again — the settled-overlap re-read that follows a copy.
      pair.gateway.refuse('notes', note.id, SyncGatewayFailure.offline);
      await b().sync();
      pair.gateway.replayOnResume = 100;
      await b().sync();
      pair.gateway.accept('notes', note.id);
      await b().sync();
      await a().sync();
      await b().sync();

      final conflict = b().hooks.conflicts.single;
      expect(conflict.incoming, isTrue);
      expect(conflict.loser.id, note.id);
      expect(conflict.loser.title, 'Log');
      expect(conflict.loserContent, 'typed on A');
      expect(a().hooks.conflicts, isEmpty);
      expect(await seenOn(b(), note.id), older);
      await expectBody(note.id, 'typed on B');
    },
  );

  test('a lost acknowledgement and then the echo of our own push file no '
      'copy', () async {
    final note = await sharedNote();
    await editNote(a(), note.id, 'typed on A');
    var lose = true;
    pair.gateway.onPushBatch = (_) async {
      if (!lose) return;
      lose = false;
      throw const SyncGatewayException(SyncGatewayFailure.offline, 'lost');
    };

    expect((await a().sync()).failure, SyncGatewayFailure.offline);
    await a().sync();
    await b().sync();

    expect(a().hooks.conflicts, isEmpty);
    expect(b().hooks.conflicts, isEmpty);
    expect(await seenOn(a(), note.id), isNull);
    await expectBody(note.id, 'typed on A');
  });

  test('an older version pushed over a newer one — a drain that never pulled '
      '— is healed by the requeue and leaves one copy of its text', () async {
    final note = await sharedNote();
    await b().engine.start();
    await b().settle();
    // Away, B hears no signal of A's push, so nothing pulls before B's drain.
    await b().engine.onAppBackgrounded();
    await editNote(b(), note.id, 'typed on B');
    await editNote(a(), note.id, 'typed on A');
    await a().sync();

    // B leaves the app again: the drain pushes its older edit over A's newer
    // one: its new chunk, then its manifest.
    expect((await b().engine.onAppBackgrounded()).pushedRows, 2);
    expect(pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.deviceId, b().id);
    b().engine.onAppResumed();
    await b().settle();

    await a().sync();
    await b().sync();
    await a().sync();

    final conflict = a().hooks.conflicts.single;
    expect(conflict.incoming, isTrue);
    expect(conflict.loserContent, 'typed on B');
    expect(b().hooks.conflicts, isEmpty);
    await expectBody(note.id, 'typed on A');
  });

  test('a local edit made on top of an accepted foreign version files no copy '
      'when that version is delivered again', () async {
    final note = await sharedNote();
    final accepted = (await b().db.noteDao.getNoteById(note.id))!.hlcTimestamp;

    await editNote(b(), note.id, 'typed on B');
    expect(await seenOn(b(), note.id), accepted);
    pair.gateway.replayOnResume = 100;
    await b().sync();

    expect(b().hooks.conflicts, isEmpty);
    await a().sync();
    expect(a().hooks.conflicts, isEmpty);
    await expectBody(note.id, 'typed on B');
  });

  test('an edit on our own row records nothing', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );
    a().statements.reset();

    await editNote(a(), note.id, 'typed on A');

    expect(
      a().statements.captured.where(
        (s) => s.args.any((v) => v is String && v.startsWith('note_seen.')),
      ),
      isEmpty,
    );
    expect(await seenOn(a(), note.id), isNull);
  });

  test('a foreign tombstone kept out by a newer local edit files no copy and '
      'is recorded as seen', () async {
    final note = await sharedNote();
    await a().db.noteDao.softDeleteNoteWithChunks(note.id);
    final deleted = (await a().db.noteDao.getNoteById(note.id))!.hlcTimestamp;
    await editNote(b(), note.id, 'typed on B');

    await a().sync();
    await b().sync();
    await a().sync();

    expect(b().hooks.conflicts, isEmpty);
    expect(a().hooks.conflicts, isEmpty);
    expect(await seenOn(b(), note.id), deleted);
  });

  bool touchesSeen(CapturedStatement s) =>
      s.args.any((v) => v is String && v.startsWith(SyncDao.noteSeenPrefix));

  test('the initial pull of 500 notes records each accepted version in one '
      'upsert, reads no chunk and files no copy', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    for (var i = 0; i < 500; i++) {
      await writeNote(a(), folderId: folder.id, title: 'Note $i', body: '$i');
    }
    await a().sync();
    b().statements.reset();

    final report = await b().sync();

    expect(report.pulledRows, 501);
    final seen = b().statements.captured.where(touchesSeen).toList();
    expect(seen, hasLength(500));
    expect(seen.where((s) => s.isSelect), isEmpty);
    // The merge's own plan reads the chunk index of a stored body; no body
    // text is read, which only the rule's comparison would do.
    expect(b().statements.captured.where(_readsBodyText), isEmpty);
    expect(b().hooks.conflicts, isEmpty);
  });

  test('a foreign version kept out again after it was seen reads no chunk and '
      'writes nothing to note_seen', () async {
    final note = await sharedNote();
    final accepted = (await a().db.noteDao.getNoteById(note.id))!;
    await editNote(b(), note.id, 'typed on B');
    b().statements.reset();

    final outcome = await b().db.noteDao.mergeNoteDocument(accepted, 'base');

    expect(outcome, const MergeOutcome(MergeResult.keptLocal));
    expect(b().statements.captured.where(_readsBodyText), isEmpty);
    expect(
      b().statements.captured.where((s) => touchesSeen(s) && !s.isSelect),
      isEmpty,
    );
  });

  test('a foreign tombstone inserted here records nothing; one that wins over '
      'a live row is recorded (S8 re-review R4)', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final gone = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Gone',
      body: 'x',
    );
    final kept = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Kept',
      body: 'y',
    );
    await a().db.noteDao.softDeleteNoteWithChunks(gone.id);
    await a().sync();
    await b().sync();

    expect((await b().db.noteDao.getNoteById(gone.id))!.isDeleted, isTrue);
    expect(await seenOn(b(), gone.id), isNull);

    await a().db.noteDao.softDeleteNoteWithChunks(kept.id);
    final deleted = (await a().db.noteDao.getNoteById(kept.id))!.hlcTimestamp;
    await a().sync();
    await b().sync();

    expect(await seenOn(b(), kept.id), deleted);
  });

  test('bodies differing only in trailing whitespace file no copy', () async {
    final note = await sharedNote();
    await editNote(a(), note.id, 'typed\n\n');
    await editNote(b(), note.id, 'typed');

    await a().sync();
    await b().sync();

    expect(b().hooks.conflicts, isEmpty);
  });

  for (final (name, write) in <(String, Future<void> Function(Note))>[
    (
      'a bulk label',
      (n) => b().db.noteDao.updateLabelForNotes(
        ids: [n.id],
        label: ItemLabel.teal,
      ),
    ),
    // A position write re-stamps the row as ours without touching its body,
    // like a drag's `applyOrder`; `seen` was recorded at acceptance, so no
    // writer has to remember it.
    (
      'a reorder',
      (n) => b().db.noteDao.updateNotePosition(id: n.id, newPosition: 7),
    ),
  ]) {
    test('$name over an accepted foreign version, then an edit, then that '
        'version delivered again: no copy (S8 review F1)', () async {
      final note = await sharedNote();
      await write(note);
      await editNote(b(), note.id, 'typed on B');
      pair.gateway.replayOnResume = 100;

      await b().sync();

      expect(b().hooks.conflicts, isEmpty);
    });
  }

  group('a newer local delete', () {
    for (final (name, delete) in <(String, Future<void> Function(Note))>[
      ('one note', (n) => b().db.noteDao.softDeleteNoteWithChunks(n.id)),
      ('a selection', (n) => b().db.noteDao.softDeleteNotesWithChunks([n.id])),
      (
        'its folder',
        (n) => b().db.folderDao.softDeleteFolderWithDescendants(n.folderId),
      ),
    ]) {
      test('of $name over an accepted foreign version files no copy when that '
          'version is delivered again', () async {
        final note = await sharedNote();
        await delete(note);
        pair.gateway.replayOnResume = 100;

        await b().sync();

        expect(b().hooks.conflicts, isEmpty);
      });

      test('of $name keeping out a foreign live edit files that text once, on '
          'the deleting device, and not again on a re-read', () async {
        final note = await sharedNote();
        await editNote(a(), note.id, 'typed on A');
        await delete(note);

        await a().sync();
        pair.gateway.refuse('notes', note.id, SyncGatewayFailure.offline);
        await b().sync();
        pair.gateway.replayOnResume = 100;
        await b().sync();
        pair.gateway.accept('notes', note.id);
        await b().sync();
        await a().sync();

        final conflict = b().hooks.conflicts.single;
        expect(conflict.incoming, isTrue);
        expect(conflict.loserContent, 'typed on A');
        expect(conflict.loser.folderId, note.folderId);
        expect(a().hooks.conflicts, isEmpty);
      });
    }
  });
}

/// A read of a note's body text (`ContentChunkDao.loadContent`), as opposed
/// to the chunk index a merge's write plan reads.
bool _readsBodyText(CapturedStatement s) =>
    s.isSelect && s.sql.contains('AS "content_chunks.content"');
