import 'package:flutter/widgets.dart';

/// Bounds a `[[wiki link]]` title for the snackbars that report on one.
///
/// Display only. The lookup still receives the trimmed full title, and the
/// DAO caps what it is willing to match separately — a title too long to
/// resolve is a different concern from a title too long to read. What this
/// prevents is the other half: a note named by a pasted paragraph filling
/// the "not found" snackbar edge to edge.
///
/// The cut is taken in **grapheme clusters**, never code units, so a
/// surrogate pair or a combining mark is never split in half — half a
/// cluster renders as a replacement glyph in the middle of the message.
abstract final class WikiLinkTitle {
  /// Longest title shown in full, counted in grapheme clusters. A title
  /// past this keeps [maxDisplayLength] clusters in total: the first
  /// `maxDisplayLength - 1` plus the ellipsis.
  static const int maxDisplayLength = 80;

  /// [raw] trimmed, and elided when it is longer than [maxDisplayLength]
  /// grapheme clusters.
  static String forDisplay(String raw) {
    final trimmed = raw.trim();
    final clusters = trimmed.characters;
    if (clusters.length <= maxDisplayLength) return trimmed;
    return '${clusters.take(maxDisplayLength - 1)}…';
  }
}
