import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `FilterPresetDao.mergeRemotePreset`: the shared contract and the
/// filter blob landing verbatim, a field this build does not know included.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  const filters = '{"trackedOnly":true,"fromTheFuture":[1,2]}';

  CalendarFilterPresetRow remote(
    String id,
    String hlc, {
    bool deleted = false,
  }) {
    return CalendarFilterPresetRow(
      id: id,
      name: 'Pulled',
      filters: filters,
      sortOrder: 5,
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

  Future<void> seed() => db.filterPresetDao.upsertPreset(
    const CalendarFilterPresetsCompanion(
      id: Value('p1'),
      name: Value('Saved'),
      filters: Value('{}'),
    ),
  );

  runMergeContract(
    MergeContract<CalendarFilterPresetRow>(
      table: 'calendar_filter_presets',
      freshKey: 'pulled',
      seedLocal: (_) async {
        await seed();
        return 'p1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.filterPresetDao.mergeRemotePreset(row, floor: floor),
      markerColumn: 'filters',
      markerValue: filters,
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer preset lands every column, its blob verbatim', () async {
    await seed();

    await db.filterPresetDao.mergeRemotePreset(remote('p1', newerHlc));

    expect(
      await db.select(db.calendarFilterPresets).getSingle(),
      remote('p1', newerHlc),
    );
  });
}
