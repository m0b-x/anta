import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_appearance.dart';

void main() {
  group('CalendarMissedDisplay.fromName', () {
    test('round-trips every value', () {
      for (final display in CalendarMissedDisplay.values) {
        expect(CalendarMissedDisplay.fromName(display.name), display);
      }
    });

    test('falls back to faded on null', () {
      expect(CalendarMissedDisplay.fromName(null), CalendarMissedDisplay.faded);
    });

    test('falls back to faded on an unknown name', () {
      expect(
        CalendarMissedDisplay.fromName('dimmed'),
        CalendarMissedDisplay.faded,
      );
      expect(CalendarMissedDisplay.fromName(''), CalendarMissedDisplay.faded);
      expect(
        CalendarMissedDisplay.fromName('Faded'),
        CalendarMissedDisplay.faded,
      );
    });
  });

  group('CalendarAppearance', () {
    test('defaults missedDisplay to faded', () {
      expect(
        const CalendarAppearance().missedDisplay,
        CalendarMissedDisplay.faded,
      );
    });

    test('copyWith carries missedDisplay and it is an equality input', () {
      const base = CalendarAppearance();
      final hidden = base.copyWith(missedDisplay: CalendarMissedDisplay.hidden);
      expect(hidden.missedDisplay, CalendarMissedDisplay.hidden);
      expect(hidden, isNot(base));
      expect(hidden.copyWith(), hidden);
    });
  });
}
