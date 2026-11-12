import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/calendar_event_occurrences_binding.dart';
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

  setUp(() async => pair = await SyncPair.open());
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

      test('pushed by another device after everything this one knows of '
          'the event is left to that device: one that is behind never '
          'unsays what another wrote', () async {
        await b().sync();
        // The server's clock, past every stamp B holds: the document was
        // written by a device that may know of a mark B has yet to pull.
        pair.gateway.elapse(const Duration(days: 730));
        final row = (await texts.loadByKeys(b().db, [textKey])).single;
        pair.gateway.plant(
          pair.space,
          (await texts.encode(
            b().db,
            row,
            boundUid: syncUid,
          )).sharedInto(pairId),
          pushedBy: 'A',
        );
        final before = pair.gateway.pushes.length;

        await b().sync();

        expect(pair.gateway.pushes, hasLength(before));
        expect(shared()[text], pairId);
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
  });

  test('only the five tables that can be shared ever name a pair', () async {
    final shelf = await a().db.folderDao.createFolder(name: 'Shelf');
    await writeNote(a(), folderId: shelf.id, title: 'Top', body: 'One');
    await event(a(), 'e1');
    await a().db.eventSkipDao.markSkipped('e1', day);
    await a().db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.present);
    await a().db.folderDao.setSharedPair(shelf.id, pairId);
    await a().db.calendarEventDao.setSharedPair('e1', pairId);

    final report = await a().sync();

    expect(report.failure, isNull);
    expect({
      for (final key in shared().keys) key.split('/').first,
    }, everyElement(isIn(sharedTables)));
    expect(a().engine.current.heldBack, isEmpty);
  });
}
