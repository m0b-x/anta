import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/note_search_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';

import '../services/support/body_index_support.dart';
import 'support/db_test_support.dart';

Future<void> _noWait() async {}

bool _neverBusy() => false;

Future<R> _inline<R>(R Function() work) async => work();

/// v56 → v57: the ledger gains each note's tags as a nullable column, NULL
/// for "not read yet", and the drain fills it from the bodies alone — no
/// note goes stale and the FTS table is never rewritten for it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StatementCounter statements;
  late Folder folder;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    folder = await db.folderDao.createFolder(name: 'Log');
  });
  tearDown(() async => db.close());

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

  Future<void> upgrade(int from, [int? to]) async {
    await db.customStatement('PRAGMA user_version = $from');
    await DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      from,
      to ?? DatabaseSchema.currentVersion,
    );
  }

  /// A v56 ledger: the column a fresh install has, taken away again.
  Future<void> toV56() =>
      db.customStatement('ALTER TABLE note_search_ledger DROP COLUMN tags');

  Future<int> one(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.single as int;

  Future<Map<String, ({String hlc, String? tags})>> ledger() async {
    final rows = await db
        .customSelect(
          'SELECT note_id, indexed_hlc, tags FROM note_search_ledger',
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('note_id'): (
          hlc: row.read<String>('indexed_hlc'),
          tags: row.read<String?>('tags'),
        ),
    };
  }

  Future<String> hlcOf(String id) async =>
      (await db.noteDao.getNoteById(id))!.hlcTimestamp;

  Future<List<String>> pragmaColumns(AppDatabase on) async {
    final rows = await on
        .customSelect('PRAGMA table_info(note_search_ledger)')
        .get();
    return [
      for (final row in rows)
        '${row.read<String>('name')} ${row.read<String>('type')} '
            'notnull=${row.read<int>('notnull')} '
            'default=${row.read<String?>('dflt_value')} '
            'pk=${row.read<int>('pk')}',
    ];
  }

  Future<List<String>> squatHits() async => [
    for (final hit in await NoteSearchDao(
      db,
    ).quickMatching(bodyMatchExpression({'squat'}), limit: 50))
      hit.note.id,
  ];

  test('the step leaves every row current with its tags unread, and the '
      'drain fills them a page at a time without touching the FTS '
      'table', () async {
    final legs = await note('Legs', 'squat #LegDay and #legday #Cardio');
    final plain = await note('Plain', 'squat');
    final broken = await note('Broken', 'squat #hidden');
    for (var i = 0; i < 8; i++) {
      await note('Session $i', 'squat set $i #set$i');
    }
    await db.customUpdate(
      "UPDATE content_chunks SET is_compressed = 1, content = 'not base64!' "
      'WHERE note_id = ?',
      variables: [Variable<String>(broken.id)],
    );
    await drain();
    await toV56();

    await upgrade(DatabaseSchema.v56CategorySharedPair);

    final upgraded = await ledger();
    expect(upgraded, hasLength(11));
    for (final MapEntry(key: id, value: row) in upgraded.entries) {
      expect(row.tags, isNull);
      expect(row.hlc, await hlcOf(id), reason: 'no note is made stale');
    }
    final dao = NoteSearchDao(db);
    expect(
      await dao.hasPendingWork(),
      isFalse,
      reason: 'the index is current: no search waits on the tags',
    );
    expect(await dao.untaggedNotes(), hasLength(11), reason: 'the drain\'s');
    final before = await squatHits();
    expect(before, hasLength(10), reason: 'the broken body is not indexed');
    final ftsRows = await one('SELECT COUNT(*) FROM note_body_fts');
    final ftsBytes = await one(
      'SELECT SUM(length(block)) FROM note_body_fts_data',
    );
    final pages = await one('PRAGMA page_count');

    final during = <List<String>>[];
    final heard = <void>[];
    final subscription = BodySearchIndexer.changes.listen(heard.add);
    addTearDown(subscription.cancel);
    statements.reset();
    await BodySearchIndexer(
      database: db,
      pageBytes: 1,
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: () async => during.add(await squatHits()),
        editorBusy: _neverBusy,
        editorPoll: _noWait,
        run: _inline,
      ),
    ).drain();
    await pumpEventQueue();

    // Every drain's orphan sweep aside, which found none to delete.
    expect(
      statements.statements.where(
        (sql) =>
            sql.contains('note_body_fts') &&
            !sql.contains(NoteSearchDao.orphanRowids) &&
            (sql.startsWith('INSERT') || sql.startsWith('DELETE')),
      ),
      isEmpty,
    );
    expect(statements.executions('UPDATE note_search_ledger SET tags'), 11);
    expect(heard, hasLength(11), reason: 'one page a note, each announced');
    expect(await one('SELECT COUNT(*) FROM note_body_fts'), ftsRows);
    expect(
      await one('SELECT SUM(length(block)) FROM note_body_fts_data'),
      ftsBytes,
    );
    expect(await one('PRAGMA page_count'), pages);
    expect(during, hasLength(11));
    for (final hits in during) {
      expect(hits, unorderedEquals(before));
    }
    expect(await squatHits(), unorderedEquals(before));

    final filled = await ledger();
    expect(filled.values.where((row) => row.tags == null), isEmpty);
    expect(filled[legs.id]!.tags, 'LegDay Cardio');
    expect(filled[plain.id]!.tags, '');
    expect(filled[broken.id]!.tags, '', reason: 'an unreadable body');
    expect(await dao.hasPendingWork(), isFalse);
  });

  test('a note edited between the read and the write keeps NULL and gets '
      'its tags from its projection', () async {
    final legs = await note('Legs', '#squat');
    await drain();
    await toV56();
    await upgrade(DatabaseSchema.v56CategorySharedPair);
    final dao = NoteSearchDao(db);
    final read = (await dao.untaggedNotes()).single;

    await db.noteDao.updateNote(
      id: legs.id,
      contentLength: 6,
      content: '#bench',
    );
    final written = await dao.writeTags([
      (rowid: read.rowid, id: read.id, hlc: read.hlc, tags: 'squat'),
    ]);

    expect(written, 0);
    expect((await ledger())[legs.id]!.tags, isNull);
    expect(
      await dao.untaggedNotes(),
      isEmpty,
      reason: 'stale as well: the projection\'s, not the backfill\'s',
    );

    await drain();
    expect((await ledger())[legs.id]!.tags, 'bench');
  });

  test('the backfill resumes after an interrupted drain', () async {
    for (var i = 0; i < 4; i++) {
      await note('Session $i', '#set$i');
    }
    await drain();
    await toV56();
    await upgrade(DatabaseSchema.v56CategorySharedPair);

    late BodySearchIndexer cut;
    cut = BodySearchIndexer(
      database: db,
      pageBytes: 1,
      scheduler: BodyIndexScheduler(
        yieldBetweenPages: () async => cut.close(),
        editorBusy: _neverBusy,
        editorPoll: _noWait,
        run: _inline,
      ),
    );
    await cut.drain();

    Future<int> unread() =>
        one('SELECT COUNT(*) FROM note_search_ledger WHERE tags IS NULL');
    expect(await unread(), 3, reason: 'one page landed before the cut');
    expect(await NoteSearchDao(db).untaggedNotes(), hasLength(3));

    await drain();

    expect(await unread(), 0);
  });

  test('the step run again changes nothing', () async {
    await note('Legs', 'squat #LegDay');
    await drain();
    await toV56();
    await upgrade(DatabaseSchema.v56CategorySharedPair);
    await drain();
    final settled = await ledger();
    expect(settled.values.single.tags, 'LegDay');

    await upgrade(DatabaseSchema.v56CategorySharedPair);

    expect(await ledger(), settled);
    expect(await NoteSearchDao(db).hasPendingWork(), isFalse);
  });

  test('a database with no ledger gets one in the fresh install\'s shape, '
      'and opens', () async {
    final fresh = await openTestDatabase();
    addTearDown(fresh.close);
    await db.customStatement('DROP TABLE note_search_ledger');

    await upgrade(DatabaseSchema.v56CategorySharedPair);

    expect(await pragmaColumns(db), await pragmaColumns(fresh));
    await note('Legs', '#squat');
    await drain();
    expect((await ledger()).values.single.tags, 'squat');
  });

  test('v50 spells the ledger as it stood: four columns, v57 adds the '
      'fifth', () async {
    await db.customStatement('DROP TABLE note_search_ledger');
    await db.customStatement('DROP TABLE note_body_fts');

    await upgrade(
      DatabaseSchema.v49Counters,
      DatabaseSchema.v50QuickSearchIndex,
    );

    expect(
      [for (final column in await pragmaColumns(db)) column.split(' ').first],
      ['note_rowid', 'note_id', 'indexed_hlc', 'fingerprint'],
    );

    await upgrade(DatabaseSchema.v50QuickSearchIndex);
    final fresh = await openTestDatabase();
    addTearDown(fresh.close);
    expect(await pragmaColumns(db), await pragmaColumns(fresh));
  });

  test('a fresh install\'s ledger carries the column as the step adds it: '
      'nullable, no default', () async {
    expect(
      (await pragmaColumns(db)).last,
      'tags TEXT notnull=0 default=null pk=0',
    );
  });
}
