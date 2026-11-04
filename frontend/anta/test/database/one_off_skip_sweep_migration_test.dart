// `isNotNull` is a SQL builder in drift and a matcher in flutter_test; this
// file wants the matcher.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/calendar_event_skips_binding.dart';

import 'support/db_test_support.dart';

/// v44 → v45: the skip rows a series left behind when it was converted to a
/// one-off are tombstoned; a series' skips are not touched.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  /// Unix seconds, Drift's storage for a `DateTimeColumn`.
  int seconds(DateTime day) => day.millisecondsSinceEpoch ~/ 1000;

  final startDay = DateTime.utc(2026, 3, 2);
  final otherDay = DateTime.utc(2026, 3, 9);

  late String seededStamp;

  Future<void> insertEvent(String id, String ruleKind, {bool deleted = false}) {
    return db.customStatement(
      'INSERT INTO calendar_events '
      '(id, title, category, start_date, rule_kind, created_at, updated_at, '
      'hlc_timestamp, device_id, is_deleted) '
      "VALUES (?, ?, 'gym', ?, ?, 0, 0, 'hlc', 'legacy-device', ?)",
      [id, id, seconds(startDay), ruleKind, deleted ? 1 : 0],
    );
  }

  Future<void> insertSkip(
    String eventId,
    DateTime day, {
    bool deleted = false,
  }) {
    return db.customStatement(
      'INSERT INTO calendar_event_skips '
      '(event_id, day, created_at, updated_at, hlc_timestamp, device_id, '
      'is_deleted, deleted_at) '
      "VALUES (?, ?, 0, 0, ?, 'legacy-device', ?, ?)",
      [eventId, seconds(day), seededStamp, deleted ? 1 : 0, deleted ? 7 : null],
    );
  }

  /// The skips' outbox entries as `{rowKey: row}`, untyped for the same
  /// reason.
  Future<Map<String, Map<String, Object?>>> outboxRows() async {
    final rows = await db
        .customSelect(
          'SELECT * FROM sync_outbox '
          "WHERE table_name = 'calendar_event_skips'",
        )
        .get();
    return {for (final row in rows) row.read<String>('row_key'): row.data};
  }

  Future<void> runV45() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v44CategoryProfiles,
      DatabaseSchema.v45OneOffSkipSweep,
    );
  }

  /// Untyped, so a later migration cannot break this file for reasons that
  /// have nothing to do with v45.
  Future<Map<String, QueryRow>> skipRows() async {
    final rows = await db
        .customSelect('SELECT * FROM calendar_event_skips')
        .get();
    return {
      for (final row in rows)
        '${row.read<String>('event_id')}@${row.read<int>('day')}': row,
    };
  }

  String key(String eventId, DateTime day) => '$eventId@${seconds(day)}';

  Future<void> seed() async {
    seededStamp = db.migrationBackfillHlc();
    await insertEvent('one-off-start', 'oneTime');
    await insertEvent('one-off-other', 'oneTime');
    await insertEvent('series', 'weekly');
    await insertEvent('one-off-tombstoned', 'oneTime');
    await insertEvent('one-off-deleted', 'oneTime', deleted: true);
    await insertEvent('dates', 'specificDates');
    await insertSkip('one-off-start', startDay);
    await insertSkip('one-off-other', otherDay);
    await insertSkip('series', otherDay);
    await insertSkip('one-off-tombstoned', startDay, deleted: true);
    await insertSkip('one-off-deleted', startDay);
    await insertSkip('dates', otherDay);
  }

  /// The rows the sweep tombstones. A soft-deleted one-off's row is among
  /// them: the frozen `UPDATE` matches on the rule alone, and the row is the
  /// same leftover — restoring the event would bring the hidden day back.
  final sweptKeys = [
    ('one-off-start', startDay),
    ('one-off-other', otherDay),
    ('one-off-deleted', startDay),
  ];

  test('the step is registered at 45', () {
    expect(DatabaseSchema.v45OneOffSkipSweep, 45);
    expect(
      DatabaseSchema.currentVersion,
      greaterThanOrEqualTo(DatabaseSchema.v45OneOffSkipSweep),
    );
  });

  test('tombstones only the one-offs\' skips, with a newer stamp and '
      'version + 1', () async {
    await seed();

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await runV45();

    final rows = await skipRows();
    for (final (eventId, day) in sweptKeys) {
      final swept = key(eventId, day);
      final row = rows[swept]!;
      expect(row.read<int>('is_deleted'), 1, reason: swept);
      // Unix seconds, as Drift stores them — never milliseconds.
      for (final column in ['deleted_at', 'updated_at']) {
        expect(
          row.read<int>(column),
          inInclusiveRange(nowSeconds - 60, nowSeconds + 60),
          reason: '$swept $column',
        );
      }
      expect(row.read<int>('version'), 2, reason: swept);
      expect(
        row.read<String>('hlc_timestamp').compareTo(seededStamp),
        greaterThan(0),
        reason: swept,
      );
      expect(row.read<String>('device_id'), 'test-device', reason: swept);
    }

    for (final (eventId, day) in [('series', otherDay), ('dates', otherDay)]) {
      final untouched = rows[key(eventId, day)]!;
      expect(untouched.read<int>('is_deleted'), 0, reason: eventId);
      expect(untouched.read<int>('version'), 1, reason: eventId);
      expect(untouched.read<String>('hlc_timestamp'), seededStamp);
      expect(untouched.read<String>('device_id'), 'legacy-device');
    }

    final tombstoned = rows[key('one-off-tombstoned', startDay)]!;
    expect(tombstoned.read<int>('is_deleted'), 1);
    expect(tombstoned.read<int>('deleted_at'), 7);
    expect(tombstoned.read<int>('version'), 1);
    expect(tombstoned.read<String>('hlc_timestamp'), seededStamp);
  });

  test('queues one tombstone per swept row under the dayRowKey, nothing '
      'else', () async {
    await seed();

    await runV45();

    final rows = await skipRows();
    final outbox = await outboxRows();
    expect(outbox.keys.toSet(), {
      for (final (eventId, day) in sweptKeys) dayRowKey(eventId, day),
    });
    for (final (eventId, day) in sweptKeys) {
      final entry = outbox[dayRowKey(eventId, day)]!;
      expect(entry['op'], OutboxOp.tombstone.name);
      expect(
        entry['hlc'],
        rows[key(eventId, day)]!.read<String>('hlc_timestamp'),
      );
    }
  });

  test('a rerun changes nothing and queues nothing', () async {
    await seed();
    await runV45();
    final before = {
      for (final MapEntry(:key, :value) in (await skipRows()).entries)
        key: value.data,
    };
    final queued = await outboxRows();

    await runV45();

    final after = {
      for (final MapEntry(:key, :value) in (await skipRows()).entries)
        key: value.data,
    };
    expect(after, before);
    expect(await outboxRows(), queued);
  });

  test('a swept row pulled back live under an older stamp stays '
      'tombstoned', () async {
    await seed();
    await runV45();
    const binding = CalendarEventSkipsBinding();
    final rowKey = dayRowKey('one-off-start', startDay);

    await binding.mergeRemote(
      db,
      SyncEnvelope(
        table: binding.table,
        rowKey: rowKey,
        hlc: seededStamp,
        deviceId: 'remote',
        version: 1,
        op: OutboxOp.upsert,
        ownerId: 'uid-1',
        data: {
          'eventId': 'one-off-start',
          'dayMs': startDay.millisecondsSinceEpoch,
          'createdAtMs': 0,
          'updatedAtMs': 0,
        },
      ),
    );

    final row = (await skipRows())[key('one-off-start', startDay)]!;
    expect(row.read<int>('is_deleted'), 1);
    expect(row.read<String>('device_id'), 'test-device');
  });
}
