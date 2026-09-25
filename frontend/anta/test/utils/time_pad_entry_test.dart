import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/time_pad_entry.dart';

TimePadEntry run(
  String keys, {
  int from = 9 * 60,
  bool use24h = true,
  int? after,
}) {
  var entry = TimePadEntry.open(
    initialMinute: from,
    use24h: use24h,
    periodAfter: after,
  );
  for (final key in keys.split('')) {
    entry = switch (key) {
      '<' => entry.backspace(),
      'z' => entry.pressShortcut(0),
      'h' => entry.pressShortcut(30),
      'a' => entry.pressPeriod(TimePadPeriod.am),
      'p' => entry.pressPeriod(TimePadPeriod.pm),
      '!' => entry.finish(),
      'M' => entry.selectPart(TimePadPart.minute),
      'H' => entry.selectPart(TimePadPart.hour),
      _ => entry.pressDigit(int.parse(key)),
    };
  }
  return entry;
}

String hhmm(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:'
    '${(value % 60).toString().padLeft(2, '0')}';

List<int> liveDigits(TimePadEntry entry) => [
  for (var d = 0; d <= 9; d++)
    if (entry.canPressDigit(d)) d,
];

void main() {
  group('24-hour entries that finish on their own', () {
    const cases = <(String, int, String)>[
      ('1830', 9 * 60, '18:30'),
      ('930', 9 * 60, '09:30'),
      ('745', 9 * 60, '07:45'),
      ('0745', 9 * 60, '07:45'),
      ('2359', 9 * 60, '23:59'),
      ('0000', 9 * 60, '00:00'),
      ('245', 9 * 60, '02:45'),
      ('18z', 9 * 60, '18:00'),
      ('7h', 9 * 60, '07:30'),
      ('1h', 9 * 60, '01:30'),
      ('2z', 9 * 60, '02:00'),
      ('h', 9 * 60, '09:30'),
      ('z', 9 * 60 + 15, '09:00'),
      ('M45', 9 * 60, '09:45'),
      ('1M30', 9 * 60, '01:30'),
      ('18<930', 9 * 60, '19:30'),
      ('9<745', 9 * 60, '07:45'),
      ('183<45', 9 * 60, '18:45'),
    ];
    for (final (keys, from, expected) in cases) {
      test('$keys from ${hhmm(from)} is $expected', () {
        final entry = run(keys, from: from);
        expect(entry.isComplete, isTrue);
        expect(hhmm(entry.value), expected);
      });
    }
  });

  group('24-hour entries still open', () {
    test('two hour digits move to the minutes and wait', () {
      final entry = run('18');
      expect(entry.isComplete, isFalse);
      expect(entry.active, TimePadPart.minute);
      expect(entry.hour, 18);
      expect(entry.pending, isEmpty);
    });

    test('an hour digit that could grow waits in place', () {
      final entry = run('1');
      expect(entry.active, TimePadPart.hour);
      expect(entry.pending, '1');
      expect(entry.hour, 9);
    });

    test('a half-typed minute previews as its tens', () {
      final entry = run('183');
      expect(entry.isComplete, isFalse);
      expect(hhmm(entry.previewValue), '18:30');
    });

    test('a pending hour previews on the minutes already there', () {
      expect(hhmm(run('2', from: 9 * 60 + 15).previewValue), '02:15');
    });

    test('Done keeps the minutes nobody touched', () {
      expect(hhmm(run('18!', from: 9 * 60 + 15).value), '18:15');
    });

    test('Done completes a half-typed minute with a zero', () {
      expect(hhmm(run('183!').value), '18:30');
    });

    test('Done takes a lone hour digit as that hour', () {
      expect(hhmm(run('1!').value), '01:00');
    });

    test('retyping the hour replaces it and keeps the minutes', () {
      final entry = run('18H07!', from: 9 * 60 + 20);
      expect(hhmm(entry.value), '07:20');
    });
  });

  group('24-hour keys that cannot make a time are off', () {
    test('any first hour digit is live', () {
      expect(liveDigits(run('')), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('after 2, digits up to 3 extend it and 4 and 5 start the minutes', () {
      expect(liveDigits(run('2')), [0, 1, 2, 3, 4, 5]);
    });

    test('after 0 or 1 every digit extends the hour', () {
      expect(liveDigits(run('0')), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(liveDigits(run('1')), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('a minute starts with 0 to 5 and ends with anything', () {
      expect(liveDigits(run('18')), [0, 1, 2, 3, 4, 5]);
      expect(liveDigits(run('184')), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('a switched-off digit changes nothing', () {
      final entry = run('2');
      expect(identical(entry.pressDigit(7), entry), isTrue);
    });
  });

  group('backspace', () {
    test('steps from the empty minutes back into the typed hour', () {
      final entry = run('18<');
      expect(entry.active, TimePadPart.hour);
      expect(entry.pending, '1');
      expect(entry.hour, 9);
    });

    test('has nothing to delete on an untouched hour', () {
      final entry = run('');
      expect(entry.canBackspace, isFalse);
      expect(identical(entry.backspace(), entry), isTrue);
    });
  });

  group('12-hour entries', () {
    test('1 3 0 is 1:30 and waits for AM or PM', () {
      final entry = run('130', use24h: false);
      expect(entry.isComplete, isFalse);
      expect(entry.awaitingPeriod, isTrue);
      expect(entry.periodIsSuggestion, isTrue);
      expect(hhmm(entry.value), '13:30');
    });

    test('AM or PM finishes the entry', () {
      expect(hhmm(run('130p', use24h: false).value), '13:30');
      expect(hhmm(run('130a', use24h: false).value), '01:30');
      expect(run('130a', use24h: false).isComplete, isTrue);
    });

    test('Done keeps the suggested period', () {
      final entry = run('130!', use24h: false);
      expect(entry.isComplete, isTrue);
      expect(hhmm(entry.value), '13:30');
    });

    test('a period chosen first lets the minutes finish the entry', () {
      final entry = run('p130', use24h: false);
      expect(entry.isComplete, isTrue);
      expect(hhmm(entry.value), '13:30');
    });

    test('twelve is midnight in the morning and noon after', () {
      expect(hhmm(run('1230a', use24h: false).value), '00:30');
      expect(hhmm(run('1230p', use24h: false).value), '12:30');
    });

    test('a leading zero is accepted', () {
      expect(hhmm(run('0930a', use24h: false).value), '09:30');
    });

    test('an untouched hour keeps its period and finishes on the minutes', () {
      final entry = run('h', from: 21 * 60, use24h: false);
      expect(entry.isComplete, isTrue);
      expect(hhmm(entry.value), '21:30');
    });

    test('the suggestion is the one nearest the time it opened on', () {
      expect(hhmm(run('7h!', from: 9 * 60, use24h: false).value), '07:30');
      expect(hhmm(run('7h!', from: 17 * 60, use24h: false).value), '19:30');
    });

    test('an end time suggests the first one after the start', () {
      final entry = run('130!', from: 23 * 60, use24h: false, after: 22 * 60);
      expect(hhmm(entry.value), '01:30');
    });

    test('after 1, 0 to 2 extend it and 3 to 5 start the minutes', () {
      expect(liveDigits(run('1', use24h: false)), [0, 1, 2, 3, 4, 5]);
    });

    test('a lone 0 cannot stand as an hour', () {
      final entry = run('0', use24h: false);
      expect(liveDigits(entry), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(entry.canPressShortcut, isFalse);
      expect(entry.canFinish, isFalse);
    });

    test('backspace from the period question reopens the minutes', () {
      final entry = run('145<', use24h: false);
      expect(entry.awaitingPeriod, isFalse);
      expect(entry.active, TimePadPart.minute);
      expect(entry.pending, '4');
    });

    test('labels drop the leading zero', () {
      final entry = run('', from: 9 * 60 + 5, use24h: false);
      expect(entry.hourLabel, '9');
      expect(entry.minuteLabel, '05');
      expect(run('', from: 9 * 60 + 5).hourLabel, '09');
    });
  });

  test('a finished entry ignores every key', () {
    final entry = run('1830');
    expect(entry.isComplete, isTrue);
    expect(identical(entry.pressDigit(1), entry), isTrue);
    expect(identical(entry.backspace(), entry), isTrue);
    expect(identical(entry.finish(), entry), isTrue);
    expect(identical(entry.selectPart(TimePadPart.hour), entry), isTrue);
  });

  test('an opening value past midnight wraps into the day', () {
    final entry = TimePadEntry.open(initialMinute: 1500, use24h: true);
    expect(hhmm(entry.value), '01:00');
  });
}
