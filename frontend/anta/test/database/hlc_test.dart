import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/hlc.dart';

/// A node's stamps must be strictly increasing however fast they are asked
/// for. `DateTime.now()` resolves to microseconds while a stamp carries
/// milliseconds, and comparing the two at full precision let two stamps
/// inside one millisecond reset the counter and come out equal — the
/// same-millisecond collision that made every "moves the HLC" DAO test flake
/// under full-suite load (2026-09-22).
void main() {
  test('stamps taken inside one millisecond still move', () {
    final clock = HybridLogicalClock(nodeId: 'n1');
    var previous = clock.now();
    for (var i = 0; i < 2000; i++) {
      final next = clock.now();
      expect(
        next.compareTo(previous),
        greaterThan(0),
        reason: 'stamp $i did not move: $previous -> $next',
      );
      expect(next.toString(), isNot(previous.toString()));
      previous = next;
    }
  });

  test('a stamp received from another node moves this one past it', () {
    final clock = HybridLogicalClock(nodeId: 'n1');
    final mine = clock.now();
    final remote = HlcTimestamp(
      wallTime: mine.wallTime,
      logicalCounter: mine.logicalCounter + 5,
      nodeId: 'n2',
    );

    final merged = clock.receive(remote);

    expect(merged.compareTo(remote), greaterThan(0));
    expect(merged.compareTo(mine), greaterThan(0));
  });

  final wall = DateTime.utc(2026, 10, 23, 12);
  HlcTimestamp at(DateTime instant, {int counter = 0, String node = 'n2'}) =>
      HlcTimestamp(
        wallTime: instant.millisecondsSinceEpoch,
        logicalCounter: counter,
        nodeId: node,
      );

  group('seeding from a stored stamp', () {
    test('a wall clock behind the stored stamp still stamps above it', () {
      final stored = at(wall.add(const Duration(minutes: 5)), counter: 7);
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall)
        ..seed(stored);

      var previous = clock.now();
      expect(previous.compareTo(stored), greaterThan(0));
      expect(previous.toString().compareTo(stored.toString()), greaterThan(0));
      for (var i = 0; i < 100; i++) {
        final next = clock.now();
        expect(next.compareTo(previous), greaterThan(0));
        previous = next;
      }
    });

    test('a seed never lowers the clock', () {
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall);
      final before = clock.now();

      clock.seed(at(wall.subtract(const Duration(days: 1))));

      expect(clock.last, before);
      expect(clock.seedAhead, Duration.zero);
    });

    test('seedAhead reports a far-ahead seed and the seed is not capped', () {
      final stored = at(wall.add(const Duration(days: 400)));
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall)
        ..seed(stored);

      expect(clock.seedAhead, const Duration(days: 400));
      expect(clock.last.wallTime, stored.wallTime);
      expect(clock.now().compareTo(stored), greaterThan(0));
    });

    test('a seed behind the wall reports nothing ahead', () {
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall)
        ..seed(at(wall.subtract(const Duration(seconds: 3))));

      expect(clock.seedAhead, Duration.zero);
    });
  });

  group('the drift guard', () {
    final limit = wall.add(HybridLogicalClock.maxDrift);

    test('receive holds a far-future remote to the guard and counts it', () {
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall);

      final merged = clock.receive(at(wall.add(const Duration(days: 30))));

      expect(merged.wallTime, limit.millisecondsSinceEpoch);
      expect(clock.clampedRemotes, 1);
    });

    test('update holds a far-future remote to the guard and counts it', () {
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall);

      clock.update(at(wall.add(const Duration(days: 30)), counter: 9));

      expect(clock.last.wallTime, limit.millisecondsSinceEpoch);
      expect(clock.clampedRemotes, 1);
    });

    test('a remote inside the guard is honoured exactly', () {
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall);
      final remote = at(wall.add(const Duration(minutes: 59)), counter: 4);

      final merged = clock.receive(remote);
      clock.update(at(remote.dateTime, counter: 20));

      expect(merged.wallTime, remote.wallTime);
      expect(merged.logicalCounter, 5);
      expect(clock.last.wallTime, remote.wallTime);
      expect(clock.last.logicalCounter, 20);
      expect(clock.clampedRemotes, 0);
    });

    test('a seed already beyond the guard is not lowered by a clamp', () {
      final stored = at(wall.add(const Duration(days: 2)), counter: 3);
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall)
        ..seed(stored);

      final merged = clock.receive(at(wall.add(const Duration(days: 30))));
      clock.update(at(wall.add(const Duration(days: 30)), counter: 50));

      expect(merged.compareTo(stored), greaterThan(0));
      expect(clock.last.wallTime, stored.wallTime);
      expect(clock.clampedRemotes, 2);
    });

    test('a remote at or below a clock beyond the guard passes as it is', () {
      final stored = at(wall.add(const Duration(days: 2)), counter: 3);
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall)
        ..seed(stored);
      final remote = at(wall.add(const Duration(days: 1)), counter: 9);

      final merged = clock.receive(remote);

      expect(merged.compareTo(remote), greaterThan(0));
      expect(merged.compareTo(stored), greaterThan(0));
      expect(clock.clampedRemotes, 0);
    });

    test('adopt follows a far-future stamp and counts it', () {
      final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall);
      final stamp = at(wall.add(const Duration(days: 30)), counter: 9);

      clock.adopt(stamp);

      expect(clock.last.wallTime, stamp.wallTime);
      expect(clock.last.logicalCounter, 9);
      expect(clock.now().compareTo(stamp), greaterThan(0));
      expect(clock.clampedRemotes, 1);
    });
  });

  test('a seeded counter past four hex digits moves to the next ms', () {
    final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall)
      ..seed(at(wall, counter: 0x10000));

    expect(clock.last.wallTime, wall.millisecondsSinceEpoch + 1);
    expect(clock.last.logicalCounter, 0);
    expect(
      clock.last.toString().compareTo(at(wall, counter: 0xFFFF).toString()),
      greaterThan(0),
    );
  });

  test('a counter past four hex digits moves to the next millisecond', () {
    final clock = HybridLogicalClock(nodeId: 'n1', wallClock: () => wall);
    var previous = clock.now();
    for (var i = 1; i < 0x10000 + 2; i++) {
      final next = clock.now();
      if (next.compareTo(previous) <= 0 ||
          next.toString().compareTo(previous.toString()) <= 0) {
        fail('stamp $i did not move: $previous -> $next');
      }
      previous = next;
    }

    expect(previous.wallTime, wall.millisecondsSinceEpoch + 1);
    expect(previous.logicalCounter, 2);
  });
}
