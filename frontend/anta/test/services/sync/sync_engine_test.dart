import 'dart:ui' show Locale;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/conflict_copy_title.dart';
import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
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

  test('a counter tap made during a counter page is kept on both devices '
      'after the next push (S3c review H1)', () async {
    final counters = await CounterService.forTesting(a().db);
    final id = await counters.addCounter(name: 'Sets', startValue: 3);
    await a().sync();
    await b().sync();
    await b().db.counterDao.upsertValue(id, '', 8);
    await b().sync();
    final production = AppSyncApplyHooks(counters: () async => counters);
    var tapped = false;
    a().hooks.onBeforePage = (table) async {
      await production.beforePage(table);
      if (table == 'counter_values' && !tapped) {
        tapped = true;
        await counters.incrementGlobal(id);
      }
    };
    a().hooks.onAfterPage = production.afterPage;

    await a().sync();

    expect(tapped, isTrue);
    expect(counters.getGlobalValue(id), 9);
    await counters.flush();
    await a().sync();
    await b().sync();

    for (final device in [a(), b()]) {
      expect(await device.db.counterDao.getValue(id, ''), 9, reason: device.id);
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

  group('the conflict copy inside the page', () {
    late Folder folder;
    late Note note;

    /// A's unpushed edit of the note is about to lose to B's newer one.
    setUp(() async {
      folder = await a().db.folderDao.createFolder(name: 'Training');
      note = await writeNote(a(), folderId: folder.id, title: 'Log', body: 'base');
      await a().sync();
      await b().sync();
      await editNote(a(), note.id, 'typed on A');
      await editNote(b(), note.id, 'typed on B');
      await b().sync();
    });

    Future<List<String>> queuedOnA() async => [
      for (final e in await a().db.syncOutboxDao.pending())
        '${e.syncedTable}/${e.rowKey}',
    ];

    test('a copy that fails rolls its page back: the local note, its chunks, '
        'its queue entry and the cursor stay, and the next run files it', () async {
      final cursor = await a().db.syncDao.getValue(
        SyncDao.keyPullCursor('notes'),
      );
      a().hooks.onConflict = (_) async => throw StateError('title clash');

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.unknown);
      expect(
        await a().db.contentChunkDao.loadContent(note.id),
        'typed on A',
      );
      expect(await queuedOnA(), contains('notes/${note.id}'));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
        cursor,
      );
      final remote = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
      expect(remote.deviceId, 'B', reason: 'the losing edit was not pushed');

      a().hooks.onConflict = null;
      await a().sync();

      expect(a().hooks.conflicts.single.loserContent, 'typed on A');
      expect(
        await a().db.contentChunkDao.loadContent(note.id),
        'typed on B',
      );
    });

    test('a rolled-back page leaves the clock where it was, and the retry '
        'moves it', () async {
      final remote = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.hlc;
      final before = a().db.hlc.last.toString();
      a().hooks.onConflict = (_) async => throw StateError('title clash');

      await a().sync();

      // `hlc.update` is in memory and no rollback undoes it. Advanced
      // inside the page, this device could mint above a remote row it
      // never merged — and that row would then lose on every device with
      // no conflict copy, the one outcome §3.9 exists to prevent (R65).
      expect(a().db.hlc.last.toString(), before);

      a().hooks.onConflict = null;
      await a().sync();

      // The retry commits, and the clock is then at or past the stamp it
      // merged — the node is dropped, since this device's own is its own.
      String tick(String stamp) => stamp.substring(0, stamp.lastIndexOf(':'));
      expect(
        tick(a().db.hlc.last.toString()).compareTo(tick(remote)),
        greaterThanOrEqualTo(0),
      );
    });

    test('a copy is filed after its page merged and before its cursor moved, '
        'and commits with the merge', () async {
      final cursor = await a().db.syncDao.getValue(
        SyncDao.keyPullCursor('notes'),
      );
      String? mergedBody;
      String? cursorWithin;
      a().hooks.onConflict = (conflict) async {
        mergedBody = await a().db.contentChunkDao.loadContent(note.id);
        cursorWithin = await a().db.syncDao.getValue(
          SyncDao.keyPullCursor('notes'),
        );
        final copy = await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log (copy)',
          body: conflict.loserContent,
        );
        return copy.id;
      };

      await a().sync();

      expect(mergedBody, 'typed on B');
      expect(cursorWithin, cursor);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
        isNot(cursor),
      );
      final copy = (await a().db.noteDao.getNotesByFolder(folder.id))
          .singleWhere((n) => n.title == 'Log (copy)');
      expect(await a().db.contentChunkDao.loadContent(copy.id), 'typed on A');
    });

    test('a committed page hands its copy to afterPage once, as an inserted '
        'note beside the merged one', () async {
      a().hooks.clear();
      String? filed;
      a().hooks.onConflict = (conflict) async {
        final copy = await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log (copy)',
          body: conflict.loserContent,
        );
        return filed = copy.id;
      };

      final report = await a().sync();

      final notePages = [
        for (final (table, rows) in a().hooks.pages)
          if (table == 'notes') rows,
      ];
      final copyRows = [
        for (final rows in notePages)
          for (final row in rows)
            if (row.rowKey == filed) row,
      ];
      expect(copyRows, [
        SyncAppliedRow(
          rowKey: filed!,
          result: MergeResult.inserted,
          tombstone: false,
          // The body the page wrote rides with the row, as it does for a
          // merged note (R4).
          content: 'typed on A',
        ),
      ]);
      expect(
        notePages.expand((rows) => rows).map((r) => r.rowKey),
        contains(note.id),
      );
      expect(report.failure, isNull);
    });

    /// The one engine case that runs the **production** copy rather than a
    /// hand-written one: `AppSyncApplyHooks.fileConflictCopy` is the app's
    /// only unguarded hook, so nothing above it catches what it throws
    /// (A5 review R106).
    test("the production hook files the copy with D3's title, beside the "
        'note it came from, and the engine announces and queues it', () async {
      initializeDateFormatting('en');
      final strings = lookupAppLocalizations(const Locale('en'));
      final filedAt = DateTime(2026, 10, 27, 9, 30);
      final notes = NoteRepository(database: a().db);
      final production = AppSyncApplyHooks(
        notes: () => notes,
        folders: () => FolderRepository(database: a().db),
        noteStorage: () => NoteStorageService(repository: notes),
        strings: () async => strings,
        now: () => filedAt,
      );
      a().hooks.clear();
      a().hooks.onConflict = production.fileConflictCopy;

      final report = await a().sync();

      expect(report.failure, isNull);
      final announced = [
        for (final (table, rows) in a().hooks.pages)
          if (table == 'notes')
            for (final row in rows)
              if (row.rowKey != note.id) row,
      ];
      expect(announced, hasLength(1));
      expect(announced.single.result, MergeResult.inserted);
      final copy = (await a().db.noteDao.getNoteById(announced.single.rowKey))!;
      expect(copy.title, conflictCopyTitle(strings, 'Log', filedAt));
      expect(copy.folderId, folder.id);
      expect(await a().db.contentChunkDao.loadContent(copy.id), 'typed on A');
      // Stamped and queued like any local note, so the same run pushed it and
      // the other device receives the losing text too (record §3.9).
      expect(
        pair.gateway.rowsOf(pair.space, 'notes').keys,
        contains(copy.id),
      );
    });

    test('a page that rolls back hands its copy to no afterPage', () async {
      a().hooks.clear();
      String? filed;
      a().hooks.onConflict = (conflict) async {
        final copy = await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log (copy)',
          body: conflict.loserContent,
        );
        filed = copy.id;
        throw StateError('the page failed after the copy');
      };

      await a().sync();

      expect(filed, isNotNull);
      expect(
        [
          for (final (_, rows) in a().hooks.pages)
            for (final row in rows) row.rowKey,
        ],
        isNot(contains(filed)),
      );
      expect(await a().db.noteDao.getNoteById(filed!), isNull);
    });
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

    // And the snapshot sees a tombstoned row's columns: a tombstone carries
    // no data, so comparing the wire alone called two rows equal however
    // far their columns had drifted (A7 R103).
    await b().db.customUpdate(
      'UPDATE notes SET title = ? WHERE id = ?',
      variables: [Variable<String>('Drifted'), Variable<String>(note.id)],
      updates: {b().db.notes},
    );
    expect(await SyncPair.snapshot(b()), isNot(await SyncPair.snapshot(a())));
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

    group('with a started engine that has no signal yet', () {
      late Folder kept;
      late Folder yielded;

      String? spaceName(String id) =>
          pair.gateway.rowsOf(pair.space, 'folders')[id]?.data?[JsonKeys.name]
              as String?;

      /// The unbound-then-rebound case, B's engine started while unbound so
      /// no run and no signal reached it before the rebind.
      setUp(() async {
        await pair.bind(a());
        await pair.bind(b());
        kept = await a().db.folderDao.createFolder(name: 'X');
        yielded = await a().db.folderDao.createFolder(name: 'Y');
        await a().sync();
        await b().sync();
        await a().db.folderDao.updateFolder(id: yielded.id, name: 'Y from A');
        await a().sync();
        await b().db.folderDao.updateFolder(id: yielded.id, name: 'Y from B');
        await b().binding.unbind();
        await b().engine.start();
        await b().settle();
        await b().db.folderDao.updateFolder(id: kept.id, name: 'X after unbind');
        await pair.bind(b());
      });

      Future<void> expectNewerEverywhere() async {
        await a().sync();
        for (final device in [a(), b()]) {
          expect((await folderOn(device, yielded.id)).name, 'Y from A');
          expect((await folderOn(device, kept.id)).name, 'X after unbind');
        }
        expect(spaceName(yielded.id), 'Y from A');
        await expectConverged();
      }

      test('going to the background pushes nothing before the floor pull', () async {
        pair.gateway.calls.clear();

        final report = await b().engine.onAppBackgrounded();

        // Named, not merely a drain that pushed nothing: the caller has to
        // tell this apart from a drain that ran (R56, A7 review R142).
        expect(report.skipped, SyncRunSkip.initialMergePending);
        expect(pair.gateway.calls, isEmpty);
        expect(spaceName(yielded.id), 'Y from A');
        expect(
          await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
          isNotNull,
        );

        b().engine.onAppResumed();
        await b().settle();
        await expectNewerEverywhere();
      });

      test('the debounced drain pulls everything under the floor before it '
          'pushes', () async {
        pair.gateway.calls.clear();
        await pumpEventQueue();

        expect(b().scheduler.fire(const Duration(seconds: 30)), 1);
        await b().settle();

        expect(pair.gateway.calls.first, 'pull:calendar_categories');
        expect(
          pair.gateway.calls.indexOf('push:B'),
          greaterThan(pair.gateway.calls.indexOf('pull:vocabulary_items')),
        );
        expect(spaceName(yielded.id), 'Y from A');
        await expectNewerEverywhere();
      });
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

  test('a page with a cursor and hasMore but no envelope advances the table '
      'past it', () async {
    for (var i = 0; i <= pair.gateway.maxBatch; i++) {
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          'f$i',
          '${(i + 1).toRadixString(16).padLeft(12, '0')}:0000:C',
        ),
      );
      // Every document of the first page is one this build cannot read; the
      // row past them must still arrive.
      if (i < pair.gateway.maxBatch) {
        pair.gateway.unreadable.add(('folders', 'f$i'));
      }
    }

    final report = await a().sync();

    expect(report.pulledRows, 1);
    expect(await a().db.folderDao.getFolderById('f500'), isNotNull);
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
