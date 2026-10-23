// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/services/counter_service.dart';

import '../database/support/db_test_support.dart';

/// Guards what the debounced flush writes, now that every write stamps an HLC
/// (**v43**): a write that changes nothing would read as a change once devices
/// merge, and a write landing after a delete would bring the counter's values
/// back.
void main() {
  late AppDatabase db;
  late CounterService service;

  setUp(() async {
    db = await openTestDatabase();
    service = await CounterService.forTesting(db);
  });
  tearDown(() async {
    await service.flush();
    await db.close();
  });

  Future<Map<String, int>> versions(String noteId) async {
    final rows = await (db.select(
      db.counterValues,
    )..where((v) => v.noteId.equals(noteId))).get();
    return {for (final r in rows) r.counterId: r.version};
  }

  test('a flush writes only the per-note value that changed', () async {
    final ids = [
      for (var i = 0; i < 5; i++)
        await service.addCounter(name: 'C$i', scope: CounterScope.perNote),
    ];
    for (final id in ids) {
      await service.increment(id, noteId: 'n1');
    }
    await service.flush();
    final before = await versions('n1');
    expect(before, hasLength(5));

    await service.increment(ids[2], noteId: 'n1');
    await service.flush();

    final after = await versions('n1');
    final moved = [
      for (final id in ids)
        if (after[id] != before[id]) id,
    ];
    expect(moved, [ids[2]]);
  });

  test(
    'resetting a global counter already at its start writes nothing',
    () async {
      final id = await service.addCounter(name: 'Sets', startValue: 3);
      final before = (await versions(''))[id];

      await service.resetGlobal(id);
      await service.flush();

      expect((await versions(''))[id], before);
    },
  );

  test(
    'a flush pending when the counter is deleted leaves no live value',
    () async {
      final id = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await service.increment(id, noteId: 'n1');
      await service.incrementGlobal(id);

      await service.deleteCounter(id);
      await service.flush();

      final live =
          await (db.select(db.counterValues)..where(
                (v) => v.counterId.equals(id) & v.isDeleted.equals(false),
              ))
              .get();
      expect(live, isEmpty);
    },
  );
}
