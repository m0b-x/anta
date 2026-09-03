part of re_editor;

const int _kCodeLineSegamentDefaultSize = 256;

class CodeLines {
  final List<CodeLineSegment> segments;

  // Cached aggregates. `null` means stale and must be recomputed lazily.
  // These avoid O(segments) folds on every call to length/lineCount/charCount,
  // which are hit per frame and per line during scroll/paint/edit.
  int? _lengthCache;
  int? _lineCountCache;
  int? _charCountCache;

  // Cumulative end-offsets per segment. `_segmentEnds[i]` is the sum of
  // `segments[0..i].length`. Used as a binary-search index by `operator []`.
  // Stale when `null`.
  List<int>? _segmentEnds;

  // "Last segment hit" cache for sequential `operator []` access (the common
  // pattern: paint loop, find iteration, line indicator, etc.).
  int _lastHitSegment = 0;
  int _lastHitStart = 0;
  int _lastHitEnd = 0;

  // Cache the joined-string form. Two slots because the editor concurrently
  // asks for both the user-facing text (`asString(lineBreak, true)` via
  // `controller.text`) and the highlight payload (`asString(lf, false)`).
  // A single-slot cache would thrash between them on every keystroke.
  String? _asStringCache0;
  TextLineBreak? _asStringCache0LineBreak;
  bool _asStringCache0ExpandChunks = true;
  String? _asStringCache1;
  TextLineBreak? _asStringCache1LineBreak;
  bool _asStringCache1ExpandChunks = true;

  CodeLines(this.segments);

  factory CodeLines.empty() {
    return CodeLines.of([]);
  }

  factory CodeLines.fromText(String text) {
    return text.codeLines;
  }

  factory CodeLines.from(CodeLines codeLines) {
    final List<CodeLineSegment> segments = [];
    for (final CodeLineSegment segment in codeLines.segments) {
      if (segment.isEmpty) {
        continue;
      }
      // `cloneShallowDirty` reuses cached lineCount/charCount instead of
      // re-iterating segment.codeLines (was O(N) per keystroke).
      segments.add(segment.cloneShallowDirty());
    }
    final CodeLines copy = CodeLines(segments);
    // Precondition: a source `CodeLines` is never structurally mutated after a
    // `from` copy — callers copy, write the copy, publish, and never touch the
    // source again. The segment backing lists already share on that rule;
    // `_segmentEnds`/`_lengthCache` join them unless an empty segment was
    // dropped above, which changes the layout.
    if (segments.length == codeLines.segments.length) {
      copy._segmentEnds = codeLines._segmentEnds;
      copy._lengthCache = codeLines._lengthCache;
    }
    return copy;
  }

  factory CodeLines.of(Iterable<CodeLine> elements) {
    final List<CodeLineSegment> segments = [];
    int count = 0;
    for (int i = 0; i < elements.length; i++) {
      if (count == 0) {
        segments.add(CodeLineSegment.of(codeLines: []));
      }
      segments.last.add(elements.elementAt(i));
      count++;
      if (count >= _kCodeLineSegamentDefaultSize) {
        count = 0;
      }
    }
    return CodeLines(segments);
  }

  /// Invalidate only what replacing one line in place can change. The
  /// segment layout — and therefore `_segmentEnds`, `_lengthCache` and the
  /// last-hit fields — is untouched by such a write.
  void _invalidateLineContent() {
    _lineCountCache = null;
    _charCountCache = null;
    _asStringCache0 = null;
    _asStringCache0LineBreak = null;
    _asStringCache1 = null;
    _asStringCache1LineBreak = null;
  }

  /// Invalidate all derived caches after a structural mutation.
  void _invalidate() {
    _lengthCache = null;
    _lineCountCache = null;
    _charCountCache = null;
    _segmentEnds = null;
    _lastHitSegment = 0;
    _lastHitStart = 0;
    _lastHitEnd = 0;
    _asStringCache0 = null;
    _asStringCache0LineBreak = null;
    _asStringCache1 = null;
    _asStringCache1LineBreak = null;
  }

