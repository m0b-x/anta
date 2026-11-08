import 'package:drift/drift.dart' show QueryExecutor, Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import '../support/scale_fixtures.dart';
import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards D13 (`docs/scalability-roadmap.md` §5.7 S16): a tombstoned note
/// keeps no body. On each of the four paths that tombstone a note the chunk
/// rows are deleted outright, while the note row keeps its tombstone and the
/// stamp that made it. Also the v47 step that purges the bodies earlier
/// builds kept.
void main() {
  late AppDatabase db;
  late Folder folder;

  setUp(() async {
    db = await openTestDatabase();
    folder = await db.folderDao.createFolder(name: 'Log');
  });
  tearDown(() async => db.close());

  /// Every chunk row of [noteId], tombstoned ones included.
  Future<int> chunkRows(String noteId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM content_chunks WHERE note_id = ?',
          variables: [Variable<String>(noteId)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// A note whose body is stored as several chunks.
  Future<Note> seed({String? folderId, String title = 'Squat log'}) async {
    final note = await db.noteDao.createNote(
      folderId: folderId ?? folder.id,
      title: title,
      content: bigBody(30000),
    );
    expect(await chunkRows(note.id), greaterThan(1));
    return note;
  }

  /// The note is a tombstone stamped after [before], its stamp queued.
  Future<void> expectTombstone(Note before) async {
    final row = (await db.noteDao.getNoteById(before.id))!;
    expect(row.isDeleted, isTrue);
    expect(row.deletedAt, isNotNull);
    expect(row.version, before.version + 1);
    expect(row.hlcTimestamp.compareTo(before.hlcTimestamp), greaterThan(0));
    final queued = await db.syncOutboxDao.pendingForTable('notes');
    final entry = queued.singleWhere((e) => e.rowKey == before.id);
    expect(entry.hlc, row.hlcTimestamp);
    expect(entry.op, 'tombstone');
  }

  test('softDeleteNote deletes the body and keeps the tombstone', () async {
    final note = await seed();

    await db.noteDao.softDeleteNote(note.id);

    expect(await chunkRows(note.id), 0);
    await expectTombstone(note);
  });

  test('softDeleteNoteWithChunks deletes the body and keeps the '
      'tombstone', () async {
    final note = await seed();

    await db.noteDao.softDeleteNoteWithChunks(note.id);

    expect(await chunkRows(note.id), 0);
    await expectTombstone(note);
  });

  test(
    'softDeleteNotesWithChunks deletes the selection\'s bodies only',
    () async {
      final picked = [await seed(title: 'A'), await seed(title: 'B')];
      final kept = await seed(title: 'C');
      final keptRows = await chunkRows(kept.id);

      await db.noteDao.softDeleteNotesWithChunks([
        for (final n in picked) n.id,
      ]);

      for (final note in picked) {
        expect(await chunkRows(note.id), 0);
        await expectTombstone(note);
      }
      expect(await chunkRows(kept.id), keptRows);
      expect(await db.contentChunkDao.loadContent(kept.id), bigBody(30000));
    },
  );

  test('the folder cascade deletes the bodies of the notes it '
      'tombstones', () async {
    final child = await db.folderDao.createFolder(
      name: 'Week 1',
      parentId: folder.id,
    );
    final inParent = await seed(title: 'A');
    final inChild = await seed(folderId: child.id, title: 'B');
    final other = await db.folderDao.createFolder(name: 'Other');
    final elsewhere = await seed(folderId: other.id, title: 'C');
    final elsewhereRows = await chunkRows(elsewhere.id);

    await db.folderDao.softDeleteFolderWithDescendants(folder.id);

    for (final note in [inParent, inChild]) {
      expect(await chunkRows(note.id), 0);
      await expectTombstone(note);
    }
    expect(await chunkRows(elsewhere.id), elsewhereRows);
  });

  test('a remote tombstone deletes the body after naming the loser with '
      'its text', () async {
    final local = await seed();
    final body = await db.contentChunkDao.loadContent(local.id);

    final outcome = await db.noteDao.mergeNoteDocument(
      local.copyWith(
        hlcTimestamp: newerHlc,
        deviceId: 'remote',
        version: 7,
        isDeleted: true,
        deletedAt: Value(DateTime.utc(2026, 2, 3).toLocal()),
      ),
      null,
    );

    expect(outcome.result, MergeResult.applied);
    expect(outcome.loserContent, body, reason: 'read before the delete');
    expect(await chunkRows(local.id), 0);
    final row = (await db.noteDao.getNoteById(local.id))!;
    expect(row.isDeleted, isTrue);
    expect(row.hlcTimestamp, newerHlc);
    expect(row.deviceId, 'remote');
  });

  // SQLite refuses a statement binding more than 32,766 variables, and the
  // refusal rolls the whole cascade back.
  group('a cascade past SQLite\'s variable limit', () {
    test('a folder of 33,000 notes is deleted with every body', () async {
      const count = 33000;
      await db.customStatement(
        'WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq '
        'WHERE i < $count) '
        'INSERT INTO notes (id, folder_id, title, content_length, '
        'chunk_count, created_at, updated_at, hlc_timestamp, device_id) '
        "SELECT 'n' || i, ?, 'Set ' || i, 1, 1, 0, 0, 'h', 'd' FROM seq",
        [folder.id],
      );
      await db.customStatement(
        'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
        "hlc_timestamp, device_id) SELECT 'c' || id, id, 0, 'x', 'h', 'd' "
        'FROM notes',
      );
      Future<int> countOf(String sql) async =>
          (await db.customSelect(sql).getSingle()).read<int>('n');
      expect(await countOf('SELECT COUNT(*) AS n FROM content_chunks'), count);

      await db.folderDao.softDeleteFolderWithDescendants(folder.id);

      expect(
        await countOf('SELECT COUNT(*) AS n FROM notes WHERE is_deleted = 0'),
        0,
      );
      expect(await countOf('SELECT COUNT(*) AS n FROM content_chunks'), 0);
    });

    // "Select all" in a folder of this size hands the bulk delete every id;
    // its note update binds them in batches, so the selection goes whole.
    test('a selection of 33,000 notes is tombstoned with every body', () async {
      const count = 33000;
      await db.customStatement(
        'WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq '
        'WHERE i < $count) '
        'INSERT INTO notes (id, folder_id, title, content_length, '
        'chunk_count, created_at, updated_at, hlc_timestamp, device_id) '
        "SELECT 'n' || i, ?, 'Set ' || i, 1, 1, 0, 0, 'h', 'd' FROM seq",
        [folder.id],
      );
      await db.customStatement(
        'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
        "hlc_timestamp, device_id) SELECT 'c' || id, id, 0, 'x', 'h', 'd' "
        'FROM notes',
      );
      Future<int> countOf(String sql) async =>
          (await db.customSelect(sql).getSingle()).read<int>('n');

      await db.noteDao.softDeleteNotesWithChunks([
        for (var i = 1; i <= count; i++) 'n$i',
      ]);

      expect(
        await countOf('SELECT COUNT(*) AS n FROM notes WHERE is_deleted = 0'),
        0,
      );
      expect(await countOf('SELECT COUNT(*) AS n FROM content_chunks'), 0);
      expect(
        await countOf(
          "SELECT COUNT(*) AS n FROM sync_outbox WHERE table_name = 'notes'",
        ),
        count,
      );
    });

    test('the chunk delete runs one statement per id batch', () async {
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);
      final ids = [
        for (var i = 0; i < 2 * AppConstants.sqlIdBatch + 1; i++) 'n$i',
      ];

      counter.reset();
      await counted.contentChunkDao.deleteChunksForNotes(ids);

      expect(counter.matching('DELETE FROM "content_chunks"'), hasLength(3));
    });
  });

  group('the v47 purge', () {
    Future<void> insertChunk(
      String id,
      String noteId,
      int index, {
      bool deleted = false,
    }) {
      return db.customStatement(
        'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
        'is_compressed, hlc_timestamp, device_id, is_deleted) '
        "VALUES (?, ?, ?, 'x', 0, 'h', 'd', ?)",
        [id, noteId, index, deleted ? 1 : 0],
      );
    }

    /// The v46 chunk index: partial, the one the purge runs under.
    Future<void> v46ChunkIndex(AppDatabase on) async {
      await on.customStatement('DROP INDEX IF EXISTS idx_content_chunks_note');
      await on.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_chunks_note_index ON '
        'content_chunks(note_id, chunk_index) WHERE is_deleted = 0',
      );
    }

    Future<void> runStep(AppDatabase on) async {
      await v46ChunkIndex(on);
      await DatabaseMigrations(on).runMigrations(
        on.createMigrator(),
        DatabaseSchema.v46ContentChunkHashes,
        DatabaseSchema.v47StorageHygiene,
      );
    }

    Future<Set<String>> chunkIds() async => {
      for (final row
          in await db.customSelect('SELECT id FROM content_chunks').get())
        row.read<String>('id'),
    };

    test('scans content_chunks once', () async {
      final counter = _CustomStatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);
      await runStep(counted);
      final purge = counter.captured.singleWhere(
        (c) => c.sql.startsWith('DELETE FROM content_chunks'),
      );
      await v46ChunkIndex(counted);

      final plan = await explainCaptured(counted, purge);

      final scans = [
        for (final line in plan)
          if (RegExp(r'^SCAN (content_chunks|c)\b').hasMatch(line)) line,
      ];
      expect(scans, ['SCAN content_chunks'], reason: plan.join('\n'));
    });

    test('keeps only live notes\' live chunks, and the tombstoned text of a '
        'live note left with no live chunk', () async {
      Future<Note> note(String title, String content) => db.noteDao.createNote(
        folderId: folder.id,
        title: title,
        content: content,
        contentLength: content.length,
      );
      Future<Set<String>> chunksOf(String noteId) async => {
        for (final row
            in await db
                .customSelect(
                  'SELECT id FROM content_chunks WHERE note_id = ?',
                  variables: [Variable<String>(noteId)],
                )
                .get())
          row.read<String>('id'),
      };
      final live = await note('Live', 'bench 80');
      final dead = await note('Dead', 'row 60');
      final anomalous = await note('Half-synced', 'deadlift 140');
      final empty = await note('Empty', '');
      expect(anomalous.contentLength, greaterThan(0));
      final liveChunks = await chunksOf(live.id);
      final anomalousChunks = await chunksOf(anomalous.id);
      expect(liveChunks, isNotEmpty);
      expect(anomalousChunks, isNotEmpty);
      expect(await chunksOf(dead.id), isNotEmpty);

      await db.customStatement('UPDATE notes SET is_deleted = 1 WHERE id = ?', [
        dead.id,
      ]);
      await db.customStatement(
        'UPDATE content_chunks SET is_deleted = 1 WHERE note_id = ?',
        [anomalous.id],
      );
      await insertChunk('dead-tombstoned', dead.id, 1, deleted: true);
      await insertChunk('orphan', 'gone', 0);
      await insertChunk('older-version', live.id, 99, deleted: true);
      await insertChunk('empty-tombstoned', empty.id, 0, deleted: true);

      await runStep(db);

      expect(await chunkIds(), {...liveChunks, ...anomalousChunks});
      expect(await db.contentChunkDao.loadContent(live.id), 'bench 80');
    });
  });
}

/// Also records `customStatement`, the way every migration step writes.
class _CustomStatementCounter extends StatementCounter {
  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    captured.add(CapturedStatement(statement, args));
    return super.runCustom(executor, statement, args);
  }
}
