import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/quick_alarm_request.dart';

/// The request holds a tile or shortcut tap for the calendar page, once, and
/// not for long.
void main() {
  late QuickAlarmRequest request;

  setUp(() => request = QuickAlarmRequest());

  test('hands a fresh request over once', () {
    var notified = 0;
    request.addListener(() => notified++);

    request.publish();

    expect(notified, 1);
    expect(request.hasPending, isTrue);
    expect(request.take(), isTrue);
    expect(request.hasPending, isFalse);
    expect(request.take(), isFalse);
  });

  test('a second tap before the first is served is the same tap', () {
    request.publish();
    request.publish();

    expect(request.take(), isTrue);
    expect(request.take(), isFalse);
  });

  test('a request nobody served within the freshness window is dropped', () {
    var now = DateTime(2026, 9, 23, 7);
    request.clock = () => now;
    request.publish();
    now = now.add(QuickAlarmRequest.freshness + const Duration(seconds: 1));

    expect(request.take(), isFalse);
  });
}
