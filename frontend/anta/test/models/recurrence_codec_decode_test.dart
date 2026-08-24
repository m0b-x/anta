import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/recurrence_rule_codec.dart';

/// Guard for [RecurrenceCodec.decode] (roadmap 5.2): a weekly payload used to
/// be `jsonDecode`d twice — once each from `_decodeWeekdays` and
/// `_decodeInterval` — and the fix collapses that to a single parse per
/// [RecurrenceCodec.decode] call, threaded through as an already-decoded
/// `Map?` instead of the raw payload string.
///
/// The defensive contract that made each field extractor independently safe
/// has to survive the refactor exactly: a malformed `rule_payload` must still
/// produce a rule of the **correct kind** with defaulted fields — never a
/// throw, and never a silent collapse to [OneTimeRecurrence] — with the one
/// documented exception being [RecurrenceCodec.kSpecificDates], which falls
/// back to one-time when the *decoded* date set is empty (not when the
/// payload fails to parse; those are different failure modes that happen to
/// land on the same fallback for this one kind).
void main() {
  DateTime day(int year, int month, int d) => DateTime.utc(year, month, d);

  /// One representative, non-default-valued rule per kind the codec
  /// supports, keyed by the codec's own kind constants (not string literals)
  /// so a future rule kind that gains a `kindOf`/`decode` case but is
  /// forgotten here shows up as a missing map entry rather than a silently
  /// skipped case.
  final samples = <String, RecurrenceRule>{
    RecurrenceCodec.kOneTime: const OneTimeRecurrence(),
    RecurrenceCodec.kSpecificDates: SpecificDatesRecurrence(
      dates: {day(2026, 1, 1), day(2026, 3, 15)},
    ),
    RecurrenceCodec.kDaily: const DailyRecurrence(interval: 3),
    RecurrenceCodec.kWeekly: const WeeklyRecurrence(
      weekdays: {1, 3, 5},
      interval: 2,
    ),
    RecurrenceCodec.kMonthly: const MonthlyRecurrence(interval: 4),
    RecurrenceCodec.kYearly: const YearlyRecurrence(interval: 2),
    RecurrenceCodec.kWorkdays: const WorkdaysRecurrence(),
    RecurrenceCodec.kWeekends: const WeekendsRecurrence(),
    RecurrenceCodec.kHolidaysOnly: const PublicHolidaysOnlyRecurrence(),
  };

  /// The runtime type [RecurrenceCodec.decode] must still produce for each
  /// kind when handed a payload it cannot parse. Every kind maps to its own
  /// rule type, except [RecurrenceCodec.kSpecificDates]: an unparsable
  /// payload decodes to an empty date set, which is [RecurrenceCodec.decode]'s
  /// own documented empty-set fallback to one-time.
  final expectedKindOnMalformed = <String, Type>{
    RecurrenceCodec.kOneTime: OneTimeRecurrence,
    RecurrenceCodec.kSpecificDates: OneTimeRecurrence,
    RecurrenceCodec.kDaily: DailyRecurrence,
    RecurrenceCodec.kWeekly: WeeklyRecurrence,
    RecurrenceCodec.kMonthly: MonthlyRecurrence,
    RecurrenceCodec.kYearly: YearlyRecurrence,
    RecurrenceCodec.kWorkdays: WorkdaysRecurrence,
    RecurrenceCodec.kWeekends: WeekendsRecurrence,
    RecurrenceCodec.kHolidaysOnly: PublicHolidaysOnlyRecurrence,
  };

  group('round-trip', () {
    for (final entry in samples.entries) {
      test('${entry.key}: encode then decode is the identity', () {
        final rule = entry.value;
        final kind = RecurrenceCodec.kindOf(rule);
        expect(kind, entry.key, reason: 'kindOf must agree with the map key');
        final payload = RecurrenceCodec.payloadOf(rule);
        final decoded = RecurrenceCodec.decode(kind, payload);
        expect(decoded, rule);
      });
    }
  });

  group('weekly: single parse still resolves both fields', () {
    test('weekdays and interval both decode from one payload', () {
      const rule = WeeklyRecurrence(weekdays: {2, 4, 7}, interval: 3);
      final payload = RecurrenceCodec.payloadOf(rule);
      final decoded =
          RecurrenceCodec.decode(RecurrenceCodec.kWeekly, payload)
              as WeeklyRecurrence;
      expect(decoded.weekdays, {2, 4, 7});
      expect(decoded.interval, 3);
    });

    test('a hand-written payload with both keys decodes both', () {
      final decoded =
          RecurrenceCodec.decode(
                RecurrenceCodec.kWeekly,
                '{"weekdays":[1,6],"interval":4}',
              )
              as WeeklyRecurrence;
      expect(decoded.weekdays, {1, 6});
      expect(decoded.interval, 4);
    });
  });

  group('malformed payload lets the kind through', () {
    const garbagePayloads = [
      'not json',
      '{',
      '[]',
      '{"weekdays": "nope"}',
    ];

    for (final entry in expectedKindOnMalformed.entries) {
      final kind = entry.key;
      final expectedType = entry.value;
      for (final garbage in garbagePayloads) {
        test('$kind with payload `$garbage` stays $expectedType', () {
          late RecurrenceRule decoded;
          expect(
            () => decoded = RecurrenceCodec.decode(kind, garbage),
            returnsNormally,
          );
          expect(decoded.runtimeType, expectedType);
        });
      }
    }

    test('daily: garbage payload defaults interval to 1', () {
      for (final garbage in garbagePayloads) {
        final decoded =
            RecurrenceCodec.decode(RecurrenceCodec.kDaily, garbage)
                as DailyRecurrence;
        expect(decoded.interval, 1, reason: 'payload was `$garbage`');
      }
    });

    test('weekly: garbage payload defaults to empty weekdays, interval 1', () {
      for (final garbage in garbagePayloads) {
        final decoded =
            RecurrenceCodec.decode(RecurrenceCodec.kWeekly, garbage)
                as WeeklyRecurrence;
        expect(decoded.weekdays, isEmpty, reason: 'payload was `$garbage`');
        expect(decoded.interval, 1, reason: 'payload was `$garbage`');
      }
    });

    test('monthly and yearly: garbage payload defaults interval to 1', () {
      for (final garbage in garbagePayloads) {
        final monthly =
            RecurrenceCodec.decode(RecurrenceCodec.kMonthly, garbage)
                as MonthlyRecurrence;
        final yearly =
            RecurrenceCodec.decode(RecurrenceCodec.kYearly, garbage)
                as YearlyRecurrence;
        expect(monthly.interval, 1, reason: 'payload was `$garbage`');
        expect(yearly.interval, 1, reason: 'payload was `$garbage`');
      }
    });

    test('specificDates: garbage payload yields an empty date set, '
        'which is the documented fallback to one-time', () {
      for (final garbage in garbagePayloads) {
        final decoded = RecurrenceCodec.decode(
          RecurrenceCodec.kSpecificDates,
          garbage,
        );
        expect(decoded, const OneTimeRecurrence(), reason: 'payload was `$garbage`');
      }
    });
  });

  group('null and empty payloads', () {
    for (final entry in expectedKindOnMalformed.entries) {
      final kind = entry.key;
      final expectedType = entry.value;
      test('$kind with a null payload stays $expectedType', () {
        final decoded = RecurrenceCodec.decode(kind, null);
        expect(decoded.runtimeType, expectedType);
      });
      test('$kind with an empty-string payload stays $expectedType', () {
        final decoded = RecurrenceCodec.decode(kind, '');
        expect(decoded.runtimeType, expectedType);
      });
    }

    test('daily/weekly/monthly/yearly default interval to 1 on null payload', () {
      expect(
        (RecurrenceCodec.decode(RecurrenceCodec.kDaily, null) as DailyRecurrence)
            .interval,
        1,
      );
      final weekly =
          RecurrenceCodec.decode(RecurrenceCodec.kWeekly, null)
              as WeeklyRecurrence;
      expect(weekly.interval, 1);
      expect(weekly.weekdays, isEmpty);
      expect(
        (RecurrenceCodec.decode(RecurrenceCodec.kMonthly, null)
                as MonthlyRecurrence)
            .interval,
        1,
      );
      expect(
        (RecurrenceCodec.decode(RecurrenceCodec.kYearly, null)
                as YearlyRecurrence)
            .interval,
        1,
      );
    });
  });

  group('legacy payloads with no interval key', () {
    test('daily payload without interval defaults to 1', () {
      final decoded =
          RecurrenceCodec.decode(RecurrenceCodec.kDaily, '{}')
              as DailyRecurrence;
      expect(decoded.interval, 1);
    });

    test('weekly payload with weekdays but no interval defaults to 1', () {
      final decoded =
          RecurrenceCodec.decode(
                RecurrenceCodec.kWeekly,
                '{"weekdays":[1,3,5]}',
              )
              as WeeklyRecurrence;
      expect(decoded.weekdays, {1, 3, 5});
      expect(decoded.interval, 1);
    });

    test('monthly payload without interval defaults to 1', () {
      final decoded =
          RecurrenceCodec.decode(RecurrenceCodec.kMonthly, '{}')
              as MonthlyRecurrence;
      expect(decoded.interval, 1);
    });

    test('yearly payload without interval defaults to 1', () {
      final decoded =
          RecurrenceCodec.decode(RecurrenceCodec.kYearly, '{}')
              as YearlyRecurrence;
      expect(decoded.interval, 1);
    });
  });
}
