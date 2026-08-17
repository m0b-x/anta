import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards the invariant that the **create path and the migration path agree**.
///
/// This is not hypothetical. `idx_folders_position` / `idx_notes_position`
/// were introduced inside the v3→v4 migration and never added to
/// `DatabaseIndexes.createAllIndexes`, so for years they existed only on
/// databases that had *upgraded* through v4. Every fresh install — a new user,
/// or any database added through the multi-database feature — ran the folder
/// content page's primary query (`ORDER BY position`) as a scan-and-sort. It
/// was invisible until a folder grew large. This test fails on that.
///
/// The declared set is scraped from the source rather than hardcoded, so a
/// hand-maintained golden list can't rot: adding an index anywhere under
/// `lib/database/` immediately obliges the create path to produce it.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('every index declared in lib/database is created on a fresh install', () async {
    final declared = _declaredNames(
      RegExp(r'CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+([a-z_0-9]+)'),
    );
    // Sanity: the scrape itself must not silently match nothing.
    expect(declared, isNotEmpty, reason: 'index scrape found nothing');

    final actual = await indexNames(db);
    expect(
      declared.difference(actual),
      isEmpty,
      reason:
          'These indexes exist somewhere in lib/database but a freshly created '
          'database does not have them. An index reachable only from a '
          'migration leaves every fresh install slower than an upgraded one. '
          'Add it to DatabaseIndexes.createAllIndexes().',
    );
  });

  test('every table declared in lib/database is created on a fresh install', () async {
    final declared = _declaredNames(
      RegExp(
        r'CREATE\s+(?:VIRTUAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+([a-z_0-9]+)',
      ),
    );
    expect(declared, isNotEmpty, reason: 'table scrape found nothing');

    final actual = await tableNames(db);
    expect(
      declared.difference(actual),
      isEmpty,
      reason:
          'A table created by a migration is missing from the fresh-create '
          'path. Add it to the @DriftDatabase tables list.',
    );
  });

  test('the occurrence table matches its frozen migration DDL', () async {
    // The migration writes raw DDL frozen at v24 rather than using
    // `m.createTable`, precisely so upgraders and fresh installs cannot drift.
    // That only pays off if something checks it. v28 grew the CRDT block onto
    // it by ALTER, which is the same agreement under more pressure.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_occurrences)')
        .get();
    final byName = {
      for (final row in columns) row.read<String>('name'): row,
    };

    expect(byName.keys.toSet(), {
      'event_id',
      'day',
      'description',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });
    for (final name in byName.keys) {
      // `deleted_at` is the single nullable column — the one place the blanket
      // loop does not apply. `ContentChunks` skips it entirely, which is
      // exactly the variant this table must not become.
      expect(
        byName[name]!.read<int>('notnull'),
        name == 'deleted_at' ? 0 : 1,
        reason: name == 'deleted_at'
            ? 'deleted_at must stay nullable'
            : '$name should be NOT NULL',
      );
    }
    expect(byName['event_id']!.read<String>('type'), 'TEXT');
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    // Non-nullable: the row's existence is the override, and `''` is a
    // meaningful value — a reset tombstones instead of blanking.
    expect(byName['description']!.read<String>('type'), 'TEXT');
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    // The `calendar_events` variant, not the absence table's: v28 added these
    // to a *populated* table, so `ALTER TABLE … ADD COLUMN NOT NULL` demanded a
    // default and the Drift declaration had to grow the same one. `''` is
    // transitional — the migration backfills it in the same run.
    expect(byName['hlc_timestamp']!.read<String>('dflt_value'), "''");
    expect(byName['device_id']!.read<String>('dflt_value'), "''");
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    // Composite primary key, in order — this is what gives the point lookup
    // and the per-event cascade an index without declaring one.
    expect(byName['event_id']!.read<int>('pk'), 1);
    expect(byName['day']!.read<int>('pk'), 2);
  });

  test('the absence table matches its frozen migration DDL', () async {
    // Frozen at v26 for the same reason as the occurrence table, but this one
    // also carries the five CRDT columns — the first frozen-DDL table in the
    // codebase to do so (notes/folders are v1 `createAll`-only). Their exact
    // shape is what cloud-sync phase-02 wires transport to, so a drift here is
    // a schema retrofit later.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_absences)')
        .get();
    final byName = {
      for (final row in columns) row.read<String>('name'): row,
    };

    expect(byName.keys.toSet(), {
      'event_id',
      'day',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });
    for (final name in byName.keys) {
      // `deleted_at` is the single nullable column — the one place the
      // blanket loop above does not apply. `ContentChunks` skips it entirely,
      // which is exactly the variant this table must not become.
      expect(
        byName[name]!.read<int>('notnull'),
        name == 'deleted_at' ? 0 : 1,
        reason: name == 'deleted_at'
            ? 'deleted_at must stay nullable'
            : '$name should be NOT NULL',
      );
    }
    expect(byName['event_id']!.read<String>('type'), 'TEXT');
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    // No DEFAULT on the identity columns on purpose: every insert must stamp
    // them or fail, which is what keeps CRDT stamping out of the service.
    expect(byName['hlc_timestamp']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    // Composite primary key, in order — the automatic index it gives SQLite is
    // why this table declares none of its own.
    expect(byName['event_id']!.read<int>('pk'), 1);
    expect(byName['day']!.read<int>('pk'), 2);
  });

  test('the event table carries the v27 CRDT block', () async {
    // `calendar_events` is the one CRDT table whose identity columns have a
    // DEFAULT: v27 added them to a *populated* table, and SQLite's
    // `ALTER TABLE … ADD COLUMN NOT NULL` demands one. The Drift declaration
    // then has to match, so the create path grows the same defaults — which is
    // exactly the create-vs-migrate agreement this file exists to pin.
    //
    // `''` is transitional, never a valid stored identity: the migration
    // backfills it in the same run and `CalendarEventDao` stamps every write.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_events)')
        .get();
    final byName = {
      for (final row in columns) row.read<String>('name'): row,
    };

    expect(
      byName.keys,
      containsAll([
        'hlc_timestamp',
        'device_id',
        'version',
        'is_deleted',
        'deleted_at',
        // v28's per-event description scope. Added by ALTER on upgraders and by
        // the Drift declaration on fresh installs — the same two paths this
        // file exists to hold together.
        'per_occurrence_descriptions',
      ]),
    );
    expect(byName['per_occurrence_descriptions']!.read<int>('notnull'), 1);
    // Off is the pre-v28 reading: one shared description for every day.
    expect(
      byName['per_occurrence_descriptions']!.read<String>('dflt_value'),
      '0',
    );
    for (final name in ['hlc_timestamp', 'device_id', 'version', 'is_deleted']) {
      expect(
        byName[name]!.read<int>('notnull'),
        1,
        reason: '$name should be NOT NULL',
      );
    }
    // The single nullable column of the block, and the reason a tombstone can
    // say *when* — `ContentChunks` drops it, which is the variant this must
    // not become.
    expect(byName['deleted_at']!.read<int>('notnull'), 0);
    expect(byName['deleted_at']!.readNullable<String>('dflt_value'), isNull);

    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    expect(byName['hlc_timestamp']!.read<String>('dflt_value'), "''");
    expect(byName['device_id']!.read<String>('dflt_value'), "''");
    // A pre-v27 event is a live, never-merged row — which is what it was.
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
  });

  test('the event start-date index is partial on live rows', () async {
    // The v27 migration drops the full index by name before recreating it, so
    // an upgraded database and a fresh one hold the same definition. The
    // name-only scrape above cannot see that difference; this can.
    final sql = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_calendar_events_start_date'",
        )
        .getSingle();
    expect(sql.read<String>('sql'), contains('WHERE is_deleted = 0'));
  });
}

/// All capture-group-1 matches of [pattern] across `lib/database/**.dart`,
/// with `//` comments stripped first so prose mentioning a statement (there is
/// one, describing why `IF NOT EXISTS` matters) is not mistaken for a
/// declaration.
Set<String> _declaredNames(RegExp pattern) {
  final names = <String>{};
  final dir = Directory('lib/database');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Generated code restates the schema; scanning it would assert nothing
    // about hand-written migrations.
    if (entity.path.endsWith('.g.dart')) continue;
    final source = entity
        .readAsLinesSync()
        .map((line) {
          final comment = line.indexOf('//');
          return comment == -1 ? line : line.substring(0, comment);
        })
        .join('\n');
    for (final match in pattern.allMatches(source)) {
      names.add(match.group(1)!);
    }
  }
  return names;
}
