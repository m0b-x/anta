import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/placeholders.dart';

void main() {
  final now = DateTime(2026, 9, 26, 14, 30);
  final todayUtc = DateTime.utc(2026, 9, 26).millisecondsSinceEpoch;
  const dayMs = 24 * 60 * 60 * 1000;

  test('today resolves to UTC midnight in epoch ms', () {
    expect(resolvePlaceholders('{{today}}', now: now), '$todayUtc');
    expect(resolvePlaceholders('{{today+3}}', now: now), '${todayUtc + 3 * dayMs}');
    expect(resolvePlaceholders('{{today-1}}', now: now), '${todayUtc - dayMs}');
    expect(resolvePlaceholders('{{ today + 2 }}', now: now), '${todayUtc + 2 * dayMs}');
  });

  test('a quoted numeric placeholder sheds its quotes so JSON stays numeric', () {
    expect(
      resolvePlaceholders('{"startDateMs": "{{today+1}}"}', now: now),
      '{"startDateMs": ${todayUtc + dayMs}}',
    );
    expect(
      resolvePlaceholders('"{{weekday}}"', now: now),
      '6',
    );
  });

  test('day keeps its quotes and formats yyyy-MM-dd', () {
    expect(resolvePlaceholders('"{{day}}"', now: now), '"2026-09-26"');
    expect(resolvePlaceholders('id:calendar-day-{{day+5}}', now: now), 'id:calendar-day-2026-10-01');
    expect(resolvePlaceholders('{{day-30}}', now: now), '2026-08-27');
  });

  test('weekday, year, month and dom follow the shifted day', () {
    expect(resolvePlaceholders('{{weekday}}', now: now), '6');
    expect(resolvePlaceholders('{{weekday+2}}', now: now), '1');
    expect(resolvePlaceholders('{{year+120}}', now: now), '2027');
    expect(resolvePlaceholders('{{month+5}}', now: now), '10');
    expect(resolvePlaceholders('{{dom}}', now: now), '26');
  });

  test('longdate is the English label a day cell carries', () {
    expect(resolvePlaceholders('{{longdate}}', now: now), 'Saturday, September 26, 2026');
    expect(resolvePlaceholders('tap "{{longdate+5}}"', now: now), 'tap "Thursday, October 1, 2026"');
  });

  test('now is the instant, not midnight', () {
    expect(resolvePlaceholders('{{now}}', now: now), '${now.millisecondsSinceEpoch}');
  });

  test('text without placeholders is returned untouched, and counts are honest', () {
    const plain = 'tap "Save"';
    expect(identical(resolvePlaceholders(plain, now: now), plain), isTrue);
    expect(countPlaceholders(plain), 0);
    expect(countPlaceholders('{{today}} and "{{day+1}}"'), 2);
  });

  test('a mismatched quote pair keeps what it had', () {
    expect(resolvePlaceholders('"{{today}}', now: now), '"$todayUtc');
  });

  group('minutes ahead', () {
    // A fixture is resolved mid-minute, and the event it places starts when
    // the clock turns to the minute it named: the seconds are dropped.
    final midMinute = DateTime(2026, 9, 26, 14, 30, 45);

    /// The instant the app fires an event carrying the resolved pair at —
    /// `AlertPlanner.fireInstant`'s constructor form, on the day `minuteday`
    /// named.
    DateTime startOf(DateTime reference, int offset) {
      final sign = offset < 0 ? '-' : '+';
      final count = offset.abs();
      final day = DateTime.fromMillisecondsSinceEpoch(
        int.parse(
          resolvePlaceholders('{{minuteday$sign$count}}', now: reference),
        ),
        isUtc: true,
      );
      final minute = int.parse(
        resolvePlaceholders('{{minute$sign$count}}', now: reference),
      );
      return DateTime(day.year, day.month, day.day, 0, minute);
    }

    test('minute is the minute of the day N minutes from now, and minuteday '
        'the day it falls on', () {
      expect(
        resolvePlaceholders('{{minute+3}}', now: midMinute),
        '${14 * 60 + 33}',
      );
      expect(
        resolvePlaceholders('{{minute}}', now: midMinute),
        '${14 * 60 + 30}',
      );
      expect(
        resolvePlaceholders('{{minute-31}}', now: midMinute),
        '${13 * 60 + 59}',
      );
      expect(
        resolvePlaceholders('{{ minute + 90 }}', now: midMinute),
        '${16 * 60}',
      );
      expect(
        resolvePlaceholders('{{minuteday+3}}', now: midMinute),
        '$todayUtc',
      );
      expect(startOf(midMinute, 3), DateTime(2026, 9, 26, 14, 33));
    });

    test('across midnight the minute wraps and the day moves with it', () {
      final late = DateTime(2026, 9, 26, 23, 58, 10);
      expect(resolvePlaceholders('{{minute+1}}', now: late), '1439');
      expect(resolvePlaceholders('{{minuteday+1}}', now: late), '$todayUtc');
      expect(resolvePlaceholders('{{minute+2}}', now: late), '0');
      expect(
        resolvePlaceholders('{{minuteday+2}}', now: late),
        '${todayUtc + dayMs}',
      );
      expect(resolvePlaceholders('{{minute+5}}', now: late), '3');
      expect(
        resolvePlaceholders('{{minuteday+5}}', now: late),
        '${todayUtc + dayMs}',
      );
      // `{{today}}` beside `{{minute+5}}` would have put this one at 00:03
      // on the day that is ending — 23 hours and 55 minutes ago.
      expect(startOf(late, 5), DateTime(2026, 9, 27, 0, 3));

      final early = DateTime(2026, 9, 26, 0, 1);
      expect(resolvePlaceholders('{{minute-2}}', now: early), '1439');
      expect(
        resolvePlaceholders('{{minuteday-2}}', now: early),
        '${todayUtc - dayMs}',
      );

      // The last minute of a month and of a year roll the date the same way.
      final yearEnd = DateTime(2026, 12, 31, 23, 59);
      expect(resolvePlaceholders('{{minute+1}}', now: yearEnd), '0');
      expect(
        resolvePlaceholders('{{minuteday+1}}', now: yearEnd),
        '${DateTime.utc(2027).millisecondsSinceEpoch}',
      );
    });

    // The clock-change days of 2026 a host is likely to live through: Europe's
    // two, then the United States'. Asserted as wall clock, the way the alert
    // planner's own daylight-saving cases are, so the cases are honest in any
    // host timezone — where none of these days changes the clock they are the
    // ordinary case, which has to hold as well. Local midnight plus a
    // `Duration` fails every one of them in a zone that does change: the
    // afternoon lands an hour out, and so does the minute after midnight.
    for (final day in [
      DateTime(2026, 3, 29),
      DateTime(2026, 10, 25),
      DateTime(2026, 3, 8),
      DateTime(2026, 11, 1),
    ]) {
      final label =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';

      test('on the clock-change day $label the pair is the wall clock N '
          'minutes on', () {
        final afternoon = DateTime(day.year, day.month, day.day, 14, 30, 20);
        expect(
          resolvePlaceholders('{{minute+3}}', now: afternoon),
          '${14 * 60 + 33}',
        );
        expect(
          resolvePlaceholders('{{minuteday+3}}', now: afternoon),
          '${DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch}',
        );
        // Three minutes of real time ahead of the minute it was resolved in,
        // which is the whole point of the pair: the alert rings then.
        final resolvedIn = DateTime(day.year, day.month, day.day, 14, 30);
        expect(
          startOf(afternoon, 3).difference(resolvedIn),
          const Duration(minutes: 3),
        );

        final late = DateTime(day.year, day.month, day.day, 23, 59);
        expect(resolvePlaceholders('{{minute+2}}', now: late), '1');
        expect(
          resolvePlaceholders('{{minuteday+2}}', now: late),
          '${DateTime.utc(day.year, day.month, day.day + 1).millisecondsSinceEpoch}',
        );
        expect(
          startOf(late, 2),
          DateTime(day.year, day.month, day.day + 1, 0, 1),
        );
      });
    }

    test('both shed their quotes, so a fixture is JSON before and after', () {
      const raw =
          '{"startDateMs": "{{minuteday+3}}", "startMinute": "{{minute+3}}"}';
      expect(jsonDecode(raw), isA<Map<String, dynamic>>());
      expect(countPlaceholders(raw), 2);

      final resolved = resolvePlaceholders(raw, now: midMinute);
      expect(
        resolved,
        '{"startDateMs": $todayUtc, "startMinute": ${14 * 60 + 33}}',
      );
      expect(jsonDecode(resolved), {
        'startDateMs': todayUtc,
        'startMinute': 14 * 60 + 33,
      });
    });
  });
}
