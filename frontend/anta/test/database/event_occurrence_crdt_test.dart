// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards the columns nothing renders — the v28 CRDT block on
/// `calendar_event_occurrences`.
///
/// Per-day description text was the last per-day user data without merge
/// metadata: cloud-sync phase-02 had filed it "device-local", and v28 reverses
/// that because a day's note is user data on par with an absence mark. Every
/// assertion here is invisible from the app — a reset that tombstones and one
/// that hard-deletes both fall back to the template, a version that never
/// increments changes nothing on screen, and a resurrected row draws exactly
/// like a fresh one. They are the properties a merge will depend on, and by
/// then the history they protect is already gone.
void main() {
  late AppDatabase db;

  final day = DateTime.utc(2026, 8, 10);
  final otherDay = DateTime.utc(2026, 8, 11);

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<EventOccurrenceRow> rowFor(String eventId, DateTime value) {
    return (db.select(db.eventOccurrenceDescriptions)
          ..where((o) => o.eventId.equals(eventId) & o.day.equals(value)))
        .getSingle();
  }

  Future<List<EventOccurrenceRow>> allRows() =>
      db.select(db.eventOccurrenceDescriptions).get();

  group('stamping', () {
    test(
      'a first write is a live version-1 row stamped with this device',
      () async {
        await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));

        final row = await rowFor('e1', day);
        expect(row.description, 'squats felt heavy');
        expect(row.version, 1);
        expect(row.isDeleted, isFalse);
        expect(row.deletedAt, isNull);
        // `''` exists only between the v28 ALTER and its backfill. Seeing it come
        // out of a write path means something wrote around the DAO.
        expect(row.hlcTimestamp, isNotEmpty);
        expect(row.deviceId, 'test-device');
      },
    );

    test(
      'an edit bumps the version, keeps createdAt and moves the HLC',
      () async {
        await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
        final before = await rowFor('e1', day);

        await db.eventOccurrenceDao.upsert(
          _entry(day, 'deload next week', createdAt: DateTime.utc(2030, 1, 1)),
        );
        final after = await rowFor('e1', day);

        expect(after.description, 'deload next week');
        expect(after.version, before.version + 1);
        // The whole reason this is not `insertOnConflictUpdate`: the caller's
        // companion always carries a `createdAt`, and it is always wrong.
        expect(after.createdAt, before.createdAt);
        // A version bump with a stale HLC would order two edits arbitrarily.
        expect(after.hlcTimestamp, isNot(before.hlcTimestamp));
        expect(after.deviceId, 'test-device');
      },
    );

    test('an empty description is a row, not an absence of one', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, ''));

      // A deliberately blanked day must not fall back to the template, which
      // is why `''` is stored and reset tombstones instead.
      final row = await rowFor('e1', day);
      expect(row.description, isEmpty);
      expect(row.isDeleted, isFalse);
      expect(await db.eventOccurrenceDao.getActive(), hasLength(1));
    });
  });

  group('reset this day', () {
    test('the row survives as a tombstone and leaves getActive', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      await db.eventOccurrenceDao.upsert(_entry(otherDay, 'easy run'));
      await db.eventOccurrenceDao.tombstone('e1', day);

      final rows = await allRows();
      expect(rows, hasLength(2));
      final dead = await rowFor('e1', day);
      expect(dead.isDeleted, isTrue);
      expect(dead.deletedAt, isNotNull);
      expect(dead.version, 2);
      // The published cache is built from this, so the filter is what makes
      // the day fall back to the template and the badge disappear.
      final active = await db.eventOccurrenceDao.getActive();
      expect(active.map((r) => r.day.millisecondsSinceEpoch), [
        otherDay.millisecondsSinceEpoch,
      ]);
    });

    test('the text is left intact, never blanked', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      await db.eventOccurrenceDao.tombstone('e1', day);

      // Writing `''` would mean "deliberately blank day" to the facade — a
      // different thing entirely, and the invariant v24 shipped.
      expect((await rowFor('e1', day)).description, 'squats felt heavy');
    });

    test('resetting a day that has no row writes nothing', () async {
      await db.eventOccurrenceDao.tombstone('e1', day);
      expect(await allRows(), isEmpty);
    });

    test('resetting twice does not churn the version', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      await db.eventOccurrenceDao.tombstone('e1', day);
      final before = await rowFor('e1', day);
      await db.eventOccurrenceDao.tombstone('e1', day);
      final after = await rowFor('e1', day);

      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test('re-describing a reset day resurrects its original row', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      final original = await rowFor('e1', day);
      await db.eventOccurrenceDao.tombstone('e1', day);

      await db.eventOccurrenceDao.upsert(_entry(day, 'back again'));

      final row = await rowFor('e1', day);
      // Without the explicit `isDeleted: false` on the update branch this row
      // would come back invisible — the same trap the event upsert defuses.
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.description, 'back again');
      expect(row.version, 3);
      expect(row.createdAt, original.createdAt);
      expect(await allRows(), hasLength(1));
      expect(await db.eventOccurrenceDao.getActive(), hasLength(1));
    });
  });

  group('event cascade', () {
    test('tombstones every live day with one shared HLC', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      await db.eventOccurrenceDao.upsert(_entry(otherDay, 'easy run'));
      await db.eventOccurrenceDao.upsert(
        _entry(day, 'other event', eventId: 'e2'),
      );

      await db.eventOccurrenceDao.tombstoneForEvent('e1');

      final rows = await allRows();
      expect(rows, hasLength(3));
      for (final row in rows.where((r) => r.eventId == 'e1')) {
        expect(row.isDeleted, isTrue);
        expect(row.deletedAt, isNotNull);
        expect(row.version, 2);
      }
      // One user action, one point in the merge order — the days died together
      // and must not sort against each other.
      expect(
        rows.where((r) => r.eventId == 'e1').map((r) => r.hlcTimestamp).toSet(),
        hasLength(1),
      );
      final survivor = await rowFor('e2', day);
      expect(survivor.isDeleted, isFalse);
    });

    test('leaves already-tombstoned days alone', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      await db.eventOccurrenceDao.upsert(_entry(otherDay, 'easy run'));
      await db.eventOccurrenceDao.tombstone('e1', otherDay);
      final alreadyDead = await rowFor('e1', otherDay);

      await db.eventOccurrenceDao.tombstoneForEvent('e1');

      // Rewriting a row that was already tombstoned would invent an ordering
      // event out of nothing.
      final untouched = await rowFor('e1', otherDay);
      expect(untouched.version, alreadyDead.version);
      expect(untouched.hlcTimestamp, alreadyDead.hlcTimestamp);
    });

    test('the hard cascade still removes the rows', () async {
      await db.eventOccurrenceDao.upsert(_entry(day, 'squats felt heavy'));
      await db.eventOccurrenceDao.tombstone('e1', day);

      await db.eventOccurrenceDao.deleteForEvent('e1');

      // Retained for the wipe paths, where no parent survives to merge against
      // and a tombstoned child would strand an orphan in every export.
      expect(await allRows(), isEmpty);
    });
  });

  group('import', () {
    test('preserves audit timestamps and stamps fresh identity', () async {
      final createdAt = DateTime(2024, 3, 1, 9, 30);
      final updatedAt = DateTime(2024, 3, 2, 18, 5);
      await db.eventOccurrenceDao.importAll([
        _entry(day, 'restored', createdAt: createdAt, updatedAt: updatedAt),
      ]);

      final row = await rowFor('e1', day);
      // Drift stores unix seconds, so a restored timestamp round-trips to the
      // second, not the millisecond.
      expect(
        row.createdAt.millisecondsSinceEpoch ~/ 1000,
        createdAt.millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        row.updatedAt.millisecondsSinceEpoch ~/ 1000,
        updatedAt.millisecondsSinceEpoch ~/ 1000,
      );
      // A backup is not a sync channel: the restored day is this device's own
      // live row, never a replayed one.
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });
  });
}

EventOccurrenceDescriptionsCompanion _entry(
  DateTime day,
  String description, {
  String eventId = 'e1',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final stamp = createdAt ?? DateTime.utc(2026, 1, 1, 9);
  return EventOccurrenceDescriptionsCompanion.insert(
    eventId: eventId,
    day: day,
    description: description,
    createdAt: stamp,
    updatedAt: updatedAt ?? stamp,
  );
}
