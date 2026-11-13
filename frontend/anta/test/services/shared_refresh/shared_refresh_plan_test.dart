import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/shared_refresh/shared_refresh_plan.dart';

/// `SharedRefreshPlan.next` — when the phone next reads what the partner
/// shares by itself (`docs/cloud-shared-freshness.md` §4, decision c).
void main() {
  final now = DateTime(2026, 11, 13, 9);

  DateTime after(Duration d) => now.add(d);

  group('the table', () {
    final cases =
        <
          ({
            String name,
            List<Duration> fires,
            bool categoryAlerts,
            Duration? gap,
          })
        >[
          (
            name:
                'B1: nothing of the partner\'s can ring here — no check at '
                'all',
            fires: const [],
            categoryAlerts: false,
            gap: null,
          ),
          (
            name: 'half the time left to the one armed alert',
            fires: const [Duration(hours: 6)],
            categoryAlerts: false,
            gap: const Duration(hours: 3),
          ),
          (
            name: 'the nearest alert decides, whatever order they come in',
            fires: const [
              Duration(days: 2),
              Duration(hours: 4),
              Duration(hours: 20),
            ],
            categoryAlerts: false,
            gap: const Duration(hours: 2),
          ),
          (
            name: 'never later than twelve hours, however far the alert',
            fires: const [Duration(days: 20)],
            categoryAlerts: false,
            gap: const Duration(hours: 12),
          ),
          (
            name: 'exactly a day ahead is the ceiling itself',
            fires: const [Duration(hours: 24)],
            categoryAlerts: false,
            gap: const Duration(hours: 12),
          ),
          (
            name: 'never sooner than ten minutes: fifteen left waits ten',
            fires: const [Duration(minutes: 15)],
            categoryAlerts: false,
            gap: const Duration(minutes: 10),
          ),
          (
            name: 'twenty minutes left is the floor itself',
            fires: const [Duration(minutes: 20)],
            categoryAlerts: false,
            gap: const Duration(minutes: 10),
          ),
          (
            name:
                'at most ten minutes away takes no further check: one '
                'planned from exactly ten would land on the ring',
            fires: const [Duration(minutes: 10)],
            categoryAlerts: false,
            gap: null,
          ),
          (
            name: 'a second past ten minutes still takes its one check',
            fires: const [Duration(minutes: 10, seconds: 1)],
            categoryAlerts: false,
            gap: const Duration(minutes: 10),
          ),
          (
            name: 'an alert under ten minutes away takes no further check',
            fires: const [Duration(minutes: 9, seconds: 59)],
            categoryAlerts: false,
            gap: null,
          ),
          (
            name: '…and the next nearest decides',
            fires: const [Duration(minutes: 4), Duration(hours: 8)],
            categoryAlerts: false,
            gap: const Duration(hours: 4),
          ),
          (
            name: 'a fire time already behind counts for nothing',
            fires: const [Duration(minutes: -30)],
            categoryAlerts: false,
            gap: null,
          ),
          (
            name: 'a past one beside a coming one leaves the coming one',
            fires: const [Duration(hours: -2), Duration(hours: 1)],
            categoryAlerts: false,
            gap: const Duration(minutes: 30),
          ),
          (
            name:
                '"Category alerts too" with nothing armed yet looks every '
                'hour',
            fires: const [],
            categoryAlerts: true,
            gap: const Duration(hours: 1),
          ),
          (
            name: '…and holds a far alert to the hour',
            fires: const [Duration(days: 3)],
            categoryAlerts: true,
            gap: const Duration(hours: 1),
          ),
          (
            name: '…while a near alert still brings the check sooner',
            fires: const [Duration(minutes: 50)],
            categoryAlerts: true,
            gap: const Duration(minutes: 25),
          ),
          (
            name: '…and an alert about to ring leaves the hourly check',
            fires: const [Duration(minutes: 3)],
            categoryAlerts: true,
            gap: const Duration(hours: 1),
          ),
        ];

    for (final c in cases) {
      test(c.name, () {
        expect(
          SharedRefreshPlan.next(now, [
            for (final fire in c.fires) after(fire),
          ], categoryAlerts: c.categoryAlerts),
          c.gap,
        );
      });
    }
  });

  group('an alert of mine on a partner\'s event that can still occur, armed '
      'or not', () {
    Duration? next(List<Duration> fires, {bool categoryAlerts = false}) =>
        SharedRefreshPlan.next(
          now,
          [for (final fire in fires) after(fire)],
          categoryAlerts: categoryAlerts,
          alertAhead: true,
        );

    test('past the alerts\' horizon, with nothing armed: the twelve-hour '
        'check goes on, so an event the partner moves nearer is read', () {
      expect(next(const []), const Duration(hours: 12));
    });

    test('its one fire about to ring: the next check is the ceiling\'s, '
        'never none', () {
      expect(next(const [Duration(minutes: 4)]), const Duration(hours: 12));
    });

    test('an armed fire still decides while it is far enough', () {
      expect(next(const [Duration(hours: 2)]), const Duration(hours: 1));
    });

    test('under "Category alerts too" the ceiling is the hour', () {
      expect(next(const [], categoryAlerts: true), const Duration(hours: 1));
    });
  });

  group('followed from one check to the next', () {
    /// How long before [fireAt] each check runs, every run planning its
    /// successor at the instant it was planned for.
    List<Duration> checksBefore(
      DateTime fireAt, {
      bool categoryAlerts = false,
    }) {
      final before = <Duration>[];
      var at = now;
      while (true) {
        final gap = SharedRefreshPlan.next(at, [
          fireAt,
        ], categoryAlerts: categoryAlerts);
        if (gap == null) return before;
        expect(gap, greaterThanOrEqualTo(kSharedRefreshMinGap));
        expect(gap, lessThanOrEqualTo(kSharedRefreshMaxGap));
        at = at.add(gap);
        before.add(fireAt.difference(at));
        expect(before.length, lessThan(100), reason: 'the chain must end');
      }
    }

    test('B2: an alert three days ahead is checked every twelve hours while '
        'it is far, then at half the time left each time, the last within '
        'twenty minutes of it', () {
      final checks = checksBefore(after(const Duration(days: 3)));

      expect(checks, const [
        Duration(hours: 60),
        Duration(hours: 48),
        Duration(hours: 36),
        Duration(hours: 24),
        Duration(hours: 12),
        Duration(hours: 6),
        Duration(hours: 3),
        Duration(minutes: 90),
        Duration(minutes: 45),
        Duration(minutes: 22, seconds: 30),
        Duration(minutes: 11, seconds: 15),
        Duration(minutes: 1, seconds: 15),
      ]);
      expect(checks.last, lessThan(const Duration(minutes: 20)));
      expect(checks.last, greaterThan(Duration.zero));
    });

    test('a daily alert costs eight checks from one ring to the next', () {
      final checks = checksBefore(after(const Duration(days: 1)));

      expect(checks, hasLength(8));
      expect(checks.first, const Duration(hours: 12));
    });

    test('no check is ever planned on the ring\'s instant or after it', () {
      for (final minutes in [10, 11, 19, 20, 21, 45, 600, 6000]) {
        final checks = checksBefore(after(Duration(minutes: minutes)));
        expect(
          checks.every((left) => left > Duration.zero),
          isTrue,
          reason: '$minutes min ahead: $checks',
        );
      }
    });

    test('the floor\'s own edge: a check that stands exactly ten minutes '
        'before the ring is the last', () {
      expect(checksBefore(after(const Duration(minutes: 10))), isEmpty);
      expect(checksBefore(after(const Duration(minutes: 20))), const [
        Duration(minutes: 10),
      ]);
    });
  });
}
