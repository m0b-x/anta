import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/controllers/guide_setup_reader.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';

import '../database/support/db_test_support.dart';
import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';

/// A gateway that is the network: any call to it fails the test's count.
class _NoNetwork implements PairingGateway {
  final List<Symbol> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('the setup card asked the network');
  }
}

/// A share service whose next [overview] answers what it held when asked,
/// but only once [overviewHold] completes.
class _HeldShareService extends FakeShareService {
  _HeldShareService(ShareAvailability availability)
    : super(availability: availability);

  Completer<void>? overviewHold;

  @override
  Future<ShareOverview> overview({bool withCounts = false}) async {
    final answer = super.overview(withCounts: withCounts);
    final gate = overviewHold;
    overviewHold = null;
    if (gate != null) await gate.future;
    return answer;
  }
}

const _maria = ShareAudience(
  id: 'pair-1',
  displayName: 'Maria',
  members: [AppUser(uid: 'maria', displayName: 'Maria')],
);

/// The "Your setup" card's reader (`docs/guide-hub-roadmap.md` D48, §11.6):
/// each fact in each state, what an account that never paired pays for it,
/// the streams it follows and lets go of, and a database switch.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StatementCounter counter;
  late SettingsService settings;
  late FakeAuthService auth;
  late _NoNetwork network;
  late StreamController<PairingStatus> writes;

  // What the sources answer, set per test.
  ShareAvailability? known;
  bool? census;
  late FakeShareService share;
  late int pairReads;
  late int bindingReads;
  late int shareOpens;

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    settings = SettingsService.forTesting(db);
    auth = FakeAuthService(user: userA);
    network = _NoNetwork();
    writes = StreamController<PairingStatus>.broadcast();
    known = null;
    census = null;
    share = FakeShareService();
    pairReads = 0;
    bindingReads = 0;
    shareOpens = 0;
  });

  tearDown(() async {
    await writes.close();
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    await db.close();
  });

  /// The pairing service of this database over what [stored] holds, built
  /// before the reader as the app's surfaces build it.
  Future<PairingService> buildPairing([
    PairingSettings stored = PairingSettings.empty,
  ]) async {
    await settings.setPairingSettings(stored);
    return PairingService.forTesting(
      auth: auth,
      gateway: network,
      settings: settings,
    );
  }

  GuideSetupSources sources() => GuideSetupSources(
    auth: auth,
    storedPairing: () {
      pairReads++;
      return settings.getPairingSettings();
    },
    binding: () {
      bindingReads++;
      return settings.getSyncBinding();
    },
    share: () async {
      shareOpens++;
      return share;
    },
    knownSharing: () => known,
    storedPair: () => census,
    pairingWrites: () => writes.stream,
  );

  Future<GuideSetupReader> started() async {
    final reader = GuideSetupReader(sources())..start();
    await pumpEventQueue();
    return reader;
  }

  group('a build without sync', () {
    test('answers unavailable and reads nothing', () async {
      auth = FakeAuthService(available: false, user: userA);
      final reader = GuideSetupReader(sources());
      expect(reader.value, const GuideSetupFacts.unavailable());
      counter.reset();
      reader.start();
      await pumpEventQueue();

      expect(reader.value, const GuideSetupFacts.unavailable());
      expect((pairReads, bindingReads, shareOpens), (0, 0, 0));
      expect(counter.count, 0);
      expect(writes.hasListener, isFalse);
      reader.dispose();
    });

    test('no identity registered reads as one', () {
      final reader = GuideSetupReader(
        GuideSetupSources(
          auth: null,
          storedPairing: () => throw StateError('asked'),
          binding: () => throw StateError('asked'),
          share: () => throw StateError('asked'),
        ),
      )..start();
      expect(reader.value.unavailable, isTrue);
      reader.dispose();
    });
  });

  test('signed out: every fact known from memory, nothing read', () async {
    auth = FakeAuthService();
    final reader = GuideSetupReader(sources());
    expect(reader.value, GuideSetupFacts.signedOut);
    counter.reset();
    reader.start();
    await pumpEventQueue();

    expect(reader.value, GuideSetupFacts.signedOut);
    expect((pairReads, bindingReads, shareOpens), (0, 0, 0));
    expect(counter.count, 0);
    reader.dispose();
  });

  group('an account that never paired pays for the binding read alone', () {
    test('known from the pairing service: no share service, no network, no '
        'statement but the binding\'s', () async {
      await buildPairing();
      expect(PairingService.pairedInMemory, isFalse);
      counter.reset();
      await settings.getSyncBinding();
      final bindingCost = counter.count;
      expect(bindingCost, greaterThan(0));
      counter.reset();

      final reader = GuideSetupReader(sources());
      // The first frame claims what memory knows and nothing else.
      expect(
        reader.value,
        const GuideSetupFacts(
          signedIn: true,
          accountName: 'Alex',
          paired: false,
          shared: 0,
        ),
      );
      reader.start();
      await pumpEventQueue();

      expect(reader.value.sync, GuideSetupSync.off);
      expect((pairReads, bindingReads, shareOpens), (0, 1, 0));
      expect(network.calls, isEmpty);
      expect(counter.count, bindingCost);
      reader.dispose();
    });

    test('known from the share census, with no pairing service built: none '
        'is built for it', () async {
      census = false;
      final reader = await started();

      expect(reader.value.paired, isFalse);
      expect(PairingService.pairedInMemory, isNull);
      expect((pairReads, bindingReads, shareOpens), (0, 1, 0));
      reader.dispose();
    });

    test('nothing in memory says: the stored pairing is read, no pairing '
        'service built for it and nothing asked of the server', () async {
      final reader = await started();

      expect(reader.value.paired, isFalse);
      expect(
        PairingService.pairedInMemory,
        isNull,
        reason: 'no pairing service built',
      );
      expect((pairReads, bindingReads, shareOpens), (1, 1, 0));
      expect(network.calls, isEmpty);
      reader.dispose();
    });
  });

  group('sync: this database bound to the signed-in account', () {
    Future<GuideSetupFacts> syncingWith(SyncBinding? binding) async {
      await buildPairing();
      await settings.setSyncBinding(binding);
      final reader = await started();
      final facts = reader.value;
      reader.dispose();
      return facts;
    }

    test('bound to hers', () async {
      final facts = await syncingWith(
        SyncBinding(spaceId: 's', ownerUid: userA.uid, accountUid: userA.uid),
      );
      expect(facts.sync, GuideSetupSync.on);
    });

    test('bound to another account\'s', () async {
      final facts = await syncingWith(
        SyncBinding(spaceId: 's', ownerUid: userB.uid, accountUid: userB.uid),
      );
      expect(facts.sync, GuideSetupSync.otherAccount);
    });

    test('not bound', () async {
      expect((await syncingWith(null)).sync, GuideSetupSync.off);
    });

    test('paired and not syncing: the binding says why', () async {
      await buildPairing(
        PairingSettings(pairId: 'pair-1', accountUid: userA.uid),
      );
      await settings.setSyncBinding(
        SyncBinding(spaceId: 's', ownerUid: userB.uid, accountUid: userB.uid),
      );
      share = FakeShareService(availability: const ShareNotSyncing(_maria));
      final reader = await started();
      expect(reader.value.sync, GuideSetupSync.otherAccount);
      expect(reader.value.paired, isTrue);
      reader.dispose();
    });
  });

  group('paired', () {
    setUp(() {
      share = FakeShareService(availability: const ShareReady(_maria))
        ..shareOverview = const ShareOverview(folderCount: 3);
    });

    test('the share service answers the partner, sync and the count', () async {
      await buildPairing(
        PairingSettings(pairId: 'pair-1', accountUid: userA.uid),
      );
      final reader = GuideSetupReader(sources());
      expect(reader.value.paired, isNull, reason: 'whose pair, not known yet');
      expect(reader.value.shared, isNull);
      reader.start();
      await pumpEventQueue();

      expect(
        reader.value,
        const GuideSetupFacts(
          signedIn: true,
          accountName: 'Alex',
          sync: GuideSetupSync.on,
          paired: true,
          partnerName: 'Maria',
          shared: 3,
        ),
      );
      expect((shareOpens, bindingReads), (1, 0));
      // The replay of what the read took asks nothing again.
      expect(share.overviews, 1);
      expect(network.calls, isEmpty);
      reader.dispose();
    });

    test('a refresh with nothing changed asks the overview nothing again; '
        'the share service speaking does', () async {
      await buildPairing(
        PairingSettings(pairId: 'pair-1', accountUid: userA.uid),
      );
      final reader = await started();
      await reader.refresh();
      await reader.refresh();
      expect(share.overviews, 1);
      expect(reader.value.shared, 3);

      share
        ..shareOverview = const ShareOverview(folderCount: 4)
        ..emit(const ShareNotSyncing(_maria));
      await pumpEventQueue();
      expect(share.overviews, 2);
      expect(reader.value.shared, 4);

      // Back from a screen a setup row opened, where a share may have been
      // made that the service's changes never tell of.
      share.shareOverview = const ShareOverview(folderCount: 5);
      reader.stepOpened();
      await reader.refresh();
      expect(share.overviews, 3);
      expect(reader.value.shared, 5);
      reader.dispose();
    });

    test('a step opened while an overview is out drops it: the count it '
        'brings back never lands, and the next read asks again', () async {
      final held = _HeldShareService(const ShareReady(_maria))
        ..shareOverview = const ShareOverview(folderCount: 3);
      share = held;
      await buildPairing(
        PairingSettings(pairId: 'pair-1', accountUid: userA.uid),
      );
      final reader = await started();
      expect(reader.value.shared, 3);
      final counts = <int?>[];
      reader.addListener(() => counts.add(reader.value.shared));

      // A read out on the overview, answering what was shared before.
      final gate = held.overviewHold = Completer<void>();
      share.shareOverview = const ShareOverview(folderCount: 4);
      reader.stepOpened();
      final pending = reader.refresh();
      await pumpEventQueue();
      expect(share.overviews, 2);

      // She opens a step and shares one more while it is out.
      reader.stepOpened();
      share.shareOverview = const ShareOverview(folderCount: 5);
      gate.complete();
      await pending;
      expect(counts, isNot(contains(4)));

      await reader.refresh();
      expect(share.overviews, 3);
      expect(reader.value.shared, 5);
      expect(counts, isNot(contains(4)));
      reader.dispose();
    });

    test('a share service not caught up with the stored pair is followed '
        'until it is: paired, the partner and the count not known', () async {
      await buildPairing(
        PairingSettings(pairId: 'pair-1', accountUid: userA.uid),
      );
      share = FakeShareService();
      final reader = await started();

      expect(reader.value.paired, isTrue);
      expect(reader.value.partnerName, isNull);
      expect(reader.value.shared, isNull);
      expect(share.heard, isTrue);

      share
        ..shareOverview = const ShareOverview(folderCount: 3)
        ..emit(const ShareReady(_maria));
      await pumpEventQueue();
      expect(reader.value.paired, isTrue);
      expect(reader.value.partnerName, 'Maria');
      expect(reader.value.shared, 3);
      reader.dispose();
    });

    test('the share service already built draws the first frame', () async {
      known = const ShareNotSyncing(_maria);
      share.emit(const ShareNotSyncing(_maria));
      final reader = GuideSetupReader(sources());
      // Not syncing, and why not is the binding's to say: the sync fact
      // waits for its read.
      expect(
        reader.value,
        const GuideSetupFacts(
          signedIn: true,
          accountName: 'Alex',
          paired: true,
          partnerName: 'Maria',
        ),
      );
      reader.start();
      await pumpEventQueue();
      expect(reader.value.sync, GuideSetupSync.off);
      expect(reader.value.shared, 3);
      expect(pairReads, 0);
      expect(PairingService.pairedInMemory, isNull);
      reader.dispose();
    });

    test('another account\'s pair on this database is not hers', () async {
      await buildPairing(
        PairingSettings(pairId: 'pair-1', accountUid: userB.uid),
      );
      final reader = await started();

      expect(reader.value.paired, isFalse);
      expect(reader.value.shared, 0);
      expect(shareOpens, 0);
      reader.dispose();
    });
  });

  group('a change on each stream reaches the listeners', () {
    late GuideSetupReader reader;
    late int told;

    setUp(() async {
      await buildPairing();
      reader = await started();
      told = 0;
      reader.addListener(() => told++);
    });

    tearDown(() => reader.dispose());

    test('the account signing out', () async {
      auth.emitAuth(null);
      await pumpEventQueue();
      expect(reader.value, GuideSetupFacts.signedOut);
      expect(told, 1);
    });

    test('the replay of the same account asks nothing again', () async {
      final reads = bindingReads;
      auth.emitAuth(userA);
      await pumpEventQueue();
      expect(bindingReads, reads);
      expect(told, 0);
    });

    test('a pair written, then the share service\'s changes', () async {
      known = const ShareReady(_maria);
      share = FakeShareService(availability: const ShareReady(_maria));
      writes.add(const PairingStatus(pairId: 'pair-1'));
      await pumpEventQueue();
      expect(reader.value.paired, isTrue);
      expect(reader.value.sync, GuideSetupSync.on);

      share.emit(const ShareNotSyncing(_maria));
      await pumpEventQueue();
      expect(reader.value.sync, GuideSetupSync.off);
      expect(reader.value.partnerName, 'Maria');
    });
  });

  test(
    'dispose lets go of everything: a later event notifies nobody',
    () async {
      known = const ShareReady(_maria);
      share = FakeShareService(availability: const ShareReady(_maria));
      final reader = await started();
      expect(share.heard, isTrue);
      expect(writes.hasListener, isTrue);
      var told = 0;
      reader.addListener(() => told++);

      reader.dispose();
      await pumpEventQueue();
      expect(share.heard, isFalse);
      expect(writes.hasListener, isFalse);

      auth.emitAuth(null);
      writes.add(const PairingStatus());
      share.emit(const ShareNotPaired());
      await pumpEventQueue();
      expect(told, 0);
    },
  );

  test('a database switch while alive: the old database\'s share service is '
      'let go of, and the next read asks the new one\'s', () async {
    known = const ShareReady(_maria);
    final first = FakeShareService(availability: const ShareReady(_maria))
      ..shareOverview = const ShareOverview(folderCount: 1);
    share = first;
    final reader = await started();
    expect(reader.value.shared, 1);

    DatabaseLifecycle.notifyDatabaseSwitching();
    final second = FakeShareService(availability: const ShareReady(_maria))
      ..shareOverview = const ShareOverview(folderCount: 5);
    share = second;
    await reader.refresh();
    await pumpEventQueue();

    expect(reader.value.shared, 5);
    expect(first.heard, isFalse);
    expect(second.heard, isTrue);
    final opens = shareOpens;
    first.emit(const ShareNotSyncing(_maria));
    await pumpEventQueue();
    expect(shareOpens, opens);
    expect(reader.value.sync, GuideSetupSync.on);
    reader.dispose();
  });
}
