import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Guards the `CodeLines` segment contract the editor's incremental line index
/// and the per-keystroke `CodeLines.from` copy both depend on:
///
/// * a copy shares every segment's backing list by identity, so an unchanged
///   segment can be recognised without comparing its lines;
/// * a single write re-owns exactly one segment and leaves the rest shared;
/// * segments never grow past 256 lines;
/// * the cached `lineCount` / `charCount` on every segment agree with a naive
///   fold over the lines after *every* mutation path (this is what pins the
///   incremental counter maintenance in `_CodeLineSegmentQuckLineCount`).
void main() {
  group('CodeLines.from', () {
    test('shares every segment backing list by identity', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final copy = CodeLines.from(original);

      expect(copy.segments.length, original.segments.length);
      for (int i = 0; i < copy.segments.length; i++) {
        expect(
          identical(copy.segments[i].codeLines, before[i]),
          isTrue,
          reason: 'segment $i backing list should be shared',
        );
      }
      expect(copy.length, original.length);
      _expectConsistent(copy, 'CodeLines.from');
    });

    test('a copy of a warmed document reads back correctly', () {
      final original = CodeLines.of(_document(1000));
      // Warm the source's prefix-sum index and length, which the copy
      // adopts because it holds the same lines in the same segments.
      _expectLineAccess(original, 'warm source');
      expect(original.length, 1000);

      final copy = CodeLines.from(original);

      expect(copy.length, 1000);
      _expectConsistent(copy, 'from a warmed source');

      copy[600] = _chunked(500);
      expect(copy[600].text, '## week 500');
      _expectConsistent(copy, 'write after from a warmed source');
      _expectConsistent(original, 'warmed source after the copy was written');
    });

    test('a copy that drops an empty segment does not adopt the layout', () {
      final original = CodeLines(<CodeLineSegment>[
        CodeLineSegment.of(codeLines: <CodeLine>[]),
        CodeLineSegment.of(codeLines: _document(30)),
      ]);
      expect(original.length, 30);
      expect(original[0].text, _document(30).first.text);

      final copy = CodeLines.from(original);

      expect(copy.segments, hasLength(1));
      expect(copy.length, 30);
      _expectConsistent(copy, 'from a document with an empty segment');
    });

    test('copies are dirty so a write re-owns the segment', () {
      final original = CodeLines.of(_document(600));
      final copy = CodeLines.from(original);
      for (final segment in copy.segments) {
        expect(segment.dirty, isTrue);
      }
      for (final segment in original.segments) {
        expect(segment.dirty, isFalse);
      }
    });
  });

  group('single []=', () {
    test('changes exactly one segment identity and leaves the rest', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);
      final copy = CodeLines.from(original);

      const int edited = 600;
      const int editedSegment = edited ~/ 256;
      copy[edited] = const CodeLine('- [x] edited');

      for (int i = 0; i < copy.segments.length; i++) {
        expect(
          identical(copy.segments[i].codeLines, before[i]),
          i != editedSegment,
          reason: 'segment $i identity after []= at $edited',
        );
      }
      expect(copy[edited].text, '- [x] edited');
      _expectConsistent(copy, '[]=');
    });

    test('leaves the source document untouched', () {
      final source = _document(1000);
      final original = CodeLines.of(source);
      final copy = CodeLines.from(original);

      copy[600] = const CodeLine('- [x] edited');

      expect(original[600].text, source[600].text);
      expect(original.lineCount, _naiveLineCount(original));
      expect(original.charCount, _naiveCharCount(original));
    });

    test('writes through in place on a non-dirty CodeLines', () {
      final codeLines = CodeLines.of(_document(600));
      final before = _backingLists(codeLines);

      codeLines[300] = _chunked(999);

      for (int i = 0; i < codeLines.segments.length; i++) {
        expect(identical(codeLines.segments[i].codeLines, before[i]), isTrue);
      }
      _expectConsistent(codeLines, '[]= in place');
    });
  });

  group('[]= cache coherence', () {
    test('every warmed cache still agrees after a write', () {
      final codeLines = CodeLines.of(_document(770));

      // Warm all of them first: `[]=` deliberately keeps the segment
      // layout caches (prefix sums, length, last hit) because a line
      // replacement cannot move a segment boundary, so a stale one would
      // only ever show up on an already-warm document.
      expect(codeLines.length, 770);
      expect(codeLines.lineCount, _naiveLineCount(codeLines));
      expect(codeLines.charCount, _naiveCharCount(codeLines));
      _expectLineAccess(codeLines, 'warm');
      _expectAsString(codeLines, 'warm');

      // Plain -> chunked moves lineCount and charCount.
      codeLines[300] = _chunked(900);
      expect(codeLines[300].text, '## week 900');
      _expectConsistent(codeLines, '[]= at 300 after warm');

      // The last line of the last segment, then the very first line.
      codeLines[769] = _chunked(901);
      _expectConsistent(codeLines, '[]= at the tail after warm');
      codeLines[0] = _plain(902);
      _expectConsistent(codeLines, '[]= at 0 after warm');

      // Straight across a segment boundary, which is where a stale
      // last-hit window would bite.
      expect(codeLines[255].text, isNotNull);
      codeLines[256] = _chunked(903);
      expect(codeLines[255].text, isNot('## week 903'));
      expect(codeLines[256].text, '## week 903');
      _expectConsistent(codeLines, '[]= across the boundary after warm');
    });

    test('a write on a warmed dirty copy re-owns and stays coherent', () {
      final original = CodeLines.of(_document(770));
      final copy = CodeLines.from(original);
      _expectLineAccess(copy, 'warm copy');
      _expectAsString(copy, 'warm copy');
      expect(copy.length, 770);

      copy[600] = _chunked(904);

      expect(copy[600].text, '## week 904');
      _expectConsistent(copy, '[]= on a warmed copy');
      _expectConsistent(original, '[]= on a warmed copy, source');
      expect(original[600].text, isNot('## week 904'));
    });

    test('out of range throws', () {
      final codeLines = CodeLines.of(_document(300));
      expect(() => codeLines[-1] = _plain(0), throwsA(isA<RangeError>()));
      expect(() => codeLines[300] = _plain(0), throwsA(isA<RangeError>()));
      expect(
        () => CodeLines.of(const <CodeLine>[])[0] = _plain(0),
        throwsA(isA<RangeError>()),
      );
    });

    test('a write into unmodifiable backing lists still throws', () {
      // The editor's "empty document" sentinel wraps both list levels in
      // `List.unmodifiable` to keep the throw-on-write protection a
      // `const` used to give it.
      final sentinel = CodeLines(
        List<CodeLineSegment>.unmodifiable(<CodeLineSegment>[
          CodeLineSegment.of(
            codeLines: List<CodeLine>.unmodifiable(<CodeLine>[
              const CodeLine(''),
            ]),
          ),
        ]),
      );

      expect(
        () => sentinel[0] = const CodeLine('written'),
        throwsUnsupportedError,
      );
      expect(sentinel[0].text, '');
    });
  });

  group('sublines never emits an empty segment', () {
    test('every boundary combination over a 3-segment document', () {
      const int documentLength = 700;
      final source = _document(documentLength);
      final original = CodeLines.of(source);
      expect(original.segments, hasLength(3));

      const List<int> boundaries = <int>[
        0,
        1,
        255,
        256,
        257,
        511,
        512,
        documentLength,
      ];

      for (final int start in boundaries) {
        for (final int end in boundaries) {
          if (end < start) continue;
          final label = 'sublines($start, $end)';
          final sub = original.sublines(start, end);

          expect(sub.length, end - start, reason: label);
          for (int i = 0; i < sub.segments.length; i++) {
            expect(
              sub.segments[i].length,
              greaterThan(0),
              reason: 'empty segment $i from $label',
            );
          }
          expect(
            sub.equals(CodeLines.of(source.sublist(start, end))),
            isTrue,
            reason: '$label should equal the rebuilt slice',
          );
          _expectConsistent(sub, label);
        }
      }

      final before = _backingLists(original);
      for (int i = 0; i < original.segments.length; i++) {
        expect(identical(original.segments[i].codeLines, before[i]), isTrue);
      }
      _expectConsistent(original, 'sublines boundary sweep source');
    });
  });

  group('replaceLine', () {
    test('re-owns exactly one segment and shares the rest', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      const int edited = 600;
      const int editedSegment = edited ~/ 256;
      final next = original.replaceLine(edited, const CodeLine('- [x] done'));

      expect(next.segments.length, before.length);
      for (int i = 0; i < next.segments.length; i++) {
        expect(
          identical(next.segments[i].codeLines, before[i]),
          i != editedSegment,
          reason: 'segment $i identity after replaceLine at $edited',
        );
      }
      expect(next[edited].text, '- [x] done');
      expect(next.length, 1000);
      _expectConsistent(next, 'replaceLine');
    });

    test('leaves the source untouched', () {
      final source = _document(1000);
      final original = CodeLines.of(source);
      final before = _backingLists(original);

      original.replaceLine(600, const CodeLine('- [x] done'));

      expect(original.length, 1000);
      expect(original[600].text, source[600].text);
      for (int i = 0; i < original.segments.length; i++) {
        expect(identical(original.segments[i].codeLines, before[i]), isTrue);
      }
      _expectConsistent(original, 'replaceLine source');
    });

    test('a chunked replacement keeps the counts right', () {
      final original = CodeLines.of(_document(770));

      final plainToChunked = original.replaceLine(300, _chunked(900));
      expect(plainToChunked[300].chunks, hasLength(2));
      _expectConsistent(plainToChunked, 'replaceLine plain -> chunked');

      final chunkedToPlain = plainToChunked.replaceLine(301, _plain(901));
      _expectConsistent(chunkedToPlain, 'replaceLine chunked -> plain');

      // Line 7 is chunked in `_document`; replacing it must give the
      // chunks' lines back.
      expect(original[7].chunks, isNotEmpty);
      final dropChunks = original.replaceLine(7, _plain(902));
      expect(
        dropChunks.lineCount,
        original.lineCount - original[7].lineCount + 1,
      );
      _expectConsistent(dropChunks, 'replaceLine dropping chunks');
    });

    test('out of range throws', () {
      final original = CodeLines.of(_document(300));
      expect(
        () => original.replaceLine(-1, _plain(0)),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => original.replaceLine(300, _plain(0)),
        throwsA(isA<RangeError>()),
      );
    });

    test('is equal to a full CodeLines.of rebuild', () {
      final source = _document(1000);
      final original = CodeLines.of(source);

      for (final int index in <int>[0, 255, 256, 999]) {
        final replacement = _chunked(index);
        final rebuilt = CodeLines.of(<CodeLine>[
          for (int i = 0; i < source.length; i++)
            if (i == index) replacement else source[i],
        ]);
        final next = original.replaceLine(index, replacement);
        expect(
          next.equals(rebuilt),
          isTrue,
          reason: 'replaceLine at $index should equal the rebuild',
        );
        expect(next.lineCount, rebuilt.lineCount);
        expect(next.charCount, rebuilt.charCount);
      }
    });
  });

  group('removeLine', () {
    test('drops the line at a segment head and keeps every later segment', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final next = original.removeLine(0);

      // `sublines(0, 0)` is empty, so `addFrom` adopts the tail's segments
      // wholesale: segment 0 is rebuilt (255 lines), 1..3 are the source's.
      expect(next.length, 999);
      expect(next.segments.length, 4);
      expect(identical(next.segments[0].codeLines, before[0]), isFalse);
      expect(next.segments[0].length, 255);
      for (int i = 1; i < 4; i++) {
        expect(
          identical(next.segments[i].codeLines, before[i]),
          isTrue,
          reason: 'segment $i should be re-used after removeLine(0)',
        );
      }
      expect(next[0].text, original[1].text);
      _expectConsistent(next, 'removeLine at 0');
    });

    test('mid-segment removal merges the two halves and keeps the rest', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final next = original.removeLine(600);

      // Segment 2 spans 512..767, so the head is 88 lines and the tail 167.
      // 88 + 167 = 255 <= 256, so `addFrom` merges them into one segment;
      // 255 + 232 > 256, so segment 3 is appended by reference.
      expect(next.length, 999);
      expect(next.segments.length, 4);
      expect(identical(next.segments[0].codeLines, before[0]), isTrue);
      expect(identical(next.segments[1].codeLines, before[1]), isTrue);
      expect(identical(next.segments[2].codeLines, before[2]), isFalse);
      expect(next.segments[2].length, 255);
      expect(identical(next.segments[3].codeLines, before[3]), isTrue);
      expect(next[600].text, original[601].text);
      expect(next[599].text, original[599].text);
      _expectConsistent(next, 'removeLine at 600');
    });

    test('removing a segment tail leaves the following segments shared', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final next = original.removeLine(255);

      // The head is 255 lines and the next append is a whole 256-line
      // segment, so nothing merges and segments 1..3 stay by reference.
      expect(next.length, 999);
      expect(next.segments.length, 4);
      expect(identical(next.segments[0].codeLines, before[0]), isFalse);
      expect(next.segments[0].length, 255);
      for (int i = 1; i < 4; i++) {
        expect(identical(next.segments[i].codeLines, before[i]), isTrue);
      }
      _expectConsistent(next, 'removeLine at 255');
    });

    test('removing a segment head leaves the preceding segments shared', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final next = original.removeLine(256);

      expect(next.length, 999);
      expect(next.segments.length, 4);
      expect(identical(next.segments[0].codeLines, before[0]), isTrue);
      expect(identical(next.segments[1].codeLines, before[1]), isFalse);
      expect(next.segments[1].length, 255);
      expect(identical(next.segments[2].codeLines, before[2]), isTrue);
      expect(identical(next.segments[3].codeLines, before[3]), isTrue);
      _expectConsistent(next, 'removeLine at 256');
    });

    test('removing the last line keeps every earlier segment', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final next = original.removeLine(999);

      expect(next.length, 999);
      for (int i = 0; i < 3; i++) {
        expect(identical(next.segments[i].codeLines, before[i]), isTrue);
      }
      expect(next.last.text, original[998].text);
      _expectConsistent(next, 'removeLine at the last line');
    });

    test('leaves the source untouched', () {
      final source = _document(1000);
      final original = CodeLines.of(source);
      final before = _backingLists(original);

      original.removeLine(600);

      expect(original.length, 1000);
      expect(original[600].text, source[600].text);
      for (int i = 0; i < original.segments.length; i++) {
        expect(identical(original.segments[i].codeLines, before[i]), isTrue);
      }
      _expectConsistent(original, 'removeLine source');
    });

    test('removing the only line yields an empty document', () {
      final original = CodeLines.of(<CodeLine>[_plain(1)]);

      final next = original.removeLine(0);

      expect(next.isEmpty, isTrue);
      expect(next.length, 0);
      expect(next.lineCount, 0);
      expect(next.charCount, 0);
      expect(original.length, 1);
    });

    test('is equal to a full CodeLines.of rebuild', () {
      final source = _document(1000);
      final original = CodeLines.of(source);

      for (final int index in <int>[0, 255, 256, 600, 999]) {
        final rebuilt = CodeLines.of(<CodeLine>[
          for (int i = 0; i < source.length; i++)
            if (i != index) source[i],
        ]);
        expect(
          original.removeLine(index).equals(rebuilt),
          isTrue,
          reason: 'removeLine at $index should equal the rebuild',
        );
      }
    });

    test('out of range throws', () {
      final original = CodeLines.of(_document(300));
      expect(() => original.removeLine(-1), throwsA(isA<RangeError>()));
      expect(() => original.removeLine(300), throwsA(isA<RangeError>()));
    });
  });

  group('append paths preserve the untouched segments', () {
    test('add re-owns only the tail segment', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);
      final copy = CodeLines.from(original);

      copy.add(_chunked(1));

      final int tail = copy.segments.length - 1;
      for (int i = 0; i < tail; i++) {
        expect(identical(copy.segments[i].codeLines, before[i]), isTrue);
      }
      expect(identical(copy.segments[tail].codeLines, before[tail]), isFalse);
      expect(copy.length, 1001);
      _expectConsistent(copy, 'add');
    });

    test(
      'add onto a full tail opens a new segment and keeps all identities',
      () {
        final original = CodeLines.of(_document(1024));
        final before = _backingLists(original);
        final copy = CodeLines.from(original);
        expect(before.length, 4);

        copy.add(const CodeLine('- [ ] overflow'));

        expect(copy.segments.length, 5);
        for (int i = 0; i < 4; i++) {
          expect(identical(copy.segments[i].codeLines, before[i]), isTrue);
        }
        expect(copy.segments.last.length, 1);
        _expectConsistent(copy, 'add over the segment boundary');
      },
    );

    test('addAll re-owns only the tail segment', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);
      final copy = CodeLines.from(original);

      copy.addAll(_document(400));

      for (int i = 0; i < before.length - 1; i++) {
        expect(identical(copy.segments[i].codeLines, before[i]), isTrue);
      }
      expect(copy.length, 1400);
      _expectConsistent(copy, 'addAll');
    });

    test('addFrom keeps both documents intact', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);
      final copy = CodeLines.from(original);

      final other = CodeLines.of(_document(700));
      final otherBefore = _backingLists(other);

      copy.addFrom(other, 100, 650);

      for (int i = 0; i < before.length - 1; i++) {
        expect(identical(copy.segments[i].codeLines, before[i]), isTrue);
      }
      for (int i = 0; i < other.segments.length; i++) {
        expect(identical(other.segments[i].codeLines, otherBefore[i]), isTrue);
      }
      expect(copy.length, 1550);
      _expectConsistent(copy, 'addFrom');
      _expectConsistent(other, 'addFrom source');
    });

    test('sublines shares whole segments and clones partial ones', () {
      final original = CodeLines.of(_document(1000));
      final before = _backingLists(original);

      final whole = original.sublines(0, 512);
      expect(whole.segments.length, 2);
      expect(identical(whole.segments[0].codeLines, before[0]), isTrue);
      expect(identical(whole.segments[1].codeLines, before[1]), isTrue);
      _expectConsistent(whole, 'sublines whole segments');

      final partial = original.sublines(100, 900);
      expect(partial.length, 800);
      expect(identical(partial.segments.first.codeLines, before[0]), isFalse);
      expect(identical(partial.segments[1].codeLines, before[1]), isTrue);
      _expectConsistent(partial, 'sublines partial');

      for (int i = 0; i < original.segments.length; i++) {
        expect(identical(original.segments[i].codeLines, before[i]), isTrue);
      }
      _expectConsistent(original, 'sublines source');
    });
  });

  group('segment size cap', () {
    test('no segment exceeds 256 lines after any build or append', () {
      final codeLines = CodeLines.of(_document(10000));
      _expectSegmentCap(codeLines, 'of');
      expect(codeLines.length, 10000);

      for (int i = 0; i < 300; i++) {
        codeLines.add(_plain(i));
      }
      _expectSegmentCap(codeLines, 'add');

      codeLines.addAll(_document(600));
      _expectSegmentCap(codeLines, 'addAll');

      codeLines.addFrom(CodeLines.of(_document(700)), 3, 690);
      _expectSegmentCap(codeLines, 'addFrom');

      expect(codeLines.length, 10000 + 300 + 600 + 687);
      _expectConsistent(codeLines, 'cap sequence');
    });

    test('an empty document stays empty', () {
      final codeLines = CodeLines.of(const <CodeLine>[]);
      expect(codeLines.isEmpty, isTrue);
      expect(codeLines.lineCount, 0);
      expect(codeLines.charCount, 0);

      codeLines.addAll(_document(300));
      _expectSegmentCap(codeLines, 'addAll onto empty');
      _expectConsistent(codeLines, 'addAll onto empty');

      codeLines.clear();
      expect(codeLines.isEmpty, isTrue);
      expect(codeLines.lineCount, 0);
      expect(codeLines.charCount, 0);
    });
  });

  group('counts agree with a naive fold after every mutation', () {
    test('CodeLines mutation sequence', () {
      final codeLines = CodeLines.of(_document(770));
      _expectConsistent(codeLines, 'of');

      final copy = CodeLines.from(codeLines);
      _expectConsistent(copy, 'from');

      copy[0] = _chunked(11);
      _expectConsistent(copy, '[]= at 0');

      copy[255] = const CodeLine('plain tail of segment 0');
      _expectConsistent(copy, '[]= at 255');

      copy[256] = _chunked(12);
      _expectConsistent(copy, '[]= at 256');

      copy[769] = _chunked(13);
      _expectConsistent(copy, '[]= at the last line');

      copy.add(_chunked(14));
      _expectConsistent(copy, 'add chunked');

      copy.add(_plain(15));
      _expectConsistent(copy, 'add plain');

      copy.addAll(_document(513));
      _expectConsistent(copy, 'addAll');

      copy.addFrom(CodeLines.of(_document(300)), 10, 290);
      _expectConsistent(copy, 'addFrom');

      final sub = copy.sublines(7, 900);
      _expectConsistent(sub, 'sublines');

      sub.add(_chunked(16));
      _expectConsistent(sub, 'add after sublines');

      copy.clear();
      _expectConsistent(copy, 'clear');
    });

    test('segment mutation sequence', () {
      final segment = CodeLineSegment.of(codeLines: _document(20));
      _expectSegmentConsistent(segment, 'of');

      segment.add(_chunked(101));
      _expectSegmentConsistent(segment, 'add chunked');

      segment.add(_plain(102));
      _expectSegmentConsistent(segment, 'add plain');

      segment.addAll(_document(9));
      _expectSegmentConsistent(segment, 'addAll');

      segment[3] = _chunked(103);
      _expectSegmentConsistent(segment, '[]= plain -> chunked');

      segment[3] = _plain(104);
      _expectSegmentConsistent(segment, '[]= chunked -> plain');

      segment[segment.length - 1] = _chunked(105);
      _expectSegmentConsistent(segment, '[]= at the tail');

      final removed = segment.removeAt(5);
      expect(removed, isNotNull);
      _expectSegmentConsistent(segment, 'removeAt');

      segment.removeLast();
      _expectSegmentConsistent(segment, 'removeLast');

      segment.length = 10;
      expect(segment.length, 10);
      _expectSegmentConsistent(segment, 'length = 10');

      segment.length = 0;
      expect(segment.length, 0);
      expect(segment.lineCount, 0);
      expect(segment.charCount, 0);
    });

    test('a rejected write on a dirty segment leaves the counts alone', () {
      final source = CodeLines.of(_document(30));
      final dirty = CodeLines.from(source).segments.first;
      final int lineCount = dirty.lineCount;
      final int charCount = dirty.charCount;

      expect(() => dirty.add(_plain(1)), throwsUnimplementedError);
      expect(() => dirty[0] = _chunked(1), throwsUnimplementedError);
      expect(() => dirty.length = 5, throwsUnimplementedError);

      expect(dirty.lineCount, lineCount);
      expect(dirty.charCount, charCount);
      _expectSegmentConsistent(dirty, 'rejected writes');
    });

    test('clone and cloneShallowDirty carry the same counts', () {
      final segment = CodeLineSegment.of(codeLines: _document(40));
      segment.add(_chunked(200));

      final shallow = segment.cloneShallowDirty();
      expect(identical(shallow.codeLines, segment.codeLines), isTrue);
      expect(shallow.lineCount, segment.lineCount);
      expect(shallow.charCount, segment.charCount);
      _expectSegmentConsistent(shallow, 'cloneShallowDirty');

      final cloned = segment.clone(5, 30);
      expect(cloned.length, 25);
      _expectSegmentConsistent(cloned, 'clone');
    });

    test('a segment never grows through its length setter', () {
      final segment = CodeLineSegment.of(codeLines: _document(3));
      expect(() => segment.length = 4, throwsAssertionError);
      _expectSegmentConsistent(segment, 'rejected growth');
    });
  });

  group('== and hashCode agree', () {
    test('two equal documents hash equal', () {
      final a = CodeLines.of(_document(600));
      final b = CodeLines.of(_document(600));
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('two copies of one source compare and hash equal', () {
      // A copy is never `==` its source: `from` marks every segment dirty
      // and dirtiness is part of segment equality. Two copies agree.
      final source = CodeLines.of(_document(600));
      final a = CodeLines.from(source);
      final b = CodeLines.from(source);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);

      a[300] = _plain(999);
      expect(a == b, isFalse);
    });

    test('a counting segment and a bare one hash equal when equal', () {
      final lines = _document(20);
      final counting = CodeLineSegment.of(codeLines: lines);
      final bare = CodeLineSegment(codeLines: lines);
      expect(counting == bare, isTrue);
      expect(bare == counting, isTrue);
      expect(counting.hashCode, bare.hashCode);
    });
  });

  group('range checks', () {
    test('sublines rejects a negative start and an end past the length', () {
      final lines = CodeLines.of(_document(30));
      expect(() => lines.sublines(-1, 10), throwsRangeError);
      expect(() => lines.sublines(5, 31), throwsRangeError);
      expect(() => lines.sublines(10, 5), throwsRangeError);
      expect(lines.sublines(5, 30).length, 25);
      expect(lines.sublines(30).isEmpty, isTrue);
    });

    test('replaceLine and removeLine reject an index past the end', () {
      final lines = CodeLines.of(_document(3));
      expect(() => lines.replaceLine(3, _plain(0)), throwsRangeError);
      expect(() => lines.removeLine(-1), throwsRangeError);
    });
  });
}

