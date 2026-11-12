import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/loading_interceptor.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/utils/compression_utils.dart';

import '../support/scale_fixtures.dart';
import 'support/db_test_support.dart';

const _oldestColumns = {
  'folders': {
    'id',
    'name',
    'parent_id',
    'created_at',
    'updated_at',
    'hlc_timestamp',
    'device_id',
    'version',
    'is_deleted',
    'deleted_at',
  },
  'notes': {
    'id',
    'folder_id',
    'title',
    'preview',
    'content_length',
    'chunk_count',
    'is_compressed',
    'created_at',
    'updated_at',
    'hlc_timestamp',
    'device_id',
    'version',
    'is_deleted',
    'deleted_at',
  },
  'content_chunks': {
    'id',
    'note_id',
    'chunk_index',
    'content',
    'is_compressed',
    'hlc_timestamp',
    'device_id',
    'version',
  },
  'sync_metadata': {'key', 'value', 'updated_at'},
};

/// `idx_folders_parent`, `idx_notes_folder` and `idx_chunks_note_index` left
/// this set in v47, which drops them on both paths.
const _indexesOlderThanTheChain = {
  'idx_folders_hlc',
  'idx_notes_hlc',
  'idx_notes_updated',
};

/// The legacy title-and-preview index as fresh installs created it until
/// v50 retired it.
const _legacyNotesFts =
    'CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(title, preview, '
    'content=notes, content_rowid=rowid)';

Future<Set<String>> _columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

/// Every trigger with the statement that made it — the fences v54 adds
/// (`SharedRowFences`), which a fresh install and an upgraded one must hold
/// alike.
Future<Map<String, String>> _triggerSql(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('name'): (row.read<String?>('sql') ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('IF NOT EXISTS ', ''),
  };
}

Future<void> _reshapeToOldest(AppDatabase db) async {
  // First: a trigger names columns the oldest shape lacks, and SQLite
  // refuses to drop a column a trigger names.
  for (final name in (await _triggerSql(db)).keys) {
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }
  for (final name in await indexNames(db)) {
    await db.customStatement('DROP INDEX IF EXISTS $name');
  }
  for (final table in await tableNames(db)) {
    if (_oldestColumns.containsKey(table)) continue;
    await db.customStatement('DROP TABLE IF EXISTS $table');
  }
  for (final entry in _oldestColumns.entries) {
    final later = (await _columnNames(db, entry.key)).difference(entry.value);
    for (final column in later) {
      await db.customStatement('ALTER TABLE ${entry.key} DROP COLUMN $column');
    }
    expect(
      await _columnNames(db, entry.key),
      entry.value,
      reason: '${entry.key} could not be taken back to its oldest shape',
    );
  }
  // Every install before v50 held the title-and-preview table, which v50
  // drops; the chain must carry it that far.
  await db.customStatement(_legacyNotesFts);
  await db.customStatement('PRAGMA user_version = 1');
}

