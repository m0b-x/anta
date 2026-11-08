/// A stored chunk row, as much of it as planning reads: never its content.
final class StoredChunk {
  const StoredChunk({required this.id, required this.index, this.hash});

  /// The row's primary key: what a delete or a move names.
  final String id;

  /// Its `chunk_index`: the row's place in the body.
  final int index;

  /// NULL on a legacy fixed slice.
  final String? hash;
}

/// The row operations that turn a note's stored chunks into a new cut.
///
/// Applied in this order: [deleteIds]; the kept suffix moved by [shift];
/// [moves]; [inserts]. Indexes may collide between the steps, never after
/// the last one.
final class ChunkPlan {
  const ChunkPlan({
    this.deleteIds = const [],
    this.shiftFrom = 0,
    this.shift = 0,
    this.moves = const [],
    this.inserts = const [],
    this.recut = false,
  });

  /// Rows whose text the new cut no longer holds.
  final List<String> deleteIds;

  /// Every stored row at or above this `chunk_index` is the kept suffix and
  /// moves by [shift], in one statement.
  final int shiftFrom;

  /// How far the kept suffix moves: the new cut's chunk count less the
  /// stored one, or 0 when nothing is kept at the end.
  final int shift;

  /// Rows the new cut holds elsewhere — a moved paragraph — given their new
  /// `chunk_index` only, never their content.
  final List<(String id, int index)> moves;

  /// The positions in the new cut whose text no stored row holds.
  final List<int> inserts;

  /// Whether the stored rows could not be diffed by hash — a legacy fixed
  /// slice among them, or a gap in their indexes — so every one is replaced.
  final bool recut;

  /// Whether the stored rows already are the new cut: nothing to write.
  bool get isEmpty =>
      deleteIds.isEmpty && shift == 0 && moves.isEmpty && inserts.isEmpty;
}

/// Plans the fewest row operations that store a new cut over the old rows.
abstract final class ChunkPlanner {
  /// [next] is the new cut's hashes in order; [stored] the note's live rows
  /// ordered by `chunk_index`.
  ///
  /// The common hash prefix stays where it is, the common suffix moves by
  /// one arithmetic shift, and in between a row whose hash the new cut still
  /// holds is moved rather than rewritten. Rows that are not a hashed run
  /// `0..n-1` are all replaced ([ChunkPlan.recut]).
  static ChunkPlan plan(List<String> next, List<StoredChunk> stored) {
    if (!isHashedRun(stored)) {
      return ChunkPlan(
        deleteIds: [for (final row in stored) row.id],
        inserts: [for (var i = 0; i < next.length; i++) i],
        recut: stored.isNotEmpty,
      );
    }
    final oldCount = stored.length;
    final newCount = next.length;
    var prefix = 0;
    while (prefix < oldCount &&
        prefix < newCount &&
        stored[prefix].hash == next[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldCount - prefix &&
        suffix < newCount - prefix &&
        stored[oldCount - 1 - suffix].hash == next[newCount - 1 - suffix]) {
      suffix++;
    }

    final unclaimed = <String, List<StoredChunk>>{};
    for (var i = prefix; i < oldCount - suffix; i++) {
      (unclaimed[stored[i].hash!] ??= []).add(stored[i]);
    }
    final moves = <(String, int)>[];
    final inserts = <int>[];
    for (var i = prefix; i < newCount - suffix; i++) {
      final rows = unclaimed[next[i]];
      if (rows == null || rows.isEmpty) {
        inserts.add(i);
        continue;
      }
      final row = rows.removeAt(0);
      if (row.index != i) moves.add((row.id, i));
    }

    return ChunkPlan(
      deleteIds: [
        for (final rows in unclaimed.values)
          for (final row in rows) row.id,
      ],
      shiftFrom: oldCount - suffix,
      shift: suffix == 0 ? 0 : newCount - oldCount,
      moves: moves,
      inserts: inserts,
    );
  }

  /// Whether [stored] can be diffed by hash: every row hashed, indexes
  /// exactly `0..n-1`. Anything else is re-cut whole.
  static bool isHashedRun(List<StoredChunk> stored) {
    for (var i = 0; i < stored.length; i++) {
      if (stored[i].hash == null || stored[i].index != i) return false;
    }
    return true;
  }
}
