import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/push/push_relay.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../support/fake_push.dart';
import 'support/sync_pair.dart';

/// The sender's trigger (`docs/cloud-shared-freshness.md` §7): a run whose
/// drain ended well pokes the partner's phone in each pair a poke is owed
/// to — owed by a write that changed a grant, or by a push that landed a
/// granted row. Urgent means it can ring: the calendar's shared rows; a
/// folder or a note is normal. A database that shares nothing owes nothing
/// and pokes nothing.
void main() {
  late FakePushRelay relay;
  final day = DateTime.utc(2026, 6, 1);

  setUp(() {
    relay = FakePushRelay(address: Uri.parse('https://relay.test'));
    GetIt.I.registerSingleton<PushRelay>(relay);
  });

  tearDown(() => GetIt.I.reset());

  Future<String?> owedIn(AppDatabase db, [String pairId = sharePairId]) =>
      db.syncDao.getValue(SyncDao.keySharePokeOwed(pairId));

  Future<void> eventIn(AppDatabase db, String id, {String category = 'general'}) =>
      db.calendarEventDao.upsert(
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

  Future<void> categoryIn(AppDatabase db, String id) =>
      db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: id,
          name: 'Category $id',
          colorValue: 0xFF336699,
          iconKey: 'event',
          createdAt: day,
          updatedAt: day,
        ),
      );

  group('the poke after a run', () {
    late SharePair pair;
    setUp(() async => pair = await SharePair.open());
    tearDown(() => pair.close());

    AppDatabase db() => pair.owner.db;

    Future<void> settle() async {
      await pair.owner.sync();
      await pair.owner.sync();
      relay.pokes.clear();
    }

    test('a private row: nothing owed, no poke', () async {
      await eventIn(db(), 'e1');
      final folder = await db().folderDao.createFolder(name: 'Mine');
      await writeNote(pair.owner, folderId: folder.id, title: 'Log', body: 'R');
      await pair.owner.sync();

      expect(relay.pokes, isEmpty);
      expect(await db().syncDao.valuesByPrefix(SyncDao.sharePokeOwedPrefix),
          isEmpty);
    });

    test('sharing an event owes an urgent poke for its pair in its own '
        'write, and the run that sends it pokes once and clears it', () async {
      await eventIn(db(), 'e1');
      await settle();
      await db().calendarEventDao.setSharedPair('e1', sharePairId);
      expect(await owedIn(db()), 'urgent', reason: 'stored before any run');

      await pair.owner.sync();

      expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
      expect(await owedIn(db()), isNull);
    });

    test('an ordinary edit of a shared event pokes urgent; of a shared note, '
        'normal', () async {
      await eventIn(db(), 'e1');
      final folder = await db().folderDao.createFolder(name: 'Shared');
      final note = await writeNote(
        pair.owner,
        folderId: folder.id,
        title: 'Log',
        body: 'Row',
      );
      await db().calendarEventDao.setSharedPair('e1', sharePairId);
      await db().folderDao.setSharedPair(folder.id, sharePairId);
      await settle();

      await db().calendarEventDao.upsert(
        const CalendarEventsCompanion(id: Value('e1'), title: Value('Night')),
      );
      expect(await owedIn(db()), isNull, reason: 'an ordinary save owes none');
      await pair.owner.sync();
      expect(relay.pokes, [(pair: sharePairId, urgent: true)]);

      relay.pokes.clear();
      await editNote(pair.owner, note.id, 'New line');
      await pair.owner.sync();
      expect(relay.pokes, [(pair: sharePairId, urgent: false)]);
    });

    test('deleted shared rows send tombstones that carry the grant: an '
        'event, a folder and a note', () async {
      await eventIn(db(), 'e1');
      final folder = await db().folderDao.createFolder(name: 'Shared');
      final note = await writeNote(
        pair.owner,
        folderId: folder.id,
        title: 'Log',
        body: 'Row',
      );
      await db().calendarEventDao.setSharedPair('e1', sharePairId);
      await db().folderDao.setSharedPair(folder.id, sharePairId);
      await settle();

      await db().noteDao.softDeleteNoteWithChunks(note.id);
      expect(await owedIn(db()), isNull);
      await pair.owner.sync();
      expect(relay.pokes, [(pair: sharePairId, urgent: false)]);

      relay.pokes.clear();
      await db().folderDao.softDeleteFolder(folder.id);
      await pair.owner.sync();
      expect(relay.pokes, [(pair: sharePairId, urgent: false)]);

      relay.pokes.clear();
      await db().calendarEventDao.softDeleteById('e1');
      await pair.owner.sync();
      expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
    });

    test('a run that fails pokes nothing; the poke stays owed', () async {
      await eventIn(db(), 'e1');
      await db().calendarEventDao.setSharedPair('e1', sharePairId);
      pair.gateway.failNextWith(SyncGatewayFailure.offline, times: 10);
      await pair.owner.sync();

      expect(relay.pokes, isEmpty);
      expect(await owedIn(db()), 'urgent');
    });

    test('no relay known: what is owed is not even read', () async {
      relay.address = null;
      await eventIn(db(), 'e1');
      await db().calendarEventDao.setSharedPair('e1', sharePairId);
      await pair.owner.sync();

      expect(await owedIn(db()), 'urgent');
    });
  });

  test('a database the shared read never found paired asks nothing of what '
      'is owed', () async {
    final pair = await SyncPair.open();
    addTearDown(pair.close);
    await pair.a.db.syncDao.oweSharePoke(pairId: 'p', urgent: true);
    await pair.a.sync();

    expect(relay.pokes, isEmpty);
    expect(await owedIn(pair.a.db, 'p'), 'urgent');
  });

  group('every write that changes a grant owes, for its pair', () {
    late SyncPair pair;
    setUp(() async => pair = await SyncPair.open());
    tearDown(() => pair.close());

    AppDatabase db() => pair.a.db;
    Future<void> clear() =>
        db().syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);

    test('a category shared, an event moved out of it, its events moved, '
        'and the category deleted: urgent', () async {
      await categoryIn(db(), 'climb');
      await categoryIn(db(), 'work');
      await db().calendarCategoryDao.setSharedPair('climb', sharePairId);
      expect(await owedIn(db()), 'urgent');
      await clear();

      await eventIn(db(), 'e1', category: 'climb');
      expect(await owedIn(db()), isNull, reason: 'a new event is its own write');
      await db().calendarEventDao.upsert(
        const CalendarEventsCompanion(id: Value('e1'), category: Value('work')),
      );
      expect(await owedIn(db()), 'urgent');
      await clear();

      await db().calendarEventDao.reassignCategory('work', 'climb');
      expect(await owedIn(db()), 'urgent');
      await clear();

      await db().calendarCategoryDao.tombstoneCascade(
        'climb',
        reassignTo: 'work',
      );
      expect(await owedIn(db()), 'urgent');
    });

    test('a folder shared and un-shared, and moved across a shared boundary: '
        'normal', () async {
      final shared = await db().folderDao.createFolder(name: 'Shared');
      final mine = await db().folderDao.createFolder(name: 'Mine');
      await db().folderDao.setSharedPair(shared.id, sharePairId);
      expect(await owedIn(db()), 'normal');
      await clear();

      await db().folderDao.moveFolder(id: mine.id, targetParentId: shared.id);
      expect(await owedIn(db()), 'normal');
      await clear();
      await db().folderDao.moveFolder(id: mine.id, targetParentId: null);
      expect(await owedIn(db()), 'normal');
      await clear();

      await db().folderDao.setSharedPair(shared.id, null);
      expect(await owedIn(db()), 'normal');
    });

    // A note's move owes from the service, off the share census
    // (`note_share_flags_test.dart`).

    test('a mark my other device changed owes on this one when it merges '
        'and re-queues', () async {
      await categoryIn(db(), 'climb');
      await eventIn(db(), 'e1', category: 'climb');
      final folder = await db().folderDao.createFolder(name: 'F');
      await pair.a.sync();
      await pair.b.sync();

      await db().calendarCategoryDao.setSharedPair('climb', sharePairId);
      await pair.a.sync();
      await pair.b.sync();
      expect(await owedIn(pair.b.db), 'urgent', reason: 'the category merge');
      await pair.b.db.syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);

      await db().calendarEventDao.setSharedPair('e1', 'pair-2');
      await pair.a.sync();
      await pair.b.sync();
      expect(await owedIn(pair.b.db, 'pair-2'), 'urgent',
          reason: 'the event merge');
      await pair.b.db.syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);

      await db().folderDao.setSharedPair(folder.id, sharePairId);
      await pair.a.sync();
      await pair.b.sync();
      expect(await owedIn(pair.b.db), 'normal', reason: 'the folder merge');
    });

    test('an urgent poke owed is never lowered by a normal one, and each '
        'pair keeps its own', () async {
      await db().syncDao.oweSharePoke(pairId: 'p1', urgent: true);
      await db().syncDao.oweSharePoke(pairId: 'p1', urgent: false);
      await db().syncDao.oweSharePoke(pairId: 'p2', urgent: false);
      expect(await owedIn(db(), 'p1'), 'urgent');
      expect(await owedIn(db(), 'p2'), 'normal');
    });
  });
}
