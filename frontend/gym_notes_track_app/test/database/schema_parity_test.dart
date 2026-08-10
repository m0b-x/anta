import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_notes_track_app/database/database.dart';

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
    // That only pays off if something checks it.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_occurrences)')
        .get();
    final byName = {
      for (final row in columns) row.read<String>('name'): row,
    };

    expect(
      byName.keys.toSet(),
      {'event_id', 'day', 'description', 'created_at', 'updated_at'},
    );
    for (final name in byName.keys) {
      expect(
        byName[name]!.read<int>('notnull'),
        1,
        reason: '$name should be NOT NULL',
      );
    }
    expect(byName['event_id']!.read<String>('type'), 'TEXT');
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    expect(byName['description']!.read<String>('type'), 'TEXT');
    // Composite primary key, in order — this is what gives the point lookup
    // and the per-event cascade an index without declaring one.
    expect(byName['event_id']!.read<int>('pk'), 1);
    expect(byName['day']!.read<int>('pk'), 2);
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
