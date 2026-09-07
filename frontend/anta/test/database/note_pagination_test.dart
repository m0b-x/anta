import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/note_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Paging is only well defined if the order is total.
///
/// `updated_at` is stored to the second, so a folder filled in one sitting is
/// mostly ties, and `LIMIT/OFFSET` re-runs the whole ordering per page: rows
/// tied on the sort key can come back in a different order for page 2 than
/// they did for page 1. The visible symptom is a note served twice — two
/// widgets under one `ValueKey`, which is a framework assertion — while
/// another is served on neither page.
void main() {
  late AppDatabase db;
  late StatementCounter counter;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });
  tearDown(() async => db.close());

  const folderId = 'f1';

  /// Forty notes sharing one `updatedAt` to the second, and one `position`,
  /// so every sort but `id` sees a single run of ties.
  Future<void> seedTiedNotes(int count) async {
    final stamp = DateTime.utc(2026, 3, 1, 10, 30, 15);
    await db.batch((batch) {
      batch.insert(
        db.folders,
        FoldersCompanion.insert(
          id: folderId,
          name: 'Training',
          hlcTimestamp: '0',
          deviceId: 'test',
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      for (var i = 0; i < count; i++) {
        batch.insert(
          db.notes,
          NotesCompanion.insert(
            id: 'n${i.toString().padLeft(3, '0')}',
            folderId: folderId,
            title: 'Session',
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: stamp,
            updatedAt: stamp,
            position: const Value(0),
          ),
        );
      }
    });
  }

  Future<List<String>> page({
    required NoteSortField sortField,
    required int offset,
    int limit = 20,
    bool ascending = false,
  }) async {
    final notes = await db.noteDao.getNotesPaginated(
      folderId: folderId,
      limit: limit,
      offset: offset,
      sortField: sortField,
      ascending: ascending,
    );
    return [for (final note in notes) note.id];
  }

  test(
    'paginating notes with identical updatedAt returns each note exactly once',
    () async {
      await seedTiedNotes(40);

      final first = await page(sortField: NoteSortField.updatedAt, offset: 0);
      final second = await page(sortField: NoteSortField.updatedAt, offset: 20);

      expect(first, hasLength(20));
      expect(second, hasLength(20));
      expect(
        {...first, ...second},
        hasLength(40),
        reason:
            'two pages of twenty must be forty distinct notes; a repeat here '
            'is the duplicate ValueKey the list throws on',
      );
    },
  );

  test('every sort field pages a run of ties without repeating one', () async {
    await seedTiedNotes(40);

    for (final sortField in NoteSortField.values) {
      final first = await page(sortField: sortField, offset: 0);
      final second = await page(sortField: sortField, offset: 20);
      expect(
        {...first, ...second},
        hasLength(40),
        reason: '$sortField repeated or dropped a row across its pages',
      );
    }
  });

  test('the tiebreaker does not disturb the sort that was asked for', () async {
    final stamp = DateTime.utc(2026, 3, 1, 10, 30, 15);
    await seedTiedNotes(3);
    // One note pushed to the front of `updatedDesc`, keeping an id that sorts
    // last — so a page ordered by the tiebreaker alone would put it elsewhere.
    await (db.update(db.notes)..where((n) => n.id.equals('n002'))).write(
      NotesCompanion(updatedAt: Value(stamp.add(const Duration(hours: 1)))),
    );

    expect(
      await page(sortField: NoteSortField.updatedAt, offset: 0),
      ['n002', 'n000', 'n001'],
    );
  });

  test('the ordered page still walks its index', () async {
    await seedTiedNotes(5);

    counter.reset();
    await db.noteDao.getNotesPaginated(
      folderId: folderId,
      limit: 20,
      offset: 0,
      sortField: NoteSortField.position,
      ascending: true,
    );
    final captured = counter.captured.single;

    final plan = await explainCaptured(db, captured);
    expect(
      plan,
      contains(contains('idx_notes_position')),
      reason:
          'the trailing `id` term must not cost the browse query its index; '
          'plan was:\n${plan.join('\n')}',
    );
  });
}
