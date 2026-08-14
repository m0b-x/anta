@Tags(['benchmark'])
library;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/daos/note_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Seeded-volume timings for the queries the app leans on.
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) because wall-clock numbers are not a pass/fail signal:
/// they move with background load, thermal state and debug-vs-release, and a
/// threshold tuned to survive that is a threshold that catches nothing. Run it
/// deliberately when you want the numbers:
///
/// ```powershell
/// flutter test --tags benchmark
/// ```
///
/// The assertions here are catastrophe-only — they catch an accidental O(n²),
/// not a 30% regression. Read the printed table for the real signal.
void main() {
  for (final noteCount in [500, 5000]) {
    group('$noteCount notes in one folder', () {
      late AppDatabase db;

      setUpAll(() async {
        db = await openTestDatabase();
        await _seed(db, noteCount: noteCount);
      });
      tearDownAll(() async => db.close());

      test('sorted folder listing, every sort order', () async {
        // ignore: avoid_print
        print('\n=== $noteCount notes ===');
        for (final field in NoteSortField.values) {
          final elapsed = await _time(
            () => db.noteDao.getNotesPaginated(
              folderId: _folderId,
              limit: 50,
              offset: 0,
              sortField: field,
              ascending: field != NoteSortField.updatedAt,
            ),
          );
          final plan = await queryPlan(
            db,
            'SELECT * FROM notes WHERE folder_id = ? AND is_deleted = 0 '
            'ORDER BY ${_column(field)} LIMIT 50',
            [Variable<String>(_folderId)],
          );
          final sorts = plan.any((l) => l.contains('USE TEMP B-TREE'));
          // ignore: avoid_print
          print(
            '  sort=${field.name.padRight(10)} '
            '${elapsed.toString().padLeft(5)}us  '
            '${sorts ? 'TEMP B-TREE' : 'index order'}',
          );
          expect(
            elapsed,
            lessThan(2000000),
            reason: 'catastrophic regression sorting by ${field.name}',
          );
        }
      });

      test('title uniqueness check stays flat', () async {
        final elapsed = await _time(
          () => db.noteDao.noteTitleExistsInFolder(
            folderId: _folderId,
            title: 'Session 400',
          ),
        );
        // ignore: avoid_print
        print('  uniqueness  ${elapsed.toString().padLeft(5)}us');
        expect(elapsed, lessThan(2000000));
      });

      test('deep pagination does not degrade', () async {
        final first = await _time(
          () => db.noteDao.getNotesPaginated(
            folderId: _folderId,
            limit: 50,
            offset: 0,
            sortField: NoteSortField.position,
            ascending: true,
          ),
        );
        final deep = await _time(
          () => db.noteDao.getNotesPaginated(
            folderId: _folderId,
            limit: 50,
            offset: noteCount - 50,
            sortField: NoteSortField.position,
            ascending: true,
          ),
        );
        // ignore: avoid_print
        print('  page first=${first}us  last=${deep}us');
        expect(deep, lessThan(2000000));
      });
    });
  }
}

const _folderId = 'bench-folder';

String _column(NoteSortField field) => switch (field) {
  NoteSortField.title => '"title" ASC',
  NoteSortField.createdAt => '"created_at" ASC',
  NoteSortField.updatedAt => '"updated_at" DESC',
  NoteSortField.position => '"position" ASC',
};

/// Microseconds for [operation], best of three so a single GC pause or a
/// cold page cache does not become the headline number.
Future<int> _time(Future<void> Function() operation) async {
  var best = 1 << 62;
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    await operation();
    sw.stop();
    if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
  }
  return best;
}

Future<void> _seed(AppDatabase db, {required int noteCount}) async {
  final now = DateTime.now();
  await db.batch((batch) {
    batch.insert(
      db.folders,
      FoldersCompanion.insert(
        id: _folderId,
        name: 'Bench',
        hlcTimestamp: '0',
        deviceId: 'bench',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (var i = 0; i < noteCount; i++) {
      batch.insert(
        db.notes,
        NotesCompanion.insert(
          id: 'bench-note-$i',
          folderId: _folderId,
          title: 'Session ${noteCount - i}',
          hlcTimestamp: '0',
          deviceId: 'bench',
          createdAt: now.subtract(Duration(minutes: i)),
          updatedAt: now.subtract(Duration(minutes: i)),
          position: Value(i),
        ),
      );
    }
  });
  await db.customStatement('ANALYZE');
}
