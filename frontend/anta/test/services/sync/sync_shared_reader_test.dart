import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/share_partner_source.dart';
import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_templates_binding.dart';
import 'package:anta/services/sync/tables/calendar_events_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import '../../database/support/db_test_support.dart';
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
    for (final row
        in await device.db
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
          call.startsWith('shared-read:') ||
          call.startsWith('count:') ||
          call == 'chunks')
        call,
  ];

  /// The shared notes [device] holds as waiting for their text, by note id.
  Future<Map<String, String>> waitingOn(SyncDevice device) async => {
    for (final (key, value) in await device.db.syncDao.valuesByPrefix(
      SyncDao.sharedWaitingPrefix,
    ))
      key.substring(SyncDao.sharedWaitingPrefix.length): value,
  };

  test('an account that never paired, shares nothing and holds no shared '
      'row asks nothing: no call for the pair, none to the space', () async {
    pair.partners.local.clear();
    pair.partners.pairs.clear();
    await event(partner(), 'own');
    partner().statements.reset();

    await partner().sync();
    await partner().sync();

    expect(pair.partners.asked, isEmpty);
    expect(sharedCalls(), isEmpty);
    expect(
      partner().statements.captured.where(
        (statement) =>
            statement.args.contains(SettingsKeys.shareHiddenCategories),
      ),
      isEmpty,
      reason: 'no choice of what shows is read',
    );
  });

  test('the Sharing page\'s read on an account that never paired asks '
      'nothing at all', () async {
    pair.partners.local.clear();
    pair.partners.pairs.clear();
    await partner().sync();
    pair.gateway.calls.clear();
    pair.gateway.readSpaceCalls = 0;

    await partner().engine.readSharedNow();

    expect(pair.partners.asked, isEmpty);
    expect(pair.gateway.calls, isEmpty);
    expect(pair.gateway.readSpaceCalls, 0);
  });

  test('an account that never paired is never told "Could not check": a '
      'local read that fails before the read knows of a pair stamps '
      'nothing', () async {
    pair.partners.local.clear();
    pair.partners.pairs.clear();
    pair.partners.localFailure = StateError('scripted');

    await partner().sync();

    final dao = partner().db.syncDao;
    expect(await dao.getValue(SyncDao.keySharedReadFailedAt), isNull);
    expect(await dao.getValue(SyncDao.keySharedReadAt), isNull);
    expect(pair.partners.asked, isEmpty);
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

    test('a read that reaches the end of every table dates the Sharing '
        'page\'s "Updated": the stamp it finished at, both ways', () async {
      await pair.syncBoth();

      final dao = partner().db.syncDao;
      final finished = await dao.getValue(SyncDao.keySharedReadAt);
      expect(finished, isNotNull);
      expect(await dao.getValue(SyncDao.keySharedReadOkAt), finished);
    });

    group('a read that fails is recorded as one (review C-5, C-9)', () {
      late DateTime clock;
      SyncDao dao() => partner().db.syncDao;
      Future<int?> stamp(String key) async =>
          int.tryParse(await dao().getValue(key) ?? '');

      setUp(() async {
        clock = DateTime.now();
        partner().now = () => clock;
        await pair.syncBoth();
        clock = clock.add(const Duration(minutes: 1));
      });

      test('the server cannot be asked: the failure is stamped, and the '
          '"Updated" stays where it was', () async {
        final ok = await stamp(SyncDao.keySharedReadOkAt);
        expect(await stamp(SyncDao.keySharedReadFailedAt), isNull);
        pair.partners.failure = const SyncGatewayException(
          SyncGatewayFailure.unknown,
        );

        await partner().sync();

        expect(
          await stamp(SyncDao.keySharedReadFailedAt),
          clock.millisecondsSinceEpoch,
        );
        expect(await stamp(SyncDao.keySharedReadOkAt), ok);
      });

      test('a read that completes after it leaves the "Updated" newer than '
          'the failure', () async {
        pair.partners.failure = const SyncGatewayException(
          SyncGatewayFailure.offline,
        );
        await partner().sync();
        final failed = await stamp(SyncDao.keySharedReadFailedAt);
        expect(failed, clock.millisecondsSinceEpoch);
        clock = clock.add(const Duration(minutes: 1));
        pair.partners.failure = null;

        await partner().sync();

        expect(await stamp(SyncDao.keySharedReadFailedAt), failed);
        expect(await stamp(SyncDao.keySharedReadOkAt), greaterThan(failed!));
      });

      test('a read the app leaving cut failed at nothing and completed '
          'nothing: neither stamp moves', () async {
        final ok = await stamp(SyncDao.keySharedReadOkAt);
        await event(owner(), 'e1', title: 'Renamed by its owner');
        await owner().sync();
        pair.gateway.calls.clear();
        var cut = false;
        partner().hooks.onBeforePage = (table) async {
          if (table == 'calendar_events' && sharedCalls().isNotEmpty) {
            cut = true;
            unawaited(partner().engine.onAppBackgrounded());
          }
        };

        await partner().sync();

        expect(cut, isTrue);
        expect(await stamp(SyncDao.keySharedReadFailedAt), isNull);
        expect(await stamp(SyncDao.keySharedReadOkAt), ok);
      });

      test('goes with the shared rows', () async {
        pair.partners.failure = const SyncGatewayException(
          SyncGatewayFailure.unknown,
        );
        await partner().sync();
        expect(await stamp(SyncDao.keySharedReadFailedAt), isNotNull);

        await partner().db.sharedRowDao.removeAll();

        expect(await stamp(SyncDao.keySharedReadFailedAt), isNull);
      });
    });

    test('is never queued on the partner\'s device, and nothing of it '
        'reaches the partner\'s own space', () async {
      await pair.syncBoth();
      await partner().sync();

      expect(await queuedOn(partner()), 0);
      expect(
        pair.gateway.rowsOf(pair.partnerSpace, 'calendar_events'),
        isEmpty,
      );
      expect(
        pair.gateway.rowsOf(pair.partnerSpace, 'calendar_event_skips'),
        isEmpty,
      );
    });

    test('follows the owner\'s changes, and the owner\'s copy wins over a '
        'copy changed here whatever its stamp says', () async {
      await pair.syncBoth();
      // A write that got past every fence — it takes the reader's own way
      // in to make one — stamped above the owner's.
      await partner().db.sharedRowDao.writing(
        () => partner().db.customStatement(
          "UPDATE calendar_events SET title = 'Changed here', "
          "hlc_timestamp = 'ffffffffffff:0000:B' WHERE id = 'e1'",
        ),
      );
      expect((await eventOn(partner(), 'e1'))!.title, 'Changed here');

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

    test('refused, is one item that could not be shown: its day rows, '
        'refused with it, are recorded for the count against the server '
        'and never counted as items of their own', () async {
      await event(partner(), 'e1', title: 'The partner\'s own');
      await partner().sync();

      await pair.syncBoth();

      final dao = partner().db.sharedRowDao;
      expect(await dao.recorded('calendar_event_skips'), isNotEmpty);
      expect(await dao.refusedCount(), 1);
    });

    test('gives way to an event of the partner\'s own that arrives from '
        'their own space under the same id afterwards: the person\'s own '
        'data comes first, whichever of the two got here first', () async {
      await pair.syncBoth();
      expect((await eventOn(partner(), 'e1'))!.ownerId, ownerUid);
      // Another device of the partner pushed an event of theirs with that
      // id — both accounts restored one backup.
      const events = CalendarEventsBinding();
      final theirs = (await eventOn(owner(), 'e1'))!;
      pair.gateway.plant(
        pair.partnerSpace,
        await events.encode(
          owner().db,
          theirs.copyWith(
            title: 'The partner\'s own',
            ownerId: const Value(partnerUid),
            sharedPair: const Value(null),
            sharedStamp: const Value(null),
          ),
          boundUid: partnerUid,
        ),
        pushedBy: 'B2',
      );

      await partner().sync();
      await partner().sync();

      final here = (await eventOn(partner(), 'e1'))!;
      expect(here.title, 'The partner\'s own');
      expect(here.ownerId, partnerUid);
      for (final days in [
        'calendar_event_skips',
        'calendar_event_occurrences',
      ]) {
        expect(
          await ownedBy(partner(), days, ownerUid, key: 'event_id'),
          isEmpty,
          reason: 'the owner\'s $days do not stay under the person\'s own',
        );
      }
    });

    test('deleted by its owner, does not delete an event of the partner\'s '
        'own under the same id', () async {
      await event(partner(), 'e1', title: 'The partner\'s own');
      await partner().sync();
      await owner().db.calendarEventDao.tombstoneEventCascade('e1');

      await pair.syncBoth();

      final own = (await eventOn(partner(), 'e1'))!;
      expect(own.isDeleted, isFalse);
      expect(own.title, 'The partner\'s own');
      expect(own.ownerId, isNot(ownerUid));
    });

    test('its day rows do not take the place of day rows of the partner\'s '
        'own under the same event and day, whoever the event belongs to '
        'here', () async {
      Future<List<String?>> skipOwners(DateTime on) async => [
        for (final row
            in await partner().db
                .customSelect(
                  'SELECT owner_id FROM calendar_event_skips '
                  "WHERE event_id = 'e1' AND day = ? AND is_deleted = 0",
                  variables: [Variable<DateTime>(on)],
                )
                .get())
          row.read<String?>('owner_id'),
      ];
      await pair.syncBoth();
      expect(await skipOwners(day), [ownerUid]);
      // A day row of the partner's own under the shared event — stored the
      // only way one can be, by the reader's hand.
      final next = day.add(const Duration(days: 7));
      await partner().db.sharedRowDao.writing(
        () => partner().db.eventSkipDao.markSkipped('e1', next),
      );

      await owner().db.eventSkipDao.markSkipped('e1', next);
      await pair.syncBoth();

      expect(await skipOwners(next), [isNot(ownerUid)]);
    });

    test('carrying the stamp of a shipped default is taken like any other: '
        'the owner\'s copy wins, and the copy here is never kept and queued '
        'against it', () async {
      await pair.syncBoth();
      const events = CalendarEventsBinding();
      final theirs = (await eventOn(owner(), 'e1'))!;
      final seeded = await events.encode(
        owner().db,
        theirs.copyWith(
          title: 'Seeded',
          hlcTimestamp: HlcTimestamp.seed.toString(),
        ),
        boundUid: ownerUid,
      );
      pair.gateway.elapse(const Duration(minutes: 1));
      pair.gateway.plant(
        pair.ownerSpace,
        SyncEnvelope(
          table: seeded.table,
          rowKey: seeded.rowKey,
          hlc: seeded.hlc,
          deviceId: seeded.deviceId,
          version: seeded.version,
          op: seeded.op,
          ownerId: ownerUid,
          data: seeded.data,
          sharedPair: sharePairId,
          wire: syncSchema,
        ),
        pushedBy: 'A',
      );

      await partner().sync();

      expect((await eventOn(partner(), 'e1'))!.title, 'Seeded');
      expect(await queuedOn(partner()), 0);
    });

    test('written by a newer build is passed over and remembered; a build '
        'that reads that wire then reads the table again from the start '
        'and takes it', () async {
      await owner().sync();
      const events = CalendarEventsBinding();
      final row = (await eventOn(owner(), 'e1'))!;
      final envelope = await events.encode(owner().db, row, boundUid: ownerUid);
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

      await owner().db.noteDao.moveNote(id: top.id, targetFolderId: cabinet.id);
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

    /// A device of the owner that had not heard of the share pushed last:
    /// the space stops naming the pair, and its notes' text is refused.
    Future<void> spaceForgetsThePair() => pair.gateway.writeSpaceShare(
      pair.ownerSpace,
      sharedPair: null,
      pushedBy: 'C',
      schema: syncSchema,
    );

    Future<void> spaceNamesThePair() => pair.gateway.writeSpaceShare(
      pair.ownerSpace,
      sharedPair: sharePairId,
      pushedBy: 'A',
      schema: syncSchema,
    );

    test('a note whose text cannot be read yet — the owner\'s space does '
        'not name the pair — waits, and the next read asks for that note '
        'alone, by its place, once more', () async {
      await owner().sync();
      await spaceForgetsThePair();

      await partner().sync();

      expect(await folderOn(partner(), shelf.id), isNotNull);
      expect(await noteOn(partner(), top.id), isNull);
      final space = pair.ownerSpace;
      expect(await waitingOn(partner()), {
        top.id: '0|${space.ownerUid}/${space.spaceId}',
        low.id: '0|${space.ownerUid}/${space.spaceId}',
      });

      await spaceNamesThePair();
      pair.gateway.calls.clear();
      pair.gateway.elapse(const Duration(minutes: 1));
      await partner().sync();

      expect(await textOn(partner(), top.id), 'Text on the shelf');
      expect(await textOn(partner(), low.id), 'Text in the box');
      expect(await waitingOn(partner()), isEmpty);
      expect(
        pair.gateway.sharedRowReads,
        unorderedEquals(['notes/${top.id}', 'notes/${low.id}']),
      );
      expect(
        [
          for (final call in sharedCalls())
            if (call == 'shared:notes') call,
        ],
        hasLength(1),
        reason: 'the cursor\'s own page, never the table from its start',
      );
    });

    test('a note still without its text is asked for a bounded number of '
        'times, then left to the daily read from the start', () async {
      await owner().sync();
      await spaceForgetsThePair();
      await partner().sync();

      await partner().sync();
      expect((await waitingOn(partner()))[top.id], startsWith('1|'));

      final space = pair.ownerSpace;
      await partner().db.syncDao.setValue(
        SyncDao.keySharedWaiting(top.id),
        '12|${space.ownerUid}/${space.spaceId}',
      );
      pair.gateway.sharedRowReads.clear();
      await partner().sync();
      expect(pair.gateway.sharedRowReads, ['notes/${low.id}']);

      await spaceNamesThePair();
      final later = DateTime.now().add(SyncEngine.fullPullInterval);
      partner().now = () => later;
      await partner().sync();

      expect(await textOn(partner(), top.id), 'Text on the shelf');
      expect(await waitingOn(partner()), isEmpty);
    });

    test('a note that stops being shared while it waits stops waiting: its '
        'document refuses the read, and nothing asks for it again', () async {
      await owner().sync();
      await spaceForgetsThePair();
      await partner().sync();
      expect(await waitingOn(partner()), isNotEmpty);

      await owner().db.folderDao.setSharedPair(shelf.id, null);
      await owner().sync();
      await partner().sync();

      expect(await waitingOn(partner()), isEmpty);
      expect(await noteOn(partner(), top.id), isNull);
      pair.gateway.sharedRowReads.clear();
      await partner().sync();
      expect(pair.gateway.sharedRowReads, isEmpty);
    });

    test('a waiting note that ends any other way than still lacking its '
        'text — here a newer build rewrote it — stops waiting: it was asked '
        'for at every poll, with no try ever counted', () async {
      await owner().sync();
      await spaceForgetsThePair();
      await partner().sync();
      expect((await waitingOn(partner())).keys, contains(top.id));
      // The owner updated, and their build wrote the note again.
      final note = pair.gateway.rowsOf(pair.ownerSpace, 'notes')[top.id]!;
      pair.gateway.plant(
        pair.ownerSpace,
        SyncEnvelope(
          table: note.table,
          rowKey: note.rowKey,
          hlc: note.hlc,
          deviceId: note.deviceId,
          version: note.version,
          op: note.op,
          ownerId: note.ownerId,
          data: note.data,
          sharedPair: sharePairId,
          wire: syncSchema + 1,
        ),
        pushedBy: 'A',
      );
      pair.gateway.sharedRowReads.clear();

      await partner().sync();
      await partner().sync();
      await partner().sync();

      expect(
        pair.gateway.sharedRowReads.where((read) => read.endsWith(top.id)),
        hasLength(1),
      );
      expect((await waitingOn(partner())).keys, isNot(contains(top.id)));
    });

    test('no longer shared, is taken off the screens as it is taken out of '
        'the database: each folder and note announced as gone, with the '
        'list it stood in', () async {
      await pair.syncBoth();
      partner().hooks.clear();

      await owner().db.folderDao.setSharedPair(shelf.id, null);
      await pair.syncBoth();

      final gone = {
        for (final (table, rows) in partner().hooks.pages)
          for (final row in rows)
            if (row.gone) '$table/${row.rowKey}': row.previousParent,
      };
      expect(gone, {
        'folders/${shelf.id}': null,
        'folders/${box.id}': shelf.id,
        'notes/${top.id}': shelf.id,
        'notes/${low.id}': box.id,
      });
    });

    test('a count the server cannot answer — its index still building — '
        'skips that table\'s look for rows that left and nothing else: the '
        'tables after it are read', () async {
      // Past the day's first read, which takes every table from its start
      // and asks for no count.
      await pair.syncBoth();
      pair.gateway.failSharedCounts.add('calendar_events');
      pair.gateway.calls.clear();
      await owner().db.folderDao.updateFolder(id: shelf.id, name: 'Renamed');
      await owner().sync();

      final report = await partner().sync();

      expect(sharedCalls(), contains('count:calendar_events'));
      expect(report.failure, isNull);
      expect((await folderOn(partner(), shelf.id))!.name, 'Renamed');
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

  // A category is a third root of a grant
  // (docs/cloud-share-surfaces-roadmap.md §7.5): read first, so an event
  // never arrives before the category that draws it.
  group('a shared category', () {
    Future<void> category(
      SyncDevice device,
      String id, {
      String? name,
      bool builtIn = false,
    }) => device.db.calendarCategoryDao.insertCategory(
      CalendarCategoriesCompanion.insert(
        id: id,
        name: name ?? 'Category $id',
        colorValue: 0xFF336699,
        iconKey: 'event',
        isBuiltIn: Value(builtIn),
        sortOrder: const Value(5),
        isHidden: const Value(true),
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

    Future<CalendarCategoryRow?> categoryOn(
      SyncDevice device,
      String id,
    ) async => (await device.db.calendarCategoryDao.getByIdsIncludingDeleted([
      id,
    ])).firstOrNull;

    setUp(() async {
      await category(owner(), 'climb', name: 'Climb');
      await eventIn(owner(), 'e1', 'climb');
      await eventIn(owner(), 'private', 'general');
      await owner().db.eventSkipDao.markSkipped('e1', day);
      await owner().db.calendarCategoryDao.setSharedPair('climb', sharePairId);
    });

    test('arrives under the owner\'s account in the same read as its events, '
        'first — the mark not stored, the owner\'s order and archive flag '
        'not obeyed, nothing queued — and an event shared only through it '
        'arrives with its day rows', () async {
      await owner().sync();
      expect(
        pair.gateway
            .rowsOf(pair.ownerSpace, 'calendar_categories')['climb']!
            .sharedPair,
        sharePairId,
        reason: 'the category\'s own document names the pair',
      );
      partner().hooks.clear();

      await partner().sync();

      final shared = (await categoryOn(partner(), 'climb'))!;
      expect(shared.name, 'Climb');
      expect(shared.ownerId, ownerUid);
      expect(shared.sharedPair, isNull);
      expect(shared.sharedStamp, isNull);
      expect(shared.sortOrder, 0);
      expect(shared.isHidden, isFalse);
      expect(shared.isBuiltIn, isFalse);
      expect((await eventOn(partner(), 'e1'))!.ownerId, ownerUid);
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
        partner().hooks.calls,
        containsAllInOrder([
          'before:calendar_categories',
          'before:calendar_events',
        ]),
      );
      expect(await queuedOn(partner()), 0);
    });

    test('follows its rename, and the owner\'s copy wins over one changed '
        'here', () async {
      await pair.syncBoth();
      await partner().db.sharedRowDao.writing(
        () => partner().db.customStatement(
          "UPDATE calendar_categories SET name = 'Changed here', "
          "hlc_timestamp = 'ffffffffffff:0000:B' WHERE id = 'climb'",
        ),
      );

      await owner().db.calendarCategoryDao.updateCategory(
        const CalendarCategoriesCompanion(
          id: Value('climb'),
          name: Value('Bouldering'),
        ),
      );
      await pair.syncBoth();

      expect((await categoryOn(partner(), 'climb'))!.name, 'Bouldering');
      expect(await queuedOn(partner()), 0);
    });

    test('made private again, leaves with the events it alone shared and '
        'their day rows; a category alert and a category profile of the '
        'partner\'s own on it stay, inert', () async {
      await pair.syncBoth();
      await partner().db.categoryAlertDao.replaceForCategory('climb', [
        CalendarCategoryAlertsCompanion.insert(
          id: 'alert',
          categoryId: 'climb',
          createdAt: day,
          updatedAt: day,
          hlcTimestamp: '000000000001:0000:B',
          deviceId: 'B',
        ),
      ]);
      await partner().db.categoryProfileDao.upsertForCategory(
        CalendarCategoryProfilesCompanion.insert(
          id: 'profile',
          categoryId: 'climb',
          kind: const Value('workout'),
          createdAt: day,
          updatedAt: day,
          hlcTimestamp: '000000000001:0000:B',
          deviceId: 'B',
        ),
      );

      await owner().db.calendarCategoryDao.setSharedPair('climb', null);
      await pair.syncBoth();

      expect(
        await categoryOn(partner(), 'climb'),
        isNull,
        reason: 'no tombstone',
      );
      expect(await eventOn(partner(), 'e1'), isNull);
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
              "SELECT 1 FROM calendar_category_alerts WHERE id = 'alert'",
            )
            .get(),
        hasLength(1),
      );
      expect(
        (await partner().db.categoryProfileDao.getActiveForCategory(
          'climb',
        ))?.id,
        'profile',
      );
    });

    group('hidden on this phone (share surfaces §6.4, D11)', () {
      Future<Set<String>> hidden() =>
          SettingsService.shareHiddenCategoriesOf(partner().db);
      Future<void> hide(Set<String> ids) =>
          SettingsService.setShareHiddenCategoriesOf(partner().db, ids);

      test('stays hidden while it is shared, read after read', () async {
        await pair.syncBoth();
        await hide({'climb'});
        partner().hooks.runs.clear();

        await pair.syncBoth();
        await pair.syncBoth();

        expect(await hidden(), {'climb'});
        expect(
          partner().hooks.runs.expand((run) => run),
          isNot(contains(SyncInvalidation.unhidden)),
          reason: 'a read that pruned nothing patches as before',
        );
      });

      test('made private, it leaves the hidden set with its share — the '
          'calendar told — so sharing it again starts shown', () async {
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        await hide({'climb', 'gym'});

        await owner().db.calendarCategoryDao.setSharedPair('climb', null);
        partner().hooks.runs.clear();
        await pair.syncBoth();

        expect(await hidden(), {'gym'});
        expect(partner().hooks.runs.last, contains(SyncInvalidation.calendar));
        expect(
          partner().hooks.runs.last,
          contains(SyncInvalidation.unhidden),
          reason: 'an event shared singly in climb is read back whole',
        );

        await owner().db.calendarCategoryDao.setSharedPair(
          'climb',
          sharePairId,
        );
        await pair.syncBoth();
        expect((await categoryOn(partner(), 'climb'))!.ownerId, ownerUid);
        expect(await hidden(), {'gym'});
      });

      test('a built-in the owner stops sharing leaves it too', () async {
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        await hide({'gym'});

        await owner().db.calendarCategoryDao.setSharedPair('gym', null);
        await pair.syncBoth();

        expect(await hidden(), isEmpty);
      });

      test('deleted by its owner, it leaves it', () async {
        await pair.syncBoth();
        await hide({'climb'});

        await owner().db.calendarCategoryDao.tombstoneCascade(
          'climb',
          reassignTo: 'general',
        );
        await pair.syncBoth();

        expect(await hidden(), isEmpty);
      });

      test('the pair ended, or another pair made, empties it: another pair\'s '
          'built-ins must not start hidden by this one\'s choices', () async {
        await pair.syncBoth();
        await hide({'climb', 'gym'});

        pair.end();
        await partner().sync();

        expect(await hidden(), isEmpty);
      });

      test('another pair made, with another account, empties it too',
          () async {
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        await hide({'climb', 'gym'});

        pair.gateway.pair('pair-3', partnerUid, 'u3');
        pair.partners.pairs[partnerUid] = SharePartner(
          pairId: 'pair-3',
          partnerUid: 'u3',
        );
        await partner().sync();

        expect(await partner().db.sharedRowDao.owner(), 'u3');
        expect(await hidden(), isEmpty);
      });

      test('an unbind takes it with the shared rows: a new pair\'s built-in '
          'does not start hidden', () async {
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        expect(await partner().db.sharedRowDao.sharedBuiltIns(), {'gym'});
        await hide({'gym'});

        // What the unbind does to the shared rows, in its own transaction.
        final removed = await partner().db.sharedRowDao.removeAll();
        expect(await hidden(), isEmpty);
        expect(removed.isEmpty, isFalse, reason: 'the screens reload by it');

        pair.end();
        pair.join(pairId: 'pair-2');
        await owner().db.calendarCategoryDao.setSharedPair('gym', 'pair-2');
        await pair.syncBoth();
        await pair.syncBoth();

        expect(await partner().db.sharedRowDao.sharedBuiltIns(), {'gym'});
        expect(await hidden(), isEmpty);
      });

      test('a switch flipped while the read prunes holds: the two '
          'read-modify-writes do not interleave', () async {
        await category(owner(), 'run');
        await owner().db.calendarCategoryDao.setSharedPair('run', sharePairId);
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        final db = partner().db;
        await hide({'climb', 'gym'});
        await owner().db.calendarCategoryDao.setSharedPair('climb', null);

        // A writer outside the prune's transaction — the Sharing page's
        // "hide run" — starting between the prune's read and its write.
        final outside = Zone.current;
        Future<void>? flipped;
        partner().statements.onStatement = (sql, args) {
          if (flipped == null &&
              sql.contains('WHERE owner_id = ? AND is_deleted = 0')) {
            flipped = outside.run(() async {
              final now = await SettingsService.shareHiddenCategoriesOf(db);
              await SettingsService.setShareHiddenCategoriesOf(db, {
                ...now,
                'run',
              });
            });
          }
          return null;
        };
        await pair.syncBoth();
        partner().statements.onStatement = null;
        await flipped;

        expect(flipped, isNotNull);
        expect(await hidden(), {'gym', 'run'});
      });

      test('a prune that fails is not a failed read: the set stays as it '
          'stood, and the read is stamped as the read went', () async {
        await pair.syncBoth();
        await hide({'climb'});
        await owner().db.calendarCategoryDao.setSharedPair('climb', null);
        partner().statements.onStatement = (sql, args) =>
            args.contains(SettingsKeys.shareHiddenCategories)
            ? Future<void>.error(StateError('settings unreadable'))
            : null;
        final dao = partner().db.syncDao;
        await dao.deleteValue(SyncDao.keySharedReadOkAt);

        await pair.syncBoth();
        partner().statements.onStatement = null;

        expect(await hidden(), {'climb'});
        expect(await dao.getValue(SyncDao.keySharedReadFailedAt), isNull);
        expect(await dao.getValue(SyncDao.keySharedReadOkAt), isNotNull);
        expect(await categoryOn(partner(), 'climb'), isNull);
      });

      test('a read with nothing hidden reads the setting once and nothing '
          'more', () async {
        await pair.syncBoth();
        partner().statements.reset();

        await partner().sync();

        final reads = [
          for (final statement in partner().statements.captured)
            if (statement.args.contains(SettingsKeys.shareHiddenCategories))
              statement,
        ];
        expect(reads, hasLength(1));
        expect(
          partner().statements.matching('WHERE owner_id = ? AND is_deleted'),
          isEmpty,
          reason: 'the shared categories are read only to prune',
        );
      });
    });

    test('deleted by its owner, arrives as a deletion, and its events, moved '
        'to a category that is not shared, leave', () async {
      await pair.syncBoth();

      await owner().db.calendarCategoryDao.tombstoneCascade(
        'climb',
        reassignTo: 'general',
      );
      await pair.syncBoth();

      final shared = (await categoryOn(partner(), 'climb'))!;
      expect(shared.isDeleted, isTrue);
      expect(shared.ownerId, ownerUid);
      expect(await eventOn(partner(), 'e1'), isNull);
    });

    group('that this device does not store', () {
      Future<int> refused() => partner().db.sharedRowDao.refusedCount();
      Future<Set<String>> builtIns() =>
          partner().db.sharedRowDao.sharedBuiltIns();

      test('a built-in is never stored, though nothing here holds its id: it '
          'is recorded as received and never counted as a row that could '
          'not be shown — and its events arrive, drawn by the person\'s own '
          'row of it', () async {
        await category(owner(), 'gym', builtIn: true);
        await eventIn(owner(), 'e2', 'gym');
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);

        await pair.syncBoth();

        expect(await categoryOn(partner(), 'gym'), isNull);
        expect(await builtIns(), {'gym'});
        expect(await refused(), 0);
        expect((await eventOn(partner(), 'e2'))!.ownerId, ownerUid);
        expect((await categoryOn(partner(), 'climb'))!.ownerId, ownerUid);
      });

      test('a built-in\'s record goes when the owner stops sharing it — a '
          'read from the start no longer meets it — and when the pair '
          'ends', () async {
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        expect(await builtIns(), {'gym'});

        await owner().db.calendarCategoryDao.setSharedPair('gym', null);
        await pair.syncBoth();
        expect(await builtIns(), isEmpty);

        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        expect(await builtIns(), {'gym'});
        pair.end();
        await partner().sync();
        expect(await builtIns(), isEmpty);
      });

      test('a custom category under an id of the person\'s own is refused, '
          'counted, and forgotten once the owner stops sharing it — at the '
          'next read, not the daily one', () async {
        await category(partner(), 'climb', name: 'The partner\'s own');
        await partner().sync();

        await pair.syncBoth();

        final own = (await categoryOn(partner(), 'climb'))!;
        expect(own.name, 'The partner\'s own');
        expect(own.ownerId, isNot(ownerUid));
        expect(await refused(), 1);
        expect(await builtIns(), isEmpty);

        await owner().db.calendarCategoryDao.setSharedPair('climb', null);
        await pair.syncBoth();

        expect(await refused(), 0);
        expect(
          (await categoryOn(partner(), 'climb'))!.name,
          'The partner\'s own',
        );
      });

      test('costs nothing while it stays — the count holds it — and one read '
          'of its table from the start once it leaves', () async {
        await category(partner(), 'climb', name: 'The partner\'s own');
        await partner().sync();
        await pair.syncBoth();
        List<String> categoryCalls() => [
          for (final call in sharedCalls())
            if (call.endsWith(':calendar_categories')) call,
        ];

        pair.gateway.calls.clear();
        await partner().sync();
        expect(categoryCalls(), [
          'shared:calendar_categories',
          'count:calendar_categories',
        ]);

        await owner().db.calendarCategoryDao.setSharedPair('climb', null);
        await owner().sync();
        pair.gateway.calls.clear();
        await partner().sync();
        expect(categoryCalls(), [
          'shared:calendar_categories',
          'count:calendar_categories',
          'shared:calendar_categories',
        ]);
      });

      test('a refused category its owner deletes is forgotten: a tombstone '
          'is nothing to show', () async {
        await category(partner(), 'climb', name: 'The partner\'s own');
        await partner().sync();
        await pair.syncBoth();
        expect(await refused(), 1);

        await owner().db.calendarCategoryDao.tombstoneCascade(
          'climb',
          reassignTo: 'general',
        );
        await pair.syncBoth();

        expect(await refused(), 0);
        expect((await categoryOn(partner(), 'climb'))!.isDeleted, isFalse);
      });

      test('a refused category its owner deletes keeps its record, which the '
          'server still counts: a category that leaves later is found at the '
          'next read, not masked by it', () async {
        await category(partner(), 'climb', name: 'The partner\'s own');
        await partner().sync();
        await category(owner(), 'hike', name: 'Hike');
        await owner().db.calendarCategoryDao.setSharedPair('hike', sharePairId);
        await category(owner(), 'gym', builtIn: true);
        await owner().db.calendarCategoryDao.setSharedPair('gym', sharePairId);
        await pair.syncBoth();
        expect(await refused(), 1);
        expect((await categoryOn(partner(), 'hike'))!.ownerId, ownerUid);

        await owner().db.calendarCategoryDao.tombstoneCascade(
          'climb',
          reassignTo: 'general',
        );
        await pair.syncBoth();
        expect(await refused(), 0);

        await owner().db.calendarCategoryDao.setSharedPair('hike', null);
        await pair.syncBoth();

        expect(await categoryOn(partner(), 'hike'), isNull);
        expect(await builtIns(), {'gym'});
      });

      test('a built-in\'s tombstone keeps its record the same way: counted '
          'against the server, never listed as received', () async {
        final dao = partner().db.sharedRowDao;
        await dao.noteRefused(
          'calendar_categories',
          'gym',
          live: true,
          builtIn: true,
        );
        await dao.noteRefused(
          'calendar_categories',
          'gym',
          live: false,
          builtIn: true,
        );

        expect(await builtIns(), isEmpty);
        expect(await dao.recorded('calendar_categories'), {'gym'});
        expect(await dao.countOf('calendar_categories', ownerUid), 1);
        expect(await refused(), 0);
      });

      group('under an id the person\'s own rows name, with no category of '
          'theirs under it', () {
        setUp(() async {
          await eventIn(partner(), 'mine', 'climb');
          await partner().db.eventTemplateDao.upsertTemplate(
            EventTemplatesCompanion.insert(
              id: 'tpl',
              name: 'Template',
              category: 'climb',
              createdAt: day,
              updatedAt: day,
              hlcTimestamp: '000000000001:0000:B',
              deviceId: 'B',
            ),
          );
          await partner().sync();
        });

        test('is refused like an id of theirs, and counted', () async {
          await pair.syncBoth();

          expect(await categoryOn(partner(), 'climb'), isNull);
          expect(await refused(), 1);
          expect((await eventOn(partner(), 'mine'))!.category, 'climb');
        });

        test('my event keeps drawing as mine — which is what keeps it in '
            'the .ics export', () async {
          await pair.syncBoth();
          CategoryService.reset();
          await CategoryService.forTesting(partner().db);

          expect(CalendarCategories.resolve('climb').fromPartner, isFalse);
          expect(CalendarCategories.all.where((c) => c.fromPartner), isEmpty);
          CategoryService.reset();
        });

        test('its tombstone is refused too, and holds nothing', () async {
          await owner().db.calendarCategoryDao.tombstoneCascade(
            'climb',
            reassignTo: 'general',
          );
          await pair.syncBoth();

          expect(await categoryOn(partner(), 'climb'), isNull);
          await partner().db.calendarEventDao.upsert(
            CalendarEventsCompanion.insert(
              id: 'later',
              title: 'Later',
              category: 'climb',
              startDate: day,
              ruleKind: 'weekly',
              createdAt: day,
              updatedAt: day,
            ),
          );
          expect((await eventOn(partner(), 'later'))!.category, 'climb');
        });

        test('a template alone names it enough', () async {
          await partner().db.customStatement(
            "DELETE FROM calendar_events WHERE id = 'mine'",
          );

          await pair.syncBoth();

          expect(await categoryOn(partner(), 'climb'), isNull);
          expect(await refused(), 1);
        });
      });
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
        pair.gateway
            .rowsOf(pair.ownerSpace, 'calendar_events')['e1']!
            .sharedPair,
        isNull,
      );
    });

    test('ended: the owner\'s caches are told its marks were cleared, which '
        'no page names; a read that clears none tells nothing (review '
        'C-1)', () async {
      expect(
        owner().hooks.runs.expand((touched) => touched),
        isNot(contains(SyncInvalidation.shareMarks)),
      );
      owner().hooks.clear();
      pair.end();

      await owner().sync();

      expect(
        owner().hooks.runs.expand((touched) => touched),
        contains(SyncInvalidation.shareMarks),
      );
    });

    test(
      'that cannot be asked about — no connection — removes nothing',
      () async {
        pair.partners.failure = const SyncGatewayException(
          SyncGatewayFailure.offline,
        );

        final report = await partner().sync();

        expect(report.failure, isNull, reason: 'the account\'s own sync ran');
        expect(await eventOn(partner(), 'e1'), isNotNull);
      },
    );

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
          'calendar_categories',
          'calendar_events',
          'calendar_event_occurrences',
          'calendar_event_skips',
          'folders',
          'notes',
        ]) ...['shared:$table', 'count:$table'],
      ]);
    });

    group('on an account that never had a refusal', () {
      bool readsRecords(CapturedStatement statement) =>
          statement.isSelect &&
          statement.args.any(
            (arg) =>
                arg is String &&
                (arg.startsWith(SyncDao.sharedRefusedPrefix) ||
                    arg.startsWith(SyncDao.sharedBuiltInPrefix)),
          );

      test('a read reads each table\'s records once, by the count — a page '
          'it stores only forgets, unread', () async {
        partner().statements.reset();

        // The events' page re-reads the shared event in the overlap before
        // the cursor, and stores it again.
        await partner().sync();

        expect(
          partner().statements.captured.where(readsRecords),
          hasLength(6),
          reason: [
            for (final s in partner().statements.captured.where(readsRecords))
              '${s.sql} ${s.args}',
          ].join('\n'),
        );
        expect(
          partner().statements.captured.where(
            (statement) =>
                statement.sql.startsWith('DELETE') &&
                statement.args.contains(
                  SyncDao.keySharedRefused('calendar_events', 'e1'),
                ),
          ),
          hasLength(1),
        );
      });

      test(
        'a page with nothing stored forgets nothing, at no statement',
        () async {
          partner().statements.reset();

          await partner().db.sharedRowDao.noteStored(
            'calendar_events',
            const [],
          );

          expect(partner().statements.count, 0);
        },
      );

      test('a templates page of the account\'s own costs three lookups: the '
          'shared account, asked twice, and one read of whether a shared '
          'category holds a category it names', () async {
        Future<int> sharedLookups() async {
          partner().statements.reset();
          await partner().sync();
          return partner().statements.captured
              .where(
                (statement) =>
                    statement.args.contains(SyncDao.keySharedOwner) ||
                    statement.sql.contains(
                      'FROM calendar_categories WHERE owner_id = ?',
                    ),
              )
              .length;
        }

        final idle = await sharedLookups();
        // Written on another device of the partner's own account: built on
        // the owner's database, which syncs no more here, and planted.
        await owner().db.eventTemplateDao.upsertTemplate(
          EventTemplatesCompanion.insert(
            id: 'tpl',
            name: 'Template',
            category: 'gym',
            createdAt: day,
            updatedAt: day,
            hlcTimestamp: '000000000001:0000:C',
            deviceId: 'C',
          ),
        );
        final row = (await owner().db.eventTemplateDao.getByIdsIncludingDeleted(
          ['tpl'],
        )).single;
        pair.gateway.plant(
          pair.partnerSpace,
          await const CalendarEventTemplatesBinding().encode(
            owner().db,
            row,
            boundUid: partnerUid,
          ),
          pushedBy: 'C',
        );

        final page = await sharedLookups();

        expect(
          (await partner().db.eventTemplateDao.getByIdsIncludingDeleted([
            'tpl',
          ])).single.category,
          'gym',
        );
        expect(
          page - idle,
          3,
          reason: partner().statements.statements.join('\n'),
        );
      });
    });

    test('the Sharing page\'s read under the manual cadence costs the shared '
        'read alone: no pull, no push, no read of the space', () async {
      await partner().engine.stop();
      await partner().binding.setCadence(SyncCadence.manual);
      await partner().engine.start();
      await partner().settle();
      await event(partner(), 'own');
      await partner().settle();
      pair.gateway.calls.clear();
      pair.gateway.readSpaceCalls = 0;
      pair.partners.asked.clear();

      final report = await partner().engine.readSharedNow();

      expect(report.skipped, isNull);
      expect(pair.partners.asked, [partnerUid]);
      expect(pair.gateway.calls, [
        for (final table in const [
          'calendar_categories',
          'calendar_events',
          'calendar_event_occurrences',
          'calendar_event_skips',
          'folders',
          'notes',
        ]) ...['shared:$table', 'count:$table'],
      ]);
      expect(pair.gateway.readSpaceCalls, 0);
      expect(await queuedOn(partner()), 1, reason: 'nothing was pushed');
    });

    test('the Sharing page\'s read merged into a run nobody asked for — '
        'queued as the cadence turned manual — reads the share and pulls '
        'nothing (review C-7)', () async {
      await partner().engine.start();
      await partner().settle();
      final asked = pair.partners.asked.length;
      Future<SyncRunReport>? read;
      pair.gateway.onPullPage = (table) async {
        if (table != 'calendar_categories') return;
        pair.gateway.onPullPage = null;
        // The partner's own space moves: a stale run nobody asked for
        // queues behind the one in flight. Then the switch goes off, and
        // the Sharing page opens.
        await pair.gateway.writeSpaceShare(
          pair.partnerSpace,
          sharedPair: null,
          pushedBy: 'B2',
          schema: syncSchema,
        );
        await Future<void>.delayed(Duration.zero);
        await partner().engine.setCadence(SyncCadence.manual);
        read = partner().engine.readSharedNow();
      };

      await partner().sync();
      final report = await read!;

      expect(report.skipped, isNull);
      expect(report.pages, 0, reason: 'no table of the account\'s own');
      expect(
        pair.partners.asked,
        hasLength(asked + 2),
        reason: 'the run in flight read the share, and so did this one',
      );
    });

    test('a shared-only run under a noAccess pause is skipped and leaves the '
        'recheck to the account\'s own run (review C-8)', () async {
      pair.gateway.failNextWith(SyncGatewayFailure.permissionDenied);
      await partner().sync();
      expect(partner().engine.current.pause, SyncPause.noAccess);
      pair.gateway.readSpaceCalls = 0;

      // The share's read is in its gate when "Sync now" asks for the
      // recheck.
      final read = partner().engine.readSharedNow();
      final now = partner().engine.syncNow();

      expect((await read).skipped, SyncRunSkip.noAccess);
      expect((await now).skipped, isNull);
      expect(pair.gateway.readSpaceCalls, 1, reason: '"Sync now"\'s recheck');
      expect(partner().engine.current.pause, SyncPause.none);
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
      // Lost the only way it can be: by the reader's own hand.
      await partner().db.sharedRowDao.writing(
        () => partner().db.customStatement(
          "DELETE FROM calendar_events WHERE id = 'e1'",
        ),
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

  group('beside the account\'s own sync', () {
    setUp(() async {
      for (final id in ['e1', 'e2', 'e3']) {
        await event(owner(), id);
        await owner().db.calendarEventDao.setSharedPair(id, sharePairId);
      }
    });

    test('reports nothing into the run: a run that brought only shared '
        'rows pulled none of the account\'s own', () async {
      await owner().sync();
      await partner().sync();
      pair.gateway.elapse(const Duration(minutes: 1));
      await event(owner(), 'e4');
      await owner().db.calendarEventDao.setSharedPair('e4', sharePairId);
      await owner().sync();
      final before = await partner().sync();

      await event(owner(), 'e5');
      await owner().db.calendarEventDao.setSharedPair('e5', sharePairId);
      await owner().sync();
      final report = await partner().sync();

      expect(await eventOn(partner(), 'e5'), isNotNull);
      expect(report.pulledRows, 0);
      expect(report.pages, before.pages);
    });

    test('a table of the account\'s own that fails its pull fails the run, '
        'and what the partner shares is read all the same', () async {
      // Past the bind's first merge, which waits for a pull that read
      // everything before another account's rows arrive.
      await partner().sync();
      await owner().sync();
      // Another device of the partner's pushed an event; its page fails
      // here on a fault of this device's own.
      const events = CalendarEventsBinding();
      final encoded = await events.encode(
        owner().db,
        (await eventOn(owner(), 'e1'))!.copyWith(
          id: 'theirs',
          ownerId: const Value(partnerUid),
          sharedPair: const Value(null),
          sharedStamp: const Value(null),
        ),
        boundUid: partnerUid,
      );
      pair.gateway.plant(pair.partnerSpace, encoded, pushedBy: 'B2');
      var failed = false;
      partner().hooks.onBeforePage = (table) async {
        if (table == 'calendar_events' && !failed) {
          failed = true;
          throw StateError('scripted');
        }
      };

      final report = await partner().sync();

      expect(failed, isTrue);
      expect(report.failure, SyncGatewayFailure.unknown);
      expect(await eventOn(partner(), 'theirs'), isNull);
      expect(await ownedBy(partner(), 'calendar_events', ownerUid), {
        'e1',
        'e2',
        'e3',
      });
    });

    test('a read from the start that the app leaving cut removes nothing: '
        'only a walk that saw every shared row says which ones left', () async {
      await pair.syncBoth();
      pair.gateway.elapse(const Duration(minutes: 1));
      await owner().db.calendarEventDao.setSharedPair('e1', null);
      await owner().sync();
      // A page per row, so the walk has an end to be cut before — and cut
      // once the count has sent the read back to the start, not earlier.
      pair.gateway.maxBatch = 1;
      pair.gateway.calls.clear();
      var cut = false;
      partner().hooks.onBeforePage = (table) async {
        if (table == 'calendar_events' &&
            pair.gateway.calls.contains('count:calendar_events')) {
          cut = true;
          unawaited(partner().engine.onAppBackgrounded());
        }
      };

      await partner().sync();

      expect(cut, isTrue);
      expect(await ownedBy(partner(), 'calendar_events', ownerUid), {
        'e1',
        'e2',
        'e3',
      });

      partner().hooks.onBeforePage = null;
      partner().engine.onAppResumed();
      await partner().sync();

      expect(await ownedBy(partner(), 'calendar_events', ownerUid), {
        'e2',
        'e3',
      });
    });
  });

  group('the person\'s own row, arriving from their own space', () {
    late Folder shelf;
    late Note top;

    /// [envelope] as a document of the partner's own, pushed by another
    /// device of theirs — both accounts restored one backup, so the ids
    /// are the same on both sides.
    SyncEnvelope asOwn(
      SyncEnvelope envelope, {
      String? rowKey,
      Map<String, Object?> over = const {},
    }) {
      final data = envelope.data == null
          ? null
          : (Map<String, Object?>.of(envelope.data!)
              ..remove('ownerId')
              ..remove('sharedPair')
              ..remove('sharedStamp')
              ..addAll(over));
      return SyncEnvelope(
        table: envelope.table,
        rowKey: rowKey ?? envelope.rowKey,
        hlc: envelope.hlc,
        deviceId: 'B2',
        version: envelope.version,
        op: envelope.op,
        ownerId: partnerUid,
        data: data,
      );
    }

    void plantOwn(SyncEnvelope envelope) =>
        pair.gateway.plant(pair.partnerSpace, envelope, pushedBy: 'B2');

    /// The owner's chunk documents, as the partner's own space would hold
    /// the same text.
    void plantOwnChunks() {
      for (final chunk
          in pair.gateway.rowsOf(pair.ownerSpace, 'content_chunks').values) {
        plantOwn(asOwn(chunk));
      }
    }

    setUp(() async {
      shelf = await owner().db.folderDao.createFolder(name: 'Shelf');
      top = await writeNote(
        owner(),
        folderId: shelf.id,
        title: 'Top',
        body: 'Text on the shelf',
      );
      await event(owner(), 'e1');
      await owner().db.folderDao.setSharedPair(shelf.id, sharePairId);
      await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
      await pair.syncBoth();
    });

    test('a note over a shared note\'s id, with the very same text: the '
        'pull stores it as the person\'s own and goes on — it used to fail '
        'on that page at every run', () async {
      final mine = await partner().db.folderDao.createFolder(name: 'Mine');
      final note = pair.gateway.rowsOf(pair.ownerSpace, 'notes')[top.id]!;
      plantOwn(asOwn(note, over: {'folderId': mine.id}));
      plantOwnChunks();

      final report = await partner().sync();
      await partner().sync();

      expect(report.failure, isNull);
      final here = (await noteOn(partner(), top.id))!;
      expect(here.ownerId, partnerUid);
      expect(here.folderId, mine.id);
      expect(
        await partner().db.contentChunkDao.loadContent(top.id),
        'Text on the shelf',
      );
    });

    test('a note over a shared note\'s id that cannot land yet — its text '
        'is not in the person\'s own space — does not leave a hole: the '
        'screens are told the shared note went, and the same run reads it '
        'back', () async {
      // A later shared note, so the reader's cursor stands well past the
      // first: nothing but a read from the start comes back to it.
      pair.gateway.elapse(const Duration(minutes: 1));
      await writeNote(
        owner(),
        folderId: shelf.id,
        title: 'Later',
        body: 'Written a minute on',
      );
      await pair.syncBoth();
      pair.gateway.elapse(const Duration(minutes: 1));
      final mine = await partner().db.folderDao.createFolder(name: 'Mine');
      final note = pair.gateway.rowsOf(pair.ownerSpace, 'notes')[top.id]!;
      plantOwn(asOwn(note, over: {'folderId': mine.id}));
      partner().hooks.clear();

      final report = await partner().sync();

      expect(report.failure, isNull);
      final here = (await noteOn(partner(), top.id))!;
      expect(here.ownerId, ownerUid, reason: 'the shared note is back');
      expect(
        await partner().db.contentChunkDao.loadContent(top.id),
        'Text on the shelf',
      );
      final told = [
        for (final (table, rows) in partner().hooks.pages)
          for (final row in rows)
            if (table == 'notes' && row.rowKey == top.id)
              row.gone ? 'gone' : row.result.name,
      ];
      expect(told, ['gone', 'inserted']);
    });

    test('a note that names a folder held here as shared is held back — not '
        'stored under it, and not counted and passed over as it used to be: '
        'it lands once the folder of the person\'s own arrives and takes the '
        'shared one\'s place', () async {
      final note = pair.gateway.rowsOf(pair.ownerSpace, 'notes')[top.id]!;
      plantOwn(asOwn(note, rowKey: 'own-note', over: {'id': 'own-note'}));
      plantOwnChunks();
      Future<List<String>> heldBack() async => [
        for (final (key, _) in await partner().db.syncDao.valuesByPrefix(
          SyncDao.pullParkedPrefix,
        ))
          key,
      ];

      final report = await partner().sync();

      expect(report.failure, isNull);
      expect(await noteOn(partner(), 'own-note'), isNull);
      expect((await folderOn(partner(), shelf.id))!.ownerId, ownerUid);
      expect((await noteOn(partner(), top.id))!.ownerId, ownerUid);
      expect(await heldBack(), [contains('own-note')]);
      expect(
        [
          for (final (_, value) in await partner().db.syncDao.valuesByPrefix(
            SyncDao.pullParkedPrefix,
          ))
            value,
        ],
        [contains(SyncHeldReason.sharedParent.name)],
        reason: 'said as what it is, not as a document that cannot be read',
      );

      final folder = pair.gateway.rowsOf(pair.ownerSpace, 'folders')[shelf.id]!;
      plantOwn(asOwn(folder));
      await partner().sync();
      await partner().sync();

      expect((await folderOn(partner(), shelf.id))!.ownerId, partnerUid);
      final here = (await noteOn(partner(), 'own-note'))!;
      expect(here.ownerId, partnerUid);
      expect(
        await partner().db.contentChunkDao.loadContent('own-note'),
        'Text on the shelf',
      );
      expect(await heldBack(), isEmpty);
    });

    test('a skipped day on an event held here as shared is held back the '
        'same way, and the owner\'s day under that key stays until it '
        'lands', () async {
      await owner().db.eventSkipDao.markSkipped('e1', day);
      await pair.syncBoth();
      final skip = pair.gateway
          .rowsOf(pair.ownerSpace, 'calendar_event_skips')
          .values
          .single;
      plantOwn(asOwn(skip));
      Future<Set<String>> skipsOf(String uid) =>
          ownedBy(partner(), 'calendar_event_skips', uid, key: 'event_id');

      final report = await partner().sync();

      expect(report.failure, isNull);
      expect((await eventOn(partner(), 'e1'))!.ownerId, ownerUid);
      expect(await skipsOf(ownerUid), {'e1'});
      expect(await skipsOf(partnerUid), isEmpty);

      final theirs = pair.gateway.rowsOf(
        pair.ownerSpace,
        'calendar_events',
      )['e1']!;
      plantOwn(asOwn(theirs));
      await partner().sync();
      await partner().sync();

      expect((await eventOn(partner(), 'e1'))!.ownerId, partnerUid);
      expect(await skipsOf(partnerUid), {'e1'});
      expect(await skipsOf(ownerUid), isEmpty);
    });

    group('an event or a template in a category held here as shared', () {
      Future<List<String>> heldBack() async => [
        for (final (key, value) in await partner().db.syncDao.valuesByPrefix(
          SyncDao.pullParkedPrefix,
        ))
          '$key $value',
      ];

      Future<String?> categoryOf(String table, String id) async {
        final rows = await partner().db
            .customSelect(
              'SELECT category FROM $table WHERE id = ?',
              variables: [Variable<String>(id)],
            )
            .get();
        return rows.isEmpty ? null : rows.single.read<String>('category');
      }

      /// The owner shares the category `climb`, which the partner's device
      /// stores as theirs; the partner's own space then carries an event and
      /// a template of the partner's own under that category id — both
      /// accounts restored one backup.
      setUp(() async {
        await owner().db.calendarCategoryDao.insertCategory(
          CalendarCategoriesCompanion.insert(
            id: 'climb',
            name: 'Climb',
            colorValue: 0xFF336699,
            iconKey: 'event',
            createdAt: day,
            updatedAt: day,
          ),
        );
        await owner().db.eventTemplateDao.upsertTemplate(
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
        await owner().db.calendarCategoryDao.setSharedPair(
          'climb',
          sharePairId,
        );
        await pair.syncBoth();
        expect(
          (await partner().db.calendarCategoryDao.getByIdsIncludingDeleted([
            'climb',
          ])).single.ownerId,
          ownerUid,
        );
        final event = pair.gateway.rowsOf(
          pair.ownerSpace,
          'calendar_events',
        )['e1']!;
        plantOwn(
          asOwn(
            event,
            rowKey: 'own-e',
            over: {'id': 'own-e', 'category': 'climb'},
          ),
        );
        final template = pair.gateway.rowsOf(
          pair.ownerSpace,
          'calendar_event_templates',
        )['t1']!;
        plantOwn(asOwn(template, rowKey: 'own-t', over: {'id': 'own-t'}));
      });

      test('is held back — not stored, and not dropped by the fence while '
          'the pull counts it and passes it for good — and lands once the '
          'share ends', () async {
        final report = await partner().sync();

        expect(report.failure, isNull);
        expect(await categoryOf('calendar_events', 'own-e'), isNull);
        expect(await categoryOf('calendar_event_templates', 'own-t'), isNull);
        expect(
          await heldBack(),
          unorderedMatches([
            allOf(
              contains('own-e'),
              contains(SyncHeldReason.sharedParent.name),
            ),
            allOf(
              contains('own-t'),
              contains(SyncHeldReason.sharedParent.name),
            ),
          ]),
        );

        await owner().db.calendarCategoryDao.setSharedPair('climb', null);
        await owner().sync();
        await partner().sync();
        await partner().sync();

        expect(await categoryOf('calendar_events', 'own-e'), 'climb');
        expect(await categoryOf('calendar_event_templates', 'own-t'), 'climb');
        expect(await ownedBy(partner(), 'calendar_events', partnerUid), {
          'own-e',
        });
        expect(await heldBack(), isEmpty);
      });

      test('lands once the person\'s own category under that id arrives and '
          'takes the shared one\'s place', () async {
        await partner().sync();
        expect(await heldBack(), hasLength(2));

        final theirs = pair.gateway.rowsOf(
          pair.ownerSpace,
          'calendar_categories',
        )['climb']!;
        plantOwn(asOwn(theirs));
        await partner().sync();
        await partner().sync();

        expect(
          (await partner().db.calendarCategoryDao.getByIdsIncludingDeleted([
            'climb',
          ])).single.ownerId,
          partnerUid,
        );
        expect(await categoryOf('calendar_events', 'own-e'), 'climb');
        expect(await categoryOf('calendar_event_templates', 'own-t'), 'climb');
        expect(await heldBack(), isEmpty);
      });
    });

    test('tells the screens what gave way: each removed row as gone, with '
        'where it stood — and before the row of the person\'s own under '
        'the same key is announced, so "created" is the last word', () async {
      final folder = pair.gateway.rowsOf(pair.ownerSpace, 'folders')[shelf.id]!;
      plantOwn(asOwn(folder));
      partner().hooks.clear();

      await partner().sync();

      final gone = {
        for (final (table, rows) in partner().hooks.pages)
          for (final row in rows)
            if (row.gone) '$table/${row.rowKey}': row.previousParent,
      };
      expect(gone, {'folders/${shelf.id}': null, 'notes/${top.id}': shelf.id});
      expect(
        [
          for (final (table, rows) in partner().hooks.pages)
            for (final row in rows)
              if (table == 'folders' && row.rowKey == shelf.id)
                row.gone ? 'gone' : row.result.name,
        ],
        ['gone', 'inserted'],
      );
      expect((await folderOn(partner(), shelf.id))!.ownerId, partnerUid);
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

  test('a backup holds what is the person\'s own: a shared event, its '
      'skipped day and its day\'s text are in none of the three export '
      'lists, and the person\'s own are', () async {
    addTearDown(() {
      CalendarEventService.reset();
      EventSkipService.reset();
      EventOccurrenceService.reset();
    });
    for (final (device, id) in [(owner(), 'e1'), (partner(), 'own')]) {
      await event(device, id);
      await device.db.eventSkipDao.markSkipped(id, day);
      await device.db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: id,
          day: day,
          description: 'Text of $id',
          createdAt: day,
          updatedAt: day,
        ),
      );
    }
    await owner().db.calendarEventDao.setSharedPair('e1', sharePairId);
    await pair.syncBoth();
    expect(await eventOn(partner(), 'e1'), isNotNull);
    final db = partner().db;

    final events = await (await CalendarEventService.forTesting(
      db,
    )).exportData();
    final skips = await (await EventSkipService.forTesting(db)).exportData();
    final texts = await (await EventOccurrenceService.forTesting(
      db,
    )).exportData();

    expect([for (final row in events) row['id']], ['own']);
    expect([for (final row in skips) row['eventId']], ['own']);
    expect([for (final row in texts) row['eventId']], ['own']);
    expect(events.single.containsKey('sharedPair'), isFalse);
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
        pair.gateway
            .rowsOf(pair.partnerSpace, 'calendar_events')['old']!
            .ownerId,
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

      await partner().db.sharedRowDao.begin(
        owner: ownerUid,
        pair: sharePairId,
        boundUid: partnerUid,
      );
      expect(
        [
          for (final entry in await partner().db.syncOutboxDao.pending())
            (entry.rowKey, entry.republish),
        ],
        [('old', false)],
        reason: 'the space never held it: a write, not a re-send',
      );

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

  group('what a read changed, for the person (share surfaces §6.14)', () {
    Future<void> category(String id, {bool builtIn = false}) =>
        owner().db.calendarCategoryDao.insertCategory(
          CalendarCategoriesCompanion.insert(
            id: id,
            name: 'Category $id',
            colorValue: 0xFF336699,
            iconKey: 'event',
            isBuiltIn: Value(builtIn),
            createdAt: day,
            updatedAt: day,
          ),
        );

    Future<void> eventIn(String id, String category) =>
        owner().db.calendarEventDao.upsert(
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

    Future<void> shareEvent(String id) =>
        owner().db.calendarEventDao.setSharedPair(id, sharePairId);

    Future<void> shareCategory(String id) =>
        owner().db.calendarCategoryDao.setSharedPair(id, sharePairId);

    /// What the partner's reads reported since the last [syncBoth].
    Future<List<SharedReadChanges>> syncBoth() async {
      partner().hooks.clear();
      await pair.syncBoth();
      return List.of(partner().hooks.shared);
    }

    /// The one read of the built-ins shared before a page that carries one.
    bool readsBuiltIns(CapturedStatement statement) =>
        statement.isSelect &&
        statement.args.length == 2 &&
        statement.args.first == SyncDao.sharedBuiltInPrefix;

    /// A read of every shared table from the start, as the daily one is.
    Future<List<SharedReadChanges>> readFromStart() async {
      final later = DateTime.now().add(SyncEngine.fullPullInterval);
      partner().now = () => later;
      return syncBoth();
    }

    test('a category arrives with its events: both reported, once, in the '
        'run\'s one afterRun of the read', () async {
      await category('climb');
      await eventIn('e1', 'climb');
      await shareCategory('climb');

      expect(await syncBoth(), [
        const SharedReadChanges(
          categoryIds: ['climb'],
          events: [(id: 'e1', title: 'Event e1', category: 'climb')],
        ),
      ]);
    });

    test('an event shared on its own reports its stored category', () async {
      await eventIn('e1', 'general');
      await shareEvent('e1');

      expect(await syncBoth(), [
        const SharedReadChanges(
          events: [(id: 'e1', title: 'Event e1', category: 'general')],
        ),
      ]);
    });

    test('an update of a held row arrives as nothing, and so does a read from '
        'the start that meets what is here', () async {
      await category('climb');
      await eventIn('e1', 'climb');
      await shareCategory('climb');
      await syncBoth();

      await owner().db.calendarEventDao.upsert(
        CalendarEventsCompanion(
          id: const Value('e1'),
          title: const Value('Renamed'),
          updatedAt: Value(day),
        ),
      );
      await owner().db.calendarCategoryDao.updateCategory(
        const CalendarCategoriesCompanion(
          id: Value('climb'),
          name: Value('Bouldering'),
        ),
      );
      expect(await syncBoth(), isEmpty);
      expect((await eventOn(partner(), 'e1'))!.title, 'Renamed');

      expect(await readFromStart(), isEmpty);
    });

    test('a built-in newly shared is a category received — by its id, with '
        'no row stored — once: a read from the start does not repeat it, '
        'and it is told though it touches no cache', () async {
      await category('gym', builtIn: true);
      await shareCategory('gym');

      partner().statements.reset();
      expect(await syncBoth(), [
        const SharedReadChanges(categoryIds: ['gym']),
      ]);
      expect(partner().statements.captured.where(readsBuiltIns), hasLength(1));

      partner().statements.reset();
      expect(await readFromStart(), isEmpty);
      expect(
        partner().statements.captured.where(readsBuiltIns),
        hasLength(1),
        reason: 'one page of categories carries it again',
      );
    });

    test('an event that leaves is reported with the title it had: made '
        'private, or deleted by its owner', () async {
      await eventIn('e1', 'general');
      await eventIn('e2', 'general');
      await shareEvent('e1');
      await shareEvent('e2');
      await syncBoth();

      await owner().db.calendarEventDao.setSharedPair('e1', null);
      expect(await syncBoth(), [
        const SharedReadChanges(left: [(id: 'e1', title: 'Event e1')]),
      ]);

      await owner().db.calendarEventDao.tombstoneEventCascade('e2');
      expect(await syncBoth(), [
        const SharedReadChanges(left: [(id: 'e2', title: 'Event e2')]),
      ]);
      expect((await eventOn(partner(), 'e2'))!.isDeleted, isTrue);

      expect(
        await readFromStart(),
        isEmpty,
        reason: 'a tombstone held here is met again, and left long ago',
      );
    });

    test('the events of a category made private leave with it', () async {
      await category('climb');
      await eventIn('e1', 'climb');
      await shareCategory('climb');
      await syncBoth();

      await owner().db.calendarCategoryDao.setSharedPair('climb', null);

      expect(await syncBoth(), [
        const SharedReadChanges(left: [(id: 'e1', title: 'Event e1')]),
      ]);
    });

    test('the pair ended, everything shared is forgotten: each live event '
        'reported as left', () async {
      await eventIn('e1', 'general');
      await eventIn('e2', 'general');
      await shareEvent('e1');
      await shareEvent('e2');
      await syncBoth();
      await owner().db.calendarEventDao.tombstoneEventCascade('e2');
      await syncBoth();

      pair.end();

      expect(await syncBoth(), [
        const SharedReadChanges(left: [(id: 'e1', title: 'Event e1')]),
      ]);
    });

    test('paired again with the same partner: an event shared again in the '
        'read that forgot the old pair has arrived, not left; one not '
        'shared again has left', () async {
      await eventIn('e1', 'general');
      await eventIn('e2', 'general');
      await shareEvent('e1');
      await shareEvent('e2');
      await syncBoth();

      pair.end();
      pair.join(pairId: 'pair-2');
      // The owner's own read clears its marks of the old pair first.
      await owner().sync();
      await owner().db.calendarEventDao.setSharedPair('e1', 'pair-2');

      expect(await syncBoth(), [
        const SharedReadChanges(
          events: [(id: 'e1', title: 'Event e1', category: 'general')],
          left: [(id: 'e2', title: 'Event e2')],
        ),
      ]);
      expect((await eventOn(partner(), 'e1'))!.isDeleted, isFalse);
    });

    test('paired again with the same partner: a category shared again has '
        'arrived with its events, none of them left', () async {
      await category('climb');
      await eventIn('e1', 'climb');
      await shareCategory('climb');
      await syncBoth();

      pair.end();
      pair.join(pairId: 'pair-2');
      await owner().sync();
      await owner().db.calendarCategoryDao.setSharedPair('climb', 'pair-2');

      expect(await syncBoth(), [
        const SharedReadChanges(
          categoryIds: ['climb'],
          events: [(id: 'e1', title: 'Event e1', category: 'climb')],
        ),
      ]);
    });

    test('under the same pair, an event a read saw deleted and then stored '
        'again from the start has neither left nor arrived', () async {
      await eventIn('e1', 'general');
      await eventIn('e2', 'general');
      await shareEvent('e1');
      await shareEvent('e2');
      await syncBoth();

      // The read meets e1's tombstone from its cursor; e2 made private makes
      // the server count fewer, so it reads again from the start — by when
      // the owner has put e1 back.
      await owner().db.calendarEventDao.tombstoneEventCascade('e1');
      await owner().db.calendarEventDao.setSharedPair('e2', null);
      await owner().sync();
      var restored = false;
      pair.gateway.onSharedPage = (table) async {
        if (table != 'calendar_events' || restored) return;
        restored = true;
        await owner().db.calendarEventDao.upsert(
          CalendarEventsCompanion(id: const Value('e1'), updatedAt: Value(day)),
        );
        await owner().sync();
      };
      partner().hooks.clear();
      await partner().sync();

      expect(restored, isTrue);
      expect(partner().hooks.shared, [
        const SharedReadChanges(left: [(id: 'e2', title: 'Event e2')]),
      ]);
      expect((await eventOn(partner(), 'e1'))!.isDeleted, isFalse);
    });

    test('costs: a read with nothing new reads no title and no built-in; a '
        'page that carries a tombstone reads the titles once', () async {
      bool readsTitles(CapturedStatement statement) =>
          statement.sql.contains('is_deleted = 0 AND id IN');
      await eventIn('e1', 'general');
      await eventIn('e2', 'general');
      await shareEvent('e1');
      await shareEvent('e2');
      await syncBoth();

      partner().statements.reset();
      await syncBoth();
      expect(partner().statements.captured.where(readsTitles), isEmpty);
      expect(partner().statements.captured.where(readsBuiltIns), isEmpty);
      expect(await syncBoth(), isEmpty);

      await owner().db.calendarEventDao.tombstoneEventCascade('e2');
      await owner().sync();
      partner().statements.reset();
      await partner().sync();
      expect(partner().statements.captured.where(readsTitles), hasLength(1));

      partner().statements.reset();
      await readFromStart();
      expect(
        partner().statements.captured.where(readsTitles),
        hasLength(1),
        reason: 'one page of events, whatever it holds',
      );
    });
  });
}
