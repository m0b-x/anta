import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/services/sync/sync_status.dart';

import '../database/support/db_test_support.dart';
import '../support/fake_share_service.dart';
import 'pairing_support.dart';

/// "This database syncs", decided by the test; every ask counted.
class _FakeSyncSource implements ShareSyncSource {
  bool bound = true;
  bool isOffline = false;
  int asks = 0;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void flip(bool next) {
    bound = next;
    _changes.add(null);
  }

  /// When set, every ask parks on a new completer here until the test
  /// answers it.
  List<Completer<bool>>? gate;

  bool failing = false;

  /// Whether anything still listens to [changes].
  bool get heard => _changes.hasListener;

  @override
  Future<bool> syncing() async {
    asks++;
    if (failing) throw StateError('the binding was not read');
    final parked = gate;
    if (parked == null) return bound;
    final answer = Completer<bool>();
    parked.add(answer);
    return answer.future;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<bool> offline() async => isOffline;

  @override
  Stream<void> get runsEnded => const Stream<void>.empty();
}

/// The facade a share surface reads (`docs/cloud-share-surfaces-roadmap.md`
/// §6.1): availability and its replaying stream, the only writer of a
/// share's mark, what the Sharing page lists, the partner test, the
/// receiver's settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StatementCounter counter;
  late AppDatabase db;
  late SettingsService settings;
  late PairingService pairing;
  late CalendarEventService events;
  late CategoryService categories;
  late _FakeSyncSource sync;
  late List<(String, String?)> eventMarks;
  late List<(String, String?)> categoryMarks;
  late List<(String, String?)> folderMarks;
  late int runs;
  late int sharedReads;
  late int reconciles;
  late int foldersChanged;

  /// The category write, counted from one, that throws instead of writing.
  int? failingCategoryWrite;

  /// When set, the shared read the service asks for lasts until it
  /// completes.
  Completer<void>? sharedReadGate;
  final day = DateTime.utc(2026, 6, 1);

  Future<void> pairWith({String? name = 'Maria', String pairId = 'pair-1'}) =>
      settings.setPairingSettings(
        PairingSettings(
          pairId: pairId,
          accountUid: 'me',
          partnerUid: 'maria-uid',
          partnerName: name,
        ),
      );

  /// The service over the real catalogue and events of [db]; every mark
  /// writer recorded on its way to the app's — the DAO's — a folder's
  /// answering true.
  Future<ShareService> open({
    FakePairingGateway? gateway,
    AppUser? user = const AppUser(uid: 'me'),
  }) async {
    categories = await CategoryService.forTesting(db);
    events = await CalendarEventService.forTesting(db);
    pairing = await PairingService.forTesting(
      auth: FakeAuthService(user: user),
      gateway: gateway ?? FakePairingGateway(),
      settings: settings,
    );
    return ShareService.forTesting(
      db: db,
      settings: settings,
      pairing: pairing,
      sync: sync,
      markEvent: (id, pairId) {
        eventMarks.add((id, pairId));
        return db.calendarEventDao.setSharedPair(id, pairId);
      },
      markCategory: (id, pairId) {
        categoryMarks.add((id, pairId));
        if (categoryMarks.length == failingCategoryWrite) {
          throw StateError('the disk is full');
        }
        return db.calendarCategoryDao.setSharedPair(id, pairId);
      },
      markFolder: (id, pairId) async {
        folderMarks.add((id, pairId));
        return true;
      },
      foldersChanged: () => foldersChanged++,
      requestRun: () async => runs++,
      requestSharedRead: () async {
        sharedReads++;
        await sharedReadGate?.future;
      },
      reconcileAlerts: () async => reconciles++,
    );
  }

  Future<void> event(String id, {String category = 'general'}) => events.upsert(
    CalendarEvent(id: id, title: id, categoryId: category, startDate: day),
  );

  Future<String> custom(String name) async => (await categories.create(
    name: name,
    colorValue: 0xFF336699,
    iconKey: 'event',
  )).id;

  CalendarEvent cached(String id) =>
      events.events.firstWhere((event) => event.id == id);

  /// Every mark the three tables hold, as `table/id`.
  Future<Set<String>> marks() async => {
    for (final table in ['calendar_categories', 'calendar_events', 'folders'])
      for (final row
          in await db
              .customSelect(
                'SELECT id FROM $table WHERE shared_pair IS NOT NULL',
              )
              .get())
        '$table/${row.read<String>('id')}',
  };

