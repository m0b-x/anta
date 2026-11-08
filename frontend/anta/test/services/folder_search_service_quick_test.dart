import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/search/search_bloc.dart';
import 'package:anta/database/daos/note_search_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/utils/tag_extractor.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

Future<void> _noWait() async {}

Future<R> _inline<R>(R Function() work) async => work();

/// The quick search on the body index (S12, D6,
/// `docs/scalability-roadmap.md` §5.5): what it finds beyond the newest
/// page, how it ranks, what a short word and a tag do, how it answers while
/// the index is behind, and what one keystroke costs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StatementCounter statements;
  late NoteStorageService notes;
  late Folder folder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    notes = NoteStorageService(repository: NoteRepository(database: db));
    await notes.initialize();
    folder = await db.folderDao.createFolder(name: 'Training');
  });

  tearDown(() async => db.close());

  Future<Note> note(String title, String body) => db.noteDao.createNote(
    folderId: folder.id,
    title: title,
    contentLength: body.length,
    content: body,
  );

  /// A note written the way the editor writes one, preview included: what
  /// the newest-notes scan reads besides the title.
  Future<NoteMetadata> previewed(String title, String body) =>
      notes.createNote(folderId: folder.id, title: title, content: body);

  /// Sets [id]'s `updated_at` without moving its stamp, so the index keeps
  /// its projection and only the order a tie falls back on changes.
  Future<void> updatedAt(String id, DateTime at) => db.customUpdate(
    'UPDATE notes SET updated_at = ? WHERE id = ?',
    variables: [Variable<DateTime>(at), Variable<String>(id)],
  );

  FolderSearchService serviceOver(BodySearchIndexer indexer) =>
      FolderSearchService(storageService: notes, indexer: () async => indexer);

  Future<FolderSearchService> drained() async {
    final indexer = BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
    );
    await indexer.drain();
    return serviceOver(indexer);
  }

  List<String> titles(List<SearchResult> results) => [
    for (final result in results) result.metadata.title,
  ];

  test('a word deep in the 1,000th newest note is a quick hit', () async {
    final now = DateTime.now();
    await db.batch((batch) {
      for (var i = 0; i < 1000; i++) {
        final id = 'n$i';
        final body = i == 999
            ? '${'filler line about rows and sets\n' * 300}zercher carry'
            : 'squat bench row $i';
        batch.insert(
          db.notes,
          NotesCompanion.insert(
            id: id,
            folderId: folder.id,
            title: 'Session $i',
            contentLength: Value(body.length),
            chunkCount: const Value(1),
            hlcTimestamp: 'h$i',
            deviceId: 'd',
            createdAt: now.subtract(Duration(minutes: i)),
            updatedAt: now.subtract(Duration(minutes: i)),
          ),
        );
        batch.insert(
          db.contentChunks,
          ContentChunksCompanion.insert(
            id: '${id}_0',
            noteId: id,
            chunkIndex: 0,
            content: body,
            hlcTimestamp: 'h$i',
            deviceId: 'd',
          ),
        );
      }
    });
    final search = await drained();

    final results = await search.quickSearch('zercher');

    expect(titles(results), ['Session 999']);
  });

  test('a two-character word matches titles only', () async {
    await note('Ab day', 'planks');
    await note('Rest', 'abs and more abs, abduction');
    final search = await drained();

    expect(titles(await search.quickSearch('ab')), ['Ab day']);
    expect(
      titles(await search.quickSearch('abs')),
      ['Rest'],
      reason: 'three characters reach the body again',
    );
  });

  test('bm25 ranks a title hit above a body-only hit', () async {
    final body = await note('Log', 'easy squat day');
    final title = await note('Squat', 'easy day');
    await drained();

    final hits = await NoteSearchDao(
      db,
    ).quickMatching(quickMatchExpression({'squat'}, const {}), limit: 10);

    expect([for (final hit in hits) hit.note.id], [title.id, body.id]);
  });

  // FTS5's bm25 weighs a column by multiplying its term frequency into one
  // saturating sum per row, so a body repeating a word can outscore a title
  // naming it once; the bar still lists title hits first.
  test('a title hit stays first over a body that repeats the word', () async {
    final body = await note('Log', 'squat squat squat squat squat squat');
    await note('Squat', 'easy day');
    final search = await drained();

    final hits = await NoteSearchDao(
      db,
    ).quickMatching(quickMatchExpression({'squat'}, const {}), limit: 10);
    expect(hits.first.note.id, body.id, reason: 'bm25 alone');

    expect(titles(await search.quickSearch('squat')), ['Squat', 'Log']);
  });

  test('equal scores fall back to the newest edit', () async {
    final older = await note('Bench', 'bench');
    final newer = await note('Bench', 'bench');
    final now = DateTime.now();
    await updatedAt(older.id, now.subtract(const Duration(days: 2)));
    await updatedAt(newer.id, now.subtract(const Duration(days: 1)));
    await drained();

    final hits = await NoteSearchDao(
      db,
    ).quickMatching(quickMatchExpression({'bench'}, const {}), limit: 10);

    expect(hits[0].score, hits[1].score);
    expect([for (final hit in hits) hit.note.id], [newer.id, older.id]);

    await updatedAt(older.id, now);
    final flipped = await NoteSearchDao(
      db,
    ).quickMatching(quickMatchExpression({'bench'}, const {}), limit: 10);
    expect([for (final hit in flipped) hit.note.id], [older.id, newer.id]);
  });

  group('a #tag', () {
    test('narrows to the notes carrying it, however deep', () async {
      final tagged = await note(
        'Monday',
        '${'warm-up sets and notes\n' * 40}squat day #LegDay',
      );
      await note('Tuesday', 'legday without the mark');
      await note('Thursday', 'squat #other');
      final search = await drained();

      expect(
        [for (final r in await search.quickSearch('#legday')) r.metadata.id],
        [tagged.id],
      );
      expect(titles(await search.quickSearch('squat #legday')), ['Monday']);
      expect(await search.quickSearch('bench #legday'), isEmpty);
    });

    test('narrows by prefix while it is typed, from one letter', () async {
      await note('Monday', 'squat day #legday');
      await note('Wednesday', 'squat #legdays');
      await note('Tuesday', 'legday without the mark');
      await note('Thursday', 'squat #other');
      final search = await drained();

      for (final typed in ['#l', '#le', '#leg', '#legday']) {
        expect(titles(await search.quickSearch(typed))..sort(), [
          'Monday',
          'Wednesday',
        ], reason: typed);
      }
    });

    test('the scan narrows by prefix as the index does', () async {
      await previewed('Monday', 'squat day #legday');
      await previewed('Tuesday', 'legday without the mark');
      // Never drained: the newest-notes scan answers alone.
      final search = serviceOver(
        BodySearchIndexer(database: db, scheduler: inlineBodyIndexScheduler),
      );

      for (final typed in ['#l', '#leg', '#legday']) {
        expect(titles(await search.quickSearch(typed)), [
          'Monday',
        ], reason: typed);
      }
    });

    test('the quick and the full search narrow alike; the full search '
        'names the tag whole', () async {
      await note('Monday', 'squat day #LegDay');
      await note('Tuesday', 'legday without the mark');
      await note('Wednesday', 'squat #legdays');
      final search = await drained();

      expect(
        titles(await search.quickSearch('#legday'))..sort(),
        ['Monday', 'Wednesday'],
        reason: 'while typing, #legday may still become #legdays',
      );
      expect(titles(await search.search('#legday')), ['Monday']);
      expect(titles(await search.search('squat #legday')), ['Monday']);
      expect(
        titles(await search.search('#legdays')),
        ['Wednesday'],
        reason: 'a whole tag never matches inside a longer or shorter one',
      );
    });

    test('folds case and diacritics as the editor reads it', () async {
      await note('Pull', 'sets of #tracțiune');
      final search = await drained();

      expect(titles(await search.quickSearch('#Tractiune')), ['Pull']);
    });
  });

  group('the catch-up', () {
    /// An indexer whose drain parks before its first page until [held]
    /// completes.
    BodySearchIndexer heldIndexer(Completer<void> held) => BodySearchIndexer(
      database: db,
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: _noWait,
        editorBusy: () => !held.isCompleted,
        editorPoll: () => held.future,
        run: _inline,
      ),
    );

    test('a keystroke never starts a drain; with none running the answer '
        'is complete, and a new note is found by its title', () async {
      final held = Completer<void>();
      final indexer = heldIndexer(held);
      await note('Zercher plan', 'carry and squat');
      final search = serviceOver(indexer);
      statements.reset();

      final found = await search.quickSearchWithCoverage('zercher');

      expect(titles(found.results), ['Zercher plan']);
      expect(
        found.incomplete,
        isFalse,
        reason: 'dirty but idle: nothing would settle to re-run it after',
      );
      expect(
        [
          for (final sql in statements.statements)
            if (!sql.trimLeft().startsWith('SELECT')) sql,
        ],
        isEmpty,
        reason: 'no drain wrote the index or the ledger',
      );
      expect(
        statements.matching('AS rid'),
        isEmpty,
        reason: 'no drain looked for stale notes',
      );
      expect(await NoteSearchDao(db).staleNotes(), hasLength(1));
      held.complete();
    });

    test(
      'opening the surface starts one drain; a second open joins it',
      () async {
        final held = Completer<void>();
        final indexer = heldIndexer(held);
        await note('Zercher plan', 'carry and squat');
        final search = serviceOver(indexer);
        statements.reset();

        await search.catchUpIndex();
        await pumpEventQueue();
        await search.catchUpIndex();
        await pumpEventQueue();

        expect(
          statements.matching('DELETE FROM note_body_fts'),
          hasLength(1),
          reason: 'one drain dropped orphans, parked behind the editor',
        );
        expect(await NoteSearchDao(db).staleNotes(), hasLength(1));

        held.complete();
        await indexer.whenIdle();
        final settled = await search.quickSearchWithCoverage('carry');
        expect(titles(settled.results), ['Zercher plan']);
        expect(settled.incomplete, isFalse);

        statements.reset();
        await search.catchUpIndex();
        await indexer.whenIdle();
        expect(
          statements.statements,
          isEmpty,
          reason: 'nothing moved, so the open starts nothing',
        );
      },
    );
  });

  group('a keystroke through the bloc', () {
    Future<void> type(SearchBloc bloc, String query) async {
      bloc.add(SearchQueryChanged(query));
      await Future<void>.delayed(SearchBloc.queryDebounce * 2);
      await pumpEventQueue();
    }

    SearchBloc blocOver(FolderSearchService search) => SearchBloc(
      searchService: search,
      noteService: notes,
      folderService: FolderStorageService(
        repository: FolderRepository(database: db),
      ),
    );

    test('runs once while the index is dirty and no drain runs', () async {
      await note('Zercher plan', 'carry and squat');
      final search = serviceOver(
        BodySearchIndexer(database: db, scheduler: inlineBodyIndexScheduler),
      );
      final bloc = blocOver(search);
      addTearDown(bloc.close);
      statements.reset();

      await type(bloc, 'zercher');
      await pumpEventQueue();

      expect(bloc.state.titleHits.map((r) => r.metadata.title), [
        'Zercher plan',
      ]);
      expect(
        statements.matching('quick_score'),
        hasLength(2),
        reason: 'one pass: its title and title-and-body MATCH, no re-run',
      );
    });

    test('runs once more after a running drain settles', () async {
      final held = Completer<void>();
      final indexer = BodySearchIndexer(
        database: db,
        scheduler: BodyIndexScheduler(
          yieldBetweenPages: _noWait,
          editorBusy: () => !held.isCompleted,
          editorPoll: () => held.future,
          run: _inline,
        ),
      );
      await note('Zercher plan', 'carry and squat');
      final search = serviceOver(indexer);
      final bloc = blocOver(search);
      addTearDown(bloc.close);
      await search.catchUpIndex();
      await pumpEventQueue();
      statements.reset();

      await type(bloc, 'carry');
      expect(statements.matching('quick_score'), hasLength(2));
      expect(bloc.state.contentHits, isEmpty, reason: 'not indexed yet');

      held.complete();
      await indexer.whenIdle();
      await pumpEventQueue();

      expect(
        statements.matching('quick_score'),
        hasLength(4),
        reason: 'the one re-run after the drain',
      );
      expect(bloc.state.contentHits.map((r) => r.metadata.title), [
        'Zercher plan',
      ]);
      await pumpEventQueue();
      expect(statements.matching('quick_score'), hasLength(4));
    });
  });

  test('a failing index read leaves the scan to answer, incomplete', () async {
    await note('Zercher plan', 'carry and squat');
    final indexer = _FailingIndexer(db);
    await indexer.drain();
    final search = serviceOver(indexer);

    final found = await search.quickSearchWithCoverage('zercher');

    expect(titles(found.results), ['Zercher plan']);
    expect(found.incomplete, isTrue);
  });

  group('title hits', () {
    test('an old title is first over ten heavier bodies', () async {
      final titled = await note('Squat', 'easy day');
      for (var i = 0; i < 12; i++) {
        await note('Log $i', 'squat squat squat squat squat squat');
      }
      final now = DateTime.now();
      await db.batch((batch) {
        for (var i = 0; i < 300; i++) {
          batch.insert(
            db.notes,
            NotesCompanion.insert(
              id: 'filler$i',
              folderId: folder.id,
              title: 'Filler $i',
              hlcTimestamp: 'h$i',
              deviceId: 'd',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      });
      await updatedAt(titled.id, now.subtract(const Duration(days: 30)));
      final search = await drained();

      final results = await search.quickSearch('squat');

      expect(results, hasLength(FolderSearchService.quickHitLimit));
      expect(results.first.metadata.id, titled.id);
    });

    test('are judged on the query as the index reads it', () async {
      await note('Log', 'squat bench squat bench squat bench squat bench');
      await note('Squat bench', 'easy day #legday');
      final search = await drained();

      for (final query in ['squat ', 'Squat', 'bench squat']) {
        expect(titles(await search.quickSearch(query)), [
          'Squat bench',
          'Log',
        ], reason: '"$query"');
      }
      expect(titles(await search.quickSearch('squat #legday')), [
        'Squat bench',
      ]);
    });

    test('a two-character word holds a title token start in the scan '
        'too', () async {
      await previewed('Cabin', 'nothing');
      await previewed('Ab day', 'planks');
      // Never drained: the newest-notes scan answers alone.
      final search = serviceOver(
        BodySearchIndexer(database: db, scheduler: inlineBodyIndexScheduler),
      );

      expect(titles(await search.quickSearch('ab')), ['Ab day']);
      expect(titles(await search.quickSearch('ab day')), ['Ab day']);
      expect(titles(await search.quickSearch('ab planks')), ['Ab day']);
      expect(await search.quickSearch('ab nothing'), isEmpty);
    });
  });

  test('a tagged keystroke leaves the report\'s tag cache alone', () async {
    final now = DateTime.now();
    await db.batch((batch) {
      for (var i = 0; i < 300; i++) {
        batch.insert(
          db.notes,
          NotesCompanion.insert(
            id: 'n$i',
            folderId: folder.id,
            title: 'Session $i',
            preview: Value('sets #week$i'),
            hlcTimestamp: 'h$i',
            deviceId: 'd',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
    const reported = 'a description with #legday';
    final cached = extractTags(reported);
    // Never drained: the scan reads all 300 previews' tags.
    final search = serviceOver(
      BodySearchIndexer(database: db, scheduler: inlineBodyIndexScheduler),
    );

    expect(await search.quickSearch('#week'), hasLength(10));

    expect(identical(extractTags(reported), cached), isTrue);
  });

  test('one keystroke is three statements and reads no body', () async {
    for (var i = 0; i < 20; i++) {
      await note('Session $i', 'squat bench row $i');
    }
    final search = await drained();
    await search.quickSearch('warm');
    statements.reset();

    final results = await search.quickSearch('squat');

    expect(results, hasLength(FolderSearchService.quickHitLimit));
    expect(
      statements.statements,
      hasLength(3),
      reason:
          'the title MATCH, the title-and-body MATCH and the newest page '
          '(the repository keeps the count): '
          '${statements.statements.join('\n')}',
    );
    expect(statements.matching('note_body_fts MATCH'), hasLength(2));
    expect(statements.matching('content_chunks'), isEmpty);
  });
}

/// An index whose quick read fails, as a transient `unknown` capability
/// does.
class _FailingIndexer extends BodySearchIndexer {
  _FailingIndexer(AppDatabase db)
    : super(database: db, scheduler: inlineBodyIndexScheduler);

  @override
  Future<List<({Note note, double score})>?> quickMatches(
    String titleMatch,
    String match, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
    required int limit,
  }) => Future.error(StateError('database is locked'));
}
