import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v39 → v40 creates **two tables**, adds **one column** to a populated one and
/// creates **three indexes**, which is the widest migration since v29 — and the
/// only one whose failure mode is a phone that rings for an event that is not
/// there.
///
/// The create path is covered by `schema_parity_test`; this file drives the
/// upgrade path by taking a fresh database back to v39 (dropping the tables,
/// the column and therefore the indexes) and running the real step against it.
///
/// The load-bearing assertion is the last group: the migrated shape is
/// compared **column for column** against the shape `createAll` produces, so
/// the frozen DDL and the Drift declarations cannot drift apart silently.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Set<String>> columnNames(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  /// `(name, type, notnull, dflt_value, pk)` per column — everything
  /// `PRAGMA table_info` can tell us about a table's shape.
  Future<List<String>> columnShape(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return [
      for (final row in rows)
        [
          row.read<String>('name'),
          row.read<String>('type'),
          row.read<int>('notnull'),
          row.readNullable<String>('dflt_value') ?? '-',
          row.read<int>('pk'),
        ].join('|'),
    ];
  }

  Future<void> dropV40() async {
    await db.customStatement('DROP TABLE IF EXISTS calendar_event_alerts');
    await db.customStatement('DROP TABLE IF EXISTS alert_registrations');
    await db.customStatement(
      'ALTER TABLE calendar_events DROP COLUMN remove_after_alert',
    );
  }

  Future<void> runV40() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v39ItemLabels,
      DatabaseSchema.v40EventAlerts,
    );
  }

  Future<void> insertLegacyEvent(String id) {
    return db.customStatement(
      'INSERT INTO calendar_events '
      '(id, title, category, start_date, all_day, rule_kind, '
      'created_at, updated_at, hlc_timestamp, device_id, version, is_deleted) '
      "VALUES ('$id', '$id', 'other', 0, 1, 'oneTime', 0, 0, 'h', 'd', 1, 0)",
    );
  }

  test('a fresh install already has everything v40 adds', () async {
    expect(await tableNames(db), containsAll(const [
      'calendar_event_alerts',
      'alert_registrations',
    ]));
    expect(await columnNames('calendar_events'), contains('remove_after_alert'));
    expect(await indexNames(db), containsAll(const [
      'idx_calendar_event_alerts_active',
      'idx_alert_registrations_pending',
      'idx_alert_registrations_event',
    ]));
  });

  test('an upgrader gets both tables, the column and the indexes', () async {
    await dropV40();
    expect(await tableNames(db), isNot(contains('calendar_event_alerts')));
    expect(
      await columnNames('calendar_events'),
      isNot(contains('remove_after_alert')),
    );

    await runV40();

    expect(await tableNames(db), containsAll(const [
      'calendar_event_alerts',
      'alert_registrations',
    ]));
    expect(await columnNames('calendar_events'), contains('remove_after_alert'));
    expect(await indexNames(db), containsAll(const [
      'idx_calendar_event_alerts_active',
      'idx_alert_registrations_pending',
      'idx_alert_registrations_event',
    ]));
  });

  test('existing events upgrade to "not removed after an alert"', () async {
    await dropV40();
    await insertLegacyEvent('legacy');

    await runV40();

    final rows = await db.customSelect('SELECT * FROM calendar_events').get();
    expect(rows, hasLength(1));
    expect(
      rows.single.read<int>('remove_after_alert'),
      0,
      reason: 'an event that could not carry an alarm could not be removed by '
          'one either, so the default needs no backfill',
    );
  });

  test('re-running it changes nothing it already wrote', () async {
    await dropV40();
    await insertLegacyEvent('legacy');
    await runV40();
    await db.customStatement(
      'UPDATE calendar_events SET remove_after_alert = 1',
    );
    await db.customStatement(
      "INSERT INTO calendar_event_alerts "
      '(id, event_id, mode, offset_minutes, days_before, enabled, '
      'created_at, updated_at, hlc_timestamp, device_id, version, is_deleted) '
      "VALUES ('a1', 'legacy', 'ring', 15, 0, 1, 0, 0, 'h', 'd', 1, 0)",
    );

    await runV40();

    final events = await db.customSelect('SELECT * FROM calendar_events').get();
    expect(
      events.single.read<int>('remove_after_alert'),
      1,
      reason: 'the PRAGMA guard must skip the ALTER, not re-add a zeroed column',
    );
    final alerts = await db
        .customSelect('SELECT * FROM calendar_event_alerts')
        .get();
    expect(
      alerts,
      hasLength(1),
      reason: 'CREATE TABLE IF NOT EXISTS must not replace a populated table',
    );
    expect(alerts.single.read<String>('mode'), 'ring');
  });

  test('a partial upgrade — one table there, the column not — completes', () async {
    await db.customStatement('DROP TABLE alert_registrations');
    await db.customStatement(
      'ALTER TABLE calendar_events DROP COLUMN remove_after_alert',
    );

    await runV40();

    expect(await tableNames(db), contains('alert_registrations'));
    expect(await columnNames('calendar_events'), contains('remove_after_alert'));
  });

  test('an insert that omits the flag relies on the frozen default', () async {
    await dropV40();
    await runV40();
    await insertLegacyEvent('later');

    final rows = await db.customSelect('SELECT * FROM calendar_events').get();
    expect(rows.single.read<int>('remove_after_alert'), 0);
  });

  group('create-vs-migrate parity', () {
    test('the alert table is column-for-column the created one', () async {
      final created = await columnShape('calendar_event_alerts');

      await dropV40();
      await runV40();

      expect(await columnShape('calendar_event_alerts'), created);
    });

    test('the registration table is column-for-column the created one', () async {
      final created = await columnShape('alert_registrations');

      await dropV40();
      await runV40();

      expect(await columnShape('alert_registrations'), created);
    });

    test('the migrated flag matches the declared one', () async {
      final created = (await columnShape(
        'calendar_events',
      )).firstWhere((c) => c.startsWith('remove_after_alert|'));

      await dropV40();
      await runV40();

      expect(
        (await columnShape('calendar_events'))
            .firstWhere((c) => c.startsWith('remove_after_alert|')),
        created,
      );
    });

    test('the three index definitions survive the upgrade verbatim', () async {
      Future<Map<String, String>> alertIndexSql() async {
        final rows = await db
            .customSelect(
              "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
              "AND (name LIKE 'idx_calendar_event_alerts%' "
              "OR name LIKE 'idx_alert_registrations%')",
            )
            .get();
        return {
          for (final row in rows)
            row.read<String>('name'): row.read<String>('sql'),
        };
      }

      final created = await alertIndexSql();
      expect(created, hasLength(3));

      await dropV40();
      await runV40();

      // The migration calls the same `DatabaseIndexes` method the create path
      // does, which is the only reason this can hold — an index spelled twice
      // is an index that eventually differs.
      expect(await alertIndexSql(), created);
    });
  });

  group('the registration table is device-local', () {
    test('it carries no CRDT block at all', () async {
      final columns = await columnNames('alert_registrations');

      // Deliberate, not an oversight: the table mirrors one phone's OS
      // scheduler, is never exported and never merged, and any reconcile can
      // rebuild it. A tombstone here would describe nothing.
      expect(columns, isNot(contains('hlc_timestamp')));
      expect(columns, isNot(contains('device_id')));
      expect(columns, isNot(contains('is_deleted')));
      expect(columns, isNot(contains('version')));
    });

    test('a hard delete really removes the row', () async {
      await db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: const Value(7),
          alertId: const Value('a1'),
          eventId: const Value('e1'),
          day: Value(DateTime.utc(2026, 9, 15).millisecondsSinceEpoch),
          fireAt: Value(DateTime(2026, 9, 15, 8).millisecondsSinceEpoch),
          backend: const Value('alarm'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await db.alertRegistrationDao.deleteForEvent('e1');

      expect(await db.select(db.alertRegistrations).get(), isEmpty);
    });

    test('markState moves a row out of pending, and a miss is a no-op', () async {
      await db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: const Value(7),
          alertId: const Value('a1'),
          eventId: const Value('e1'),
          day: Value(DateTime.utc(2026, 9, 15).millisecondsSinceEpoch),
          fireAt: Value(DateTime(2026, 9, 15, 8).millisecondsSinceEpoch),
          backend: const Value('alarm'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await db.alertRegistrationDao.markState(7, 'stopped');
      // A row the platform no longer knows about is simply absent — reconcile
      // prunes on the OS's answer, so a state change for one must not throw.
      await db.alertRegistrationDao.markState(999, 'stopped');

      expect(await db.alertRegistrationDao.pending(), isEmpty);
      final row = await (db.select(
        db.alertRegistrations,
      )..where((r) => r.osId.equals(7))).getSingle();
      expect(row.state, 'stopped');
    });

    test('the sweep spares pending rows and clears settled old ones', () async {
      final now = DateTime(2026, 9, 15, 12);
      Future<void> add(int osId, String state, DateTime updatedAt) {
        return db.alertRegistrationDao.put(
          AlertRegistrationsCompanion(
            osId: Value(osId),
            alertId: const Value('a1'),
            eventId: const Value('e1'),
            day: Value(DateTime.utc(2026, 9, 15).millisecondsSinceEpoch),
            fireAt: Value(now.millisecondsSinceEpoch),
            state: Value(state),
            backend: const Value('alarm'),
            createdAt: Value(updatedAt),
            updatedAt: Value(updatedAt),
          ),
        );
      }

      await add(1, 'pending', now.subtract(const Duration(days: 30)));
      await add(2, 'fired', now.subtract(const Duration(days: 8)));
      await add(3, 'stopped', now.subtract(const Duration(days: 2)));

      final swept = await db.alertRegistrationDao.sweep(now: now);

      expect(swept, 1);
      final left = await db.select(db.alertRegistrations).get();
      expect(
        left.map((r) => r.osId).toSet(),
        {1, 3},
        reason: 'a pending row whose instant has passed is exactly what the '
            'late-fire path has to find, so age never sweeps it',
      );
    });
  });
}
