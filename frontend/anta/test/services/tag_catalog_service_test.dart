import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/tag_catalog.dart';
import 'package:anta/database/crdt/crdt_merge.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/note_search_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/catalog_tag.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/tag_catalog_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

/// The tag catalog: what it counts from the ledger, how it orders and
/// spells it, when it reads again, and what a switch leaves of it.
void main() {
  late AppDatabase db;
  late StatementCounter statements;
  late Folder folder;

  setUp(() async {
    TagCatalogService.reset();
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    folder = await db.folderDao.createFolder(name: 'Training');
  });

  tearDown(() async {
    TagCatalogService.reset();
    await db.close();
  });

  Future<Note> note(String title, String body) => db.noteDao.createNote(
    folderId: folder.id,
    title: title,
    contentLength: body.length,
    content: body,
  );

  Future<void> drain() => BodySearchIndexer(
    database: db,
    scheduler: inlineBodyIndexScheduler,
  ).drain();

  List<(String, int)> published() => [
    for (final tag in TagCatalog.all) (tag.tag, tag.noteCount),
  ];

  test('counts each folded tag once per note, under the spelling most notes '
      'use, most notes first and then by the folded form', () async {
    await note('A', '#Legday #cardio');
    await note('B', '#legday');
    await note('C', '#LegDay #Cardio');
    await note('D', '#legday #Mobility #alpha');
    await note('E', 'no tags at all');
    await drain();

    final service = await TagCatalogService.forTesting(db);

    expect(published(), [
      ('legday', 4),
      // A tie between two spellings goes to the one that sorts first.
      ('Cardio', 2),
      // Folded first, so a capital does not sort a tag ahead.
      ('alpha', 1),
      ('Mobility', 1),
    ]);
    expect(service.tags, TagCatalog.all);
    expect(
      TagCatalog.all.first,
      const CatalogTag(tag: 'legday', folded: 'legday', noteCount: 4),
    );
    expect(
      [
        for (final c in TagCatalog.candidates)
          (c.term, c.foldedTerm, c.vocabularyId, c.itemSortOrder),
      ],
      [
        ('#legday', '#legday', TagCatalog.sourceId, 0),
        ('#Cardio', '#cardio', TagCatalog.sourceId, 1),
        ('#alpha', '#alpha', TagCatalog.sourceId, 2),
        ('#Mobility', '#mobility', TagCatalog.sourceId, 3),
      ],
    );
  });

  test('folds diacritics as the search does', () async {
    await note('A', '#Café');
    await note('B', '#cafe');
    await note('C', '#Cafe');
    await drain();

    await TagCatalogService.forTesting(db);

    expect(TagCatalog.all.single.folded, 'cafe');
    expect(TagCatalog.all.single.noteCount, 3);
  });

  test('a tombstoned note is not counted, before the drain has swept '
      'it', () async {
    await note('A', '#squat');
    final gone = await note('B', '#squat #bench');
    await drain();
    final service = await TagCatalogService.forTesting(db);
    expect(published(), [('squat', 2), ('bench', 1)]);

    await db.noteDao.softDeleteNote(gone.id);
    await service.refresh();

    expect(published(), [('squat', 1)]);
  });

  test('reads again once a drain has written', () async {
    final service = await TagCatalogService.forTesting(db);
    expect(TagCatalog.all, isEmpty);

    await note('A', '#squat');
    await drain();
    await pumpEventQueue();

    expect(published(), [('squat', 1)]);
    expect(service.tags, TagCatalog.all);
  });

  test('a database switch clears the facade, and the dropped instance never '
      'publishes again', () async {
    await note('A', '#squat');
    await drain();
    final old = await TagCatalogService.forTesting(db);
    expect(TagCatalog.all, isNotEmpty);

    DatabaseLifecycle.notifyDatabaseSwitching();

    expect(TagCatalog.all, isEmpty);
    expect(TagCatalog.candidates, isEmpty);
    await old.refresh();
    await note('B', '#bench');
    await drain();
    await pumpEventQueue();
    expect(TagCatalog.all, isEmpty, reason: 'nobody holds the catalog now');

    final fresh = await TagCatalogService.forTesting(db);
    expect(identical(fresh, old), isFalse);
    expect(published(), [('bench', 1), ('squat', 1)]);
  });

  test('a refresh is one statement however many notes there are', () async {
    final service = await TagCatalogService.forTesting(db);
    Future<int> statementsFor(int notes) async {
      for (var i = 0; i < notes; i++) {
        await note('Note $i', '#tag$i #shared');
      }
      await drain();
      await pumpEventQueue();
      statements.reset();
      await service.refresh();
      return statements.count;
    }

    final small = await statementsFor(1);
    final large = await statementsFor(60);

    expect(small, 1);
    expect(large, small);
    expect(TagCatalog.all.first.tag, 'shared');
    expect(TagCatalog.all.first.noteCount, 61);
  });

  test('refreshes asked for while one reads cost one more read between '
      'them, and publish the table as it is afterwards', () async {
    await note('A', '#squat');
    final gone = await note('B', '#squat #bench');
    await drain();
    final service = await TagCatalogService.forTesting(db);
    await db.noteDao.softDeleteNote(gone.id);
    await pumpEventQueue();
    statements.reset();

    await Future.wait([for (var i = 0; i < 5; i++) service.refresh()]);

    expect(statements.executions(NoteSearchDao.catalogTagsSql), 2);
    expect(published(), [('squat', 1)]);

    statements.reset();
    await service.refresh();
    expect(
      statements.executions(NoteSearchDao.catalogTagsSql),
      1,
      reason: 'a refresh after the last one ended reads again',
    );
  });

  test('a switch during a read with another asked for reads no more from '
      'the closing database', () async {
    await note('A', '#squat');
    await drain();
    final service = await TagCatalogService.forTesting(db);
    await pumpEventQueue();
    statements.reset();
    final held = Completer<void>();
    statements.onStatement = (sql, _) =>
        sql.contains(NoteSearchDao.catalogTagsSql) ? held.future : null;

    final first = service.refresh();
    final second = service.refresh();
    await pumpEventQueue();
    TagCatalogService.reset();
    statements.onStatement = null;
    held.complete();
    await Future.wait([first, second]);

    expect(statements.executions(NoteSearchDao.catalogTagsSql), 1);
    expect(TagCatalog.all, isEmpty);
  });

  test('a partner\'s notes leaving take their tags from the catalog, with '
      'no drain', () async {
    await note('Mine', '#squat');
    final theirs = await db.folderDao.createFolder(name: 'Theirs');
    final shared = await db.noteDao.createNote(
      folderId: theirs.id,
      title: 'Theirs',
      content: '#secretpartner #squat',
    );
    await drain();
    await db.customStatement('UPDATE folders SET owner_id = ? WHERE id = ?', [
      'partner',
      theirs.id,
    ]);
    await db.customStatement('UPDATE notes SET owner_id = ? WHERE id = ?', [
      'partner',
      shared.id,
    ]);
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
    await TagCatalogService.forTesting(db);
    expect(published(), [('squat', 2), ('secretpartner', 1)]);

    await db.sharedRowDao.removeAll();
    await pumpEventQueue();

    expect(published(), [('squat', 1)]);
  });

  test('a partner\'s tombstone merged takes its note\'s tags from the '
      'catalog, with no drain', () async {
    await note('Mine', '#squat');
    final theirs = await db.folderDao.createFolder(name: 'Theirs');
    final shared = await db.noteDao.createNote(
      folderId: theirs.id,
      title: 'Theirs',
      content: '#secretpartner #squat',
    );
    await drain();
    await db.customStatement('UPDATE notes SET owner_id = ? WHERE id = ?', [
      'partner',
      shared.id,
    ]);
    await TagCatalogService.forTesting(db);
    expect(published(), [('squat', 2), ('secretpartner', 1)]);

    final local = (await db.noteDao.getNoteById(shared.id))!;
    final stamp = HlcTimestamp.parse(local.hlcTimestamp);
    await db.noteDao.mergeNoteDocument(
      local.copyWith(
        isDeleted: true,
        deletedAt: Value(DateTime.now()),
        hlcTimestamp: HlcTimestamp(
          wallTime: stamp.wallTime + 1000,
          logicalCounter: 0,
          nodeId: 'partner-device',
        ).toString(),
        version: local.version + 1,
      ),
      null,
      floor: CrdtMerge.everyStamp,
      shared: true,
    );
    await pumpEventQueue();

    expect(published(), [('squat', 1)]);
  });

  test('a ledger row whose rowid another note now holds lends that note no '
      'tags', () async {
    final secret = await note('Secret', '#secret');
    final other = await note('Other', 'plain');
    await drain();
    final dao = NoteSearchDao(db);
    expect(await dao.catalogTags(), ['secret']);
    final rowid =
        (await db
                .customSelect(
                  'SELECT rowid AS r FROM notes WHERE id = ?',
                  variables: [Variable<String>(secret.id)],
                )
                .getSingle())
            .read<int>('r');

    // What a `VACUUM` may do to a table without an INTEGER PRIMARY KEY.
    await db.customStatement('UPDATE notes SET rowid = -1 WHERE id = ?', [
      secret.id,
    ]);
    await db.customStatement('UPDATE notes SET rowid = ? WHERE id = ?', [
      rowid,
      other.id,
    ]);

    expect(await dao.catalogTags(), isEmpty);
  });

  test('the read walks the ledger and probes each note by rowid', () async {
    final plan = await queryPlan(db, NoteSearchDao.catalogTagsSql);

    expect(plan, contains(contains('SCAN l')));
    expect(
      plan,
      contains(contains('SEARCH n USING INTEGER PRIMARY KEY (rowid=?)')),
    );
    expect(plan, isNot(contains(contains('SCAN n'))));
  });
}
