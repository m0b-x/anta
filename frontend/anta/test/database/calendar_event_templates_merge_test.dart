import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `EventTemplateDao.mergeRemoteTemplate`: the shared contract and a
/// newer template landing column for column.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  EventTemplatesCompanion local(String id) {
    final at = DateTime.utc(2026, 1, 1);
    return EventTemplatesCompanion(
      id: Value(id),
      name: const Value('Push day'),
      category: const Value('gym'),
      createdAt: Value(at),
      updatedAt: Value(at),
    );
  }

  EventTemplateRow remote(String id, String hlc, {bool deleted = false}) {
    return EventTemplateRow(
      id: id,
      name: 'Pulled',
      category: 'climb',
      sortOrder: 2,
      ruleKind: 'weekly',
      rulePayload: '{"weekdays":[1,3]}',
      startMinute: 540,
      durationMinutes: 90,
      description: 'Warm up',
      iconKey: 'bolt',
      colorValue: 0xFF445566,
      tintIcon: false,
      priority: 1,
      retroactive: true,
      countOccurrences: true,
      countStyle: 'ordinal',
      tracksPresence: true,
      assumeAbsent: true,
      perOccurrenceDescriptions: true,
      createdAt: DateTime.utc(2026, 3, 1).toLocal(),
      updatedAt: DateTime.utc(2026, 3, 2).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 3, 3).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  runMergeContract(
    MergeContract<EventTemplateRow>(
      table: 'calendar_event_templates',
      freshKey: 'pulled',
      seedLocal: (db) async {
        await db.eventTemplateDao.upsertTemplate(local('t1'));
        return 't1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.eventTemplateDao.mergeRemoteTemplate(row, floor: floor),
      markerColumn: 'name',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer template overwrites every data column', () async {
    await db.eventTemplateDao.upsertTemplate(local('t1'));

    await db.eventTemplateDao.mergeRemoteTemplate(remote('t1', newerHlc));

    expect(
      await db.select(db.eventTemplates).getSingle(),
      remote('t1', newerHlc),
    );
  });
}
