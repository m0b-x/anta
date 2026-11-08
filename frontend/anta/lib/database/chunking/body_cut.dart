import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'chunk_hasher.dart';
import 'content_chunker.dart';

/// A note body cut into content-defined chunks, each with its hash: what a
/// body write diffs against the stored rows.
final class BodyCut {
  const BodyCut._(this.text, this.ends, this.hashes);

  /// Above this many code units the cut and the hashing run on another
  /// isolate. Below it they take under 2 ms inline, and a widget test, whose
  /// fake clock never completes an `Isolate.run`, saves synchronously.
  static const int isolateThreshold = 65536;

  /// How many bodies were cut on this isolate's behalf, so a test can pin a
  /// path that must not pay for a cut (SHA-256 over the whole body).
  @visibleForTesting
  static int cutCount = 0;

  /// The cut of [text], computed inline.
  factory BodyCut.inline(String text) {
    cutCount++;
    final body = wellFormed(text);
    final (ends, hashes) = _cutAndHash(body);
    return BodyCut._(body, ends, hashes);
  }

  /// The cut of [text], off the calling isolate above [isolateThreshold].
  /// Only the offsets and hashes come back, never the text again.
  static Future<BodyCut> of(String text) async {
    if (text.length <= isolateThreshold) return BodyCut.inline(text);
    cutCount++;
    final body = wellFormed(text);
    final (ends, hashes) = await _cutAndHashOffThread(body);
    return BodyCut._(body, ends, hashes);
  }

  /// The cut of each of [texts], with what [then] makes of each cut
  /// computed where the cut was: off the calling isolate in ONE hop once the
  /// texts add up past [isolateThreshold], inline below it. A pull page cuts
  /// its bodies and encodes their chunks this way before its transaction,
  /// so the page pays one isolate start rather than one per note, and the
  /// transaction pays for neither.
  static Future<List<(BodyCut, T)>> ofEach<T>(
    List<String> texts,
    T Function(BodyCut cut, int index) then,
  ) async {
    cutCount += texts.length;
    final bodies = [for (final text in texts) wellFormed(text)];
    var units = 0;
    for (final body in bodies) {
      units += body.length;
    }
    final parts = units <= isolateThreshold
        ? _each(bodies, then)
        : await _eachOffThread(bodies, then);
    return [
      for (final (i, (ends, hashes, made)) in parts.indexed)
        (BodyCut._(bodies[i], ends, hashes), made),
    ];
  }

  /// Not async, so the closure the isolate receives captures [bodies] and
  /// [then] alone; only the offsets, hashes and [then]'s results come back.
  static Future<List<(List<int>, List<String>, T)>> _eachOffThread<T>(
    List<String> bodies,
    T Function(BodyCut cut, int index) then,
  ) => Isolate.run(() => _each(bodies, then));

  static List<(List<int>, List<String>, T)> _each<T>(
    List<String> bodies,
    T Function(BodyCut cut, int index) then,
  ) => [
    for (final (i, body) in bodies.indexed)
      if (_cutAndHash(body) case (final ends, final hashes))
        (ends, hashes, then(BodyCut._(body, ends, hashes), i)),
  ];

  /// [text] with every lone surrogate replaced by U+FFFD, the same text
  /// when it has none. SQLite stores TEXT as UTF-8, which reads a lone
  /// surrogate back as U+FFFD, so a chunk hashed over the code units it was
  /// given would never match its stored text again — its document refused,
  /// its note unsyncable for good. One code unit for one, so every offset
  /// and length stays where it was.
  static String wellFormed(String text) {
    List<int>? units;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < 0xD800 || unit > 0xDFFF) continue;
      if (unit <= 0xDBFF &&
          i + 1 < text.length &&
          (text.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
        i++;
        continue;
      }
      (units ??= text.codeUnits.toList())[i] = 0xFFFD;
    }
    return units == null ? text : String.fromCharCodes(units);
  }

  /// Not async, so the closure the isolate receives captures [text] alone.
  static Future<(List<int>, List<String>)> _cutAndHashOffThread(String text) =>
      Isolate.run(() => _cutAndHash(text));

  static (List<int>, List<String>) _cutAndHash(String text) {
    final ends = ContentChunker.cut(text);
    final hashes = <String>[];
    var start = 0;
    for (final end in ends) {
      hashes.add(ChunkHasher.hash(text, start, end));
      start = end;
    }
    return (ends, hashes);
  }

  /// The whole body.
  final String text;

  /// Each chunk's end offset in [text], ascending.
  final List<int> ends;

  /// Each chunk's [ChunkHasher] hash, in order.
  final List<String> hashes;

  /// How many chunks the body is stored as.
  int get length => ends.length;

  /// The text of chunk [index].
  String chunkText(int index) =>
      text.substring(index == 0 ? 0 : ends[index - 1], ends[index]);
}
