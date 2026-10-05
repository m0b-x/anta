import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/alert_keep_notice.dart';

/// The notice holds a Keep for the calendar page: the write went through the
/// event service, which tells nobody, and the page that can reload is usually
/// not on screen when Keep is pressed — an alarm page is over it, or there is
/// no calendar open at all.
void main() {
  late AlertKeepNotice notice;

  setUp(() => notice = AlertKeepNotice());

  test('holds a Keep until a calendar takes it, and hands it over once', () {
    var notified = 0;
    notice.addListener(() => notified++);
    expect(notice.hasPending, isFalse);

    notice.publish();

    expect(notified, 1);
    expect(notice.hasPending, isTrue);
    expect(notice.take(), isTrue);
    expect(notice.hasPending, isFalse);
    expect(notice.take(), isFalse);
  });

  test('with nothing kept there is nothing to take', () {
    expect(notice.take(), isFalse);
    expect(notice.hasPending, isFalse);
  });

  test('two Keeps before a calendar shows are one reload', () {
    // The calendar re-reads every event whichever one was kept, so a second
    // Keep adds nothing to what is owed.
    notice.publish();
    notice.publish();

    expect(notice.take(), isTrue);
    expect(notice.take(), isFalse);
  });

  test('a suite can drop what another left behind', () {
    notice.publish();

    notice.clearForTesting();

    expect(notice.hasPending, isFalse);
    expect(notice.take(), isFalse);
  });
}
