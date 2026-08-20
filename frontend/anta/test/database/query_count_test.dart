import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/daos/note_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards that operations stay **O(1) in statements**, not O(rows).
///
/// A query in a loop is what actually makes a local-SQLite app feel slow —
/// each individual statement looks fine in a profile and in a query plan, and
/// only the count gives it away. These assertions are hardware-independent for
/// the same reason the query-plan ones are: they count work, not time.
void main() {
  late StatementCounter counter;
  late AppDatabase db;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    await _seedNotes(db, 60);
  });
  tearDown(() async => db.close());

  test('resolving many notes by id is a single IN query', () async {
    final ids = [for (var i = 0; i < 50; i++) 'n$i'];
    counter.reset();
    final notes = await db.noteDao.getNotesByIds(ids);

    expect(notes, hasLength(50));
    expect(
      counter.count,
      1,
      reason:
          'getNotesByIds must stay one `WHERE id IN (…)` query. The calendar '
          'resolves linked notes through it, and rewriting it as a loop would '
          'be invisible in a query plan: 50 fast statements still beat one. '
          'Issued:\n${counter.statements.join('\n')}',
    );
  });

  test('an empty id list touches the database not at all', () async {
    counter.reset();
    await db.noteDao.getNotesByIds(const []);
    expect(counter.count, 0);
  });

  test('listing a folder page is a constant number of statements', () async {
    counter.reset();
    await db.noteDao.getNotesPaginated(
      folderId: _folderId,
      limit: 50,
      offset: 0,
      sortField: NoteSortField.position,
      ascending: true,
    );
    // One SELECT for the page. Anything more means per-row work crept in.
    expect(
      counter.count,
      1,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  test('note count does not read the rows it counts', () async {
    counter.reset();
    final total = await db.noteDao.getNoteCount(_folderId);
    expect(total, 60);
    expect(counter.count, 1);
    expect(
      counter.statements.single.toUpperCase(),
      contains('COUNT('),
      reason: 'counting must stay a COUNT(*), never a fetch-and-length',
    );
  });

  test('reordering never reads a row to write it', () async {
    final positions = {for (var i = 0; i < 50; i++) 'n$i': 50 - i};
    counter.reset();
    await db.noteDao.setNotePositions(positions);

    // One UPDATE per note is inherent — each row gets a different position.
    // What is *not* inherent is a SELECT per note, which is what this had:
    // 100 statements for 50 rows, purely to read `version` so it could write
    // `version + 1`. SQL can do that arithmetic itself.
    expect(
      counter.matching('SELECT'),
      isEmpty,
      reason:
          'reorder must not read each row before writing it. Issued:\n'
          '${counter.statements.take(6).join('\n')}',
    );
    expect(counter.count, lessThanOrEqualTo(positions.length));
  });

  test('reordering still bumps the CRDT version of each moved row', () async {
    final before = await db.noteDao.getNoteById('n0');
    await db.noteDao.setNotePositions({'n0': 99});
    final after = await db.noteDao.getNoteById('n0');

    expect(after!.position, 99);
    // The whole reason the old code read the row first. Doing it in SQL must
    // not quietly drop the increment.
    expect(after.version, before!.version + 1);
    expect(after.deviceId, db.deviceId);
  });

  test('reordering an unknown id is a no-op, not an insert', () async {
    final countBefore = await db.noteDao.getNoteCount(_folderId);
    await db.noteDao.setNotePositions({'does-not-exist': 1});
    expect(await db.noteDao.getNoteCount(_folderId), countBefore);
  });

  test('deleting an event cascades in one statement per table', () async {
    await db.calendarEventDao.upsert(_event('e1'));
    for (var i = 0; i < 20; i++) {
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: DateTime.utc(2026, 1, i + 1),
          description: 'day $i',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    for (var i = 0; i < 20; i++) {
      await db.eventAbsenceDao.markMissed('e1', DateTime.utc(2026, 1, i + 1));
    }
    // An already-tombstoned child must not be rewritten by the cascade, or a
    // repeated delete churns versions the merge reads as ordering events.
    await db.eventAbsenceDao.unmark('e1', DateTime.utc(2026, 1, 1));
    await db.eventOccurrenceDao.tombstone('e1', DateTime.utc(2026, 1, 1));

    counter.reset();
    await db.calendarEventDao.softDeleteById('e1');
    await db.eventAbsenceDao.tombstoneForEvent('e1');
    await db.eventOccurrenceDao.tombstoneForEvent('e1');

    // The parent is read-then-write (it needs `version + 1` for exactly one
    // row); everything below it is a single set-based statement covering every
    // row, not one per materialized day. Since v28 both children tombstone,
    // so "one statement per table" is now an UPDATE on each.
    expect(
      counter.matching('calendar_events'),
      hasLength(2),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(
      [
        for (final s in counter.selects)
          if (s.sql.contains('calendar_events')) s,
      ],
      hasLength(1),
      reason:
          'the single SELECT is the intended read; a second one means the '
          'cascade started reading rows it could have updated in SQL. '
          'Issued:\n${counter.statements.join('\n')}',
    );
    expect(
      counter.matching('calendar_event_occurrences'),
      hasLength(1),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(
      counter.matching('calendar_event_absences'),
      hasLength(1),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  test('reassigning a category is one statement whatever the row count', () async {
    for (var i = 0; i < 20; i++) {
      await db.calendarEventDao.upsert(_event('e$i'));
    }

    counter.reset();
    final moved = await db.calendarEventDao.reassignCategory('gym', 'other');

    expect(moved, 20);
    // Deleting a category can touch an unbounded number of events, so this one
    // cannot read-then-write: the version bump has to happen in SQL. Forgetting
    // the stamping entirely would break nothing visible today and corrupt merge
    // ordering the moment transport exists — that is what this pins.
    expect(
      counter.count,
      1,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  test('an upsert reads the row it overwrites exactly once', () async {
    counter.reset();
    await db.calendarEventDao.upsert(_event('e1'));
    // SELECT (miss) + INSERT. The extra read is the price of `version 1` vs
    // `version + 1`, paid on a table that writes at human speed.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );

    counter.reset();
    await db.calendarEventDao.upsert(_event('e1'));
    // SELECT (hit) + UPDATE — never a blind UPDATE-then-INSERT, which would be
    // two writes and could not compute the version bump.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(counter.selects, hasLength(1));
  });

  test('an occurrence upsert reads the row it overwrites exactly once', () async {
    counter.reset();
    await db.eventOccurrenceDao.upsert(_occurrence(1));
    // SELECT (miss) + INSERT. The extra read is the price of `version 1` vs
    // `version + 1` and of keeping `created_at` when a reset day is
    // re-described, paid on a table that writes at human speed.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );

    counter.reset();
    await db.eventOccurrenceDao.upsert(_occurrence(1));
    // SELECT (hit) + UPDATE — never a blind UPDATE-then-INSERT, which could not
    // compute the version bump.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(counter.selects, hasLength(1));
  });
}

EventOccurrenceDescriptionsCompanion _occurrence(int day) {
  return EventOccurrenceDescriptionsCompanion.insert(
    eventId: 'e1',
    day: DateTime.utc(2026, 1, day),
    description: 'day $day',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

CalendarEventsCompanion _event(String id) {
  return CalendarEventsCompanion.insert(
    id: id,
    title: 'Leg day',
    category: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    ruleKind: 'daily',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

const _folderId = 'f1';

Future<void> _seedNotes(AppDatabase db, int count) async {
  final now = DateTime.now();
  await db.batch((batch) {
    batch.insert(
      db.folders,
      FoldersCompanion.insert(
        id: _folderId,
        name: 'Bench',
        hlcTimestamp: '0',
        deviceId: 'test',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (var i = 0; i < count; i++) {
      batch.insert(
        db.notes,
        NotesCompanion.insert(
          id: 'n$i',
          folderId: _folderId,
          title: 'Note $i',
          hlcTimestamp: '0',
          deviceId: 'test',
          createdAt: now,
          updatedAt: now,
          position: Value(i),
        ),
      );
    }
  });
}