CodeLine _plain(int i) => CodeLine('- [ ] squat 5x5 @${100 + i % 40}kg');

CodeLine _chunked(int i) => CodeLine('## week $i', <CodeLine>[
  CodeLine('  - [ ] press $i'),
  CodeLine('  - [x] row $i', <CodeLine>[CodeLine('    note $i')]),
]);

List<CodeLine> _document(int count) =>
    List<CodeLine>.generate(count, (i) => i % 7 == 0 ? _chunked(i) : _plain(i));

List<List<CodeLine>> _backingLists(CodeLines codeLines) => <List<CodeLine>>[
  for (final CodeLineSegment segment in codeLines.segments) segment.codeLines,
];

int _naiveLineCount(CodeLines codeLines) {
  int total = 0;
  for (final CodeLineSegment segment in codeLines.segments) {
    total += _foldLineCount(segment.codeLines);
  }
  return total;
}

int _naiveCharCount(CodeLines codeLines) {
  int total = 0;
  for (final CodeLineSegment segment in codeLines.segments) {
    total += _foldCharCount(segment.codeLines);
  }
  return total;
}

int _foldLineCount(List<CodeLine> lines) {
  int total = 0;
  for (final CodeLine line in lines) {
    total += line.lineCount;
  }
  return total;
}

