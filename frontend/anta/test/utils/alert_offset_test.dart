import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/event_alert.dart';
import 'package:anta/utils/alert_offset.dart';

/// The custom alert offset's arithmetic with no widget in sight: the sheet
/// that steps it only shows what these say. The rules are the ones the alert
/// sheet's state carried before they were hoisted, so every table here is
/// also what that sheet did.
void main() {
  const minute = AlertOffsetUnit.minutes;
  const hour = AlertOffsetUnit.hours;
  const day = AlertOffsetUnit.days;
  const perDay = EventAlert.minutesPerDay;

  AlertOffset timed(int minutes) => AlertOffset.seed(minutes, allDay: false);
  AlertOffset allDay(int days) => AlertOffset.seed(days, allDay: true);

  group('the unit is a view over minutes', () {
    test('each unit is a whole number of minutes', () {
      expect(minute.multiplier, 1);
      expect(hour.multiplier, 60);
      expect(day.multiplier, perDay);
    });

    test('a timed offset stores minutes whatever it is counted in', () {
      const cases = <({int stored, AlertOffsetUnit unit, int value})>[
        (stored: 45, unit: minute, value: 45),
        (stored: 120, unit: hour, value: 2),
        (stored: 2 * perDay, unit: day, value: 2),
      ];
      for (final c in cases) {
        final offset = timed(c.stored);
        expect(offset.unit, c.unit, reason: '${c.stored} min');
        expect(offset.value, c.value, reason: '${c.stored} min');
        expect(offset.minutes, c.stored, reason: '${c.stored} min');
        expect(offset.stored, c.stored, reason: '${c.stored} min');
      }
    });
  });

  group('the natural unit', () {
    test('is days for whole days, hours for whole hours, else minutes', () {
      const cases = <int, AlertOffsetUnit>{
        0: minute,
        1: minute,
        59: minute,
        60: hour,
        61: minute,
        90: minute,
        120: hour,
        23 * 60: hour,
        perDay: day,
        25 * 60: hour,
        36 * 60: hour,
        2 * perDay: day,
        30 * perDay: day,
        30 * perDay + 1: minute,
      };
      cases.forEach((minutes, unit) {
        expect(AlertOffset.naturalUnitOf(minutes), unit, reason: '$minutes');
      });
    });

    test('a negative number has none and reads as minutes', () {
      expect(AlertOffset.naturalUnitOf(-60), minute);
      expect(AlertOffset.naturalUnitOf(-perDay), minute);
    });
  });

  group('the seed', () {
    test('opens a timed offset in its natural unit, clamped to its range', () {
      const cases = <({int stored, AlertOffsetUnit unit, int value})>[
        (stored: 1, unit: minute, value: 1),
        (stored: 5, unit: minute, value: 5),
        (stored: 59, unit: minute, value: 59),
        (stored: 60, unit: hour, value: 1),
        (stored: 23 * 60, unit: hour, value: 23),
        (stored: perDay, unit: day, value: 1),
        (stored: 7 * perDay, unit: day, value: 7),
        (stored: 30 * perDay, unit: day, value: 30),
        // What the stepper cannot count opens on the bound of its unit.
        (stored: 90, unit: minute, value: 59),
        (stored: 36 * 60, unit: hour, value: 23),
        (stored: 31 * perDay, unit: day, value: 30),
      ];
      for (final c in cases) {
        final offset = timed(c.stored);
        expect(offset.unit, c.unit, reason: '${c.stored} min');
        expect(offset.value, c.value, reason: '${c.stored} min');
        expect(offset.allDay, isFalse);
      }
    });

    test('is never under 1: "at start" opens on one minute', () {
      final atStart = timed(0);
      expect(atStart.unit, minute);
      expect(atStart.value, 1);
      expect(atStart.stored, 1);

      final negative = timed(-30);
      expect(negative.unit, minute);
      expect(negative.value, 1);
    });

    test('opens an all-day offset in days, 1 to 30', () {
      const cases = <int, int>{0: 1, 1: 1, 2: 2, 7: 7, 30: 30, 31: 30, 45: 30};
      cases.forEach((stored, value) {
        final offset = allDay(stored);
        expect(offset.unit, day, reason: '$stored days');
        expect(offset.value, value, reason: '$stored days');
        expect(offset.allDay, isTrue);
      });
    });
  });

  group('the bounds', () {
    test('are 1 to 59 minutes, 1 to 23 hours and 1 to 30 days', () {
      expect(AlertOffset.min, 1);
      expect(minute.max, 59);
      expect(hour.max, 23);
      expect(day.max, 30);
    });

    test('stepping stops at the floor of every unit', () {
      for (final unit in AlertOffsetUnit.values) {
        final floor = timed(unit.multiplier);
        expect(floor.unit, unit);
        expect(floor.value, 1);
        expect(floor.canDecrement, isFalse, reason: unit.name);
        expect(floor.canIncrement, isTrue, reason: unit.name);
        expect(floor.decremented, floor, reason: unit.name);
        expect(floor.incremented.value, 2, reason: unit.name);
      }
    });

    test('stepping stops at the ceiling of every unit', () {
      for (final unit in AlertOffsetUnit.values) {
        final ceiling = timed(unit.max * unit.multiplier);
        expect(ceiling.unit, unit);
        expect(ceiling.value, unit.max);
        expect(ceiling.canIncrement, isFalse, reason: unit.name);
        expect(ceiling.canDecrement, isTrue, reason: unit.name);
        expect(ceiling.incremented, ceiling, reason: unit.name);
        expect(ceiling.decremented.value, unit.max - 1, reason: unit.name);
      }
    });

    test('a step moves the number by one and keeps the unit', () {
      final up = timed(120).incremented;
      expect(up.unit, hour);
      expect(up.value, 3);
      expect(up.stored, 180);

      final down = timed(120).decremented;
      expect(down.unit, hour);
      expect(down.value, 1);
      expect(down.stored, 60);
    });

    test('an all-day offset steps between 1 and 30 days', () {
      expect(allDay(1).canDecrement, isFalse);
      expect(allDay(1).decremented, allDay(1));
      expect(allDay(1).incremented.stored, 2);
      expect(allDay(30).canIncrement, isFalse);
      expect(allDay(30).incremented, allDay(30));
      expect(allDay(30).decremented.stored, 29);
    });
  });

  group('a unit change', () {
    test('keeps the number, clamped into the new range', () {
      const cases =
          <({int stored, AlertOffsetUnit to, int value, int minutes})>[
            (stored: 5, to: hour, value: 5, minutes: 5 * 60),
            (stored: 5, to: day, value: 5, minutes: 5 * perDay),
            (stored: 45, to: hour, value: 23, minutes: 23 * 60),
            (stored: 45, to: day, value: 30, minutes: 30 * perDay),
            (stored: 45, to: minute, value: 45, minutes: 45),
            (stored: 23 * 60, to: minute, value: 23, minutes: 23),
            (stored: 23 * 60, to: day, value: 23, minutes: 23 * perDay),
            (stored: 30 * perDay, to: hour, value: 23, minutes: 23 * 60),
            (stored: 30 * perDay, to: minute, value: 30, minutes: 30),
          ];
      for (final c in cases) {
        final changed = timed(c.stored).withUnit(c.to);
        final reason = '${c.stored} min to ${c.to.name}';
        expect(changed.unit, c.to, reason: reason);
        expect(changed.value, c.value, reason: reason);
        expect(changed.minutes, c.minutes, reason: reason);
        expect(changed.stored, c.minutes, reason: reason);
      }
    });

    test('does not come back once it has clamped', () {
      final there = timed(45).withUnit(hour);
      expect(there.value, 23);
      expect(there.withUnit(minute).value, 23);
    });
  });

  group('an all-day event counts in days only', () {
    test('a unit change leaves it in days', () {
      final offset = allDay(3);
      expect(offset.withUnit(hour), offset);
      expect(offset.withUnit(minute), offset);
      expect(offset.withUnit(day), offset);
    });

    test('it stores days, not minutes', () {
      final offset = allDay(3);
      expect(offset.stored, 3);
      expect(offset.minutes, 3 * perDay);
      expect(offset.incremented.stored, 4);
    });

    test('a day before an all-day event is not a day before a timed one', () {
      expect(allDay(1), isNot(timed(perDay)));
      expect(allDay(1), allDay(1));
      expect(timed(perDay), timed(perDay));
    });
  });
}
