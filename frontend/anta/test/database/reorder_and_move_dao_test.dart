// `isNull` is a SQL builder in drift and a matcher in flutter_test; this
// file wants the matcher.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

const positionStride = AppConstants.positionStride;

/// Guards the browser's two set-based writes: a drag's order applied to the
/// whole group in one transaction (`applyOrder`), and a selection moved in
/// one transaction under one HLC (`moveNotes` / `moveFolders`).
void main() {
  late AppDatabase db;
  late StatementCounter counter;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });
  tearDown(() async => db.close());

  Future<Note> noteRow(String id) {
    return (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<Folder> folderRow(String id) {
    return (db.select(db.folders)..where((f) => f.id.equals(id))).getSingle();
  }

  Future<Set<String>> queued(String table) async {
    final rows = await (db.select(
      db.syncOutbox,
    )..where((o) => o.syncedTable.equals(table))).get();
    return {for (final row in rows) row.rowKey};
  }

  /// [count] notes created in order, so their positions are `0..count-1`.
  Future<(String, List<Note>)> seedNotes(int count, {String name = 'F'}) async {
    final folder = await db.folderDao.createFolder(name: name);
    final notes = [
      for (var i = 0; i < count; i++)
        await db.noteDao.createNote(folderId: folder.id, title: 'Note $i'),
    ];
    await db.syncOutboxDao.clear();
    return (folder.id, notes);
  }

  /// The group as the browser reads it in its custom direction.
  Future<List<String>> readBack(String folderId, {required bool desc}) async {
    final rows =
        await (db.select(db.notes)
              ..where((n) => n.folderId.equals(folderId) & n.isDeleted.not())
              ..orderBy([
                (n) => desc
                    ? OrderingTerm.desc(n.position)
                    : OrderingTerm.asc(n.position),
                (n) => OrderingTerm.asc(n.id),
              ]))
            .get();
    return [for (final row in rows) row.id];
  }

  group('NoteDao.applyOrder', () {
    test('ascending: the drag reads back and only the moved rows are '
        'stamped and queued', () async {
      final (folderId, notes) = await seedNotes(6);
      final ids = [for (final note in notes) note.id];
      // Third to the front: only the dragged row moves.
      final dragged = [ids[2], ids[0], ids[1], ids[3], ids[4], ids[5]];

      counter.reset();
      final changed = await db.noteDao.applyOrder(
        folderId: folderId,
        loadedOrder: dragged,
        descending: false,
      );

      expect(changed, [ids[2]]);
      expect(await readBack(folderId, desc: false), dragged);
      expect(await queued('notes'), {ids[2]});
      for (final note in notes.where((n) => n.id != ids[2])) {
        final row = await noteRow(note.id);
        expect(row.version, note.version, reason: 'unchanged, unstamped');
        expect(row.hlcTimestamp, note.hlcTimestamp);
      }
      final moved = await noteRow(ids[2]);
      expect(moved.version, notes[2].version + 1);
      expect(
        moved.updatedAt,
        notes[2].updatedAt,
        reason: 'a new place in the list is not an edit',
      );
    });

    test(
      'descending: positions count down, so DESC reads the drag back',
      () async {
        final (folderId, notes) = await seedNotes(6);
        // Display under `positionDesc`: the last created first.
        final shown = [for (final note in notes.reversed) note.id];
        final dragged = [shown[2], shown[0], shown[1], ...shown.skip(3)];

        await db.noteDao.applyOrder(
          folderId: folderId,
          loadedOrder: dragged,
          descending: true,
        );

        expect(await readBack(folderId, desc: true), dragged);
        expect(await queued('notes'), {shown[2]});
      },
    );

    test('a loaded window (hasMore) keeps the unloaded rows where they were '
        '— ascending', () async {
      final (folderId, notes) = await seedNotes(50);
      final ids = [for (final note in notes) note.id];
      final window = ids.take(20).toList();
      final dragged = [window[19], ...window.take(19)];

      counter.reset();
      await db.noteDao.applyOrder(
        folderId: folderId,
        loadedOrder: dragged,
        descending: false,
      );
      // One read of the whole group and one row written: the dragged one.
      expect(counter.selects, hasLength(1));
      expect(counter.executions('UPDATE "notes"'), 1);

      expect(await readBack(folderId, desc: false), [
        ...dragged,
        ...ids.skip(20),
      ]);
      expect(await queued('notes'), {window[19]});
    });

    test('a loaded window (hasMore) keeps the unloaded rows where they were '
        '— descending', () async {
      final (folderId, notes) = await seedNotes(50);
      final shown = [for (final note in notes.reversed) note.id];
      final window = shown.take(20).toList();
      final dragged = [window[1], window[0], ...window.skip(2)];

      counter.reset();
      await db.noteDao.applyOrder(
        folderId: folderId,
        loadedOrder: dragged,
        descending: true,
      );

      expect(await readBack(folderId, desc: true), [
        ...dragged,
        ...shown.skip(20),
      ]);
      // A swap moves one of the pair; which one the planner picks is free.
      final written = await queued('notes');
      expect(written, hasLength(1));
      expect({window[0], window[1]}.containsAll(written), isTrue);
      expect(counter.executions('UPDATE "notes"'), 1);
    });

    test('an order already in place writes nothing at all', () async {
      final (folderId, notes) = await seedNotes(5);

      counter.reset();
      final changed = await db.noteDao.applyOrder(
        folderId: folderId,
        loadedOrder: [for (final note in notes) note.id],
        descending: false,
      );

      expect(changed, isEmpty);
      expect(counter.count, 1, reason: 'the group read, and no write');
      expect(await queued('notes'), isEmpty);
    });

    test('colliding positions outside the window are spread out', () async {
      final (folderId, notes) = await seedNotes(4);
      final ids = [for (final note in notes) note.id];
      await db.customStatement('UPDATE notes SET position = 0');
      // Ties read back by id, which is the order the page loaded.
      final shown = await readBack(folderId, desc: false);
      final dragged = [shown[1], shown[0], ...shown.skip(2)];

      await db.noteDao.applyOrder(
        folderId: folderId,
        loadedOrder: dragged.take(2).toList(),
        descending: false,
      );

      final positions = [for (final id in ids) (await noteRow(id)).position];
      expect(positions.toSet(), hasLength(4), reason: 'no ties left');
      expect(await readBack(folderId, desc: false), dragged);
    });

    test('a tombstoned note is neither placed nor written', () async {
      final (folderId, notes) = await seedNotes(3);
      final ids = [for (final note in notes) note.id];
      await db.noteDao.softDeleteNotesWithChunks([ids[0]]);
      final tombstone = await noteRow(ids[0]);

      await db.noteDao.applyOrder(
        folderId: folderId,
        loadedOrder: [ids[2], ids[0], ids[1]],
        descending: false,
      );

      expect(await readBack(folderId, desc: false), [ids[2], ids[1]]);
      final after = await noteRow(ids[0]);
      expect(after.version, tombstone.version);
      expect(after.hlcTimestamp, tombstone.hlcTimestamp);
    });
  });

  group('FolderDao.applyOrder', () {
    test('the root group, descending, reads the drag back and stamps only '
        'what moved', () async {
      final folders = [
        for (var i = 0; i < 4; i++)
          await db.folderDao.createFolder(name: 'Root $i'),
      ];
      await db.syncOutboxDao.clear();
      final shown = [for (final folder in folders.reversed) folder.id];
      final dragged = [shown[1], shown[0], shown[2], shown[3]];

      await db.folderDao.applyOrder(
        parentId: null,
        loadedOrder: dragged,
        descending: true,
      );

      final rows =
          await (db.select(db.folders)
                ..where((f) => f.parentId.isNull())
                ..orderBy([(f) => OrderingTerm.desc(f.position)]))
              .get();
      expect([for (final row in rows) row.id], dragged);
      final written = await queued('folders');
      expect(written, hasLength(1));
      expect({shown[0], shown[1]}.containsAll(written), isTrue);
      final untouched = await folderRow(shown[3]);
      expect(untouched.version, folders.first.version);
    });
  });

  group('NoteDao.moveNotes', () {
    test('two hundred notes move in one transaction under one HLC', () async {
      final (source, notes) = await seedNotes(200);
      final target = await db.folderDao.createFolder(name: 'Target');
      await db.syncOutboxDao.clear();
      final ids = [for (final note in notes) note.id];

      counter.reset();
      final result = await db.noteDao.moveNotes(ids, target.id);

      expect(result.moved.keys, ids);
      expect(result.moved.values.toSet(), {source});
      // A fixed handful of reads, one batched update for all 200 rows.
      expect(counter.selects.length, lessThanOrEqualTo(4));
      expect(counter.executions('UPDATE "notes"'), 200);
      expect(
        counter.matching('UPDATE "notes"'),
        hasLength(1),
        reason: 'one prepared statement for the batch',
      );

      final rows = [for (final id in ids) await noteRow(id)];
      expect(rows.map((r) => r.folderId).toSet(), {target.id});
      expect(rows.map((r) => r.hlcTimestamp).toSet(), hasLength(1));
      expect(
        [for (final row in rows) row.position],
        [for (var i = 0; i < 200; i++) i * positionStride],
      );
      expect(await queued('notes'), ids.toSet());
    });

    test('duplicates are reported per item, against the target and within '
        'the batch; the rest still move', () async {
      final a = await db.folderDao.createFolder(name: 'A');
      final b = await db.folderDao.createFolder(name: 'B');
      final target = await db.folderDao.createFolder(name: 'Target');
      await db.noteDao.createNote(folderId: target.id, title: 'Squat');
      final clash = await db.noteDao.createNote(
        folderId: a.id,
        title: 'squat ',
      );
      final twin1 = await db.noteDao.createNote(folderId: a.id, title: 'Twin');
      final twin2 = await db.noteDao.createNote(folderId: b.id, title: 'twin');
      final blank1 = await db.noteDao.createNote(folderId: a.id, title: '');
      final blank2 = await db.noteDao.createNote(folderId: b.id, title: '');
      final already = await db.noteDao.createNote(
        folderId: target.id,
        title: 'Here',
      );

      final result = await db.noteDao.moveNotes([
        clash.id,
        twin1.id,
        twin2.id,
        blank1.id,
        blank2.id,
        already.id,
        'missing',
      ], target.id);

      expect(result.duplicates, {clash.id, twin2.id});
      expect(result.unchanged, {already.id});
      expect(result.moved.keys, [twin1.id, blank1.id, blank2.id]);
      expect((await noteRow(clash.id)).folderId, a.id);
      expect((await noteRow(twin2.id)).folderId, b.id);
    });

    test('a tombstoned target moves nothing', () async {
      final (_, notes) = await seedNotes(2);
      final target = await db.folderDao.createFolder(name: 'Gone');
      await db.folderDao.softDeleteFolder(target.id);

      final result = await db.noteDao.moveNotes([
        for (final note in notes) note.id,
      ], target.id);

      expect(result.moved, isEmpty);
      expect(await queued('notes'), isEmpty);
    });
  });

  group('FolderDao.moveFolders', () {
    test('names clash at the root too, and within the batch', () async {
      await db.folderDao.createFolder(name: 'Inbox');
      final parent = await db.folderDao.createFolder(name: 'Parent');
      final other = await db.folderDao.createFolder(name: 'Other');
      final clash = await db.folderDao.createFolder(
        name: 'inbox',
        parentId: parent.id,
      );
      final first = await db.folderDao.createFolder(
        name: 'Week',
        parentId: parent.id,
      );
      final second = await db.folderDao.createFolder(
        name: 'WEEK',
        parentId: other.id,
      );
      await db.syncOutboxDao.clear();

      final result = await db.folderDao.moveFolders([
        clash.id,
        first.id,
        second.id,
      ], null);

      expect(result.duplicates, {clash.id, second.id});
      expect(result.moved, {first.id: parent.id});
      expect((await folderRow(first.id)).parentId, isNull);
      expect(await queued('folders'), {first.id});
    });

    test('a folder cannot move under itself or its own subtree', () async {
      final top = await db.folderDao.createFolder(name: 'Top');
      final mid = await db.folderDao.createFolder(
        name: 'Mid',
        parentId: top.id,
      );
      final leaf = await db.folderDao.createFolder(
        name: 'Leaf',
        parentId: mid.id,
      );
      final loose = await db.folderDao.createFolder(name: 'Loose');

      final result = await db.folderDao.moveFolders([
        top.id,
        leaf.id,
        loose.id,
      ], leaf.id);

      expect(result.moved.keys, [loose.id]);
      expect(result.duplicates, isEmpty);
      expect((await folderRow(top.id)).parentId, isNull);
      expect((await folderRow(loose.id)).parentId, leaf.id);
    });

    test('moved folders share one HLC and append after the target', () async {
      final target = await db.folderDao.createFolder(name: 'Target');
      await db.folderDao.createFolder(name: 'Existing', parentId: target.id);
      final picked = [
        for (var i = 0; i < 3; i++)
          await db.folderDao.createFolder(name: 'Pick $i'),
      ];

      await db.folderDao.moveFolders([
        for (final folder in picked) folder.id,
      ], target.id);

      final rows = [for (final folder in picked) await folderRow(folder.id)];
      expect(
        [for (final row in rows) row.position],
        [for (var i = 1; i <= 3; i++) i * positionStride],
      );
      expect(rows.map((r) => r.hlcTimestamp).toSet(), hasLength(1));
      expect(
        [for (final row in rows) row.version],
        [for (final folder in picked) folder.version + 1],
      );
    });
  });

  group('scale', () {
    final stamp = DateTime.utc(2026, 1, 1);

    /// [count] notes `n000…` in one folder at `i * step`, inserted in one
    /// batch; [tombstone] marks one of them deleted, leaving a hole.
    Future<List<String>> seedRaw(int count, int step, {int? tombstone}) async {
      final ids = [for (var i = 0; i < count; i++) 'n${'$i'.padLeft(4, '0')}'];
      await db.batch((b) {
        b.insert(
          db.folders,
          FoldersCompanion.insert(
            id: 'f',
            name: 'Big',
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
        for (var i = 0; i < count; i++) {
          b.insert(
            db.notes,
            NotesCompanion.insert(
              id: ids[i],
              folderId: 'f',
              title: 'Note $i',
              hlcTimestamp: '0',
              deviceId: 'test',
              createdAt: stamp,
              updatedAt: stamp,
              position: Value(i * step),
              isDeleted: Value(i == tombstone),
            ),
          );
        }
      });
      return [
        for (var i = 0; i < count; i++)
          if (i != tombstone) ids[i],
      ];
    }

    Future<int> touchedUpdatedAt() async {
      final rows = await (db.select(
        db.notes,
      )..where((n) => n.updatedAt.equals(stamp).not())).get();
      return rows.length;
    }

    test('the first drag after a title sort puts what the page showed on '
        'top', () async {
      final ids = await seedRaw(120, positionStride);
      // The title-sorted first page, n0060…n0109, with n0109 dragged up.
      final shown = ids.sublist(60, 110);
      final dragged = [shown.last, ...shown.take(49)];

      await db.noteDao.applyOrder(
        folderId: 'f',
        loadedOrder: dragged,
        descending: false,
        windowAtTop: true,
      );

      expect((await readBack('f', desc: false)).take(50), dragged);
    });

    for (final desc in [false, true]) {
      test('a drag in a gapped 1,000-note folder writes at most 3 rows and '
          'no updated_at (desc: $desc)', () async {
        final ids = await seedRaw(1000, positionStride);
        final shown = desc ? ids.reversed.toList() : ids;
        final window = shown.take(50).toList();
        final dragged = [...window];
        dragged.insert(30, dragged.removeAt(3));

        counter.reset();
        await db.noteDao.applyOrder(
          folderId: 'f',
          loadedOrder: dragged,
          descending: desc,
        );
        final written = counter.executions('UPDATE "notes"');

        expect(written, lessThanOrEqualTo(3));
        expect(await touchedUpdatedAt(), 0);
        expect(await readBack('f', desc: desc), [
          ...dragged,
          ...shown.skip(50),
        ]);
      });

      test('a legacy dense folder\'s first drag writes only the shorter '
          'side (desc: $desc)', () async {
        final ids = await seedRaw(300, 1, tombstone: 120);
        final shown = desc ? ids.reversed.toList() : ids;
        final window = shown.take(50).toList();
        // Swap two rows near the top: the head side is 5 rows long.
        final swapped = [...window];
        swapped[4] = window[5];
        swapped[5] = window[4];

        counter.reset();
        await db.noteDao.applyOrder(
          folderId: 'f',
          loadedOrder: swapped,
          descending: desc,
        );
        final written = counter.executions('UPDATE "notes"');
        expect(counter.count, lessThanOrEqualTo(4));

        expect(written, lessThanOrEqualTo(6));
        expect(await touchedUpdatedAt(), 0);
        expect(await readBack('f', desc: desc), [
          ...swapped,
          ...shown.skip(50),
        ]);
      });
    }
  });

  /// The bulk name rule must refuse exactly what one move refuses: the
  /// mover's name folded in Dart, the target's by SQLite, which folds ASCII
  /// only and trims spaces only.
  group('the duplicate-name probe table', () {
    test('notes', () async {
      final source = await db.folderDao.createFolder(name: 'Source');
      final target = await db.folderDao.createFolder(name: 'Target');
      for (final title in ['Șold', 'șase', 'Leg Day', '\t']) {
        await db.noteDao.createNote(folderId: target.id, title: title);
      }
      Future<String> mover(String title) async =>
          (await db.noteDao.createNote(folderId: source.id, title: title)).id;
      final sold = await mover('Șold');
      final sase = await mover('Șase');
      final legDay = await mover('Leg Day\t');
      final tab1 = await mover('\t');
      final tab2 = await mover('\t');

      final result = await db.noteDao.moveNotes([
        sold,
        sase,
        legDay,
        tab1,
        tab2,
      ], target.id);

      // `Șold` folds to `șold` in Dart; SQLite keeps `Șold`: no clash.
      expect(result.moved.keys, [sold, tab1, tab2]);
      // `șase` is already lower case on the target; `\t` is trimmed in Dart.
      expect(result.duplicates, {sase, legDay});
    });

    test('folders', () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');
      await db.folderDao.createFolder(name: 'Plan', parentId: parent.id);
      final mover = await db.folderDao.createFolder(name: 'Plan\u00A0');

      final result = await db.folderDao.moveFolders([mover.id], parent.id);

      expect(result.duplicates, {mover.id});
      expect(result.moved, isEmpty);
    });
  });
}
