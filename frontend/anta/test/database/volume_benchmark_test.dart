@Tags(['benchmark'])
library;

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/daos/note_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/recurrence_rule_codec.dart';

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
/// flutter test --tags benchmark --run-skipped
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

  for (final eventCount in [200, 2000]) {
    group('$eventCount calendar events over five years', () {
      late AppDatabase db;

      setUpAll(() async {
        db = await openTestDatabase();
        await _seedCalendar(db, eventCount: eventCount);
      });
      tearDownAll(() async => db.close());

      test('calendar reads at volume', () async {
        // ignore: avoid_print
        print('\n=== $eventCount calendar events ===');

        final eventsElapsed = await _time(() => db.calendarEventDao.getAll());
        final events = await db.calendarEventDao.getAll();
        // ignore: avoid_print
        print(
          '  events        ${eventsElapsed.toString().padLeft(5)}us  '
          '(${events.length} rows)',
        );
        expect(eventsElapsed, lessThan(2000000));

        final descriptionBytes = events.fold<int>(
          0,
          (sum, row) => sum + (row.description?.length ?? 0),
        );
        // ignore: avoid_print
        print('  description bytes  $descriptionBytes');

        // Both shapes, deliberately. `getActiveKeys()` is what the services'
        // `_load` actually calls and what the partial indexes cover;
        // `getActive()` is the wider read backup export still needs. Timing
        // only the latter would leave a `_load` regression — or a dropped
        // index — invisible here.
        final skipKeysElapsed = await _time(
          () => db.eventSkipDao.getActiveKeys(),
        );
        // ignore: avoid_print
        print('  skip keys     ${skipKeysElapsed.toString().padLeft(5)}us');
        expect(skipKeysElapsed, lessThan(2000000));

        final skipsElapsed = await _time(() => db.eventSkipDao.getActive());
        // ignore: avoid_print
        print('  skips         ${skipsElapsed.toString().padLeft(5)}us');
        expect(skipsElapsed, lessThan(2000000));

        final absenceKeysElapsed = await _time(
          () => db.eventAbsenceDao.getActiveKeys(),
        );
        // ignore: avoid_print
        print('  absence keys  ${absenceKeysElapsed.toString().padLeft(5)}us');
        expect(absenceKeysElapsed, lessThan(2000000));

        final absencesElapsed = await _time(
          () => db.eventAbsenceDao.getActive(),
        );
        // ignore: avoid_print
        print('  absences      ${absencesElapsed.toString().padLeft(5)}us');
        expect(absencesElapsed, lessThan(2000000));

        final occurrencesElapsed = await _time(
          () => db.eventOccurrenceDao.getActive(),
        );
        // ignore: avoid_print
        print('  occurrences   ${occurrencesElapsed.toString().padLeft(5)}us');
        expect(occurrencesElapsed, lessThan(2000000));
      });
    });
  }
}

const _folderId = 'bench-folder';

/// One instance of every [RecurrenceRule] kind [RecurrenceCodec] knows,
/// cycled with `i % _recurrenceRules.length` so the seed exercises every
/// `rule_kind` / `rule_payload` shape the app can actually produce.
final _recurrenceRules = <RecurrenceRule>[
  const OneTimeRecurrence(),
  SpecificDatesRecurrence(
    dates: {
      DateTime.utc(2022, 3, 1),
      DateTime.utc(2022, 6, 1),
      DateTime.utc(2022, 9, 1),
    },
  ),
  const DailyRecurrence(),
  const WeeklyRecurrence(weekdays: {1, 3, 5}),
  const MonthlyRecurrence(),
  const YearlyRecurrence(),
  const WorkdaysRecurrence(),
  const WeekendsRecurrence(),
  const PublicHolidaysOnlyRecurrence(),
];

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
}

/// Seeds [eventCount] calendar events spread over five years, each carrying a
/// mix of skip / absence / occurrence-description deltas — and, deliberately,
/// the ~10% tombstone ratio a real five-year install accumulates, since this
/// app never collects them (`isDeleted` rows are filtered, never deleted).
Future<void> _seedCalendar(AppDatabase db, {required int eventCount}) async {
  final now = DateTime.now();
  final eventEpoch = DateTime.utc(now.year - 5, 1, 1);
  var deltaIndex = 0;
  await db.batch((batch) {
    for (var i = 0; i < eventCount; i++) {
      final eventId = 'bench-event-$i';
      final rule = _recurrenceRules[i % _recurrenceRules.length];
      final startDate = eventEpoch.add(Duration(days: i % 1825));
      batch.insert(
        db.calendarEvents,
        CalendarEventsCompanion.insert(
          id: eventId,
          title: 'Event $i',
          category: 'category-${i % 6}',
          startDate: startDate,
          ruleKind: RecurrenceCodec.kindOf(rule),
          rulePayload: Value(RecurrenceCodec.payloadOf(rule)),
          description: Value('x' * (80 + i % 400)),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final deltaCount = 3 + i % 5;
      for (var j = 0; j < deltaCount; j++) {
        final day = startDate.add(Duration(days: (j + 1) * 41));
        final isDeleted = deltaIndex % 10 == 0
            ? const Value(true)
            : const Value<bool>.absent();
        switch (deltaIndex % 3) {
          case 0:
            batch.insert(
              db.eventSkips,
              EventSkipsCompanion.insert(
                eventId: eventId,
                day: day,
                createdAt: now,
                updatedAt: now,
                hlcTimestamp: '0',
                deviceId: 'bench',
                isDeleted: isDeleted,
              ),
            );
          case 1:
            batch.insert(
              db.eventAbsences,
              EventAbsencesCompanion.insert(
                eventId: eventId,
                day: day,
                createdAt: now,
                updatedAt: now,
                hlcTimestamp: '0',
                deviceId: 'bench',
                isDeleted: isDeleted,
              ),
            );
          default:
            batch.insert(
              db.eventOccurrenceDescriptions,
              EventOccurrenceDescriptionsCompanion.insert(
                eventId: eventId,
                day: day,
                description: 'override $j for $eventId',
                createdAt: now,
                updatedAt: now,
                isDeleted: isDeleted,
              ),
            );
        }
        deltaIndex++;
      }
    }
  });
}
