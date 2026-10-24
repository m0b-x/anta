import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';

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
    ),
    db: () => db,
    statements: () => statements,
  );

  group('the body', () {
    test('a winning remote replaces the chunks with its text', () async {
      final local = await seed(body: 'old text');
      final long = 'x' * 14 * 1024;

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

    test('an inserted note gets its chunks, and none are queued', () async {
      await merge(remote('pulled', newerHlc));

      expect(await db.contentChunkDao.loadContent('pulled'), remoteBody);
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('the columns describing the body come from the body', () async {
      final long = 'y' * 14 * 1024;

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

    test('a tombstone tombstones the chunks under the remote stamp', () async {
      final local = await seed(body: 'gone text');
      final queued = await db.syncOutboxDao.count();

      await merge(remote(local.id, newerHlc, deleted: true));

      final chunks = await (db.select(
        db.contentChunks,
      )..where((c) => c.noteId.equals(local.id))).get();
      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(chunk.isDeleted, isTrue);
        expect(chunk.hlcTimestamp, newerHlc);
        expect(chunk.deviceId, 'remote');
      }
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

      final found = await db.noteDao.fullTextSearch('Pulled');
      expect(found.map((n) => n.id), [local.id]);
      expect(await db.noteDao.fullTextSearch('Squat'), isEmpty);
    });

    test('a tombstone leaves it, a resurrection returns to it', () async {
      final local = await seed(title: 'Squat log');

      await merge(remote(local.id, 'ffffffffffff:0000:remote', deleted: true));
      expect(await db.noteDao.fullTextSearch('Squat'), isEmpty);

      await merge(remote(local.id, newerHlc));
      final found = await db.noteDao.fullTextSearch('Pulled');
      expect(found.map((n) => n.id), [local.id]);
    });

    test('a note inserted as a tombstone is not indexed', () async {
      await merge(remote('pulled', newerHlc, deleted: true));

      expect(await db.noteDao.fullTextSearch('Pulled'), isEmpty);
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

      expect(outcome, const MergeOutcome(MergeResult.applied));
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

  test('no chunk ever reaches the outbox', () async {
    final local = await seed();

    await merge(remote(local.id, newerHlc), body: 'z' * 25000);

    final queued = await (db.select(
      db.syncOutbox,
    )..where((o) => o.syncedTable.equals('content_chunks'))).get();
    expect(queued, isEmpty);
  });
}
