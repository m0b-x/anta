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

  group('CalendarTintConflict.fromName', () {
    test('round-trips every value', () {
      for (final conflict in CalendarTintConflict.values) {
        expect(CalendarTintConflict.fromName(conflict.name), conflict);
      }
    });

    test('falls back to eventWins on null or an unknown name', () {
      expect(
        CalendarTintConflict.fromName(null),
        CalendarTintConflict.eventWins,
      );
      expect(CalendarTintConflict.fromName(''), CalendarTintConflict.eventWins);
      expect(
        CalendarTintConflict.fromName('event'),
        CalendarTintConflict.eventWins,
      );
      expect(
        CalendarTintConflict.fromName('EventWins'),
        CalendarTintConflict.eventWins,
      );
    });
  });

  group('CalendarAppearance tint fields', () {
    test('event tinting is off by default and defers to the event', () {
      const appearance = CalendarAppearance();
      expect(appearance.eventTint, isFalse);
      expect(appearance.tintConflict, CalendarTintConflict.eventWins);
    });

    test('copyWith carries eventTint and it is an equality input', () {
      const base = CalendarAppearance();
      final tinted = base.copyWith(eventTint: true);
      expect(tinted.eventTint, isTrue);
      expect(tinted, isNot(base));
      expect(tinted.copyWith(), tinted);
    });

    test('copyWith carries tintConflict and it is an equality input', () {
      const base = CalendarAppearance(eventTint: true);
      final both = base.copyWith(tintConflict: CalendarTintConflict.both);
      expect(both.tintConflict, CalendarTintConflict.both);
      expect(both, isNot(base));
      expect(both.copyWith(), both);
    });
  });
}
