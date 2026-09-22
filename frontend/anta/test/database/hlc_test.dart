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
}