  /// (Re)build the prefix-sum index over segment lengths. O(segments).
  List<int> _ensureSegmentEnds() {
    var ends = _segmentEnds;
    if (ends != null) {
      return ends;
    }
    ends = List<int>.filled(segments.length, 0);
    int total = 0;
    for (int i = 0; i < segments.length; i++) {
      total += segments[i].length;
      ends[i] = total;
    }
    _segmentEnds = ends;
    _lengthCache = total;
    return ends;
  }

  CodeLine get first => segments.first.first;

  CodeLine get last => segments.last.last;

  int get length {
    final cached = _lengthCache;
    if (cached != null) {
      return cached;
    }
    int total = 0;
    for (final CodeLineSegment segment in segments) {
      total += segment.length;
    }
    return _lengthCache = total;
  }

  bool get isEmpty => segments.isEmpty || length == 0;

  bool get isNotEmpty => !isEmpty;

  int get lineCount {
    final cached = _lineCountCache;
    if (cached != null) {
      return cached;
    }
    int total = 0;
    for (final CodeLineSegment segment in segments) {
      total += segment.lineCount;
    }
    return _lineCountCache = total;
  }

  int get charCount {
    final cached = _charCountCache;
    if (cached != null) {
      return cached;
    }
    int total = 0;
    for (final CodeLineSegment segment in segments) {
      total += segment.charCount;
    }
    return _charCountCache = total;
  }