int _foldCharCount(List<CodeLine> lines) {
  int total = 0;
  for (final CodeLine line in lines) {
    total += line.charCount;
  }
  return total;
}

void _expectSegmentConsistent(CodeLineSegment segment, String label) {
  expect(
    segment.lineCount,
    _foldLineCount(segment.codeLines),
    reason: 'segment lineCount after $label',
  );
  expect(
    segment.charCount,
    _foldCharCount(segment.codeLines),
    reason: 'segment charCount after $label',
  );
}

String _naiveAsString(
  CodeLines codeLines,
  TextLineBreak lineBreak,
  bool expandChunks,
) {
  return <String>[
    for (final CodeLine line in codeLines.toList())
      if (expandChunks) line.asString(0, lineBreak) else line.text,
  ].join(lineBreak.value);
}

/// `operator []` against the segments read directly, so a stale prefix-sum
/// index or last-hit cache shows up as a mismatched line rather than as a
/// confusing downstream failure.
void _expectLineAccess(CodeLines codeLines, String label) {
  final List<CodeLine> lines = codeLines.toList();
  int mismatch = -1;
  for (int i = 0; i < lines.length; i++) {
    if (!identical(codeLines[i], lines[i])) {
      mismatch = i;
      break;
    }
  }
  expect(mismatch, -1, reason: 'operator [] disagreed after $label');
}

