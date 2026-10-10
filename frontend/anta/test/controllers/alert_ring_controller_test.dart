import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/controllers/alert_ring_controller.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_keep_notice.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/session_chip.dart';

import '../database/support/db_test_support.dart';
import '../widgets/support/alarm_page_fakes.dart';

/// The alarm page's Keep, as the real controller carries it out — and the
/// two things that have to agree with it: what Stop decides when it is
/// pressed, and what a ring learns about its event as its page comes up.
///
/// Keep is a promise in three moments — nothing is removed from the press
/// on, the event is "kept" only once its write has come back, and a write
/// that fails takes the press back — and each moment is something the page
/// draws or something Stop acts on. None of them can be looked at through a
/// database: the write is over within a turn of the event loop and cannot be
/// made to fail. So the things the controller reaches the database through —
/// finding the event, saving it, removing it — are swapped for a store the
/// test holds (`AlertRingController.configureForTesting`), and everything
/// else here is the controller as it ships.
///
/// Which database is open is supplied the way the page suite supplies it
/// (`FakeRingController`), except in the last group, which is about the
/// controller's own `load` and stands in for the one preference that reads.
void main() {
  setUp(AlertKeepNotice.instance.clearForTesting);
  tearDown(AlertKeepNotice.instance.clearForTesting);

  final teaTimer = CalendarEvent(
    id: 'e1',
    title: 'Tea timer',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 9, 20),
    time: const EventTime(startMinute: 7 * 60),
    removeAfterAlert: true,
  );

  AlertPayload payload({
    bool removeAfterAlert = true,
    String database = 'gym_notes',
    bool test = false,
  }) => AlertPayload(
    database: database,
    eventId: test ? AlertPayload.testEventId : 'e1',
    alertId: test ? AlertPayload.testEventId : 'a1',
    dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
    osId: 4242,
    mode: AlertMode.ring,
    title: 'Tea timer',
    timeLabel: '07:00',
    categoryId: 'other',
    removeAfterAlert: removeAfterAlert,
  );

  /// The controller of an alarm ringing while [active] is the open database,
  /// reading and writing [store].
  AlertRingController controllerOf(
    _Store store, {
    AlertPayload? ringing,
    String active = 'gym_notes',
  }) {
    final controller = FakeRingController(ringing ?? payload(), active: active)
      ..configureForTesting(
        findEvent: store.find,
        saveEvent: store.save,
        removeEvent: store.remove,
      );
    addTearDown(() {
      if (!store.disposed) controller.dispose();
    });
    return controller;
  }

  test('Keep saves the event with its flag cleared, and nothing else of it '
      'changed', () async {
    final store = _Store(teaTimer);
    final controller = controllerOf(store);

    await controller.keep();

    expect(store.lookups, ['e1']);
    expect(store.saves, [teaTimer.copyWith(removeAfterAlert: false)]);
    expect(store.saves.single.removeAfterAlert, isFalse);
    expect(controller.keepEvent, isTrue);
    expect(controller.willRemoveEvent, isFalse);
  });

  test('from the press nothing is removed, but "kept" waits for the write to '
      'come back', () async {
    final store = _Store(teaTimer)..hold();
    final controller = controllerOf(store);
    var notified = 0;
    controller.addListener(() => notified++);
    expect(controller.willRemoveEvent, isTrue);

    final keeping = controller.keep();
    await pumpEventQueue();

    // A Stop that overtakes the write must not delete an event the user has
    // just asked to keep…
    expect(store.saves, hasLength(1));
    expect(controller.willRemoveEvent, isFalse);
    // …and "kept" is a fact about the database, which it is not yet: a Stop
    // on the notification reads the event's own flag.
    expect(controller.keepEvent, isFalse);
    expect(notified, 1);

    store.release();
    await keeping;

    expect(controller.keepEvent, isTrue);
    expect(controller.willRemoveEvent, isFalse);
    expect(notified, 2);
  });

  test('the calendar is told once the write is in, and not before', () async {
    // The service tells nobody, and the bloc above the calendar would go on
    // showing the event as "removed after it rings" until the next launch.
    final store = _Store(teaTimer)..hold();
    final controller = controllerOf(store);

    final keeping = controller.keep();
    await pumpEventQueue();
    expect(AlertKeepNotice.instance.hasPending, isFalse);

    store.release();
    await keeping;

    expect(AlertKeepNotice.instance.hasPending, isTrue);
  });

  test('a write that throws is taken back: Stop removes the event again, Keep '
      'can be pressed again, and the calendar is told nothing', () async {
    final store = _Store(teaTimer)..failure = StateError('disk full');
    final controller = controllerOf(store);
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.keep();

    expect(store.saves, hasLength(1));
    expect(controller.keepEvent, isFalse);
    expect(controller.willRemoveEvent, isTrue);
    expect(notified, 2, reason: 'the press, and the press taken back');
    expect(AlertKeepNotice.instance.hasPending, isFalse);

    // The event is still one that Stop removes, so the way out of that is
    // still there.
    store.failure = null;
    await controller.keep();

    expect(store.saves, hasLength(2));
    expect(controller.keepEvent, isTrue);
    expect(AlertKeepNotice.instance.hasPending, isTrue);
  });

  test('an event that is not there to write to is taken back too', () async {
    final store = _Store(null);
    final controller = controllerOf(store);

    await controller.keep();

    expect(store.lookups, ['e1']);
    expect(store.saves, isEmpty);
    expect(controller.keepEvent, isFalse);
    expect(controller.willRemoveEvent, isTrue);
    expect(AlertKeepNotice.instance.hasPending, isFalse);
  });

  test("another database's alarm is never looked up: the event with that id "
      "here is somebody else's", () async {
    // Two databases restored from one backup share event ids. An alarm from
    // *work* ringing while *personal* is open must not rewrite whatever
    // carries its id here.
    final store = _Store(teaTimer);
    final controller = controllerOf(
      store,
      ringing: payload(database: 'work'),
      active: 'personal',
    );

    await controller.keep();

    expect(store.lookups, isEmpty);
    expect(store.saves, isEmpty);
    expect(controller.keepEvent, isFalse);
    expect(AlertKeepNotice.instance.hasPending, isFalse);
  });

  test('while it is not known which database is open, nothing is looked up '
      'either', () async {
    // "Not known" reads as "not ours", never as "probably ours".
    final store = _Store(teaTimer);
    final controller = AlertRingController(payload: payload())
      ..configureForTesting(findEvent: store.find, saveEvent: store.save);
    addTearDown(controller.dispose);
    expect(controller.activeDatabase, isNull);

    await controller.keep();

    expect(store.lookups, isEmpty);
    expect(store.saves, isEmpty);
    expect(controller.keepEvent, isFalse);
    expect(controller.willRemoveEvent, isTrue);
  });

  test('a second Keep while the first is being saved writes once', () async {
    final store = _Store(teaTimer)..hold();
    final controller = controllerOf(store);

    final first = controller.keep();
    await pumpEventQueue();
    final second = controller.keep();
    await pumpEventQueue();
    store.release();
    await Future.wait([first, second]);

    expect(store.saves, hasLength(1));
    expect(controller.keepEvent, isTrue);
  });

  test('a Keep that has been saved is not asked for twice', () async {
    final store = _Store(teaTimer);
    final controller = controllerOf(store);

    await controller.keep();
    await controller.keep();

    expect(store.saves, hasLength(1));
  });

  test('an event that Stop would not remove has nothing to keep', () async {
    final store = _Store(teaTimer);
    final controller = controllerOf(
      store,
      ringing: payload(removeAfterAlert: false),
    );
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.keep();

    expect(store.lookups, isEmpty);
    expect(controller.keepEvent, isFalse);
    expect(notified, 0);
  });

  test('a test ring has no event to keep', () async {
    final store = _Store(teaTimer);
    final controller = controllerOf(store, ringing: payload(test: true));
    expect(controller.willRemoveEvent, isFalse);

    await controller.keep();

    expect(store.lookups, isEmpty);
    expect(store.saves, isEmpty);
  });

  test('a write that comes back after the page has closed still reaches the '
      'calendar, and tells nobody who is gone', () async {
    // Stop does not wait for Keep's write, and the page disposes the
    // controller it made when it closes.
    final store = _Store(teaTimer)..hold();
    final controller = controllerOf(store);
    controller.addListener(() {});

    final keeping = controller.keep();
    await pumpEventQueue();
    controller.dispose();
    store.disposed = true;
    store.release();

    await expectLater(keeping, completes);
    expect(store.saves, hasLength(1));
    expect(AlertKeepNotice.instance.hasPending, isTrue);
  });

  group('whether Stop removes the event is decided when it is pressed:', () {
    // Stop reads the decision and then does its work — the scheduler's stop,
    // the standing snooze, the session chip — before it acts on it, and
    // Keep's write, which may still be out, takes the press back when it
    // fails. A decision read after that work was open to a Keep failing in
    // the meantime: the event the user had asked to keep, a moment before
    // pressing Stop, was removed by that Stop.
    //
    // Stop's work is over within a turn of the event loop here, as Keep's
    // write is, so the last step of it is held: the chip asks which database
    // is open, and the test answers when it is ready.
    late Completer<String?> chipAsks;
    late Future<void> stopping;

    setUp(() {
      chipAsks = Completer<String?>();
      SessionChip.instance.configureForTesting(
        gateway: () => const NoOpAlertGateway(),
        activeDatabase: () => chipAsks.future,
        findEvent: (_) async => null,
        clock: DateTime.now,
      );
    });

    tearDown(SessionChip.instance.resetForTesting);

    /// Presses Stop and leaves it held just short of the removal.
    Future<void> pressStop(AlertRingController controller) async {
      stopping = controller.stop();
      await pumpEventQueue();
      expect(controller.busy, isTrue, reason: 'Stop is held at the chip');
    }

    /// Lets the held Stop run to its end.
    Future<void> finishStop() async {
      chipAsks.complete('gym_notes');
      await stopping;
    }

    test('with nothing kept, it removes', () async {
      final store = _Store(teaTimer);
      final controller = controllerOf(store);

      await pressStop(controller);
      await finishStop();

      expect(store.removals, [4242]);
      expect(controller.stopped, isTrue);
    });

    test('with a Keep still being saved, it removes nothing, and that write '
        'failing afterwards does not hand the removal back', () async {
      final store = _Store(teaTimer)..hold();
      final controller = controllerOf(store);

      final keeping = controller.keep();
      await pumpEventQueue();
      await pressStop(controller);

      store.failure = StateError('disk full');
      store.release();
      await keeping;
      // The press is taken back, as a Keep that failed always is: a Stop
      // pressed from here on removes…
      expect(controller.keepEvent, isFalse);
      expect(controller.willRemoveEvent, isTrue);

      await finishStop();

      // …but the one pressed while the Keep stood was told "nothing".
      expect(store.removals, isEmpty);
      expect(controller.stopped, isTrue);
    });

    test('with a Keep still being saved that is saved afterwards, it removes '
        'nothing either', () async {
      final store = _Store(teaTimer)..hold();
      final controller = controllerOf(store);

      final keeping = controller.keep();
      await pumpEventQueue();
      await pressStop(controller);
      store.release();
      await keeping;
      await finishStop();

      expect(controller.keepEvent, isTrue);
      expect(store.removals, isEmpty);
    });

    test('after a Keep that had already failed, it removes: the page was '
        'saying so again', () async {
      final store = _Store(teaTimer)..failure = StateError('disk full');
      final controller = controllerOf(store);

      await controller.keep();
      expect(controller.willRemoveEvent, isTrue);

      await pressStop(controller);
      await finishStop();

      expect(store.removals, [4242]);
    });

    test('the decision only narrows: an event kept while Stop is at work is '
        'not removed by it', () async {
      // The page switches Keep off while Stop is busy, so what gets here is
      // an event found kept by a read that outlasted the press.
      final store = _Store(teaTimer);
      final controller = controllerOf(store);

      await pressStop(controller);
      await controller.keep();
      expect(controller.keepEvent, isTrue);
      await finishStop();

      expect(store.removals, isEmpty);
    });
  });

  group('what a ring learns about its event as its page comes up:', () {
    // A payload is as old as its arming, and Keep writes the event and
    // re-arms nothing. So a ring armed before a Keep — the same alarm snoozed
    // on its notification, which the plugin re-arms as it stands, or a
    // second alarm of the event — still says that Stop removes the event,
    // and the page said so beside a live Keep, about an event kept ten
    // minutes earlier. Stop removed nothing; the sentence was false.
    //
    // This group runs the controller's own `load`, which the cases above
    // leave to `FakeRingController`. Outside its seams it asks one thing,
    // which database is open, and that is a single preference: unset here,
    // which is a phone that never switched databases and stands on
    // `gym_notes`, the payloads' own.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final keptTimer = teaTimer.copyWith(removeAfterAlert: false);

    /// The controller as the page makes it, reading [store].
    AlertRingController ringing(_Store store, {AlertPayload? of}) {
      final controller = AlertRingController(payload: of ?? payload())
        ..configureForTesting(
          findEvent: store.find,
          saveEvent: store.save,
          removeEvent: store.remove,
        );
      addTearDown(() {
        if (!store.disposed) controller.dispose();
      });
      return controller;
    }

    /// What the page draws the remove row from, as it stood each time the
    /// page was told to look.
    List<_Told> watch(AlertRingController controller) {
      final told = <_Told>[];
      controller.addListener(
        () => told.add((
          database: controller.activeDatabase,
          kept: controller.keepEvent,
          removes: controller.willRemoveEvent,
        )),
      );
      return told;
    }

    test('an event kept before this ring is kept from the first thing the '
        'page hears, and it hears once', () async {
      final store = _Store(keptTimer)..holdFind();
      final controller = ringing(store);
      final told = watch(controller);

      final loading = controller.load();
      await pumpEventQueue();

      // Which database is open is known by now, and is not said yet: said
      // alone, the page would draw "Stop also removes this event" beside a
      // live Keep, and take both back when the event answered.
      expect(store.lookups, ['e1']);
      expect(told, isEmpty);
      expect(controller.activeDatabase, isNull);

      store.releaseFind();
      await loading;

      expect(told, [(database: 'gym_notes', kept: true, removes: false)]);
      // It was read, and that is all: there is no write to make and no
      // calendar to tell.
      expect(store.saves, isEmpty);
      expect(AlertKeepNotice.instance.hasPending, isFalse);
    });

    test('an event that still carries the flag is one Stop removes, as the '
        'payload says', () async {
      final store = _Store(teaTimer);
      final controller = ringing(store);
      final told = watch(controller);

      await controller.load();

      expect(store.lookups, ['e1']);
      expect(told, [(database: 'gym_notes', kept: false, removes: true)]);
    });

    test("an event that is not there leaves the payload's word "
        'standing', () async {
      final store = _Store(null);
      final controller = ringing(store);
      final told = watch(controller);

      await controller.load();

      expect(store.lookups, ['e1']);
      expect(told, [(database: 'gym_notes', kept: false, removes: true)]);
    });

    test('so does a lookup that throws, and the page still learns which '
        'database is open', () async {
      final store = _Store(keptTimer)..findFailure = StateError('closed');
      final controller = ringing(store);
      final told = watch(controller);

      await expectLater(controller.load(), completes);

      expect(store.lookups, ['e1']);
      expect(told, [(database: 'gym_notes', kept: false, removes: true)]);
    });

    test('only an alarm of the open database that says Stop removes its '
        'event is asked about', () async {
      // Another database's alarm above all: the event with that id here is
      // somebody else's, and what it carries says nothing of this ring.
      for (final ring in [
        payload(database: 'work'),
        payload(removeAfterAlert: false),
        payload(test: true),
      ]) {
        final store = _Store(keptTimer);
        final controller = ringing(store, of: ring);
        final told = watch(controller);

        await controller.load();

        expect(
          store.lookups,
          isEmpty,
          reason: '${ring.database} ${ring.eventId}',
        );
        expect(told, hasLength(1));
        expect(told.single.database, 'gym_notes');
        expect(told.single.kept, isFalse);
      }
    });

    test('a ring that starts as kept leaves Keep nothing to write and Stop '
        'nothing to remove', () async {
      final store = _Store(keptTimer);
      final controller = ringing(store);

      await controller.load();
      await controller.keep();
      await controller.stop();

      expect(store.saves, isEmpty);
      expect(store.removals, isEmpty);
      expect(AlertKeepNotice.instance.hasPending, isFalse);
    });

    test('an answer that comes back after the page has closed tells nobody '
        'who is gone', () async {
      // The lookup can outlast the page: a ring stopped on its notification
      // closes it, and it disposes the controller it made.
      final store = _Store(keptTimer)..holdFind();
      final controller = ringing(store);
      controller.addListener(() {});

      final loading = controller.load();
      await pumpEventQueue();
      controller.dispose();
      store.disposed = true;
      store.releaseFind();

      await expectLater(loading, completes);
    });
  });

  group('a ring that ends elsewhere while Stop or Snooze is out:', () {
    // Both wait on the scheduler's serialized chain, which can be a whole
    // pass long — a resume's reconcile runs two seconds after the resume a
    // ring causes. A ring that ends by another route meanwhile — Stop or
    // Snooze on its heads-up, the Silence-after timeout, its entry
    // cancelled — closes the page, and the page disposes the controller it
    // made. The call still out then comes back to a disposed controller,
    // and telling it anything is an error in every build that asserts.
    //
    // The real `load` subscribes to the ring's endings, so it runs here as
    // in the last group; the scheduler is bound to a database of its own and
    // a gateway whose silencing — the first thing both Stop and Snooze ask
    // of it — the test holds.
    late _HeldStopGateway gateway;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      gateway = _HeldStopGateway();
      GetIt.I.registerSingleton<AlertGateway>(gateway);
      db = await openTestDatabase();
      AlertScheduler.forTesting(
        db: db,
        gateway: gateway,
        databaseName: 'gym_notes',
      );
      SessionChip.instance.configureForTesting(
        gateway: () => const NoOpAlertGateway(),
        activeDatabase: () async => 'gym_notes',
        findEvent: (_) async => null,
        clock: DateTime.now,
      );
    });

    tearDown(() async {
      SessionChip.instance.resetForTesting();
      AlertScheduler.reset();
      await GetIt.I.unregister<AlertGateway>();
      await gateway.ends.close();
      await db.close();
    });

    /// The controller as the page makes it, listening for its ring's end.
    Future<AlertRingController> ringing(_Store store) async {
      final controller = AlertRingController(payload: payload())
        ..configureForTesting(
          findEvent: store.find,
          saveEvent: store.save,
          removeEvent: store.remove,
        );
      addTearDown(() {
        if (!store.disposed) controller.dispose();
      });
      await controller.load();
      return controller;
    }

    /// The ring ends behind the page's back, and the page — which closes on
    /// that — disposes the controller it made.
    Future<void> endElsewhereAndClose(
      AlertRingController controller,
      _Store store,
    ) async {
      gateway.ends.add((
        payload: payload(),
        cause: AlertRingEndCause.dismissed,
      ));
      await pumpEventQueue();
      expect(controller.endedElsewhere, isTrue);
      controller.dispose();
      store.disposed = true;
    }

    for (final (name, press) in <(String, Future<void> Function(AlertRingController))>[
      ('Stop', (controller) => controller.stop()),
      ('Snooze', (controller) => controller.snooze()),
    ]) {
      test('$name comes back to a closed page and tells nobody who is gone',
          () async {
        final store = _Store(teaTimer);
        final controller = await ringing(store);

        gateway.hold();
        final pressed = press(controller);
        await pumpEventQueue();
        expect(controller.busy, isTrue, reason: 'held on the chain');

        await endElsewhereAndClose(controller, store);
        gateway.release();

        await expectLater(pressed, completes);
      });
    }
  });
}