  Future<Set<String>> queued() async => {
    for (final entry in await db.syncOutboxDao.pending())
      '${entry.syncedTable}/${entry.rowKey}',
  };

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    settings = SettingsService.forTesting(db);
    sync = _FakeSyncSource();
    eventMarks = [];
    categoryMarks = [];
    folderMarks = [];
    runs = 0;
    sharedReads = 0;
    reconciles = 0;
    foldersChanged = 0;
    failingCategoryWrite = null;
    sharedReadGate = null;
  });

  tearDown(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    CalendarEventService.reset();
    CategoryService.reset();
    await db.close();
  });

  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [AppUser(uid: 'maria-uid', displayName: 'Maria')],
  );

  group('availability', () {
    test('an account that never paired is not paired, and the sync '
        'settings are never asked', () async {
      final share = await open();

      expect(share.availability, const ShareNotPaired());
      expect(share.availability.audience, isNull);
      expect(sync.asks, 0);
    });

    test(
      'paired and syncing is ready, with the partner as the audience',
      () async {
        await pairWith();
        final share = await open();

        expect(share.availability, const ShareReady(audience));
      },
    );

    test('paired on a database that does not sync is not syncing, with the '
        'same audience', () async {
      await pairWith();
      sync.bound = false;
      final share = await open();

      expect(share.availability, const ShareNotSyncing(audience));
    });

    test(
      'a partner who published no name leaves the name to the surface',
      () async {
        await pairWith(name: null);
        final share = await open();

        expect(share.availability.audience!.displayName, isNull);
        expect(share.availability.audience!.members.single.uid, 'maria-uid');
      },
    );

    test("a pair another account stored on this database is not this "
        "account's, and the sync settings are never asked", () async {
      await pairWith();
      final share = await open(user: const AppUser(uid: 'someone-else'));

      expect(share.availability, const ShareNotPaired());
      expect(sync.asks, 0);
    });

    test('a stored pair with nobody signed in is not paired', () async {
      await pairWith();
      final share = await open(user: null);

      expect(share.availability, const ShareNotPaired());
    });

    test('a change heard while the first evaluation runs is not overwritten '
        'by it', () async {
      await pairWith();
      final gates = <Completer<bool>>[];
      sync.gate = gates;
      final opening = open();
      await pumpEventQueue();
      expect(gates, hasLength(1), reason: 'the first evaluation is parked');

      sync.flip(false);
      await pumpEventQueue();
      expect(gates, hasLength(2));
      gates[1].complete(false);
      await pumpEventQueue();
      gates[0].complete(true);
      final share = await opening;

      expect(share.availability, const ShareNotSyncing(audience));
    });

    test('a first evaluation that throws leaves nothing listening', () async {
      await pairWith();
      sync.failing = true;

      await expectLater(open(), throwsStateError);

      expect(sync.heard, isFalse);
      sync.failing = false;
      final share = await open();
      expect(share.availability, const ShareReady(audience));
      expect(sync.heard, isTrue);
    });

    test('changes replays the current value to every new listener', () async {
      await pairWith();
      final share = await open();

      final first = await share.changes.first;
      final second = await share.changes.first;

      expect(first, const ShareReady(audience));
      expect(second, const ShareReady(audience));
    });

    test('a bind or an unbind reaches every listener once', () async {
      await pairWith();
      final share = await open();
      final seen = <ShareAvailability>[];
      final subscription = share.changes.listen(seen.add);
      await pumpEventQueue();

      sync.flip(false);
      await pumpEventQueue();
      sync.flip(false);
      await pumpEventQueue();

      expect(seen, const [ShareReady(audience), ShareNotSyncing(audience)]);
      expect(share.availability, const ShareNotSyncing(audience));
      await subscription.cancel();
    });

    test('a pairing that ends is heard as not paired', () async {
      await pairWith();
      final share = await open();
      final seen = <ShareAvailability>[];
      final subscription = share.changes.listen(seen.add);
      await pumpEventQueue();

      await pairing.forget();
      await pumpEventQueue();

      expect(seen.last, const ShareNotPaired());
      await subscription.cancel();
    });

    test('a pairing made and ended on this device is heard at once, both '
        'ways', () async {
      final gateway = FakePairingGateway();
      await gateway.createInvite(
        code: 'ABCD2345',
        creatorUid: 'maria-uid',
        lifetime: PairingService.inviteLifetime,
      );
      final share = await open(gateway: gateway);
      final seen = <ShareAvailability>[];
      final subscription = share.changes.listen(seen.add);
      await pumpEventQueue();

      await pairing.redeem('ABCD-2345');
      await pumpEventQueue();
      expect(share.availability, isA<ShareReady>());
      expect(share.availability.audience!.members.single.uid, 'maria-uid');

      await pairing.unpair();
      await pumpEventQueue();
      expect(share.availability, const ShareNotPaired());
      expect(seen.map((a) => a.runtimeType), [
        ShareNotPaired,
        ShareReady,
        ShareNotPaired,
      ]);
      await subscription.cancel();
    });

    test('a database switch drops the service and closes its stream', () async {
      await pairWith();
      final share = await open();
      final done = Completer<void>();
      share.changes.listen(null, onDone: done.complete);

      DatabaseLifecycle.notifyDatabaseSwitching();

      await done.future.timeout(const Duration(seconds: 5));
    });
  });

  group('the share writes', () {
    test('sharing an event writes its mark under the pair, says what it '
        'changed, and asks for the run that sends it', () async {
      await pairWith();
      final share = await open();
      await event('e1');

      final shared = await share.setEventShared('e1', true);
      expect(shared.sharedEvents.single.id, 'e1');
      expect(cached('e1').markedShared, isTrue);
      final unshared = await share.setEventShared('e1', false);
      expect(unshared.unsharedEvents.single.id, 'e1');
      expect(cached('e1').markedShared, isFalse);

      expect(eventMarks, [('e1', 'pair-1'), ('e1', null)]);
      await pumpEventQueue();
      expect(runs, 2);
    });

    test('a folder takes the same path', () async {
      await pairWith();
      final share = await open();

      expect(await share.setFolderShared('f1', true), isTrue);

      expect(folderMarks, [('f1', 'pair-1')]);
      await pumpEventQueue();
      expect(runs, 1);
    });

    test('a write that changed nothing says so and asks for no run', () async {
      await pairWith();
      final share = await open();
      await event('e1');
      await share.setEventShared('e1', true);
      await pumpEventQueue();
      runs = 0;

      expect(await share.setEventShared('e1', true), ShareChange.none);
      expect(await share.setEventShared('missing', false), ShareChange.none);

      await pumpEventQueue();
      expect(runs, 0);
    });

    test('refused, with no write, unless ready', () async {
      final share = await open();
      await expectLater(
        share.setEventShared('e1', true),
        throwsA(
          isA<ShareRefused>().having(
            (refused) => refused.availability,
            'availability',
            const ShareNotPaired(),
          ),
        ),
      );

      await pairWith();
      sync.bound = false;
      await expectLater(
        share.setFolderShared('f1', true),
        throwsA(isA<ShareRefused>()),
      );
      await expectLater(
        share.setCategoriesShared({'gym'}),
        throwsA(isA<ShareRefused>()),
      );

      expect(eventMarks, isEmpty);
      expect(categoryMarks, isEmpty);
      expect(folderMarks, isEmpty);
      expect(runs, 0);
    });

    test('availability is read afresh at the write, not taken from the last '
        'change heard', () async {
      await pairWith();
      sync.bound = false;
      final share = await open();
      await event('e1');
      expect(share.availability, const ShareNotSyncing(audience));

      // Bound since, and nothing announced it.
      sync.bound = true;

      expect((await share.setEventShared('e1', true)).isEmpty, isFalse);
      expect(eventMarks.single, ('e1', 'pair-1'));
      expect(share.availability, const ShareReady(audience));
    });

    test('over the real event service, the mark is the event\'s', () async {
      await pairWith();
      final share = await open();
      await event('e1');

      await share.setEventShared('e1', true);

      final row = (await db.calendarEventDao.getByIdsIncludingDeleted([
        'e1',
      ])).single;
      expect(row.sharedPair, 'pair-1');
    });
  });

  group('what I share', () {
    test('a category\'s mark and an event\'s own load with the rows, and '
        'one helper says what shares an event: its own mark first, else its '
        'category\'s by the stored id', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      await event('own', category: work);
      await event('through', category: work);
      await event('private');
      await event('dangling', category: 'nowhere');
      await share.setCategoryShared(work, true);
      await share.setEventShared('own', true);
      await share.setCategoryShared('other', true);

      // Read from the store, as a fresh session would.
      CalendarEventService.reset();
      CategoryService.reset();
      categories = await CategoryService.forTesting(db);
      events = await CalendarEventService.forTesting(db);

      expect(CalendarCategories.byId(work)!.sharedByMe, isTrue);
      expect(CalendarCategories.byId('gym')!.sharedByMe, isFalse);
      expect(cached('own').markedShared, isTrue);
      expect(cached('through').markedShared, isFalse);
      expect(CalendarCategories.shareOf(cached('own')), EventShareVia.own);
      expect(
        CalendarCategories.shareOf(cached('through')),
        EventShareVia.category,
      );
      expect(CalendarCategories.shareOf(cached('private')), isNull);
      // Drawn under Other, which is shared; the grant is the stored id's.
      expect(CalendarCategories.resolve('nowhere').id, 'other');
      expect(CalendarCategories.shareOf(cached('dangling')), isNull);
    });

    test('a save of the model never writes the mark, and the cache keeps '
        'what the store holds: an edit stays shared, a copy under a new id '
        'is private', () async {
      await pairWith();
      final share = await open();
      await event('e1');
      await share.setEventShared('e1', true);

      await events.upsert(
        cached('e1').copyWith(title: 'Renamed', markedShared: false),
      );
      expect(cached('e1').markedShared, isTrue);

      await events.upsert(cached('e1').copyWith(id: 'copy'));
      expect(cached('copy').markedShared, isFalse);
      expect(
        (await db.calendarEventDao.getByIdsIncludingDeleted([
          'copy',
        ])).single.sharedPair,
        isNull,
      );
    });

    test('sharing a category says which; un-sharing it says how many of its '
        'events stay shared on their own (C10)', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      for (final id in ['a', 'b', 'c']) {
        await event(id, category: work);
      }
      await share.setEventShared('a', true);
      await share.setEventShared('b', true);

      final shared = await share.setCategoryShared(work, true);
      expect(shared.sharedCategories.single.id, work);
      expect(shared.keptOnTheirOwn, 0);

      final unshared = await share.setCategoryShared(work, false);
      expect(unshared.unsharedCategories.single.id, work);
      expect(unshared.keptOnTheirOwn, 2);
      expect(CalendarCategories.byId(work)!.sharedByMe, isFalse);
    });

    test('the tick sheet\'s set is diffed against the marks: one write per '
        'category that changes, one change for the snackbar', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      final travel = await custom('Travel');
      await share.setCategoriesShared({work, 'gym'});
      categoryMarks.clear();

      final change = await share.setCategoriesShared({work, travel});

      expect(categoryMarks.toSet(), {('gym', null), (travel, 'pair-1')});
      expect(change.sharedCategories.map((c) => c.id), [travel]);
      expect(change.unsharedCategories.map((c) => c.id), ['gym']);
      expect(await share.setCategoriesShared({work, travel}), ShareChange.none);
      expect(
        (await share.setCategoriesShared(
          const {},
        )).unsharedCategories.map((c) => c.id),
        unorderedEquals([work, travel]),
      );
    });

    test('undo writes back exactly what the change wrote', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      await event('e1');
      await share.setCategoriesShared({'gym'});
      final change = await share.setCategoriesShared({work});
      final eventShared = await share.setEventShared('e1', true);

      final undone = await share.undo(change);
      expect(undone.sharedCategories.map((c) => c.id), ['gym']);
      expect(undone.unsharedCategories.map((c) => c.id), [work]);
      await share.undo(eventShared);

      expect(await marks(), {'calendar_categories/gym'});
      expect(CalendarCategories.byId('gym')!.sharedByMe, isTrue);
      expect(CalendarCategories.byId(work)!.sharedByMe, isFalse);
      expect(cached('e1').markedShared, isFalse);
    });

    test('a mark set under the pair clears another pair\'s marks in the '
        'database, and every cache hears of it', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      await event('old');
      await event('e1');
      // Left by an earlier pair, written past the service.
      await categories.setShared(work, 'pair-0');
      await events.setShared('old', 'pair-0');
      expect(CalendarCategories.byId(work)!.sharedByMe, isTrue);
      expect(cached('old').markedShared, isTrue);

      await share.setEventShared('e1', true);

      expect(await marks(), {'calendar_events/e1'});
      expect(CalendarCategories.byId(work)!.sharedByMe, isFalse);
      expect(cached('old').markedShared, isFalse);
      expect(cached('e1').markedShared, isTrue);
      expect(foldersChanged, greaterThan(0));
    });

    test('each writer refreshes its own cache when it clears another pair\'s '
        'marks beside the one it sets', () async {
      await open();
      final work = await custom('Work');
      final travel = await custom('Travel');
      await event('a');
      await event('b');
      await categories.setShared(work, 'pair-0');
      await events.setShared('a', 'pair-0');

      await categories.setShared(travel, 'pair-1');
      await events.setShared('b', 'pair-1');

      expect(CalendarCategories.byId(work)!.sharedByMe, isFalse);
      expect(CalendarCategories.byId(travel)!.sharedByMe, isTrue);
      expect(cached('a').markedShared, isFalse);
      expect(cached('b').markedShared, isTrue);
    });

    test(
      'stopAll clears every mark of the three tables as one act, queues '
      'each cleared row, refreshes the caches and asks for the run',
      () async {
        await pairWith();
        final share = await open();
        final work = await custom('Work');
        await event('e1');
        await share.setCategoryShared(work, true);
        await share.setEventShared('e1', true);
        final folder = await db.folderDao.createFolder(name: 'Shelf');
        await db.folderDao.setSharedPair(folder.id, 'pair-1');
        await db.syncOutboxDao.clear();
        await pumpEventQueue();
        runs = 0;

        expect(await share.stopAll(), 3);

        expect(await marks(), isEmpty);
        expect(
          await queued(),
          containsAll([
            'calendar_categories/$work',
            'calendar_events/e1',
            'folders/${folder.id}',
          ]),
        );
        expect(CalendarCategories.byId(work)!.sharedByMe, isFalse);
        expect(cached('e1').markedShared, isFalse);
        await pumpEventQueue();
        expect(runs, 1);
        expect(await share.stopAll(), 0);
      },
    );

    test('a shared event deleted shares nothing a person can see — the '
        'overview says nothing is shared — and stopping everything still '
        'clears its mark and sends it', () async {
      await pairWith();
      final share = await open();
      await event('e1');
      await share.setEventShared('e1', true);
      await events.deleteById('e1');
      await db.syncOutboxDao.clear();

      final overview = await share.overview();

      expect(overview.events, isEmpty);
      expect(overview.anyMark, isFalse);
      expect(overview.sharesAnything, isFalse);
      expect(await share.stopAll(), 1);
      expect(await marks(), isEmpty);
      expect(await queued(), contains('calendar_events/e1'));
    });

    test('a switch-off that writes nothing but mends a flag the cache held '
        'stale tells the calendar; one that changes nothing tells it '
        'nothing', () async {
      await pairWith();
      final share = await open();
      await event('e1');
      await share.setEventShared('e1', true);
      // Cleared under the cache, as the reader clears an old pair's marks.
      await db.folderDao.clearSharesExcept(null);
      expect(cached('e1').markedShared, isTrue);
      final heard = <Object>[];
      final heardSub = CalendarEventService.externalChanges.listen(heard.add);
      addTearDown(heardSub.cancel);

      expect(await share.setEventShared('e1', false), ShareChange.none);
      await pumpEventQueue();

      expect(cached('e1').markedShared, isFalse);
      expect(heard, hasLength(1));

      heard.clear();
      expect(await share.setEventShared('e1', false), ShareChange.none);
      await pumpEventQueue();
      expect(heard, isEmpty);
    });

    test('an act stored is never reported failed by what is counted after '
        'it: with no calendar to count, none are kept, and the change stands '
        'for its Undo', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      await event('a', category: work);
      await share.setEventShared('a', true);
      await share.setCategoryShared(work, true);
      // The calendar let go of; under test no plugin answers for the
      // database's path, so it cannot be opened again.
      CalendarEventService.reset();

      final change = await share.setCategoryShared(work, false);

      expect(change.unsharedCategories.map((c) => c.id), [work]);
      expect(change.keptOnTheirOwn, 0);
      expect(await marks(), {'calendar_events/a'});
    });

    test('an act of several writes is whole: the second write throwing '
        'leaves nothing shared, and the act fails', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      final travel = await custom('Travel');
      await pumpEventQueue();
      runs = 0;
      failingCategoryWrite = 2;

      await expectLater(
        share.setCategoriesShared({work, travel}),
        throwsA(isA<StateError>()),
      );

      expect(categoryMarks, hasLength(2));
      expect(await marks(), isEmpty);
      expect(CalendarCategories.byId(work)!.sharedByMe, isFalse);
      expect(CalendarCategories.byId(travel)!.sharedByMe, isFalse);
      await pumpEventQueue();
      expect(runs, 0);
    });

    test('an undo of several rows is whole too', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      final travel = await custom('Travel');
      final change = await share.setCategoriesShared({work, travel});
      categoryMarks.clear();
      failingCategoryWrite = 2;

      await expectLater(share.undo(change), throwsA(isA<StateError>()));

      expect(await marks(), {
        'calendar_categories/$work',
        'calendar_categories/$travel',
      });
      expect(CalendarCategories.byId(work)!.sharedByMe, isTrue);
      expect(CalendarCategories.byId(travel)!.sharedByMe, isTrue);
    });

    test('an act reads each cache again once', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      await event('e1');
      int catalogueReads() => counter.statements
          .where(
            (sql) =>
                sql.contains('FROM "calendar_categories"') &&
                sql.contains('ORDER BY'),
          )
          .length;
      int markReads() => counter.statements
          .where(
            (sql) => sql.startsWith(
              'SELECT id FROM calendar_events WHERE shared_pair IS NOT NULL',
            ),
          )
          .length;

      counter.reset();
      await share.setCategoryShared(work, true);
      expect((catalogueReads(), markReads()), (1, 1));

      counter.reset();
      await share.setEventShared('e1', true);
      expect((catalogueReads(), markReads()), (1, 1));
    });
  });

  group('the overview', () {
    test('lists mine, the partner\'s and what the page says, from local '
        'reads', () async {
      await pairWith();
      final share = await open();
      final work = await custom('Work');
      await event('inWork', category: work);
      await event('alone');
      await share.setCategoryShared(work, true);
      await share.setCategoryShared('gym', true);
      await share.setEventShared('inWork', true);
      await share.setEventShared('alone', true);
      // The partner's own category, two events in what they share, one
      // shared singly from a category they keep private.
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: 'p1',
          name: 'Their trips',
          colorValue: 0xFF336699,
          iconKey: 'event',
          isBuiltIn: const Value(false),
          createdAt: day,
          updatedAt: day,
        ),
      );
      await event('t1', category: 'p1');
      await event('t2', category: 'cardio');
      await event('t3');
      await db.customStatement(
        "UPDATE calendar_categories SET owner_id = 'partner' WHERE id = 'p1'",
      );
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = 'partner' "
        "WHERE id IN ('t1', 't2', 't3')",
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      await db.syncDao.setValue(SyncDao.keySharedBuiltIn('cardio'), '1');
      await db.syncDao.setValue(
        SyncDao.keySharedRefused('calendar_events', 'x'),
        '1',
      );
      await db.syncDao.setValue(SyncDao.keySharedReadAt, '1000');
      await db.syncDao.setValue(SyncDao.keySharedReadOkAt, '1000');
      await settings.setShareHiddenCategories({'cardio'});
      await categories.reload();
      await events.reload();
      sync.isOffline = true;

      final overview = await share.overview(withCounts: true);

      expect(overview.categories.map((c) => c.id), ['gym', work]);
      expect(
        {
          for (final shared in overview.events)
            shared.event.id: shared.categoryShared,
        },
        {'inWork': true, 'alone': false},
      );
      expect(overview.partnerCategories, [
        PartnerSharedCategory(
          category: CalendarCategories.byId('p1')!,
          joinsMine: false,
          shown: true,
          eventCount: 1,
        ),
        PartnerSharedCategory(
          category: CalendarCategories.byId('cardio')!,
          joinsMine: true,
          shown: false,
          eventCount: 1,
        ),
      ]);
      expect(overview.partnerEvents.map((e) => e.id), ['t3']);
      expect(overview.readAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(overview.readFailed, isFalse);
      expect(overview.sending, isTrue);
      expect(overview.offline, isTrue);
      expect(overview.partnerNewerWire, isFalse);
      expect(overview.refusedCount, 1);
      expect(overview.sharesAnything, isTrue);
      // The tick sheet's counts: mine only, the partner's three left out.
      expect(overview.eventCounts, {work: 1, 'general': 1});
    });

    test('a summary\'s overview — the Pairing row\'s — reads no counts: the '
        'grouped count over every event is the Sharing page\'s alone', () async {
      await pairWith();
      final share = await open();
      await event('e1');
      counter.reset();

      final summary = await share.overview();

      expect(summary.eventCounts, isEmpty);
      expect(counter.matching('GROUP BY'), isEmpty);
      expect((await share.overview(withCounts: true)).eventCounts, {
        'general': 1,
      });
    });

    test('says "Could not check" only after a failure newer than the last '
        'completed read — never for an install that wrote only the old '
        'stamp — and when the partner writes a newer wire', () async {
      await pairWith();
      final share = await open();
      await db.syncDao.setValue(SyncDao.keySharedReadAt, '2000');
      await db.syncDao.setValue(SyncDao.keySharedNewerWire, '99');
      await db.syncOutboxDao.clear();

      final upgraded = await share.overview();
      expect(upgraded.readAt, isNull);
      expect(upgraded.readFailed, isFalse);
      expect(upgraded.sending, isFalse);
      expect(upgraded.partnerNewerWire, isTrue);
      expect(upgraded.sharesAnything, isFalse);

      await db.syncDao.setValue(SyncDao.keySharedReadOkAt, '1000');
      await db.syncDao.setValue(SyncDao.keySharedReadFailedAt, '2000');
      final failed = await share.overview();
      expect(failed.readAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(failed.readFailed, isTrue);

      await db.syncDao.setValue(SyncDao.keySharedReadOkAt, '3000');
      final recovered = await share.overview();
      expect(recovered.readAt, DateTime.fromMillisecondsSinceEpoch(3000));
      expect(recovered.readFailed, isFalse);
    });

    test('"Sending…" is about shares: an ordinary save while paired says '
        'nothing', () async {
      await pairWith();
      final share = await open();

      await event('e1');

      expect(await queued(), contains('calendar_events/e1'));
      expect((await share.overview()).sending, isFalse);
    });

    test('an act is sending until the outbox has drained, across a rebuild '
        'of the service; stopping everything is sending too', () async {
      await pairWith();
      var share = await open();
      await event('e1');
      await event('e2');

      await share.setEventShared('e1', true);
      expect((await share.overview()).sending, isTrue);

      ShareService.reset();
      CalendarEventService.reset();
      CategoryService.reset();
      share = await open();
      expect((await share.overview()).sending, isTrue);

      await db.syncOutboxDao.clear();
      expect((await share.overview()).sending, isFalse);
      expect(await db.syncDao.getValue(SyncDao.keyShareSending), isNull);

      await events.upsert(cached('e2').copyWith(title: 'Renamed'));
      expect((await share.overview()).sending, isFalse);

      await share.stopAll();
      expect((await share.overview()).sending, isTrue);

      // The pair ended: the marker goes with the reader's keys.
      await db.sharedRowDao.removeAll();
      expect(await db.syncDao.getValue(SyncDao.keyShareSending), isNull);
    });

    test('shares anything is the database\'s answer: a shared folder alone '
        'counts', () async {
      await pairWith();
      final share = await open();
      expect((await share.overview()).sharesAnything, isFalse);
      final folder = await db.folderDao.createFolder(name: 'Shelf');
      await db.folderDao.setSharedPair(folder.id, 'pair-1');

      final overview = await share.overview();

      expect(overview.categories, isEmpty);
      expect(overview.events, isEmpty);
      expect(overview.sharesAnything, isTrue);
    });

    test('an account that never paired pays nothing: no statement, no ask '
        'of the sync settings, no run', () async {
      final share = await open();
      counter.reset();

      expect(await share.overview(), ShareOverview.empty);
      await share.refreshShared();

      expect(counter.captured, isEmpty);
      expect(sync.asks, 0);
      await pumpEventQueue();
      expect(runs, 0);
      expect(sharedReads, 0);
    });

    test('refreshShared asks for one shared read while ready, none '
        'otherwise — never the run that pulls or pushes', () async {
      await pairWith();
      sync.bound = false;
      final share = await open();

      await share.refreshShared();
      await pumpEventQueue();
      expect(sharedReads, 0);

      sync.bound = true;
      await share.refreshShared();
      await pumpEventQueue();
      expect(sharedReads, 1);
      expect(runs, 0);
    });

    test('refreshShared completes when the read it asked for has '
        'finished', () async {
      await pairWith();
      final share = await open();
      sharedReadGate = Completer<void>();
      var done = false;

      unawaited(share.refreshShared().then((_) => done = true));
      await pumpEventQueue();
      expect(sharedReads, 1);
      expect(done, isFalse);

      sharedReadGate!.complete();
      await pumpEventQueue();
      expect(done, isTrue);
    });

    test('refreshShared asks nothing within a minute of the last completed '
        'read, and a failure does not start the clock', () async {
      expect(ShareService.sharedReadMinAge, const Duration(minutes: 1));
      await pairWith();
      final share = await open();
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.syncDao.setValue(SyncDao.keySharedReadOkAt, '${now - 30000}');
      await share.refreshShared();
      expect(sharedReads, 0);

      await db.syncDao.setValue(SyncDao.keySharedReadOkAt, '${now - 90000}');
      await db.syncDao.setValue(SyncDao.keySharedReadFailedAt, '$now');
      await share.refreshShared();
      expect(sharedReads, 1);
    });
  });

  test('isFromPartner is true only for a row the partner owns', () async {
    final share = await open();
    for (final id in ['theirs', 'mine']) {
      await event(id);
    }
    await db.customStatement(
      "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
    );
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');

    expect(await share.isFromPartner('calendar_events', 'theirs'), isTrue);
    expect(await share.isFromPartner('calendar_events', 'mine'), isFalse);
  });

  group('the receiver\'s settings', () {
    test('ship as outlined, marked, own alerts, nothing hidden', () async {
      final share = await open();

      expect(await share.eventLook(), ShareEventLook.outlined);
      expect(await share.markMine(), isTrue);
      expect(await share.alerts(), ShareAlerts.own);
      expect(await share.hiddenCategories(), isEmpty);
    });

    test('each round-trips, and the page settings carry the looks', () async {
      final share = await open();

      await share.setEventLook(ShareEventLook.avatar);
      await share.setMarkMine(false);
      await share.setAlerts(ShareAlerts.category);
      await share.setHiddenCategories({'b', 'a'});

      expect(await share.eventLook(), ShareEventLook.avatar);
      expect(await share.markMine(), isFalse);
      expect(await share.alerts(), ShareAlerts.category);
      expect(await share.hiddenCategories(), {'a', 'b'});
      // What the calendar and the overview re-read when they are returned
      // to (`didPopNext`): a look changed on the Sharing page reaches both.
      expect(
        (await settings.getCalendarPageSettings()).share,
        const ShareLook(eventLook: ShareEventLook.avatar, markMine: false),
      );
      expect(
        (await settings.getCalendarOverviewSettings()).share,
        const ShareLook(eventLook: ShareEventLook.avatar, markMine: false),
      );
      expect(
        await share.looks(),
        (await settings.getCalendarPageSettings()).share,
      );

      await share.setHiddenCategories(const {});
      expect(await share.hiddenCategories(), isEmpty);
    });

    test('a change of what may ring runs the alert pass', () async {
      final share = await open();

      await share.setAlerts(ShareAlerts.off);

      expect(reconciles, 1);
    });

    test('an unknown stored value reads as the shipped one', () async {
      await db.userSettingsDao.setValue('share_event_look', 'sparkles');
      await db.userSettingsDao.setValue('share_alerts', 'loud');
      await db.userSettingsDao.setValue('share_hidden_categories', '{bad');
      final share = await open();

      expect(await share.eventLook(), ShareEventLook.outlined);
      expect(await share.alerts(), ShareAlerts.own);
      expect(await share.hiddenCategories(), isEmpty);
    });
  });

  test('a run ends where the engine\'s activity goes back to idle, never at '
      'an idle status between runs', () async {
    final activity = StreamController<SyncActivity>();
    final source = BindingShareSyncSource(
      currentUser: () => null,
      authChanges: const Stream.empty(),
      binding: () async => null,
      bindingChanges: () => const Stream.empty(),
      offline: () async => false,
      activity: () => activity.stream,
    );
    var ended = 0;
    final subscription = source.runsEnded.listen((_) => ended++);

    for (final next in [
      SyncActivity.idle,
      SyncActivity.pulling,
      SyncActivity.pushing,
      SyncActivity.idle,
      SyncActivity.idle,
      SyncActivity.pushing,
      SyncActivity.idle,
    ]) {
      activity.add(next);
    }
    await pumpEventQueue();

    expect(ended, 2);
    await subscription.cancel();
    await activity.close();
  });

  group('what shows on this phone (slice D, §6.4)', () {
    /// The partner's own category `p1` with their `t1`; their `t2` in the
    /// built-in Cardio they share, beside my own `m2` there; their `t3`
    /// shared singly from a category they keep private.
    Future<ShareService> seedPartner() async {
      await pairWith();
      final share = await open();
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: 'p1',
          name: 'Their trips',
          colorValue: 0xFF336699,
          iconKey: 'event',
          isBuiltIn: const Value(false),
          createdAt: day,
          updatedAt: day,
        ),
      );
      await event('t1', category: 'p1');
      await event('t2', category: 'cardio');
      await event('m2', category: 'cardio');
      await event('t3');
      await db.customStatement(
        "UPDATE calendar_categories SET owner_id = 'partner' WHERE id = 'p1'",
      );
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = 'partner' "
        "WHERE id IN ('t1', 't2', 't3')",
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      await db.syncDao.setValue(SyncDao.keySharedBuiltIn('cardio'), '1');
      await categories.reload();
      await events.reload();
      return share;
    }

    Set<String> cachedIds() => {for (final event in events.events) event.id};

    Future<bool> stored(String id) async =>
        (await db
                .customSelect(
                  'SELECT id FROM calendar_events WHERE id = ? '
                  'AND is_deleted = 0',
                  variables: [Variable<String>(id)],
                )
                .get())
            .isNotEmpty;

    PartnerSharedCategory partnerRow(ShareOverview overview, String id) =>
        overview.partnerCategories.firstWhere((row) => row.category.id == id);

    test('hiding one of theirs takes its events out of what every surface '
        'reads, at once; the rows stay stored, nothing leaves the phone, and '
        'the alert pass runs', () async {
      final share = await seedPartner();
      expect(CalendarCategories.partnerShown.map((c) => c.id), ['p1']);
      final announced = <CalendarExternalChange>[];
      final listening = CalendarEventService.externalChanges.listen(
        announced.add,
      );
      addTearDown(listening.cancel);
      final outbox = await queued();

      await share.setCategoryShown('p1', false);

      expect(cachedIds(), {'t2', 'm2', 't3'});
      expect(await stored('t1'), isTrue);
      expect(CalendarCategories.partnerShown, isEmpty);
      expect(CalendarCategories.partner.map((c) => c.id), ['p1']);
      expect(CalendarCategories.resolve('p1').name, 'Their trips');
      expect(await settings.getShareHiddenCategories(), {'p1'});
      expect(reconciles, 1);
      await pumpEventQueue();
      expect(announced.single.cacheCurrent, isTrue);
      expect(await queued(), outbox, reason: 'a choice of this phone');
      expect(runs, 0);
      expect(sharedReads, 0);
      final overview = await share.overview();
      expect(partnerRow(overview, 'p1').shown, isFalse);
      expect(
        partnerRow(overview, 'p1').eventCount,
        1,
        reason: 'counted while hidden too',
      );
      expect(overview.partnerEvents.map((e) => e.id), ['t3']);
    });

    test('showing it again brings its events back with one local reload, no '
        'read of the network', () async {
      final share = await seedPartner();
      await share.setCategoryShown('p1', false);
      counter.reset();

      await share.setCategoryShown('p1', true);

      expect(cachedIds(), {'t1', 't2', 'm2', 't3'});
      expect(CalendarCategories.partnerShown.map((c) => c.id), ['p1']);
      expect(await settings.getShareHiddenCategories(), isEmpty);
      expect(counter.matching('FROM "calendar_events"'), hasLength(1));
      expect(runs, 0);
      expect(sharedReads, 0);
      expect(reconciles, 2);
      expect(partnerRow(await share.overview(), 'p1').shown, isTrue);
    });

    test('a shared built-in hides the partner\'s half alone: my own events '
        'in it stay, and it is never one of the partner\'s shown', () async {
      final share = await seedPartner();

      await share.setCategoryShown('cardio', false);

      expect(cachedIds(), {'t1', 'm2', 't3'});
      expect(CalendarCategories.partnerShown.map((c) => c.id), ['p1']);
      final row = partnerRow(await share.overview(), 'cardio');
      expect(row.joinsMine, isTrue);
      expect(row.shown, isFalse);
      expect(row.eventCount, 1);
    });

    test('a pull that changes a hidden event keeps it out of the cache, and '
        'it comes back as it now stands', () async {
      final share = await seedPartner();
      await share.setCategoryShown('p1', false);
      // As the shared reader writes: the one writer the fences let through.
      await db.sharedRowDao.writing(
        () => db.customStatement(
          "UPDATE calendar_events SET title = 'Moved' WHERE id = 't1'",
        ),
      );

      expect(await CalendarEventService.applyMerged({'t1'}), isTrue);
      expect(cachedIds(), isNot(contains('t1')));

      await share.setCategoryShown('p1', true);
      expect(cached('t1').title, 'Moved');
    });

    test(
      'asking for what already stands writes nothing and runs no pass',
      () async {
        final share = await seedPartner();

        await share.setCategoryShown('p1', true);

        expect(reconciles, 0);
        expect(
          await db.userSettingsDao.getValue(SettingsKeys.shareHiddenCategories),
          isNull,
        );
      },
    );

    test('two switches flipped at once both hold', () async {
      final share = await seedPartner();

      await Future.wait([
        share.setCategoryShown('p1', false),
        share.setCategoryShown('cardio', false),
      ]);

      expect(await settings.getShareHiddenCategories(), {'p1', 'cardio'});
      expect(cachedIds(), {'m2', 't3'});
    });

    group('what a load costs', () {
      int hiddenReads() => [
        for (final statement in counter.captured)
          if (statement.args.contains(SettingsKeys.shareHiddenCategories))
            statement,
      ].length;

      test('an account that never paired reads nothing new', () async {
        await open();
        await event('mine');
        await settings.setShareHiddenCategories({'general'});
        counter.reset();

        await events.reload();
        await categories.reload();

        expect(hiddenReads(), 0);
        expect(cachedIds(), {'mine'});
      });

      test('a paired one reads the hidden set once per load, and once per '
          'catalogue load while it holds one of the partner\'s', () async {
        await seedPartner();

        counter.reset();
        await events.reload();
        expect(hiddenReads(), 1);

        counter.reset();
        await categories.reload();
        expect(hiddenReads(), 1);

        await db.sharedRowDao.writing(
          () => db.customStatement(
            "DELETE FROM calendar_categories WHERE id = 'p1'",
          ),
        );
        counter.reset();
        await categories.reload();
        expect(hiddenReads(), 0);
      });
    });
  });

  test('the fake replays its current value to every new listener, as the '
      'service does', () async {
    final fake = FakeShareService(availability: const ShareReady(audience));

    expect(await fake.changes.first, const ShareReady(audience));
    fake.emit(const ShareNotPaired());
    expect(await fake.changes.first, const ShareNotPaired());
  });
}
