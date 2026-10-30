import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/overview_view.dart';

void main() {
  final today = DateTime(2026, 10, 13);

  OverviewView roundTrip(OverviewView view) => OverviewView.fromJson(
    jsonDecode(jsonEncode(view.toJson(today: today))),
    id: view.id,
    name: view.name,
    today: today,
    weekStart: CalendarWeekStart.monday,
    sortOrder: view.sortOrder,
  );

  OverviewView read(Object? json) => OverviewView.fromJson(
    json,
    id: 'v',
    name: 'View',
    today: today,
    weekStart: CalendarWeekStart.monday,
  );

  group('round trips', () {
    test('a year', () {
      const view = OverviewView(
        id: 'a',
        name: 'Last year',
        period: OverviewYearPeriod(2025),
        sortOrder: 3,
      );
      expect(roundTrip(view), view);
    });

    test('a rolling preset with every option set', () {
      const view = OverviewView(
        id: 'b',
        name: 'Missed lately',
        period: OverviewRollingPeriod(OverviewRollingPreset.last90Days),
        options: OverviewListOptions(
          order: OverviewOrder.newestFirst,
          rows: OverviewRows.perEvent,
          missedOnly: true,
        ),
        categoryIds: {'work', 'gym'},
      );
      expect(roundTrip(view), view);
    });

    test('a custom span', () {
      final view = OverviewView(
        id: 'c',
        name: 'Q1',
        period: OverviewCustomPeriod(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 3, 31),
        ),
      );
      final back = roundTrip(view);
      expect(back, view);
      expect(back.toJson(today: today)['period'], {
        'kind': 'custom',
        'start': '2026-01-01',
        'end': '2026-03-31',
      });
    });

    test('a view saved on this year applies as this year in a later one '
        '(review 4)', () {
      const view = OverviewView(
        id: 'e',
        name: 'This year',
        period: OverviewYearPeriod(2026),
      );
      final json = jsonDecode(jsonEncode(view.toJson(today: today)));
      expect((json as Map)['period'], {'kind': 'thisYear'});

      final nextYear = OverviewView.fromJson(
        json,
        id: 'e',
        name: 'This year',
        today: DateTime(2027, 2, 1),
        weekStart: CalendarWeekStart.monday,
      );

      expect(nextYear.period, const OverviewYearPeriod(2027));
      expect(
        nextYear.matches(
          OverviewPeriod.thisYear(today: DateTime(2027, 2, 1)),
          OverviewListOptions.defaults,
          const {},
          today: DateTime(2027, 2, 1),
          weekStart: CalendarWeekStart.monday,
        ),
        isTrue,
      );
    });

    test('a view saved on a paged year keeps its number', () {
      const view = OverviewView(
        id: 'f',
        name: '2024',
        period: OverviewYearPeriod(2024),
      );
      final json = jsonDecode(jsonEncode(view.toJson(today: today)));
      expect((json as Map)['period'], {'kind': 'year', 'year': 2024});

      final later = OverviewView.fromJson(
        json,
        id: 'f',
        name: '2024',
        today: DateTime(2027, 2, 1),
        weekStart: CalendarWeekStart.monday,
      );

      expect(later.period, const OverviewYearPeriod(2024));
    });

    // October 13, 2026 is a Tuesday: this week starts on Monday the 12th.
    test('a view saved on this week rolls into a later week, on the week '
        'start read then', () {
      final view = OverviewView(
        id: 'w',
        name: 'This week',
        period: OverviewPeriod.thisWeek(
          today: today,
          weekStart: CalendarWeekStart.monday,
        ),
      );
      final json = jsonDecode(jsonEncode(view.toJson(today: today)));
      expect((json as Map)['period'], {'kind': 'thisWeek'});
      expect(roundTrip(view), view);

      final later = OverviewView.fromJson(
        json,
        id: 'w',
        name: 'This week',
        today: DateTime(2026, 11, 4),
        weekStart: CalendarWeekStart.sunday,
      );
      expect(later.period, OverviewWeekPeriod(DateTime.utc(2026, 11, 1)));
      expect(later.rollsWithToday, isTrue);
      // A rename on that later day keeps it rolling.
      expect(
        later
            .copyWith(name: 'Week')
            .toJson(today: DateTime(2026, 11, 4))['period'],
        {'kind': 'thisWeek'},
      );
    });

    test('a view saved on this month rolls into a later month', () {
      final view = OverviewView(
        id: 'mo',
        name: 'This month',
        period: OverviewPeriod.thisMonth(today: today),
      );
      final json = jsonDecode(jsonEncode(view.toJson(today: today)));
      expect((json as Map)['period'], {'kind': 'thisMonth'});
      expect(roundTrip(view), view);

      final later = OverviewView.fromJson(
        json,
        id: 'mo',
        name: 'This month',
        today: DateTime(2027, 1, 2),
        weekStart: CalendarWeekStart.monday,
      );
      expect(later.period, const OverviewMonthPeriod(2027, 1));
    });

    test('a view saved on a paged week or month keeps its dates', () {
      final week = OverviewView(
        id: 'pw',
        name: 'Last week',
        period: OverviewWeekPeriod(DateTime.utc(2026, 10, 5)),
      );
      final weekJson = jsonDecode(jsonEncode(week.toJson(today: today)));
      expect((weekJson as Map)['period'], {
        'kind': 'week',
        'start': '2026-10-05',
      });

      const month = OverviewView(
        id: 'pm',
        name: 'September',
        period: OverviewMonthPeriod(2026, 9),
      );
      final monthJson = jsonDecode(jsonEncode(month.toJson(today: today)));
      expect((monthJson as Map)['period'], {
        'kind': 'month',
        'year': 2026,
        'month': 9,
      });

      for (final (view, json) in [(week, weekJson), (month, monthJson)]) {
        final later = OverviewView.fromJson(
          json,
          id: view.id,
          name: view.name,
          today: DateTime(2027, 2, 1),
          weekStart: CalendarWeekStart.sunday,
        );
        expect(later.period, view.period);
        expect(later.rollsWithToday, isFalse);
      }
    });
  });

  group('forward compatibility', () {
    test('an unknown period kind is this year', () {
      final view = read({
        'period': {'kind': 'fiscalQuarter', 'quarter': 2},
      });
      expect(view.period, const OverviewYearPeriod(2026));
    });

    test('an unknown preset or a malformed span is this year', () {
      expect(
        read({
          'period': {'kind': 'preset', 'preset': 'last7Days'},
        }).period,
        const OverviewYearPeriod(2026),
      );
      expect(
        read({
          'period': {'kind': 'custom', 'start': 'soon', 'end': '2026-03-31'},
        }).period,
        const OverviewYearPeriod(2026),
      );
    });

    test('a malformed week or month is this year', () {
      for (final period in [
        {'kind': 'week'},
        {'kind': 'week', 'start': 'monday'},
        {'kind': 'month', 'year': 2026},
        {'kind': 'month', 'year': 2026, 'month': 13},
        {'kind': 'month', 'year': '2026', 'month': 9},
      ]) {
        final view = read({'period': period});
        expect(view.period, const OverviewYearPeriod(2026), reason: '$period');
        expect(view.rollsWithToday, isNull, reason: '$period');
      }
    });

    test('absent options are the defaults', () {
      final view = read({
        'period': {'kind': 'year', 'year': 2024},
      });
      expect(view.period, const OverviewYearPeriod(2024));
      expect(view.options, OverviewListOptions.defaults);
      expect(view.categoryIds, isEmpty);
    });

    test('an extra key is ignored', () {
      final view = read({
        'period': {'kind': 'year', 'year': 2024, 'extra': true},
        'rows': 'perEvent',
        'someFutureKey': [1, 2],
      });
      expect(view.period, const OverviewYearPeriod(2024));
      expect(view.options.rows, OverviewRows.perEvent);
    });

    test('anything not a map is this year with the defaults', () {
      for (final junk in [null, 'text', 42, const <Object?>[]]) {
        final view = read(junk);
        expect(view.period, const OverviewYearPeriod(2026));
        expect(view.options, OverviewListOptions.defaults);
      }
    });
  });

  group('matches', () {
    const view = OverviewView(
      id: 'm',
      name: 'Gym',
      period: OverviewYearPeriod(2026),
      options: OverviewListOptions(rows: OverviewRows.perEvent),
      categoryIds: {'gym'},
    );

    bool matches(
      OverviewView view,
      OverviewPeriod period,
      OverviewListOptions options,
      Set<String> categoryIds,
    ) => view.matches(
      period,
      options,
      categoryIds,
      today: today,
      weekStart: CalendarWeekStart.monday,
    );

    test('the same list matches', () {
      expect(
        matches(
          view,
          const OverviewYearPeriod(2026),
          const OverviewListOptions(rows: OverviewRows.perEvent),
          {'gym'},
        ),
        isTrue,
      );
    });

    test('another period, option or allowlist does not', () {
      expect(
        matches(
          view,
          const OverviewYearPeriod(2025),
          view.options,
          view.categoryIds,
        ),
        isFalse,
      );
      expect(
        matches(
          view,
          view.period,
          const OverviewListOptions(),
          view.categoryIds,
        ),
        isFalse,
      );
      expect(matches(view, view.period, view.options, const {}), isFalse);
    });

    test('a rolling view matches the list of the day it is read on', () {
      final saved = read({
        'period': {'kind': 'thisWeek'},
      });
      final nextWeek = OverviewPeriod.thisWeek(
        today: DateTime(2026, 10, 21),
        weekStart: CalendarWeekStart.monday,
      );
      expect(
        saved.matches(
          nextWeek,
          OverviewListOptions.defaults,
          const {},
          today: DateTime(2026, 10, 21),
          weekStart: CalendarWeekStart.monday,
        ),
        isTrue,
      );
      expect(
        saved.matches(
          saved.period,
          OverviewListOptions.defaults,
          const {},
          today: DateTime(2026, 10, 21),
          weekStart: CalendarWeekStart.monday,
        ),
        isFalse,
        reason: 'the snapshot is last week by then',
      );
    });
  });

  group('periodOn', () {
    // October 13, 2026 is a Tuesday; eight days later is Wednesday the 21st.
    final later = DateTime(2026, 10, 21);

    test('a view saved on this week reads as the week of the day asked', () {
      final saved = read({
        'period': {'kind': 'thisWeek'},
      });
      expect(saved.period, OverviewWeekPeriod(DateTime.utc(2026, 10, 12)));
      expect(
        saved.periodOn(today: later, weekStart: CalendarWeekStart.monday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 19)),
      );
      expect(
        saved.periodOn(today: later, weekStart: CalendarWeekStart.sunday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 18)),
      );
    });

    test('this month and this year roll too', () {
      final month = read({
        'period': {'kind': 'thisMonth'},
      });
      expect(
        month.periodOn(
          today: DateTime(2027, 1, 2),
          weekStart: CalendarWeekStart.monday,
        ),
        const OverviewMonthPeriod(2027, 1),
      );
      final year = read({
        'period': {'kind': 'thisYear'},
      });
      expect(
        year.periodOn(
          today: DateTime(2027, 1, 2),
          weekStart: CalendarWeekStart.monday,
        ),
        const OverviewYearPeriod(2027),
      );
    });

    test('a pinned view or one just picked is its period as is', () {
      final pinned = read({
        'period': {'kind': 'week', 'start': '2026-10-05'},
      });
      expect(
        pinned.periodOn(today: later, weekStart: CalendarWeekStart.monday),
        OverviewWeekPeriod(DateTime.utc(2026, 10, 5)),
      );
      final picked = OverviewView(
        id: 'p',
        name: 'Picked',
        period: OverviewWeekPeriod(DateTime.utc(2026, 10, 12)),
      );
      expect(picked.rollsWithToday, isNull);
      expect(
        picked.periodOn(today: later, weekStart: CalendarWeekStart.monday),
        picked.period,
      );
      final custom = read({
        'period': {
          'kind': 'custom',
          'start': '2026-01-01',
          'end': '2026-03-31',
        },
      });
      expect(
        custom.periodOn(today: later, weekStart: CalendarWeekStart.monday),
        custom.period,
      );
    });
  });
}
