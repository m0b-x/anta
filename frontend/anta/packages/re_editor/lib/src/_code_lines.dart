part of re_editor;

class _CodeLineSegmentQuckLineCount extends CodeLineSegment {
  late int _lineCount;
  late int _charCount;
  // Cache for hashCode. The default implementation in [CodeLineSegment] hashes
  // the entire codeLines list, which is O(N). Equals/hashCode are hit on every
  // controller value notification (highlight, find, chunk listeners).
  int? _hashCache;

  _CodeLineSegmentQuckLineCount({
    required super.codeLines,
    required super.dirty,
  }) {
    _lineCount = super.lineCount;
    _charCount = super.charCount;
  }

  /// Build a segment whose `_lineCount` / `_charCount` are taken directly from
  /// pre-computed values instead of re-folded over `codeLines`. Used by
  /// `CodeLines.from()` to avoid an O(N) scan over every line on each
  /// keystroke (the controller calls `CodeLines.from(codeLines)` per edit).
  _CodeLineSegmentQuckLineCount._withCounts({
    required List<CodeLine> codeLines,
    required bool dirty,
    required int lineCount,
    required int charCount,
  }) : super(codeLines: codeLines, dirty: dirty) {
    _lineCount = lineCount;
    _charCount = charCount;
  }

  @override
  int get lineCount => _lineCount;

  @override
  int get charCount => _charCount;

  @override
  int get hashCode => _hashCache ??=
      Object.hash(codeLines.length, _lineCount, _charCount, dirty);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CodeLineSegment) {
      return false;
    }
    // Cheap structural rejects before falling back to listEquals (O(N)).
    if (other.length != codeLines.length) {
      return false;
    }
    if (other.dirty != dirty) {
      return false;
    }
    if (other is _CodeLineSegmentQuckLineCount) {
      if (other._lineCount != _lineCount || other._charCount != _charCount) {
        return false;
      }
    } else if (other.lineCount != _lineCount) {
      return false;
    }
    return listEquals(other.codeLines, codeLines);
  }

  @override
  set length(int newLength) {
    final int oldLength = codeLines.length;
    int lineDelta = 0;
    int charDelta = 0;
    for (int i = newLength; i < oldLength; i++) {
      final CodeLine removed = codeLines[i];
      lineDelta += removed.lineCount;
      charDelta += removed.charCount;
    }
    super.length = newLength;
    if (newLength > oldLength) {
      _lineCount = super.lineCount;
      _charCount = super.charCount;
    } else {
      _lineCount -= lineDelta;
      _charCount -= charDelta;
    }
    _hashCache = null;
  }

  @override
  void add(CodeLine element) {
    super.add(element);
    _lineCount += element.lineCount;
    _charCount += element.charCount;
    _hashCache = null;
  }

  @override
  CodeLineSegment clone([int start = 0, int? end]) {
    if (start == 0 && (end == null || end == codeLines.length)) {
      return _CodeLineSegmentQuckLineCount._withCounts(
        codeLines: List<CodeLine>.of(codeLines),
        dirty: false,
        lineCount: _lineCount,
        charCount: _charCount,
      );
    }
    return super.clone(start, end);
  }

  @override
  void operator []=(int index, CodeLine value) {
    final CodeLine previous = codeLines[index];
    super[index] = value;
    _lineCount += value.lineCount - previous.lineCount;
    _charCount += value.charCount - previous.charCount;
    _hashCache = null;
  }
}
