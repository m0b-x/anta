import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/utils/position_plan.dart';

const positionStride = AppConstants.positionStride;

/// Applies [plan] to [current] and reads the group back in display order.
List<PositionedId> applied(
  List<PositionedId> current,
  Map<String, int> plan, {
  required bool desc,
}) {
  final rows = [
    for (final row in current)
      (id: row.id, position: plan[row.id] ?? row.position),
  ];
  rows.sort((x, y) {
    final byPosition = desc
        ? y.position.compareTo(x.position)
        : x.position.compareTo(y.position);
    return byPosition != 0 ? byPosition : x.id.compareTo(y.id);
  });
  return rows;
}

/// Runs [drags] random single-row drags over [start], returning the rows each
/// one wrote; every drag must read back as planned.
List<int> dragRun(
  List<PositionedId> start,
  int drags, {
  required bool desc,
  int seed = 7,
}) {
  final random = Random(seed);
  var rows = start;
  final written = <int>[];
  for (var d = 0; d < drags; d++) {
    final order = [for (final row in rows) row.id];
    final from = random.nextInt(order.length);
    final moved = order.removeAt(from);
    order.insert(random.nextInt(order.length + 1), moved);
    final plan = planGappedPositions(
      current: rows,
      order: order,
      descending: desc,
    );
    rows = applied(rows, plan, desc: desc);
    expect([for (final row in rows) row.id], order);
    expect(
      {for (final row in rows) row.position},
      hasLength(rows.length),
      reason: 'no ties left behind',
    );
    written.add(plan.length);
  }
  return written;
}

