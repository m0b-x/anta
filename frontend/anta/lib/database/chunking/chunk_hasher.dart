import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A chunk's identity: SHA-256 over its UTF-16 code units, each written as
/// two bytes little-endian, as 64 lowercase hex digits.
///
/// UTF-16 rather than UTF-8 so the bytes are the code units exactly: UTF-8
/// would write any lone surrogate as U+FFFD, and two different texts would
/// hash alike. Cryptographic because the hash is also the chunk's id on the
/// chunked sync wire, where two devices must never name different text the
/// same (`docs/scalability-roadmap.md` §5.2 S4, decision D1). Frozen: a new
/// definition would read every stored chunk as changed.
abstract final class ChunkHasher {
  /// The hash of `text.substring(start, end)`, without the substring.
  static String hash(String text, [int start = 0, int? end]) {
    final stop = end ?? text.length;
    final bytes = Uint8List(2 * (stop - start));
    for (var i = start, j = 0; i < stop; i++, j += 2) {
      final unit = text.codeUnitAt(i);
      bytes[j] = unit & 0xFF;
      bytes[j + 1] = unit >> 8;
    }
    return sha256.convert(bytes).toString();
  }
}
