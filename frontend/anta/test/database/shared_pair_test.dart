import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/crdt/crdt_merge.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/daos/folder_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// The share mark (`docs/cloud-sharing-foundations.md` §3): one column on
/// an event and on a folder, written by one call each, and what follows
/// from it — the rows that are shared by where they hang carry no mark, so
/// a change of their root has to queue them again, or their documents would
/// go on saying who may read them as of the push before.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  final day = DateTime.utc(2026, 6, 1);
  final otherDay = DateTime.utc(2026, 6, 2);

  /// What the queue holds, as `table/key` — emptied by [settle] so a test
  /// reads only what its act queued.
  Future<Set<String>> queued() async => {
    for (final entry in await db.syncOutboxDao.pending())
      '${entry.syncedTable}/${entry.rowKey}',
  };

  Future<void> settle() => db.syncOutboxDao.clear();

  Future<void> event(String id) => db.calendarEventDao.upsert(
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

  Future<CalendarEventRow> eventRow(String id) async =>
      (await db.calendarEventDao.getByIdsIncludingDeleted([id])).single;

  Future<Folder> folderRow(String id) async =>
      (await db.folderDao.getByIdsIncludingDeleted([id])).single;

  Future<String> folder(String name, {String? under}) async =>
      (await db.folderDao.createFolder(name: name, parentId: under)).id;

  Future<String> note(String title, String folderId) async =>
      (await db.noteDao.createNote(folderId: folderId, title: title)).id;

  String skipKey(String eventId, DateTime on) =>
      'calendar_event_skips/${dayRowKey(eventId, on)}';
  String textKey(String eventId, DateTime on) =>
      'calendar_event_occurrences/${dayRowKey(eventId, on)}';

  group('an event\'s mark', () {
    test('is one stamped write of the one column: queued, a version on, '
        'updated_at left alone', () async {
      await event('e1');
      final before = await eventRow('e1');
      await settle();

      expect(await db.calendarEventDao.setSharedPair('e1', 'pair-1'), isTrue);

      final after = await eventRow('e1');
      expect(after.sharedPair, 'pair-1');
      expect(after.sharedStamp, after.hlcTimestamp);
      expect(after.version, before.version + 1);
      expect(after.hlcTimestamp.compareTo(before.hlcTimestamp), greaterThan(0));
      expect(after.updatedAt, before.updatedAt);
      expect(after.title, before.title);
      expect(await queued(), {'calendar_events/e1'});
    });

    test('taken away again is the same write', () async {
      await event('e1');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      final marked = await eventRow('e1');
      await settle();

      expect(await db.calendarEventDao.setSharedPair('e1', null), isTrue);

      final after = await eventRow('e1');
      expect(after.sharedPair, isNull);
      expect(
        after.sharedStamp,
        after.hlcTimestamp,
        reason: 'a mark taken away is stamped too: that is what tells it '
            'from a mark never heard of',
      );
      expect(after.version, marked.version + 1);
      expect(await queued(), {'calendar_events/e1'});
    });

    test('a mark it already carries, a missing event and a deleted one '
        'write nothing', () async {
      await event('e1');
      await event('gone');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      await db.calendarEventDao.softDeleteById('gone');
      final marked = await eventRow('e1');
      await settle();

      expect(await db.calendarEventDao.setSharedPair('e1', 'pair-1'), isFalse);
      expect(
        await db.calendarEventDao.setSharedPair('none', 'pair-1'),
        isFalse,
      );
      expect(
        await db.calendarEventDao.setSharedPair('gone', 'pair-1'),
        isFalse,
      );

      expect(await queued(), isEmpty);
      expect((await eventRow('e1')).version, marked.version);
      expect((await eventRow('gone')).sharedPair, isNull);
    });

    test('queues its skipped days and per-day texts again at their own '
        'stamps — deleted ones too — and never a presence mark, nor '
        'another event\'s rows', () async {
      await event('e1');
      await event('e2');
      await db.eventSkipDao.markSkipped('e1', day);
      await db.eventSkipDao.markSkipped('e1', otherDay);
      await db.eventSkipDao.unskip('e1', otherDay);
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: day,
          description: 'Bring the keys',
          createdAt: day,
          updatedAt: day,
        ),
      );
      await db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.missed);
      await db.eventSkipDao.markSkipped('e2', day);
      final stamps = {
        for (final row in await db.select(db.eventSkips).get())
          dayRowKey(row.eventId, row.day): row.hlcTimestamp,
      };
      await settle();

      await db.calendarEventDao.setSharedPair('e1', 'pair-1');

      expect(await queued(), {
        'calendar_events/e1',
        skipKey('e1', day),
        skipKey('e1', otherDay),
        textKey('e1', day),
      });
      final entries = {
        for (final entry in await db.syncOutboxDao.pending())
          if (entry.syncedTable == 'calendar_event_skips') entry.rowKey: entry,
      };
      for (final MapEntry(:key, value: entry) in entries.entries) {
        expect(entry.hlc, stamps[key], reason: 'no stamp is minted for $key');
      }
      expect(entries[dayRowKey('e1', otherDay)]!.op, OutboxOp.tombstone.name);
      // The rows themselves did not change.
      expect({
        for (final row in await db.select(db.eventSkips).get())
          dayRowKey(row.eventId, row.day): row.hlcTimestamp,
      }, stamps);
    });

    test('a mark for one pair clears every mark of another, on events and '
        'folders alike, and queues what those shared', () async {
      await event('old');
      await event('new');
      await db.eventSkipDao.markSkipped('old', day);
      final shelf = await folder('Shelf');
      final inside = await note('Inside', shelf);
      await db.calendarEventDao.setSharedPair('old', 'pair-old');
      await db.folderDao.setSharedPair(shelf, 'pair-old');
      await settle();

      await db.calendarEventDao.setSharedPair('new', 'pair-new');

      expect((await eventRow('old')).sharedPair, isNull);
      expect((await folderRow(shelf)).sharedPair, isNull);
      expect((await eventRow('new')).sharedPair, 'pair-new');
      expect(await queued(), {
        'calendar_events/new',
        'calendar_events/old',
        skipKey('old', day),
        'folders/$shelf',
        'notes/$inside',
      });
    });

    test('a second mark for the same pair leaves the first alone', () async {
      await event('e1');
      await event('e2');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      await settle();

      await db.calendarEventDao.setSharedPair('e2', 'pair-1');

      expect((await eventRow('e1')).sharedPair, 'pair-1');
      expect(await queued(), {'calendar_events/e2'});
    });
  });

  group('a folder\'s mark', () {
    test('is one stamped write of the one column, and queues every folder '
        'and note under it again — deleted ones too — and nothing '
        'beside it', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      final deep = await folder('Deep', under: box);
      final beside = await folder('Beside');
      final top = await note('Top', shelf);
      final low = await note('Low', deep);
      final dropped = await note('Dropped', box);
      final apart = await note('Apart', beside);
      await db.noteDao.softDeleteNote(dropped);
      final before = await folderRow(shelf);
      await settle();

      expect(await db.folderDao.setSharedPair(shelf, 'pair-1'), isTrue);

      final after = await folderRow(shelf);
      expect(after.sharedPair, 'pair-1');
      expect(after.version, before.version + 1);
      expect(after.updatedAt, before.updatedAt);
      expect(await queued(), {
        'folders/$shelf',
        'folders/$box',
        'folders/$deep',
        'notes/$top',
        'notes/$low',
        'notes/$dropped',
      });
      expect(await queued(), isNot(contains('notes/$apart')));
      expect((await folderRow(box)).sharedPair, isNull, reason: 'derived');
    });

    test('a mark it already carries, a missing folder and a deleted one '
        'write nothing', () async {
      final shelf = await folder('Shelf');
      final gone = await folder('Gone');
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await db.folderDao.softDeleteFolder(gone);
      await settle();

      expect(await db.folderDao.setSharedPair(shelf, 'pair-1'), isFalse);
      expect(await db.folderDao.setSharedPair('none', 'pair-1'), isFalse);
      expect(await db.folderDao.setSharedPair(gone, 'pair-1'), isFalse);

      expect(await queued(), isEmpty);
    });

    test('covers the marks inside its own subtree, which are cleared with '
        'it', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      final inBox = await note('In the box', box);
      await db.folderDao.setSharedPair(box, 'pair-1');
      final marked = await folderRow(box);
      await settle();

      await db.folderDao.setSharedPair(shelf, 'pair-1');

      final inner = await folderRow(box);
      expect(inner.sharedPair, isNull);
      expect(inner.version, marked.version + 1);
      expect(await queued(), {
        'folders/$shelf',
        'folders/$box',
        'notes/$inBox',
      });
    });

    test('a mark for one pair clears every mark of another, events '
        'included', () async {
      await event('old');
      final oldShelf = await folder('Old shelf');
      final oldNote = await note('Old note', oldShelf);
      final shelf = await folder('Shelf');
      await db.calendarEventDao.setSharedPair('old', 'pair-old');
      await db.folderDao.setSharedPair(oldShelf, 'pair-old');
      await settle();

      await db.folderDao.setSharedPair(shelf, 'pair-new');

      expect((await eventRow('old')).sharedPair, isNull);
      expect((await folderRow(oldShelf)).sharedPair, isNull);
      expect(await queued(), {
        'folders/$shelf',
        'folders/$oldShelf',
        'notes/$oldNote',
        'calendar_events/old',
      });
    });

    test('taken away queues the subtree again, so its documents stop '
        'naming the pair', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      final inBox = await note('In the box', box);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await settle();

      expect(await db.folderDao.setSharedPair(shelf, null), isTrue);

      expect(await queued(), {
        'folders/$shelf',
        'folders/$box',
        'notes/$inBox',
      });
      expect(await db.folderDao.sharedPairsOf([shelf, box]), isEmpty);
    });
  });

  group('what a row is shared into', () {
    test('a folder by its own mark, else by the nearest marked folder above '
        'it; a folder under none by nothing', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      final deep = await folder('Deep', under: box);
      final own = await folder('Own', under: deep);
      final beside = await folder('Beside');
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      // Set directly: two pairs at once is what a merge can leave.
      await db.customStatement(
        'UPDATE folders SET shared_pair = ? WHERE id = ?',
        ['pair-2', own],
      );

      expect(
        await db.folderDao.sharedPairsOf([shelf, box, deep, own, beside, 'x']),
        {shelf: 'pair-1', box: 'pair-1', deep: 'pair-1', own: 'pair-2'},
      );
    });

    test('nothing is read past the marks when no folder carries one', () async {
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);
      final shelf = await counted.folderDao.createFolder(name: 'Shelf');
      counter.reset();

      expect(
        await counted.folderDao.sharedPairsOf([shelf.id, 'a', 'b']),
        isEmpty,
      );

      expect(counter.count, 1);
    });

    test('a deleted folder keeps its place in what is shared: the partner '
        'has to hear of the delete', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await db.folderDao.softDeleteFolderWithDescendants(shelf);

      expect(await db.folderDao.sharedPairsOf([shelf, box]), {
        shelf: 'pair-1',
        box: 'pair-1',
      });
    });

    test(
      'a parent cycle ends at the depth bound, shared into nothing',
      () async {
        final a = await folder('A');
        final b = await folder('B', under: a);
        final marked = await folder('Marked');
        await db.folderDao.setSharedPair(marked, 'pair-1');
        await db.customStatement(
          'UPDATE folders SET parent_id = ? WHERE id = ?',
          [b, a],
        );

        expect(await db.folderDao.sharedPairsOf([a, b]), isEmpty);
        expect(FolderDao.maxFolderDepth, greaterThan(2));
      },
    );

    test('an event by its own mark, read for many at once', () async {
      await event('e1');
      await event('e2');
      await event('e3');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      await db.calendarEventDao.setSharedPair('e3', 'pair-1');
      await db.calendarEventDao.softDeleteById('e3');

      expect(await db.calendarEventDao.sharedPairsOf(['e1', 'e2', 'e3', 'x']), {
        'e1': 'pair-1',
        'e3': 'pair-1',
      });
      expect(await db.calendarEventDao.sharedPairsOf(const []), isEmpty);
    });

    test('the pair the database\'s notes are shared into is its live '
        'folders\' mark, and none without one', () async {
      expect(await db.folderDao.sharedPairOfNotes(), isNull);
      final shelf = await folder('Shelf');
      await event('e1');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      expect(
        await db.folderDao.sharedPairOfNotes(),
        isNull,
        reason: 'an event shares no note text',
      );

      await db.folderDao.setSharedPair(shelf, 'pair-1');
      expect(await db.folderDao.sharedPairOfNotes(), 'pair-1');

      await db.folderDao.softDeleteFolder(shelf);
      expect(await db.folderDao.sharedPairOfNotes(), isNull);
    });
  });

  group('a folder moved', () {
    late String shelf;
    late String box;
    late String inBox;
    late String deep;

    setUp(() async {
      shelf = await folder('Shelf');
      box = await folder('Box');
      deep = await folder('Deep', under: box);
      inBox = await note('In the box', box);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await settle();
    });

    Set<String> subtree() => {'folders/$deep', 'notes/$inBox'};

    test('under a shared folder queues its subtree again, and out of it '
        'too', () async {
      await db.folderDao.moveFolder(id: box, targetParentId: shelf);
      expect(await queued(), {'folders/$box', ...subtree()});
      await settle();

      await db.folderDao.moveFolder(id: box, targetParentId: null);
      expect(await queued(), {'folders/$box', ...subtree()});
    });

    test('between two places that share alike queues only itself', () async {
      final plain = await folder('Plain');
      await settle();

      await db.folderDao.moveFolder(id: box, targetParentId: plain);

      expect(await queued(), {'folders/$box'});
    });

    test('by a rename-and-move queues its subtree the same way', () async {
      await db.folderDao.updateFolder(
        id: box,
        parentId: shelf,
        updateParent: true,
      );

      expect(await queued(), {'folders/$box', ...subtree()});
    });

    test('as one of a selection queues the subtree of each that changed '
        'what it shares into', () async {
      final loose = await folder('Loose');
      final inLoose = await note('In loose', loose);
      await settle();

      await db.folderDao.moveFolders([box, loose], shelf);

      expect(await queued(), {
        'folders/$box',
        'folders/$loose',
        'notes/$inLoose',
        ...subtree(),
      });
    });
  });

  group('a merge', () {
    /// A stamp above every one this device mints, in the order of [n].
    String high(int n) => 'ffffffffff0$n:0000:other';

    /// [local] as another device wrote it later — a higher stamp, the next
    /// version — carrying [mark] as that device held it: the local one
    /// unless given.
    Folder later(
      Folder local, {
      int n = 0,
      ShareMark? mark,
      String? parentId,
      String? name,
    }) => Folder(
      id: local.id,
      name: name ?? local.name,
      parentId: parentId ?? local.parentId,
      position: local.position,
      label: local.label,
      createdAt: local.createdAt,
      updatedAt: local.updatedAt,
      noteSortOrder: local.noteSortOrder,
      subfolderSortOrder: local.subfolderSortOrder,
      hlcTimestamp: high(n),
      deviceId: 'other',
      version: local.version + 1,
      isDeleted: false,
      deletedAt: null,
      ownerId: local.ownerId,
      sharedPair: mark == null ? local.sharedPair : mark.pair,
      sharedStamp: mark == null ? local.sharedStamp : mark.stamp,
    );

    test('that brings a folder\'s mark queues this device\'s copies of '
        'what lies under it again; one that takes it away, too', () async {
      final shelf = await folder('Shelf');
      final inside = await note('Inside', shelf);
      await settle();

      await db.folderDao.mergeFolder(
        later(await folderRow(shelf), mark: (pair: 'pair-1', stamp: high(0))),
      );
      expect((await folderRow(shelf)).sharedPair, 'pair-1');
      expect((await folderRow(shelf)).sharedStamp, high(0));
      expect(await queued(), {'notes/$inside'});
      await settle();

      await db.folderDao.mergeFolder(
        later(
          await folderRow(shelf),
          n: 1,
          mark: (pair: null, stamp: high(1)),
        ),
      );
      expect((await folderRow(shelf)).sharedPair, isNull);
      expect((await folderRow(shelf)).sharedStamp, high(1));
      expect(await queued(), {'notes/$inside'});
    });

    test('that moves a folder under a shared one queues its subtree '
        'again', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box');
      final inBox = await note('In the box', box);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await settle();

      await db.folderDao.mergeFolder(
        later(await folderRow(box), parentId: shelf),
      );

      expect(await queued(), {'notes/$inBox'});
    });

    test('that changes neither queues nothing', () async {
      final shelf = await folder('Shelf');
      await note('Inside', shelf);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await settle();

      await db.folderDao.mergeFolder(
        later(await folderRow(shelf), name: 'Renamed elsewhere'),
      );

      expect((await folderRow(shelf)).name, 'Renamed elsewhere');
      expect((await folderRow(shelf)).sharedPair, 'pair-1');
      expect(await queued(), isEmpty);
    });

    test('of a deleted folder keeps the mark it had', () async {
      final shelf = await folder('Shelf');
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      final marked = await folderRow(shelf);

      await db.folderDao.mergeFolder(
        Folder(
          id: marked.id,
          name: marked.id,
          position: 0,
          label: 0,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          hlcTimestamp: high(2),
          deviceId: 'other',
          version: marked.version + 1,
          isDeleted: true,
          deletedAt: day,
        ),
      );

      final tombstone = await folderRow(shelf);
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.sharedPair, 'pair-1');
      expect(tombstone.sharedStamp, marked.sharedStamp);
    });

    group('settles the mark apart from the row', () {
      test('a rename made where the end of a share had not arrived wins the '
          'row and does not bring the share back: the mark taken away later '
          'stands, and the folder is queued so its document says so', () async {
        final shelf = await folder('Shelf');
        final inside = await note('Inside', shelf);
        await db.folderDao.setSharedPair(shelf, 'pair-1');
        final shared = await folderRow(shelf);
        await db.folderDao.setSharedPair(shelf, null);
        final ended = await folderRow(shelf);
        await settle();

        // The other device still held the share when it renamed the folder,
        // after the share's end by the clock.
        await db.folderDao.mergeFolder(
          later(
            ended,
            name: 'Renamed where the share still stood',
            mark: (pair: 'pair-1', stamp: shared.sharedStamp),
          ),
        );

        final merged = await folderRow(shelf);
        expect(merged.name, 'Renamed where the share still stood');
        expect(merged.hlcTimestamp, high(0));
        expect(merged.sharedPair, isNull);
        expect(merged.sharedStamp, ended.sharedStamp);
        expect(await queued(), {'folders/$shelf'});
        expect(
          (await db.syncOutboxDao.pending()).single.republish,
          isFalse,
          reason: 'sent with the real writes, ahead of any row under it',
        );
        expect(await queued(), isNot(contains('notes/$inside')));
      });

      test('nor does such a rename end a share made since', () async {
        final shelf = await folder('Shelf');
        final before = await folderRow(shelf);
        await db.folderDao.setSharedPair(shelf, 'pair-1');
        final shared = await folderRow(shelf);
        await settle();

        await db.folderDao.mergeFolder(
          later(
            shared,
            name: 'Renamed before the share arrived',
            mark: (pair: before.sharedPair, stamp: before.sharedStamp),
          ),
        );

        final merged = await folderRow(shelf);
        expect(merged.name, 'Renamed before the share arrived');
        expect(merged.sharedPair, 'pair-1');
        expect(merged.sharedStamp, shared.sharedStamp);
        expect(await queued(), {'folders/$shelf'});
      });

      test('a newer mark is taken from a remote whose row loses: this '
          'device\'s later rename stands, shared as the other one says', () async {
        final shelf = await folder('Shelf');
        final inside = await note('Inside', shelf);
        final local = await folderRow(shelf);
        final lower = HlcTimestamp.parse(local.hlcTimestamp);
        // Stamped between this device's two writes: the share, made
        // elsewhere, then this device's rename.
        final stamp = HlcTimestamp(
          wallTime: lower.wallTime,
          logicalCounter: lower.logicalCounter + 1,
          nodeId: 'other',
        ).toString();
        // Past the millisecond the folder was made in, so the rename's stamp
        // is above the share's by its wall time, not by a node id.
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await db.folderDao.updateFolder(id: shelf, name: 'Renamed here');
        final renamed = await folderRow(shelf);
        expect(renamed.hlcTimestamp.compareTo(stamp), greaterThan(0));
        await settle();

        final outcome = await db.folderDao.mergeFolder(
          Folder(
            id: local.id,
            name: local.name,
            parentId: local.parentId,
            position: local.position,
            label: local.label,
            createdAt: local.createdAt,
            updatedAt: local.updatedAt,
            hlcTimestamp: stamp,
            deviceId: 'other',
            version: local.version + 1,
            isDeleted: false,
            sharedPair: 'pair-1',
            sharedStamp: stamp,
          ),
        );

        expect(outcome.result, MergeResult.keptLocal);
        final merged = await folderRow(shelf);
        expect(merged.name, 'Renamed here');
        expect(merged.hlcTimestamp, renamed.hlcTimestamp);
        expect(merged.sharedPair, 'pair-1');
        expect(merged.sharedStamp, stamp);
        expect(await queued(), {'folders/$shelf', 'notes/$inside'});
      });

      test('a mark that arrives at the row\'s own stamp is taken: a build '
          'that could not read marks stored the row without it', () async {
        final shelf = await folder('Shelf');
        final inside = await note('Inside', shelf);
        final local = await folderRow(shelf);
        await settle();

        final outcome = await db.folderDao.mergeFolder(
          local.copyWith(
            sharedPair: const Value('pair-1'),
            sharedStamp: Value(local.hlcTimestamp),
          ),
        );

        expect(outcome.result, MergeResult.unchanged);
        expect((await folderRow(shelf)).sharedPair, 'pair-1');
        expect((await folderRow(shelf)).sharedStamp, local.hlcTimestamp);
        expect(await queued(), {'notes/$inside'});
      });

      test('two marks never stamped that differ settle private on every '
          'device, whichever side it stands on', () async {
        final shelf = await folder('Shelf');
        final other = await folder('Other');
        await db.customStatement(
          "UPDATE folders SET shared_pair = 'pair-1' WHERE id = ?",
          [other],
        );
        await settle();

        await db.folderDao.mergeFolder(
          later(await folderRow(shelf), mark: (pair: 'pair-1', stamp: null)),
        );
        await db.folderDao.mergeFolder(
          later(await folderRow(other), mark: (pair: null, stamp: null)),
        );

        expect((await folderRow(shelf)).sharedPair, isNull);
        expect((await folderRow(other)).sharedPair, isNull);
      });
    });

    test('that brings an event\'s mark queues its day rows again; one that '
        'changes nothing about it does not', () async {
      await event('e1');
      await db.eventSkipDao.markSkipped('e1', day);
      await settle();
      final local = await eventRow('e1');

      await db.calendarEventDao.mergeRemoteEvent(
        local.copyWith(
          hlcTimestamp: high(0),
          deviceId: 'other',
          version: local.version + 1,
          sharedPair: const Value('pair-1'),
          sharedStamp: Value(high(0)),
        ),
      );
      expect((await eventRow('e1')).sharedPair, 'pair-1');
      expect(await queued(), {skipKey('e1', day)});
      await settle();

      final marked = await eventRow('e1');
      await db.calendarEventDao.mergeRemoteEvent(
        marked.copyWith(
          title: 'Renamed',
          hlcTimestamp: high(1),
          deviceId: 'other',
          version: marked.version + 1,
        ),
      );
      expect((await eventRow('e1')).title, 'Renamed');
      expect(await queued(), isEmpty);
    });

    test('an edit of an event made where the end of its share had not '
        'arrived wins the row and does not bring the share back', () async {
      await event('e1');
      await db.eventSkipDao.markSkipped('e1', day);
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      final shared = await eventRow('e1');
      await db.calendarEventDao.setSharedPair('e1', null);
      final ended = await eventRow('e1');
      await settle();

      await db.calendarEventDao.mergeRemoteEvent(
        ended.copyWith(
          title: 'Edited where the share still stood',
          hlcTimestamp: high(0),
          deviceId: 'other',
          version: ended.version + 1,
          sharedPair: const Value('pair-1'),
          sharedStamp: Value(shared.sharedStamp),
        ),
      );

      final merged = await eventRow('e1');
      expect(merged.title, 'Edited where the share still stood');
      expect(merged.sharedPair, isNull);
      expect(merged.sharedStamp, ended.sharedStamp);
      expect(await queued(), {'calendar_events/e1'});
    });
  });

  group('the rows a mark queues again', () {
    Future<void> own(String table, String id, String? owner) =>
        db.customStatement('UPDATE $table SET owner_id = ? WHERE id = ?', [
          owner,
          id,
        ]);

    test('are every one of this device\'s own, whatever the owner column '
        'spells that as: a row from before the bind carries the account, '
        'one written since carries none', () async {
      final shelf = await folder('Shelf');
      final box = await folder('Box', under: shelf);
      final atBind = await note('Here at the bind', shelf);
      final since = await note('Written since', shelf);
      final deep = await note('In the box', box);
      await own('folders', shelf, 'me');
      await own('notes', atBind, 'me');
      await own('notes', deep, 'an-account-that-bound-before');
      await settle();
      final all = {
        'folders/$shelf',
        'folders/$box',
        'notes/$atBind',
        'notes/$since',
        'notes/$deep',
      };

      await db.folderDao.setSharedPair(shelf, 'pair-1');
      expect(await queued(), all);
      await settle();

      await db.folderDao.setSharedPair(shelf, null);
      expect(await queued(), all);
    });

    test('and of an event: a day row written after the bind follows an '
        'event from before it', () async {
      await event('e1');
      await db.eventSkipDao.markSkipped('e1', day);
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: day,
          description: 'Bring the keys',
          createdAt: day,
          updatedAt: day,
        ),
      );
      await own('calendar_events', 'e1', 'me');
      await settle();

      await db.calendarEventDao.setSharedPair('e1', 'pair-1');

      expect(await queued(), {
        'calendar_events/e1',
        skipKey('e1', day),
        textKey('e1', day),
      });
    });

    test('never a row another account shares with this one', () async {
      final shelf = await folder('Shelf');
      final mine = await note('Mine', shelf);
      final theirs = await note('Theirs', shelf);
      await own('notes', theirs, 'partner');
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      await settle();

      await db.folderDao.setSharedPair(shelf, 'pair-1');

      expect(await queued(), {'folders/$shelf', 'notes/$mine'});
    });

    test('as re-sends of versions the space holds — the mark\'s own write '
        'is the one real write among them', () async {
      final shelf = await folder('Shelf');
      final inside = await note('Inside', shelf);
      await settle();

      await db.folderDao.setSharedPair(shelf, 'pair-1');

      expect(
        {
          for (final entry in await db.syncOutboxDao.pending())
            '${entry.syncedTable}/${entry.rowKey}': entry.republish,
        },
        {'folders/$shelf': false, 'notes/$inside': true},
      );
      expect(
        [
          for (final entry in await db.syncOutboxDao.pending(
            unpushedOnly: true,
          ))
            '${entry.syncedTable}/${entry.rowKey}',
        ],
        ['folders/$shelf'],
      );
    });

    test('a note edited and not yet pushed stays an unpushed write when a '
        'mark queues it again', () async {
      final shelf = await folder('Shelf');
      final inside = await note('Inside', shelf);
      await settle();
      await db.noteDao.updateNote(id: inside, preview: 'New', content: 'New');

      await db.folderDao.setSharedPair(shelf, 'pair-1');

      final entry = (await db.syncOutboxDao.pending()).singleWhere(
        (entry) => entry.rowKey == inside,
      );
      expect(entry.republish, isFalse);
    });
  });

  group('the marks of a pair that is no longer the account\'s', () {
    test('are cleared together, on events and folders, each under the one '
        'stamp and queued with what hangs under it', () async {
      final shelf = await folder('Shelf');
      final inside = await note('Inside', shelf);
      final kept = await folder('Kept');
      await event('e1');
      await event('e2');
      await db.eventSkipDao.markSkipped('e1', day);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      await settle();
      final stamp = db.newStamp();

      expect(await db.folderDao.clearOtherPairs('pair-2', stamp), 1);
      expect(await db.calendarEventDao.clearOtherPairs('pair-2', stamp), 1);

      expect((await folderRow(shelf)).sharedPair, isNull);
      expect((await folderRow(shelf)).sharedStamp, stamp.hlc);
      expect((await eventRow('e1')).sharedPair, isNull);
      expect((await eventRow('e1')).sharedStamp, stamp.hlc);
      expect(await queued(), {
        'folders/$shelf',
        'notes/$inside',
        'calendar_events/e1',
        skipKey('e1', day),
      });
      expect((await folderRow(kept)).hlcTimestamp, isNot(stamp.hlc));
      expect((await eventRow('e2')).sharedStamp, isNull);
    });

    test('with no pair at all, every mark goes; the marks of the pair that '
        'stands are left alone', () async {
      final shelf = await folder('Shelf');
      await event('e1');
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await db.calendarEventDao.setSharedPair('e1', 'pair-1');
      await settle();

      expect(await db.folderDao.clearOtherPairs('pair-1', db.newStamp()), 0);
      expect(
        await db.calendarEventDao.clearOtherPairs('pair-1', db.newStamp()),
        0,
      );
      expect(await queued(), isEmpty);

      expect(await db.folderDao.clearOtherPairs(null, db.newStamp()), 1);
      expect(await db.calendarEventDao.clearOtherPairs(null, db.newStamp()), 1);
      expect((await folderRow(shelf)).sharedPair, isNull);
      expect((await eventRow('e1')).sharedPair, isNull);
    });
  });
}
