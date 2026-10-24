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
/// under two documents — and every table that queues on its own has exactly
/// one binding.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('the tables pull parents first, the calendar before the browser', () {
    expect(syncTableBindings.map((b) => b.table), [
      'calendar_categories',
      'calendar_event_templates',
      'calendar_events',
      'calendar_event_occurrences',
      'calendar_event_absences',
      'calendar_event_skips',
      'calendar_event_alerts',
      'calendar_category_alerts',
      'event_digests',
      'calendar_filter_presets',
      'overview_views',
      'folders',
      'notes',
      'counters',
      'counter_values',
      'vocabularies',
      'vocabulary_items',
    ]);
  });

  test('every table queued on its own has exactly one binding', () {
    final queued = [
      for (final t in syncedTables)
        if (!t.travelsWithParent) t.name,
    ];
    final bound = syncTableBindings.map((b) => b.table).toList();

    for (final table in queued) {
      expect(bound.where((b) => b == table), hasLength(1), reason: table);
    }
    for (final table in bound) {
      expect(queued, contains(table), reason: '$table is not a synced table');
    }
  });

  // The EU spring-forward day: a day key read back through a local midnight
  // would land an hour off.
  final day = DateTime.utc(2026, 3, 29);
  const dayTables = {
    'calendar_event_occurrences',
    'calendar_event_absences',
    'calendar_event_skips',
  };

  for (final binding in syncTableBindings) {
    test('${binding.table} keys a row as its rowKeySql does', () async {
      final synced = syncedTables.singleWhere((t) => t.name == binding.table);
      final key = switch (binding.table) {
        'counter_values' => 'c1|note-1',
        final t when dayTables.contains(t) => dayRowKey('e1', day),
        _ => 'row-1',
      };
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
      if (dayTables.contains(binding.table)) {
        // Stored as unix seconds, keyed as epoch milliseconds.
        final stored = await db
            .customSelect('SELECT day FROM ${binding.table}')
            .getSingle();
        expect(stored.read<int>('day'), day.millisecondsSinceEpoch ~/ 1000);
        expect(key, 'e1|${day.millisecondsSinceEpoch}');
      }
    });
  }
}
