import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/alert_skip_notice.dart';

/// The notice holds a Skip for the calendar page. It holds one only for the
/// active database: two databases restored from one backup share event ids,
/// so the id alone could find the wrong event's occurrence (the positive
/// check A3's removal makes).
void main() {
  AlertPayload payloadOf(String database) => AlertPayload(
    database: database,
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: DateTime.utc(2026, 9, 22).millisecondsSinceEpoch,
    osId: 7,
    mode: AlertMode.ring,
    title: 'Leg day',
    timeLabel: '07:00',
    categoryId: 'gym',
  );

  late AlertSkipNotice notice;

  setUp(() => notice = AlertSkipNotice());

  test("holds a request for the active database, and hands it over once", () {
    notice.publish(payloadOf('personal'), activeDatabase: 'personal');
    expect(notice.hasPending, isTrue);
    expect(notice.take()?.database, 'personal');
    expect(notice.hasPending, isFalse);
    expect(notice.take(), isNull);
  });

  test("holds nothing for another database's alarm", () {
    var notified = 0;
    notice.addListener(() => notified++);
    notice.publish(payloadOf('personal'), activeDatabase: 'personal-copy');
    expect(notice.hasPending, isFalse);
    expect(notified, 0);
  });

  test('a request nobody served within the freshness window is dropped', () {
    var now = DateTime(2026, 9, 22, 7);
    notice.clock = () => now;
    notice.publish(payloadOf('personal'), activeDatabase: 'personal');
    now = now.add(AlertSkipNotice.freshness + const Duration(seconds: 1));
    expect(notice.take(), isNull);
  });
}
