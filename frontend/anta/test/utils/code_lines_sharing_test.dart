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

    test('add onto a full tail opens a new segment and keeps all identities',
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
    });

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
  });
}

CodeLine _plain(int i) => CodeLine('- [ ] squat 5x5 @${100 + i % 40}kg');

CodeLine _chunked(int i) => CodeLine('## week $i', <CodeLine>[
  CodeLine('  - [ ] press $i'),
  CodeLine('  - [x] row $i', <CodeLine>[CodeLine('    note $i')]),
]);

List<CodeLine> _document(int count) => List<CodeLine>.generate(
  count,
  (i) => i % 7 == 0 ? _chunked(i) : _plain(i),
);

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
