import 'dart:ui' show Brightness;

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

  group('CalendarCellStyle.fromName', () {
    test('round-trips every value', () {
      for (final style in CalendarCellStyle.values) {
        expect(CalendarCellStyle.fromName(style.name), style);
      }
    });

    test('falls back to solid on null', () {
      expect(CalendarCellStyle.fromName(null), CalendarCellStyle.solid);
    });

    test('falls back to solid on an unknown name', () {
      expect(CalendarCellStyle.fromName(''), CalendarCellStyle.solid);
      expect(CalendarCellStyle.fromName('gradient'), CalendarCellStyle.solid);
      expect(CalendarCellStyle.fromName('Solid'), CalendarCellStyle.solid);
      expect(CalendarCellStyle.fromName('  fade'), CalendarCellStyle.solid);
    });
  });

  group('CalendarAppearance cell style fields', () {
    test('both themes default to solid, the look that already shipped', () {
      const appearance = CalendarAppearance();
      expect(appearance.cellStyleLight, CalendarCellStyle.solid);
      expect(appearance.cellStyleDark, CalendarCellStyle.solid);
    });

    test('cellStyleFor picks the field matching the brightness', () {
      const appearance = CalendarAppearance(
        cellStyleLight: CalendarCellStyle.outline,
        cellStyleDark: CalendarCellStyle.fade,
      );
      expect(
        appearance.cellStyleFor(Brightness.light),
        CalendarCellStyle.outline,
      );
      expect(appearance.cellStyleFor(Brightness.dark), CalendarCellStyle.fade);
    });

    test('the two fields are independent', () {
      const base = CalendarAppearance();
      final lightOnly = base.copyWith(cellStyleLight: CalendarCellStyle.fade);

      // The whole point of the setting: softening the light grid must leave
      // the dark one exactly as it was.
      expect(lightOnly.cellStyleLight, CalendarCellStyle.fade);
      expect(lightOnly.cellStyleDark, CalendarCellStyle.solid);
      expect(
        lightOnly.cellStyleFor(Brightness.dark),
        base.cellStyleFor(Brightness.dark),
      );
    });

    test('copyWith carries both and each is an equality input', () {
      const base = CalendarAppearance();
      final light = base.copyWith(cellStyleLight: CalendarCellStyle.outline);
      final dark = base.copyWith(cellStyleDark: CalendarCellStyle.outline);

      expect(light, isNot(base));
      expect(dark, isNot(base));
      expect(light, isNot(dark));
      expect(light.copyWith(), light);
      expect(dark.copyWith(), dark);
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
