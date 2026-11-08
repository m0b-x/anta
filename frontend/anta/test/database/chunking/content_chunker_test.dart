import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/content_chunker.dart';

import '../../support/scale_fixtures.dart';

/// The content-defined cut (`docs/scalability-roadmap.md` §5.2 S4): bounded,
/// deterministic, surrogate-safe, and local — an edit moves only the
/// boundaries next to it, which is what keeps a save's writes proportional
/// to the edit.
void main() {
  const min = ContentChunker.minCodeUnits;
  const max = ContentChunker.maxCodeUnits;

  List<int> lengths(List<int> ends) => [
    for (final (i, end) in ends.indexed) end - (i == 0 ? 0 : ends[i - 1]),
  ];

  test('an empty text has no chunks, a short one has one', () {
    expect(ContentChunker.cut(''), isEmpty);
    expect(ContentChunker.cut('Squat 5x5'), [9]);
    expect(ContentChunker.cut('x' * min), [min]);
  });

  test('every chunk but the last is within the bounds', () {
    for (final text in [bigBody(300000), 'x' * 100000, 'ab' * 50000]) {
      final ends = ContentChunker.cut(text);
      expect(ends.last, text.length);
      final sizes = lengths(ends);
      for (final size in sizes.take(sizes.length - 1)) {
        expect(size, inInclusiveRange(min, max));
      }
      expect(sizes.last, inInclusiveRange(1, max));
    }
  });

  test('a markdown body cuts near the target size on average', () {
    final ends = ContentChunker.cut(bigBody(3000000));
    final average = 3000000 / ends.length;
    expect(average, inInclusiveRange(6000, 12000));
  });

  test('the same text always cuts the same way', () {
    final text = bigBody(300000);
    expect(ContentChunker.cut(text), ContentChunker.cut(text));
    expect(
      ContentChunker.cut(text),
      ContentChunker.cut(String.fromCharCodes(text.codeUnits)),
    );
  });

  test('no cut falls between the halves of a surrogate pair', () {
    // Pairs everywhere, so both the hash's cut points and the maximum land
    // on them.
    final dense = '$lifter a ' * 40000;
    final noBreaks = lifter * 30000;
    for (final text in [dense, noBreaks, bigBody(300000)]) {
      for (final end in ContentChunker.cut(text)) {
        if (end == text.length) continue;
        final unit = text.codeUnitAt(end - 1);
        expect(
          unit >= 0xD800 && unit <= 0xDBFF,
          isFalse,
          reason: 'a cut at $end splits a pair',
        );
      }
    }
  });

  test('a text with no cut point ends each chunk on its smallest hash past '
      'the target', () {
    // One letter repeated hashes the same everywhere, so the first position
    // past the target is the smallest.
    final sizes = lengths(ContentChunker.cut('x' * (3 * max)));
    expect(sizes.take(sizes.length - 1).toSet(), {
      ContentChunker.targetCodeUnits,
    });
  });

  test('a low-entropy table still cuts on content: an insertion near its '
      'top typically changes one chunk', () {
    final table = '| --- | --- |\n' * (100000 ~/ 14);
    List<String> pieces(String text) {
      final ends = ContentChunker.cut(text);
      return [
        for (final (i, end) in ends.indexed)
          text.substring(i == 0 ? 0 : ends[i - 1], end),
      ];
    }

    final before = pieces(table).toSet();
    final after = pieces('${table.substring(0, 10)}x${table.substring(10)}');
    expect(after.where((p) => !before.contains(p)), hasLength(1));
  });

  group('an insertion typically moves at most two boundaries', () {
    final body = bigBody(300000);

    for (final (where, at) in [
      ('near the top', 100),
      ('in the second chunk', 10100),
      ('in the middle', 150000),
      ('near the end', 299900),
    ]) {
      test(where, () {
        final edited = '${body.substring(0, at)}x${body.substring(at)}';
        final before = {
          for (final end in ContentChunker.cut(body)) end <= at ? end : end + 1,
        };
        final after = ContentChunker.cut(edited).toSet();

        expect(after.difference(before).length, lessThanOrEqualTo(2));
        expect(before.difference(after).length, lessThanOrEqualTo(2));
      });
    }
  });
}
