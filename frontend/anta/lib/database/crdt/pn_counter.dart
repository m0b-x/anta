import 'dart:convert';
import 'dart:math' as math;

/// One replica's taps on a counter value since the epoch: [p] the steps up,
/// [n] the steps down. Both only grow, which is what lets a join take the
/// larger of each without counting a tap twice.
typedef PnShard = ({int p, int n});

/// A counter value's mergeable state (scalability record D8 A): the last
/// absolute write — its stamp [epochHlc] and number [epochValue] — and each
/// replica's taps since, so taps made offline on two devices add up where a
/// last-writer-wins number kept one side's.
///
/// `counter_values.value` stays the materialised [value]: every reader, the
/// backup and an older build read that column alone. Only an absolute write
/// (a reset, a typed value, a restore) starts an epoch, and the greater epoch
/// supersedes every tap of a lesser one — a reset on one device beats the taps
/// another made before it heard of the reset, by design.
final class PnCounterState {
  /// The epoch of a value first written by a tap: shared by every device, so
  /// two devices tapping a value neither had stored join their taps instead of
  /// one epoch superseding the other. Sorts below every real stamp.
  static const String genesis = '';

  /// The stamp of the absolute write the taps count from — what decides
  /// between two states, never the row's own stamp, which a pin or a join
  /// moves too.
  final String epochHlc;

  /// The number that absolute write set.
  final int epochValue;

  /// Each replica's taps since the epoch, keyed by its `replica_id`.
  final Map<String, PnShard> shards;

  /// A state as stored; a write builds one through [tap] or a new epoch.
  const PnCounterState({
    required this.epochHlc,
    required this.epochValue,
    this.shards = const {},
  });

  /// What `counter_values.value` must hold: the epoch's number plus every
  /// replica's steps up less its steps down.
  int get value {
    var total = epochValue;
    for (final shard in shards.values) {
      total += shard.p - shard.n;
    }
    return total;
  }

  /// [delta] tapped on [replica]: a step up grows its `p`, a step down its
  /// `n`, so neither ever shrinks.
  PnCounterState tap(String replica, int delta) {
    if (delta == 0) return this;
    final shard = shards[replica] ?? (p: 0, n: 0);
    return PnCounterState(
      epochHlc: epochHlc,
      epochValue: epochValue,
      shards: {
        ...shards,
        replica: delta > 0
            ? (p: shard.p + delta, n: shard.n)
            : (p: shard.p, n: shard.n - delta),
      },
    );
  }

  /// The state both sides converge on, whichever joins which: the greater
  /// epoch whole, or within one epoch each replica's larger `p` and larger
  /// `n`. Two epochs of one stamp with different numbers cannot come from one
  /// write; the larger number is kept so the join stays commutative.
  PnCounterState join(PnCounterState other) {
    final order = epochHlc.compareTo(other.epochHlc);
    if (order != 0) return order > 0 ? this : other;
    if (epochValue != other.epochValue) {
      return epochValue > other.epochValue ? this : other;
    }
    final joined = {...shards};
    for (final MapEntry(key: replica, value: theirs) in other.shards.entries) {
      final mine = joined[replica];
      joined[replica] = mine == null
          ? theirs
          : (p: math.max(mine.p, theirs.p), n: math.max(mine.n, theirs.n));
    }
    return PnCounterState(
      epochHlc: epochHlc,
      epochValue: epochValue,
      shards: joined,
    );
  }

  /// The `shards` column: `''` for none, else JSON with the replicas sorted,
  /// so one state is always stored as one text.
  String get shardsColumn {
    if (shards.isEmpty) return '';
    return jsonEncode(shardsWire);
  }

  /// The shards as the wire carries them: `{replicaId: [p, n]}`.
  Map<String, List<int>> get shardsWire {
    final replicas = shards.keys.toList()..sort();
    return {
      for (final replica in replicas)
        replica: [shards[replica]!.p, shards[replica]!.n],
    };
  }

  /// [shardsColumn] read back.
  static Map<String, PnShard> shardsOfColumn(String column) {
    if (column.isEmpty) return const {};
    return shardsOfWire(jsonDecode(column));
  }

  /// [shardsWire] read back. Anything but replica ids mapped to two
  /// non-negative integers is a [FormatException]: a negative `p` or `n`
  /// would let a join lower a count.
  static Map<String, PnShard> shardsOfWire(Object? wire) {
    if (wire is! Map) throw FormatException('shards are not a map', wire);
    final shards = <String, PnShard>{};
    for (final MapEntry(key: replica, value: pair) in wire.entries) {
      if (replica is! String ||
          replica.isEmpty ||
          pair is! List ||
          pair.length != 2) {
        throw FormatException('not a replica shard', '$replica: $pair');
      }
      final [p, n] = pair;
      if (p is! int || n is! int || p < 0 || n < 0) {
        throw FormatException('not a replica shard', '$replica: $pair');
      }
      shards[replica] = (p: p, n: n);
    }
    return shards;
  }

  @override
  bool operator ==(Object other) {
    if (other is! PnCounterState ||
        other.epochHlc != epochHlc ||
        other.epochValue != epochValue ||
        other.shards.length != shards.length) {
      return false;
    }
    for (final MapEntry(key: replica, value: shard) in shards.entries) {
      if (other.shards[replica] != shard) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(epochHlc, epochValue, shardsColumn);
}
