import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/daos/folder_dao.dart';
import 'package:anta/database/daos/note_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// Asserts *how* SQLite answers the app's hot queries, which is the half of
/// performance testing that is deterministic. Wall-clock assertions flake on a
/// busy machine and get loosened until they catch nothing; a query plan does
/// not care how fast the laptop is.
///
/// Every statement here is captured from the DAO as it actually ran, so these
/// tests can never drift into asserting about SQL the app does not issue.
///
/// The queries below lean on **partial** indexes (`WHERE is_deleted = 0`) and
/// **expression** indexes (`COALESCE(parent_id, '')`, `LOWER(TRIM(name))`).
/// Those are only usable when the query repeats the expression exactly, so a
/// harmless-looking rewrite can silently drop to a full scan with no visible
/// symptom until a user has thousands of rows.
void main() {
  late StatementCounter counter;
  late AppDatabase db;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });
  tearDown(() async => db.close());

  /// Runs [operation], then explains the single statement it issued.
  ///
  /// `EXPLAIN QUERY PLAN` describes writes too — a `DELETE … WHERE` has to
  /// find its rows the same way a read does, so an unindexed delete is just as
  /// much a scan.
  Future<List<String>> planOf(
    Future<void> Function() operation, {
    String? containing,
  }) async {
    counter.reset();
    await operation();
    final statements = containing == null
        ? counter.captured
        : [
            for (final c in counter.captured)
              if (c.sql.contains(containing)) c,
          ];
    expect(
      statements,
      hasLength(1),
      reason: 'expected exactly one statement to explain, got: $statements',
    );
    return explainCaptured(db, statements.single);
  }

  Matcher usesIndex(String name) => contains(contains('USING INDEX $name'));

  /// A *covering* index is a different plan line — SQLite writes
  /// `USING COVERING INDEX`, which [usesIndex] deliberately does not match.
  /// The distinction is the whole point where it is asserted: a non-covering
  /// index still costs one rowid lookup per row returned.
  Matcher usesCoveringIndex(String name) =>
      contains(contains('USING COVERING INDEX $name'));

  final sortsInMemory = contains(contains('USE TEMP B-TREE FOR ORDER BY'));

  /// The single statement [operation] issued, for assertions about the SQL
  /// text itself rather than the plan SQLite picked for it.
  Future<String> sqlOf(Future<void> Function() operation) async {
    counter.reset();
    await operation();
    expect(counter.captured, hasLength(1));
    return counter.captured.single.sql;
  }

  group('folder browse', () {
    test('notes in a folder ordered by position walk the index', () async {
      final plan = await planOf(
        () => db.noteDao.getNotesPaginated(
          folderId: 'f1',
          limit: 50,
          offset: 0,
          sortField: NoteSortField.position,
          ascending: true,
        ),
      );
      expect(plan, usesIndex('idx_notes_position'));
      // The index supplies the order, so there is no sort step. This is the
      // whole point of idx_notes_position — and it was missing from every
      // fresh install until v25.
      expect(plan, isNot(sortsInMemory));
    });

    test('subfolders ordered by position walk the index', () async {
      final plan = await planOf(
        () => db.folderDao.getFoldersPaginated(
          parentId: 'p1',
          limit: 50,
          offset: 0,
          sortField: FolderSortField.position,
          ascending: true,
        ),
      );
      expect(plan, usesIndex('idx_folders_position'));
      expect(plan, isNot(sortsInMemory));
    });
  });

  group('name uniqueness (expression indexes)', () {
    test('note title lookup uses idx_notes_folder_ltitle', () async {
      final plan = await planOf(
        () => db.noteDao.noteTitleExistsInFolder(
          folderId: 'f1',
          title: 'Leg day',
        ),
      );
      expect(plan, usesIndex('idx_notes_folder_ltitle'));
      expect(plan, isNot(contains(contains('SCAN notes'))));
    });

    test('root folder name lookup uses idx_folders_parent_lname', () async {
      // The root case is why the index is on COALESCE(parent_id, '') — SQLite
      // treats each NULL as distinct, so a plain (parent_id, …) index cannot
      // satisfy `parent_id IS NULL`.
      final plan = await planOf(
        () => db.folderDao.folderNameExistsInParent(
          parentId: null,
          name: 'Programs',
        ),
      );
      expect(plan, usesIndex('idx_folders_parent_lname'));
      expect(plan, isNot(contains(contains('SCAN folders'))));
    });

    test('nested folder name lookup uses the same index', () async {
      final plan = await planOf(
        () => db.folderDao.folderNameExistsInParent(
          parentId: 'p1',
          name: 'Week 1',
        ),
      );
      expect(plan, usesIndex('idx_folders_parent_lname'));
    });
  });

  group('note content', () {
    test('chunks for a note are indexed by (note_id, chunk_index)', () async {
      final plan = await planOf(
        () => db.contentChunkDao.getChunksForNote('n1'),
      );
      expect(plan, usesIndex('idx_chunks_note_index'));
      // Ordering comes from the index, so opening a long note never sorts.
      expect(plan, isNot(sortsInMemory));
    });
  });

  group('calendar', () {
    test('events are read in start-date order without sorting', () async {
      final plan = await planOf(() => db.calendarEventDao.getAll());
      // A full read is correct here — the service caches every event in
      // memory. What matters is that the order arrives from the index rather
      // than from a sort.
      //
      // Since v27 the index is **partial** (`WHERE is_deleted = 0`) and
      // `getAll` restates that predicate. This is the canary for the two
      // drifting apart: SQLite will not use a partial index it cannot prove
      // the query implies, and the fallback — a scan plus a temp B-tree for
      // the ordering — is silent until a calendar gets big.
      expect(plan, usesIndex('idx_calendar_events_start_date'));
      expect(plan, isNot(sortsInMemory));
    });

    test('tombstoning a single event is a primary-key update', () async {
      await db.calendarEventDao.upsert(_event('e1'));
      final plan = await planOf(
        () => db.calendarEventDao.softDeleteById('e1'),
        containing: 'UPDATE',
      );
      // Deleting an event now *finds* a row and rewrites it rather than
      // dropping it, so the delete path has a plan worth guarding.
      expect(plan, contains(contains('SEARCH calendar_events')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });

    test('the absence tombstone cascade is a prefix search', () async {
      await db.eventAbsenceDao.markMissed('e1', DateTime.utc(2026, 8, 10));
      final plan = await planOf(
        () => db.eventAbsenceDao.tombstoneForEvent('e1'),
      );
      // Same shape as the hard cascade it replaced: `event_id` is leftmost in
      // the PK, so the bulk tombstone rides the automatic index instead of
      // scanning every mark in the table.
      expect(plan, contains(contains('SEARCH calendar_event_absences')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });

    test('resetting one day to the template is a primary-key update', () async {
      await db.eventOccurrenceDao.upsert(_occurrence('e1'));
      final plan = await planOf(
        () => db.eventOccurrenceDao.tombstone('e1', DateTime.utc(2026, 8, 10)),
        containing: 'UPDATE',
      );
      // Since v28 "reset this day" tombstones rather than deletes, so this is
      // the one write on the hot path that has to *find* a row. The composite
      // PK {event_id, day} is the index; declaring a separate one would be
      // redundant. Guards that decision.
      expect(plan, contains(contains('SEARCH calendar_event_occurrences')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });

    test('the occurrence tombstone cascade is a prefix search', () async {
      await db.eventOccurrenceDao.upsert(_occurrence('e1'));
      final plan = await planOf(
        () => db.eventOccurrenceDao.tombstoneForEvent('e1'),
      );
      // `event_id` is leftmost in the PK, so the bulk tombstone rides the
      // automatic index instead of scanning every materialized day in the
      // table — the same shape as the hard cascade it replaced.
      expect(plan, contains(contains('SEARCH calendar_event_occurrences')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });

    test('un-marking an occurrence is a primary-key update', () async {
      await db.eventAbsenceDao.markMissed('e1', DateTime.utc(2026, 8, 10));
      final plan = await planOf(
        () => db.eventAbsenceDao.unmark('e1', DateTime.utc(2026, 8, 10)),
        containing: 'UPDATE',
      );
      // Un-marking tombstones the row rather than deleting it, so this is the
      // one write that has to *find* a row on the hot path. The composite PK
      // {event_id, day} is the index; declaring a separate one would be
      // redundant.
      expect(plan, contains(contains('SEARCH calendar_event_absences')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });

    test('the absence cascade for an event is a prefix search', () async {
      final plan = await planOf(() => db.eventAbsenceDao.deleteForEvent('e1'));
      // `event_id` is leftmost in the PK, which is what lets the per-event
      // cascade ride the same automatic index as the point lookup.
      expect(plan, contains(contains('SEARCH calendar_event_absences')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });
  });

  // Both delta tables keep tombstones forever — that is the correct CRDT
  // policy, and it means a multi-year user's live rows sit among thousands of
  // dead ones. Each service re-reads every live row at startup and after every
  // event delete, so these two loads are the only place the tombstone pile has
  // a running cost. v31's answer is a partial index on exactly the columns the
  // load consumes, which is why `getActiveKeys` exists next to `getActive`.
  group('calendar delta loads', () {
    test('the skip load is answered entirely from its index', () async {
      final plan = await planOf(() => db.eventSkipDao.getActiveKeys());
      // COVERING is not a nicety here — it is the entire justification for
      // narrowing the projection. A plain index would still pay one rowid
      // lookup per live row, which is what made the same idea a *loss* on
      // `calendar_event_occurrences`, whose load also reads `description`.
      //
      // Note there is no `isNot(SCAN)` companion here, unlike the write-path
      // tests above: an index-only read of every live row is still reported as
      // a SCAN — of the index. Covering is the property that matters.
      expect(plan, usesCoveringIndex('idx_calendar_event_skips_active'));
    });

    test('the absence load is answered entirely from its index', () async {
      final plan = await planOf(() => db.eventAbsenceDao.getActiveKeys());
      expect(plan, usesCoveringIndex('idx_calendar_event_absences_active'));
    });

    // The plan assertions above describe *this host's* SQLite. These two do
    // not, and they are what actually guards the shipped Android build.
    //
    // Drift's `.equals(false)` emits `is_deleted = ?` with a bound `0`.
    // Whether SQLite can prove that implies a partial index's
    // `WHERE is_deleted = 0` is version-dependent: 3.53 uses the index, 3.50
    // drops to a scan. `sqlite3_flutter_libs` decides which version ships, and
    // it is not the one `flutter test` runs against — so the plan tests would
    // stay green while every phone fell back to a scan. Asserting the literal
    // is in the SQL is host-independent: no version has to *infer* anything.
    test('the skip load spells the predicate as a literal', () async {
      final sql = await sqlOf(() => db.eventSkipDao.getActiveKeys());
      expect(sql, contains('is_deleted = 0'));
      expect(sql, isNot(contains('?')));
    });

    test('the absence load spells the predicate as a literal', () async {
      final sql = await sqlOf(() => db.eventAbsenceDao.getActiveKeys());
      expect(sql, contains('is_deleted = 0'));
      expect(sql, isNot(contains('?')));
    });

    // v31 adds no table and no column — an index-only migration, the v10
    // shape. That makes a v30 database structurally identical to a v31 one
    // minus these two indexes, so dropping them from a fresh database
    // reproduces v30 exactly and the step can be run for real against it.
    test(
      'v30 → v31 creates both delta indexes on an existing install',
      () async {
        // The fresh-install half: `createAllIndexes` must already produce them,
        // or upgraders end up faster than new users — the `idx_folders_position`
        // failure that v25 existed to repair.
        expect(
          await indexNames(db),
          allOf(
            contains('idx_calendar_event_skips_active'),
            contains('idx_calendar_event_absences_active'),
          ),
        );

        await db.customStatement('DROP INDEX idx_calendar_event_skips_active');
        await db.customStatement(
          'DROP INDEX idx_calendar_event_absences_active',
        );

        await DatabaseMigrations(db).runMigrations(
          db.createMigrator(),
          DatabaseSchema.v30EventSkips,
          DatabaseSchema.v31CalendarDeltaIndexes,
        );

        expect(
          await indexNames(db),
          allOf(
            contains('idx_calendar_event_skips_active'),
            contains('idx_calendar_event_absences_active'),
          ),
        );
      },
    );
  });
}

CalendarEventsCompanion _event(String id) {
  return CalendarEventsCompanion.insert(
    id: id,
    title: 'Leg day',
    category: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    ruleKind: 'daily',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

EventOccurrenceDescriptionsCompanion _occurrence(String eventId) {
  return EventOccurrenceDescriptionsCompanion.insert(
    eventId: eventId,
    day: DateTime.utc(2026, 8, 10),
    description: 'squats felt heavy',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
