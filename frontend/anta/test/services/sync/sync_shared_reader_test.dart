import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/tables/calendar_events_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import 'support/sync_pair.dart';

/// The reader's side of sharing (`docs/cloud-sharing-foundations.md` §5,
/// §6): two accounts, paired, each with a device bound to a space of its
/// own. What the owner shares arrives on the partner's device under the
/// owner's account, follows every change, and is removed when it stops
/// being shared; nothing of it is ever queued there.
void main() {
  late SharePair pair;

  setUp(() async => pair = await SharePair.open());
  tearDown(() async => pair.close());

  SyncDevice owner() => pair.owner;
  SyncDevice partner() => pair.partner;

  final day = DateTime.utc(2026, 6, 1);

  Future<void> event(SyncDevice device, String id, {String? title}) =>
      device.db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: id,
          title: title ?? 'Event $id',
          category: 'general',
          startDate: day,
          ruleKind: 'weekly',
          createdAt: day,
          updatedAt: day,
        ),
      );

  Future<CalendarEventRow?> eventOn(SyncDevice device, String id) async =>
      (await device.db.calendarEventDao.getByIdsIncludingDeleted([
        id,
      ])).firstOrNull;

  Future<Folder?> folderOn(SyncDevice device, String id) async =>
      (await device.db.folderDao.getByIdsIncludingDeleted([id])).firstOrNull;

  Future<Note?> noteOn(SyncDevice device, String id) async =>
      (await device.db.noteDao.getByIdsIncludingDeleted([id])).firstOrNull;

  /// The keys of [table]'s rows [device] holds that [uid] owns.
  Future<Set<String>> ownedBy(
    SyncDevice device,
    String table,
    String uid, {
    String key = 'id',
  }) async => {
    for (final row in await device.db
        .customSelect(
          'SELECT $key AS k FROM $table WHERE owner_id = ?',
          variables: [Variable<String>(uid)],
        )
        .get())
      row.read<String>('k'),
  };

  Future<int> queuedOn(SyncDevice device) => device.db.syncOutboxDao.count();

  /// The calls the shared read made, of everything the gateway logged.
  List<String> sharedCalls() => [
    for (final call in pair.gateway.calls)
      if (call.startsWith('shared:') ||
          call.startsWith('count:') ||
          call == 'chunks')
        call,
  ];

  test('an account that never paired, shares nothing and holds no shared '
      'row asks nothing: no call for the pair, none to the space', () async {
    pair.partners.local.clear();
    pair.partners.pairs.clear();
    await event(partner(), 'own');

    await partner().sync();
    await partner().sync();

    expect(pair.partners.asked, isEmpty);
    expect(sharedCalls(), isEmpty);
  });

  group('a shared event', () {
    setUp(() async {
      await event(owner(), 'e1');
      await event(owner(), 'private');
      await owner().db.eventSkipDao.markSkipped('e1', day);
      await owner().db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: day,
          description: 'Bring the keys',
          createdAt: day,
          updatedAt: day,
        ),
      );
      await owner().db.eventAbsenceDao.setStatus(
        'e1',
        day,
        PresenceStatus.missed,
      );
      await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
    });

    test('arrives on the partner\'s device under the owner\'s account, with '
        'its skipped day and its day\'s text — never the owner\'s presence '
        'mark, another event of theirs, nor the mark itself', () async {
      await pair.syncBoth();

      final shared = (await eventOn(partner(), 'e1'))!;
      expect(shared.title, 'Event e1');
      expect(shared.ownerId, ownerUid);
      expect(shared.sharedPair, isNull, reason: 'here a mark means "I share"');
      expect(shared.sharedStamp, isNull);
      expect(await eventOn(partner(), 'private'), isNull);
      expect(
        await ownedBy(
          partner(),
          'calendar_event_skips',
          ownerUid,
          key: 'event_id',
        ),
        {'e1'},
      );
      expect(
        await ownedBy(
          partner(),
          'calendar_event_occurrences',
          ownerUid,
          key: 'event_id',
        ),
        {'e1'},
      );
      expect(
        await partner().db
            .customSelect('SELECT 1 FROM calendar_event_absences')
            .get(),
        isEmpty,
      );
      expect(await pair.partner.db.sharedRowDao.owner(), ownerUid);
    });

    test('is never queued on the partner\'s device, and nothing of it '
        'reaches the partner\'s own space', () async {
      await pair.syncBoth();
      await partner().sync();

      expect(await queuedOn(partner()), 0);
      expect(pair.gateway.rowsOf(pair.partnerSpace, 'calendar_events'), isEmpty);
      expect(
        pair.gateway.rowsOf(pair.partnerSpace, 'calendar_event_skips'),
        isEmpty,
      );
    });

    test('follows the owner\'s changes, and the owner\'s copy wins over a '
        'copy changed here whatever its stamp says', () async {
      await pair.syncBoth();
      // A write that slipped past every fence, stamped above the owner's.
      await partner().db.customStatement(
        "UPDATE calendar_events SET title = 'Changed here', "
        "hlc_timestamp = 'ffffffffffff:0000:B' WHERE id = 'e1'",
      );

      await event(owner(), 'e1', title: 'Renamed by its owner');
      await pair.syncBoth();

      final shared = (await eventOn(partner(), 'e1'))!;
      expect(shared.title, 'Renamed by its owner');
      expect(shared.ownerId, ownerUid);
      expect(await queuedOn(partner()), 0);
    });

    test('tells the screens: the page of each shared table, then the '
        'calendar once for the run', () async {
      await owner().sync();
      partner().hooks.clear();

      await partner().sync();

      expect(
        partner().hooks.calls,
        containsAllInOrder([
          'before:calendar_events',
          'after:calendar_events',
          'before:calendar_event_occurrences',
          'before:calendar_event_skips',
          'run',
        ]),
      );
      expect(partner().hooks.runs.last, contains(SyncInvalidation.calendar));
    });

    test('made private again, leaves the partner\'s device with its day '
        'rows — while what the partner added of their own stays', () async {
      await pair.syncBoth();
      await partner().db.eventAbsenceDao.setStatus(
        'e1',
        day,
        PresenceStatus.present,
      );
      await partner().sync();

      await owner().db.calendarEventDao.setSharedPair('e1', null);
      await pair.syncBoth();

      expect(await eventOn(partner(), 'e1'), isNull, reason: 'no tombstone');
      expect(await ownedBy(partner(), 'calendar_events', ownerUid), isEmpty);
      expect(
        await ownedBy(
          partner(),
          'calendar_event_skips',
          ownerUid,
          key: 'event_id',
        ),
        isEmpty,
      );
      expect(
        await partner().db
            .customSelect(
              "SELECT 1 FROM calendar_event_absences WHERE event_id = 'e1'",
            )
            .get(),
        hasLength(1),
        reason: 'the partner\'s own presence mark is theirs',
      );
      expect(await queuedOn(partner()), 0);
    });

    test('deleted by its owner, arrives as a deletion', () async {
      await pair.syncBoth();

      await owner().db.calendarEventDao.tombstoneEventCascade('e1');
      await pair.syncBoth();

      final shared = (await eventOn(partner(), 'e1'))!;
      expect(shared.isDeleted, isTrue);
      expect(shared.ownerId, ownerUid);
    });

    test('does not take the place of an event of the partner\'s own under '
        'the same id — two accounts that restored one backup hold the same '
        'ids — and that event is never removed for it', () async {
      await event(partner(), 'e1', title: 'The partner\'s own');
      await partner().sync();

      await pair.syncBoth();

      final own = (await eventOn(partner(), 'e1'))!;
      expect(own.title, 'The partner\'s own');
      expect(own.ownerId, isNot(ownerUid));
      expect(
        await ownedBy(
          partner(),
          'calendar_event_skips',
          ownerUid,
          key: 'event_id',
        ),
        isEmpty,
        reason: 'nor do the owner\'s day rows hang under it',
      );

      await owner().db.calendarEventDao.setSharedPair('e1', null);
      await pair.syncBoth();
      expect((await eventOn(partner(), 'e1'))!.title, 'The partner\'s own');
    });

    test('written by a newer build is passed over and remembered; a build '
        'that reads that wire then reads the table again from the start '
        'and takes it', () async {
      await owner().sync();
      const events = CalendarEventsBinding();
      final row = (await eventOn(owner(), 'e1'))!;
      final envelope = await events.encode(
        owner().db,
        row,
        boundUid: ownerUid,
      );
      // The same row, as a build one wire ahead pushed it.
      pair.gateway.plant(
        pair.ownerSpace,
        SyncEnvelope(
          table: envelope.table,
          rowKey: envelope.rowKey,
          hlc: envelope.hlc,
          deviceId: envelope.deviceId,
          version: envelope.version,
          op: envelope.op,
          ownerId: envelope.ownerId,
          data: envelope.data,
          sharedPair: sharePairId,
          wire: syncSchema + 1,
        ),
        pushedBy: 'A',
      );

      await partner().sync();

      expect(await eventOn(partner(), 'e1'), isNull);
      expect(
        await partner().db.syncDao.getValue(SyncDao.keySharedNewerWire),
        '${syncSchema + 1}',
      );

      // The update: this database under a build that reads that wire.
      final updated = SyncEngine.detached(
        db: partner().db,
        gateway: pair.gateway,
        binding: partner().binding,
        status: partner().status,
        hooks: partner().hooks,
        deviceId: partner().id,
        schema: syncSchema + 1,
        currentUser: () => partner().user,
        partners: pair.partners,
      );
      addTearDown(updated.dispose);
      await updated.syncNow();
      await updated.whenIdle;

      expect((await eventOn(partner(), 'e1'))!.ownerId, ownerUid);
      expect(
        await partner().db.syncDao.getValue(SyncDao.keySharedNewerWire),
        isNull,
      );
    });
  });

  group('a shared folder', () {
    late Folder cabinet;
    late Folder shelf;
    late Folder box;
    late Note top;
    late Note low;
    late Note apart;

    setUp(() async {
      final db = owner().db;
      cabinet = await db.folderDao.createFolder(name: 'Cabinet');
      shelf = await db.folderDao.createFolder(
        name: 'Shelf',
        parentId: cabinet.id,
      );
      box = await db.folderDao.createFolder(name: 'Box', parentId: shelf.id);
      top = await writeNote(
        owner(),
        folderId: shelf.id,
        title: 'Top',
        body: 'Text on the shelf',
      );
      low = await writeNote(
        owner(),
        folderId: box.id,
        title: 'Low',
        body: 'Text in the box',
      );
      apart = await writeNote(
        owner(),
        folderId: cabinet.id,
        title: 'Apart',
        body: 'Never shared',
      );
      await db.folderDao.setSharedPair(shelf.id, sharePairId);
    });

    Future<String> textOn(SyncDevice device, String noteId) =>
        device.db.contentChunkDao.loadContent(noteId);

    test('arrives with everything under it and the notes\' text, read from '
        'the owner\'s space — and stands at the top level, its own parent '
        'not being shared', () async {
      await pair.syncBoth();

      final root = (await folderOn(partner(), shelf.id))!;
      expect(root.ownerId, ownerUid);
      expect(root.parentId, isNull, reason: 'the cabinet is not shared');
      expect(root.sharedPair, isNull);
      expect((await folderOn(partner(), box.id))!.parentId, shelf.id);
      expect(await folderOn(partner(), cabinet.id), isNull);
      expect((await noteOn(partner(), top.id))!.folderId, shelf.id);
      expect(await textOn(partner(), top.id), 'Text on the shelf');
      expect(await textOn(partner(), low.id), 'Text in the box');
      expect(await noteOn(partner(), apart.id), isNull);
      expect(sharedCalls(), contains('chunks'));
      expect(await queuedOn(partner()), 0);
      expect(
        pair.gateway.rowsOf(pair.partnerSpace, 'content_chunks'),
        isEmpty,
        reason: 'the owner\'s text is never pushed into the partner\'s space',
      );
      expect(pair.gateway.sharedPairOf(pair.partnerSpace), isNull);
    });

    test('stays at the top level through the owner\'s later changes of it, '
        'and nothing about it is ever stamped here', () async {
      await pair.syncBoth();

      await owner().db.folderDao.updateFolder(id: shelf.id, name: 'Renamed');
      await pair.syncBoth();

      final root = (await folderOn(partner(), shelf.id))!;
      final theirs = (await folderOn(owner(), shelf.id))!;
      expect(root.name, 'Renamed');
      expect(root.parentId, isNull);
      expect(root.hlcTimestamp, theirs.hlcTimestamp);
      expect(root.version, theirs.version);
    });

    test('goes back under its parent once the owner shares that too', () async {
      await pair.syncBoth();

      await owner().db.folderDao.setSharedPair(cabinet.id, sharePairId);
      await pair.syncBoth();

      expect((await folderOn(partner(), cabinet.id))!.parentId, isNull);
      expect((await folderOn(partner(), shelf.id))!.parentId, cabinet.id);
      expect(await noteOn(partner(), apart.id), isNotNull);
      expect(
        await partner().db.syncDao.valuesByPrefix(SyncDao.sharedRootPrefix),
        isEmpty,
      );
    });

    test('follows an edit of a note\'s text', () async {
      await pair.syncBoth();

      await editNote(owner(), top.id, 'Text on the shelf, edited');
      await pair.syncBoth();

      expect(await textOn(partner(), top.id), 'Text on the shelf, edited');
    });

    test('a note moved out of it leaves the partner\'s device with its '
        'text; one moved in arrives', () async {
      await pair.syncBoth();

      await owner().db.noteDao.moveNote(
        id: top.id,
        targetFolderId: cabinet.id,
      );
      await owner().db.noteDao.moveNote(id: apart.id, targetFolderId: box.id);
      await pair.syncBoth();

      expect(await noteOn(partner(), top.id), isNull);
      expect(
        await partner().db
            .customSelect(
              'SELECT 1 FROM content_chunks WHERE note_id = ?',
              variables: [Variable<String>(top.id)],
            )
            .get(),
        isEmpty,
      );
      expect(await textOn(partner(), apart.id), 'Never shared');
    });

    test('no longer shared, leaves with everything under it', () async {
      await pair.syncBoth();
      partner().hooks.clear();

      await owner().db.folderDao.setSharedPair(shelf.id, null);
      await pair.syncBoth();

      expect(await ownedBy(partner(), 'folders', ownerUid), isEmpty);
      expect(await ownedBy(partner(), 'notes', ownerUid), isEmpty);
      expect(
        await partner().db.customSelect('SELECT 1 FROM content_chunks').get(),
        isEmpty,
      );
      expect(
        partner().hooks.runs.last,
        containsAll([SyncInvalidation.folders, SyncInvalidation.notes]),
      );
      expect(await queuedOn(partner()), 0);
    });

    test('a note whose text cannot be read yet — the owner\'s space does '
        'not name the pair — waits, and is taken at the next read once it '
        'does', () async {
      await owner().sync();
      // A device of the owner that had not heard of the share pushed last.
      await pair.gateway.writeSpaceShare(
        pair.ownerSpace,
        sharedPair: null,
        pushedBy: 'C',
        schema: syncSchema,
      );

      await partner().sync();

      expect(await folderOn(partner(), shelf.id), isNotNull);
      expect(await noteOn(partner(), top.id), isNull);

      await pair.gateway.writeSpaceShare(
        pair.ownerSpace,
        sharedPair: sharePairId,
        pushedBy: 'A',
        schema: syncSchema,
      );
      await partner().sync();

      expect(await textOn(partner(), top.id), 'Text on the shelf');
      expect(
        await partner().db.syncDao.valuesByPrefix(SyncDao.sharedRetryPrefix),
        isEmpty,
      );
    });

    test('a shared note is never stored inside a folder of the partner\'s '
        'own, whatever the document says of where it lies', () async {
      final own = await partner().db.folderDao.createFolder(name: 'Mine');
      await owner().sync();
      const notes = NotesBinding();
      final envelope = await notes.encode(
        owner().db,
        (await noteOn(owner(), top.id))!,
        boundUid: ownerUid,
      );
      pair.gateway.plant(
        pair.ownerSpace,
        SyncEnvelope(
          table: envelope.table,
          rowKey: 'planted',
          hlc: envelope.hlc,
          deviceId: envelope.deviceId,
          version: envelope.version,
          op: envelope.op,
          ownerId: ownerUid,
          data: {...envelope.data!, 'id': 'planted', 'folderId': own.id},
          sharedPair: sharePairId,
          wire: syncSchema,
        ),
        pushedBy: 'A',
      );

      await partner().sync();

      expect(await noteOn(partner(), 'planted'), isNull);
      expect(await noteOn(partner(), top.id), isNotNull);
    });
  });

  group('the pair', () {
    setUp(() async {
      await event(owner(), 'e1');
      await event(partner(), 'own');
      await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
      await pair.syncBoth();
    });

    test('ended: the shared rows leave the partner\'s device, its own stay, '
        'and nothing more is asked of the space', () async {
      pair.end();
      pair.gateway.calls.clear();

      await partner().sync();

      expect(await eventOn(partner(), 'e1'), isNull);
      expect(await eventOn(partner(), 'own'), isNotNull);
      expect(await partner().db.sharedRowDao.owner(), isNull);
      expect(sharedCalls(), isEmpty);
    });

    test('ended: the owner\'s marks of it are cleared on the owner\'s own '
        'device, so its documents stop naming a pair that is over', () async {
      pair.end();

      await owner().sync();
      await owner().sync();

      expect((await eventOn(owner(), 'e1'))!.sharedPair, isNull);
      expect(
        pair.gateway.rowsOf(pair.ownerSpace, 'calendar_events')['e1']!.sharedPair,
        isNull,
      );
    });

    test('that cannot be asked about — no connection — removes nothing', () async {
      pair.partners.failure = const SyncGatewayException(
        SyncGatewayFailure.offline,
      );

      final report = await partner().sync();

      expect(report.failure, isNull, reason: 'the account\'s own sync ran');
      expect(await eventOn(partner(), 'e1'), isNotNull);
    });

    test('made again under another id starts with nothing shared: the rows '
        'of the first one leave, then what is shared into the new one '
        'arrives', () async {
      pair.end();
      pair.join(pairId: 'pair-2');

      await partner().sync();
      expect(await eventOn(partner(), 'e1'), isNull);

      await owner().sync();
      expect((await eventOn(owner(), 'e1'))!.sharedPair, isNull);
      await owner().db.calendarEventDao.setSharedPair('e1', 'pair-2');
      await pair.syncBoth();
      expect((await eventOn(partner(), 'e1'))!.ownerId, ownerUid);
      expect(
        await partner().db.syncDao.getValue(SyncDao.keySharedPair),
        'pair-2',
      );
    });

    test('a refusal by the space\'s rules — not deployed yet, or the pair '
        'just ended — fails nothing of the account\'s own sync and removes '
        'nothing', () async {
      pair.gateway.endPair(sharePairId);

      final report = await partner().sync();

      expect(report.failure, isNull);
      expect(report.skipped, isNull);
      expect(await eventOn(partner(), 'e1'), isNotNull);
      expect(partner().engine.current.pause.name, 'none');
    });
  });

  group('how often', () {
    setUp(() async {
      await event(owner(), 'e1');
      await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
      await pair.syncBoth();
    });

    test('a read with nothing new costs the pair, a page and a count per '
        'shareable table, and nothing for a note\'s text', () async {
      pair.gateway.calls.clear();
      pair.partners.asked.clear();

      await partner().sync();

      expect(pair.partners.asked, [partnerUid]);
      expect(sharedCalls(), [
        for (final table in const [
          'calendar_events',
          'calendar_event_occurrences',
          'calendar_event_skips',
          'folders',
          'notes',
        ]) ...['shared:$table', 'count:$table'],
      ]);
    });

    test('a run nobody asked for reads again only once the interval has '
        'passed; "Sync now" reads at once', () async {
      await partner().engine.start();
      await partner().settle();
      final asked = pair.partners.asked.length;
      var clock = DateTime.now();
      partner().now = () => clock;

      // The partner's own space moves: an unasked run.
      await event(partner(), 'own');
      await partner().settle();
      partner().scheduler.fire();
      await partner().settle();
      expect(pair.partners.asked, hasLength(asked));

      clock = clock.add(SyncEngine.sharedReadInterval);
      await event(partner(), 'own-2');
      await partner().settle();
      partner().scheduler.fire();
      await partner().settle();
      expect(pair.partners.asked, hasLength(asked + 1));

      await partner().sync();
      expect(pair.partners.asked, hasLength(asked + 2));
    });

    test('once a day every shared table is read from the start whatever '
        'the count says, which brings back a row this device lost', () async {
      // A second shared event, long after the first: the cursor stands past
      // the first one by more than a resumed read looks back.
      pair.gateway.elapse(const Duration(minutes: 1));
      await event(owner(), 'e2');
      await owner().db.calendarEventDao.setSharedPair('e2', sharePairId);
      await pair.syncBoth();
      await partner().db.customStatement(
        "DELETE FROM calendar_events WHERE id = 'e1'",
      );
      // Fewer here than on the server reads as "still arriving": the count
      // does not show it, and the cursor never comes back to it.
      await partner().sync();
      expect(await eventOn(partner(), 'e1'), isNull);

      final later = DateTime.now().add(SyncEngine.fullPullInterval);
      partner().now = () => later;
      await partner().sync();

      expect(await eventOn(partner(), 'e1'), isNotNull);
    });
  });

  group('a database that stops syncing', () {
    test('drops what was shared with it and keeps its own rows, which '
        'become nobody\'s again', () async {
      await event(owner(), 'e1');
      await event(partner(), 'own');
      await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
      await pair.syncBoth();

      await partner().binding.unbind();

      expect(await eventOn(partner(), 'e1'), isNull);
      final own = (await eventOn(partner(), 'own'))!;
      expect(own.ownerId, isNull);
      expect(await partner().db.sharedRowDao.owner(), isNull);
      expect(
        await partner().db.syncDao.valuesByPrefix(SyncDao.sharedCursorPrefix),
        isEmpty,
      );
    });
  });

  group('the push', () {
    test('never sends a row another account shared, whatever queued it: '
        'its entry is retired unsent and the run goes on', () async {
      await event(owner(), 'e1');
      await event(partner(), 'own');
      await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
      await pair.syncBoth();
      // A write that slipped past every fence: the shared row, queued.
      await partner().db.syncOutboxDao.requeueRow('calendar_events', 'e1');
      await event(partner(), 'own', title: 'Edited');

      final report = await partner().sync();

      expect(report.failure, isNull);
      expect(await queuedOn(partner()), 0);
      final sent = pair.gateway.rowsOf(pair.partnerSpace, 'calendar_events');
      expect(sent.keys, ['own']);
      expect(sent['own']!.data!['title'], 'Edited');
      expect((await eventOn(partner(), 'e1'))!.ownerId, ownerUid);
    });

    test('takes over a row of this device\'s own that an old binding left '
        'under another account, and sends it — where the run used to fail '
        'on it for as long as it stood queued', () async {
      pair.partners.local.clear();
      pair.partners.pairs.clear();
      await event(partner(), 'old');
      await partner().db.customStatement(
        "UPDATE calendar_events SET owner_id = 'an-earlier-account' "
        "WHERE id = 'old'",
      );

      final report = await partner().sync();

      expect(report.failure, isNull);
      expect((await eventOn(partner(), 'old'))!.ownerId, partnerUid);
      expect(
        pair.gateway.rowsOf(pair.partnerSpace, 'calendar_events')['old']!.ownerId,
        partnerUid,
      );
      expect(pair.partners.asked, isEmpty, reason: 'no pairing involved');
    });
  });

  group('before the first shared row is stored', () {
    test('every row left under another account by an old binding is made '
        'this account\'s and queued: from here on another owner means '
        'another person\'s row', () async {
      await event(partner(), 'old');
      await partner().db.customStatement(
        "UPDATE calendar_events SET owner_id = 'an-earlier-account' "
        "WHERE id = 'old'",
      );
      await partner().db.syncOutboxDao.clear();

      await partner().sync();
      await partner().sync();

      expect((await eventOn(partner(), 'old'))!.ownerId, partnerUid);
      expect(
        pair.gateway.rowsOf(pair.partnerSpace, 'calendar_events').keys,
        contains('old'),
      );
      expect(await partner().db.sharedRowDao.owner(), ownerUid);
    });

    test('and that holds when the earlier account is the partner now — one '
        'person\'s two accounts, paired: the row is theirs, and no read '
        'removes it for not being shared', () async {
      await event(partner(), 'old');
      await partner().db.customStatement(
        "UPDATE calendar_events SET owner_id = ? WHERE id = 'old'",
        [ownerUid],
      );

      await partner().sync();
      final later = DateTime.now().add(SyncEngine.fullPullInterval);
      partner().now = () => later;
      await partner().sync();

      expect((await eventOn(partner(), 'old'))!.ownerId, partnerUid);
    });
  });

}