  /// The index of the segment holding line [index], by binary search over
  /// the prefix-sum index. Throws [RangeError] when [index] is out of the
  /// document.
  int _segmentIndexFor(int index) {
    final List<int> ends = _ensureSegmentEnds();
    if (ends.isEmpty || index < 0 || index >= ends.last) {
      throw RangeError.range(index, 0, ends.isEmpty ? -1 : ends.last - 1);
    }
    int lo = 0;
    int hi = ends.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (ends[mid] <= index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  CodeLine operator [](int index) {
    // Fast path: same segment as the previous lookup (very common during
    // sequential paint/iteration).
    if (index >= _lastHitStart && index < _lastHitEnd) {
      return segments[_lastHitSegment][index - _lastHitStart];
    }
    final int segmentIndex = _segmentIndexFor(index);
    final List<int> ends = _segmentEnds!;
    final int segStart = segmentIndex == 0 ? 0 : ends[segmentIndex - 1];
    _lastHitSegment = segmentIndex;
    _lastHitStart = segStart;
    _lastHitEnd = ends[segmentIndex];
    return segments[segmentIndex][index - segStart];
  }

  void operator []=(int index, CodeLine value) {
    final int segmentIndex = _segmentIndexFor(index);
    final List<int> ends = _segmentEnds!;
    final int segStart = segmentIndex == 0 ? 0 : ends[segmentIndex - 1];
    CodeLineSegment segment = segments[segmentIndex];
    if (segment.dirty) {
      segment = segment.clone();
      segments[segmentIndex] = segment;
    }
    segment[index - segStart] = value;
    // Only the line's own aggregates can move (lineCount/charCount when
    // chunks differ, and the joined-string caches). The segment layout is
    // untouched, so the prefix-sum index and the last-hit fields stay
    // valid — and stay warm for the next lookup.
    _invalidateLineContent();
  }

  void add(CodeLine value) {
    if (isEmpty || segments.last.length >= _kCodeLineSegamentDefaultSize) {
      segments.add(CodeLineSegment.of(codeLines: [value]));
    } else {
      CodeLineSegment segment = segments.last;
      if (segment.dirty) {
        segment = segment.clone();
        segments.last = segment;
      }
      segment.add(value);
    }
    _invalidate();
  }

  void addAll(Iterable<CodeLine> iterable) {
    if (isEmpty) {
      segments.addAll(CodeLines.of(iterable).segments);
      _invalidate();
      return;
    }
    final CodeLineSegment segment = segments.last;
    int count;
    if (segment.length >= _kCodeLineSegamentDefaultSize) {
      count = 0;
    } else {
      count = segment.length;
      if (segment.dirty) {
        segments.last = segment.clone();
      }
    }
    for (int i = 0; i < iterable.length; i++) {
      if (count == 0) {
        segments.add(CodeLineSegment.of(codeLines: []));
      }
      segments.last.add(iterable.elementAt(i));
      count++;
      if (count >= _kCodeLineSegamentDefaultSize) {
        count = 0;
      }
    }
    _invalidate();
  }

  void addFrom(CodeLines codeLines, int start, [int? end]) {
    final CodeLines sub = codeLines.sublines(start, end);
    if (sub.isEmpty) {
      return;
    }
    if (isEmpty) {
      segments.addAll(sub.segments);
      _invalidate();
      return;
    }
    final List<CodeLineSegment> appendSegments = sub.segments;
    for (int i = 0; i < appendSegments.length; i++) {
      CodeLineSegment tail = segments.last;
      final CodeLineSegment appendSegment = appendSegments[i];
      if (tail.length + appendSegment.length <= _kCodeLineSegamentDefaultSize) {
        if (tail.dirty) {
          tail = tail.clone();
          segments.last = tail;
        }
        tail.addAll(appendSegment);
      } else {
        segments.add(appendSegment);
      }
    }
    _invalidate();
  }

  bool equals(CodeLines? codeLines) {
    if (codeLines == null) {
      return false;
    }
    // Quick comparation
    if (isEmpty && codeLines.isEmpty) {
      return true;
    }
    if (isEmpty && codeLines.isNotEmpty) {
      return false;
    }
    if (isNotEmpty && codeLines.isEmpty) {
      return false;
    }
    if (first != codeLines.first) {
      return false;
    }
    if (last != codeLines.last) {
      return false;
    }
    final int length1 = length;
    final int length2 = codeLines.length;
    if (length1 != length2) {
      return false;
    }
    final int minSegmentLength =
        min(segments.length, codeLines.segments.length);
    int offset = 0;
    for (int i = 0; i < minSegmentLength; i++) {
      if (segments[i].length != codeLines.segments[i].length) {
        break;
      }
      if (!listEquals(segments[i].codeLines, codeLines.segments[i].codeLines)) {
        return false;
      }
      offset += segments[i].length;
    }
    // The worst is the distributions are different, we should compare them one by one
    for (int i = offset; i < length1; i++) {
      if (this[i] != codeLines[i]) {
        return false;
      }
    }
    return true;
  }

  CodeLines sublines(int start, [int? end]) {
    end ??= length;
    if (end > length) {
      throw RangeError.range(end, 0, length - 1);
    }
    if (start > end) {
      throw RangeError('start $start should be less than end $end');
    }
    if (start == end) {
      return CodeLines.empty();
    }
    final List<CodeLineSegment> newSegments = [];
    int offset = 0;
    for (final CodeLineSegment segment in segments) {
      if (start - offset >= segment.length) {
        offset += segment.length;
        continue;
      }
      if (start <= offset) {
        if (end - offset >= segment.length) {
          // Same dirty shallow copy as `copyWith(dirty: true)`, but reuses
          // the cached lineCount/charCount instead of re-folding the segment.
          newSegments.add(segment.cloneShallowDirty());
          offset += segment.length;
          continue;
        } else {
          if (end > offset) {
            newSegments.add(segment.clone(0, end - offset));
          }
          break;
        }
      } else {
        if (end - offset >= segment.length) {
          newSegments.add(segment.clone(start - offset, segment.length));
          offset += segment.length;
          continue;
        } else {
          newSegments.add(segment.clone(start - offset, end - offset));
          break;
        }
      }
    }
    assert(
      newSegments.every((segment) => segment.isNotEmpty),
      'sublines($start, $end) produced an empty segment; addFrom would then '
      'merge it into a shared tail and silently re-own that segment',
    );
    return CodeLines(newSegments);
  }

  /// A copy of this document with line [index] replaced by [line].
  ///
  /// `this` is left untouched. Only the segment holding [index] re-owns its
  /// backing list; every other segment's list stays shared by identity with
  /// this document's, which is what an incremental per-line index can use as
  /// its dirty flag.
  CodeLines replaceLine(int index, CodeLine line) {
    if (index < 0 || index >= length) {
      throw RangeError.range(index, 0, length - 1);
    }
    final CodeLines copy = CodeLines.from(this);
    copy[index] = line;
    return copy;
  }

  /// A copy of this document without line [index].
  ///
  /// `this` is left untouched. Whole segments before and after the removed
  /// line keep sharing their backing list wherever [sublines] and [addFrom]
  /// already share them; only the segment the line sat in is rebuilt (and,
  /// per [addFrom]'s merge rule, possibly joined with the segment after it).
  ///
  /// Removing the only line yields an empty `CodeLines`, which a controller
  /// cannot render. A caller must either guarantee another line survives —
  /// the page's Enter-on-empty-item path does, removing line `current - 1`
  /// with `current > 0` — or route the result through the controller's
  /// `codeLines` setter, which maps an empty document onto the initial
  /// blank line.
  CodeLines removeLine(int index) {
    if (index < 0 || index >= length) {
      throw RangeError.range(index, 0, length - 1);
    }
    final CodeLines result = sublines(0, index);
    if (index + 1 < length) {
      result.addFrom(this, index + 1);
    }
    return result;
  }

  void clear() {
    segments.clear();
    _invalidate();
  }

  String asString(TextLineBreak lineBreak, [bool expandChunks = true]) {
    if (_asStringCache0 != null &&
        _asStringCache0LineBreak == lineBreak &&
        _asStringCache0ExpandChunks == expandChunks) {
      return _asStringCache0!;
    }
    if (_asStringCache1 != null &&
        _asStringCache1LineBreak == lineBreak &&
        _asStringCache1ExpandChunks == expandChunks) {
      return _asStringCache1!;
    }
    final StringBuffer sb = StringBuffer();
    final int length = this.length;
    int count = 0;
    for (final CodeLineSegment segment in segments) {
      for (final CodeLine codeLine in segment.codeLines) {
        count++;
        if (expandChunks) {
          sb.write(codeLine.asString(0, lineBreak));
        } else {
          sb.write(codeLine.text);
        }
        if (count != length) {
          sb.write(lineBreak.value);
        }
      }
    }
    final String result = sb.toString();
    // Round-robin slots: shift slot 0 to slot 1 and put the new entry in 0.
    _asStringCache1 = _asStringCache0;
    _asStringCache1LineBreak = _asStringCache0LineBreak;
    _asStringCache1ExpandChunks = _asStringCache0ExpandChunks;
    _asStringCache0 = result;
    _asStringCache0LineBreak = lineBreak;
    _asStringCache0ExpandChunks = expandChunks;
    return result;
  }

  int index2lineIndex(int index) {
    if (index < 0 || index >= length) {
      return -1;
    }
    int lineIndex = 0;
    int offset = 0;
    for (final CodeLineSegment segment in segments) {
      if (index - offset >= segment.length) {
        offset += segment.length;
        lineIndex += segment.lineCount;
      } else {
        for (int j = 0; j < index - offset; j++) {
          lineIndex += segment[j].lineCount;
        }
        break;
      }
    }
    return lineIndex;
  }

  CodeLineIndex lineIndex2Index(int lineIndex) {
    if (lineIndex < 0) {
      return const CodeLineIndex(-1, -1);
    }
    // Find the segment first
    int segmentIndex = -1;
    int lineCount = 0;
    for (int i = 0, start = 0; i < segments.length; i++) {
      final int end = start + segments[i].lineCount;
      if (lineIndex >= start && lineIndex < end) {
        segmentIndex = i;
        lineIndex -= start;
        break;
      }
      start = end;
      lineCount += segments[i].length;
    }
    if (segmentIndex < 0) {
      return const CodeLineIndex(-1, -1);
    }
    // Find the index in the segment
    final List<CodeLine> codeLines = segments[segmentIndex].codeLines;
    int index = -1;
    int start = 0;
    for (int i = 0; i < codeLines.length; i++) {
      final int end = start + codeLines[i].lineCount;
      if (lineIndex >= start && lineIndex < end) {
        index = i;
        start++;
        break;
      }
      start = end;
    }
    if (index == -1) {
      return const CodeLineIndex(-1, -1);
    }
    // Find the index in the chunk
    int chunkIndex = -1;
    final List<CodeLine> chunks = codeLines[index].chunks;
    for (int i = 0; i < chunks.length; i++) {
      final int end = start + chunks[i].lineCount;
      if (lineIndex >= start && lineIndex < end) {
        chunkIndex = i;
        break;
      }
      start = end;
    }
    return CodeLineIndex(index + lineCount, chunkIndex);
  }

  List<CodeLine> toList() {
    final List<CodeLine> codeLines = [];
    for (final CodeLineSegment segment in segments) {
      codeLines.addAll(segment.codeLines);
    }
    return codeLines;
  }

  @override
  int get hashCode => segments.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeLines && listEquals(other.segments, segments);
  }

  @override
  String toString() {
    return '[ ${segments.join(',')} ]';
  }
}

class CodeLineSegment with ListMixin<CodeLine> {
  final List<CodeLine> codeLines;
  final bool dirty;

