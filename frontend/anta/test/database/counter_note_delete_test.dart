// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards that a per-note counter value dies with its note (scalability
/// record S20, Part B): every local note delete tombstones the note's live
/// values in its own transaction and under its own stamp, a flush that
/// arrives after the note went writes nothing, and the sweep tombstones the
/// values of notes a pull deleted, and nothing else.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  Future<CounterValueRow?> valueOf(String counterId, String noteId) {
    return (db.select(db.counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .getSingleOrNull();
  }

  Future<Note> noteRow(String id) =>
      (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

  Future<String?> queued(String rowKey) async {
    final row =
        await (db.select(db.syncOutbox)..where(
              (o) =>
                  o.syncedTable.equals('counter_values') &
                  o.rowKey.equals(rowKey),
            ))
            .getSingleOrNull();
    return row == null ? null : '${row.op}@${row.hlc}';
  }

  /// A live note holding a per-note value of `reps` and `laps`, beside the
  /// global value of `reps`.
  Future<String> noteWithValues(String folderId) async {
    final note = await db.noteDao.createNote(
      folderId: folderId,
      title: 'Session',
      preview: 'squat',
    );
    await db.counterDao.upsertValue('reps', note.id, 5);
    await db.counterDao.upsertValue('laps', note.id, 2);
    await db.counterDao.upsertValue('reps', '', 40);
    return note.id;
  }

  Future<void> expectDiedWith(String noteId) async {
    final note = await noteRow(noteId);
    expect(note.isDeleted, isTrue);
    for (final counterId in ['reps', 'laps']) {
      final value = (await valueOf(counterId, noteId))!;
      expect(value.isDeleted, isTrue, reason: counterId);
      expect(value.hlcTimestamp, note.hlcTimestamp, reason: 'one stamp');
      expect(value.deletedAt, note.deletedAt);
      expect(value.version, 2);
      expect(
        await queued(counterValueRowKey(counterId, noteId)),
        'tombstone@${note.hlcTimestamp}',
      );
    }
    expect((await valueOf('reps', ''))!.isDeleted, isFalse);
  }

  Future<String> folder() async =>
      (await db.folderDao.createFolder(name: 'Training')).id;

  test('a single note delete tombstones its values with it', () async {
    final noteId = await noteWithValues(await folder());

    await db.noteDao.softDeleteNote(noteId);

    await expectDiedWith(noteId);
  });

  test('a selection delete tombstones every picked note\'s values', () async {
    final folderId = await folder();
    final first = await noteWithValues(folderId);
    final second = await noteWithValues(folderId);
    final kept = await noteWithValues(folderId);

    await db.noteDao.softDeleteNotesWithChunks([first, second]);

    await expectDiedWith(first);
    await expectDiedWith(second);
    expect((await valueOf('reps', kept))!.isDeleted, isFalse);
  });

  test(
    'a folder delete tombstones the values of every note under it',
    () async {
      final parent = await folder();
      final child = (await db.folderDao.createFolder(
        name: 'Legs',
        parentId: parent,
      )).id;
      final top = await noteWithValues(parent);
      final nested = await noteWithValues(child);
      final elsewhere = await noteWithValues(await folder());

      await db.folderDao.softDeleteFolderWithDescendants(parent);

      await expectDiedWith(top);
      await expectDiedWith(nested);
      expect((await valueOf('reps', elsewhere))!.isDeleted, isFalse);
    },
  );

  test('a repeated delete re-stamps no value', () async {
    final noteId = await noteWithValues(await folder());
    await db.noteDao.softDeleteNote(noteId);
    final before = await valueOf('reps', noteId);

    await db.noteDao.softDeleteNotesWithChunks([noteId]);

    expect(await valueOf('reps', noteId), before);
  });

  test('the cascade over 33,000 notes binds one stamp, under SQLite\'s '
      'variable limit', () async {
    const count = 33000;
    final now = DateTime.now();
    await db.batch((batch) {
      batch.insert(
        db.folders,
        FoldersCompanion.insert(
          id: 'big',
          name: 'Big',
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
            folderId: 'big',
            title: 'Note $i',
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: now,
            updatedAt: now,
          ),
        );
        batch.insert(
          db.counterValues,
          CounterValuesCompanion.insert(
            counterId: 'reps',
            noteId: Value('n$i'),
            value: i,
          ),
        );
      }
    });
    // The notes as the delete leaves them, tombstoned under one stamp.
    final stamp = db.newStamp();
    await db.customStatement(
      'UPDATE notes SET is_deleted = 1, hlc_timestamp = ?',
      [stamp.hlc],
    );
    statements.reset();

    await db.transaction(
      () => db.counterDao.tombstoneValuesOfDeletedNotes(stamp, now),
    );

    final cascade = statements.captured.singleWhere(
      (c) => c.sql.startsWith('UPDATE counter_values'),
    );
    expect(cascade.args, hasLength(4));
    final live = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM counter_values WHERE is_deleted = 0',
        )
        .getSingle();
    expect(live.read<int>('n'), 0);
    final queuedCount = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM sync_outbox '
          "WHERE table_name = 'counter_values' AND op = 'tombstone'",
        )
        .getSingle();
    expect(queuedCount.read<int>('n'), count);
  });

  test('a flush after the note was tombstoned writes nothing', () async {
    final noteId = await noteWithValues(await folder());
    await db.noteDao.softDeleteNote(noteId);
    final tombstone = await valueOf('reps', noteId);
    statements.reset();

    final tapped = await db.counterDao.applyCount(
      'reps',
      noteId,
      delta: 3,
      startValue: 0,
    );
    await db.counterDao.upsertValue('fresh', noteId, 9);

    expect(tapped, isNull);
    expect(statements.captured.where((c) => !c.isSelect), isEmpty);
    expect(await valueOf('reps', noteId), tombstone);
    expect(await valueOf('fresh', noteId), isNull);
  });

  test('a value under a note not stored yet is still written', () async {
    expect(
      await db.counterDao.applyCount(
        'reps',
        'note-being-created',
        delta: 1,
        startValue: 0,
      ),
      1,
    );
  });

  group('sweepOrphanValues', () {
    const deletedThere = '000000000500:0000:remote';
    final deletedAt = DateTime.utc(2026, 11, 2, 9);

    /// A delete a pull merged: the note's tombstone alone, no cascade, under
    /// the deleting device's stamp.
    Future<void> mergedDelete(String noteId) {
      return db.customStatement(
        'UPDATE notes SET is_deleted = 1, hlc_timestamp = ?, '
        "device_id = 'remote', deleted_at = ? WHERE id = ?",
        [deletedThere, deletedAt.millisecondsSinceEpoch ~/ 1000, noteId],
      );
    }

    /// Puts a value's stamp at [hlc], as a merge would have stored it.
    Future<void> stampValue(String counterId, String noteId, String hlc) {
      return db.customStatement(
        'UPDATE counter_values SET hlc_timestamp = ? '
        'WHERE counter_id = ? AND note_id = ?',
        [hlc, counterId, noteId],
      );
    }

    test('tombstones the values its note\'s tombstone outranks, under the '
        'note\'s own stamp, and nothing else', () async {
      final folderId = await folder();
      final live = await noteWithValues(folderId);
      final merged = await noteWithValues(folderId);
      await db.counterDao.upsertValue('sets', merged, 1);
      await mergedDelete(merged);
      await stampValue('reps', merged, '000000000400:0000:here');
      await stampValue('sets', merged, '000000000450:0000:here');
      // Tapped on another device after the delete: it outranks the
      // tombstone, and a newer edit there may yet bring the note back.
      await stampValue('laps', merged, '000000000600:0000:other');
      await db.counterDao.upsertValue('reps', 'not-pulled-yet', 3);
      // Pushed long ago: the entries the writes queued at today's clock
      // would outrank the hand-set stamps above.
      await db.syncOutboxDao.clear();

      final swept = await db.counterDao.sweepOrphanValues();

      expect(swept, unorderedEquals(['reps|$merged', 'sets|$merged']));
      for (final counterId in ['reps', 'sets']) {
        final orphan = (await valueOf(counterId, merged))!;
        expect(orphan.isDeleted, isTrue);
        expect(orphan.hlcTimestamp, deletedThere);
        expect(orphan.deviceId, 'remote');
        expect(orphan.deletedAt, deletedAt.toLocal());
        expect(
          await queued(counterValueRowKey(counterId, merged)),
          'tombstone@$deletedThere',
        );
      }
      final late = (await valueOf('laps', merged))!;
      expect(late.isDeleted, isFalse);
      expect(late.hlcTimestamp, '000000000600:0000:other');
      expect((await valueOf('reps', live))!.isDeleted, isFalse);
      expect((await valueOf('laps', live))!.isDeleted, isFalse);
      expect((await valueOf('reps', ''))!.isDeleted, isFalse);
      expect(
        (await valueOf('reps', 'not-pulled-yet'))!.isDeleted,
        isFalse,
        reason: 'a missing note is no evidence of a delete',
      );
      expect(await db.counterDao.sweepOrphanValues(), isEmpty);
    });

    test('leaves an already tombstoned value as it is', () async {
      final merged = await noteWithValues(await folder());
      await db.counterDao.deleteValue('laps', merged);
      final gone = await valueOf('laps', merged);
      await mergedDelete(merged);
      await stampValue('reps', merged, '000000000400:0000:here');
      await stampValue('laps', merged, '000000000400:0000:here');
      final stamped = await valueOf('laps', merged);

      await db.counterDao.sweepOrphanValues();

      expect(gone!.isDeleted, isTrue);
      expect(await valueOf('laps', merged), stamped);
    });
  });

  test(
    'a single note delete finds its values through the note index',
    () async {
      final noteId = await noteWithValues(await folder());
      statements.reset();

      await db.noteDao.softDeleteNote(noteId);

      final cascade = statements.captured.singleWhere(
        (c) => c.sql.startsWith('UPDATE counter_values'),
      );
      expect(
        (await explainCaptured(db, cascade)).join('\n'),
        contains('INDEX idx_counter_values_note (note_id=?)'),
      );
    },
  );
}