Future<void> _upgrade(AppDatabase db, int from, [int? to]) {
  return DatabaseMigrations(db).runMigrations(
    db.createMigrator(),
    from,
    to ?? DatabaseSchema.currentVersion,
  );
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<Map<String, Set<String>>> _columns(AppDatabase db) async {
  final result = <String, Set<String>>{};
  for (final table in await tableNames(db)) {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    result[table] = {
      for (final row in rows)
        '${row.read<String>('name')} ${row.read<String>('type')} '
            'notnull=${row.read<int>('notnull')} '
            'default=${row.read<String?>('dflt_value')} '
            'pk=${row.read<int>('pk')}',
    };
  }
  return result;
}

Future<Map<String, String>> _indexSql(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
        "AND name NOT LIKE 'sqlite_autoindex_%'",
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('name'): (row.read<String?>('sql') ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('IF NOT EXISTS ', ''),
  };
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('every step runs on the shape the steps before it leave behind', () async {
    await _reshapeToOldest(db);

    final failures = <String>[];
    for (var v = 1; v < DatabaseSchema.currentVersion; v++) {
      try {
        await _upgrade(db, v, v + 1);
      } catch (e) {
        failures.add('v$v -> v${v + 1}: ${e.toString().split('\n').first}');
      }
    }

    expect(
      failures,
      isEmpty,
      reason:
          'A step named a column, table or index shape that only a LATER step '
          'creates. The usual cause is a step calling a shared, live definition '
          '(a DatabaseIndexes helper, m.createTable, a DAO) that has since been '
          'widened. Freeze that step at the shape it shipped with.',
    );
    expect(await _userVersion(db), DatabaseSchema.currentVersion);
  });

  test(
    'a database upgraded from the oldest shape matches a fresh install',
    () async {
      await _reshapeToOldest(db);
      await _upgrade(db, 1);
      final fresh = await openTestDatabase();
      addTearDown(fresh.close);

      expect(await _columns(db), await _columns(fresh));

      final upgraded = await _indexSql(db);
      final created = await _indexSql(fresh);
      for (final entry in upgraded.entries) {
        expect(entry.value, created[entry.key], reason: entry.key);
      }
      expect(
        created.keys.toSet().difference(upgraded.keys.toSet()),
        _indexesOlderThanTheChain,
        reason:
            'An index a fresh install gets is created by no migration step, so '
            'upgraders never receive it.',
      );

      final fences = await _triggerSql(fresh);
      expect(fences, isNotEmpty);
      expect(
        await _triggerSql(db),
        fences,
        reason:
            'A trigger exists on one path only: an upgraded database and a '
            'fresh one would keep shared rows differently.',
      );
    },
  );

  test(
    'v30 and older upgrade past the absences index that gained status in v37',
    () async {
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_calendar_event_absences_active',
      );
      await db.customStatement(
        'ALTER TABLE calendar_event_absences DROP COLUMN status',
      );
      await db.customStatement(
        'INSERT INTO calendar_event_absences '
        '(event_id, day, created_at, updated_at, hlc_timestamp, device_id) '
        "VALUES ('e1', 1, 1, 1, 'h', 'd')",
      );

      await _upgrade(db, DatabaseSchema.v30EventSkips);

      final sql = (await _indexSql(db))['idx_calendar_event_absences_active'];
      expect(sql, contains('(event_id, day, status)'));
      final row = await db
          .customSelect('SELECT status FROM calendar_event_absences')
          .getSingle();
      expect(row.read<String>('status'), 'missed');
    },
  );

  test(
    'v9 and older upgrade past the start-date index that became partial in v27',
    () async {
      await _reshapeToOldest(db);
      await _upgrade(db, 1, DatabaseSchema.v9NameUniquenessIndexes);

      await _upgrade(db, DatabaseSchema.v9NameUniquenessIndexes);

      final sql = (await _indexSql(db))['idx_calendar_events_start_date'];
      expect(sql, contains('WHERE is_deleted = 0'));
    },
  );

  // v41 is a brand-new table, so a v40 database is a fresh one without it.
  // The re-run is what makes `IF NOT EXISTS` load-bearing: a partial upgrade
  // replays the step over a table that already holds a view.
  test(
    'v40 upgrades to v41 with overview_views, and a re-run keeps its rows',
    () async {
      await db.customStatement('DROP TABLE overview_views');
      expect(await tableNames(db), isNot(contains('overview_views')));

      await _upgrade(
        db,
        DatabaseSchema.v40EventAlerts,
        DatabaseSchema.v41OverviewViews,
      );

      expect(await tableNames(db), contains('overview_views'));
      expect(await _userVersion(db), DatabaseSchema.v41OverviewViews);

      await db.overviewViewDao.upsertView(
        const OverviewViewsCompanion(
          id: Value('v1'),
          name: Value('Q1 gym'),
          payload: Value('{}'),
        ),
      );
      await _upgrade(db, DatabaseSchema.v40EventAlerts);

      expect(await db.overviewViewDao.getAll(), hasLength(1));
    },
  );

  test('a v30 database file opens through the real upgrade path', () async {
    final dir = await Directory.systemTemp.createTemp('upgrade_chain_test');
    addTearDown(() => dir.delete(recursive: true));
    AppDatabase open() => AppDatabase.forTesting(
      LazyDatabase(
        () async => NativeDatabase.createInBackground(
          File('${dir.path}/app.sqlite'),
          setup: configureSqliteConnection,
        ).interceptWith(LoadingQueryInterceptor()),
      ),
    );

    final old = open();
    await old.customSelect('SELECT 1').get();
    await old.customStatement(
      'DROP INDEX IF EXISTS idx_calendar_event_absences_active',
    );
    await old.customStatement(
      'ALTER TABLE calendar_event_absences DROP COLUMN status',
    );
    await old.customStatement('PRAGMA user_version = 30');
    await old.close();

    final reopened = open();
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').get();

    expect(await _userVersion(reopened), DatabaseSchema.currentVersion);
    expect(
      (await _indexSql(reopened))['idx_calendar_event_absences_active'],
      contains('(event_id, day, status)'),
    );
  });

  // v46 adds the chunk hash and leaves every stored body alone: a legacy
  // note reads as before and is re-cut on its next body save, without a
  // stamp when the text is the same.
  test('a v45 note in fixed slices upgrades, reads the same and is re-cut '
      'on its next save', () async {
    final folder = await db.folderDao.createFolder(name: 'Log');
    final note = await db.noteDao.createNote(folderId: folder.id, title: 'A');
    await db.customStatement('DROP INDEX idx_content_chunks_hash');
    await db.customStatement(
      'ALTER TABLE content_chunks DROP COLUMN content_hash',
    );
    final text = bigBody(25000);
    var start = 0;
    for (var i = 0; start < text.length; i++) {
      var end = start + 10000 > text.length ? text.length : start + 10000;
      final last = text.codeUnitAt(end - 1);
      if (end < text.length && last >= 0xD800 && last <= 0xDBFF) end--;
      final slice = text.substring(start, end);
      start = end;
      await db.customStatement(
        'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
        'is_compressed, hlc_timestamp, device_id) VALUES (?, ?, ?, ?, 1, ?, ?)',
        [
          '${note.id}_chunk_$i',
          note.id,
          i,
          CompressionUtils.compressToBase64(slice),
          note.hlcTimestamp,
          note.deviceId,
        ],
      );
    }

    await _upgrade(db, DatabaseSchema.v45OneOffSkipSweep);
    await _upgrade(db, DatabaseSchema.v45OneOffSkipSweep);

    expect(await _columnNames(db, 'content_chunks'), contains('content_hash'));
    expect(
      (await _indexSql(db))['idx_content_chunks_hash'],
      contains('content_chunks(content_hash)'),
    );
    expect(await db.contentChunkDao.loadContent(note.id), text);

    final stored = await db.noteDao.updateNote(
      id: note.id,
      contentLength: 0,
      content: text,
    );
    expect(stored!.hlcTimestamp, note.hlcTimestamp);
    expect(stored.version, note.version);
    final chunks = await db.contentChunkDao.getChunksForNote(note.id);
    expect(chunks.every((c) => c.contentHash != null), isTrue);
    expect(chunks.any((c) => c.id.startsWith('${note.id}_chunk_')), isFalse);
    expect(stored.chunkCount, chunks.length);
    expect(await db.contentChunkDao.loadContent(note.id), text);

    final edited = await db.noteDao.updateNote(
      id: note.id,
      content: '${text}x',
    );
    expect(edited!.hlcTimestamp, isNot(note.hlcTimestamp));
    expect(await db.contentChunkDao.loadContent(note.id), '${text}x');
  });

  // v47 purges the bodies every earlier build kept for deleted notes: the
  // chunks of tombstoned and of missing notes, then stray tombstoned chunks
  // of live notes. A live note's body is left as it was.
  test('a v46 database with dead bodies upgrades to live notes\' chunks '
      'alone, on the create path\'s indices', () async {
    final folder = await db.folderDao.createFolder(name: 'Log');
    final live = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Live',
      content: bigBody(30000),
    );
    final dead = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Dead',
      content: bigBody(20000),
    );
    final fresh = await openTestDatabase();
    addTearDown(fresh.close);
    final created = await _indexSql(fresh);

    // The v46 shape and what v46 left: tombstoned chunks under a
    // tombstoned note, a chunk whose note is gone, a stray tombstoned chunk
    // under the live note.
    await db.customStatement('DROP INDEX idx_content_chunks_note');
    await db.customStatement('DROP INDEX idx_sync_outbox_order');
    await db.customStatement(
      'CREATE INDEX idx_chunks_note_index ON content_chunks(note_id, '
      'chunk_index) WHERE is_deleted = 0',
    );
    await db.customStatement(
      'CREATE INDEX idx_notes_folder ON notes(folder_id) WHERE is_deleted = 0',
    );
    await db.customStatement(
      'CREATE INDEX idx_folders_parent ON folders(parent_id) '
      'WHERE is_deleted = 0',
    );
    await db.customStatement(
      "UPDATE notes SET is_deleted = 1 WHERE id = '${dead.id}'",
    );
    await db.customStatement(
      "UPDATE content_chunks SET is_deleted = 1 WHERE note_id = '${dead.id}'",
    );
    Future<void> insertChunk(String id, String noteId, int index, int deleted) {
      return db.customStatement(
        'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
        'is_compressed, hlc_timestamp, device_id, is_deleted) '
        "VALUES (?, ?, ?, 'x', 0, 'h', 'd', ?)",
        [id, noteId, index, deleted],
      );
    }

    await insertChunk('orphan', 'gone', 0, 0);
    await insertChunk('stray', live.id, 99, 1);
    final liveRows = await db.contentChunkDao.getChunksForNote(live.id);
    await db.customStatement('PRAGMA user_version = 46');

    await _upgrade(db, DatabaseSchema.v46ContentChunkHashes);
    await _upgrade(db, DatabaseSchema.v46ContentChunkHashes);

    final remaining = await db
        .customSelect('SELECT id FROM content_chunks')
        .get();
    expect(
      {for (final row in remaining) row.read<String>('id')},
      {for (final chunk in liveRows) chunk.id},
    );
    expect(await db.contentChunkDao.loadContent(live.id), bigBody(30000));
    expect(await _userVersion(db), DatabaseSchema.currentVersion);
    expect(await _indexSql(db), created);
  });

  // v48 adds the body search index empty and reads no body: the indexer
  // fills it after launch. Twice, because a step must be idempotent.
  test(
    'a v47 database gains an empty body index and keeps its notes',
    () async {
      final folder = await db.folderDao.createFolder(name: 'Log');
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'A',
        content: 'squat',
      );
      await db.customStatement('DROP TABLE note_body_fts');
      await db.customStatement('DROP TABLE note_search_ledger');

      await _upgrade(db, DatabaseSchema.v47StorageHygiene);
      await _upgrade(db, DatabaseSchema.v47StorageHygiene);

      expect(
        await tableNames(db),
        containsAll(<String>['note_body_fts', 'note_search_ledger']),
      );
      final ledger = await db
          .customSelect('SELECT COUNT(*) AS c FROM note_search_ledger')
          .getSingle();
      expect(ledger.read<int>('c'), 0);
      expect(await db.contentChunkDao.loadContent(note.id), 'squat');
    },
  );

  // v50 drops the title-and-preview table and recreates the body index with
  // the quick search's columns, clearing the ledger so every note is
  // projected again lazily. Twice, because a step must be idempotent — and
  // the second run must not clear a ledger the first one already rebuilt.
  test('a v49 database loses notes_fts and re-projects lazily', () async {
    final folder = await db.folderDao.createFolder(name: 'Log');
    final note = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'A',
      content: 'squat',
    );
    await db.customStatement(_legacyNotesFts);
    await db.customStatement('DROP TABLE note_body_fts');
    await db.customStatement(
      'CREATE VIRTUAL TABLE note_body_fts USING fts5(body, '
      "tokenize='trigram case_sensitive 1', content='', "
      'contentless_delete=1)',
    );
    await db.customStatement(
      'INSERT INTO note_search_ledger (note_rowid, note_id, indexed_hlc, '
      "fingerprint) SELECT rowid, id, hlc_timestamp, 'f' FROM notes",
    );
    Future<int> ledgerRows() async =>
        (await db
                .customSelect('SELECT COUNT(*) AS c FROM note_search_ledger')
                .getSingle())
            .read<int>('c');

    await _upgrade(db, DatabaseSchema.v49Counters);

    expect(await tableNames(db), isNot(contains('notes_fts')));
    expect(await _columnNames(db, 'note_body_fts'), {'title', 'body', 'tags'});
    expect(await ledgerRows(), 0);

    await db.customStatement(
      'INSERT INTO note_search_ledger (note_rowid, note_id, indexed_hlc, '
      "fingerprint) SELECT rowid, id, hlc_timestamp, 'f' FROM notes",
    );
    await _upgrade(db, DatabaseSchema.v49Counters);

    expect(await ledgerRows(), 1);
    expect(await db.contentChunkDao.loadContent(note.id), 'squat');
    expect(await _userVersion(db), DatabaseSchema.currentVersion);
  });

  // v51 adds `sync_outbox.republish`; an entry queued before it reads as a
  // real edit, as every entry did. Twice, because a step must be idempotent.
  test(
    'a v50 outbox gains republish and keeps its entries as real edits',
    () async {
      await db.customStatement('ALTER TABLE sync_outbox DROP COLUMN republish');
      await db.customStatement(
        'INSERT INTO sync_outbox (table_name, row_key, hlc, op, enqueued_at) '
        "VALUES ('notes', 'n1', 'h', 'upsert', 1)",
      );

      await _upgrade(db, DatabaseSchema.v50QuickSearchIndex);
      await _upgrade(db, DatabaseSchema.v50QuickSearchIndex);

      final entry = await db
          .customSelect('SELECT row_key, republish FROM sync_outbox')
          .getSingle();
      expect(entry.read<String>('row_key'), 'n1');
      expect(entry.read<int>('republish'), 0);
      expect(await _userVersion(db), DatabaseSchema.currentVersion);
    },
  );

  test('a fresh install has no notes_fts', () async {
    final names = await tableNames(db);
    expect(names.where((name) => name.startsWith('notes_fts')), isEmpty);
    expect(await _columnNames(db, 'note_body_fts'), {'title', 'body', 'tags'});
  });

  group('a half-finished upgrade', () {
    test(
      'a failing step rolls back whole and leaves the version where it was',
      () async {
        await db.customStatement(
          'DROP INDEX IF EXISTS idx_calendar_event_skips_active',
        );
        await db.customStatement('DROP TABLE calendar_event_absences');
        await db.customStatement('PRAGMA user_version = 30');

        await expectLater(
          _upgrade(db, DatabaseSchema.v30EventSkips),
          throwsA(anything),
        );

        expect(
          await indexNames(db),
          isNot(contains('idx_calendar_event_skips_active')),
          reason: 'the first statement of the failed step must not survive it',
        );
        expect(await _userVersion(db), 30);
      },
    );

    test('each finished step stamps its own version', () async {
      await db.customStatement('PRAGMA user_version = 30');

      await _upgrade(
        db,
        DatabaseSchema.v30EventSkips,
        DatabaseSchema.v33CategoryHidden,
      );

      expect(await _userVersion(db), DatabaseSchema.v33CategoryHidden);
    });

    test(
      'running the whole chain again over an upgraded database is harmless',
      () async {
        await _reshapeToOldest(db);
        await db.customStatement(
          'INSERT INTO folders '
          '(id, name, created_at, updated_at, hlc_timestamp, device_id) '
          "VALUES ('f1', 'First', 1, 1, 'h', 'd'), ('f2', 'Second', 2, 2, 'h', 'd')",
        );
        await _upgrade(db, 1);
        await db.customStatement(
          "UPDATE folders SET position = 7 WHERE id = 'f1'",
        );

        await _upgrade(db, 1);

        final folder = await db
            .customSelect("SELECT position FROM folders WHERE id = 'f1'")
            .getSingle();
        expect(
          folder.read<int>('position'),
          7,
          reason:
              'v4 seeds positions once; a re-run must not undo a manual order',
        );
      },
    );

    test(
      'the priority flip is applied once, however often its step runs',
      () async {
        await _reshapeToOldest(db);
        await _upgrade(db, 1, DatabaseSchema.v17PublicHolidaySuppressed);
        await db.customStatement(
          'INSERT INTO calendar_events '
          '(id, title, category, start_date, rule_kind, created_at, updated_at, priority) '
          "VALUES ('e1', 'Leg day', 'gym', 1, 'oneTime', 1, 1, 5)",
        );

        await _upgrade(db, DatabaseSchema.v17PublicHolidaySuppressed);
        await _upgrade(db, DatabaseSchema.v17PublicHolidaySuppressed);

        final event = await db
            .customSelect(
              "SELECT priority FROM calendar_events WHERE id = 'e1'",
            )
            .getSingle();
        expect(event.read<int>('priority'), 1);
      },
    );
  });
}
