import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/daos/note_search_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

Future<void> _noWait() async {}

bool _neverBusy() => false;

Future<R> _inline<R>(R Function() work) async => work();

/// The tags v57 left unread are the drain's work, never the search's: a
/// search over a current index answers at once, says it is complete, and
/// never shows "still indexing" while the backfill fills them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late NoteStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    final folder = await db.folderDao.createFolder(name: 'Training');
    for (var i = 0; i < 4; i++) {
      await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Session $i',
        contentLength: 14,
        content: 'squat #set$i',
      );
    }
    await BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
    ).drain();
    storage = NoteStorageService(repository: NoteRepository(database: db));
    await storage.initialize();
  });

  tearDown(() async => db.close());

  /// What the v57 step leaves (`ledger_tags_migration_test.dart`): every
  /// ledger row current, its tags unread.
  Future<void> unreadTags() =>
      db.customStatement('UPDATE note_search_ledger SET tags = NULL');

  Future<int> unread() async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM note_search_ledger WHERE tags IS NULL',
              )
              .getSingle())
          .read<int>('n');

  test('the probe asks about the index alone', () async {
    await unreadTags();

    expect(await NoteSearchDao(db).hasPendingWork(), isFalse);
    expect(await unread(), 4);
  });

  // Since the probe no longer asks after the tags, the one-time backfill
  // runs only because a new indexer starts dirty: these pin that.
  test('a fresh indexer\'s launch start alone fills every unread tag, and '
      'the catalog reads them', () async {
    await unreadTags();
    final indexer = BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
    );

    indexer.start();
    await indexer.whenIdle();

    expect(await unread(), 0);
    expect(
      await NoteSearchDao(db).catalogTags(),
      unorderedEquals(['set0', 'set1', 'set2', 'set3']),
    );
  });

  test('a backfill a switch cut short is finished by the next database '
      'open\'s indexer', () async {
    await unreadTags();
    late BodySearchIndexer cut;
    cut = BodySearchIndexer(
      database: db,
      pageBytes: 1,
      scheduler: BodyIndexScheduler(
        // What a switch does to the indexer it leaves (`reset`).
        yieldBetweenPages: () async => cut.close(),
        editorBusy: _neverBusy,
        editorPoll: _noWait,
        run: _inline,
      ),
    );
    cut.start();
    await cut.whenIdle();
    expect(await unread(), 3, reason: 'one page landed before the cut');

    final next = BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
    );
    next.start();
    await next.whenIdle();

    expect(await unread(), 0);
  });

  test('a full and a quick search answer complete while the backfill is '
      'held between its pages', () async {
    await unreadTags();
    final firstPage = Completer<void>();
    final resume = Completer<void>();
    final indexer = BodySearchIndexer(
      database: db,
      pageBytes: 1,
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: () {
          if (!firstPage.isCompleted) firstPage.complete();
          return resume.future;
        },
        editorBusy: _neverBusy,
        editorPoll: _noWait,
        run: _inline,
      ),
    );
    final search = FolderSearchService(
      storageService: storage,
      indexer: () async => indexer,
      indexBudget: const Duration(seconds: 2),
    );
    addTearDown(() async {
      if (!resume.isCompleted) resume.complete();
      await indexer.whenIdle();
      await search.close();
    });

    unawaited(indexer.drain());
    await firstPage.future;
    expect(await unread(), 3, reason: 'one tag page landed, three wait');

    final watch = Stopwatch()..start();
    final full = await search.searchWithCoverage('squat');
    watch.stop();
    expect(full.incomplete, isFalse, reason: 'the index is current');
    expect(full.results, hasLength(4));
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'never waits its budget on tags',
    );
    expect(indexer.mayBeBehind, isFalse);
    final quick = await search.quickSearchWithCoverage('squat');
    expect(quick.incomplete, isFalse);
    expect(quick.results, hasLength(4));
    await search.whenIndexed().timeout(const Duration(seconds: 1));
    expect(resume.isCompleted, isFalse, reason: 'the backfill is still held');

    resume.complete();
    await indexer.whenIdle();
    expect(await unread(), 0);
  });

  test('a note edited while the backfill runs keeps "incomplete" until a '
      'drain has projected it', () async {
    await unreadTags();
    final firstPage = Completer<void>();
    final resume = Completer<void>();
    final indexer = BodySearchIndexer(
      database: db,
      pageBytes: 1,
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: () {
          if (!firstPage.isCompleted) firstPage.complete();
          return resume.future;
        },
        editorBusy: _neverBusy,
        editorPoll: _noWait,
        run: _inline,
      ),
    );
    final search = FolderSearchService(
      storageService: storage,
      indexer: () async => indexer,
      indexBudget: const Duration(milliseconds: 500),
    );
    addTearDown(() async {
      if (!resume.isCompleted) resume.complete();
      await indexer.whenIdle();
      await search.close();
    });
    unawaited(indexer.drain());
    await firstPage.future;

    final edited = (await db.noteDao.getAllNotes()).first;
    await db.noteDao.updateNote(
      id: edited.id,
      contentLength: 14,
      content: 'deadlift #set9',
    );

    final behind = await search.searchWithCoverage('deadlift');
    expect(behind.incomplete, isTrue, reason: 'the index is behind');
    var settled = false;
    unawaited(search.whenIndexed().then((_) => settled = true));
    await pumpEventQueue();
    expect(settled, isFalse, reason: 'nothing has projected the edit yet');

    resume.complete();
    await search.whenIndexed();
    final found = await search.searchWithCoverage('deadlift');
    expect(found.incomplete, isFalse);
    expect(found.results.single.metadata.id, edited.id);
  });
}
