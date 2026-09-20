import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/loading_interceptor.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

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

const _indexesOlderThanTheChain = {
  'idx_folders_parent',
  'idx_folders_hlc',
  'idx_notes_folder',
  'idx_notes_hlc',
  'idx_notes_updated',
  'idx_chunks_note_index',
};

Future<Set<String>> _columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<void> _reshapeToOldest(AppDatabase db) async {
  for (final name in await indexNames(db)) {
    await db.customStatement('DROP INDEX IF EXISTS $name');
  }
  for (final table in await tableNames(db)) {
    if (_oldestColumns.containsKey(table) || table.startsWith('notes_fts')) {
      continue;
    }
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
    if (table.startsWith('notes_fts')) continue;
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
