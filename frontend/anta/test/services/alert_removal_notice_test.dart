import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_removal_notice.dart';

/// The notice is what turns A3's silent deletion into an offer, and it waits
/// for a calendar that may not exist yet — so the two properties worth pinning
/// are that it survives until someone takes it, and that it does not survive
/// forever.
void main() {
  final event = CalendarEvent(
    id: 'e1',
    title: 'Wake up',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 9, 20),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 7 * 60),
    removeAfterAlert: true,
  );

  const alerts = [
    EventAlert(id: 'a1', eventId: 'e1', mode: AlertMode.ring),
  ];

  final notice = AlertRemovalNotice.instance;

  tearDown(notice.clearForTesting);

  test('a notice waits until it is taken, then is gone', () {
    var notified = 0;
    void listener() => notified++;
    notice.addListener(listener);
    addTearDown(() => notice.removeListener(listener));

    notice.publish(event, alerts);

    expect(notified, 1);
    expect(notice.hasPending, isTrue);
    final taken = notice.take();
    expect(taken?.event.id, 'e1');
    // The cascade tombstoned them, so Undo needs them back.
    expect(taken?.alerts, alerts);
    expect(notice.take(), isNull);
  });

  test('a stale notice is dropped rather than offered', () {
    var now = DateTime(2026, 9, 20, 7);
    notice.clock = () => now;

    notice.publish(event, alerts);
    now = now.add(AlertRemovalNotice.freshness + const Duration(seconds: 1));

    expect(notice.take(), isNull);
    expect(notice.hasPending, isFalse);
  });
}
