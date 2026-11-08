import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/search_constants.dart';
import 'package:anta/database/daos/note_search_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/utils/compression_utils.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

Future<void> _noWait() async {}

bool _neverBusy() => false;

Future<R> _inline<R>(R Function() work) async => work();

/// The body index's drain and the search over it (S11,
/// `docs/scalability-roadmap.md` §5.5): what they read, what they write, what
/// they leave alone, and how they stop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StatementCounter statements;
  late Folder folder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    folder = await db.folderDao.createFolder(name: 'Training');
  });

  tearDown(() async => db.close());

  Future<Note> note(String title, String body) => db.noteDao.createNote(
    folderId: folder.id,
    title: title,
    contentLength: body.length,
    content: body,
  );

  Future<Map<String, String>> ledger() async {
    final rows = await db
        .customSelect('SELECT note_id, indexed_hlc FROM note_search_ledger')
        .get();
    return {
      for (final row in rows)
        row.read<String>('note_id'): row.read<String>('indexed_hlc'),
    };
  }

  Future<String> hlcOf(String id) async =>
      (await db.noteDao.getNoteById(id))!.hlcTimestamp;

  BodySearchIndexer indexerWith({
    AppDatabase? database,
    BodyIndexScheduler scheduler = inlineBodyIndexScheduler,
    int pageBytes = 256 * 1024,
  }) => BodySearchIndexer(
    database: database ?? db,
    scheduler: scheduler,
    pageBytes: pageBytes,
  );

  Future<NoteStorageService> storageOver(AppDatabase database) async {
    final notes = NoteStorageService(
      repository: NoteRepository(database: database),
    );
    await notes.initialize();
    return notes;
  }

  /// The batched body reads — `loadContentForNotes` — as opposed to the
  /// per-hit `loadContent` a result's offsets cost.
  int batchedBodyReads() => statements
      .matching('FROM "content_chunks"')
      .where((sql) => sql.contains(' IN ('))
      .length;

  test('the trigram table exists on this SQLite and answers', () async {
    expect(
      await NoteSearchDao(db).probeCapability(),
      BodyIndexCapability.usable,
    );
  });

  test('the counter sees every index write (positive control)', () async {
    for (var i = 0; i < 3; i++) {
      await note('Session $i', 'squat bench row');
    }
    statements.reset();

    await indexerWith().drain();

    expect(statements.executions('INSERT INTO note_body_fts'), 3);
    expect(
      statements.executions('INSERT OR REPLACE INTO note_search_ledger'),
      3,
    );
    expect(
      statements.executions('DELETE FROM note_body_fts WHERE rowid = ?'),
      3,
      reason: 'delete-before-insert, by rowid',
    );
  });

  test('a page\'s transaction holds the index writes alone: its bodies are '
      'read and decompressed before it opens', () async {
    for (var i = 0; i < 3; i++) {
      // Past the chunk compression threshold, so a read decompresses.
      await note('Session $i', '${'squat bench row ' * 800}set $i');
    }
    final inside = <String>[];
    var from = 0;
    statements.onTransaction = (begins) {
      if (begins) {
        from = statements.count;
      } else {
        inside.addAll(statements.statements.skip(from));
      }
    };
    statements.reset();

    await indexerWith().drain();

    expect(statements.executions('INSERT INTO note_body_fts'), 3);
    expect(inside, isNotEmpty);
    expect(
      inside.where(
        (sql) =>
            !sql.contains('note_search_ledger') &&
            !sql.contains('note_body_fts'),
      ),
      isEmpty,
    );
  });

  test('a page past the isolate threshold projects in an isolate', () async {
    // The closure an isolate receives must carry the page alone: one that
    // captured the indexer would fail to send its database.
    await note('Long', '${'bench press ' * 8000}zercher');
    final indexer = indexerWith(
      scheduler: const BodyIndexScheduler(
        yieldBetweenPages: _noWait,
        editorBusy: _neverBusy,
        editorPoll: _noWait,
      ),
    );

    await indexer.drain();

    expect(await ledger(), hasLength(1));
    expect(await indexer.candidates({'zercher'}), hasLength(1));
  });

  test('a write path issues no index statement', () async {
    final session = await note('Session', 'squat');
    await indexerWith().drain();
    statements.reset();

    await db.noteDao.updateNote(
      id: session.id,
      contentLength: 9,
      content: 'squat row',
    );
    await db.noteDao.updateNoteLabel(id: session.id, label: ItemLabel.red);

    expect(statements.matching('note_body_fts'), isEmpty);
    expect(statements.matching('note_search_ledger'), isEmpty);
  });

  test('a stale note is re-projected once', () async {
    final session = await note('Session', 'squat');
    final indexer = indexerWith();
    await indexer.drain();

    await db.noteDao.updateNote(
      id: session.id,
      contentLength: 9,
      content: 'squat row',
    );
    statements.reset();
    await indexer.drain();
    expect(statements.executions('INSERT INTO note_body_fts'), 1);
    expect((await ledger())[session.id], await hlcOf(session.id));

    statements.reset();
    await indexer.drain();
    expect(statements.executions('INSERT INTO note_body_fts'), 0);
  });

  test('a label change is settled by one touch, never re-projected', () async {
    final session = await note('Session', 'squat');
    await note('Other', 'bench');
    final indexer = indexerWith();
    await indexer.drain();

    await db.noteDao.updateNoteLabel(id: session.id, label: ItemLabel.teal);
    expect((await ledger())[session.id], isNot(await hlcOf(session.id)));
    statements.reset();
    await indexer.drain();

    expect(statements.executions('INSERT INTO note_body_fts'), 0);
    expect(statements.executions('FROM "content_chunks"'), 0);
    expect(statements.executions('UPDATE note_search_ledger'), 1);
    expect((await ledger())[session.id], await hlcOf(session.id));
  });

  // Review P4: the chunk planner keeps a moved chunk's stamp, so swapping two
  // blocks changes no count and no stamp — only their order, which the
  // fingerprint must see, or words joined at the new seams stay unfindable.
  test('a body whose chunks were only reordered is re-projected', () async {
    final body = [for (var i = 0; i < 9000; i++) 'w$i'].join(' ');
    final session = await note('Long', body);
    final indexer = indexerWith();
    await indexer.drain();

    final chunks = await db.contentChunkDao.getChunksForNote(session.id);
    expect(chunks.length, greaterThan(2), reason: 'the body must be cut');
    String text(ContentChunk c) => c.isCompressed
        ? CompressionUtils.decompressFromBase64(c.content)
        : c.content;
    final first = text(chunks[0]);
    final second = text(chunks[1]);
    final swapped =
        second + first + body.substring(first.length + second.length);
    expect(swapped, hasLength(body.length));
    await db.noteDao.updateNote(
      id: session.id,
      contentLength: swapped.length,
      content: swapped,
    );
    expect(
      {
        for (final c in await db.contentChunkDao.getChunksForNote(session.id))
          c.id,
      },
      {for (final c in chunks) c.id},
      reason: 'a moves-only plan: the same chunks, reordered, stamps kept',
    );
    statements.reset();

    await indexer.drain();

    expect(statements.executions('INSERT INTO note_body_fts'), 1);
    final tail = RegExp(r'\w+$').stringMatch(second) ?? '';
    final head = RegExp(r'^\w+').stringMatch(first) ?? '';
    if (tail.isNotEmpty && head.isNotEmpty) {
      expect(
        await indexer.candidates({'$tail$head'}),
        hasLength(1),
        reason: 'the word the swap joined at the seam',
      );
    }
  });

  test('a deleted note leaves the index at the next drain', () async {
    final session = await note('Session', 'squat');
    final indexer = indexerWith();
    await indexer.drain();

    await db.noteDao.softDeleteNote(session.id);
    await indexer.drain();

    expect(await ledger(), isEmpty);
    expect(
      await NoteSearchDao(db).matching(bodyMatchExpression({'squat'})),
      isEmpty,
    );
  });

  test(
    'an unreadable note is settled by its title until it is written',
    () async {
      final broken = await note('Broken squat', 'zercher');
      await note('Fine', 'bench');
      await db.customUpdate(
        "UPDATE content_chunks SET is_compressed = 1, content = 'not base64!' "
        'WHERE note_id = ?',
        variables: [Variable<String>(broken.id)],
      );
      final search = FolderSearchService(
        storageService: await storageOver(db),
        indexer: bodyIndexerOver(db),
      );
      addTearDown(search.close);

      await search.search('bench');
      expect(await ledger(), hasLength(2));
      expect(await NoteSearchDao(db).hasPendingWork(), isFalse);
      expect(
        await NoteSearchDao(db).matching(bodyMatchExpression({'squat'})),
        hasLength(1),
        reason: 'its title is still searchable',
      );

      statements.reset();
      await search.search('bench');
      expect(statements.count, 3, reason: 'back to the warm search');
      expect(statements.matching('wal_checkpoint'), isEmpty);

      await db.noteDao.updateNote(
        id: broken.id,
        contentLength: 7,
        content: 'deadlift',
      );
      statements.reset();
      expect(await search.search('deadlift'), hasLength(1));
      expect(statements.executions('INSERT INTO note_body_fts'), 1);
    },
  );

  test('the compare-and-set skips a note whose stamp moved', () async {
    final session = await note('Session', 'squat');
    final dao = NoteSearchDao(db);
    final stale = (await dao.staleNotes()).single;

    await db.noteDao.updateNote(
      id: session.id,
      contentLength: 5,
      content: 'bench',
    );
    final written = await dao.writeProjections([
      BodyProjection(
        rowid: stale.rowid,
        id: stale.id,
        hlc: stale.hlc,
        text: searchProjection('Session', 'squat'),
        title: titleProjection('Session'),
        tags: tagProjection('squat'),
      ),
    ]);

    expect(written, 0);
    expect(await ledger(), isEmpty);
    expect(await dao.matching(bodyMatchExpression({'squat'})), isEmpty);

    await indexerWith().drain();
    expect(await dao.matching(bodyMatchExpression({'bench'})), hasLength(1));
  });

  test('a page holds at most bodyPageMaxNotes notes, however small', () async {
    final now = DateTime.now();
    await db.batch((batch) {
      for (var i = 0; i < 1200; i++) {
        batch.insert(
          db.notes,
          NotesCompanion.insert(
            id: 'tiny$i',
            folderId: folder.id,
            title: 'Filler $i',
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
    final pages = (1200 / SearchConstants.bodyPageMaxNotes).ceil();
    final search = FolderSearchService(
      storageService: await storageOver(db),
      indexer: bodyIndexerOver(db),
    );
    addTearDown(search.close);

    statements.reset();
    await search.buildIndex();
    expect(batchedBodyReads(), pages, reason: 'the backfill');

    statements.reset();
    expect(await search.search('filler', limit: 5), hasLength(5));
    expect(batchedBodyReads(), pages, reason: 'the scoring');
  });

  test('a database switch mid-drain writes nothing after it', () async {
    for (var i = 0; i < 4; i++) {
      await note('Session $i', 'squat bench');
    }
    final paused = Completer<void>();
    final resume = Completer<void>();
    final indexer = indexerWith(
      pageBytes: 11,
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: () {
          if (!paused.isCompleted) paused.complete();
          return resume.future;
        },
        editorBusy: _neverBusy,
        editorPoll: _noWait,
        run: _inline,
      ),
    );

    final drained = indexer.drain();
    await paused.future;
    expect(await ledger(), hasLength(1), reason: 'one page landed');
    DatabaseLifecycle.notifyDatabaseSwitching();
    resume.complete();
    await drained;

    expect(await ledger(), hasLength(1));
  });

  test('the drain waits while an editor holds unsaved text', () async {
    await note('Session', 'squat');
    var busy = true;
    final polled = Completer<void>();
    final indexer = indexerWith(
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: _noWait,
        editorBusy: () => busy,
        editorPoll: () async {
          if (!polled.isCompleted) polled.complete();
          await pumpEventQueue();
        },
        run: _inline,
      ),
    );

    final drained = indexer.drain();
    await polled.future;
    expect(await ledger(), isEmpty);
    busy = false;
    await drained;

    expect(await ledger(), hasLength(1));
  });

  test(
    'the editor pause is bounded: a refused save cannot hold the index',
    () async {
      await note('Session', 'squat');
      var polls = 0;
      final indexer = indexerWith(
        scheduler: BodyIndexScheduler(
          yieldBetweenPages: _noWait,
          editorBusy: () => true,
          editorPoll: () async => polls++,
          run: _inline,
        ),
      );

      await indexer.drain();

      expect(
        polls,
        SearchConstants.bodyIndexEditorPauseLimit.inMilliseconds ~/
            SearchConstants.bodyIndexEditorPoll.inMilliseconds,
      );
      expect(await ledger(), hasLength(1));
    },
  );

  group('an edit with no search between it and the drain', () {
    // Review P1: the edit lands after the launch drain and before any full
    // search, so no flag can be relied on to have reached the indexer.
    test('is found by the next search', () async {
      final notes = await storageOver(db);
      final search = FolderSearchService(
        storageService: notes,
        indexer: bodyIndexerOver(db),
      );
      addTearDown(search.close);
      final session = await notes.createNote(
        folderId: folder.id,
        title: 'Session',
        content: 'squat',
      );
      await search.buildIndex();

      await notes.updateNote(noteId: session.id, content: 'zercher');

      expect(await search.search('zercher'), hasLength(1));
    });

    // Review P1c: a search on one database, a switch, a drain of the next,
    // then an edit there.
    test('is found after a switch too', () async {
      final other = await openTestDatabase();
      addTearDown(other.close);
      final repository = NoteRepository(database: db);
      final notes = NoteStorageService(repository: repository);
      await notes.initialize();
      var active = indexerWith();
      final search = FolderSearchService(
        storageService: notes,
        indexer: () async => active,
      );
      addTearDown(search.close);
      await note('Session', 'squat');
      expect(await search.search('squat'), hasLength(1));

      DatabaseLifecycle.notifyDatabaseSwitching();
      repository.rebindDatabase(other);
      active = indexerWith(database: other);
      final elsewhere = await other.folderDao.createFolder(name: 'Elsewhere');
      final moved = await notes.createNote(
        folderId: elsewhere.id,
        title: 'Other',
        content: 'bench',
      );
      await search.buildIndex();

      await notes.updateNote(noteId: moved.id, content: 'zercher');

      expect(await search.search('zercher'), hasLength(1));
    });
  });

  group('a search during the backfill', () {
    late Completer<void> resume;
    late BodySearchIndexer indexer;
    late FolderSearchService search;

    setUp(() async {
      for (var i = 0; i < 3; i++) {
        await note('Session $i', 'squat bench');
      }
      resume = Completer<void>();
      var first = true;
      indexer = indexerWith(
        scheduler: BodyIndexScheduler(
          yieldBetweenPages: _noWait,
          editorBusy: () => first,
          editorPoll: () async {
            await resume.future;
            first = false;
          },
          run: _inline,
        ),
      );
      search = FolderSearchService(
        storageService: await storageOver(db),
        indexer: () async => indexer,
        indexBudget: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      if (!resume.isCompleted) resume.complete();
      await indexer.whenIdle();
      await search.close();
    });

    test('answers within its budget and says it is incomplete', () async {
      final found = await search.searchWithCoverage('squat');

      expect(resume.isCompleted, isFalse, reason: 'the drain is still held');
      expect(found.results, isEmpty, reason: 'nothing is indexed yet');
      expect(found.incomplete, isTrue);

      resume.complete();
      await search.whenIndexed();

      final again = await search.searchWithCoverage('squat');
      expect(again.incomplete, isFalse);
      expect(again.results, hasLength(3));
    });
  });

  group('the capability guard', () {
    test('a missing table is created again by the next indexer', () async {
      await note('Session', 'heavy squat');
      await db.customStatement('DROP TABLE note_body_fts');

      await indexerWith().drain();

      expect(
        await NoteSearchDao(db).probeCapability(),
        BodyIndexCapability.usable,
      );
      expect(await ledger(), hasLength(1));
    });

    test(
      'a one-column table left at v50 is recreated once, then filled',
      () async {
        await note('Session', 'heavy squat');
        await indexerWith().drain();
        // What a refused v50 drop leaves: the v48 shape, with its ledger.
        await db.customStatement('DROP TABLE note_body_fts');
        await db.customStatement(
          'CREATE VIRTUAL TABLE note_body_fts USING fts5(body, '
          "tokenize='trigram case_sensitive 1', content='', "
          'contentless_delete=1)',
        );
        expect(
          await NoteSearchDao(db).probeCapability(),
          BodyIndexCapability.unsupported,
        );
        statements.reset();

        final indexer = indexerWith();
        await indexer.drain();
        await note('Bench', 'press');
        await indexer.drain();

        expect(
          statements.executions('INSERT INTO note_body_fts'),
          2,
          reason:
              'the old note once, into the new table, and the new one; a '
              'second recreate would have projected the old note again',
        );
        final ddl = await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'note_body_fts'",
            )
            .getSingle();
        expect(ddl.read<String>('sql'), contains('tags'));
        expect(
          await NoteSearchDao(db).probeCapability(),
          BodyIndexCapability.usable,
        );
        final hits = await indexer.quickMatches(
          quickTitleExpression({'squat'}, const {}),
          quickMatchExpression({'squat'}, const {}),
          limit: 10,
        );
        expect([for (final hit in hits!) hit.note.title], ['Session']);
      },
    );

    test('a table this SQLite cannot query falls back to scoring', () async {
      await note('Session', 'heavy squat');
      await note('Other', 'bench press');
      // Holds the name, so `CREATE VIRTUAL TABLE IF NOT EXISTS` is a no-op
      // and the MATCH probe fails — a `.db` from a SQLite with the tokenizer
      // opened by one without it.
      await db.customStatement('DROP TABLE note_body_fts');
      await db.customStatement('CREATE TABLE note_body_fts (body TEXT)');
      final search = FolderSearchService(
        storageService: await storageOver(db),
        indexer: bodyIndexerOver(db),
      );
      addTearDown(search.close);
      statements.reset();

      final found = await search.searchWithCoverage('quat');

      expect(found.results.map((r) => r.metadata.title), ['Session']);
      expect(found.incomplete, isFalse);
      expect(statements.matching('INSERT'), isEmpty);
    });
  });

  test('a stored label outside the palette filters as no colour', () async {
    final odd = await note('Odd', 'squat');
    await db.customUpdate(
      'UPDATE notes SET label = 42 WHERE id = ?',
      variables: [Variable<String>(odd.id)],
    );
    final search = FolderSearchService(
      storageService: await storageOver(db),
      indexer: bodyIndexerOver(db),
    );
    addTearDown(search.close);

    final none = await search.search(
      'squat',
      filter: const SearchFilter(labels: {ItemLabel.none}),
    );
    final red = await search.search(
      'squat',
      filter: const SearchFilter(labels: {ItemLabel.red}),
    );

    expect(none.map((r) => r.metadata.title), ['Odd']);
    expect(red, isEmpty);
  });

  test('one search is a constant number of statements', () async {
    Future<int> statementsFor(int fillers) async {
      final search = FolderSearchService(
        storageService: await storageOver(db),
        indexer: bodyIndexerOver(db),
      );
      addTearDown(search.close);
      for (var i = 0; i < fillers; i++) {
        await note('Filler $i', 'bench press and row');
      }
      await search.buildIndex();
      // Warm the per-hit body cache so only the search's own reads count.
      await search.search('zercher');
      statements.reset();
      await search.search('zercher');
      return statements.count;
    }

    await note('Hit one', 'zercher squat');
    await note('Hit two', 'zercher carry');
    final small = await statementsFor(5);
    final large = await statementsFor(120);

    expect(
      small,
      3,
      reason: 'the stale probe, the match, then one batched body read',
    );
    expect(large, small);
  });
}
