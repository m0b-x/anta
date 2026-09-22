import 'package:alarm/alarm.dart';
import 'package:alarm/service/alarm_storage.dart';
import 'package:alarm/src/alarm_trigger_api_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_host.dart';

/// Lets already-queued microtasks run.
///
/// `Alarm.snoozed` is a broadcast stream, so a listener is notified in a
/// microtask rather than synchronously with the `add`.
Future<void> pump() => Future<void>.delayed(Duration.zero);

/// Delivers the snooze the way the host would when an engine is attached.
Future<void> hostReportsSnooze(int alarmId, DateTime nextRingAt) =>
    hostReportsEvent(snoozeEvent(alarmId, nextRingAt));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHost host;

  AlarmSettings buildAlarm(
    int id,
    DateTime dateTime, {
    Duration? snoozeDuration = const Duration(minutes: 9),
  }) {
    return AlarmSettings(
      id: id,
      dateTime: dateTime,
      volumeSettings: const VolumeSettings.fixed(),
      androidSnoozeDuration: snoozeDuration,
      notificationSettings: const NotificationSettings(
        title: 'Wake up',
        body: '',
        androidSnoozeButton: 'Snooze',
      ),
    );
  }

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

  group('snooze reconciliation on init', () {
    test(
      'B1: reopening before the snooze fires does not cancel it',
      () async {
        // The alarm rang at its original time and the user snoozed from the
        // notification with no engine running, so Dart still has the original
        // past time. Reopening the app must not read that as a missed alarm.
        final originalTime =
            DateTime.now().subtract(const Duration(minutes: 2));
        final nextRingAt = DateTime.now().add(const Duration(minutes: 7));
        await AlarmStorage.saveAlarm(buildAlarm(42, originalTime));
        host.pending.add(
          snoozeEvent(42, nextRingAt),
        );

        await Alarm.init();

        expect(
          host.calls,
          isNot(contains('stopAlarm')),
          reason: 'the snoozed alarm must not be stopped as if it were missed',
        );

        final stored = await Alarm.getAlarm(42);
        expect(stored, isNotNull);
        expect(
          stored!.dateTime.millisecondsSinceEpoch,
          nextRingAt.millisecondsSinceEpoch,
          reason: 'Dart storage must hold the shifted time, not the original',
        );
      },
    );

    test('B2: a marker recorded with no engine is applied on the next init',
        () async {
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      await AlarmStorage.saveAlarm(
        buildAlarm(7, DateTime.now().subtract(const Duration(minutes: 1))),
      );
      host.pending.add(
        snoozeEvent(7, nextRingAt),
      );

      await Alarm.init();

      expect(Alarm.scheduled.value.containsId(7), isTrue);
      expect(Alarm.ringing.value.containsId(7), isFalse);
    });

    test('reaches a listener that subscribes after init', () async {
      // The setup the README recommends is `await Alarm.init()` in main, so the
      // realistic listener attaches afterwards. Before Alarm.snoozed became a
      // view over the buffered events stream, a deferral replayed during init
      // reached only listeners that already existed — which that ordering made
      // unlikely.
      final nextRingAt = DateTime.now().add(const Duration(minutes: 5));
      await AlarmStorage.saveAlarm(
        buildAlarm(21, DateTime.now().subtract(const Duration(minutes: 1))),
      );
      host.pending.add(snoozeEvent(21, nextRingAt));

      await Alarm.init();

      final seen = <({int id, DateTime nextRingAt})>[];
      // Deprecated in favour of Alarm.events, but still shipped, and this
      // group is the coverage that keeps it behaving as documented.
      // ignore: deprecated_member_use_from_same_package
      final subscription = Alarm.snoozed.listen(seen.add);
      addTearDown(subscription.cancel);
      await pump();

      expect(seen, hasLength(1));
      expect(seen.single.id, 21);
      expect(
        seen.single.nextRingAt.millisecondsSinceEpoch,
        nextRingAt.millisecondsSinceEpoch,
      );
    });

    test('acknowledges the marker it applied, matching id and timestamp',
        () async {
      final nextRingAt = DateTime.now().add(const Duration(minutes: 5));
      await AlarmStorage.saveAlarm(
        buildAlarm(3, DateTime.now().subtract(const Duration(minutes: 1))),
      );
      host.pending.add(
        snoozeEvent(3, nextRingAt),
      );

      await Alarm.init();

      expect(
        host.acknowledged,
        contains((3, nextRingAt.millisecondsSinceEpoch)),
      );
    });

    test('a marker whose time has already passed is refused, not applied',
        () async {
      // Applying it would rewrite the alarm to a past time, which the
      // reconciliation loop then deletes.
      final original = DateTime.now().subtract(const Duration(minutes: 30));
      final stalePending = DateTime.now().subtract(const Duration(minutes: 10));
      await AlarmStorage.saveAlarm(buildAlarm(11, original));
      host.pending.add(
        snoozeEvent(11, stalePending),
      );

      await Alarm.init();

      expect(Alarm.scheduled.value.containsId(11), isFalse);
    });

    test('rebuilds state for a marker that was already applied', () async {
      // The crash window: Dart persisted the shifted time, then the process
      // died before native could acknowledge. The marker survives and storage
      // already agrees with it, so there is nothing to write — but a fresh
      // isolate still has to surface the alarm.
      final nextRingAt = DateTime.now().add(const Duration(minutes: 7));
      await AlarmStorage.saveAlarm(buildAlarm(99, nextRingAt));
      host.pending.add(
        snoozeEvent(99, nextRingAt),
      );

      await Alarm.init();

      expect(
        Alarm.scheduled.value.containsId(99),
        isTrue,
        reason: 'an already-applied marker must not leave the alarm invisible',
      );
    });

    test('an alarm genuinely missed is still stopped', () async {
      // Guards the B1 fix against over-correcting: with no marker, a past
      // alarm that is not ringing should still be cleaned up.
      await AlarmStorage.saveAlarm(
        buildAlarm(5, DateTime.now().subtract(const Duration(hours: 1))),
      );

      await Alarm.init();

      expect(host.calls, contains('stopAlarm'));
    });
  });

  group('the documented replacement for Alarm.snoozed', () {
    // README and the example app now tell applications to filter Alarm.events
    // themselves rather than use the deprecated view. If the two ever stopped
    // agreeing, that advice would silently start losing deferrals, so pin the
    // equivalence rather than trusting the getter's one-line body.
    test('sees every deferral the deprecated stream sees, plus recordedAt',
        () async {
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      // Deliberately not nextRingAt: a marker drained on a later init was
      // recorded when the user pressed Snooze, and the whole point of the
      // field is that it answers a different question from "when does it ring".
      final recordedAt = DateTime.now().subtract(const Duration(minutes: 3));
      await AlarmStorage.saveAlarm(
        buildAlarm(23, DateTime.now().add(const Duration(minutes: 1))),
      );
      await Alarm.init();

      final viaEvents = <AlarmMoved>[];
      final subEvents = Alarm.events
          .where(
            (event) =>
                event is AlarmMoved && event.cause == AlarmEventCause.snooze,
          )
          .cast<AlarmMoved>()
          .listen(viaEvents.add);
      final viaSnoozed = <({int id, DateTime nextRingAt})>[];
      // Deprecated in favour of Alarm.events, but still shipped, and this
      // group is the coverage that keeps it behaving as documented.
      // ignore: deprecated_member_use_from_same_package
      final subSnoozed = Alarm.snoozed.listen(viaSnoozed.add);
      addTearDown(subEvents.cancel);
      addTearDown(subSnoozed.cancel);

      await hostReportsEvent(
        snoozeEvent(23, nextRingAt, recordedAt: recordedAt),
      );
      await pump();

      expect(viaSnoozed, hasLength(1));
      expect(
        viaEvents.map((event) => (id: event.id, nextRingAt: event.nextRingAt)),
        viaSnoozed,
        reason: 'the filter the docs prescribe must yield the same deferrals',
      );
      expect(
        viaEvents.single.recordedAt.millisecondsSinceEpoch,
        recordedAt.millisecondsSinceEpoch,
        reason: 'the field Alarm.snoozed drops, and the reason to move; '
            'acknowledgeEvent is keyed on it',
      );
    });

    test('a deferral the platform forced reaches only the replacement',
        () async {
      // The deprecated stream deliberately means "the user snoozed". Anyone
      // migrating to the raw filter keeps that distinction only because the
      // cause is part of it.
      final nextRingAt = DateTime.now().add(const Duration(seconds: 30));
      await AlarmStorage.saveAlarm(
        buildAlarm(24, DateTime.now().subtract(const Duration(seconds: 5))),
      );
      await Alarm.init();

      final viaEvents = <AlarmEvent>[];
      final subEvents = Alarm.events.listen(viaEvents.add);
      final viaSnoozed = <({int id, DateTime nextRingAt})>[];
      // Deprecated in favour of Alarm.events, but still shipped, and this
      // group is the coverage that keeps it behaving as documented.
      // ignore: deprecated_member_use_from_same_package
      final subSnoozed = Alarm.snoozed.listen(viaSnoozed.add);
      addTearDown(subEvents.cancel);
      addTearDown(subSnoozed.cancel);

      await hostReportsEvent(refusedRingEvent(24, nextRingAt));
      await pump();

      expect(viaSnoozed, isEmpty, reason: 'the user did not snooze this');
      expect(viaEvents.single.cause, AlarmEventCause.platformRefusal);
    });
  });

  group('live snooze report', () {
    test('moves the alarm forward and emits on Alarm.snoozed', () async {
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      await AlarmStorage.saveAlarm(
        buildAlarm(21, DateTime.now().add(const Duration(minutes: 1))),
      );
      await Alarm.init();

      final events = <({int id, DateTime nextRingAt})>[];
      // Deprecated in favour of Alarm.events, but still shipped, and this
      // group is the coverage that keeps it behaving as documented.
      // ignore: deprecated_member_use_from_same_package
      final sub = Alarm.snoozed.listen(events.add);
      addTearDown(sub.cancel);

      await hostReportsSnooze(21, nextRingAt);
      await pump();

      expect(events, hasLength(1));
      expect(events.single.id, 21);
      final stored = await Alarm.getAlarm(21);
      expect(
        stored!.dateTime.millisecondsSinceEpoch,
        nextRingAt.millisecondsSinceEpoch,
      );
    });

    test('applying the same deferral twice changes nothing', () async {
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      await AlarmStorage.saveAlarm(
        buildAlarm(22, DateTime.now().add(const Duration(minutes: 1))),
      );
      await Alarm.init();

      final events = <({int id, DateTime nextRingAt})>[];
      // Deprecated in favour of Alarm.events, but still shipped, and this
      // group is the coverage that keeps it behaving as documented.
      // ignore: deprecated_member_use_from_same_package
      final sub = Alarm.snoozed.listen(events.add);
      addTearDown(sub.cancel);

      await hostReportsSnooze(22, nextRingAt);
      await pump();
      await hostReportsSnooze(22, nextRingAt);
      await pump();

      expect(
        events,
        hasLength(1),
        reason: 'a replayed marker must collapse into the live report',
      );
      final stored = await Alarm.getAlarm(22);
      expect(
        stored!.dateTime.millisecondsSinceEpoch,
        nextRingAt.millisecondsSinceEpoch,
      );
    });

    test('an older deferral cannot pull a newer one backwards', () async {
      final earlier = DateTime.now().add(const Duration(minutes: 5));
      final later = DateTime.now().add(const Duration(minutes: 15));
      await AlarmStorage.saveAlarm(
        buildAlarm(23, DateTime.now().add(const Duration(minutes: 1))),
      );
      await Alarm.init();

      await hostReportsSnooze(23, later);
      await hostReportsSnooze(23, earlier);

      final stored = await Alarm.getAlarm(23);
      expect(
        stored!.dateTime.millisecondsSinceEpoch,
        later.millisecondsSinceEpoch,
      );
    });

    test('the reply to the host waits for Dart to persist', () async {
      // The host drops its marker on the strength of this reply, so replying
      // before the write lands would lose the deferral to a crash in between.
      final nextRingAt = DateTime.now().add(const Duration(minutes: 9));
      await AlarmStorage.saveAlarm(
        buildAlarm(31, DateTime.now().add(const Duration(minutes: 1))),
      );
      await Alarm.init();

      await hostReportsSnooze(31, nextRingAt);

      // handlePlatformMessage completes only once the handler's future does,
      // so by here the write must already be visible.
      final stored = await Alarm.getAlarm(31);
      expect(
        stored!.dateTime.millisecondsSinceEpoch,
        nextRingAt.millisecondsSinceEpoch,
      );
    });
  });
}
