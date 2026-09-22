import 'package:alarm/alarm.dart';
import 'package:alarm/service/alarm_storage.dart';
import 'package:alarm/src/alarm_trigger_api_impl.dart';
import 'package:alarm/src/generated/platform_bindings.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_host.dart';

/// Lets already-queued stream deliveries run.
Future<void> pump() => Future<void>.delayed(Duration.zero);

/// The host event mechanism, beyond the snooze case that already exercises it.
///
/// `moved` is covered in depth by the snooze suite, since a snooze *is* a move.
/// What is untested there is the other verb and the other causes, which nothing
/// in the plugin emits yet — so these tests stand in for the callers that will,
/// and are the reason a later change can rely on this plumbing working.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHost host;

  AlarmSettings buildAlarm(int id, DateTime dateTime) => AlarmSettings(
        id: id,
        dateTime: dateTime,
        volumeSettings: const VolumeSettings.fixed(),
        notificationSettings: const NotificationSettings(
          title: 'Wake up',
          body: '',
        ),
      );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Alarm.resetForTesting();
    AlarmStorage.resetForTesting();
    AlarmTriggerApiImpl.resetForTesting();
    host = FakeHost()..install();
  });

  tearDown(() {
    host.remove();
    Alarm.resetForTesting();
    AlarmStorage.resetForTesting();
    AlarmTriggerApiImpl.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
  });

  group('a dropped alarm', () {
    test('is removed, reported, and acknowledged on init', () async {
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init();

      expect(await Alarm.getAlarms(), isEmpty);
      expect(Alarm.scheduled.value.alarms, isEmpty);
      expect(
        host.acknowledged,
        contains((42, scheduledFor.millisecondsSinceEpoch)),
      );

      expect(seen, hasLength(1));
      final event = seen.single;
      expect(event, isA<AlarmDropped>());
      expect(event.id, 42);
      expect(event.cause, AlarmEventCause.staleAtBoot);
      expect(
        (event as AlarmDropped).scheduledFor.millisecondsSinceEpoch,
        scheduledFor.millisecondsSinceEpoch,
      );
    });

    test('is not stopped again by the reconcile loop', () async {
      // The host already discarded it, so telling the host to stop it would be
      // a pointless round trip that also reports a stop for an alarm the app
      // was never told was ringing.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      await Alarm.init();

      expect(host.calls, isNot(contains('stopAlarm')));
    });

    test('does not reach the snoozed stream', () async {
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final snoozes = <({int id, DateTime nextRingAt})>[];
      // Deprecated in favour of Alarm.events, but still shipped, so what it
      // must NOT report is still worth asserting.
      // ignore: deprecated_member_use_from_same_package
      final subscription = Alarm.snoozed.listen(snoozes.add);
      addTearDown(subscription.cancel);

      await Alarm.init();

      expect(snoozes, isEmpty);
    });

    test('reaches a listener that subscribes after init', () async {
      // The README tells applications to `await Alarm.init()` in main, so the
      // realistic listener attaches afterwards — and a stale-at-boot drop is
      // only ever discovered during that drain, because the alarm was discarded
      // at boot with no engine to call. An unbuffered stream would deliver this
      // to nobody, which is the one case the event exists for.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      await Alarm.init();

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);
      await pump();

      expect(seen, hasLength(1));
      expect(seen.single, isA<AlarmDropped>());
      expect(seen.single.id, 42);
    });

    test('is not reported twice when its marker is replayed', () async {
      // The host keeps the marker until Dart acknowledges it, so a process
      // death between reporting and acknowledging replays the event on the next
      // drain. Reporting it again would have the app tell its user twice about
      // one missed alarm.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init();
      // The fake host still offers the same marker, which is exactly what a
      // host that never saw the acknowledgement would do.
      await Alarm.checkAlarm();
      await pump();

      expect(seen, hasLength(1));
    });

    test('is still reported when a previous run died before reporting it',
        () async {
      // Removing the alarm is durable and completes before the report, so a
      // process death in between leaves the marker with the alarm already gone.
      // Suppressing on "the alarm is missing" would swallow the only notice the
      // application ever gets — silence here is unrecoverable, a duplicate is
      // not, which is why this replays rather than dedups across runs.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      // Deliberately no saveAlarm: the run that died already removed it.
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init();
      await pump();

      expect(seen, hasLength(1));
      expect(seen.single.id, 42);
    });

    test('a drain larger than a small buffer still reaches a late listener',
        () async {
      // One marker per alarm, and Android allows up to 500 alarms, so a drain
      // can be far bigger than a conservatively sized replay buffer. A late
      // listener silently missing the oldest events would break the buffering
      // guarantee exactly when an app has the most to be told about.
      const count = 100;
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      for (var i = 0; i < count; i++) {
        await AlarmStorage.saveAlarm(buildAlarm(1000 + i, scheduledFor));
        host.pending.add(droppedEvent(1000 + i, scheduledFor));
      }

      await Alarm.init();

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);
      await pump();

      expect(seen, hasLength(count));
      expect(await Alarm.getAlarms(), isEmpty);
    });

    test('applies when the host reports it live', () async {
      // Deliberately an alarm that is still in the future: a past-due one is
      // removed by the reconcile loop during init, so a drop arriving
      // afterwards would find nothing left and be suppressed as a repeat. That
      // suppression is correct, but it would make this test assert nothing.
      final scheduledFor = DateTime.now().add(const Duration(hours: 1));
      await AlarmStorage.saveAlarm(buildAlarm(7, scheduledFor));
      await Alarm.init();

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await hostReportsEvent(droppedEvent(7, scheduledFor));
      // Stream delivery is asynchronous, so assert only once it has run rather
      // than relying on the awaits inside the drop having pumped enough turns.
      await pump();

      expect(await Alarm.getAlarm(7), isNull);
      expect(seen.single, isA<AlarmDropped>());
    });
  });

  group('a move the platform forced', () {
    test('reaches events but not the snoozed stream', () async {
      // Alarm.snoozed means the user deferred the alarm. A deferral the
      // platform imposed is not that, and reporting it there would put an
      // event in the app's records that the app cannot explain.
      final nextRingAt = DateTime.now().add(const Duration(seconds: 30));
      await AlarmStorage.saveAlarm(
        buildAlarm(9, DateTime.now().subtract(const Duration(seconds: 5))),
      );
      host.pending.add(refusedRingEvent(9, nextRingAt));

      final seen = <AlarmEvent>[];
      final snoozes = <({int id, DateTime nextRingAt})>[];
      final events = Alarm.events.listen(seen.add);
      // Deprecated in favour of Alarm.events, but still shipped, so what it
      // must NOT report is still worth asserting.
      // ignore: deprecated_member_use_from_same_package
      final snoozed = Alarm.snoozed.listen(snoozes.add);
      addTearDown(events.cancel);
      addTearDown(snoozed.cancel);

      await Alarm.init();

      expect(snoozes, isEmpty, reason: 'the user did not snooze this');
      expect(seen.single, isA<AlarmMoved>());
      expect(seen.single.cause, AlarmEventCause.platformRefusal);

      final stored = await Alarm.getAlarm(9);
      expect(stored, isNotNull);
      expect(
        stored!.dateTime.millisecondsSinceEpoch,
        nextRingAt.millisecondsSinceEpoch,
        reason: 'the shifted time must reach Dart storage, or the next '
            'reconciliation stops the alarm and cancels the retry',
      );
    });
  });

  group('the acknowledgement boundary', () {
    /// The alarm and event a live report needs.
    ///
    /// Deliberately still in the future: a past-due alarm is removed by the
    /// reconcile loop during init, so a drop arriving afterwards would find
    /// nothing left and be suppressed as a repeat.
    Future<AlarmEventWire> liveDrop(int id) async {
      final scheduledFor = DateTime.now().add(const Duration(hours: 1));
      await AlarmStorage.saveAlarm(buildAlarm(id, scheduledFor));
      return droppedEvent(id, scheduledFor);
    }

    test('the default acknowledges without waiting for the application',
        () async {
      // What every app on 5.10.0 has, and what they keep until 6.0.0.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      await Alarm.init();

      expect(
        host.acknowledged,
        contains((42, scheduledFor.millisecondsSinceEpoch)),
      );
    });

    test('a live event is acknowledged by Dart rather than by the host',
        () async {
      // The host used to drop its marker as soon as this call replied, which
      // put the boundary back on the side that cannot see whether a listener
      // has finished. Dart owns it on both paths now, which is what makes the
      // opt-out mean anything for an event that arrives live.
      final event = await liveDrop(7);
      await Alarm.init();

      await hostReportsEvent(event);
      await pump();

      expect(host.acknowledged, contains((7, event.recordedAtMillis)));
    });

    test('the opt-out leaves an event the application was given unacknowledged',
        () async {
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();

      expect(seen, hasLength(1));
      expect(
        host.acknowledged,
        isEmpty,
        reason: 'the marker is the only thing that survives a process death '
            'while the handler is still writing the event down',
      );
    });

    test('the opt-out covers a live event too', () async {
      final event = await liveDrop(7);
      await Alarm.init(acknowledgeEventsAutomatically: false);

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await hostReportsEvent(event);
      await pump();

      expect(seen, hasLength(1));
      expect(host.acknowledged, isEmpty);
    });

    test('acknowledgeEvent drops the marker the opt-out kept', () async {
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();
      expect(host.acknowledged, isEmpty);

      await Alarm.acknowledgeEvent(seen.single);

      expect(
        host.acknowledged,
        contains((42, scheduledFor.millisecondsSinceEpoch)),
      );
    });

    test('acknowledgeEvent is safe under the default and when repeated',
        () async {
      // A listener written for the manual boundary has to be runnable either
      // way, or taking the opt-out becomes an all-or-nothing rewrite.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init();
      await pump();

      await Alarm.acknowledgeEvent(seen.single);
      await Alarm.acknowledgeEvent(seen.single);
    });

    test('an event the application never saw is acknowledged under the opt-out',
        () async {
      // A deferral for an alarm this run has no record of cannot be applied and
      // never reaches [Alarm.events], so no listener can ever acknowledge it.
      // Holding its marker would redeliver it on every init until it expired.
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      // Deliberately no saveAlarm: nothing here to move.
      host.pending.add(snoozeEvent(404, nextRingAt));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();

      expect(seen, isEmpty);
      expect(
        host.acknowledged,
        contains((404, nextRingAt.millisecondsSinceEpoch)),
      );
    });

    test('a marker replayed inside one run stays unacknowledged', () async {
      // The second drain suppresses the report because the application already
      // has the event — which is the reason this run must not acknowledge it.
      // Reading "we did not emit it this time" as "nobody has it" would delete
      // the marker while the first handler was still writing.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init(acknowledgeEventsAutomatically: false);
      // The fake host still offers the same marker, which is exactly what a
      // host that never saw an acknowledgement would do.
      await Alarm.checkAlarm();
      await pump();

      expect(seen, hasLength(1));
      expect(host.acknowledged, isEmpty);
    });

    /// Runs [body] as a fresh process over the same storage and the same host.
    ///
    /// Dart's in-memory state goes and the stored alarms stay, which is what a
    /// process death looks like from the next launch. The fake host still
    /// offers any marker nothing acknowledged, exactly as a real one would.
    Future<void> afterRestart(Future<void> Function() body) async {
      Alarm.resetForTesting();
      await body();
    }

    test(
        'a move whose marker outlived a restart is re-emitted under the '
        'opt-out', () async {
      // The plugin stores the moved time before it emits, so on the next launch
      // the stored alarm already matches and the deferral is not news. That
      // proves the *plugin* applied it, never that the application recorded it
      // — and a marker that survived is proof the application did not. Reading
      // "already applied" as "already delivered" would silently drop the one
      // event the opt-out exists to keep.
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      await AlarmStorage.saveAlarm(
        buildAlarm(21, DateTime.now().add(const Duration(minutes: 1))),
      );
      host.pending.add(snoozeEvent(21, nextRingAt));

      final firstRun = <AlarmEvent>[];
      final firstSubscription = Alarm.events.listen(firstRun.add);
      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();
      expect(firstRun, hasLength(1));
      expect(host.acknowledged, isEmpty);
      await firstSubscription.cancel();

      await afterRestart(() async {
        final secondRun = <AlarmEvent>[];
        final subscription = Alarm.events.listen(secondRun.add);
        addTearDown(subscription.cancel);

        await Alarm.init(acknowledgeEventsAutomatically: false);
        await pump();

        expect(
          secondRun,
          hasLength(1),
          reason: 'the run that was given this event died before confirming '
              'it, so this run has to hand it over again',
        );
        expect(secondRun.single, isA<AlarmMoved>());
        expect(host.acknowledged, isEmpty);
      });
    });

    test('a move replayed after a restart is left alone under the default',
        () async {
      // The other half of the case above: an app that never opted in keeps
      // 5.10.0's behaviour exactly, including not being told twice.
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      await AlarmStorage.saveAlarm(
        buildAlarm(21, DateTime.now().add(const Duration(minutes: 1))),
      );
      host.pending.add(snoozeEvent(21, nextRingAt));

      await Alarm.init();
      await pump();
      host.acknowledged.clear();

      await afterRestart(() async {
        final secondRun = <AlarmEvent>[];
        final subscription = Alarm.events.listen(secondRun.add);
        addTearDown(subscription.cancel);

        await Alarm.init();
        await pump();

        expect(secondRun, isEmpty);
        expect(
          host.acknowledged,
          contains((21, nextRingAt.millisecondsSinceEpoch)),
        );
      });
    });

    test('a later bare init does not hand the boundary back', () async {
      // init is callable more than once — on resume, or from a second library
      // path — and a call that says nothing about acknowledgement is not the
      // application changing its mind. Letting it restore the default would
      // start acknowledging events the application still owns, silently
      // undoing the opt-out from somewhere that never mentioned it.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();
      expect(seen, hasLength(1));

      await Alarm.init();
      await pump();

      expect(host.acknowledged, isEmpty);

      // And the boundary is still the application's for what comes next.
      final live = await (() async {
        final at = DateTime.now().add(const Duration(hours: 1));
        await AlarmStorage.saveAlarm(buildAlarm(8, at));
        return droppedEvent(8, at);
      })();
      await hostReportsEvent(live);
      await pump();

      expect(host.acknowledged, isEmpty);
    });

    test('a concurrent bare init cannot flip the policy mid-drain', () async {
      // The policy is read when the drain acknowledges, not when init is
      // called, so a second init landing while the first one's drain is still
      // in flight used to decide the boundary for events it knew nothing about.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      final subscription = Alarm.events.listen(seen.add);
      addTearDown(subscription.cancel);

      // Deliberately not awaited in order: the second call runs up to its first
      // await while the first call's drain is still going.
      final opted = Alarm.init(acknowledgeEventsAutomatically: false);
      final bare = Alarm.init();
      await Future.wait([opted, bare]);
      await pump();

      expect(seen, hasLength(1));
      expect(host.acknowledged, isEmpty);
    });

    test('an explicit init(true) does hand the boundary back', () async {
      // The escape hatch stays deliberate: an application that names the value
      // is asking for it, which is the one thing a bare call is not.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();
      expect(host.acknowledged, isEmpty);

      await Alarm.init(acknowledgeEventsAutomatically: true);
      await pump();

      expect(
        host.acknowledged,
        contains((42, scheduledFor.millisecondsSinceEpoch)),
      );
    });

    test(
        'an init arriving during a drain does not acknowledge what that drain '
        'handed over', () async {
      // checkAlarm is single-flight, which is what stops the init below from
      // starting a second drain: that drain would run under the new policy and
      // acknowledge an event the first one had already given the application,
      // and nothing afterwards puts the marker back.
      //
      // Guards the single-flight, not the per-event policy capture — the
      // capture closes a window between applying an event and acknowledging it
      // that no public call can be made to land in.
      final scheduledFor = DateTime.now().subtract(const Duration(hours: 2));
      await AlarmStorage.saveAlarm(buildAlarm(42, scheduledFor));
      host.pending.add(droppedEvent(42, scheduledFor));

      final seen = <AlarmEvent>[];
      Future<void>? handedBack;
      final subscription = Alarm.events.listen((event) {
        seen.add(event);
        // Another startup path initialising while this handler runs.
        handedBack ??= Alarm.init(acknowledgeEventsAutomatically: true);
      });
      addTearDown(subscription.cancel);

      await Alarm.init(acknowledgeEventsAutomatically: false);
      await pump();
      await handedBack;
      await pump();

      expect(seen, hasLength(1));
      expect(
        host.acknowledged,
        isEmpty,
        reason: 'the event was handed over under the manual boundary, so the '
            'application still owns it however the policy moved afterwards',
      );
    });
  });
}
