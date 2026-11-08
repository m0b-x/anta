import 'package:anta/database/daos/note_search_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';

Future<void> _noWait() async {}

bool _neverBusy() => false;

Future<R> _inline<R>(R Function() work) async => work();

/// Drains with no timers and no isolates: every page runs back to back, in
/// the test's own isolate.
const BodyIndexScheduler inlineBodyIndexScheduler = BodyIndexScheduler(
  yieldBetweenPages: _noWait,
  editorBusy: _neverBusy,
  editorPoll: _noWait,
  run: _inline,
);

/// The `indexer:` a `FolderSearchService` under test takes: one indexer over
/// [db], on [inlineBodyIndexScheduler] unless the test brings its own.
Future<BodySearchIndexer> Function() bodyIndexerOver(
  AppDatabase db, {
  BodyIndexScheduler scheduler = inlineBodyIndexScheduler,
}) {
  final indexer = BodySearchIndexer(database: db, scheduler: scheduler);
  return () async => indexer;
}

/// The ids of the live notes the body index holds [query]'s words for, once
/// a drain over [db] has caught it up — what the retired `notes_fts` checks
/// asked of a write path: is the note found by its new text, and no longer
/// by its old.
Future<List<String>> indexedHits(AppDatabase db, String query) async {
  await BodySearchIndexer(
    database: db,
    scheduler: inlineBodyIndexScheduler,
  ).drain();
  final notes = await NoteSearchDao(
    db,
  ).matching(bodyMatchExpression(tokenizeForSearch(query)));
  return [for (final note in notes) note.id];
}
