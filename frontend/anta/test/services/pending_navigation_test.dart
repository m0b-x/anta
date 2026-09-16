import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/pending_navigation.dart';

/// The queue exists because a cold-start tap arrives before there is a
/// `Navigator`, and because the notification plugin delivers that tap twice —
/// once through the response callback and once through the launch details.
void main() {
  AlertPayload payloadOf(int osId, {String eventId = 'e1'}) => AlertPayload(
    database: 'gym_notes',
    eventId: eventId,
    alertId: 'a$osId',
    dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
    osId: osId,
    mode: AlertMode.notify,
    title: 'Leg day',
    timeLabel: '07:00',
    categoryId: 'gym',
  );

  late PendingNavigationQueue queue;

  setUp(() => queue = PendingNavigationQueue());

  test('an intent takes its id from the payload', () {
    expect(OpenEventIntent(payload: payloadOf(17)).osId, 17);
    expect(OpenAlarmIntent(payload: payloadOf(18)).osId, 18);
  });

  test('queues in arrival order', () {
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    queue.enqueue(OpenAlarmIntent(payload: payloadOf(2)));
    queue.enqueue(OpenEventIntent(payload: payloadOf(3)));

    expect(queue.drain().map((intent) => intent.osId), [1, 2, 3]);
    expect(queue.isEmpty, isTrue);
  });

  test('dedupes on osId while queued', () {
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));

    expect(queue.length, 1);
    expect(queue.drain(), hasLength(1));
  });

  test('dedupes the second half of a delivery that straddles a drain', () {
    // The real shape of the double delivery: the response callback lands, the
    // app drains it, and `getNotificationAppLaunchDetails()` reports the same
    // tap 8 ms later.
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    expect(queue.drain(), hasLength(1));

    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    expect(queue.isEmpty, isTrue);
  });

  test('only the last drain is remembered', () {
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    queue.drain();
    queue.enqueue(OpenEventIntent(payload: payloadOf(2)));
    queue.drain();

    // Two drains later the first id is a new tap again, not an echo.
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    expect(queue.drain().single.osId, 1);
  });

  test('the dedupe memory expires, so a later ring of the same id lands', () {
    // The os id of a snooze is a hash of (database, alert, day, kind), so
    // snoozing the same alert twice on the same day re-arms it under exactly
    // the id the first ring already used. Without an expiry the second ring
    // is dropped as an echo — hours later, with the phone making noise and no
    // page to stop it.
    var now = DateTime(2026, 9, 20, 7);
    queue.clock = () => now;

    queue.enqueue(OpenAlarmIntent(payload: payloadOf(1)));
    expect(queue.drain().single.osId, 1);

    // Still inside the window: this is the notification plugin's cold-start
    // double delivery, which arrives milliseconds apart.
    now = now.add(const Duration(milliseconds: 8));
    queue.enqueue(OpenAlarmIntent(payload: payloadOf(1)));
    expect(queue.isEmpty, isTrue);

    // Past it: a new ring, whatever id it carries.
    now = now.add(PendingNavigationQueue.doubleDeliveryWindow);
    queue.enqueue(OpenAlarmIntent(payload: payloadOf(1)));
    expect(queue.drain().single.osId, 1);
  });

  test('notifies only when something was actually added', () {
    var notifications = 0;
    queue.addListener(() => notifications++);

    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));

    expect(notifications, 1);
  });

  test('draining an empty queue hands back nothing and forgets nothing', () {
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    queue.drain();

    expect(queue.drain(), isEmpty);
    // The empty drain must not have cleared the dedupe memory.
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    expect(queue.isEmpty, isTrue);
  });

  test('nothing is handed out until the holder asks', () {
    // The queue never pushes: it holds until `_MyAppState` drains it, which is
    // what keeps a cold-start tap from reaching a null navigator.
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    expect(queue.isEmpty, isFalse);
    expect(queue.length, 1);
  });

  test('clearForTesting drops the dedupe memory too', () {
    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    queue.drain();
    queue.clearForTesting();

    queue.enqueue(OpenEventIntent(payload: payloadOf(1)));
    expect(queue.length, 1);
  });

  test('the app-wide instance is a singleton', () {
    expect(
      identical(PendingNavigationQueue.instance, PendingNavigationQueue.instance),
      isTrue,
    );
  });
}
