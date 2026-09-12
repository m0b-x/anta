import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/item_label.dart';

import 'support/db_test_support.dart';

/// v38 → v39 adds one `label` column to **two** real tables by `ALTER TABLE`,
/// so what is worth pinning is that an upgrader gets both, that a re-run
/// cannot fail or zero a label already written (the `PRAGMA table_info` guard
/// is load-bearing after a partial upgrade), and that a pre-v39 row reads back
/// as [ItemLabel.none] rather than as some arbitrary colour.
///
/// The create path is covered by `schema_parity_test`; this file drives the
/// upgrade path by dropping the columns back off the real tables.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<void> dropLabels() async {
    await db.customStatement('ALTER TABLE notes DROP COLUMN label');
    await db.customStatement('ALTER TABLE folders DROP COLUMN label');
  }

  Future<void> runV39() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v38PresenceDefaultRepair,
      DatabaseSchema.v39ItemLabels,
    );
  }

  Future<Set<String>> columnNames(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  /// Reads untyped, so a later migration cannot break this group for reasons
  /// that have nothing to do with v39.
  Future<List<QueryRow>> rowsOf(String table) {
    return db.customSelect('SELECT * FROM $table').get();
  }

  Future<void> insertLegacyFolder(String id) {
    return db.customStatement(
      'INSERT INTO folders '
      '(id, name, parent_id, position, created_at, updated_at, '
      'hlc_timestamp, device_id, version, is_deleted) '
      "VALUES ('$id', '$id', NULL, 0, 0, 0, 'h', 'd', 1, 0)",
    );
  }

  Future<void> insertLegacyNote(String id) {
    return db.customStatement(
      'INSERT INTO notes '
      '(id, folder_id, title, preview, content_length, chunk_count, '
      'is_compressed, position, created_at, updated_at, '
      'hlc_timestamp, device_id, version, is_deleted) '
      "VALUES ('$id', 'f', '$id', '', 0, 1, 0, 0, 0, 0, 'h', 'd', 1, 0)",
    );
  }

  test('a fresh install already has both columns', () async {
    expect(await columnNames('notes'), contains('label'));
    expect(await columnNames('folders'), contains('label'));
  });

  test('both columns are added on an upgrader', () async {
    await dropLabels();
    expect(await columnNames('notes'), isNot(contains('label')));
    expect(await columnNames('folders'), isNot(contains('label')));

    await runV39();

    expect(await columnNames('notes'), contains('label'));
    expect(await columnNames('folders'), contains('label'));
  });

  test('existing rows default to unlabelled', () async {
    await dropLabels();
    await insertLegacyFolder('legacy-folder');
    await insertLegacyNote('legacy-note');

    await runV39();

    final folders = await rowsOf('folders');
    final notes = await rowsOf('notes');
    expect(folders, hasLength(1));
    expect(notes, hasLength(1));
    expect(
      ItemLabel.fromStorage(folders.single.read<int>('label')),
      ItemLabel.none,
      reason: 'nothing carried a label before v39, and 0 says exactly that',
    );
    expect(
      ItemLabel.fromStorage(notes.single.read<int>('label')),
      ItemLabel.none,
    );
  });

  test('re-running it is a no-op and keeps labels already written', () async {
    await dropLabels();
    await insertLegacyFolder('legacy-folder');
    await insertLegacyNote('legacy-note');
    await runV39();
    await db.customStatement('UPDATE folders SET label = 5');
    await db.customStatement('UPDATE notes SET label = 3');

    await runV39();

    expect(
      ItemLabel.fromStorage((await rowsOf('folders')).single.read<int>('label')),
      ItemLabel.teal,
      reason: 'the PRAGMA guard must skip the ALTER, not re-add a zeroed column',
    );
    expect(
      ItemLabel.fromStorage((await rowsOf('notes')).single.read<int>('label')),
      ItemLabel.yellow,
    );
  });

  test('a partial upgrade — one table migrated, one not — completes', () async {
    await db.customStatement('ALTER TABLE notes DROP COLUMN label');

    await runV39();

    expect(await columnNames('notes'), contains('label'));
    expect(await columnNames('folders'), contains('label'));
  });

  test('an insert that omits the column relies on the frozen default', () async {
    await dropLabels();
    await runV39();
    await insertLegacyFolder('later');
    await insertLegacyNote('later-note');

    expect((await rowsOf('folders')).single.read<int>('label'), 0);
    expect((await rowsOf('notes')).single.read<int>('label'), 0);
  });
}
