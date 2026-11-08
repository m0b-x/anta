// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/tables/counter_values_binding.dart';
import 'package:anta/services/sync/tables/counters_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import 'support/sync_pair.dart';

/// Two devices through the engine and the fake space (scalability record
/// S20, D8 A): taps made offline on both add up once each has synced, the
/// devices then settle with nothing left to push, a note deleted on one
/// takes its counter values with it on the other, and the sweep of a merged
/// delete runs only after a complete pull and never outranks a value written
/// after the delete.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  Future<int?> valueOn(SyncDevice device, [String noteId = '']) async {
    final row =
        await (device.db.select(
              device.db.counterValues,
            )..where((v) => v.counterId.equals('c1') & v.noteId.equals(noteId)))
            .getSingleOrNull();
    return row == null || row.isDeleted ? null : row.value;
  }

  Future<void> tap(SyncDevice device, int delta, [String noteId = '']) => device
      .db
      .counterDao
      .applyCount('c1', noteId, delta: delta, startValue: 0);

  Future<void> shareCounter() async {
    await a().db.counterDao.insertCounterWithValue(
      CountersCompanion(
        id: const Value('c1'),
        name: const Value('Sets'),
        createdAt: Value(DateTime.utc(2026, 11, 1)),
      ),
      0,
    );
    await a().sync();
    await b().sync();
    expect(await valueOn(b()), 0);
  }

  test('taps made offline on two devices add up after both sync', () async {
    await shareCounter();
    await tap(a(), 2);
    await tap(b(), 3);
    await tap(b(), -1);

    await a().sync();
    await b().sync();
    await a().sync();

    expect(await valueOn(a()), 4);
    expect(await valueOn(b()), 4);
    expect(await a().db.syncOutboxDao.count(), 0);
    expect(await b().db.syncOutboxDao.count(), 0);

    await b().sync();
    await a().sync();

    expect(await valueOn(a()), 4);
    expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));
  });

  test('a note deleted on one device takes its values on the other', () async {
    await shareCounter();
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    final note = await a().db.noteDao.createNote(
      folderId: folder.id,
      title: 'Day',
    );
    await tap(a(), 5, note.id);
    await a().sync();
    await b().sync();
    expect(await valueOn(b(), note.id), 5);

    await a().db.noteDao.softDeleteNote(note.id);
    await a().sync();
    await b().sync();

    expect(await valueOn(b(), note.id), isNull);
    expect(await valueOn(b()), 0, reason: 'the global value stays');
    expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));
  });

  /// A note on both devices holding a value of 5.
  Future<String> sharedNote() async {
    await shareCounter();
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    final note = await a().db.noteDao.createNote(
      folderId: folder.id,
      title: 'Day',
    );
    await tap(a(), 5, note.id);
    await a().sync();
    await b().sync();
    expect(await valueOn(b(), note.id), 5);
    return note.id;
  }

  test('a value tapped after the delete, on a note a newer edit brings back, '
      'survives the sweep on both devices (review F1)', () async {
    final noteId = await sharedNote();
    await b().db.noteDao.softDeleteNote(noteId);
    // A, unaware of the delete, edits the note and taps on.
    await a().db.noteDao.updateNote(id: noteId, title: 'Day edited');
    await tap(a(), 1, noteId);
    await a().sync();
    // A's value reaches B before A's note edit does — the order within one
    // run when the edit lands between the two tables' pulls — and a sweep
    // runs there.
    const binding = CounterValuesBinding();
    final row =
        await (a().db.select(
              a().db.counterValues,
            )..where((v) => v.counterId.equals('c1') & v.noteId.equals(noteId)))
            .getSingle();
    await binding.mergeRemote(
      b().db,
      await binding.encode(a().db, row, boundUid: syncUid),
    );
    expect(await b().db.counterDao.sweepOrphanValues(), isEmpty);

    await b().sync();
    await a().sync();
    await b().sync();

    for (final device in [a(), b()]) {
      expect((await device.db.noteDao.getNoteById(noteId))!.isDeleted, isFalse);
      expect(await valueOn(device, noteId), 6, reason: device.id);
    }
  });

  /// [noteId] deleted on A the way an older build deletes it: the note's
  /// tombstone alone, queued, its values left live.
  Future<String> deleteWithoutCascade(String noteId) async {
    final stamp = a().db.newStamp();
    await a().db.transaction(() async {
      await a().db.customStatement(
        'UPDATE notes SET is_deleted = 1, hlc_timestamp = ?, device_id = ? '
        'WHERE id = ?',
        [stamp.hlc, stamp.deviceId, noteId],
      );
      await a().db.enqueue(
        a().db.notes,
        noteId,
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
    });
    return stamp.hlc;
  }

  test(
    'a complete run sweeps the values of a note deleted elsewhere, under '
    'the note\'s own stamp, and the sweep reaches the other device',
    () async {
      final noteId = await sharedNote();
      final deletedAt = await deleteWithoutCascade(noteId);
      await a().sync();

      await b().sync();

      final swept =
          await (b().db.select(b().db.counterValues)..where(
                (v) => v.counterId.equals('c1') & v.noteId.equals(noteId),
              ))
              .getSingle();
      expect(swept.isDeleted, isTrue);
      expect(swept.hlcTimestamp, deletedAt);
      expect(b().hooks.calls, contains('after:counter_values'));

      await a().sync();
      expect(await valueOn(a(), noteId), isNull);
    },
  );

  test('a run that stops short of a complete pull, the initial merge\'s '
      'included, sweeps nothing until a complete one', () async {
    final noteId = await sharedNote();
    await deleteWithoutCascade(noteId);
    // A page after the notes, so the note's tombstone has landed.
    await a().db.counterDao.insertCounter(
      CountersCompanion(
        id: const Value('c2'),
        name: const Value('Laps'),
        createdAt: Value(DateTime.utc(2026, 11, 2)),
      ),
    );
    // Planted rather than pushed: A's own run would sweep A's value and push
    // its tombstone, and B would merge that instead of sweeping.
    final note = (await a().db.noteDao.getNoteById(noteId))!;
    final counter = (await a().db.counterDao.getAllCounters()).singleWhere(
      (c) => c.id == 'c2',
    );
    pair.gateway
      ..plant(
        pair.space,
        await const NotesBinding().encode(a().db, note, boundUid: syncUid),
      )
      ..plant(
        pair.space,
        await const CountersBinding().encode(
          a().db,
          counter,
          boundUid: syncUid,
        ),
      );
    await b().db.syncDao.setValue(SyncDao.keyBindMergePending, '1');
    b().hooks.onBeforePage = (table) async {
      if (table == 'counters') throw StateError('a page that fails');
    };

    await b().sync();

    expect((await b().db.noteDao.getNoteById(noteId))!.isDeleted, isTrue);
    expect(await valueOn(b(), noteId), 5);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
      isNotNull,
    );

    b().hooks.onBeforePage = null;
    await b().sync();

    expect(await b().db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
    expect(await valueOn(b(), noteId), isNull);
  });

  test('a complete run that pulls nothing still sweeps a note tombstone an '
      'earlier run left (re-review N2)', () async {
    final noteId = await sharedNote();
    // A tombstone an incomplete run merged: the note's alone, above the
    // value's stamp, the values left live.
    final later = b().db.newStamp();
    await b().db.customStatement(
      'UPDATE notes SET is_deleted = 1, hlc_timestamp = ? WHERE id = ?',
      [later.hlc, noteId],
    );
    expect(await valueOn(b(), noteId), 5);

    final report = await b().sync();

    expect(report.pulledRows, 0);
    expect(await valueOn(b(), noteId), isNull);
  });
}
