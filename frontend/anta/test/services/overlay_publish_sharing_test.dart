import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

/// Guard for **5.5**: a single-day mutation republishes by **sharing** every
/// event it did not touch, instead of deep-copying the whole store.
///
/// Two properties have to hold at once, and they pull against each other —
/// which is the whole reason this is worth a test:
///
///   * **sharing** — after touching event A, event B's published collection is
///     `identical` to the instance published before. Value equality proves
///     nothing here: a full deep copy also compares equal, so only identity
///     can tell a shared entry from a rebuilt one.
///   * **immutability** — the invariant the original doc comment states, and
///     the one sharing could plausibly break: a published collection is never
///     mutated in place, so a render path already holding one cannot see it
///     change underneath. Sharing is only safe *because* of this.
///
/// Runs against the real DAOs and the real static facades over an in-memory
/// database, the shape `event_occurrence_service_test.dart` uses — these
/// services have no injection seam below the DAO.
void main() {
  late AppDatabase db;

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    db = await openTestDatabase();
  });

  tearDown(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  group('presence', () {
    test('marking one event leaves the others shared, not rebuilt', () async {
      final service = await EventPresenceService.forTesting(db);
      await service.markMissed('a', DateTime.utc(2026, 1, 1));
      await service.markMissed('b', DateTime.utc(2026, 1, 2));
      await service.markMissed('b', DateTime.utc(2026, 1, 3));

      final untouchedBefore = EventPresence.daysFor('b');
      await service.markMissed('a', DateTime.utc(2026, 1, 5));

      expect(
        identical(EventPresence.daysFor('b'), untouchedBefore),
        isTrue,
        reason: 'b was not touched, so its published set must be reused',
      );
      expect(EventPresence.daysFor('a'), hasLength(2));
    });

    test('the touched event gets a fresh set, never a patched one', () async {
      final service = await EventPresenceService.forTesting(db);
      await service.markMissed('a', DateTime.utc(2026, 1, 1));

      final before = EventPresence.daysFor('a');
      expect(before, hasLength(1));
      await service.markMissed('a', DateTime.utc(2026, 1, 2));

      // The invariant sharing depends on: the snapshot a render path was
      // already reading must still say what it said.
      expect(before, hasLength(1));
      expect(identical(EventPresence.daysFor('a'), before), isFalse);
      expect(EventPresence.daysFor('a'), hasLength(2));
    });

    test('unmarking the last day drops the event and keeps the rest', () async {
      final service = await EventPresenceService.forTesting(db);
      await service.markMissed('a', DateTime.utc(2026, 1, 1));
      await service.markMissed('b', DateTime.utc(2026, 1, 2));

      final untouchedBefore = EventPresence.daysFor('b');
      await service.unmark('a', DateTime.utc(2026, 1, 1));

      expect(EventPresence.daysFor('a'), isEmpty);
      expect(identical(EventPresence.daysFor('b'), untouchedBefore), isTrue);
    });

    test('a published set cannot be mutated by a caller', () async {
      final service = await EventPresenceService.forTesting(db);
      await service.markMissed('a', DateTime.utc(2026, 1, 1));

      expect(
        () => EventPresence.daysFor('a').add(DateTime.utc(2026, 1, 9)),
        throwsUnsupportedError,
      );
    });
  });

  group('skips', () {
    // `markSkipped` clears any absence on the same day through the presence
    // service, so that singleton has to be bound to this database too —
    // otherwise it reaches for the real one, fails, and the defensive catch
    // swallows it, leaving the cross-service half of the mutation untested.
    setUp(() => EventPresenceService.forTesting(db));

    test('skipping one event leaves the others shared', () async {
      final service = await EventSkipService.forTesting(db);
      await service.markSkipped('a', DateTime.utc(2026, 1, 1));
      await service.markSkipped('b', DateTime.utc(2026, 1, 2));

      final untouchedBefore = EventSkips.daysFor('b');
      await service.markSkipped('a', DateTime.utc(2026, 1, 5));

      expect(identical(EventSkips.daysFor('b'), untouchedBefore), isTrue);
      expect(EventSkips.isSkipped('a', DateTime.utc(2026, 1, 5)), isTrue);
    });

    test('an earlier snapshot of the touched event still reads true', () async {
      final service = await EventSkipService.forTesting(db);
      await service.markSkipped('a', DateTime.utc(2026, 1, 1));

      final before = EventSkips.daysFor('a');
      await service.unskip('a', DateTime.utc(2026, 1, 1));

      expect(before, hasLength(1));
      expect(EventSkips.daysFor('a'), isEmpty);
    });
  });

  group('descriptions', () {
    test('writing one event leaves the others shared', () async {
      final service = await EventOccurrenceService.forTesting(db);
      await service.setDescription('a', DateTime.utc(2026, 1, 1), 'squat');
      await service.setDescription('b', DateTime.utc(2026, 1, 2), 'press');

      final untouchedBefore = OccurrenceDescriptions.overridesFor('b');
      await service.setDescription('a', DateTime.utc(2026, 1, 5), 'deadlift');

      expect(
        identical(OccurrenceDescriptions.overridesFor('b'), untouchedBefore),
        isTrue,
      );
      expect(
        OccurrenceDescriptions.overrideFor('a', DateTime.utc(2026, 1, 5)),
        'deadlift',
      );
    });

    test('an earlier snapshot keeps the text it was published with', () async {
      final service = await EventOccurrenceService.forTesting(db);
      await service.setDescription('a', DateTime.utc(2026, 1, 1), 'squat');

      final before = OccurrenceDescriptions.overridesFor('a');
      await service.setDescription('a', DateTime.utc(2026, 1, 1), 'rewritten');

      expect(before[DateTime.utc(2026, 1, 1)], 'squat');
      expect(
        OccurrenceDescriptions.overrideFor('a', DateTime.utc(2026, 1, 1)),
        'rewritten',
      );
    });

    test('clearing the last day drops the event and keeps the rest', () async {
      final service = await EventOccurrenceService.forTesting(db);
      await service.setDescription('a', DateTime.utc(2026, 1, 1), 'squat');
      await service.setDescription('b', DateTime.utc(2026, 1, 2), 'press');

      final untouchedBefore = OccurrenceDescriptions.overridesFor('b');
      await service.clearDescription('a', DateTime.utc(2026, 1, 1));

      expect(OccurrenceDescriptions.hasAnyOverride('a'), isFalse);
      expect(
        identical(OccurrenceDescriptions.overridesFor('b'), untouchedBefore),
        isTrue,
      );
    });

    test('a blanked day stays live — empty is not absent', () async {
      // The documented distinction the sharing must not blur: `''` is a
      // deliberately blank day, `null` is a day with no row.
      final service = await EventOccurrenceService.forTesting(db);
      await service.setDescription('a', DateTime.utc(2026, 1, 1), '');

      expect(
        OccurrenceDescriptions.overrideFor('a', DateTime.utc(2026, 1, 1)),
        '',
      );
      expect(OccurrenceDescriptions.hasAnyOverride('a'), isTrue);
    });
  });
}
