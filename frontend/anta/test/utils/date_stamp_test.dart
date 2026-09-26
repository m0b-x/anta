import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/date_stamp.dart';

void main() {
  DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

  group('DateStamp.project', () {
    test('weeks add seven days per step', () {
      final result = DateStamp.project({d(2026, 9, 25)}, DateStampUnit.week, 2);
      expect(result.added, {d(2026, 10, 2), d(2026, 10, 9)});
      expect(result.skipped, 0);
      expect(result.last, d(2026, 10, 9));
    });

    test('months keep the day and skip months without it', () {
      final result = DateStamp.project(
        {d(2026, 1, 31)},
        DateStampUnit.month,
        3,
      );
      expect(result.added, {d(2026, 3, 31)});
      expect(result.skipped, 2);
      expect(result.last, d(2026, 3, 31));
    });

    test('december rolls into the next year', () {
      final result = DateStamp.project(
        {d(2026, 11, 15)},
        DateStampUnit.month,
        2,
      );
      expect(result.added, {d(2026, 12, 15), d(2027, 1, 15)});
      expect(result.last, d(2027, 1, 15));
    });

    test('years skip Feb 29 outside leap years', () {
      final result = DateStamp.project({d(2028, 2, 29)}, DateStampUnit.year, 4);
      expect(result.added, {d(2032, 2, 29)});
      expect(result.skipped, 3);
    });

    test(
      'every picked date is projected and existing dates are not re-added',
      () {
        final result = DateStamp.project(
          {d(2026, 9, 1), d(2026, 10, 1)},
          DateStampUnit.month,
          1,
        );
        expect(result.added, {d(2026, 11, 1)});
        expect(result.skipped, 0);
      },
    );

    test('past the last date counts as skipped', () {
      final result = DateStamp.project(
        {d(2100, 12, 1)},
        DateStampUnit.month,
        1,
        lastDate: d(2100, 12, 31),
      );
      expect(result.isEmpty, isTrue);
      expect(result.skipped, 1);
      expect(result.last, isNull);
    });

    test('an empty set projects nothing', () {
      final result = DateStamp.project({}, DateStampUnit.year, 3);
      expect(result.isEmpty, isTrue);
      expect(result.skipped, 0);
    });
  });
}
