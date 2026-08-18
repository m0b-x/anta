// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real CRDT stamping and the real facade against
/// `NativeDatabase.memory()`, the way the `test/database` suite does.
///
/// Structurally this mirrors the presence suite, because the tables are
/// identical — the assertions that earn their place are the two where skips
/// differ: cancelling a day must clear any absence mark on it, and a leaked
/// facade after a database switch *hides* occurrences rather than merely
/// mis-drawing them.
void main() {
  late AppDatabase db;
  late EventSkipService service;

  final day = DateTime.utc(2026, 8, 10);
  final otherDay = DateTime.utc(2026, 8, 11);

  setUp(() async {
    EventSkipService.reset();
    EventPresenceService.reset();
    db = await openTestDatabase();
    service = await EventSkipService.forTesting(db);
    await EventPresenceService.forTesting(db);
  });

  tearDown(() async {
    EventSkipService.reset();
    EventPresenceService.reset();
    await db.close();
  });

  Future<List<EventSkipRow>> allRows() => db.select(db.eventSkips).get();

  Future<EventSkipRow> rowFor(String eventId, DateTime value) {
    return (db.select(db.eventSkips)..where(
          (s) => s.eventId.equals(eventId) & s.day.equals(value),
        ))
        .getSingle();
  }

  group('marking', () {
    test('a cancelled day publishes to the facade', () async {
      await service.markSkipped('e1', day);

      expect(EventSkips.isSkipped('e1', day), isTrue);
      expect(EventSkips.isSkipped('e1', otherDay), isFalse);
      expect(EventSkips.daysFor('e1'), {day});
    });

    test('a first skip is a live version-1 row', () async {
      await service.markSkipped('e1', day);

      final row = await rowFor('e1', day);
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.hlcTimestamp, isNotEmpty);
      expect(row.deviceId, 'test-device');
    });

    test('cancelling twice does not churn the version', () async {
      await service.markSkipped('e1', day);
      final once = await rowFor('e1', day);

      await service.markSkipped('e1', day);

      expect((await rowFor('e1', day)).version, once.version);
    });

    test('a naive local day normalizes to the same row', () async {
      await service.markSkipped('e1', DateTime(2026, 8, 10, 22, 15));

      expect(EventSkips.isSkipped('e1', day), isTrue);
      expect(await allRows(), hasLength(1));
    });
  });

  group('restoring', () {
    test('tombstones rather than deleting', () async {
      await service.markSkipped('e1', day);

      await service.unskip('e1', day);

      expect(EventSkips.isSkipped('e1', day), isFalse);
      final row = await rowFor('e1', day);
      expect(row.isDeleted, isTrue);
      expect(row.deletedAt, isNotNull);
      expect(row.version, 2);
    });

    test('re-cancelling resurrects the same row', () async {
      await service.markSkipped('e1', day);
      final created = (await rowFor('e1', day)).createdAt;
      await service.unskip('e1', day);

      await service.markSkipped('e1', day);

      final row = await rowFor('e1', day);
      expect(row.isDeleted, isFalse);
      expect(row.createdAt, created);
      expect(await allRows(), hasLength(1));
    });

    test('restoring a day that was never cancelled is a no-op', () async {
      await service.unskip('e1', day);

      expect(await allRows(), isEmpty);
    });
  });

  group('presence interaction', () {
    test('cancelling a day clears its absence mark', () async {
      final presence = await EventPresenceService.getInstance();
      await presence.markMissed('e1', day);
      expect(EventPresence.isMissed('e1', day), isTrue);

      await service.markSkipped('e1', day);

      // An occurrence that does not exist cannot have been missed; leaving the
      // mark would resurface it the moment the skip is undone.
      expect(EventPresence.isMissed('e1', day), isFalse);
    });

    test('an absence on another day survives', () async {
      final presence = await EventPresenceService.getInstance();
      await presence.markMissed('e1', otherDay);

      await service.markSkipped('e1', day);

      expect(EventPresence.isMissed('e1', otherDay), isTrue);
    });
  });

  group('reset', () {
    test('clears the facade so another database cannot hide days', () async {
      await service.markSkipped('e1', day);

      EventSkipService.reset();

      expect(EventSkips.isSkipped('e1', day), isFalse);
    });
  });

  group('backup', () {
    test('export/import round-trips live skips only', () async {
      await service.markSkipped('e1', day);
      await service.markSkipped('e1', otherDay);
      await service.unskip('e1', otherDay);
      final exported = await service.exportData();

      expect(exported, hasLength(1));

      await service.clearAllForImport();
      expect(EventSkips.daysFor('e1'), isEmpty);
      await service.importData(exported);

      expect(EventSkips.daysFor('e1'), {day});
    });

    test('import stamps fresh identity, never the backup\'s', () async {
      await service.importData([
        {'eventId': 'e1', 'dayMs': day.millisecondsSinceEpoch},
      ]);

      final row = await rowFor('e1', day);
      expect(row.deviceId, 'test-device');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
    });

    test('a malformed row is skipped and the rest still imports', () async {
      await service.importData([
        'not a map',
        {'eventId': 'e1'},
        {'eventId': 'e2', 'dayMs': day.millisecondsSinceEpoch},
      ]);

      expect(EventSkips.daysFor('e1'), isEmpty);
      expect(EventSkips.daysFor('e2'), {day});
    });
  });
}
