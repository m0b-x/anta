// `isNull` is a SQL builder in drift and a matcher in flutter_test; this file
// wants the matcher.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// v36 → v37 is four `ALTER TABLE`s across three tables plus one index swap,
/// so the two things worth pinning are that an *upgrader* gets all of it and
/// that re-running the step cannot fail or lose rows — `runMigrations` replays
/// every step whose `toVersion` is in range, and a partial upgrade is what
/// makes the `PRAGMA table_info` guards load-bearing rather than decorative.
///
/// The create path is covered by `schema_parity_test`; this file drives the
/// upgrade path by dropping the columns back off real tables.
///
/// The index swap is the half a column check cannot see.
/// `idx_calendar_event_absences_active` existed since v31 over
/// `(event_id, day)`, and `getActiveKeys` now projects `status` as well — an
/// upgrader left on the two-column index still answers the load, but no longer
/// *covering*, so every live mark costs a rowid lookup at every startup with
/// nothing anywhere to say so. Only the definition stored in `sqlite_master`
/// tells the two apart.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Set<String>> columnNames(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<String> absenceIndexSql() async {
    final row = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_calendar_event_absences_active'",
        )
        .getSingle();
    return row.read<String>('sql');
  }

  /// Reproduces a v36 database out of a fresh one.
  ///
  /// The index has to go first: SQLite refuses to drop a column an index
  /// mentions, and `status` is in this one since v37. Recreating it in the v31
  /// two-column shape is what makes the swap assertion below real rather than
  /// a tautology about an index that was simply missing.
  Future<void> dropV37() async {
    await db.customStatement(
      'DROP INDEX IF EXISTS idx_calendar_event_absences_active',
    );
    await db.customStatement(
      'ALTER TABLE calendar_event_absences DROP COLUMN status',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_event_absences_active '
      'ON calendar_event_absences(event_id, day) WHERE is_deleted = 0',
    );
    await db.customStatement(
      'ALTER TABLE calendar_events DROP COLUMN assume_absent',
    );
    await db.customStatement(
      'ALTER TABLE calendar_events DROP COLUMN assume_absent_from',
    );
    await db.customStatement(
      'ALTER TABLE calendar_event_templates DROP COLUMN assume_absent',
    );
  }

  Future<void> runV37() {
    return DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v36NoteTitleIndex,
      DatabaseSchema.v37AssumeAbsent,
    );
  }

  /// Reads untyped, so a later migration cannot break this group for reasons
  /// that have nothing to do with v37.
  Future<QueryRow> singleRow(String table) async {
    final rows = await db.customSelect('SELECT * FROM $table').get();
    expect(rows, hasLength(1));
    return rows.single;
  }

  Future<void> insertLegacyEvent(String id) {
    return db.customStatement(
      'INSERT INTO calendar_events '
      '(id, title, category, start_date, rule_kind, created_at, updated_at) '
      "VALUES ('$id', '$id', 'gym', 0, 'daily', 0, 0)",
    );
  }

  Future<void> insertLegacyAbsence(String eventId) {
    return db.customStatement(
      'INSERT INTO calendar_event_absences '
      '(event_id, day, created_at, updated_at, hlc_timestamp, device_id) '
      "VALUES ('$eventId', 0, 0, 0, 'hlc', 'legacy-device')",
    );
  }

  Future<void> insertLegacyTemplate(String id) {
    return db.customStatement(
      'INSERT INTO calendar_event_templates '
      '(id, name, category, created_at, updated_at, hlc_timestamp, device_id) '
      "VALUES ('$id', '$id', 'gym', 0, 0, 'hlc', 'legacy-device')",
    );
  }

  test('a fresh install already has all four columns', () async {
    expect(
      await columnNames('calendar_events'),
      allOf(contains('assume_absent'), contains('assume_absent_from')),
    );
    expect(await columnNames('calendar_event_absences'), contains('status'));
    expect(
      await columnNames('calendar_event_templates'),
      contains('assume_absent'),
    );
  });

  test('the columns are added on an upgrader', () async {
    await dropV37();
    expect(
      await columnNames('calendar_events'),
      allOf(
        isNot(contains('assume_absent')),
        isNot(contains('assume_absent_from')),
      ),
    );
    expect(
      await columnNames('calendar_event_absences'),
      isNot(contains('status')),
    );
    expect(
      await columnNames('calendar_event_templates'),
      isNot(contains('assume_absent')),
    );

    await runV37();

    expect(
      await columnNames('calendar_events'),
      allOf(contains('assume_absent'), contains('assume_absent_from')),
    );
    expect(await columnNames('calendar_event_absences'), contains('status'));
    expect(
      await columnNames('calendar_event_templates'),
      contains('assume_absent'),
    );
  });

  test('existing rows keep the meaning they already had', () async {
    await dropV37();
    await insertLegacyEvent('legacy');
    await insertLegacyAbsence('legacy');
    await insertLegacyTemplate('legacy-template');

    await runV37();

    final event = await singleRow('calendar_events');
    expect(
      event.read<int>('assume_absent'),
      0,
      reason:
          'an event tracked before v37 was tracked under implicit attendance, '
          'and there is no backfill because the default already says so',
    );
    expect(
      event.readNullable<int>('assume_absent_from'),
      isNull,
      reason: 'no boundary is the only thing a pre-v37 event could have meant',
    );
    expect(
      (await singleRow('calendar_event_absences')).read<String>('status'),
      'missed',
      reason:
          'every live row before v37 meant exactly one thing, which is what '
          'the column default encodes',
    );
    expect(
      (await singleRow('calendar_event_templates')).read<int>('assume_absent'),
      0,
    );
  });

  test('re-running it is a no-op and keeps existing rows', () async {
    await dropV37();
    await insertLegacyEvent('legacy');
    await insertLegacyAbsence('legacy');
    await runV37();
    await db.customStatement(
      "UPDATE calendar_events SET assume_absent = 1, assume_absent_from = 100 "
      "WHERE id = 'legacy'",
    );
    await db.customStatement(
      "UPDATE calendar_event_absences SET status = 'present'",
    );

    await runV37();

    final event = await singleRow('calendar_events');
    expect(
      event.read<int>('assume_absent'),
      1,
      reason:
          'the PRAGMA guard must skip the ALTER, not re-add a zeroed column',
    );
    expect(event.read<int>('assume_absent_from'), 100);
    expect(
      (await singleRow('calendar_event_absences')).read<String>('status'),
      'present',
    );
  });

  test(
    'an insert that omits the columns relies on the frozen defaults',
    () async {
      await dropV37();
      await runV37();
      await insertLegacyEvent('later');
      await insertLegacyAbsence('later');
      await insertLegacyTemplate('later-template');

      final event = await singleRow('calendar_events');
      expect(event.read<int>('assume_absent'), 0);
      expect(event.readNullable<int>('assume_absent_from'), isNull);
      expect(
        (await singleRow('calendar_event_absences')).read<String>('status'),
        'missed',
      );
      expect(
        (await singleRow(
          'calendar_event_templates',
        )).read<int>('assume_absent'),
        0,
      );
    },
  );

  test('the two-column absence index is replaced, not left alone', () async {
    expect(await absenceIndexSql(), contains('(event_id, day, status)'));

    await dropV37();
    expect(
      await absenceIndexSql(),
      isNot(contains('status')),
      reason:
          'the v31 shape has to actually be in place, or the swap below '
          'proves nothing',
    );

    await runV37();

    // `CREATE INDEX IF NOT EXISTS` alone would have left the upgrader on the
    // two-column definition forever — which is why the migration drops by name
    // first, the same idiom v27 used for the event start-date index.
    expect(await absenceIndexSql(), contains('(event_id, day, status)'));
    expect(await absenceIndexSql(), contains('WHERE is_deleted = 0'));
  });

  test('the swapped index still answers the load without the table', () async {
    await dropV37();
    await runV37();

    final plan = await queryPlan(
      db,
      'SELECT event_id, day, status FROM calendar_event_absences '
      'WHERE is_deleted = 0',
    );

    // The whole point of widening the index rather than dropping `status` from
    // the projection: an upgraded database must read the marks index-only, the
    // way a fresh install does.
    expect(
      plan,
      contains(
        contains('USING COVERING INDEX idx_calendar_event_absences_active'),
      ),
    );
  });

  group('v37 → v38 repair', () {
    /// Reproduces the shape an intermediate build stamped as 37: the status
    /// column and the three-column index in their final form, but one
    /// `presence_default` text column where the `assume_absent` pair landed.
    Future<void> intermediateV37() async {
      await db.customStatement(
        'ALTER TABLE calendar_events DROP COLUMN assume_absent',
      );
      await db.customStatement(
        'ALTER TABLE calendar_events DROP COLUMN assume_absent_from',
      );
      await db.customStatement(
        'ALTER TABLE calendar_event_templates DROP COLUMN assume_absent',
      );
      for (final table in const [
        'calendar_events',
        'calendar_event_templates',
      ]) {
        await db.customStatement(
          "ALTER TABLE $table ADD COLUMN presence_default TEXT NOT NULL "
          "DEFAULT 'present'",
        );
      }
    }

    Future<void> runV38() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v37AssumeAbsent,
        DatabaseSchema.v38PresenceDefaultRepair,
      );
    }

    test('a database stamped 37 by the intermediate build is repaired', () async {
      await intermediateV37();
      await insertLegacyEvent('kept');
      await insertLegacyEvent('flipped');
      await db.customStatement(
        "UPDATE calendar_events SET presence_default = 'absent' "
        "WHERE id = 'flipped'",
      );
      await insertLegacyTemplate('tpl');
      await db.customStatement(
        "UPDATE calendar_event_templates SET presence_default = 'absent' "
        "WHERE id = 'tpl'",
      );

      await runV38();

      final template = await singleRow('calendar_event_templates');
      expect(template.read<int>('assume_absent'), 1);

      expect(
        await columnNames('calendar_events'),
        allOf(
          contains('assume_absent'),
          contains('assume_absent_from'),
          isNot(contains('presence_default')),
        ),
      );
      expect(
        await columnNames('calendar_event_templates'),
        allOf(contains('assume_absent'), isNot(contains('presence_default'))),
      );
      final rows = await db
          .customSelect(
            'SELECT id, assume_absent, assume_absent_from FROM calendar_events '
            'ORDER BY id',
          )
          .get();
      expect(rows.map((r) => r.read<String>('id')), ['flipped', 'kept']);
      expect(rows[0].read<int>('assume_absent'), 1);
      expect(rows[1].read<int>('assume_absent'), 0);
      expect(rows[0].read<int?>('assume_absent_from'), isNull);
      // The rows are what the whole step exists to bring back: the typed DAO
      // read is the query that failed on the missing column.
      expect(await db.calendarEventDao.getAll(), hasLength(2));
    });

    test('a correct v37 database passes through v38 untouched', () async {
      await insertLegacyEvent('e');
      await db.customStatement(
        "UPDATE calendar_events SET assume_absent = 1, "
        "assume_absent_from = 86400 WHERE id = 'e'",
      );
      final before = await columnNames('calendar_events');

      await runV38();

      expect(await columnNames('calendar_events'), before);
      final row = await singleRow('calendar_events');
      expect(row.read<int>('assume_absent'), 1);
      expect(row.read<int>('assume_absent_from'), 86400);
      expect(await absenceIndexSql(), contains('(event_id, day, status)'));
    });
  });
}
