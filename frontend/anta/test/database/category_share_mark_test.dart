import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/tables/calendar_categories_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_skips_binding.dart';
import 'package:anta/services/sync/tables/calendar_events_binding.dart';

import 'support/db_test_support.dart';

/// A category as a third root of a grant (`docs/cloud-share-surfaces-roadmap.md`
/// §7): its mark, written by one call, shares every event in it that has no
/// mark of its own — and their skipped days and per-day texts — so whatever
/// changes what a category grants, or which category an event takes its
/// grant from, has to queue those rows again, or their documents would go on
/// saying who may read them as of the push before.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  final day = DateTime.utc(2026, 6, 1);

  /// What the queue holds, as `table/key` — emptied by [settle] so a test
  /// reads only what its act queued.
  Future<Set<String>> queued() async => {
    for (final entry in await db.syncOutboxDao.pending())
      '${entry.syncedTable}/${entry.rowKey}',
  };

  /// The queue as `table/key` → whether the entry only re-sends a version
  /// the space holds.
  Future<Map<String, bool>> republished() async => {
    for (final entry in await db.syncOutboxDao.pending())
      '${entry.syncedTable}/${entry.rowKey}': entry.republish,
  };

  Future<void> settle() => db.syncOutboxDao.clear();

  Future<void> category(String id, {bool builtIn = false}) =>
      db.calendarCategoryDao.insertCategory(
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

  CalendarEventsCompanion eventEntry(String id, String category) =>
      CalendarEventsCompanion.insert(
        id: id,
        title: 'Event $id',
        category: category,
        startDate: day,
        ruleKind: 'weekly',
        createdAt: day,
        updatedAt: day,
      );

  Future<void> event(String id, String category) =>
      db.calendarEventDao.upsert(eventEntry(id, category));

  /// A skipped day and a per-day text for [eventId], and a presence mark,
  /// which is never shared.
  Future<void> dayRows(String eventId) async {
    await db.eventSkipDao.markSkipped(eventId, day);
    await db.eventOccurrenceDao.upsert(
      EventOccurrenceDescriptionsCompanion.insert(
        eventId: eventId,
        day: day,
        description: 'Bring the keys',
        createdAt: day,
        updatedAt: day,
      ),
    );
    await db.eventAbsenceDao.setStatus(eventId, day, PresenceStatus.missed);
  }

  Future<CalendarCategoryRow> categoryRow(String id) async =>
      (await db.calendarCategoryDao.getByIdsIncludingDeleted([id])).single;

  Future<CalendarEventRow> eventRow(String id) async =>
      (await db.calendarEventDao.getByIdsIncludingDeleted([id])).single;

  String skipKey(String eventId) =>
      'calendar_event_skips/${dayRowKey(eventId, day)}';
  String textKey(String eventId) =>
      'calendar_event_occurrences/${dayRowKey(eventId, day)}';

  /// The event [eventId] and the day rows a grant follows to.
  Set<String> granted(String eventId) => {
    'calendar_events/$eventId',
    skipKey(eventId),
    textKey(eventId),
  };

  group('a category\'s mark', () {
    test('is one stamped write: queued, a version on, updated_at left '
        'alone, and every event that takes its grant from it queued again '
        'with its day rows — a deleted one too — as re-sends', () async {
      await category('c1');
      await category('c2');
      await event('inherits', 'c1');
      await dayRows('inherits');
      await event('deleted', 'c1');
      await dayRows('deleted');
      await db.calendarEventDao.softDeleteById('deleted');
      await event('own', 'c1');
      await dayRows('own');
      await db.calendarEventDao.setSharedPair('own', 'pair-1');
      await event('elsewhere', 'c2');
      await dayRows('elsewhere');
      final before = await categoryRow('c1');
      await settle();

      expect(await db.calendarCategoryDao.setSharedPair('c1', 'pair-1'), isTrue);

      final after = await categoryRow('c1');
      expect(after.sharedPair, 'pair-1');
      expect(after.sharedStamp, after.hlcTimestamp);
      expect(after.version, before.version + 1);
      expect(after.hlcTimestamp.compareTo(before.hlcTimestamp), greaterThan(0));
      expect(after.updatedAt, before.updatedAt);
      expect(after.name, before.name);
      expect(await republished(), {
        'calendar_categories/c1': false,
        for (final key in {...granted('inherits'), ...granted('deleted')})
          key: true,
      });
    });

    test('taken away again is the same write, and queues the same rows',
        () async {
      await category('c1');
      await event('e1', 'c1');
      await dayRows('e1');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      final marked = await categoryRow('c1');
      await settle();

      expect(await db.calendarCategoryDao.setSharedPair('c1', null), isTrue);

      final after = await categoryRow('c1');
      expect(after.sharedPair, isNull);
      expect(after.sharedStamp, after.hlcTimestamp);
      expect(after.version, marked.version + 1);
      expect(await queued(), {'calendar_categories/c1', ...granted('e1')});
    });

    test('a mark it already carries, a missing category, a deleted one and '
        'another account\'s write nothing', () async {
      await category('c1');
      await category('gone');
      await category('theirs');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      await db.calendarCategoryDao.softDeleteById('gone');
      await db.customStatement(
        "UPDATE calendar_categories SET owner_id = 'partner' WHERE id = ?",
        ['theirs'],
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      final marked = await categoryRow('c1');
      await settle();

      final dao = db.calendarCategoryDao;
      expect(await dao.setSharedPair('c1', 'pair-1'), isFalse);
      expect(await dao.setSharedPair('none', 'pair-1'), isFalse);
      expect(await dao.setSharedPair('gone', 'pair-1'), isFalse);
      expect(await dao.setSharedPair('theirs', 'pair-1'), isFalse);

      expect(await queued(), isEmpty);
      expect((await categoryRow('c1')).version, marked.version);
      expect((await categoryRow('gone')).sharedPair, isNull);
      expect((await categoryRow('theirs')).sharedPair, isNull);
    });

    test('a built-in is marked like any other, under its fixed id', () async {
      await category('gym', builtIn: true);

      expect(
        await db.calendarCategoryDao.setSharedPair('gym', 'pair-1'),
        isTrue,
      );
      expect((await categoryRow('gym')).sharedPair, 'pair-1');
    });

    test('a mark for one pair clears every mark of another — on categories, '
        'events and folders alike, under the one stamp — and queues what '
        'those shared', () async {
      await category('old');
      await category('new');
      await event('inOld', 'old');
      await dayRows('inOld');
      await event('ownOld', 'new');
      await db.eventSkipDao.markSkipped('ownOld', day);
      final shelf = (await db.folderDao.createFolder(name: 'Shelf')).id;
      final inside = (await db.noteDao.createNote(
        folderId: shelf,
        title: 'Inside',
      )).id;
      await db.calendarCategoryDao.setSharedPair('old', 'pair-old');
      await db.calendarEventDao.setSharedPair('ownOld', 'pair-old');
      await db.folderDao.setSharedPair(shelf, 'pair-old');
      await settle();

      await db.calendarCategoryDao.setSharedPair('new', 'pair-new');

      final stamp = (await categoryRow('new')).sharedStamp;
      expect((await categoryRow('old')).sharedPair, isNull);
      expect((await categoryRow('old')).sharedStamp, stamp);
      expect((await eventRow('ownOld')).sharedPair, isNull);
      expect((await eventRow('ownOld')).sharedStamp, stamp);
      expect(
        (await db.folderDao.getByIdsIncludingDeleted([shelf])).single
            .sharedPair,
        isNull,
      );
      expect(await queued(), {
        'calendar_categories/new',
        'calendar_categories/old',
        ...granted('inOld'),
        // Its own mark gone, it is shared as its category now is.
        'calendar_events/ownOld',
        skipKey('ownOld'),
        'folders/$shelf',
        'notes/$inside',
      });
    });

    test('an event\'s mark and a folder\'s for another pair clear a '
        'category\'s too', () async {
      await category('c1');
      await event('inC1', 'c1');
      await event('other', 'c1');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-old');
      await settle();

      await db.calendarEventDao.setSharedPair('other', 'pair-new');
      expect((await categoryRow('c1')).sharedPair, isNull);
      expect(await queued(), contains('calendar_events/inC1'));

      await db.calendarCategoryDao.setSharedPair('c1', 'pair-old');
      final shelf = (await db.folderDao.createFolder(name: 'Shelf')).id;
      await db.folderDao.setSharedPair(shelf, 'pair-new');
      expect((await categoryRow('c1')).sharedPair, isNull);
    });

    test('the look at the account\'s pair clears a category of another '
        'pair with the events and folders, and leaves the pair that '
        'stands', () async {
      await category('c1');
      await category('dead');
      await event('e1', 'c1');
      await event('inDead', 'dead');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      await db.calendarCategoryDao.setSharedPair('dead', 'pair-1');
      await db.calendarCategoryDao.softDeleteById('dead');
      await settle();

      expect(await db.folderDao.clearSharesExcept('pair-1'), 0);
      expect(await queued(), isEmpty);

      expect(await db.folderDao.clearSharesExcept('pair-2'), 2);
      expect((await categoryRow('c1')).sharedPair, isNull);
      expect((await categoryRow('dead')).sharedPair, isNull);
      expect(await queued(), {
        'calendar_categories/c1',
        'calendar_categories/dead',
        'calendar_events/e1',
        // A deleted category granted nothing, so its events' documents say
        // the same as before.
      });
    });

    test('is metadata to an edit: renaming a shared category keeps the mark '
        'and queues only the category', () async {
      await category('c1');
      await event('e1', 'c1');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      await settle();

      await db.calendarCategoryDao.updateCategory(
        const CalendarCategoriesCompanion(
          id: Value('c1'),
          name: Value('Renamed'),
        ),
      );

      expect((await categoryRow('c1')).sharedPair, 'pair-1');
      expect(await queued(), {'calendar_categories/c1'});
    });
  });

  group('what an event is shared into', () {
    test('its own mark, else its live category\'s; under neither, '
        'nothing', () async {
      await category('shared');
      await category('private');
      await event('inherits', 'shared');
      await event('private', 'private');
      await event('own', 'private');
      await event('ownOver', 'shared');
      await event('deleted', 'shared');
      await event('orphan', 'missing');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
      await db.calendarEventDao.setSharedPair('own', 'pair-1');
      await db.calendarEventDao.softDeleteById('deleted');
      // Set directly: two pairs at once is what a merge can leave, and it
      // shows whose mark is read.
      await db.customStatement(
        "UPDATE calendar_events SET shared_pair = 'pair-2' WHERE id = ?",
        ['ownOver'],
      );
      final ids = ['inherits', 'private', 'own', 'ownOver', 'deleted', 'orphan'];

      final expected = {
        'inherits': 'pair-1',
        'own': 'pair-1',
        'ownOver': 'pair-2',
        'deleted': 'pair-1',
      };
      expect(await db.calendarEventDao.sharedPairsOf([...ids, 'x']), expected);
      expect(
        await const CalendarEventsBinding().sharedPairs(
          db,
          await db.calendarEventDao.getByIdsIncludingDeleted(ids),
        ),
        expected,
      );
    });

    test('a day row as its event, by the same rule', () async {
      await category('shared');
      await event('e1', 'shared');
      await event('e2', 'shared');
      await db.eventSkipDao.markSkipped('e1', day);
      await db.eventSkipDao.markSkipped('e2', day);
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
      // Set directly: the writer would clear the category's other pair.
      await db.customStatement(
        "UPDATE calendar_events SET shared_pair = 'pair-2' WHERE id = 'e2'",
      );

      const binding = CalendarEventSkipsBinding();
      final rows = await binding.loadByKeys(db, [
        dayRowKey('e1', day),
        dayRowKey('e2', day),
      ]);
      expect(await binding.sharedPairs(db, rows), {
        dayRowKey('e1', day): 'pair-1',
        dayRowKey('e2', day): 'pair-2',
      });
    });

    test('a deleted category grants nothing, and neither does a missing '
        'one; the category\'s own document keeps its mark', () async {
      await category('shared');
      await event('e1', 'shared');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
      await db.customStatement(
        'UPDATE calendar_categories SET is_deleted = 1 WHERE id = ?',
        ['shared'],
      );

      expect(await db.calendarEventDao.sharedPairsOf(['e1']), isEmpty);
      expect(
        await const CalendarCategoriesBinding().sharedPairs(db, [
          await categoryRow('shared'),
        ]),
        {'shared': 'pair-1'},
      );

      await db.customStatement('DELETE FROM calendar_categories');
      expect(await db.calendarEventDao.sharedPairsOf(['e1']), isEmpty);
    });

    test('a category\'s mark never reaches an event another account shares '
        'with this one', () async {
      await category('shared');
      await event('theirs', 'shared');
      await event('mine', 'shared');
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = 'partner' WHERE id = ?",
        ['theirs'],
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');

      expect(await db.calendarEventDao.sharedPairsOf(['theirs', 'mine']), {
        'mine': 'pair-1',
      });
    });

    test('decided by the newer of the event\'s own stamp and its '
        'category\'s mark\'s', () async {
      await category('shared');
      await event('inherits', 'shared');
      await event('own', 'shared');
      await db.calendarEventDao.setSharedPair('own', 'pair-1');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
      final mark = (await categoryRow('shared')).sharedStamp!;

      expect(await db.calendarEventDao.stampsOf(['inherits', 'own']), {
        'inherits': mark,
        // Its own mark decides; the category's is not read.
        'own': (await eventRow('own')).hlcTimestamp,
      });

      await db.calendarEventDao.upsert(
        eventEntry('inherits', 'shared').copyWith(title: const Value('Edit')),
      );
      expect(await db.calendarEventDao.stampsOf(['inherits']), {
        'inherits': (await eventRow('inherits')).hlcTimestamp,
      });
    });

    test('read for many events in one statement, which reaches each '
        'category by its key', () async {
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);
      for (var i = 0; i < 30; i++) {
        await counted.calendarEventDao.upsert(eventEntry('e$i', 'c1'));
      }
      counter.reset();

      await counted.calendarEventDao.sharedPairsOf([
        for (var i = 0; i < 30; i++) 'e$i',
      ]);

      expect(counter.count, 1);
      final plan = await explainCaptured(counted, counter.captured.single);
      expect(
        plan.where((line) => line.contains('SCAN c')),
        isEmpty,
        reason: '$plan',
      );
    });
  });

  group('an event that changes category', () {
    setUp(() async {
      await category('shared');
      await category('private');
      await category('alsoPrivate');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
    });

    test('by a save, out of a shared category, queues its day rows; between '
        'two that share alike, only itself', () async {
      await event('e1', 'shared');
      await dayRows('e1');
      await settle();

      await db.calendarEventDao.upsert(eventEntry('e1', 'private'));
      expect(await queued(), granted('e1'));
      expect(await republished(), {
        'calendar_events/e1': false,
        skipKey('e1'): true,
        textKey('e1'): true,
      });
      await settle();

      await db.calendarEventDao.upsert(eventEntry('e1', 'alsoPrivate'));
      expect(await queued(), {'calendar_events/e1'});
      await settle();

      await db.calendarEventDao.upsert(eventEntry('e1', 'shared'));
      expect(await queued(), granted('e1'));
    });

    test('by a save, with a mark of its own, queues only itself', () async {
      await event('e1', 'shared');
      await dayRows('e1');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      await settle();

      await db.calendarEventDao.upsert(eventEntry('e1', 'private'));

      expect(await queued(), {'calendar_events/e1'});
    });

    test('by a reassignment, queues every event it moved and, when the two '
        'categories grant differently, their day rows', () async {
      await event('e1', 'shared');
      await event('e2', 'shared');
      await event('own', 'shared');
      await dayRows('e1');
      await dayRows('own');
      await db.calendarEventDao.setSharedPair('own', 'pair-1');
      await settle();

      expect(
        await db.calendarEventDao.reassignCategory('shared', 'private'),
        3,
      );

      expect(await queued(), {
        ...granted('e1'),
        'calendar_events/e2',
        'calendar_events/own',
      });
      await settle();

      await db.calendarEventDao.reassignCategory('private', 'alsoPrivate');
      expect(await queued(), {
        'calendar_events/e1',
        'calendar_events/e2',
        'calendar_events/own',
      });
    });

    test('when its shared category is deleted: the live ones move and say '
        'their new grant, and a deleted one left in it says it too',
        () async {
      await event('live', 'shared');
      await event('gone', 'shared');
      await dayRows('live');
      await dayRows('gone');
      await db.calendarEventDao.softDeleteById('gone');
      await settle();

      expect(
        await db.calendarCategoryDao.tombstoneCascade(
          'shared',
          reassignTo: 'private',
        ),
        isTrue,
      );

      expect((await eventRow('live')).category, 'private');
      expect(await db.calendarEventDao.sharedPairsOf(['live', 'gone']), isEmpty);
      expect(
        await queued(),
        containsAll({
          'calendar_categories/shared',
          ...granted('live'),
          ...granted('gone'),
        }),
      );
    });

    test('by a restore of the events, queues the day rows of every one it '
        'imported', () async {
      await event('e1', 'shared');
      await dayRows('e1');
      await settle();

      await db.calendarEventDao.deleteAll();
      await db.calendarEventDao.importAll([eventEntry('e1', 'private')]);

      expect(await queued(), granted('e1'));
    });
  });

  group('a category', () {
    test('wiped by a restore says its events again first: no mark is '
        'restored with it', () async {
      await category('shared');
      await category('private');
      await event('e1', 'shared');
      await event('e2', 'private');
      await dayRows('e1');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
      await settle();

      await db.calendarCategoryDao.deleteAll();

      expect(await queued(), granted('e1'));
      expect(await db.calendarEventDao.sharedPairsOf(['e1']), isEmpty);
    });

    CalendarCategoriesCompanion gymSeed() => CalendarCategoriesCompanion.insert(
      id: 'gym',
      name: 'Gym',
      colorValue: 0xFF336699,
      iconKey: 'event',
      isBuiltIn: const Value(true),
      createdAt: day,
      updatedAt: day,
    );

    test('a deleted built-in seeded back comes back private: the delete '
        'ended its grant for good, and the cleared mark carries the '
        'revival\'s stamp, so every device takes it', () async {
      await category('gym', builtIn: true);
      await event('e1', 'gym');
      await dayRows('e1');
      await db.calendarCategoryDao.setSharedPair('gym', 'pair-1');
      final marked = await categoryRow('gym');
      await db.customStatement(
        "UPDATE calendar_categories SET is_deleted = 1 WHERE id = 'gym'",
      );
      await settle();

      await db.calendarCategoryDao.seedMissing([gymSeed()]);

      final revived = await categoryRow('gym');
      expect(revived.isDeleted, isFalse);
      expect(revived.sharedPair, isNull);
      expect(revived.sharedStamp, revived.hlcTimestamp);
      expect(revived.sharedStamp!.compareTo(marked.sharedStamp!), 1);
      expect(await queued(), {'calendar_categories/gym'});
      expect(await db.calendarEventDao.sharedPairsOf(['e1']), isEmpty);
    });

    test('a built-in another account shares under its id is taken out '
        'before the person\'s own is seeded: a copy an older build stored '
        'never keeps the person\'s built-in away', () async {
      const partner = 'partner';
      await category('gym');
      await db.calendarEventDao.upsert(eventEntry('theirs', 'gym'));
      await db.customStatement(
        "UPDATE calendar_categories SET owner_id = '$partner' "
        "WHERE id = 'gym'",
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
      await settle();

      await db.calendarCategoryDao.seedMissing([gymSeed()]);

      final seeded = await categoryRow('gym');
      expect(seeded.ownerId, isNull);
      expect(seeded.name, 'Gym');
      expect(seeded.isBuiltIn, isTrue);
      expect(await queued(), {'calendar_categories/gym'});
    });
  });

  group('a merge', () {
    /// A stamp above every one this device mints, in the order of [n].
    String high(int n) => 'ffffffffff0$n:0000:other';

    /// [local] as another device wrote it later.
    CalendarCategoryRow later(
      CalendarCategoryRow local, {
      int n = 0,
      String? name,
      String? pair,
      String? stamp,
      bool keepMark = true,
    }) => local.copyWith(
      name: name,
      hlcTimestamp: high(n),
      deviceId: 'other',
      version: local.version + 1,
      sharedPair: keepMark ? Value(local.sharedPair) : Value(pair),
      sharedStamp: keepMark ? Value(local.sharedStamp) : Value(stamp),
    );

    test('that brings a category\'s mark queues this device\'s copies of '
        'its events and their day rows; one that takes it away, too',
        () async {
      await category('c1');
      await event('e1', 'c1');
      await dayRows('e1');
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        later(
          await categoryRow('c1'),
          keepMark: false,
          pair: 'pair-1',
          stamp: high(0),
        ),
      );
      expect((await categoryRow('c1')).sharedPair, 'pair-1');
      expect(await queued(), granted('e1'));
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        later(await categoryRow('c1'), n: 1, keepMark: false, stamp: high(1)),
      );
      expect((await categoryRow('c1')).sharedPair, isNull);
      expect(await queued(), granted('e1'));
    });

    test('that changes nothing about the grant queues nothing', () async {
      await category('c1');
      await event('e1', 'c1');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        later(await categoryRow('c1'), name: 'Renamed'),
      );

      expect((await categoryRow('c1')).name, 'Renamed');
      expect(await queued(), isEmpty);
    });

    test('a rename made where the end of a share had not arrived wins the '
        'row and does not bring the share back', () async {
      await category('c1');
      await event('e1', 'c1');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      final shared = await categoryRow('c1');
      await db.calendarCategoryDao.setSharedPair('c1', null);
      final ended = await categoryRow('c1');
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        later(
          ended,
          name: 'Renamed where the share still stood',
          keepMark: false,
          pair: 'pair-1',
          stamp: shared.sharedStamp,
        ),
      );

      final merged = await categoryRow('c1');
      expect(merged.name, 'Renamed where the share still stood');
      expect(merged.sharedPair, isNull);
      expect(merged.sharedStamp, ended.sharedStamp);
      // Queued as a real write, so the push corrects the document that
      // said "shared" ahead of anything under it.
      expect(await republished(), {'calendar_categories/c1': false});
    });

    test('of a shared category\'s delete keeps the mark it had and queues '
        'its events: a deleted category grants nothing', () async {
      await category('c1');
      await event('e1', 'c1');
      await dayRows('e1');
      await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
      final local = await categoryRow('c1');
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        later(
          local,
          keepMark: false,
        ).copyWith(isDeleted: true, deletedAt: Value(day)),
      );

      final merged = await categoryRow('c1');
      expect(merged.isDeleted, isTrue);
      expect(merged.sharedPair, 'pair-1');
      expect(await queued(), granted('e1'));
    });

    for (final (remote, stale) in [
      ('one that never held the mark', false),
      ('one that held the mark from before the delete', true),
    ]) {
      test('of a live row over a shared category\'s tombstone — $remote — '
          'brings it back private: a delete ends the grant for good, and '
          'the cleared mark is stamped and queued for every device', () async {
        await category('c1');
        await event('e1', 'c1');
        await dayRows('e1');
        await db.calendarCategoryDao.setSharedPair('c1', 'pair-1');
        final marked = await categoryRow('c1');
        await db.calendarCategoryDao.softDeleteById('c1');
        final tombstone = await categoryRow('c1');
        expect(
          tombstone.sharedPair,
          'pair-1',
          reason: 'the partner has to hear of the delete',
        );
        await settle();

        final outcome = await db.calendarCategoryDao.mergeRemoteCategory(
          later(
            tombstone,
            name: 'Renamed elsewhere',
            keepMark: false,
            pair: stale ? 'pair-1' : null,
            stamp: stale ? marked.sharedStamp : null,
          ).copyWith(isDeleted: false, deletedAt: const Value(null)),
        );

        final merged = await categoryRow('c1');
        expect(outcome.result, MergeResult.applied);
        expect(merged.isDeleted, isFalse);
        expect(merged.name, 'Renamed elsewhere');
        expect(merged.sharedPair, isNull);
        expect(merged.sharedStamp!.compareTo(tombstone.hlcTimestamp), 1);
        expect(await db.calendarEventDao.sharedPairsOf(['e1']), isEmpty);
        expect(
          await const CalendarEventsBinding().sharedPairs(db, [
            await eventRow('e1'),
          ]),
          isEmpty,
        );
        expect(await republished(), {'calendar_categories/c1': false});
      });
    }

    test('of a live row over a tombstone no mark ever touched writes and '
        'queues nothing more than the row', () async {
      await category('c1');
      await db.calendarCategoryDao.softDeleteById('c1');
      final tombstone = await categoryRow('c1');
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        later(
          tombstone,
          name: 'Renamed elsewhere',
        ).copyWith(isDeleted: false, deletedAt: const Value(null)),
      );

      final merged = await categoryRow('c1');
      expect(merged.isDeleted, isFalse);
      expect(merged.sharedStamp, isNull);
      expect(await queued(), isEmpty);
    });

    test('of a new category that carries a mark queues the events that '
        'arrived ahead of it', () async {
      await event('e1', 'c1');
      await dayRows('e1');
      await settle();

      await db.calendarCategoryDao.mergeRemoteCategory(
        CalendarCategoryRow(
          id: 'c1',
          name: 'Climb',
          colorValue: 0xFF336699,
          iconKey: 'event',
          sortOrder: 0,
          isBuiltIn: false,
          isHidden: false,
          createdAt: day,
          updatedAt: day,
          hlcTimestamp: high(0),
          deviceId: 'other',
          version: 2,
          isDeleted: false,
          sharedPair: 'pair-1',
          sharedStamp: high(0),
        ),
      );

      expect(await queued(), granted('e1'));
    });

    test('of an event moved out of a shared category queues its day rows; '
        'a new event in one, too; a new one in a private one, nothing',
        () async {
      await category('shared');
      await category('private');
      await db.calendarCategoryDao.setSharedPair('shared', 'pair-1');
      await event('e1', 'shared');
      await dayRows('e1');
      await dayRows('arrives');
      await dayRows('arrivesPrivate');
      await settle();

      final local = await eventRow('e1');
      await db.calendarEventDao.mergeRemoteEvent(
        local.copyWith(
          category: 'private',
          hlcTimestamp: high(0),
          deviceId: 'other',
          version: local.version + 1,
        ),
      );
      expect(await queued(), {skipKey('e1'), textKey('e1')});
      await settle();

      for (final (id, category) in [
        ('arrives', 'shared'),
        ('arrivesPrivate', 'private'),
      ]) {
        await db.calendarEventDao.mergeRemoteEvent(
          local.copyWith(
            id: id,
            category: category,
            hlcTimestamp: high(1),
            deviceId: 'other',
            version: 1,
          ),
        );
      }
      expect(await queued(), {skipKey('arrives'), textKey('arrives')});
    });
  });
}
