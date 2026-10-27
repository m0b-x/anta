// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_merge.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/note_storage_service.dart';

import 'support/db_test_support.dart';

/// Guards the change feed: every local write on a browser-side synced table
/// leaves exactly one `sync_outbox` entry per row it touched, carrying that
/// row's HLC, and a remote merge leaves none.
///
/// Nothing here is visible in the app. It is what the push side will read
/// instead of scanning tables — a write that commits without its entry is a
/// change that never leaves the device, and an entry for a remote row is an
/// echo.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<List<SyncOutboxRow>> queued([String? table]) {
    final query = db.select(db.syncOutbox);
    if (table != null) query.where((o) => o.syncedTable.equals(table));
    return query.get();
  }

  Future<SyncOutboxRow> onlyEntry(String table) async {
    final rows = await queued(table);
    expect(rows, hasLength(1), reason: 'one entry per touched $table row');
    return rows.single;
  }

  Future<Note> noteRow(String id) {
    return (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<Folder> folderRow(String id) {
    return (db.select(db.folders)..where((f) => f.id.equals(id))).getSingle();
  }

  Future<String> seedFolderId() async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    await db.syncOutboxDao.clear();
    return folder.id;
  }

  group('folders', () {
    test('a create queues the row at its HLC', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');

      final entry = await onlyEntry('folders');
      expect(entry.rowKey, folder.id);
      expect(entry.hlc, folder.hlcTimestamp);
      expect(entry.op, 'upsert');
    });

    test('a second write coalesces to the newer HLC', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      await db.folderDao.updateFolder(id: folder.id, name: 'Gym');

      final entry = await onlyEntry('folders');
      expect(entry.hlc, (await folderRow(folder.id)).hlcTimestamp);
      expect(entry.hlc.compareTo(folder.hlcTimestamp), greaterThan(0));
    });

    test('a delete records a tombstone', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      await db.folderDao.softDeleteFolder(folder.id);

      final entry = await onlyEntry('folders');
      expect(entry.op, 'tombstone');
      expect(entry.hlc, (await folderRow(folder.id)).hlcTimestamp);
    });

    test('a reorder queues only the rows it moved, under one HLC', () async {
      final a = await db.folderDao.createFolder(name: 'A');
      final b = await db.folderDao.createFolder(name: 'B');
      final c = await db.folderDao.createFolder(name: 'C');
      await db.syncOutboxDao.clear();

      // `a` stays at 0; `b` and `c` swap.
      await db.folderDao.setFolderPositions({a.id: 0, b.id: 2, c.id: 1});

      final rows = await queued('folders');
      expect(rows.map((r) => r.rowKey), unorderedEquals([b.id, c.id]));
      expect(rows.map((r) => r.hlc).toSet(), hasLength(1));
      expect((await folderRow(a.id)).version, a.version);
    });
  });

  group('notes', () {
    test(
      'a create with a body queues the note once and no chunk at all',
      () async {
        final folderId = await seedFolderId();
        final note = await db.noteDao.createNote(
          folderId: folderId,
          title: 'Log',
          content: 'squat 5x5',
        );

        final entry = await onlyEntry('notes');
        expect(entry.rowKey, note.id);
        expect(entry.hlc, note.hlcTimestamp);
        expect(entry.op, 'upsert');
        expect(await queued('content_chunks'), isEmpty);
        expect(await db.contentChunkDao.loadContent(note.id), 'squat 5x5');
      },
    );

    test('a save coalesces to the newer HLC', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      final saved = await db.noteDao.updateNote(
        id: note.id,
        title: 'B',
        content: 'body',
      );

      final entry = await onlyEntry('notes');
      expect(entry.hlc, saved!.hlcTimestamp);
      expect(saved.version, note.version + 1);
    });

    test('a delete records a tombstone', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      await db.noteDao.softDeleteNoteWithChunks(note.id);

      final entry = await onlyEntry('notes');
      expect(entry.op, 'tombstone');
      expect(entry.hlc, (await noteRow(note.id)).hlcTimestamp);
    });

    test('a refused save of a tombstone queues nothing new', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      await db.noteDao.softDeleteNote(note.id);
      final before = await onlyEntry('notes');

      expect(await db.noteDao.updateNote(id: note.id, title: 'B'), isNull);

      final after = await onlyEntry('notes');
      expect(after.hlc, before.hlc);
      expect(after.op, 'tombstone');
    });

    test('a bulk label queues only the rows whose colour moved', () async {
      final folderId = await seedFolderId();
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        final note = await db.noteDao.createNote(
          folderId: folderId,
          title: 'N$i',
        );
        ids.add(note.id);
      }
      await db.noteDao.softDeleteNote(ids[4]);
      await db.syncOutboxDao.clear();

      await db.noteDao.updateLabelForNotes(ids: ids, label: ItemLabel.teal);

      final rows = await queued('notes');
      expect(rows.map((r) => r.rowKey), unorderedEquals(ids.take(4)));
      final stored = await noteRow(ids[0]);
      expect(rows.every((r) => r.hlc == stored.hlcTimestamp), isTrue);
    });

    test('a bulk delete queues every tombstone under one HLC', () async {
      final folderId = await seedFolderId();
      final ids = [
        for (var i = 0; i < 6; i++)
          (await db.noteDao.createNote(folderId: folderId, title: 'N$i')).id,
      ];
      await db.syncOutboxDao.clear();

      await db.noteDao.softDeleteNotesWithChunks(ids);

      final rows = await queued('notes');
      expect(rows.map((r) => r.rowKey), unorderedEquals(ids));
      expect(rows.every((r) => r.op == 'tombstone'), isTrue);
      expect(rows.map((r) => r.hlc).toSet(), hasLength(1));
    });

    test('a reorder queues only the rows it moved', () async {
      final folderId = await seedFolderId();
      final a = await db.noteDao.createNote(folderId: folderId, title: 'A');
      final b = await db.noteDao.createNote(folderId: folderId, title: 'B');
      await db.syncOutboxDao.clear();

      await db.noteDao.setNotePositions({a.id: a.position, b.id: 7});

      final entry = await onlyEntry('notes');
      expect(entry.rowKey, b.id);
      expect((await noteRow(a.id)).version, a.version);
    });
  });

  group('content_chunks', () {
    test('a body-only save queues its note once, never a chunk', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      await db.syncOutboxDao.clear();

      await db.noteDao.updateNote(id: note.id, content: 'x' * 25000);

      final entry = await onlyEntry('notes');
      final stored = await noteRow(note.id);
      expect(entry.hlc, stored.hlcTimestamp);
      expect(stored.version, note.version + 1);
      expect(await queued('content_chunks'), isEmpty);
      final chunks = await db.contentChunkDao.getChunksForNote(note.id);
      expect(chunks.map((c) => c.hlcTimestamp).toSet(), {stored.hlcTimestamp});
    });

    test('writing chunks queues nothing of their own', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      await db.syncOutboxDao.clear();

      await db.transaction(
        () => db.contentChunkDao.writeChunks(
          noteId: note.id,
          content: 'body',
          hlc: db.newStamp().hlc,
        ),
      );

      expect(await queued(), isEmpty);
    });
  });

  group('counters and their values', () {
    CountersCompanion counter(String id, {String name = 'Sets'}) {
      return CountersCompanion(
        id: Value(id),
        name: Value(name),
        createdAt: Value(DateTime.utc(2026, 10, 1)),
      );
    }

    test('an insert queues the counter and its global value', () async {
      await db.counterDao.insertCounterWithValue(counter('c1'), 3);

      final counterEntry = await onlyEntry('counters');
      final valueEntry = await onlyEntry('counter_values');
      expect(counterEntry.rowKey, 'c1');
      expect(valueEntry.rowKey, 'c1|', reason: "the global value's noteId");
      expect(valueEntry.hlc, counterEntry.hlc, reason: 'one act, one HLC');
    });

    test('an edit coalesces to the newer HLC', () async {
      await db.counterDao.insertCounter(counter('c1'));
      final first = await onlyEntry('counters');
      await db.counterDao.updateCounter(counter('c1', name: 'Reps'));

      final second = await onlyEntry('counters');
      expect(second.hlc.compareTo(first.hlc), greaterThan(0));
    });

    test('a per-note value is keyed counterId|noteId', () async {
      await db.counterDao.insertCounter(counter('c1'));
      await db.counterDao.upsertValue('c1', 'n1', 4);
      await db.counterDao.upsertValue('c1', 'n1', 5);

      final entry = await onlyEntry('counter_values');
      expect(entry.rowKey, 'c1|n1');
      final row = await (db.select(
        db.counterValues,
      )..where((v) => v.noteId.equals('n1'))).getSingle();
      expect(entry.hlc, row.hlcTimestamp);
    });

    test('a value write that changes nothing queues nothing', () async {
      await db.counterDao.insertCounter(counter('c1'));
      await db.counterDao.upsertValue('c1', 'n1', 4);
      await db.syncOutboxDao.clear();

      await db.counterDao.upsertValue('c1', 'n1', 4);

      expect(await queued(), isEmpty);
    });

    test('a delete tombstones the counter and every value', () async {
      await db.counterDao.insertCounterWithValue(counter('c1'), 0);
      await db.counterDao.upsertValue('c1', 'n1', 1);
      await db.counterDao.upsertValue('c1', 'n2', 2);

      await db.counterDao.deleteCounter('c1');

      final rows = await queued();
      expect(rows, hasLength(4));
      expect(rows.every((r) => r.op == 'tombstone'), isTrue);
      expect(rows.map((r) => r.hlc).toSet(), hasLength(1));
      // The cascade builds the values' keys from what its UPDATE returned;
      // they must agree with the ones every single-row write uses.
      expect(
        rows.map((r) => r.rowKey),
        unorderedEquals([
          'c1',
          counterValueRowKey('c1', ''),
          counterValueRowKey('c1', 'n1'),
          counterValueRowKey('c1', 'n2'),
        ]),
      );
    });
  });

  group('vocabularies and their items', () {
    VocabulariesCompanion vocabulary(String id, String name) {
      return VocabulariesCompanion(
        id: Value(id),
        name: Value(name),
        createdAt: Value(DateTime.utc(2024)),
        updatedAt: Value(DateTime.utc(2024)),
      );
    }

    test('an upsert queues the row and a second one coalesces', () async {
      await db.vocabularyDao.upsertVocabulary(vocabulary('v1', 'Lifts'));
      final first = await onlyEntry('vocabularies');
      await db.vocabularyDao.upsertVocabulary(vocabulary('v1', 'Moves'));

      final second = await onlyEntry('vocabularies');
      expect(second.rowKey, 'v1');
      expect(second.hlc.compareTo(first.hlc), greaterThan(0));
    });

    test('a term list save queues every written term under one HLC', () async {
      await db.vocabularyDao.upsertVocabulary(vocabulary('v1', 'Lifts'));
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: ['squat', 'bench', 'deadlift'],
      );
      await db.syncOutboxDao.clear();

      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: ['squat', 'deadlift', 'press'],
      );

      final rows = await queued('vocabulary_items');
      final ops = {for (final r in rows) r.rowKey: r.op};
      final items = await db.select(db.vocabularyItems).get();
      String idOf(String term) => items.firstWhere((i) => i.term == term).id;
      // `squat` stayed put and is not queued; `deadlift` moved up a slot.
      expect(ops, {
        idOf('deadlift'): 'upsert',
        idOf('press'): 'upsert',
        idOf('bench'): 'tombstone',
      });
      expect(rows.map((r) => r.hlc).toSet(), hasLength(1));
    });

    test('a delete tombstones the list and every term', () async {
      await db.vocabularyDao.upsertVocabulary(vocabulary('v1', 'Lifts'));
      await db.vocabularyDao.saveItems(
        vocabularyId: 'v1',
        terms: ['squat', 'bench'],
      );

      await db.vocabularyDao.softDeleteVocabularyById('v1');

      final rows = await queued();
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.op == 'tombstone'), isTrue);
      expect(rows.map((r) => r.hlc).toSet(), hasLength(1));
    });
  });

  group('calendar_categories', () {
    CalendarCategoriesCompanion category(String id, {int order = 0}) {
      final at = DateTime.utc(2026, 10, 1);
      return CalendarCategoriesCompanion(
        id: Value(id),
        name: Value(id),
        colorValue: const Value(0xFF00FF00),
        iconKey: const Value('event'),
        sortOrder: Value(order),
        createdAt: Value(at),
        updatedAt: Value(at),
      );
    }

    Future<CalendarCategoryRow> categoryRow(String id) {
      return (db.select(
        db.calendarCategories,
      )..where((c) => c.id.equals(id))).getSingle();
    }

    test('an insert, an edit and a delete leave one entry', () async {
      await db.calendarCategoryDao.insertCategory(category('climb'));
      await db.calendarCategoryDao.updateCategory(
        category('climb').copyWith(name: const Value('Bouldering')),
      );
      await db.calendarCategoryDao.softDeleteById('climb');

      final entry = await onlyEntry('calendar_categories');
      expect(entry.rowKey, 'climb');
      expect(entry.op, 'tombstone');
      expect(entry.hlc, (await categoryRow('climb')).hlcTimestamp);
    });

    test('a reorder queues only the rows it moved', () async {
      await db.calendarCategoryDao.insertCategory(category('a', order: 0));
      await db.calendarCategoryDao.insertCategory(category('b', order: 1));
      await db.calendarCategoryDao.insertCategory(category('c', order: 2));
      await db.syncOutboxDao.clear();

      await db.calendarCategoryDao.reorder(['a', 'c', 'b']);

      final rows = await queued('calendar_categories');
      expect(rows.map((r) => r.rowKey), unorderedEquals(['b', 'c']));
    });

    test('an import queues every restored row', () async {
      await db.calendarCategoryDao.importAll([category('x'), category('y')]);

      final rows = await queued('calendar_categories');
      expect(rows.map((r) => r.rowKey), unorderedEquals(['x', 'y']));
      expect(rows.every((r) => r.op == 'upsert'), isTrue);
    });
  });

  group('merges', () {
    const newer = 'ffffffffffff:0001:remote';
    const older = '000000000001:0000:remote';

    Future<Note> seedNote(String title) async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(
        folderId: folderId,
        title: title,
        preview: 'heavy',
      );
      await db.syncOutboxDao.clear();
      return note;
    }

    test('a remote note merge queues nothing, either branch', () async {
      final local = await seedNote('Squat log');

      await db.noteDao.mergeNoteDocument(
        local.copyWith(id: 'pulled', hlcTimestamp: newer),
        'pulled body',
      );
      await db.noteDao.mergeNoteDocument(
        local.copyWith(title: 'Deadlift log', hlcTimestamp: newer),
        'pulled body',
      );

      expect(await queued(), isEmpty);
    });

    test('a newer note is applied and re-indexed', () async {
      final local = await seedNote('Squat log');

      final outcome = await db.noteDao.mergeNoteDocument(
        local.copyWith(title: 'Deadlift log', hlcTimestamp: newer),
        'pulled body',
      );

      expect(outcome.result, MergeResult.applied);
      final found = await db.noteDao.fullTextSearch('Deadlift');
      expect(found.map((n) => n.id), [local.id]);
      expect(await db.noteDao.fullTextSearch('Squat'), isEmpty);
    });

    test('an unknown note is inserted and indexed', () async {
      final local = await seedNote('Squat log');

      final outcome = await db.noteDao.mergeNoteDocument(
        local.copyWith(id: 'pulled', title: 'Bench log', hlcTimestamp: newer),
        'pulled body',
      );

      expect(outcome.result, MergeResult.inserted);
      final found = await db.noteDao.fullTextSearch('Bench');
      expect(found.map((n) => n.id), ['pulled']);
    });

    test('an older note keeps the local row and re-queues it', () async {
      final local = await seedNote('Squat log');

      final outcome = await db.noteDao.mergeNoteDocument(
        local.copyWith(title: 'Stale', hlcTimestamp: older),
        'stale body',
      );

      expect(outcome.result, MergeResult.keptLocal);
      expect((await noteRow(local.id)).title, 'Squat log');
      expect((await onlyEntry('notes')).hlc, local.hlcTimestamp);
    });

    test('a remote tombstone leaves the index', () async {
      final local = await seedNote('Squat log');

      await db.noteDao.mergeNoteDocument(
        local.copyWith(isDeleted: true, hlcTimestamp: newer),
        null,
      );

      expect(await db.noteDao.fullTextSearch('Squat'), isEmpty);
    });

    test('a remote folder merge queues nothing', () async {
      final local = await db.folderDao.createFolder(name: 'Training');
      await db.syncOutboxDao.clear();

      final outcome = await db.folderDao.mergeFolder(
        local.copyWith(name: 'Gym', hlcTimestamp: newer),
      );

      expect(outcome.result, MergeResult.applied);
      expect((await folderRow(local.id)).name, 'Gym');
      expect(await queued(), isEmpty);
    });

    test('a chunk merge queues nothing remote, its note when local', () async {
      final local = await seedNote('Squat log');
      final chunk = ContentChunk(
        id: '${local.id}_chunk_0',
        noteId: local.id,
        chunkIndex: 0,
        content: 'pulled body',
        isCompressed: false,
        hlcTimestamp: newer,
        deviceId: 'remote',
        version: 1,
        isDeleted: false,
      );

      await db.contentChunkDao.mergeChunk(chunk, origin: MergeOrigin.remote);
      expect(await queued(), isEmpty);

      await db.contentChunkDao.mergeChunk(
        chunk.copyWith(id: '${local.id}_chunk_1', chunkIndex: 1),
        origin: MergeOrigin.local,
      );
      final entry = await onlyEntry('notes');
      final stored = await noteRow(local.id);
      expect(entry.rowKey, local.id);
      expect(entry.hlc, newer);
      expect(stored.hlcTimestamp, newer, reason: 'the row carries it too');
      expect(stored.version, local.version + 1);
      expect(await queued('content_chunks'), isEmpty);
    });

    test('a note merged over a tombstone names no loser', () async {
      final local = await seedNote('Squat log');
      await db.noteDao.softDeleteNote(local.id);

      final outcome = await db.noteDao.mergeNoteDocument(
        local.copyWith(title: 'Back', hlcTimestamp: newer),
        'back again',
      );

      expect(outcome.result, MergeResult.applied);
      expect(outcome.loser, isNull);
      expect((await noteRow(local.id)).title, 'Back');
    });

    test('a folder merged over a tombstone resurrects it', () async {
      final local = await db.folderDao.createFolder(name: 'Training');
      await db.folderDao.softDeleteFolder(local.id);

      final outcome = await db.folderDao.mergeFolder(
        local.copyWith(name: 'Back', hlcTimestamp: newer),
      );

      expect(outcome.result, MergeResult.applied);
      expect((await folderRow(local.id)).isDeleted, isFalse);
    });

    group('a merged stamp orders before the next local one', () {
      // Ahead of the wall clock, as a pull from a device whose clock runs
      // fast delivers it: the next local stamp must still order after it.
      String ahead() => HlcTimestamp(
        wallTime: DateTime.now().millisecondsSinceEpoch + 3600 * 1000,
        logicalCounter: 3,
        nodeId: 'remote',
      ).toString();

      test('mergeNoteDocument, once the puller advanced the clock', () async {
        final local = await seedNote('Squat log');
        final remoteHlc = ahead();

        await db.noteDao.mergeNoteDocument(
          local.copyWith(id: 'pulled', hlcTimestamp: remoteHlc),
          'pulled body',
        );

        // The merge itself does not move the clock; the puller does, once
        // the page committed (A7 R65).
        expect(db.newStamp().hlc.compareTo(remoteHlc), lessThan(0));
        CrdtMerge.advanceClock(db, remoteHlc);
        expect(db.newStamp().hlc.compareTo(remoteHlc), greaterThan(0));
      });

      test('mergeFolder, once the puller advanced the clock', () async {
        final local = await db.folderDao.createFolder(name: 'Training');
        final remoteHlc = ahead();

        await db.folderDao.mergeFolder(
          local.copyWith(id: 'pulled', hlcTimestamp: remoteHlc),
        );

        expect(db.newStamp().hlc.compareTo(remoteHlc), lessThan(0));
        CrdtMerge.advanceClock(db, remoteHlc);
        expect(db.newStamp().hlc.compareTo(remoteHlc), greaterThan(0));
      });

      test('mergeChunk', () async {
        final local = await seedNote('Squat log');
        final remoteHlc = ahead();

        await db.contentChunkDao.mergeChunk(
          ContentChunk(
            id: '${local.id}_chunk_0',
            noteId: local.id,
            chunkIndex: 0,
            content: 'pulled body',
            isCompressed: false,
            hlcTimestamp: remoteHlc,
            deviceId: 'remote',
            version: 1,
            isDeleted: false,
          ),
          origin: MergeOrigin.remote,
        );

        expect(db.newStamp().hlc.compareTo(remoteHlc), greaterThan(0));
      });
    });
  });

  group('guards: a write that changes nothing queues nothing', () {
    test('a repeated note delete', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      await db.noteDao.softDeleteNote(note.id);
      final first = await noteRow(note.id);
      await db.syncOutboxDao.clear();

      await db.noteDao.softDeleteNote(note.id);
      await db.noteDao.softDeleteNoteWithChunks(note.id);

      expect(await queued(), isEmpty);
      expect((await noteRow(note.id)).version, first.version);
    });

    test('a repeated folder delete', () async {
      final folder = await db.folderDao.createFolder(name: 'A');
      await db.folderDao.softDeleteFolder(folder.id);
      final first = await folderRow(folder.id);
      await db.syncOutboxDao.clear();

      await db.folderDao.softDeleteFolder(folder.id);

      expect(await queued(), isEmpty);
      expect((await folderRow(folder.id)).version, first.version);
    });

    test('a folder rename to the same name', () async {
      final folder = await db.folderDao.createFolder(name: 'A');
      await db.syncOutboxDao.clear();

      await db.folderDao.updateFolder(id: folder.id, name: 'A');
      await db.folderDao.updateFolder(
        id: folder.id,
        parentId: folder.parentId,
        updateParent: true,
      );

      expect(await queued(), isEmpty);
      expect((await folderRow(folder.id)).version, folder.version);
    });

    test('a folder sort it already has', () async {
      final folder = await db.folderDao.createFolder(name: 'A');
      await db.folderDao.updateFolderSortPreferences(
        id: folder.id,
        noteSortOrder: 'titleAsc',
      );
      final first = await folderRow(folder.id);
      await db.syncOutboxDao.clear();

      await db.folderDao.updateFolderSortPreferences(
        id: folder.id,
        noteSortOrder: 'titleAsc',
      );
      await db.folderDao.updateFolderSortPreferences(
        id: folder.id,
        clearSubfolderSortOrder: true,
      );

      expect(await queued(), isEmpty);
      expect((await folderRow(folder.id)).version, first.version);
    });

    test('a value pin it already has', () async {
      await db.counterDao.insertCounter(
        CountersCompanion(
          id: const Value('c1'),
          name: const Value('Sets'),
          createdAt: Value(DateTime.utc(2026)),
        ),
      );
      await db.counterDao.upsertValue('c1', 'n1', 1);
      await db.counterDao.setNoteValuePinned('c1', 'n1', true);
      await db.syncOutboxDao.clear();

      await db.counterDao.setNoteValuePinned('c1', 'n1', true);

      expect(await queued(), isEmpty);
    });

    test('a vocabulary upsert that changes nothing', () async {
      final entry = VocabulariesCompanion(
        id: const Value('v1'),
        name: const Value('Lifts'),
        createdAt: Value(DateTime.utc(2024)),
        updatedAt: Value(DateTime.utc(2024)),
      );
      await db.vocabularyDao.upsertVocabulary(entry);
      await db.syncOutboxDao.clear();

      await db.vocabularyDao.upsertVocabulary(
        entry.copyWith(updatedAt: Value(DateTime.utc(2025))),
      );

      expect(await queued(), isEmpty);
    });
  });

  group('imports', () {
    test('importNote queues its one row', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.importNote(
        folderId: folderId,
        title: 'Archived',
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
        content: 'body',
      );

      final entry = await onlyEntry('notes');
      expect(entry.rowKey, note.id);
      expect(entry.hlc, note.hlcTimestamp);
      expect(await queued(), hasLength(1));
    });

    test('importFolder queues its one row', () async {
      final folder = await db.folderDao.importFolder(
        name: 'Archived',
        createdAt: DateTime.utc(2024),
      );

      final entry = await onlyEntry('folders');
      expect(entry.rowKey, folder.id);
      expect(entry.hlc, folder.hlcTimestamp);
    });
  });

  test('a write that throws inside its transaction leaves no entry', () async {
    final folderId = await seedFolderId();

    await expectLater(
      db.transaction(() async {
        await db.noteDao.createNote(folderId: folderId, title: 'Doomed');
        throw StateError('the write fails after the row');
      }),
      throwsStateError,
    );

    expect(await queued(), isEmpty);
    expect(await db.select(db.notes).get(), isEmpty);
  });

  group('the outbox dao', () {
    test('ackThrough retires an entry the push has caught up with', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');

      expect(
        await db.syncOutboxDao.ackThrough('notes', note.id, note.hlcTimestamp),
        isTrue,
      );
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('ackThrough keeps an entry re-queued during the push', () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(folderId: folderId, title: 'A');
      // A save lands while the push of the create is in flight.
      final saved = await db.noteDao.updateNote(id: note.id, title: 'B');

      expect(
        await db.syncOutboxDao.ackThrough('notes', note.id, note.hlcTimestamp),
        isFalse,
      );
      final entry = await onlyEntry('notes');
      expect(entry.hlc, saved!.hlcTimestamp);
    });

    test('an entry never moves back to an older HLC', () async {
      final older = db.newStamp().hlc;
      final newer = db.newStamp().hlc;

      await db.transaction(() => db.enqueue(db.notes, 'n1', newer));
      await db.transaction(
        () => db.enqueue(db.notes, 'n1', older, op: OutboxOp.tombstone),
      );
      await db.transaction(() => db.enqueueMany(db.notes, ['n1'], older));

      final entry = await onlyEntry('notes');
      expect(entry.hlc, newer);
      expect(entry.op, 'upsert');
    });

    test('requeueRow queues a row at the stamp it carries', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      await db.syncOutboxDao.clear();

      expect(await db.syncOutboxDao.requeueRow('folders', folder.id), isTrue);

      final entry = await onlyEntry('folders');
      expect(entry.rowKey, folder.id);
      expect(entry.hlc, folder.hlcTimestamp);
      expect(entry.op, 'upsert');
    });

    test('requeueRow raises an older entry and keys a composite row', () async {
      await db.counterDao.insertCounterWithValue(
        CountersCompanion(
          id: const Value('c1'),
          name: const Value('Sets'),
          createdAt: Value(DateTime.utc(2026, 10, 1)),
        ),
        3,
      );
      final row = await db.select(db.counterValues).getSingle();
      await db.syncOutboxDao.clear();
      await db.transaction(
        () => db.enqueue(db.counterValues, 'c1|', '000000000001:0000:old'),
      );

      expect(
        await db.syncOutboxDao.requeueRow('counter_values', 'c1|'),
        isTrue,
      );

      final entry = await onlyEntry('counter_values');
      expect(entry.rowKey, 'c1|');
      expect(entry.hlc, row.hlcTimestamp);
    });

    test('requeueRow never lowers a newer entry', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      await db.syncOutboxDao.clear();
      const ahead = 'ffffffffffff:0000:other';
      await db.transaction(() => db.enqueue(db.folders, folder.id, ahead));

      expect(await db.syncOutboxDao.requeueRow('folders', folder.id), isFalse);
      expect((await onlyEntry('folders')).hlc, ahead);
    });

    test('requeueRow queues a tombstone as one', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      await db.folderDao.softDeleteFolder(folder.id);
      await db.syncOutboxDao.clear();

      await db.syncOutboxDao.requeueRow('folders', folder.id);

      expect((await onlyEntry('folders')).op, 'tombstone');
    });

    test('requeueRow writes nothing for a missing row', () async {
      expect(await db.syncOutboxDao.requeueRow('folders', 'missing'), isFalse);
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('requeueRow refuses a table that is not queued on its own', () async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'Squat log',
        content: 'body',
      );
      await db.syncOutboxDao.clear();

      expect(
        () => db.syncOutboxDao.requeueRow('nope', 'x'),
        throwsArgumentError,
      );
      expect(
        () => db.syncOutboxDao.requeueRow(
          'content_chunks',
          '${note.id}_chunk_0',
        ),
        throwsArgumentError,
      );
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('pending lists oldest change first and honours a limit', () async {
      final a = await db.folderDao.createFolder(name: 'A');
      final b = await db.folderDao.createFolder(name: 'B');
      await db.folderDao.updateFolder(id: a.id, name: 'A2');

      final all = await db.syncOutboxDao.pending();
      expect(all.map((r) => r.rowKey), [b.id, a.id]);
      final first = await db.syncOutboxDao.pending(limit: 1);
      expect(first.single.rowKey, b.id);
    });

    test('pending resumes after an entry already read', () async {
      final a = await db.folderDao.createFolder(name: 'A');
      final b = await db.folderDao.createFolder(name: 'B');
      final c = await db.folderDao.createFolder(name: 'C');

      final head = (await db.syncOutboxDao.pending(limit: 1)).single;
      final rest = await db.syncOutboxDao.pending(
        after: (hlc: head.hlc, table: head.syncedTable, rowKey: head.rowKey),
      );

      expect([a.id, b.id, c.id], contains(head.rowKey));
      expect(rest, hasLength(2));
      expect(rest.map((r) => r.rowKey), isNot(contains(head.rowKey)));
      expect(
        rest.map((r) => r.rowKey),
        (await db.syncOutboxDao.pending()).skip(1).map((r) => r.rowKey),
      );
    });

    test('pendingForTable reads one table, oldest change first', () async {
      final folderId = await seedFolderId();
      final a = await db.folderDao.createFolder(name: 'A');
      await db.noteDao.createNote(
        folderId: folderId,
        title: 'Note',
        content: 'body',
      );

      final folders = await db.syncOutboxDao.pendingForTable('folders');

      expect(folders.map((r) => r.syncedTable).toSet(), {'folders'});
      expect(folders.map((r) => r.rowKey), contains(a.id));
      expect(await db.syncOutboxDao.pendingForTable('nope'), isEmpty);
    });
  });

  test(
    'the usage probe: 200 saves of one note leave one notes entry',
    () async {
      final folderId = await seedFolderId();
      final note = await db.noteDao.createNote(
        folderId: folderId,
        title: 'Session',
        content: 'warm-up',
      );

      for (var i = 0; i < 200; i++) {
        await db.noteDao.updateNote(
          id: note.id,
          title: 'Session $i',
          preview: 'set $i',
          content: 'warm-up\n${'set $i\n' * (i + 1)}',
        );
      }

      final rows = await queued();
      expect(rows, hasLength(1));
      expect(rows.single.syncedTable, 'notes');
      expect(rows.single.hlc, (await noteRow(note.id)).hlcTimestamp);
      expect(await queued('content_chunks'), isEmpty);
    },
  );

  test('the usage probe through the editor\'s save path', () async {
    final folderId = await seedFolderId();
    final service = NoteStorageService(
      repository: NoteRepository(database: db),
    );
    final note = await service.createNote(
      folderId: folderId,
      title: 'Session',
      content: 'warm-up',
    );

    for (var i = 0; i < 200; i++) {
      await service.updateNote(
        noteId: note.id,
        title: 'Session $i',
        content: 'warm-up\n${'set $i\n' * (i + 1)}',
      );
    }

    final rows = await queued();
    expect(rows, hasLength(1));
    expect(rows.single.syncedTable, 'notes');
    expect(rows.single.rowKey, note.id);
    expect(rows.single.hlc, (await noteRow(note.id)).hlcTimestamp);
  });

  test('a folder cascade queues every tombstone under one HLC', () async {
    final root = await db.folderDao.createFolder(name: 'Root');
    final child = await db.folderDao.createFolder(
      name: 'Child',
      parentId: root.id,
    );
    final rootNote = await db.noteDao.createNote(folderId: root.id, title: 'R');
    final childNote = await db.noteDao.createNote(
      folderId: child.id,
      title: 'C',
    );
    final bystander = await db.folderDao.createFolder(name: 'Other');
    await db.syncOutboxDao.clear();

    await db.folderDao.softDeleteFolderWithDescendants(root.id);

    final rows = await queued();
    expect(
      {for (final r in rows) '${r.syncedTable}:${r.rowKey}'},
      {
        'folders:${root.id}',
        'folders:${child.id}',
        'notes:${rootNote.id}',
        'notes:${childNote.id}',
      },
    );
    expect(rows.every((r) => r.op == 'tombstone'), isTrue);
    expect(rows.map((r) => r.hlc).toSet(), {
      (await folderRow(root.id)).hlcTimestamp,
    });
    expect((await folderRow(bystander.id)).isDeleted, isFalse);
  });
}
