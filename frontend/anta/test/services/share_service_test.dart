import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';

import '../database/support/db_test_support.dart';
import '../support/fake_share_service.dart';
import 'pairing_support.dart';

/// "This database syncs", decided by the test; every ask counted.
class _FakeSyncSource implements ShareSyncSource {
  bool bound = true;
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
}

/// The facade a share surface reads (`docs/cloud-share-surfaces-roadmap.md`
/// §6.1): availability and its replaying stream, the only writer of a
/// share's mark, the partner test, the receiver's settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SettingsService settings;
  late PairingService pairing;
  late _FakeSyncSource sync;
  late List<(String, String?)> eventMarks;
  late List<(String, String?)> folderMarks;
  late int runs;
  late int reconciles;
  bool markChanges = true;

  Future<void> pairWith({String? name = 'Maria'}) =>
      settings.setPairingSettings(
        PairingSettings(
          pairId: 'pair-1',
          accountUid: 'me',
          partnerUid: 'maria-uid',
          partnerName: name,
        ),
      );

  Future<ShareService> open({
    FakePairingGateway? gateway,
    AppUser? user = const AppUser(uid: 'me'),
  }) async {
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
      markEvent: (id, pairId) async {
        eventMarks.add((id, pairId));
        return markChanges;
      },
      markFolder: (id, pairId) async {
        folderMarks.add((id, pairId));
        return markChanges;
      },
      requestRun: () async => runs++,
      reconcileAlerts: () async => reconciles++,
    );
  }

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    sync = _FakeSyncSource();
    eventMarks = [];
    folderMarks = [];
    runs = 0;
    reconciles = 0;
    markChanges = true;
  });

  tearDown(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
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
    test('sharing an event writes its mark under the pair and asks for the '
        'run that sends it', () async {
      await pairWith();
      final share = await open();

      expect(await share.setEventShared('e1', true), isTrue);
      expect(await share.setEventShared('e1', false), isTrue);

      expect(eventMarks, [('e1', 'pair-1'), ('e1', null)]);
      await pumpEventQueue();
      expect(runs, 2);
    });

    test('a folder takes the same path', () async {
      await pairWith();
      final share = await open();

      await share.setFolderShared('f1', true);

      expect(folderMarks, [('f1', 'pair-1')]);
      await pumpEventQueue();
      expect(runs, 1);
    });

    test('a write that changed nothing asks for no run', () async {
      await pairWith();
      final share = await open();
      markChanges = false;

      expect(await share.setEventShared('e1', true), isFalse);

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

      expect(eventMarks, isEmpty);
      expect(folderMarks, isEmpty);
      expect(runs, 0);
    });

    test('availability is read afresh at the write, not taken from the last '
        'change heard', () async {
      await pairWith();
      sync.bound = false;
      final share = await open();
      expect(share.availability, const ShareNotSyncing(audience));

      // Bound since, and nothing announced it.
      sync.bound = true;

      expect(await share.setEventShared('e1', true), isTrue);
      expect(eventMarks.single, ('e1', 'pair-1'));
      expect(share.availability, const ShareReady(audience));
    });

    test('over the real event service, the mark is the event\'s', () async {
      await pairWith();
      final events = await CalendarEventService.forTesting(db);
      await events.upsert(
        CalendarEvent(
          id: 'e1',
          title: 'Dinner',
          categoryId: 'general',
          startDate: DateTime.utc(2026, 6, 1),
        ),
      );
      pairing = await PairingService.forTesting(
        auth: FakeAuthService(user: const AppUser(uid: 'me')),
        gateway: FakePairingGateway(),
        settings: settings,
      );
      final share = await ShareService.forTesting(
        db: db,
        settings: settings,
        pairing: pairing,
        sync: sync,
        markEvent: events.setShared,
        markFolder: (_, _) async => false,
      );

      await share.setEventShared('e1', true);

      final row = (await db.calendarEventDao.getByIdsIncludingDeleted([
        'e1',
      ])).single;
      expect(row.sharedPair, 'pair-1');
      CalendarEventService.reset();
    });
  });

  test('isFromPartner is true only for a row the partner owns', () async {
    final events = await CalendarEventService.forTesting(db);
    for (final id in ['theirs', 'mine']) {
      await events.upsert(
        CalendarEvent(
          id: id,
          title: id,
          categoryId: 'general',
          startDate: DateTime.utc(2026, 6, 1),
        ),
      );
    }
    await db.customStatement(
      "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
    );
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
    final share = await open();

    expect(await share.isFromPartner('calendar_events', 'theirs'), isTrue);
    expect(await share.isFromPartner('calendar_events', 'mine'), isFalse);
    CalendarEventService.reset();
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
      expect(
        (await settings.getCalendarPageSettings()).share,
        const ShareLook(eventLook: ShareEventLook.avatar, markMine: false),
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

  test('the fake replays its current value to every new listener, as the '
      'service does', () async {
    final fake = FakeShareService(availability: const ShareReady(audience));

    expect(await fake.changes.first, const ShareReady(audience));
    fake.emit(const ShareNotPaired());
    expect(await fake.changes.first, const ShareNotPaired());
  });
}
