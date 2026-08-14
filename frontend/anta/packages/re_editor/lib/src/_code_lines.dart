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
    super.length = newLength;
    _lineCount = super.lineCount;
    _charCount = super.charCount;
    _hashCache = null;
  }

  @override
  void add(CodeLine element) {
    super.add(element);
    _lineCount = super.lineCount;
    _charCount = super.charCount;
    _hashCache = null;
  }

  @override
  void operator []=(int index, CodeLine value) {
    super[index] = value;
    _lineCount = super.lineCount;
    _charCount = super.charCount;
    _hashCache = null;
  }
}