  const CodeLineSegment({required this.codeLines, this.dirty = false});

  factory CodeLineSegment.of(
          {required List<CodeLine> codeLines, bool dirty = false}) =>
      _CodeLineSegmentQuckLineCount(codeLines: codeLines, dirty: dirty);

  @override
  int get length => codeLines.length;

  int get lineCount => codeLines.fold(
      0, (previousValue, element) => previousValue += element.lineCount);

  int get charCount => codeLines.fold(
      0, (previousValue, element) => previousValue += element.charCount);

  @override
  CodeLine operator [](int index) {
    return codeLines[index];
  }

  @override
  void operator []=(int index, CodeLine value) {
    if (dirty) {
      // Not support write operation
      throw UnimplementedError();
    } else {
      codeLines[index] = value;
    }
  }

  @override
  set length(int newLength) {
    if (dirty) {
      // Not support write operation
      throw UnimplementedError();
    } else {
      codeLines.length = newLength;
    }
  }

  @override
  void add(CodeLine element) {
    if (dirty) {
      // Not support write operation
      throw UnimplementedError();
    } else {
      codeLines.add(element);
    }
  }

  CodeLineSegment clone([int start = 0, int? end]) =>
      CodeLineSegment.of(codeLines: codeLines.sublist(start, end));

  /// Create a `dirty=true` shallow copy of this segment that shares the
  /// underlying `codeLines` list. Used by `CodeLines.from()` so that we do
  /// not re-fold `codeLines` to recompute `lineCount` / `charCount` on every
  /// edit (it can be O(total document lines) otherwise).
  CodeLineSegment cloneShallowDirty() {
    return _CodeLineSegmentQuckLineCount._withCounts(
      codeLines: codeLines,
      dirty: true,
      lineCount: lineCount,
      charCount: charCount,
    );
  }

  CodeLineSegment copyWith({
    List<CodeLine>? codeLines,
    bool? dirty,
  }) {
    return CodeLineSegment.of(
        codeLines: codeLines ?? this.codeLines, dirty: dirty ?? this.dirty);
  }

  @override
  int get hashCode => Object.hash(codeLines.length, lineCount, dirty);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeLineSegment &&
        listEquals(other.codeLines, codeLines) &&
        other.lineCount == lineCount &&
        other.dirty == dirty;
  }

  @override
  String toString() {
    return '[ ${join(',')} ]';
  }
}
