import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/utils/alert_labels.dart';

/// The labels in a process where **no date symbols were ever loaded** — which
/// is why this file is its own: `intl` keeps them per isolate, a suite runs
/// in one, and nothing here may call `initializeDateFormatting`.
///
/// It is the state of almost every suite that reaches the scheduler, and the
/// state a label must survive wherever it is written: a write runs inside the
/// pass that arms an alarm, and one that throws takes the alarm with it.
void main() {
  final sunday = DateTime.utc(2026, 9, 20);
  final monday = DateTime.utc(2026, 9, 21);
  const session = EventTime(startMinute: 18 * 60, durationMinutes: 90);

  test('the fixed labels write times and days with nothing loaded', () {
    // `en_US` is the one locale `intl` answers for out of the box, which is
    // what lets every scheduler suite stamp with these and load nothing.
    expect(
      AlertLabels.fixed.whenLabel(
        time: session,
        day: monday,
        fireAt: DateTime(2026, 9, 20, 0, 18 * 60),
      ),
      'Mon, Sep 21 · 18:00 – 19:30',
    );
    expect(
      AlertLabels.fixed.dayLabel(
        fireAt: DateTime(2026, 9, 21, 0, 30),
        noticeAt: DateTime(2026, 9, 20, 0, 22 * 60 + 30),
      ),
      'Mon, Sep 21',
    );
    expect(
      AlertLabels.fixed.untilLabel(DateTime(2026, 9, 20, 0, 19 * 60 + 30)),
      '19:30',
    );
    expect(
      AlertLabels.fixed.timeLabel(DateTime(2026, 9, 20, 0, 18 * 60)),
      '18:00',
    );
  });

  test('labels in a language with no symbols loaded are left out, '
      'never thrown', () {
    final german = AlertLabels(
      strings: lookupAppLocalizations(const Locale('de')),
      use24Hour: false,
    );
    final due = DateTime(2026, 9, 20, 0, 9 * 60);

    // No caption is what every reader already draws for an entry that has
    // none; a missing day and the neutral clock are the same kind of answer.
    expect(german.whenLabel(time: session, day: sunday, fireAt: due), '');
    expect(german.whenLabel(time: null, day: monday, fireAt: due), '');
    expect(
      german.dayLabel(
        fireAt: DateTime(2026, 9, 21, 0, 30),
        noticeAt: DateTime(2026, 9, 20, 0, 22 * 60 + 30),
      ),
      isNull,
    );
    expect(german.untilLabel(DateTime(2026, 9, 20, 0, 19 * 60 + 30)), '19:30');
    // The due time is the one label an entry cannot do without: it falls to
    // the neutral clock like the chip's end, never to nothing.
    expect(german.timeLabel(due), '09:00');
    // What needs no symbols is still written.
    expect(german.whenLabel(time: null, day: sunday, fireAt: due), 'Ganztägig');
    expect(german.languageCode, 'de');
  });
}
