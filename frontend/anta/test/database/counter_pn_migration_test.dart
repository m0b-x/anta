import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v48 → v49 (scalability record S20): every existing counter value becomes
/// the epoch of its own last write with no number changing, and the values
/// of tombstoned notes are tombstoned and queued once.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
    // The v48 shape: the step's three columns are what it adds.
    for (final column in ['epoch_hlc', 'epoch_value', 'shards']) {
      await db.customStatement(
        'ALTER TABLE counter_values DROP COLUMN $column',
      );
    }
  });
  tearDown(() async => db.close());

  /// The note's tombstone stamp sits between a value at 4 and one at 8.
  const noteStamp = '000000000005:0000:deleter';

  Future<void> insertNote(String id, {bool deleted = false}) {
    return db.customStatement(
      'INSERT INTO notes (id, folder_id, title, created_at, updated_at, '
      'hlc_timestamp, device_id, is_deleted, deleted_at) '
      "VALUES (?, 'f', ?, 0, 0, ?, 'deleter', ?, ?)",
      [id, id, noteStamp, deleted ? 1 : 0, deleted ? 77 : null],
    );
  }

  Future<void> insertValue(String counterId, String noteId, int value) {
    return db.customStatement(
      'INSERT INTO counter_values (counter_id, note_id, value, hlc_timestamp, '
      "device_id) VALUES (?, ?, ?, ?, 'old')",
      [counterId, noteId, value, '00000000000$value:0000:old'],
    );
  }

  Future<void> runV49() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v47StorageHygiene,
      DatabaseSchema.v49Counters,
    );
  }

  /// Untyped, so a later migration cannot break this file for reasons that
  /// have nothing to do with v49.
  Future<Map<String, Map<String, Object?>>> valueRows() async {
    final rows = await db.customSelect('SELECT * FROM counter_values').get();
    return {
      for (final row in rows)
        '${row.read<String>('counter_id')}|${row.read<String>('note_id')}':
            row.data,
    };
  }

  test('keeps every value as the epoch of its own write', () async {
    await insertNote('live');
    await insertValue('reps', '', 7);
    await insertValue('reps', 'live', 3);
    await insertValue('laps', 'never-pulled', 5);

    await runV49();

    final rows = await valueRows();
    expect(rows, hasLength(3));
    for (final row in rows.values) {
      expect(row['epoch_value'], row['value']);
      expect(row['epoch_hlc'], row['hlc_timestamp']);
      expect(row['shards'], '');
      expect(row['is_deleted'], 0);
    }
    expect(rows['reps|']!['value'], 7);
  });

  test('tombstones and queues, under the note\'s own tombstone, the values '
      'it outranks, once', () async {
    await insertNote('gone', deleted: true);
    await insertValue('reps', 'gone', 4);
    await insertValue('laps', 'gone', 8);
    await insertValue('reps', '', 7);

    await runV49();

    final swept = (await valueRows())['reps|gone']!;
    expect(swept['is_deleted'], 1);
    expect(swept['version'], 2);
    expect(swept['value'], 4, reason: 'a tombstone keeps its number');
    expect(
      (swept['hlc_timestamp'], swept['device_id'], swept['deleted_at']),
      (noteStamp, 'deleter', 77),
    );
    expect(
      (await valueRows())['laps|gone']!['is_deleted'],
      0,
      reason: 'written after the delete, it outranks the tombstone',
    );
    final queued = await db
        .customSelect(
          "SELECT * FROM sync_outbox WHERE table_name = 'counter_values'",
        )
        .get();
    expect(
      queued.map((r) => (r.read<String>('row_key'), r.read<String>('op'))),
      [('reps|gone', 'tombstone')],
    );
    expect(queued.single.read<String>('hlc'), swept['hlc_timestamp']);
    expect((await valueRows())['reps|']!['is_deleted'], 0);
  });

  test('creates the note index the cascade reads by', () async {
    await db.customStatement('DROP INDEX idx_counter_values_note');

    await runV49();

    final index = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'idx_counter_values_note'",
        )
        .getSingle();
    expect(index.read<String>('sql'), contains('WHERE is_deleted = 0'));
  });

  test('a rerun changes nothing', () async {
    await insertNote('gone', deleted: true);
    await insertValue('reps', 'gone', 4);
    await insertValue('reps', '', 7);
    await runV49();
    // A tap since: the epoch must not move under a rerun.
    await db.customStatement(
      "UPDATE counter_values SET value = 9, shards = '{\"r\":[2,0]}' "
      "WHERE note_id = ''",
    );
    final before = await valueRows();

    await runV49();

    expect(await valueRows(), before);
  });
}
