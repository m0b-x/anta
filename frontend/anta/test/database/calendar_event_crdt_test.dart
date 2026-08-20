// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/migrations.dart';

import 'support/db_test_support.dart';

/// Guards the columns nothing renders — the v27 CRDT block on `calendar_events`.
///
/// Every assertion here is invisible from the app: an event that tombstones
/// correctly and one that hard-deletes look identical on screen, a version that
/// never increments changes nothing a user can see, and a resurrected row and a
/// freshly inserted one draw the same. They are the properties a merge will
/// depend on once transport exists, and by then the history they protect is
/// already gone — which is why the schema was fixed before the transport.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<CalendarEventRow> rowFor(String id) {
    return (db.select(
      db.calendarEvents,
    )..where((e) => e.id.equals(id))).getSingle();
  }

  Future<List<CalendarEventRow>> allRows() =>
      db.select(db.calendarEvents).get();

  group('stamping', () {
    test('an insert is a live version-1 row stamped with this device', () async {
      await db.calendarEventDao.upsert(_event('e1'));

      final row = await rowFor('e1');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      // `''` exists only between the v27 ALTER and its backfill. Seeing it come
      // out of a write path means something wrote around the DAO.
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });

    test(
      'an edit bumps the version, keeps createdAt and moves the HLC',
      () async {
        await db.calendarEventDao.upsert(_event('e1'));
        final before = await rowFor('e1');

        await db.calendarEventDao.upsert(
          _event('e1', title: 'Push day', createdAt: DateTime.utc(2030, 1, 1)),
        );
        final after = await rowFor('e1');

        expect(after.title, 'Push day');
        expect(after.version, before.version + 1);
        // The whole reason this is not `insertOnConflictUpdate`: the caller's
        // companion always carries a `createdAt`, and it is always wrong.
        expect(after.createdAt, before.createdAt);
        // A version bump with a stale HLC would order two edits arbitrarily.
        expect(after.hlcTimestamp, isNot(before.hlcTimestamp));
        expect(after.deviceId, 'test-device');
      },
    );
  });

  group('tombstoning', () {
    test('a delete keeps the row and marks it deleted', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.softDeleteById('e1');

      final rows = await allRows();
      expect(rows, hasLength(1));
      expect(rows.single.isDeleted, isTrue);
      expect(rows.single.deletedAt, isNotNull);
      expect(rows.single.version, 2);
    });

    test('deleting twice does not churn the version', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.softDeleteById('e1');
      final before = await rowFor('e1');
      await db.calendarEventDao.softDeleteById('e1');
      final after = await rowFor('e1');

      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test('deleting an unknown id writes nothing', () async {
      await db.calendarEventDao.softDeleteById('does-not-exist');
      expect(await allRows(), isEmpty);
    });

    test('getAll hides tombstones', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.upsert(_event('e2'));
      await db.calendarEventDao.softDeleteById('e1');

      // The single read path, so this filter is what removes a deleted event
      // from the grid, the day panel, the agenda, the timeline, the `.ics`
      // export and the backup snapshot at once.
      final live = await db.calendarEventDao.getAll();
      expect(live.map((r) => r.id), ['e2']);
      expect(await allRows(), hasLength(2));
    });

    test('an upsert over a tombstone resurrects the row', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.softDeleteById('e1');

      await db.calendarEventDao.upsert(_event('e1', title: 'Back again'));

      final row = await rowFor('e1');
      // Without the explicit `isDeleted: false` on the update branch this row
      // would import invisible — the trap a tombstoning backup wipe would
      // spring on every restored id.
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.title, 'Back again');
      expect(row.version, 3);
      expect(await db.calendarEventDao.getAll(), hasLength(1));
    });

    test('the hard delete really removes the row', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.deleteById('e1');

      // Retained for the wipe paths; `deleteAll` must stay hard forever, or a
      // backup import would depend on resurrection to be visible at all.
      expect(await allRows(), isEmpty);
    });
  });

  group('v26 → v27 migration', () {
    /// Rebuilds `calendar_events` at its v26 shape — every column the twelve
    /// earlier calendar migrations left behind, none of the CRDT block — plus
    /// the **full** index v27 has to replace, then runs the real migration
    /// over it.
    ///
    /// The parity scrape can only see index *names*, and v27 reuses the name,
    /// so an upgraded database silently keeping the full index while fresh
    /// installs get the partial one is invisible to every other test here.
    Future<void> rebuildAtV26() async {
      await db.customStatement('DROP TABLE calendar_events');
      await db.customStatement(
        'CREATE TABLE calendar_events ('
        '  id TEXT NOT NULL PRIMARY KEY, '
        '  title TEXT NOT NULL, '
        '  category TEXT NOT NULL, '
        '  start_date INTEGER NOT NULL, '
        '  all_day INTEGER NOT NULL DEFAULT 1, '
        '  icon_key TEXT, '
        '  rule_kind TEXT NOT NULL, '
        '  rule_payload TEXT, '
        '  created_at INTEGER NOT NULL, '
        '  updated_at INTEGER NOT NULL, '
        '  end_date INTEGER, '
        '  start_minute INTEGER, '
        '  duration_minutes INTEGER, '
        '  description TEXT, '
        '  note_id TEXT, '
        '  color_value INTEGER, '
        '  tint_icon INTEGER NOT NULL DEFAULT 1, '
        '  priority INTEGER NOT NULL DEFAULT 3, '
        '  retroactive INTEGER NOT NULL DEFAULT 0, '
        '  count_occurrences INTEGER NOT NULL DEFAULT 0, '
        "  count_style TEXT NOT NULL DEFAULT 'numbered', "
        '  tracks_presence INTEGER NOT NULL DEFAULT 0'
        ')',
      );
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_calendar_events_start_date',
      );
      await db.customStatement(
        'CREATE INDEX idx_calendar_events_start_date '
        'ON calendar_events(start_date)',
      );
      await db.customStatement(
        'INSERT INTO calendar_events '
        '(id, title, category, start_date, rule_kind, created_at, updated_at) '
        "VALUES ('legacy', 'Leg day', 'gym', 0, 'daily', 0, 0)",
      );
    }

    Future<void> runV27() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v26EventPresence,
        DatabaseSchema.v27CalendarEventsCrdt,
      );
    }

    /// Reads the row untyped. The table is deliberately parked at the v27
    /// shape, and the generated mapper expects every column the *current*
    /// schema declares — so each later migration would otherwise break this
    /// group for reasons that have nothing to do with v27.
    Future<QueryRow> legacyRow() {
      return db
          .customSelect("SELECT * FROM calendar_events WHERE id = 'legacy'")
          .getSingle();
    }

    test('backfills real identity onto every pre-existing row', () async {
      await rebuildAtV26();
      await runV27();

      final row = await legacyRow();
      // `''` is transitional: it exists between the ALTER and the backfill
      // inside one migration run and must never survive it.
      expect(row.read<String>('hlc_timestamp'), isNotEmpty);
      expect(row.read<String>('device_id'), 'test-device');
      // A pre-v27 event is a live, never-merged row, which is what it was.
      expect(row.read<int>('version'), 1);
      expect(row.read<int>('is_deleted'), 0);
      expect(row.readNullable<int>('deleted_at'), isNull);
      expect(row.read<String>('title'), 'Leg day');
    });

    test('replaces the full start-date index with the partial one', () async {
      await rebuildAtV26();
      await runV27();

      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_calendar_events_start_date'",
          )
          .getSingle();
      // Skipping the DROP would satisfy `IF NOT EXISTS` and leave upgraders on
      // the full index forever — a create-vs-migrate divergence under one name.
      expect(sql.read<String>('sql'), contains('WHERE is_deleted = 0'));
    });

    test('re-running it changes nothing', () async {
      await rebuildAtV26();
      await runV27();
      final once = await legacyRow();

      await runV27();
      final twice = await legacyRow();

      // Idempotence is not academic here: the ALTERs would throw on a
      // partially-upgraded database, and a second backfill would restamp rows
      // the DAO had since written.
      expect(
        twice.read<String>('hlc_timestamp'),
        once.read<String>('hlc_timestamp'),
      );
      expect(twice.read<int>('version'), once.read<int>('version'));
    });
  });

  group('v27 → v28 migration', () {
    /// Rebuilds both tables at their v27 shapes — `calendar_events` with the
    /// CRDT block but without the per-event description flag, and
    /// `calendar_event_occurrences` at the v24 shape it kept for four versions
    /// — then seeds the rows the backfill has to sort out.
    Future<void> rebuildAtV27() async {
      await db.customStatement('DROP TABLE calendar_events');
      await db.customStatement(
        'CREATE TABLE calendar_events ('
        '  id TEXT NOT NULL PRIMARY KEY, '
        '  title TEXT NOT NULL, '
        '  category TEXT NOT NULL, '
        '  start_date INTEGER NOT NULL, '
        '  all_day INTEGER NOT NULL DEFAULT 1, '
        '  icon_key TEXT, '
        '  rule_kind TEXT NOT NULL, '
        '  rule_payload TEXT, '
        '  created_at INTEGER NOT NULL, '
        '  updated_at INTEGER NOT NULL, '
        '  end_date INTEGER, '
        '  start_minute INTEGER, '
        '  duration_minutes INTEGER, '
        '  description TEXT, '
        '  note_id TEXT, '
        '  color_value INTEGER, '
        '  tint_icon INTEGER NOT NULL DEFAULT 1, '
        '  priority INTEGER NOT NULL DEFAULT 3, '
        '  retroactive INTEGER NOT NULL DEFAULT 0, '
        '  count_occurrences INTEGER NOT NULL DEFAULT 0, '
        "  count_style TEXT NOT NULL DEFAULT 'numbered', "
        '  tracks_presence INTEGER NOT NULL DEFAULT 0, '
        "  hlc_timestamp TEXT NOT NULL DEFAULT '', "
        "  device_id TEXT NOT NULL DEFAULT '', "
        '  version INTEGER NOT NULL DEFAULT 1, '
        '  is_deleted INTEGER NOT NULL DEFAULT 0, '
        '  deleted_at INTEGER'
        ')',
      );
      await db.customStatement('DROP TABLE calendar_event_occurrences');
      await db.customStatement(
        'CREATE TABLE calendar_event_occurrences ('
        '  event_id TEXT NOT NULL, '
        '  day INTEGER NOT NULL, '
        '  description TEXT NOT NULL, '
        '  created_at INTEGER NOT NULL, '
        '  updated_at INTEGER NOT NULL, '
        '  PRIMARY KEY (event_id, day)'
        ')',
      );

      for (final seed in const [
        ('repeating', 'daily', 0),
        ('once', 'oneTime', 0),
        ('deleted', 'weekly', 1),
      ]) {
        await db.customStatement(
          'INSERT INTO calendar_events '
          '(id, title, category, start_date, rule_kind, created_at, '
          'updated_at, hlc_timestamp, device_id, is_deleted) '
          "VALUES (?, 'Leg day', 'gym', 0, ?, 0, 0, 'legacy-hlc', 'legacy', ?)",
          [seed.$1, seed.$2, seed.$3],
        );
      }
      await db.customStatement(
        'INSERT INTO calendar_event_occurrences '
        '(event_id, day, description, created_at, updated_at) '
        "VALUES ('repeating', 0, 'squats felt heavy', 0, 0)",
      );
    }

    Future<void> setGlobalFlag(String value) async {
      await db.customStatement(
        'INSERT OR REPLACE INTO user_settings (key, value, updated_at) '
        "VALUES ('event_per_occurrence_descriptions', ?, 0)",
        [value],
      );
    }

    Future<void> runV28() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v27CalendarEventsCrdt,
        DatabaseSchema.v28DescriptionScope,
      );
    }

    Future<Map<String, bool>> scopeFlags() async {
      final rows = await db.select(db.calendarEvents).get();
      return {for (final row in rows) row.id: row.perOccurrenceDescriptions};
    }

    test('a global ON flips live repeating events and nothing else', () async {
      await rebuildAtV27();
      await setGlobalFlag('true');
      await runV28();

      // A global-ON user had the scope control on *every* repeating event, so
      // every repeating event keeps it — behaviour and capability preserved,
      // and they can now turn individual ones off.
      expect(await scopeFlags(), {
        'repeating': true,
        // One day has nothing to separate; the v24 gate excluded it too.
        'once': false,
        // Flipping a tombstone would resurrect it into a later merge as a
        // newer write, for a flag no surface can reach.
        'deleted': false,
      });
    });

    test('a global OFF flips nothing', () async {
      await rebuildAtV27();
      await setGlobalFlag('false');
      await runV28();

      // Booleans live in `user_settings` as the literal strings, so anything
      // that is not exactly 'true' has to read as off.
      expect(await scopeFlags(), {
        'repeating': false,
        'once': false,
        'deleted': false,
      });
    });

    test('a never-written setting flips nothing', () async {
      await rebuildAtV27();
      await runV28();

      // The overwhelmingly common case: the switch was never discovered, so
      // the rows that exist stay dormant exactly as they render today.
      expect(await scopeFlags(), {
        'repeating': false,
        'once': false,
        'deleted': false,
      });
    });

    test('backfills real identity onto every occurrence row', () async {
      await rebuildAtV27();
      await runV28();

      final row = await db.select(db.eventOccurrenceDescriptions).getSingle();
      // `''` is transitional: it exists between the ALTER and the backfill
      // inside one migration run and must never survive it.
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
      // A pre-v28 override is a live, never-merged row, which is what it was.
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.description, 'squats felt heavy');
    });

    test('re-running it changes nothing', () async {
      await rebuildAtV27();
      await setGlobalFlag('true');
      await runV28();
      final once = await db.select(db.eventOccurrenceDescriptions).getSingle();

      await runV28();
      final twice = await db.select(db.eventOccurrenceDescriptions).getSingle();

      // Idempotence is not academic here: the ALTERs would throw on a
      // partially-upgraded database, and a second backfill would restamp rows
      // the DAO had since written.
      expect(twice.hlcTimestamp, once.hlcTimestamp);
      expect(twice.version, once.version);
      expect(await scopeFlags(), containsPair('repeating', true));
    });
  });

  group('reassignCategory', () {
    test('bumps every moved row with one shared HLC', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.upsert(_event('e2'));

      final moved = await db.calendarEventDao.reassignCategory('gym', 'other');
      expect(moved, 2);

      final rows = await db.calendarEventDao.getAll();
      expect(rows.map((r) => r.category), everyElement('other'));
      expect(rows.map((r) => r.version), everyElement(2));
      expect(rows.map((r) => r.deviceId), everyElement('test-device'));
      // One user action, one point in the merge order — the rows moved
      // together and must not sort against each other.
      expect(rows.map((r) => r.hlcTimestamp).toSet(), hasLength(1));
      expect(rows.first.hlcTimestamp, isNotEmpty);
    });

    test('leaves tombstoned rows alone', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      await db.calendarEventDao.upsert(_event('e2'));
      await db.calendarEventDao.softDeleteById('e2');

      final moved = await db.calendarEventDao.reassignCategory('gym', 'other');
      expect(moved, 1);

      final tombstone = await rowFor('e2');
      // A deleted event's category is not a thing to repair, and touching it
      // would resurrect it into every later merge as a newer write.
      expect(tombstone.category, 'gym');
      expect(tombstone.version, 2);
    });
  });
}

CalendarEventsCompanion _event(
  String id, {
  String title = 'Leg day',
  DateTime? createdAt,
}) {
  final stamp = createdAt ?? DateTime.utc(2026, 1, 1, 9);
  return CalendarEventsCompanion.insert(
    id: id,
    title: title,
    category: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    ruleKind: 'daily',
    createdAt: stamp,
    updatedAt: stamp,
  );
}
