import 'dart:math' as math;
import 'dart:typed_data';

/// Cuts a note body into content-defined chunks: a boundary falls where the
/// text around it says so, not at a fixed offset, so an edit typically moves
/// only the boundaries next to it and every other chunk keeps its text — and
/// its hash (`docs/scalability-roadmap.md` §5.2 S4).
///
/// A Gear rolling hash over UTF-16 code units: each unit shifts the 32-bit
/// hash left by one and adds its table value, so the hash's high bits depend
/// on the last [_window] code units only, and a cut point is decided by the
/// text just before it, wherever its chunk began.
///
/// Normalized, as FastCDC is: below [targetCodeUnits] a cut point needs the
/// stricter [_strictMask], above it the looser [_looseMask], so chunk sizes
/// gather around the target and a run with no cut point is rare. When one
/// happens anyway — low-entropy text such as a long markdown table, whose
/// hash only takes a few values — the chunk ends after the smallest hash
/// between the target and the maximum, which is still a property of the
/// text, so the cuts after an edit fall back into step instead of all moving
/// with it. A deletion can cascade further than an insert before the cuts
/// fall back: 2 of 300 random deletions measured rewrote up to 8 chunks.
///
/// The table, the masks and the bounds are frozen: changing any of them
/// moves every boundary of every note, so each note's next save rewrites its
/// whole body, and the chunk hashes another device holds stop matching.
abstract final class ContentChunker {
  /// No chunk but a body's last is shorter, so a run of cut points close
  /// together cannot shred the text into tiny rows.
  static const int minCodeUnits = 4096;

  /// Where the stricter mask gives way to the looser one: chunks gather
  /// around this size.
  static const int targetCodeUnits = 8192;

  /// No chunk is longer, so one row stays a bounded write however long a
  /// stretch of text finds no cut point.
  static const int maxCodeUnits = 16384;

  /// The high bits a cut point below [targetCodeUnits] has clear: 15, one
  /// code unit in 32,768.
  static const int _strictMask = 0xFFFE0000;

  /// The high bits a cut point from [targetCodeUnits] on has clear: 11, one
  /// code unit in 2,048, so the maximum is reached by about one chunk in 50.
  static const int _looseMask = 0xFFE00000;

  /// How many trailing code units the high bits of the hash depend on: the
  /// shift pushes anything older out of the 32 bits.
  static const int _window = 32;

  static final Uint32List _gear = _buildGear();

  /// The 256 table values, from xorshift32 off a fixed seed.
  static Uint32List _buildGear() {
    final table = Uint32List(256);
    var x = 0x9E3779B9;
    for (var i = 0; i < table.length; i++) {
      x ^= (x << 13) & 0xFFFFFFFF;
      x ^= x >> 17;
      x ^= (x << 5) & 0xFFFFFFFF;
      table[i] = x;
    }
    return table;
  }

  /// The end offset of every chunk of [text], ascending; the last is
  /// `text.length`. Empty for an empty text. Never between the two halves of
  /// a surrogate pair: a chunk is hashed and compressed on its own, and UTF-8
  /// writes a lone surrogate as U+FFFD.
  static List<int> cut(String text) {
    final ends = <int>[];
    var start = 0;
    while (start < text.length) {
      start = _nextEnd(text, start);
      ends.add(start);
    }
    return ends;
  }

  static int _nextEnd(String text, int start) {
    final length = text.length;
    if (length - start <= minCodeUnits) return length;
    final limit = math.min(start + maxCodeUnits, length);
    final earliest = start + minCodeUnits;
    final target = start + targetCodeUnits;
    var hash = 0;
    var lowest = -1;
    var lowestHash = 0;
    for (var i = earliest - _window; i < limit; i++) {
      final unit = text.codeUnitAt(i);
      hash = ((hash << 1) + _gear[(unit ^ (unit >> 8)) & 0xFF]) & 0xFFFFFFFF;
      final end = i + 1;
      if (end < earliest || _isHighSurrogate(unit)) continue;
      if (end < target) {
        if (hash & _strictMask == 0) return end;
        continue;
      }
      if (hash & _looseMask == 0) return end;
      if (lowest < 0 || hash < lowestHash) {
        lowest = end;
        lowestHash = hash;
      }
    }
    if (limit == length) return length;
    // Only text made of lone high surrogates offers no position at all.
    return lowest < 0 ? limit : lowest;
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
}
