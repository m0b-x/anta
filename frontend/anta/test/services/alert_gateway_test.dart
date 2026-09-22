import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/utils/alert_planner.dart';

/// The no-op binding is what keeps `flutter test` honest: nothing in the test
/// tree stubs an alert plugin channel because nothing in the test tree can
/// reach one. It is also what desktop and web run, so it has to be a complete,
/// silent implementation rather than a pile of `UnimplementedError`s.
void main() {
  const gateway = NoOpAlertGateway();

  final fire = PlannedFire(
    event: CalendarEvent(
      id: 'e1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 9, 20),
      rule: const OneTimeRecurrence(),
      time: const EventTime(startMinute: 18 * 60),
    ),
    alert: const EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
    day: DateTime.utc(2026, 9, 20),
    fireAt: DateTime(2026, 9, 20, 18),
    kind: AlertKind.scheduled,
  );

  const payload = AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: 1789862400000,
    osId: 1,
    mode: AlertMode.ring,
    title: 'Leg day',
    timeLabel: '18:00',
    categoryId: 'gym',
  );

  test('it names itself, and says it cannot see the platform', () {
    expect(gateway.backendName, 'none');
    // False is what stops reconcile from reading its silence as "the OS holds
    // nothing" and cancelling the whole horizon on every pass.
    expect(gateway.tracksPending, isFalse);
  });

  test('a schedule is accepted and holds nothing', () async {
    expect(await gateway.schedule(fire, payload), isTrue);
    expect(
      await gateway.schedule(fire, payload, noticeAt: DateTime(2026, 9, 20, 16)),
      isTrue,
    );
    expect(await gateway.pendingEntries(), isEmpty);
    expect(await gateway.pendingIds(), isEmpty);
  });

  test('the remaining calls are silent, not missing', () async {
    await gateway.cancel(1);
    await gateway.showMissed(payload);
    await gateway.stopRinging(1);
    await gateway.dispose();

    expect(await gateway.ringing.toList(), isEmpty);
    expect(await gateway.showAlarms.toList(), isEmpty);
    expect(await gateway.launchIntent(), isNull);
    // Nothing can snooze on its own where nothing rings.
    expect(await gateway.takeMoves(), isEmpty);
    await gateway.acknowledgeMove((
      osId: 1,
      nextRingAt: DateTime(2026, 9, 20, 18, 10),
      recordedAt: DateTime(2026, 9, 20, 18),
    ));
  });

  test('pendingIds is derived from pendingEntries on the interface', () async {
    // The §3.1 spelling stays, but the platform is asked once: a binding only
    // has to implement `pendingEntries`.
    final probe = _EntriesOnlyGateway([
      (osId: 7, payload: payload),
      (osId: 9, payload: payload),
    ]);

    expect(await probe.pendingIds(), {7, 9});
  });

  test('availability is the SyncAvailability rule, phones only', () {
    expect(
      AlertAvailability.isSupported,
      Platform.isAndroid || Platform.isIOS,
    );
    // The test host is a desktop, so this is also the assertion that desktop
    // stays plan-only.
    expect(AlertAvailability.isSupported, isFalse);
  });
}

/// A binding that implements only [AlertGateway.pendingEntries], to prove the
/// interface derives the ids rather than asking the platform twice.
class _EntriesOnlyGateway extends NoOpAlertGateway {
  const _EntriesOnlyGateway(this.entries);

  final List<PendingAlertEntry> entries;

  @override
  Future<List<PendingAlertEntry>> pendingEntries() async => entries;
}
