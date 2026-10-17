import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

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
    sortOrder: view.sortOrder,
  );

  OverviewView read(Object? json) =>
      OverviewView.fromJson(json, id: 'v', name: 'View', today: today);

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
      );

      expect(nextYear.period, const OverviewYearPeriod(2027));
      expect(
        nextYear.matches(
          OverviewPeriod.thisYear(today: DateTime(2027, 2, 1)),
          OverviewListOptions.defaults,
          const {},
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
      );

      expect(later.period, const OverviewYearPeriod(2024));
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

    test('the same list matches', () {
      expect(
        view.matches(
          const OverviewYearPeriod(2026),
          const OverviewListOptions(rows: OverviewRows.perEvent),
          {'gym'},
        ),
        isTrue,
      );
    });

    test('another period, option or allowlist does not', () {
      expect(
        view.matches(
          const OverviewYearPeriod(2025),
          view.options,
          view.categoryIds,
        ),
        isFalse,
      );
      expect(
        view.matches(
          view.period,
          const OverviewListOptions(),
          view.categoryIds,
        ),
        isFalse,
      );
      expect(view.matches(view.period, view.options, const {}), isFalse);
    });
  });
}
