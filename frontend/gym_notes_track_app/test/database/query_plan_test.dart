import 'package:flutter_test/flutter_test.dart';
import 'package:gym_notes_track_app/database/daos/folder_dao.dart';
import 'package:gym_notes_track_app/database/daos/note_dao.dart';
import 'package:gym_notes_track_app/database/database.dart';

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
        : [for (final c in counter.captured) if (c.sql.contains(containing)) c];
    expect(
      statements,
      hasLength(1),
      reason: 'expected exactly one statement to explain, got: $statements',
    );
    return explainCaptured(db, statements.single);
  }

  Matcher usesIndex(String name) => contains(contains('USING INDEX $name'));
  final sortsInMemory = contains(contains('USE TEMP B-TREE FOR ORDER BY'));

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
      final plan = await planOf(() => db.contentChunkDao.getChunksForNote('n1'));
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
      expect(plan, usesIndex('idx_calendar_events_start_date'));
      expect(plan, isNot(sortsInMemory));
    });

    test('an occurrence override is a primary-key lookup', () async {
      final plan = await planOf(
        () => db.eventOccurrenceDao.deleteFor('e1', DateTime.utc(2026, 8, 10)),
      );
      // The composite PK {event_id, day} is the index; declaring a separate
      // one would be redundant. Guards that decision.
      expect(plan, contains(contains('SEARCH calendar_event_occurrences')));
      expect(plan, isNot(contains(contains('SCAN'))));
    });
  });
}