void main() {
  group('spliceLoadedOrder', () {
    test('a loaded prefix goes first and the rest keeps its order', () {
      expect(
        spliceLoadedOrder(
          displayOrder: ['a', 'b', 'c', 'd', 'e'],
          loadedOrder: ['c', 'a', 'b'],
        ),
        ['c', 'a', 'b', 'd', 'e'],
      );
    });

    test('ids the group no longer holds are dropped, repeats count once', () {
      expect(
        spliceLoadedOrder(
          displayOrder: ['a', 'b', 'c'],
          loadedOrder: ['b', 'gone', 'b', 'a'],
        ),
        ['b', 'a', 'c'],
      );
    });

    test('a row created above the window after the page loaded stays above '
        'it', () {
      expect(
        spliceLoadedOrder(
          displayOrder: ['new', 'a', 'b', 'c', 'd'],
          loadedOrder: ['b', 'a'],
        ),
        ['new', 'b', 'a', 'c', 'd'],
      );
    });
  });

  group('planGappedPositions', () {
    List<PositionedId> rows(
      List<String> ids,
      int step, {
      bool desc = false,
    }) => [
      for (var i = 0; i < ids.length; i++)
        (id: ids[i], position: desc ? (ids.length - 1 - i) * step : i * step),
    ];

    List<String> readBack(
      List<PositionedId> current,
      Map<String, int> plan, {
      required bool desc,
    }) {
      final positions = <String, int>{
        for (final row in current) row.id: plan[row.id] ?? row.position,
      };
      return positions.keys.toList()..sort(
        (x, y) => desc
            ? positions[y]!.compareTo(positions[x]!)
            : positions[x]!.compareTo(positions[y]!),
      );
    }

    for (final desc in [false, true]) {
      test('one drag in a gapped group writes one row (desc: $desc)', () {
        final ids = [for (var i = 0; i < 1000; i++) 'n$i'];
        final current = rows(ids, positionStride, desc: desc);
        final order = [...ids]..remove('n10');
        order.insert(500, 'n10');

        final plan = planGappedPositions(
          current: current,
          order: order,
          descending: desc,
        );

        expect(plan.keys, ['n10']);
        expect(readBack(current, plan, desc: desc), order);
      });

      test('a dense legacy group respreads only the shorter side '
          '(desc: $desc)', () {
        final ids = [for (var i = 0; i < 100; i++) 'n$i'];
        final current = rows(ids, 1, desc: desc);
        final order = ['n9', ...ids.where((id) => id != 'n9')];

        final plan = planGappedPositions(
          current: current,
          order: order,
          descending: desc,
        );

        expect(plan.length, lessThanOrEqualTo(10));
        expect(readBack(current, plan, desc: desc), order);
      });
    }

    for (final desc in [false, true]) {
      test('a colliding legacy region heals on the first drag, so later '
          'drags write next to nothing (desc: $desc)', () {
        final tied = <PositionedId>[
          for (var i = 0; i < 300; i++)
            (id: 'n${'$i'.padLeft(3, '0')}', position: i ~/ 4),
        ];
        final written = dragRun(tied, 51, desc: desc);
        // Every row is tied with three others, so the first drag must
        // respread them all; measured 2026-11-08: 299 rows, then one row
        // per drag (average 1.0, max 1 over 50 random drags).
        expect(written.first, lessThanOrEqualTo(300));
        expect(written.skip(1).reduce(max), lessThanOrEqualTo(3));
      });
    }

    test('a corrupt position at the int64 edge respreads, never wraps', () {
      final current = <PositionedId>[
        (id: 'a', position: -(1 << 62) - 5),
        (id: 'b', position: 0),
        (id: 'c', position: (1 << 62) + 5),
      ];
      final plan = planGappedPositions(
        current: current,
        order: ['c', 'a', 'b'],
        descending: false,
      );
      expect(readBack(current, plan, desc: false), ['c', 'a', 'b']);
      expect(nextPosition((1 << 62) + 5), (1 << 62) + 5);
    });

    for (final desc in [false, true]) {
      test('the int64 minimum is caught as corrupt too (desc: $desc)', () {
        // -2^63: `abs()` and negation both wrap on it.
        const min = -0x8000000000000000;
        final current = <PositionedId>[
          (id: 'a', position: 0),
          (id: 'b', position: positionStride),
          (id: 'c', position: min),
        ];
        final order = ['b', 'c', 'a'];
        final plan = planGappedPositions(
          current: current,
          order: order,
          descending: desc,
        );
        expect(readBack(current, plan, desc: desc), order);
        expect(
          plan.values.every((p) => p.abs() <= 1 << 40),
          isTrue,
          reason: 'respread from zero',
        );
      });

      test('repeated drags into one middle gap of a stride-spaced group stay '
          'local (desc: $desc)', () {
        var rows = <PositionedId>[
          for (var i = 0; i < 1000; i++)
            (
              id: 'n${'$i'.padLeft(4, '0')}',
              position: desc ? (999 - i) * positionStride : i * positionStride,
            ),
        ];
        final written = <int>[];
        for (var d = 0; d < 300; d++) {
          final order = [for (final row in rows) row.id];
          order.insert(501, order.removeLast());
          final plan = planGappedPositions(
            current: rows,
            order: order,
            descending: desc,
          );
          rows = applied(rows, plan, desc: desc);
          expect([for (final row in rows) row.id], order);
          written.add(plan.length);
        }
        // "Place each next item just below the last one placed": measured
        // 2026-11-08 over 300 drags, max 189 rows, average 3.92, total
        // 1,176 (a fixed half-stride bar: max 499, total 3,958).
        expect(written.reduce(max), lessThanOrEqualTo(200));
        expect(written.reduce((a, b) => a + b), lessThanOrEqualTo(1300));
      });

      test('a dense group without ties heals on the first drag '
          '(desc: $desc)', () {
        final dense = <PositionedId>[
          for (var i = 0; i < 300; i++)
            if (i != 120)
              (id: 'n${'$i'.padLeft(3, '0')}', position: desc ? 299 - i : i),
        ];
        final written = dragRun(dense, 1001, desc: desc);
        final later = written.skip(1).toList();
        // A dense part heals toward its nearer end the first time a drag
        // lands in it. Measured 2026-11-08 over 1,000 random drags with one
        // row missing: first 9 rows, max 150, average 1.29, total 1,298.
        expect(written.first, lessThanOrEqualTo(150));
        expect(later.reduce((a, b) => a + b) / later.length, lessThan(2));
      });
    }

    test('a window from another sort goes on top of the group', () {
      final shown = [for (var i = 60; i < 110; i++) 'n$i']..insert(0, 'n109');
      shown.removeLast();
      expect(
        spliceLoadedOrder(
          displayOrder: [for (var i = 0; i < 120; i++) 'n$i'],
          loadedOrder: shown,
          windowAtTop: true,
        ).take(5),
        ['n109', 'n60', 'n61', 'n62', 'n63'],
      );
    });

    test('colliding positions are spread out', () {
      final current = <PositionedId>[
        for (final id in ['a', 'b', 'c']) (id: id, position: 0),
      ];
      final plan = planGappedPositions(
        current: current,
        order: ['a', 'b', 'c'],
        descending: false,
      );
      expect(readBack(current, plan, desc: false), ['a', 'b', 'c']);
      expect(plan, isNotEmpty);
    });

    test('an order already in place plans nothing', () {
      final ids = ['a', 'b', 'c'];
      expect(
        planGappedPositions(
          current: rows(ids, 7),
          order: ids,
          descending: false,
        ),
        isEmpty,
      );
    });
  });
}
