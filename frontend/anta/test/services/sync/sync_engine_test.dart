import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/folders_binding.dart';

import 'support/sync_pair.dart';

/// The convergence suite: two databases, one fake space, two engines. Each
/// case writes on one device or both, syncs, and proves the two hold the
/// same rows — or that the one difference D3 allows, a conflict copy, was
/// filed on the right device exactly once.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  Future<void> expectConverged() async {
    expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));
  }

  Future<Folder> folderOn(SyncDevice device, String id) async =>
      (await device.db.folderDao.getFolderById(id))!;

  test('a folder, a 14 KB note, an event, a presence day, a counter and a '
      'term created on A reach B whole', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final body = [for (var i = 0; i < 800; i++) 'Line $i of the log.'].join(
      '\n',
    );
    expect(body.length, greaterThan(14000));
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: body,
    );
    await a().db.calendarEventDao.upsert(eventRow('e1'));
    await a().db.eventAbsenceDao.setStatus(
      'e1',
      DateTime.utc(2026, 3, 29),
      PresenceStatus.present,
    );
    await a().db.counterDao.insertCounterWithValue(
      CountersCompanion(
        id: const Value('c1'),
        name: const Value('Sets'),
        createdAt: Value(DateTime.utc(2026, 10, 1)),
      ),
      5,
    );
    await a().db.vocabularyDao.importVocabulary(
      VocabulariesCompanion(
        id: const Value('v1'),
        name: const Value('Exercises'),
        createdAt: Value(DateTime.utc(2026, 1, 1)),
        updatedAt: Value(DateTime.utc(2026, 1, 1)),
      ),
    );
    await a().db.vocabularyDao.importItem(
      VocabularyItemsCompanion(
        id: const Value('i1'),
        vocabularyId: const Value('v1'),
        term: const Value('Squat'),
        createdAt: Value(DateTime.utc(2026, 1, 1)),
        updatedAt: Value(DateTime.utc(2026, 1, 1)),
      ),
    );

    final pushed = await a().sync();
    final pulled = await b().sync();

    expect(pushed.failure, isNull);
    expect(pushed.pushedRows, 8);
    expect(pulled.pulledRows, 8);
    final rows = await SyncPair.snapshot(b());
    expect(
      rows.keys,
      containsAll([
        'folders/${folder.id}',
        'notes/${note.id}',
        'calendar_events/e1',
        'calendar_event_absences/e1|${DateTime.utc(2026, 3, 29).millisecondsSinceEpoch}',
        'counters/c1',
        'counter_values/c1|',
        'vocabularies/v1',
        'vocabulary_items/i1',
      ]),
    );
    await expectConverged();
    expect(await b().db.contentChunkDao.loadContent(note.id), body);
    expect(await a().db.syncOutboxDao.count(), 0);
    expect(await b().db.syncOutboxDao.count(), 0);
  });

  test('edits of different rows on both devices all arrive', () async {
    final onA = await a().db.folderDao.createFolder(name: 'From A');
    final onB = await b().db.folderDao.createFolder(name: 'From B');

    await a().sync();
    await b().sync();
    await a().sync();

    expect((await folderOn(a(), onB.id)).name, 'From B');
    expect((await folderOn(b(), onA.id)).name, 'From A');
    await expectConverged();
  });

  test('both devices editing one event end on the later edit', () async {
    await a().db.calendarEventDao.upsert(eventRow('e1'));
    await a().sync();
    await b().sync();

    await a().db.calendarEventDao.upsert(eventRow('e1', title: 'From A'));
    await b().db.calendarEventDao.upsert(eventRow('e1', title: 'From B'));
    await a().sync();
    await b().sync();
    await a().sync();

    for (final device in [a(), b()]) {
      final event = await device.db.select(device.db.calendarEvents).getSingle();
      expect(event.title, 'From B', reason: device.id);
    }
    await expectConverged();
  });

  test('the device whose unpushed note edit loses files one conflict copy, '
      'the other none', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );
    await a().sync();
    await b().sync();
    a().hooks.clear();
    b().hooks.clear();

    await editNote(a(), note.id, 'typed on A');
    await editNote(b(), note.id, 'typed on B');
    await b().sync();
    await a().sync();
    await b().sync();
    await a().sync();

    final conflict = a().hooks.conflicts.single;
    expect(conflict.loser.id, note.id);
    expect(conflict.loserContent, 'typed on A');
    expect(b().hooks.conflicts, isEmpty);
    for (final device in [a(), b()]) {
      expect(
        await device.db.contentChunkDao.loadContent(note.id),
        'typed on B',
        reason: device.id,
      );
    }
    await expectConverged();
  });

  test('a note deleted on A is tombstoned on B, its chunks too', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'body',
    );
    await a().sync();
    await b().sync();

    await a().db.noteDao.softDeleteNote(note.id);
    await a().sync();
    await b().sync();

    expect((await b().db.noteDao.getNoteById(note.id))!.isDeleted, isTrue);
    final live = await b().db
        .customSelect(
          'SELECT COUNT(*) AS n FROM content_chunks '
          'WHERE note_id = ? AND is_deleted = 0',
          variables: [Variable<String>(note.id)],
        )
        .getSingle();
    expect(live.read<int>('n'), 0);
    await expectConverged();
  });

  test('a folder deleted with its two notes on A is deleted whole on B', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Old');
    final notes = [
      for (final title in ['One', 'Two'])
        await writeNote(a(), folderId: folder.id, title: title, body: title),
    ];
    await a().sync();
    await b().sync();

    await a().db.folderDao.softDeleteFolderWithDescendants(folder.id);
    await a().sync();
    await b().sync();

    expect((await folderOn(b(), folder.id)).isDeleted, isTrue);
    for (final note in notes) {
      expect((await b().db.noteDao.getNoteById(note.id))!.isDeleted, isTrue);
    }
    await expectConverged();
  });

  test('a newer upsert over a tombstone resurrects the row on both', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Kept');
    await a().sync();
    await b().sync();
    await a().db.folderDao.softDeleteFolder(folder.id);
    await a().sync();
    await b().sync();
    final tombstone = HlcTimestamp.parse(
      (await folderOn(a(), folder.id)).hlcTimestamp,
    );

    final newer = HlcTimestamp(
      wallTime: tombstone.wallTime + 1000,
      logicalCounter: 0,
      nodeId: 'C',
    ).toString();
    await pair.gateway.pushBatch(
      pair.space,
      [folderEnvelope(folder.id, newer, name: 'Back')],
      pushedBy: 'C',
      schema: syncSchema,
    );
    await a().sync();
    await b().sync();

    for (final device in [a(), b()]) {
      final row = await folderOn(device, folder.id);
      expect((row.isDeleted, row.name), (false, 'Back'), reason: device.id);
    }
    await expectConverged();
  });

  test('a row pushed late under a lower stamp still reaches a device whose '
      'cursor passed higher ones', () async {
    await a().db.folderDao.createFolder(name: 'High');
    await a().sync();
    await b().sync();
    await a().sync();

    // B holds a row stamped below everything A has pulled, queued at its own
    // stamp — a phone that edited offline and pushes now.
    await const FoldersBinding().mergeRemote(
      b().db,
      folderEnvelope('late', '000000000001:0000:B', name: 'Late', deviceId: 'B'),
    );
    await b().db.syncOutboxDao.requeueRow('folders', 'late');
    expect((await b().sync()).pushedRows, 1);

    await a().sync();

    expect((await folderOn(a(), 'late')).name, 'Late');
    await expectConverged();
  });

  test('rows re-delivered on a resumed page change nothing', () async {
    for (final name in ['One', 'Two', 'Three']) {
      await b().db.folderDao.createFolder(name: name);
    }
    await b().sync();
    await a().sync();
    pair.gateway.replayOnResume = 2;
    a().hooks.clear();
    final before = await SyncPair.snapshot(a());

    final report = await a().sync();

    expect(report.pulledRows, 2);
    final rows = [for (final page in a().hooks.pages) ...page.$2];
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.result), everyElement(MergeResult.unchanged));
    expect(a().hooks.runs, isEmpty, reason: 'nothing changed here');
    expect(await SyncPair.snapshot(a()), before);
    expect(await a().db.syncOutboxDao.count(), 0);
  });

  test('an older push over a newer document is repaired by the device that '
      'holds the newer row', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Base');
    await a().sync();
    await b().sync();

    await a().db.folderDao.updateFolder(id: folder.id, name: 'Older, from A');
    await b().db.folderDao.updateFolder(id: folder.id, name: 'Newer, from B');
    await b().sync();
    // A pushes without pulling first — the window §3.4 repairs.
    final stale = await const FoldersBinding().encode(
      a().db,
      await folderOn(a(), folder.id),
      boundUid: syncUid,
    );
    await pair.gateway.pushBatch(
      pair.space,
      [stale],
      pushedBy: 'A',
      schema: syncSchema,
    );
    expect(pair.gateway.rowsOf(pair.space, 'folders')[folder.id], stale);
    b().hooks.clear();

    final repair = await b().sync();
    await a().sync();

    expect(b().hooks.pages.single.$2.single.result, MergeResult.keptLocal);
    expect(repair.pushedRows, 1);
    for (final device in [a(), b()]) {
      expect(
        (await folderOn(device, folder.id)).name,
        'Newer, from B',
        reason: device.id,
      );
    }
    await expectConverged();
  });

  group('the initial merge under the floor', () {
    setUp(() async {
      await pair.close();
      pair = await SyncPair.open(bind: false);
    });

    test('a never-bound database yields a renamed built-in to the space, '
        'then ends the initial merge', () async {
      await a().db.calendarCategoryDao.insertCategory(birthdayCategory());
      await pair.bind(a());
      await a().sync();
      await b().db.calendarCategoryDao.insertCategory(birthdayCategory());
      await b().db.calendarCategoryDao.updateCategory(
        birthdayCategory(name: 'Birthdays, mine'),
      );
      await pair.bind(b());

      final report = await b().sync();

      final category = await b().db
          .select(b().db.calendarCategories)
          .getSingle();
      expect(category.name, 'Birthday');
      expect(report.pushedRows, 0, reason: 'the stale entry was dropped');
      expect(
        await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
        isNull,
      );
      expect(
        b().statuses.map((s) => s.downloadedRows),
        contains(greaterThan(0)),
      );
      expect(b().engine.current.downloadedRows, 0);
      await expectConverged();
    });

    test('an unbound-then-rebound database keeps an edit made after the '
        'unbind and yields the rest', () async {
      await pair.bind(a());
      await pair.bind(b());
      final kept = await a().db.folderDao.createFolder(name: 'X');
      final yielded = await a().db.folderDao.createFolder(name: 'Y');
      await a().sync();
      await b().sync();

      await a().db.folderDao.updateFolder(id: yielded.id, name: 'Y from A');
      await a().sync();
      // B's edit is newer than A's, but made before the unbind: it is at or
      // below the floor the unbind writes, so the space wins it.
      await b().db.folderDao.updateFolder(id: yielded.id, name: 'Y from B');
      await b().binding.unbind();
      await b().db.folderDao.updateFolder(id: kept.id, name: 'X after unbind');
      await pair.bind(b());

      await b().sync();
      await a().sync();

      for (final device in [a(), b()]) {
        expect((await folderOn(device, yielded.id)).name, 'Y from A');
        expect((await folderOn(device, kept.id)).name, 'X after unbind');
      }
      await expectConverged();
    });
  });

  test('a run pulls every table in order before it pushes', () async {
    await a().db.folderDao.createFolder(name: 'Training');
    pair.gateway.calls.clear();

    await a().sync();

    expect(pair.gateway.calls, [
      for (final binding in syncTableBindings) 'pull:${binding.table}',
      'push:A',
    ]);
  });

  test('a page is one transaction: one clock write per page, the cursor '
      'stored with it', () async {
    for (var i = 0; i <= pair.gateway.maxBatch; i++) {
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          'f$i',
          '${(i + 1).toRadixString(16).padLeft(12, '0')}:0000:C',
        ),
      );
    }
    a().statements.reset();

    final report = await a().sync();

    expect(report.pulledRows, pair.gateway.maxBatch + 1);
    final clockWrites = [
      for (final s in a().statements.captured)
        if (s.sql.contains('sync_metadata') && s.args.contains('last_hlc')) s,
    ];
    expect(clockWrites, hasLength(2));
    expect(
      a().hooks.calls.where((c) => c == 'before:folders'),
      hasLength(2),
    );
    expect(
      await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
      '${pair.gateway.maxBatch + 1}',
    );
  });

  test('"hasMore, then an empty page" ends the table without a write', () async {
    pair.gateway.looseHasMore = true;
    for (var i = 0; i < pair.gateway.maxBatch; i++) {
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          'f$i',
          '000000000100:${i.toRadixString(16).padLeft(4, '0')}:C',
        ),
      );
    }
    a().statements.reset();
    pair.gateway.calls.clear();

    final report = await a().sync();

    expect(report.pulledRows, pair.gateway.maxBatch);
    expect(pair.gateway.calls.where((c) => c == 'pull:folders'), hasLength(2));
    expect(
      a().hooks.calls.where((c) => c == 'before:folders'),
      hasLength(1),
    );
  });
}
