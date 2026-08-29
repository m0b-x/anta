import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v32 → v33 adds one column by `ALTER TABLE`, so the two things worth pinning
/// are that an *upgrader* gets it and that re-running the step cannot fail or
/// lose rows — `runMigrations` replays every step whose `toVersion` is in
/// range, and a partial upgrade is what makes the `PRAGMA table_info` guard
/// load-bearing rather than decorative.
///
/// The create path is covered by `schema_parity_test`; this file drives the
/// upgrade path by dropping the column back off a real table.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<void> dropIsHidden() {
    return db.customStatement(
      'ALTER TABLE calendar_categories DROP COLUMN is_hidden',
    );
  }

  Future<void> runV33() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v32Vocabularies,
      DatabaseSchema.v33CategoryHidden,
    );
  }

  Future<Set<String>> columnNames() async {
    final rows = await db
        .customSelect('PRAGMA table_info(calendar_categories)')
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  /// Reads untyped, so a later migration cannot break this group for reasons
  /// that have nothing to do with v33.
  Future<List<QueryRow>> categoryRows() {
    return db.customSelect('SELECT * FROM calendar_categories').get();
  }

  Future<void> insertLegacyRow(String id) {
    return db.customStatement(
      'INSERT INTO calendar_categories '
      '(id, name, color_value, icon_key, sort_order, is_built_in, '
      'created_at, updated_at) '
      "VALUES ('$id', '$id', 1, 'event', 0, 0, 0, 0)",
    );
  }

  test('a fresh install already has the column', () async {
    expect(await columnNames(), contains('is_hidden'));
  });

  test('the column is added on an upgrader', () async {
    await dropIsHidden();
    expect(await columnNames(), isNot(contains('is_hidden')));

    await runV33();

    expect(await columnNames(), contains('is_hidden'));
  });

  test('existing rows default to visible', () async {
    await dropIsHidden();
    await insertLegacyRow('legacy');

    await runV33();

    final rows = await categoryRows();
    expect(rows, hasLength(1));
    expect(
      rows.single.read<int>('is_hidden'),
      0,
      reason:
          'a category that existed before the flag was visible, and there is '
          'no backfill because the default already says so',
    );
  });

  test('re-running it is a no-op and keeps existing rows', () async {
    await dropIsHidden();
    await insertLegacyRow('legacy');
    await runV33();
    await db.customStatement(
      "UPDATE calendar_categories SET is_hidden = 1 WHERE id = 'legacy'",
    );

    await runV33();

    final rows = await categoryRows();
    expect(rows, hasLength(1));
    expect(
      rows.single.read<int>('is_hidden'),
      1,
      reason:
          'the PRAGMA guard must skip the ALTER, not re-add a zeroed column',
    );
  });

  test(
    'an insert that omits the column relies on the frozen default',
    () async {
      await dropIsHidden();
      await runV33();
      await insertLegacyRow('later');

      final rows = await categoryRows();
      expect(rows.single.read<int>('is_hidden'), 0);
    },
  );
}
