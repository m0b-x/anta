import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_tables.dart';

import '../../database/support/db_test_support.dart';

/// Pins the binding registry to the table registry: every binding names a
/// synced table that queues on its own, and keys its rows exactly as the
/// outbox's `rowKeySql` does — a key built two ways would address one row
/// under two documents. S2b adds the completeness pin once every table has
/// its binding.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('the browser tables pull parents first', () {
    expect(syncTableBindings.map((b) => b.table), [
      'folders',
      'notes',
      'counters',
      'counter_values',
      'vocabularies',
      'vocabulary_items',
    ]);
  });

  test('every binding names a synced table queued on its own', () {
    final queued = {
      for (final t in syncedTables)
        if (!t.travelsWithParent) t.name,
    };
    for (final binding in syncTableBindings) {
      expect(queued, contains(binding.table));
    }
    expect(syncTableBindings.map((b) => b.table).toSet(), hasLength(6));
  });

  for (final binding in syncTableBindings) {
    test('${binding.table} keys a row as its rowKeySql does', () async {
      final synced = syncedTables.singleWhere((t) => t.name == binding.table);
      final key = binding.table == 'counter_values' ? 'c1|note-1' : 'row-1';
      // A data-less tombstone stores a row of column defaults under the key
      // alone — enough to read the key back both ways.
      await binding.mergeRemote(
        db,
        SyncEnvelope(
          table: binding.table,
          rowKey: key,
          hlc: '0193a0b0c0d0:0000:remote',
          deviceId: 'remote',
          version: 1,
          op: OutboxOp.tombstone,
          ownerId: 'uid-1',
        ),
      );

      final rows = await binding.loadByKeys(db, [key]);
      final sql = await db
          .customSelect(
            'SELECT ${synced.rowKeySql} AS k FROM ${binding.table} '
            'WHERE ${synced.rowKeySql} = ?',
            variables: [Variable<String>(key)],
          )
          .getSingle();

      expect(rows, hasLength(1), reason: 'tombstones load too');
      expect(binding.rowKeyOf(rows.single), sql.read<String>('k'));
      expect(binding.rowKeyOf(rows.single), key);
    });
  }
}
