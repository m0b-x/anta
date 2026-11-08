import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/body_cut.dart';
import 'package:anta/database/chunking/chunk_planner.dart';

import '../../support/scale_fixtures.dart';

/// The planner turns a new cut into the fewest row operations over the
/// stored rows (`docs/scalability-roadmap.md` §5.2 S4): a common prefix
/// stays, a common suffix moves by one arithmetic shift, a chunk whose hash
/// the new cut still holds is moved and never rewritten.
void main() {
  /// Stored rows `0..n-1` holding [hashes], with ids `r<index>`.
  List<StoredChunk> stored(List<String?> hashes) => [
    for (final (i, hash) in hashes.indexed)
      StoredChunk(id: 'r$i', index: i, hash: hash),
  ];

  /// Statements as the DAO runs them: one DELETE for every dropped row, one
  /// UPDATE for the shift, one per move, one INSERT per new chunk.
  int operations(ChunkPlan plan) =>
      (plan.deleteIds.isEmpty ? 0 : 1) +
      (plan.shift == 0 ? 0 : 1) +
      plan.moves.length +
      plan.inserts.length;

  test('identical hashes plan nothing', () {
    final plan = ChunkPlanner.plan(['a', 'b', 'c'], stored(['a', 'b', 'c']));
    expect(plan.isEmpty, isTrue);
    expect(plan.recut, isFalse);
  });

  test('a changed chunk is one DELETE and one INSERT, nothing shifted', () {
    final plan = ChunkPlanner.plan(['a', 'X', 'c'], stored(['a', 'b', 'c']));
    expect(plan.deleteIds, ['r1']);
    expect(plan.inserts, [1]);
    expect(plan.shift, 0);
    expect(plan.moves, isEmpty);
  });

  test('a chunk split at the top shifts the suffix by one statement', () {
    final plan = ChunkPlanner.plan([
      'a1',
      'a2',
      'b',
      'c',
      'd',
      'e',
    ], stored(['a', 'b', 'c', 'd', 'e']));
    expect(plan.deleteIds, ['r0']);
    expect(plan.inserts, [0, 1]);
    expect(plan.shiftFrom, 1);
    expect(plan.shift, 1);
    expect(plan.moves, isEmpty);
    expect(operations(plan), 4);
  });

  test('two chunks merged shift the suffix down', () {
    final plan = ChunkPlanner.plan([
      'ab',
      'c',
      'd',
    ], stored(['a', 'b', 'c', 'd']));
    expect(plan.deleteIds, unorderedEquals(['r0', 'r1']));
    expect(plan.inserts, [0]);
    expect(plan.shiftFrom, 2);
    expect(plan.shift, -1);
  });

  test('a moved paragraph reuses its chunk by index alone', () {
    final plan = ChunkPlanner.plan([
      'a',
      'd',
      'b',
      'c',
      'e',
    ], stored(['a', 'b', 'c', 'd', 'e']));
    expect(plan.deleteIds, isEmpty);
    expect(plan.inserts, isEmpty);
    expect(plan.shift, 0);
    expect(plan.moves, unorderedEquals([('r3', 1), ('r1', 2), ('r2', 3)]));
  });

  test('a repeated chunk is claimed once per occurrence', () {
    final plan = ChunkPlanner.plan([
      'q',
      'x',
      'x',
      'x',
      'r',
    ], stored(['a', 'x', 'x', 'b']));
    expect(plan.moves, isEmpty);
    expect(plan.inserts, [0, 3, 4]);
    expect(plan.deleteIds, unorderedEquals(['r0', 'r3']));
    expect(plan.shift, 0);
  });

  test('appending inserts at the end and touches nothing else', () {
    final plan = ChunkPlanner.plan(['a', 'b', 'c'], stored(['a', 'b']));
    expect(plan.inserts, [2]);
    expect(plan.deleteIds, isEmpty);
    expect(plan.shift, 0);
    expect(plan.moves, isEmpty);
  });

  test('an emptied body deletes every row', () {
    final plan = ChunkPlanner.plan([], stored(['a', 'b']));
    expect(plan.deleteIds, unorderedEquals(['r0', 'r1']));
    expect(plan.inserts, isEmpty);
    expect(plan.shift, 0);
  });

  test('legacy fixed slices are replaced whole, once', () {
    final legacy = ChunkPlanner.plan(['a', 'b'], stored([null, null, null]));
    expect(legacy.recut, isTrue);
    expect(legacy.deleteIds, ['r0', 'r1', 'r2']);
    expect(legacy.inserts, [0, 1]);

    final mixed = ChunkPlanner.plan(['a', 'b'], stored(['a', null]));
    expect(mixed.recut, isTrue);
    expect(mixed.inserts, [0, 1]);

    final again = ChunkPlanner.plan(['a', 'b'], stored(['a', 'b']));
    expect(again.isEmpty, isTrue);
  });

  test('a gap in the stored indexes is replaced whole', () {
    final plan = ChunkPlanner.plan(
      ['a', 'b'],
      const [
        StoredChunk(id: 'r0', index: 0, hash: 'a'),
        StoredChunk(id: 'r2', index: 2, hash: 'b'),
      ],
    );
    expect(plan.recut, isTrue);
    expect(plan.deleteIds, ['r0', 'r2']);
  });

  test('a new note inserts every chunk and is no re-cut', () {
    final plan = ChunkPlanner.plan(['a', 'b'], const []);
    expect(plan.inserts, [0, 1]);
    expect(plan.recut, isFalse);
  });

  group('a one-character insert into a 3 MB body', () {
    final body = bigBody(3000000);
    final before = BodyCut.inline(body);
    final rows = stored(before.hashes);

    for (final (where, at) in [
      ('near the top', 100),
      ('in the middle', 1500000),
      ('at the end', 3000000),
    ]) {
      test('$where plans at most four operations', () {
        final edited = '${body.substring(0, at)}x${body.substring(at)}';
        final plan = ChunkPlanner.plan(BodyCut.inline(edited).hashes, rows);
        expect(operations(plan), inInclusiveRange(1, 4));
        expect(plan.inserts.length, lessThanOrEqualTo(2));
      });
    }
  });
}