void _expectAsString(CodeLines codeLines, String label) {
  // Both line breaks and both chunk modes, so the two `asString` cache
  // slots are exercised (a single-slot cache would thrash between them).
  for (final TextLineBreak lineBreak in <TextLineBreak>[
    TextLineBreak.lf,
    TextLineBreak.crlf,
  ]) {
    for (final bool expandChunks in <bool>[true, false]) {
      expect(
        codeLines.asString(lineBreak, expandChunks),
        _naiveAsString(codeLines, lineBreak, expandChunks),
        reason: 'asString($lineBreak, $expandChunks) after $label',
      );
    }
  }
}

void _expectConsistent(CodeLines codeLines, String label) {
  for (final CodeLineSegment segment in codeLines.segments) {
    _expectSegmentConsistent(segment, label);
  }
  expect(
    codeLines.lineCount,
    _naiveLineCount(codeLines),
    reason: 'lineCount after $label',
  );
  expect(
    codeLines.charCount,
    _naiveCharCount(codeLines),
    reason: 'charCount after $label',
  );
  int length = 0;
  for (final CodeLineSegment segment in codeLines.segments) {
    length += segment.codeLines.length;
  }
  expect(codeLines.length, length, reason: 'length after $label');
  _expectLineAccess(codeLines, label);
  _expectAsString(codeLines, label);
}

void _expectSegmentCap(CodeLines codeLines, String label) {
  for (int i = 0; i < codeLines.segments.length; i++) {
    expect(
      codeLines.segments[i].length,
      lessThanOrEqualTo(256),
      reason: 'segment $i over the cap after $label',
    );
    expect(
      codeLines.segments[i].length,
      greaterThan(0),
      reason: 'empty segment $i after $label',
    );
  }
}
