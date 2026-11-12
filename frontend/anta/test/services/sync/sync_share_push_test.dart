import 'dart:ui' show AppLifecycleState;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/calendar_categories_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_occurrences_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_skips_binding.dart';
import 'package:anta/services/sync/tables/calendar_events_binding.dart';
import 'package:anta/services/sync/tables/folders_binding.dart';

import 'support/sync_pair.dart';

/// What sharing puts on the wire (`docs/cloud-sharing-foundations.md` §3,
/// §4), from the owner's side: two devices of one account over the fake
/// gateway. A marked event or folder carries its mark in its row; every
/// document that is shared — the root, and what hangs under it — names the
/// pair beside its data; the space names the pair its notes are shared
/// into. Nothing here reads a partner's rows: that is the reader's suite.
void main() {
  late SyncPair pair;

  // The server's time on the devices' own clock: what a device says again
  // can depend on whether a push landed before or after it decided
  // something, and that has to follow from the order a test acts in.
  setUp(() async => pair = await SyncPair.open(serverOnDeviceClock: true));
  tearDown(() async => pair.close());

  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  const pairId = 'pair-1';
  final day = DateTime.utc(2026, 6, 1);

  /// The document the space holds for each row, as `table/key`.
  Map<String, SyncEnvelope> documents() => {
    for (final binding in syncTableBindings)
      for (final MapEntry(:key, :value)
          in pair.gateway.rowsOf(pair.space, binding.table).entries)
        '${binding.table}/$key': value,
  };

  /// Writes [device]'s row [key] of [binding]'s table into the space as its
  /// drain would have — [sharedPair] what its document says — and retires
  /// its entry: a push that landed, staged without running the engine, so a
  /// test decides what the device knew when it pushed.
  Future<void> pushedAs<R extends Object>(
    SyncDevice device,
    SyncTableBinding<R> binding,
    String key, {
    required String? sharedPair,
  }) async {
    final row = (await binding.loadByKeys(device.db, [key])).single;
    final envelope = await binding.encode(device.db, row, boundUid: syncUid);
    pair.gateway.plant(
      pair.space,
      envelope.sharedInto(sharedPair),
      pushedBy: device.id,
    );
    await device.db.syncOutboxDao.ackThrough(binding.table, key, envelope.hlc);
  }

  /// The rows whose newest document names a pair, with the pair.
  Map<String, String> shared() => {
    for (final MapEntry(:key, :value) in documents().entries)
      key: ?value.sharedPair,
  };

  Future<void> event(SyncDevice device, String id) =>
      device.db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: id,
          title: 'Event $id',
          category: 'general',
          startDate: day,
          ruleKind: 'weekly',
          createdAt: day,
          updatedAt: day,
        ),
      );

  String dayKey(String table, String eventId) =>
      '$table/${dayRowKey(eventId, day)}';

  /// Starts [device]'s engine in the background, where its first run only
  /// drains, as an update installed while the phone was locked would.
  Future<void> startInBackground(SyncDevice device) async {
    device.lifecycleState = AppLifecycleState.paused;
    await device.engine.start();
    await device.settle();
  }

  Future<void> resume(SyncDevice device) async {
    device.lifecycleState = AppLifecycleState.resumed;
    device.engine.onAppResumed();
    await device.settle();
  }

  test('nothing shared: no document names a pair, and neither does the '
      'space', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    await writeNote(a(), folderId: folder.id, title: 'Log', body: 'Row');
    await event(a(), 'e1');

    await a().sync();

    expect(documents(), isNotEmpty);
    expect(shared(), isEmpty);
    expect(pair.gateway.sharedPairOf(pair.space), isNull);
  });

  group('a shared event', () {
    setUp(() async {
      await event(a(), 'e1');
      await event(a(), 'e2');
      await a().db.eventSkipDao.markSkipped('e1', day);
      await a().db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: day,
          description: 'Bring the keys',
          createdAt: day,
          updatedAt: day,
        ),
      );
      await a().db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.missed);
      await a().db.eventSkipDao.markSkipped('e2', day);
      await a().sync();
    });

    test('names the pair on its document and on its skipped days and '
        'per-day texts — never on a presence mark, another event or its '
        'rows — and carries the mark in its own data', () async {
      await a().db.calendarEventDao.setSharedPair('e1', pairId);
      await a().sync();

      expect(shared(), {
        'calendar_events/e1': pairId,
        dayKey('calendar_event_skips', 'e1'): pairId,
        dayKey('calendar_event_occurrences', 'e1'): pairId,
      });
      expect(documents()['calendar_events/e1']!.data!['sharedPair'], pairId);
      expect(
        documents()[dayKey('calendar_event_skips', 'e1')]!.data!.containsKey(
          'sharedPair',
        ),
        isFalse,
        reason: 'a day row stores no mark: its document says it',
      );
      expect(
        documents().keys,
        contains(dayKey('calendar_event_absences', 'e1')),
      );
      // An event shares no note text.
      expect(pair.gateway.sharedPairOf(pair.space), isNull);
    });

    test('made private again, every one of those documents stops naming '
        'the pair with its next push', () async {
      await a().db.calendarEventDao.setSharedPair('e1', pairId);
      await a().sync();

      await a().db.calendarEventDao.setSharedPair('e1', null);
      await a().sync();

      expect(shared(), isEmpty);
      expect(
        documents()['calendar_events/e1']!.data!.containsKey('sharedPair'),
        isFalse,
      );
    });

    test('deleted, its tombstones still name the pair: the partner has to '
        'hear of the delete', () async {
      await a().db.calendarEventDao.setSharedPair('e1', pairId);
      await a().sync();

      await a().db.calendarEventDao.tombstoneEventCascade('e1');
      await a().sync();

      final event = documents()['calendar_events/e1']!;
      expect(event.op, OutboxOp.tombstone);
      expect(event.sharedPair, pairId);
      expect(shared()[dayKey('calendar_event_skips', 'e1')], pairId);
      expect(shared()[dayKey('calendar_event_occurrences', 'e1')], pairId);
    });

    test('a day row written later is shared from its first push', () async {
      await a().db.calendarEventDao.setSharedPair('e1', pairId);
      await a().sync();
      final later = DateTime.utc(2026, 6, 8);

      await a().db.eventSkipDao.markSkipped('e1', later);
      await a().sync();

      expect(
        shared()['calendar_event_skips/${dayRowKey('e1', later)}'],
        pairId,
      );
    });

    test('reaches the account\'s other device with its mark, and a day row '
        'that device writes is shared too', () async {
      await a().db.calendarEventDao.setSharedPair('e1', pairId);
      await a().sync();
      await b().sync();

      final merged = (await b().db.calendarEventDao.getByIdsIncludingDeleted([
        'e1',
      ])).single;
      expect(merged.sharedPair, pairId);
      expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));

      final later = DateTime.utc(2026, 6, 8);
      await b().db.eventSkipDao.markSkipped('e1', later);
      await b().sync();
      expect(
        shared()['calendar_event_skips/${dayRowKey('e1', later)}'],
        pairId,
      );
    });

    group('a day text the other device pushed before it had merged a '
        'change of the event\'s mark', () {
      const texts = CalendarEventOccurrencesBinding();
      final textKey = dayRowKey('e1', day);
      final text = dayKey('calendar_event_occurrences', 'e1');

      Future<void> rewriteOnB(String description) =>
          b().db.eventOccurrenceDao.upsert(
            EventOccurrenceDescriptionsCompanion.insert(
              eventId: 'e1',
              day: day,
              description: description,
              createdAt: day,
              updatedAt: day,
            ),
          );

      test('is said again once it merges the mark, though its own push, '
          'read back in that pull, retires the entry the merge '
          'queued', () async {
        await b().sync();
        await a().db.calendarEventDao.setSharedPair('e1', pairId);
        await a().sync();
        // B does not hold the mark yet: its edit went out private, over the
        // shared document A wrote.
        await rewriteOnB('Bring the keys and the papers');
        await pushedAs(b(), texts, textKey, sharedPair: null);
        expect(shared().containsKey(text), isFalse);

        await b().sync();

        expect(shared()[text], pairId);
        expect(
          documents()[text]!.data!['description'],
          'Bring the keys and the papers',
        );
      });

      test('stops naming the pair once it merges the end of the share: a '
          'document must not outlive the share it was written under', () async {
        await a().db.calendarEventDao.setSharedPair('e1', pairId);
        await a().sync();
        await b().sync();
        await a().db.calendarEventDao.setSharedPair('e1', null);
        await a().sync();
        expect(shared(), isEmpty);
        // B still holds the mark: its edit went out shared, after the owner
        // had made the event private again.
        await rewriteOnB('Bring the keys and the papers');
        await pushedAs(b(), texts, textKey, sharedPair: pairId);
        expect(shared()[text], pairId);

        await b().sync();

        expect(shared(), isEmpty);
        expect(
          documents()[text]!.data!['description'],
          'Bring the keys and the papers',
        );
      });

      /// B's copy of the text as another device, [by], pushed it now,
      /// naming [sharedPair].
      Future<void> plantedBy(String by, {required String? sharedPair}) async {
        final row = (await texts.loadByKeys(b().db, [textKey])).single;
        pair.gateway.plant(
          pair.space,
          (await texts.encode(
            b().db,
            row,
            boundUid: syncUid,
          )).sharedInto(sharedPair),
          pushedBy: by,
        );
      }

      test('pushed shared by another device, after everything this one '
          'knows of the event, where this one holds it private, is said '
          'private again all the same: that device may never come back, and '
          'a share must not outlive its end on the chance that it '
          'will', () async {
        await b().sync();
        await plantedBy('C', sharedPair: pairId);
        expect(shared()[text], pairId);

        await b().sync();

        expect(shared(), isEmpty);
      });

      test('pushed private by another device, after everything this one '
          'knows of the event, where this one holds it shared, is left to '
          'that device: one that may be behind never says "shared" over '
          'another\'s "private"', () async {
        await a().db.calendarEventDao.setSharedPair('e1', pairId);
        await a().sync();
        await b().sync();
        await plantedBy('C', sharedPair: null);
        final before = pair.gateway.pushes.length;

        await b().sync();

        expect(pair.gateway.pushes, hasLength(before));
        expect(shared().containsKey(text), isFalse);
      });

      test('written private where the share had not arrived, and pushed '
          'before this device shared the event, is said shared by this one: '
          'the newer text retired the entry its own mark had queued, and '
          'the device that wrote it could not have known', () async {
        await b().sync();
        await rewriteOnB('Written on B before A shared');
        await pushedAs(b(), texts, textKey, sharedPair: null);

        await a().db.calendarEventDao.setSharedPair('e1', pairId);
        await a().sync();

        expect(shared()[text], pairId);
        expect(
          documents()[text]!.data!['description'],
          'Written on B before A shared',
        );
      });

      test('written shared where the end of the share had not arrived, '
          'after that end was decided on a device with no connection, is '
          'made private once that device syncs — however long after', () async {
        await a().db.calendarEventDao.setSharedPair('e1', pairId);
        await a().sync();
        await b().sync();
        // A ends the share offline. B, still holding the mark, pushes a new
        // text long after by the server's clock, and goes away.
        await a().db.calendarEventDao.setSharedPair('e1', null);
        pair.gateway.elapse(const Duration(days: 730));
        await rewriteOnB('Written on B while A was away');
        await pushedAs(b(), texts, textKey, sharedPair: pairId);
        expect(shared()[text], pairId);

        await a().sync();

        expect(shared(), isEmpty);
        expect(
          documents()[text]!.data!['description'],
          'Written on B while A was away',
        );
      });

      test('pushed by another device before this one ended the share is '
          'made private by this one at once — that device may be offline '
          'for days', () async {
        await a().db.calendarEventDao.setSharedPair('e1', pairId);
        await a().sync();
        await b().sync();
        // A's last word before it went offline: a new text, shared.
        await a().db.eventOccurrenceDao.upsert(
          EventOccurrenceDescriptionsCompanion.insert(
            eventId: 'e1',
            day: day,
            description: 'Written on A, then A went offline',
            createdAt: day,
            updatedAt: day,
          ),
        );
        await pushedAs(a(), texts, textKey, sharedPair: pairId);

        // B has not pulled that text when the owner ends the share on it.
        await b().db.calendarEventDao.setSharedPair('e1', null);
        await b().sync();

        expect(shared(), isEmpty);
        expect(
          documents()[text]!.data!['description'],
          'Written on A, then A went offline',
        );
      });
    });
  });

  group('a shared folder', () {
    late Folder shelf;
    late Folder box;
    late Folder beside;
    late Note top;
    late Note low;
    late Note apart;

    setUp(() async {
      shelf = await a().db.folderDao.createFolder(name: 'Shelf');
      box = await a().db.folderDao.createFolder(
        name: 'Box',
        parentId: shelf.id,
      );
      beside = await a().db.folderDao.createFolder(name: 'Beside');
      top = await writeNote(a(), folderId: shelf.id, title: 'Top', body: 'One');
      low = await writeNote(a(), folderId: box.id, title: 'Low', body: 'Two');
      apart = await writeNote(
        a(),
        folderId: beside.id,
        title: 'Apart',
        body: 'Three',
      );
      await a().sync();
    });

    test('names the pair on itself and on every folder and note under it — '
        'never on a note\'s text, nor beside it — and the space names '
        'it for the text', () async {
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      expect(shared(), {
        'folders/${shelf.id}': pairId,
        'folders/${box.id}': pairId,
        'notes/${top.id}': pairId,
        'notes/${low.id}': pairId,
      });
      expect(documents()['folders/${shelf.id}']!.data!['sharedPair'], pairId);
      expect(
        documents()['folders/${box.id}']!.data!.containsKey('sharedPair'),
        isFalse,
        reason: 'derived: only the marked folder stores it',
      );
      expect(
        documents().keys,
        contains('content_chunks/${ChunkHasher.hash('One')}'),
      );
      expect(documents().keys, contains('notes/${apart.id}'));
      expect(pair.gateway.sharedPairOf(pair.space), pairId);
    });

    test('no longer shared, its documents and the space stop naming the '
        'pair', () async {
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      await a().db.folderDao.setSharedPair(shelf.id, null);
      await a().sync();

      expect(shared(), isEmpty);
      expect(pair.gateway.sharedPairOf(pair.space), isNull);
    });

    test('renamed on a device that last ran below the wire that carries '
        'share marks waits there for the folders\' re-read: a run that only '
        'drains does not send it private over the mark', () async {
      await b().sync();
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();
      await b().db.syncDao.setValue(
        SyncDao.keyWireVersion,
        '${DatabaseSchema.shareWireVersion - 1}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b().db.folderDao.updateFolder(id: shelf.id, name: 'Rack');

      await startInBackground(b());

      expect(documents()['folders/${shelf.id}']!.sharedPair, pairId);
      expect(documents()['folders/${shelf.id}']!.data!['name'], 'Shelf');

      await resume(b());

      expect(documents()['folders/${shelf.id}']!.data!['name'], 'Rack');
      expect(shared(), {
        'folders/${shelf.id}': pairId,
        'folders/${box.id}': pairId,
        'notes/${top.id}': pairId,
        'notes/${low.id}': pairId,
      });
    });

    test('a note written or moved into it is shared from that push, and '
        'one moved out stops being', () async {
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      final written = await writeNote(
        a(),
        folderId: box.id,
        title: 'New',
        body: 'Four',
      );
      await a().db.noteDao.moveNote(id: apart.id, targetFolderId: shelf.id);
      await a().db.noteDao.moveNote(id: low.id, targetFolderId: beside.id);
      await a().sync();

      expect(shared()['notes/${written.id}'], pairId);
      expect(shared()['notes/${apart.id}'], pairId);
      expect(shared().containsKey('notes/${low.id}'), isFalse);
    });

    test('a folder moved into it brings its whole subtree, and takes it '
        'along when it leaves', () async {
      final inBeside = await a().db.folderDao.createFolder(
        name: 'Inner',
        parentId: beside.id,
      );
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      await a().db.folderDao.moveFolder(
        id: beside.id,
        targetParentId: shelf.id,
      );
      await a().sync();
      expect(shared()['folders/${beside.id}'], pairId);
      expect(shared()['folders/${inBeside.id}'], pairId);
      expect(shared()['notes/${apart.id}'], pairId);

      await a().db.folderDao.moveFolder(id: beside.id, targetParentId: null);
      await a().sync();
      expect(shared().containsKey('folders/${beside.id}'), isFalse);
      expect(shared().containsKey('folders/${inBeside.id}'), isFalse);
      expect(shared().containsKey('notes/${apart.id}'), isFalse);
    });

    test('deleted with what is under it, the tombstones still name the '
        'pair', () async {
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      await a().db.folderDao.softDeleteFolderWithDescendants(shelf.id);
      await a().sync();

      for (final key in [
        'folders/${shelf.id}',
        'folders/${box.id}',
        'notes/${top.id}',
        'notes/${low.id}',
      ]) {
        expect(documents()[key]!.op, OutboxOp.tombstone, reason: key);
        expect(shared()[key], pairId, reason: key);
      }
      // No live folder is shared any more: nobody else fetches text here.
      expect(pair.gateway.sharedPairOf(pair.space), isNull);
    });

    test(
      'reaches the account\'s other device with its mark; a note that '
      'device then writes under it is shared, and the two converge',
      () async {
        await a().db.folderDao.setSharedPair(shelf.id, pairId);
        await a().sync();
        await b().sync();

        final merged = (await b().db.folderDao.getByIdsIncludingDeleted([
          shelf.id,
        ])).single;
        expect(merged.sharedPair, pairId);

        final written = await writeNote(
          b(),
          folderId: box.id,
          title: 'From B',
          body: 'Five',
        );
        await b().sync();
        expect(shared()['notes/${written.id}'], pairId);
        expect(pair.gateway.sharedPairOf(pair.space), pairId);

        await a().sync();
        await b().sync();
        expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));
      },
    );

    test('a folder under it that the other device pushed before it had the '
        'mark is said again once it merges it — and unsaid once it merges '
        'the end of the share', () async {
      const folders = FoldersBinding();
      await b().sync();
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();
      // B still holds the shelf unmarked: its rename of the box went out
      // private, over the shared document A wrote.
      await b().db.folderDao.updateFolder(id: box.id, name: 'Crate');
      await pushedAs(b(), folders, box.id, sharedPair: null);
      expect(shared().containsKey('folders/${box.id}'), isFalse);

      await b().sync();

      expect(shared()['folders/${box.id}'], pairId);
      expect(documents()['folders/${box.id}']!.data!['name'], 'Crate');

      await a().sync();
      await a().db.folderDao.setSharedPair(shelf.id, null);
      await a().sync();
      // And the other way: B, still holding the mark, sends it shared.
      await b().db.folderDao.updateFolder(id: box.id, name: 'Chest');
      await pushedAs(b(), folders, box.id, sharedPair: pairId);
      expect(shared()['folders/${box.id}'], pairId);

      await b().sync();

      expect(shared(), isEmpty);
      expect(documents()['folders/${box.id}']!.data!['name'], 'Chest');
    });

    test('goes out mark first: the folder\'s own write is in the space '
        'before any row under it is sent again, so the account\'s other '
        'device never sees a row shared under a folder it holds '
        'private', () async {
      pair.gateway.maxBatch = 2;
      final before = pair.gateway.pushes.length;

      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      final sent = pair.gateway.pushes.skip(before).toList();
      expect(sent.length, greaterThan(1));
      expect([
        for (final envelope in sent.first) envelope.rowKey,
      ], contains(shelf.id));
      expect(shared(), hasLength(4));
    });

    test('files no copy of a note another device edited since this one '
        'last pulled: the rows a mark queues again are no unpushed '
        'edits', () async {
      await b().sync();
      await editNote(b(), top.id, 'One, edited on B');
      await b().sync();

      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      expect(a().hooks.conflicts, isEmpty);
      expect(await a().db.contentChunkDao.loadContent(top.id), contains('B'));
      expect(shared()['notes/${top.id}'], pairId);
    });

    test('files no copy on the other device either, whose merge of the mark '
        'queues the notes under it again just before their newer versions '
        'arrive', () async {
      await b().sync();
      // B wrote the note it holds, so nothing says its version came from
      // elsewhere: only the entry's kind tells a re-send from an edit.
      await editNote(b(), top.id, 'One, edited on B');
      await b().sync();
      await a().sync();
      await editNote(a(), top.id, 'One, edited on B and then on A');
      await a().db.folderDao.setSharedPair(shelf.id, pairId);
      await a().sync();

      await b().sync();

      expect(b().hooks.conflicts, isEmpty);
      expect(
        await b().db.contentChunkDao.loadContent(top.id),
        'One, edited on B and then on A',
      );
      await a().sync();
      expect(await SyncPair.snapshot(b()), await SyncPair.snapshot(a()));
    });

    test(
      'taken away while a push of the rows under it is in flight, they '
      'are sent again private in the same run: the entries that push '
      'would have retired are the very ones the change had to queue',
      () async {
        await a().db.folderDao.setSharedPair(shelf.id, pairId);
        var pushes = 0;
        pair.gateway.onPushBatch = (batch) async {
          // The second push carries the rows under the shelf, shared.
          if (++pushes == 2) {
            expect(
              batch.map((envelope) => envelope.sharedPair),
              contains(pairId),
            );
            await a().db.folderDao.setSharedPair(shelf.id, null);
          }
        };

        await a().sync();

        pair.gateway.onPushBatch = null;
        expect(pushes, greaterThan(2));
        expect(shared(), isEmpty);
        expect(pair.gateway.sharedPairOf(pair.space), isNull);
      },
    );

    group('the pair the space names for its notes\' text', () {
      setUp(() async {
        await a().db.folderDao.setSharedPair(shelf.id, pairId);
        await a().sync();
        await b().sync();
        await a().engine.start();
        await a().settle();
      });

      test('is taken out again by a device that knows the share ended, '
          'after one that did not put it back with a push of something '
          'else', () async {
        await a().db.folderDao.setSharedPair(shelf.id, null);
        await a().sync();
        expect(pair.gateway.sharedPairOf(pair.space), isNull);
        // B has not pulled the end of the share when it pushes something
        // else: its push writes the pair it still believes in.
        await pair.gateway.writeSpaceShare(
          pair.space,
          sharedPair: pairId,
          pushedBy: 'B',
          schema: syncSchema,
        );
        expect(pair.gateway.sharedPairOf(pair.space), pairId);

        await a().settle();

        expect(pair.gateway.sharedPairOf(pair.space), isNull);
        expect(pair.gateway.calls, contains('share:A'));
      });

      test('is not put back by a device that shares over another\'s word '
          'that nothing is: two devices that disagree never write the '
          'space at each other, and the next push of rows says it', () async {
        // Another device, which does not hold the share, pushed last.
        await pair.gateway.writeSpaceShare(
          pair.space,
          sharedPair: null,
          pushedBy: 'C',
          schema: syncSchema,
        );
        await a().settle();
        expect(pair.gateway.sharedPairOf(pair.space), isNull);
        expect(pair.gateway.calls, isNot(contains('share:A')));

        await writeNote(a(), folderId: shelf.id, title: 'Next', body: 'Six');
        await a().sync();
        expect(pair.gateway.sharedPairOf(pair.space), pairId);
      });

      test('is put back by the device whose own push took it out before it '
          'had merged the share', () async {
        // B pushed from before it knew of the share; then it pulls.
        await pair.gateway.writeSpaceShare(
          pair.space,
          sharedPair: null,
          pushedBy: 'B',
          schema: syncSchema,
        );
        await b().engine.start();
        await b().settle();

        expect(pair.gateway.sharedPairOf(pair.space), pairId);
        expect(pair.gateway.calls, contains('share:B'));
      });

      test('under the manual cadence, by the run\'s own read of the '
          'space', () async {
        await a().engine.setCadence(SyncCadence.manual);
        await pair.gateway.writeSpaceShare(
          pair.space,
          sharedPair: 'another-pair',
          pushedBy: 'C',
          schema: syncSchema,
        );
        await a().db.folderDao.setSharedPair(shelf.id, null);
        // Everything but the space's own field is in step once this lands.
        await a().sync();
        await pair.gateway.writeSpaceShare(
          pair.space,
          sharedPair: pairId,
          pushedBy: 'C',
          schema: syncSchema,
        );

        await a().sync();

        expect(pair.gateway.sharedPairOf(pair.space), isNull);
      });
    });
  });

  // A category is a third root (docs/cloud-share-surfaces-roadmap.md §7):
  // its own document carries its mark, and every event in it without a
  // mark of its own is shared as it is, day rows included.
  group('a shared category', () {
    const categories = CalendarCategoriesBinding();

    Future<void> category(SyncDevice device, String id) =>
        device.db.calendarCategoryDao.insertCategory(
          CalendarCategoriesCompanion.insert(
            id: id,
            name: 'Category $id',
            colorValue: 0xFF336699,
            iconKey: 'event',
            createdAt: day,
            updatedAt: day,
          ),
        );

    Future<void> eventIn(SyncDevice device, String id, String category) =>
        device.db.calendarEventDao.upsert(
          CalendarEventsCompanion.insert(
            id: id,
            title: 'Event $id',
            category: category,
            startDate: day,
            ruleKind: 'weekly',
            createdAt: day,
            updatedAt: day,
          ),
        );

    setUp(() async {
      await category(a(), 'climb');
      await category(a(), 'run');
      await eventIn(a(), 'e1', 'climb');
      await eventIn(a(), 'e2', 'run');
      await a().db.eventSkipDao.markSkipped('e1', day);
      await a().db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.missed);
      await a().db.eventTemplateDao.upsertTemplate(
        EventTemplatesCompanion.insert(
          id: 't1',
          name: 'Bouldering',
          category: 'climb',
          createdAt: day,
          updatedAt: day,
          hlcTimestamp: '000000000001:0000:A',
          deviceId: 'A',
        ),
      );
      await a().sync();
    });

    test('names the pair on its own document, with the mark in its data, '
        'and on every event in it and their day rows — never on another '
        'category\'s event, a presence mark or a template', () async {
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();

      expect(shared(), {
        'calendar_categories/climb': pairId,
        'calendar_events/e1': pairId,
        dayKey('calendar_event_skips', 'e1'): pairId,
      });
      expect(
        documents()['calendar_categories/climb']!.data!['sharedPair'],
        pairId,
      );
      expect(
        documents()['calendar_events/e1']!.data!.containsKey('sharedPair'),
        isFalse,
        reason: 'the event carries no mark of its own: its document says it',
      );
    });

    test('made private again, every one of those documents stops naming '
        'the pair with its next push', () async {
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();

      await a().db.calendarCategoryDao.setSharedPair('climb', null);
      await a().sync();

      expect(shared(), isEmpty);
    });

    test('pushed shared by another device, where this one holds it private, '
        'is said private again: a share must not outlive its end', () async {
      await b().sync();
      final row = (await categories.loadByKeys(b().db, ['climb'])).single;
      pair.gateway.plant(
        pair.space,
        (await categories.encode(
          b().db,
          row,
          boundUid: syncUid,
        )).sharedInto(pairId),
        pushedBy: 'C',
      );
      expect(shared()['calendar_categories/climb'], pairId);

      await b().sync();

      expect(shared(), isEmpty);
    });

    test('taken away while its push is in flight, it and its events are '
        'sent again private in the same run', () async {
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      var cleared = false;
      pair.gateway.onPushBatch = (batch) async {
        if (!cleared &&
            batch.any(
              (envelope) =>
                  envelope.table == 'calendar_categories' &&
                  envelope.sharedPair == pairId,
            )) {
          cleared = true;
          await a().db.calendarCategoryDao.setSharedPair('climb', null);
        }
      };

      await a().sync();

      pair.gateway.onPushBatch = null;
      expect(cleared, isTrue);
      expect(shared(), isEmpty);
    });

    Future<String?> markOn(SyncDevice device) async =>
        (await device.db.calendarCategoryDao.getByIdsIncludingDeleted([
          'climb',
        ])).single.sharedPair;

    Future<void> editOn(SyncDevice device, String id, String category) =>
        device.db.calendarEventDao.upsert(
          CalendarEventsCompanion.insert(
            id: id,
            title: 'Edited on ${device.id}',
            category: category,
            startDate: day,
            ruleKind: 'weekly',
            createdAt: day,
            updatedAt: day,
          ),
        );

    test('an event added on a device that had not heard the share end, '
        'pushed shared with its day row, is said private by the device '
        'that ended it, and stays so', () async {
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();
      await b().sync();
      expect(await markOn(b()), pairId);
      await eventIn(b(), 'e3', 'climb');
      await b().db.eventSkipDao.markSkipped('e3', day);
      await a().db.calendarCategoryDao.setSharedPair('climb', null);
      await a().sync();
      expect(shared(), isEmpty);

      await pushedAs(
        b(),
        const CalendarEventsBinding(),
        'e3',
        sharedPair: pairId,
      );
      await pushedAs(
        b(),
        const CalendarEventSkipsBinding(),
        dayRowKey('e3', day),
        sharedPair: pairId,
      );
      expect(shared().keys, {
        'calendar_events/e3',
        dayKey('calendar_event_skips', 'e3'),
      });

      expect((await a().sync()).pushedRows, 2);
      expect(shared(), isEmpty);
      expect((await b().sync()).pushedRows, 0);
      expect(await markOn(b()), isNull);
      expect((await a().sync()).pushedRows, 0);
      expect((await b().sync()).pushedRows, 0);
      expect(shared(), isEmpty);
    });

    test('an event edited on a device that had not heard the share end is '
        'pushed private once that device merges the end', () async {
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', null);
      await a().sync();
      await editOn(b(), 'e1', 'climb');

      expect((await b().sync()).pushedRows, 1);

      expect(shared(), isEmpty);
      expect(await markOn(b()), isNull);
      expect((await a().sync()).pushedRows, 0);
      expect((await b().sync()).pushedRows, 0);
    });

    test('an event pushed private by a device that had not heard the share '
        'begin, after the mark was set, is said shared by that device once '
        'it merges the mark — not by the one that set it, which cannot tell '
        'the push came after', () async {
      await b().sync();
      await editOn(b(), 'e1', 'climb');
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b().sync();
      expect(shared(), isEmpty);

      expect((await a().sync()).pushedRows, 2);
      expect(shared(), {
        'calendar_categories/climb': pairId,
        dayKey('calendar_event_skips', 'e1'): pairId,
      });

      expect((await b().sync()).pushedRows, 1);
      final settled = {
        'calendar_categories/climb': pairId,
        'calendar_events/e1': pairId,
        dayKey('calendar_event_skips', 'e1'): pairId,
      };
      expect(shared(), settled);
      expect((await a().sync()).pushedRows, 0);
      expect((await b().sync()).pushedRows, 0);
      expect(shared(), settled);
    });

    test('an event pushed private before the mark was set is said shared '
        'by the device that set it, in the same run', () async {
      await b().sync();
      await editOn(b(), 'e1', 'climb');
      await b().sync();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);

      expect((await a().sync()).pushedRows, 3);

      final settled = {
        'calendar_categories/climb': pairId,
        'calendar_events/e1': pairId,
        dayKey('calendar_event_skips', 'e1'): pairId,
      };
      expect(shared(), settled);
      expect((await b().sync()).pushedRows, 0);
      expect((await a().sync()).pushedRows, 0);
      expect(shared(), settled);
    });

    test('set on one device and cleared on the other, every document says '
        'it once each way and then rests', () async {
      for (var i = 0; i < 5; i++) {
        await eventIn(a(), 'x$i', 'climb');
      }
      await a().sync();
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);

      // The category, its six events and the one skipped day.
      expect((await a().sync()).pushedRows, 8);
      expect((await b().sync()).pushedRows, 0);
      expect(shared(), hasLength(8));
      expect((await a().sync()).pushedRows, 0);
      expect((await b().sync()).pushedRows, 0);

      await b().db.calendarCategoryDao.setSharedPair('climb', null);
      expect((await b().sync()).pushedRows, 8);
      expect(shared(), isEmpty);
      expect((await a().sync()).pushedRows, 0);
      expect((await b().sync()).pushedRows, 0);
      expect((await a().sync()).pushedRows, 0);
      expect(shared(), isEmpty);
    });

    test('a day row the other device pushed shared after this one moved its '
        'event out of the category is said private by that device\'s next '
        'run', () async {
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();
      await b().sync();
      final later = DateTime.utc(2026, 6, 8);
      await b().db.eventSkipDao.markSkipped('e1', later);
      await eventIn(a(), 'e1', 'run');
      await a().sync();
      expect(shared(), {'calendar_categories/climb': pairId});

      await pushedAs(
        b(),
        const CalendarEventSkipsBinding(),
        dayRowKey('e1', later),
        sharedPair: pairId,
      );
      expect(
        shared()['calendar_event_skips/${dayRowKey('e1', later)}'],
        pairId,
      );

      expect((await b().sync()).pushedRows, 1);
      expect(shared(), {'calendar_categories/climb': pairId});
      expect((await a().sync()).pushedRows, 0);
      expect(shared(), {'calendar_categories/climb': pairId});
    });

    test('an event of it made and deleted before another device ever held '
        'it: that device stores the tombstone and leaves its document '
        'shared — it cannot know the grant, and the partner has to hear of '
        'the delete', () async {
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();
      await b().sync();
      await eventIn(a(), 'e9', 'climb');
      await a().db.calendarEventDao.softDeleteById('e9');
      await a().sync();
      expect(shared()['calendar_events/e9'], pairId);

      final report = await b().sync();

      expect(
        (await b().db.calendarEventDao.getByIdsIncludingDeleted([
          'e9',
        ])).single.isDeleted,
        isTrue,
      );
      expect(report.pushedRows, 0);
      expect(shared()['calendar_events/e9'], pairId);
    });

    test('a tombstone named shared over an event this device held in a '
        'private category is still said private again', () async {
      await b().sync();
      await a().db.calendarEventDao.softDeleteById('e2');
      final row = (await const CalendarEventsBinding().loadByKeys(a().db, [
        'e2',
      ])).single;
      pair.gateway.plant(
        pair.space,
        (await const CalendarEventsBinding().encode(
          a().db,
          row,
          boundUid: syncUid,
        )).sharedInto(pairId),
        pushedBy: 'C',
      );

      await b().sync();

      expect(
        (await b().db.calendarEventDao.getByIdsIncludingDeleted([
          'e2',
        ])).single.isDeleted,
        isTrue,
      );
      expect(shared()['calendar_events/e2'], isNull);
    });

    test('deleted, and brought back by a rename from a device that never '
        'read the mark, comes back private, and so does an event added to '
        'it there: a delete ends the grant for good', () async {
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();
      await a().db.calendarCategoryDao.tombstoneCascade(
        'climb',
        reassignTo: 'run',
      );
      await a().sync();
      expect(shared(), {'calendar_categories/climb': pairId});

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b().db.calendarCategoryDao.updateCategory(
        CalendarCategoriesCompanion(
          id: const Value('climb'),
          name: const Value('Bouldering'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await eventIn(b(), 'e3', 'climb');
      await b().sync();
      await a().sync();
      await b().sync();
      await a().sync();

      Future<CalendarCategoryRow> climbOn(SyncDevice device) async =>
          (await device.db.calendarCategoryDao.getByIdsIncludingDeleted([
            'climb',
          ])).single;
      for (final device in [a(), b()]) {
        final row = await climbOn(device);
        expect(row.isDeleted, isFalse);
        expect(row.sharedPair, isNull);
      }
      expect(shared(), isEmpty);
      expect(documents().keys, contains('calendar_events/e3'));
      expect((await b().sync()).pushedRows, 0);
      expect((await a().sync()).pushedRows, 0);
    });

    test('renamed on a device that last ran below the wire that carries a '
        'category\'s mark waits there for the categories\' re-read: a run '
        'that only drains does not send it private over the mark', () async {
      await b().sync();
      await a().db.calendarCategoryDao.setSharedPair('climb', pairId);
      await a().sync();
      await b().db.syncDao.setValue(
        SyncDao.keyWireVersion,
        '${DatabaseSchema.categoryShareWireVersion - 1}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b().db.calendarCategoryDao.updateCategory(
        CalendarCategoriesCompanion(
          id: const Value('climb'),
          name: const Value('Bouldering'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await b().db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'e1',
          title: 'Edited on B',
          category: 'climb',
          startDate: day,
          ruleKind: 'weekly',
          createdAt: day,
          updatedAt: day,
        ),
      );

      await startInBackground(b());

      final held = documents()['calendar_categories/climb']!;
      expect(held.sharedPair, pairId);
      expect(held.data!['sharedPair'], pairId);
      expect(held.data!['name'], 'Category climb');

      await resume(b());

      expect(
        (await b().db.calendarCategoryDao.getByIdsIncludingDeleted([
          'climb',
        ])).single.sharedPair,
        pairId,
      );
      expect(
        documents()['calendar_categories/climb']!.data!['name'],
        'Bouldering',
      );
      expect(
        documents()['calendar_events/e1']!.data!['title'],
        'Edited on B',
        reason:
            'the event its drain sent private is sent again once the '
            'mark is merged',
      );
      expect(shared(), {
        'calendar_categories/climb': pairId,
        'calendar_events/e1': pairId,
        dayKey('calendar_event_skips', 'e1'): pairId,
      });
    });
  });

  test('only the six tables that can be shared ever name a pair', () async {
    final shelf = await a().db.folderDao.createFolder(name: 'Shelf');
    await writeNote(a(), folderId: shelf.id, title: 'Top', body: 'One');
    await event(a(), 'e1');
    await a().db.eventSkipDao.markSkipped('e1', day);
    await a().db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.present);
    await a().db.folderDao.setSharedPair(shelf.id, pairId);
    await a().db.calendarEventDao.setSharedPair('e1', pairId);
    await a().db.calendarCategoryDao.insertCategory(
      CalendarCategoriesCompanion.insert(
        id: 'climb',
        name: 'Climb',
        colorValue: 0xFF336699,
        iconKey: 'event',
        createdAt: day,
        updatedAt: day,
      ),
    );
    await a().db.calendarCategoryDao.setSharedPair('climb', pairId);

    final report = await a().sync();

    expect(report.failure, isNull);
    expect({
      for (final key in shared().keys) key.split('/').first,
    }, everyElement(isIn(sharedTables)));
    expect(a().engine.current.heldBack, isEmpty);
  });
}