/// A gateway that tells the controller its ring ended, and whose silencing
/// can be kept in flight — which keeps the scheduler's chain, and the Stop or
/// Snooze waiting on it, out until [release].
class _HeldStopGateway extends EndingGateway {
  Completer<void>? _held;

  void hold() => _held = Completer<void>();

  void release() {
    _held?.complete();
    _held = null;
  }

  @override
  Future<void> stopRinging(int osId) async {
    await _held?.future;
  }
}

/// What the page draws its remove row from.
typedef _Told = ({String? database, bool kept, bool removes});

/// The things the controller reaches a database through, held by the test:
/// the one event the database has, every lookup, every save and every
/// removal, a lookup and a write that can each be kept in flight and each be
/// made to throw.
class _Store {
  _Store(this.event);

  final CalendarEvent? event;

  final List<String> lookups = <String>[];

  final List<CalendarEvent> saves = <CalendarEvent>[];

  /// The os id of every ring Stop asked to have its event removed for.
  final List<int> removals = <int>[];

  /// What the next save throws once it has been asked for, or null.
  Object? failure;

  /// What the next lookup throws once it has been asked for, or null.
  Object? findFailure;

  /// Whether the test disposed the controller itself.
  bool disposed = false;

  Completer<void>? _held;

  Completer<void>? _heldFind;

  /// Keeps the next save in flight until [release].
  void hold() => _held = Completer<void>();

  void release() {
    _held?.complete();
    _held = null;
  }

  /// Keeps the next lookup unanswered until [releaseFind].
  void holdFind() => _heldFind = Completer<void>();

  void releaseFind() {
    _heldFind?.complete();
    _heldFind = null;
  }

  Future<CalendarEvent?> find(String eventId) async {
    lookups.add(eventId);
    await _heldFind?.future;
    final failure = findFailure;
    if (failure != null) throw failure;
    return event?.id == eventId ? event : null;
  }

  Future<void> save(CalendarEvent event) async {
    saves.add(event);
    await _held?.future;
    final failure = this.failure;
    if (failure != null) throw failure;
  }

  Future<void> remove(AlertPayload payload) async => removals.add(payload.osId);
}
