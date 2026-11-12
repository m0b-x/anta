import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/services/share_service.dart';

import '../support/fake_share_service.dart';

/// An overview read that throws while [failing].
class _UnreadableShare extends FakeShareService {
  _UnreadableShare({super.availability});

  bool failing = true;

  @override
  Future<ShareOverview> overview() async {
    if (failing) throw StateError('the read failed');
    return super.overview();
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
}
