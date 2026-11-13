import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/share_service.dart';

import '../support/fake_share_service.dart';

/// An overview read that throws while [failing].
class _UnreadableShare extends FakeShareService {
  _UnreadableShare({super.availability});

  bool failing = true;

  @override
  Future<ShareOverview> overview({bool withCounts = false}) async {
    if (failing) throw StateError('the read failed');
    return super.overview(withCounts: withCounts);
  }
}

/// Every read the bloc makes after a write — the overview, the looks, the
/// alert setting — throws while [failReads].
class _ReadBackFails extends FakeShareService {
  _ReadBackFails({super.availability});

  bool failReads = false;

  @override
  Future<ShareOverview> overview({bool withCounts = false}) async {
    if (failReads) throw StateError('overview read failed');
    return super.overview(withCounts: withCounts);
  }

  @override
  Future<ShareLook> looks() async {
    if (failReads) throw StateError('looks read failed');
    return super.looks();
  }

  @override
  Future<ShareAlerts> alerts() async {
    if (failReads) throw StateError('alerts read failed');
    return super.alerts();
  }
}

/// The Sharing page's bloc: it loads the overview, follows the service's
/// availability and the calendar's changes, and routes the page's intents —
/// every rule stays the service's.
void main() {
  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [],
  );
  const work = CalendarCategory(
    id: 'work',
    name: 'Work',
    colorValue: 0xFF336699,
    iconKey: 'event',
    sortOrder: 0,
    isBuiltIn: false,
    sharedByMe: true,
  );
  const overview = ShareOverview(categories: [work], sending: true);
  const change = ShareChange(unsharedCategories: [work], keptOnTheirOwn: 2);

  late FakeShareService share;
  late StreamController<Object?> calendar;
  late ShareBloc bloc;

  setUp(() {
    share = FakeShareService(availability: const ShareReady(audience))
      ..shareOverview = overview;
    calendar = StreamController<Object?>.broadcast();
    bloc = ShareBloc(
      service: () async => share,
      calendarChanges: calendar.stream,
    );
  });

  tearDown(() async {
    await bloc.close();
    await calendar.close();
  });

  Future<ShareLoaded> settled() async {
    await pumpEventQueue();
    return bloc.state as ShareLoaded;
  }

  test('opening loads the overview and asks for one shared read', () async {
    bloc.add(const ShareOpened());

    final state = await settled();
    expect(state.availability, const ShareReady(audience));
    expect(state.overview, overview);
    expect(state.outcome, isNull);
    expect(share.sharedReads, 1);
  });

  test('a load — Sync & sharing\'s — reads the overview and asks for no '
      'shared read, ready or not', () async {
    bloc.add(const ShareLoadRequested());

    final state = await settled();
    expect(state.availability, const ShareReady(audience));
    expect(state.overview, overview);
    expect(share.overviews, 1);
    expect(share.sharedReads, 0);
  });

  test('not paired: the empty overview, and no shared read', () async {
    share.emit(const ShareNotPaired());

    bloc.add(const ShareOpened());

    final state = await settled();
    expect(state.availability, const ShareNotPaired());
    expect(state.overview, ShareOverview.empty);
    expect(share.sharedReads, 0);
  });

  test('a first load that throws is a failure the page can say; one after '
      'a load keeps what was shown', () async {
    final failing = ShareBloc(
      service: () async => throw StateError('no database'),
      calendarChanges: const Stream.empty(),
    );
    addTearDown(failing.close);
    failing.add(const ShareLoadRequested());
    await pumpEventQueue();
    expect(failing.state, const ShareLoadFailed());

    final unreadable = _UnreadableShare(
      availability: const ShareReady(audience),
    );
    final loaded = ShareBloc(
      service: () async => unreadable,
      calendarChanges: const Stream.empty(),
    );
    addTearDown(loaded.close);
    loaded.add(const ShareLoadRequested());
    await pumpEventQueue();
    expect(loaded.state, const ShareLoadFailed());

    unreadable
      ..failing = false
      ..shareOverview = overview;
    loaded.add(const ShareLoadRequested());
    await pumpEventQueue();
    expect((loaded.state as ShareLoaded).overview, overview);

    unreadable.failing = true;
    loaded.add(const ShareLoadRequested());
    await pumpEventQueue();
    expect((loaded.state as ShareLoaded).overview, overview);
  });

  test('the tick sheet\'s set goes to the service whole, and what it '
      'changed comes back for the snackbar', () async {
    bloc.add(const ShareOpened());
    await settled();
    share.nextChange = change;

    bloc.add(const ShareCategoriesSet({'travel'}));

    final state = await settled();
    expect(share.categorySets, [
      {'travel'},
    ]);
    expect(state.outcome!.act, ShareAct.categoriesSet);
    expect(state.outcome!.change, change);
    expect(state.outcome!.failure, isNull);
  });

  test('an event un-shared, an undo and stop everything each reach the '
      'service, each with an outcome of its own', () async {
    bloc.add(const ShareOpened());
    await settled();

    bloc.add(const ShareEventUnshared('e1'));
    final unshared = (await settled()).outcome!;
    bloc.add(const ShareUndoRequested(change));
    final undone = (await settled()).outcome!;
    bloc.add(const ShareStopAllRequested());
    final stopped = (await settled()).outcome!;

    expect(share.eventShares, [('e1', false)]);
    expect(share.undone, [change]);
    expect(share.stops, 1);
    expect(unshared.act, ShareAct.eventUnshared);
    expect(undone.act, ShareAct.undo);
    expect(stopped.act, ShareAct.stopAll);
    expect(stopped.cleared, 1);
    expect({
      unshared.sequence,
      undone.sequence,
      stopped.sequence,
    }, hasLength(3));
  });

  test('two equal acts in a row are two outcomes', () async {
    bloc.add(const ShareOpened());
    await settled();

    bloc.add(const ShareEventUnshared('e1'));
    final first = (await settled()).outcome!;
    bloc.add(const ShareEventUnshared('e1'));
    final second = (await settled()).outcome!;

    expect(second, isNot(first));
  });

  test('a write refused because sharing is no longer ready says so, and '
      'writes nothing', () async {
    bloc.add(const ShareOpened());
    await settled();
    share.emit(const ShareNotSyncing(audience));
    await settled();

    bloc.add(const ShareCategoriesSet({'travel'}));

    final state = await settled();
    expect(share.categorySets, isEmpty);
    expect(state.outcome!.failure, ShareFailure.refused);
    expect(state.availability, const ShareNotSyncing(audience));
  });

  test('an act\'s outcome is carried whatever the reload after it did: one '
      'that cannot reach the service still carries it', () async {
    var reachable = true;
    final acting = ShareBloc(
      service: () async =>
          reachable ? share : throw StateError('the database switched'),
      calendarChanges: const Stream.empty(),
    );
    addTearDown(acting.close);
    acting.add(const ShareOpened());
    await pumpEventQueue();
    share.nextChange = change;
    final hold = share.hold = Completer<void>();

    acting.add(const ShareCategoriesSet({'travel'}));
    await pumpEventQueue();
    reachable = false;
    hold.complete();
    await pumpEventQueue();

    final outcome = (acting.state as ShareLoaded).outcome;
    expect(outcome?.act, ShareAct.categoriesSet);
    expect(outcome?.change, change);
  });

  test('closing while a write is held completes before the write answers, '
      'and the write still lands', () async {
    bloc.add(const ShareOpened());
    await settled();
    final hold = share.hold = Completer<void>();
    bloc.add(const ShareCategoriesSet({'travel'}));
    await pumpEventQueue();

    var closed = false;
    unawaited(bloc.close().then((_) => closed = true));
    await pumpEventQueue();

    expect(closed, isTrue);
    hold.complete();
    await pumpEventQueue();
    expect(share.categorySets, [
      {'travel'},
    ]);
  });

  test('an Undo still queued behind a running act when the bloc closes is '
      'written through the road an Undo takes past its bloc', () async {
    bloc.add(const ShareOpened());
    await settled();
    final hold = share.hold = Completer<void>();
    bloc.add(const ShareCategoriesSet({'travel'}));
    await pumpEventQueue();
    final orphaned = <ShareChange>[];
    bloc.add(ShareUndoRequested(change, pastBloc: orphaned.add));

    await bloc.close();
    hold.complete();
    await pumpEventQueue();

    expect(orphaned, [change]);
    expect(share.undone, isEmpty, reason: 'written once, by that road');
  });

  test('a change of availability and a change of the calendar each read '
      'the overview again, keeping the last outcome', () async {
    bloc.add(const ShareOpened());
    await settled();
    bloc.add(const ShareEventUnshared('e1'));
    final outcome = (await settled()).outcome;
    final reads = share.overviews;

    share.shareOverview = ShareOverview.empty;
    calendar.add(null);
    final afterCalendar = await settled();
    expect(afterCalendar.overview, ShareOverview.empty);
    expect(afterCalendar.outcome, outcome);

    share.emit(const ShareNotSyncing(audience));
    final afterAvailability = await settled();
    expect(afterAvailability.availability, const ShareNotSyncing(audience));
    expect(share.overviews, reads + 2);
  });

  test('the overview is read again when the shared read the open asked '
      'for has finished', () async {
    final read = Completer<void>();
    share.sharedRead = read;
    bloc.add(const ShareOpened());
    expect((await settled()).overview, overview);

    const after = ShareOverview(categories: [work]);
    share.shareOverview = after;
    read.complete();

    expect((await settled()).overview, after);
  });

  test('while open, the overview is read again as each sync run ends — '
      '"Sending…" goes once the share has left', () async {
    bloc.add(const ShareOpened());
    await settled();

    const sent = ShareOverview(categories: [work]);
    share.shareOverview = sent;
    share.endRun();

    expect((await settled()).overview, sent);
  });

  test('a bloc closed while its service resolves follows nothing and asks '
      'for no read', () async {
    final resolving = Completer<ShareService>();
    final closing = ShareBloc(
      service: () => resolving.future,
      calendarChanges: calendar.stream,
    );
    closing.add(const ShareOpened());
    await pumpEventQueue();
    await closing.close();

    resolving.complete(share);
    await pumpEventQueue();

    expect(share.heard, isFalse);
    expect(share.sharedReads, 0);
    // Heard by a bloc that subscribed after its close, this would add to it.
    share.emit(const ShareNotSyncing(audience));
    share.endRun();
    await pumpEventQueue();
  });

  for (final (name, event) in [
    ('opened', const ShareOpened()),
    ('loaded', const ShareLoadRequested()),
  ]) {
    test('a bloc $name and closed in the same turn subscribes to nothing, '
        'and a later change adds nothing to it', () async {
      final closing = ShareBloc(
        service: () async => share,
        calendarChanges: calendar.stream,
      );
      final errors = <Object>[];
      var listened = true;
      var heard = true;
      // Guarded: what a late subscription adds to the closed bloc throws
      // outside any future the test awaits.
      await runZonedGuarded(() async {
        closing.add(event);
        await closing.close();
        await pumpEventQueue();
        listened = calendar.hasListener;
        heard = share.heard;
        calendar.add(null);
        share.endRun();
        await pumpEventQueue();
      }, (error, _) => errors.add(error));

      expect(listened, isFalse);
      expect(heard, isFalse);
      expect(errors, isEmpty);
      expect(share.sharedReads, 0);
    });
  }

  test('a load — the Pairing row\'s summary — follows the calendar too: a '
      'change reads the overview again, with no shared read', () async {
    bloc.add(const ShareLoadRequested());
    await settled();
    final reads = share.overviews;

    share.shareOverview = ShareOverview.empty;
    calendar.add(null);

    expect((await settled()).overview, ShareOverview.empty);
    expect(share.overviews, reads + 1);
    expect(share.sharedReads, 0);
  });

  test('the tick sheet\'s counts are read for the Sharing page alone: never '
      'by a summary\'s load, on every load once the page opened', () async {
    bloc.add(const ShareLoadRequested());
    await settled();
    calendar.add(null);
    await settled();
    expect(share.countReads, [false, false]);

    share.countReads.clear();
    bloc.add(const ShareOpened());
    await settled();
    calendar.add(null);
    await settled();
    bloc.add(const ShareLoadRequested());
    await settled();

    expect(share.countReads, isNotEmpty);
    expect(share.countReads, everyElement(isTrue));
  });

  test('acts run one at a time, in the order they were added: a second act '
      'that would finish first ends on its own outcome', () async {
    bloc.add(const ShareOpened());
    await settled();
    const second = ShareChange(sharedCategories: [work]);
    final gate = Completer<void>();
    share
      ..hold = gate
      ..nextChange = change;

    bloc.add(const ShareEventUnshared('a'));
    await pumpEventQueue();
    share.nextChange = second;
    bloc.add(const ShareEventUnshared('b'));
    await pumpEventQueue();
    gate.complete();

    final state = await settled();
    expect(share.eventShares, [('a', false), ('b', false)]);
    expect(state.outcome!.change, second);
  });

  group('the receiver\'s settings (slice D)', () {
    test('a load carries the looks and the alert setting as stored, so the '
        'page draws them with no read of its own', () async {
      share
        ..look = ShareEventLook.avatar
        ..mine = false
        ..shareAlerts = ShareAlerts.category;

      bloc.add(const ShareLoadRequested());

      final state = await settled();
      expect(
        state.look,
        const ShareLook(eventLook: ShareEventLook.avatar, markMine: false),
      );
      expect(state.alerts, ShareAlerts.category);
    });

    test('not paired: the shipped values, and no setting is read', () async {
      share
        ..emit(const ShareNotPaired())
        ..look = ShareEventLook.plain;

      bloc.add(const ShareLoadRequested());

      final state = await settled();
      expect(state.look, const ShareLook());
      expect(state.alerts, ShareAlerts.own);
      expect(share.settingsReads, 0);
    });

    test('hiding and showing a category each write at once and read the '
        'overview again', () async {
      bloc.add(const ShareOpened());
      await settled();
      final reads = share.overviews;

      bloc.add(const ShareCategoryShownSet('shifts', shown: false));
      await settled();
      expect(share.hidden, {'shifts'});
      bloc.add(const ShareCategoryShownSet('gym', shown: false));
      await settled();
      bloc.add(const ShareCategoryShownSet('shifts', shown: true));
      final state = await settled();

      expect(share.shownSets, [
        ('shifts', false),
        ('gym', false),
        ('shifts', true),
      ]);
      expect(share.hidden, {'gym'});
      expect(share.overviews, reads + 3);
      expect(state.outcome, isNull, reason: 'no snackbar for a switch');
    });

    test('the look, the mark and the alert setting each write at once, and '
        'the state shows what was written', () async {
      bloc.add(const ShareOpened());
      await settled();

      bloc.add(const ShareEventLookSet(ShareEventLook.plain));
      expect((await settled()).look.eventLook, ShareEventLook.plain);
      bloc.add(const ShareMarkMineSet(false));
      expect((await settled()).look.markMine, isFalse);
      bloc.add(const ShareAlertsSet(ShareAlerts.off));
      final state = await settled();

      expect(state.alerts, ShareAlerts.off);
      expect(share.look, ShareEventLook.plain);
      expect(share.mine, isFalse);
      expect(share.shareAlerts, ShareAlerts.off);
    });

    test('a write that fails leaves the state at what is stored', () async {
      bloc.add(const ShareOpened());
      await settled();
      share.settingsFailure = StateError('disk');

      bloc.add(const ShareEventLookSet(ShareEventLook.avatar));
      bloc.add(const ShareCategoryShownSet('shifts', shown: false));
      final state = await settled();

      expect(state.look.eventLook, ShareEventLook.outlined);
      expect(share.hidden, isEmpty);
      expect(state.outcome, isNull);
    });
  });

  group('what my alerts lose (D30, D33)', () {
    test('the armed count answers what the service counts, and 0 when it '
        'cannot be read', () async {
      share.armedByCategory = {'shifts': 2, 'gym': 1};
      final counted = Completer<int>();
      bloc.add(ShareArmedCountRequested(counted));
      expect(await counted.future, 3);
      expect(share.armedReads, [null]);

      final failing = ShareBloc(
        service: () async => throw StateError('closed'),
        calendarChanges: const Stream.empty(),
      );
      addTearDown(failing.close);
      final none = Completer<int>();
      failing.add(ShareArmedCountRequested(none));
      expect(await none.future, 0);
    });

    test('whether a partner\'s event is still held answers the service, and '
        'yes when it cannot be read', () async {
      share.partnerRows.add('calendar_events/e1');
      final held = Completer<bool>();
      bloc.add(SharePartnerEventHeldRequested('e1', held));
      expect(await held.future, isTrue);
      final gone = Completer<bool>();
      bloc.add(SharePartnerEventHeldRequested('e2', gone));
      expect(await gone.future, isFalse);

      final failing = ShareBloc(
        service: () async => throw StateError('closed'),
        calendarChanges: const Stream.empty(),
      );
      addTearDown(failing.close);
      final unknown = Completer<bool>();
      failing.add(SharePartnerEventHeldRequested('e1', unknown));
      expect(await unknown.future, isTrue);
    });
  });

  group('a setting shows from the tap, before its write has landed', () {
    const shifts = CalendarCategory(
      id: 'shifts',
      name: 'Night shift',
      colorValue: 0xFF3949AB,
      iconKey: 'event',
      sortOrder: 0,
      isBuiltIn: false,
      fromPartner: true,
    );
    const gym = CalendarCategory(
      id: 'gym',
      name: 'Gym',
      colorValue: 0xFF43A047,
      iconKey: 'fitness_center',
      sortOrder: 1,
      isBuiltIn: true,
    );

    /// What storage holds at one moment: the fake answers it as its
    /// overview, whatever the bloc has shown ahead of it.
    ShareOverview stored({bool shiftsShown = true, bool gymShown = true}) =>
        ShareOverview(
          categories: const [work],
          partnerCategories: [
            PartnerSharedCategory(
              category: shifts,
              joinsMine: false,
              shown: shiftsShown,
              eventCount: 18,
            ),
            PartnerSharedCategory(
              category: gym,
              joinsMine: true,
              shown: gymShown,
              eventCount: 9,
            ),
          ],
        );

    bool shownOf(ShareLoaded state, String id) => state
        .overview
        .partnerCategories
        .firstWhere((shared) => shared.category.id == id)
        .shown;

    test('a hidden category reads hidden while its write is still held, '
        'and nothing else moves', () async {
      share.shareOverview = stored();
      bloc.add(const ShareOpened());
      await settled();
      final gate = Completer<void>();
      share.settingsHold = gate;

      bloc.add(const ShareCategoryShownSet('shifts', shown: false));
      final early = await settled();

      expect(share.shownSets, isEmpty, reason: 'the write is still held');
      expect(shownOf(early, 'shifts'), isFalse);
      expect(shownOf(early, 'gym'), isTrue);
      expect(early.overview.categories, const [work]);

      share.shareOverview = stored(shiftsShown: false);
      gate.complete();
      final landed = await settled();
      expect(share.shownSets, [('shifts', false)]);
      expect(shownOf(landed, 'shifts'), isFalse);
    });

    test(
      'a write that fails draws the switch back to what is stored',
      () async {
        share.shareOverview = stored();
        bloc.add(const ShareOpened());
        await settled();
        final gate = Completer<void>();
        share
          ..settingsHold = gate
          ..settingsFailure = StateError('disk');

        bloc.add(const ShareCategoryShownSet('shifts', shown: false));
        expect(shownOf(await settled(), 'shifts'), isFalse);

        gate.complete();
        expect(shownOf(await settled(), 'shifts'), isTrue);
      },
    );

    group('a write that fails, and whose read-back fails too', () {
      late _ReadBackFails failing;
      late ShareBloc reading;

      setUp(() async {
        failing = _ReadBackFails(availability: const ShareReady(audience))
          ..shareOverview = stored()
          ..shareAlerts = ShareAlerts.category;
        reading = ShareBloc(
          service: () async => failing,
          calendarChanges: calendar.stream,
        );
        reading.add(const ShareOpened());
        await pumpEventQueue();
        failing
          ..settingsFailure = StateError('disk')
          ..failReads = true;
      });

      tearDown(() => reading.close());

      test('draws the switch back to what was last read, not to what the '
          'tap showed', () async {
        reading.add(const ShareCategoryShownSet('shifts', shown: false));
        await pumpEventQueue();

        expect(failing.hidden, isEmpty, reason: 'nothing was stored');
        expect(shownOf(reading.state as ShareLoaded, 'shifts'), isTrue);
      });

      test('the look and the alert setting fall back the same way', () async {
        reading
          ..add(const ShareEventLookSet(ShareEventLook.avatar))
          ..add(const ShareAlertsSet(ShareAlerts.off));
        await pumpEventQueue();

        final state = reading.state as ShareLoaded;
        expect(state.look.eventLook, ShareEventLook.outlined);
        expect(state.alerts, ShareAlerts.category);
      });
    });

    test('the read after an earlier write keeps a later switch whose own '
        'write is still on its way', () async {
      share.shareOverview = stored();
      bloc.add(const ShareOpened());
      await settled();
      final first = Completer<void>();
      final second = Completer<void>();

      share.settingsHold = first;
      bloc.add(const ShareCategoryShownSet('shifts', shown: false));
      await pumpEventQueue();
      share.settingsHold = second;
      bloc.add(const ShareCategoryShownSet('gym', shown: false));
      await pumpEventQueue();

      // The first write lands: storage holds it, and not yet the second.
      share.shareOverview = stored(shiftsShown: false);
      first.complete();
      final between = await settled();
      expect(share.shownSets, [('shifts', false)]);
      expect(shownOf(between, 'shifts'), isFalse);
      expect(shownOf(between, 'gym'), isFalse, reason: 'still on its way');

      share.shareOverview = stored(shiftsShown: false, gymShown: false);
      second.complete();
      final landed = await settled();
      expect(share.shownSets, [('shifts', false), ('gym', false)]);
      expect(shownOf(landed, 'gym'), isFalse);
    });

    test('one switch flipped off and on again ends on, whatever the first '
        'write\'s read says in between', () async {
      share.shareOverview = stored();
      bloc.add(const ShareOpened());
      await settled();
      final first = Completer<void>();
      final second = Completer<void>();

      share.settingsHold = first;
      bloc.add(const ShareCategoryShownSet('shifts', shown: false));
      await pumpEventQueue();
      share.settingsHold = second;
      bloc.add(const ShareCategoryShownSet('shifts', shown: true));
      expect(shownOf(await settled(), 'shifts'), isTrue);

      share.shareOverview = stored(shiftsShown: false);
      first.complete();
      expect(shownOf(await settled(), 'shifts'), isTrue);

      share.shareOverview = stored();
      second.complete();
      expect(shownOf(await settled(), 'shifts'), isTrue);
      expect(share.shownSets, [('shifts', false), ('shifts', true)]);
    });

    test('the look, the mark and the alert setting show at once too, each '
        'over the others', () async {
      bloc.add(const ShareOpened());
      await settled();
      final gate = Completer<void>();
      share.settingsHold = gate;

      bloc.add(const ShareEventLookSet(ShareEventLook.avatar));
      bloc.add(const ShareMarkMineSet(false));
      bloc.add(const ShareAlertsSet(ShareAlerts.category));
      final early = await settled();

      expect(share.look, ShareEventLook.outlined, reason: 'still held');
      expect(
        early.look,
        const ShareLook(eventLook: ShareEventLook.avatar, markMine: false),
      );
      expect(early.alerts, ShareAlerts.category);

      gate.complete();
      final landed = await settled();
      expect(share.look, ShareEventLook.avatar);
      expect(
        landed.look,
        const ShareLook(eventLook: ShareEventLook.avatar, markMine: false),
      );
      expect(landed.alerts, ShareAlerts.category);
    });
  });

  group('folders (slice F0)', () {
    const trips = ShareFolderRef(id: 'trips', name: 'Trips');
    const lisbon = ShareFolderRef(id: 'lisbon', name: 'Lisbon');
    const shared = ShareChange(
      sharedFolders: [trips],
      coveredFolders: [lisbon],
    );
    const unshared = ShareChange(unsharedFolders: [trips]);

    test('a folder shared and one un-shared each reach the service, each '
        'with an outcome of its own carrying what it wrote', () async {
      bloc.add(const ShareOpened());
      await settled();

      share.nextChange = shared;
      bloc.add(const ShareFolderShared('trips'));
      final first = (await settled()).outcome!;
      share.nextChange = unshared;
      bloc.add(const ShareFolderUnshared('trips'));
      final second = (await settled()).outcome!;

      expect(share.folderShares, [('trips', true), ('trips', false)]);
      expect(first.act, ShareAct.folderShared);
      expect(first.change, shared);
      expect(second.act, ShareAct.folderUnshared);
      expect(second.change, unshared);
      expect(second.sequence, isNot(first.sequence));
    });

    test('folder acts join the one ordered queue: one held act keeps the '
        'next waiting, and the last outcome is the last act\'s', () async {
      bloc.add(const ShareOpened());
      await settled();
      final gate = Completer<void>();
      share
        ..hold = gate
        ..nextChange = shared;

      bloc.add(const ShareFolderShared('trips'));
      await pumpEventQueue();
      share.nextChange = unshared;
      bloc.add(const ShareFolderUnshared('trips'));
      bloc.add(const ShareEventUnshared('e1'));
      await pumpEventQueue();
      expect(share.folderShares, [('trips', true)]);
      expect(share.eventShares, isEmpty);

      gate.complete();
      final state = await settled();
      expect(share.folderShares, [('trips', true), ('trips', false)]);
      expect(share.eventShares, [('e1', false)]);
      expect(state.outcome!.act, ShareAct.eventUnshared);
    });

    test('a folder act refused because sharing is no longer ready says so, '
        'and writes nothing', () async {
      bloc.add(const ShareOpened());
      await settled();
      share.emit(const ShareNotSyncing(audience));
      await settled();

      bloc.add(const ShareFolderShared('trips'));

      final state = await settled();
      expect(share.folderShares, isEmpty);
      expect(state.outcome!.act, ShareAct.folderShared);
      expect(state.outcome!.failure, ShareFailure.refused);
    });

    test('a load carries the notes look as stored', () async {
      share.notes = ShareNoteLook.plain;

      bloc.add(const ShareOpened());

      expect((await settled()).look.noteLook, ShareNoteLook.plain);
    });

    test('the notes look shows from the tap, keeps the other looks, and '
        'stands once written', () async {
      bloc.add(const ShareOpened());
      await settled();
      final gate = Completer<void>();
      share.settingsHold = gate;

      bloc.add(const ShareNoteLookSet(ShareNoteLook.plain));
      bloc.add(const ShareEventLookSet(ShareEventLook.avatar));
      final early = await settled();

      expect(share.notes, ShareNoteLook.avatar, reason: 'still held');
      expect(
        early.look,
        const ShareLook(
          eventLook: ShareEventLook.avatar,
          noteLook: ShareNoteLook.plain,
        ),
      );

      gate.complete();
      final landed = await settled();
      expect(share.notes, ShareNoteLook.plain);
      expect(landed.look.noteLook, ShareNoteLook.plain);
      expect(landed.look.eventLook, ShareEventLook.avatar);
    });

    test('a notes look whose write fails draws back to what is '
        'stored', () async {
      bloc.add(const ShareOpened());
      await settled();
      final gate = Completer<void>();
      share
        ..settingsHold = gate
        ..settingsFailure = StateError('disk');

      bloc.add(const ShareNoteLookSet(ShareNoteLook.plain));
      expect((await settled()).look.noteLook, ShareNoteLook.plain);

      gate.complete();
      final state = await settled();
      expect(state.look.noteLook, ShareNoteLook.avatar);
      expect(state.outcome, isNull, reason: 'no snackbar for a setting');
    });
  });
}
