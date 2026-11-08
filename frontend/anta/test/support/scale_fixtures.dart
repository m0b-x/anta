/// Note bodies at the sizes the scalability roadmap fixes
/// (`docs/scalability-roadmap.md` §2, §5.1 S3): a multi-year training log
/// or journal of 100 KB to 3 MB, the size no other suite writes.
library;

import 'dart:math';

/// The weight-lifter emoji, U+1F3CB: outside the Basic Multilingual Plane,
/// so it is two UTF-16 code units — the character a cut at a fixed offset
/// splits.
const String lifter = '\u{1F3CB}';

/// The legacy fixed slice size — what `ContentChunkDao` cut a body at before
/// v46's content-defined chunks — on whose boundaries the fixture places its
/// surrogate pairs, the cut S2 made safe.
const int chunkCodeUnits = 10000;

/// The largest row the pusher sends: `_Pusher.maxDocumentBytes`
/// (`lib/services/sync/sync_pusher.dart:18`). The class is library-private,
/// so the value is restated here; it moves with [maxBatchBytesToday], since
/// a batch must always fit at least one row.
const int maxDocumentBytesToday = 900000;

/// The most row data the pusher sends in one call: `_Pusher.maxBatchBytes`
/// (`lib/services/sync/sync_pusher.dart:23`), restated for the same reason
/// as [maxDocumentBytesToday] and moving with it.
const int maxBatchBytesToday = 8 * 1024 * 1024;

const List<String> _lines = [
  '# Week {n}: training log',
  '- Squat 5x5 @ 100 kg, bench 3x8, row 4x10, notes on form and tempo.',
  'Antrenament de forță {n}: genuflexiuni, îndreptări, tracțiuni și fandări.',
  'Krafttraining {n}: Kniebeugen, Kreuzheben, Klimmzüge, größere Gewichte.',
  '',
];

/// A deterministic markdown-like body of exactly [codeUnits] UTF-16 code
/// units: ASCII, Romanian and German lines (diacritics included), with a
/// [lifter] straddling every interior multiple of [chunkCodeUnits] — its
/// high surrogate the last code unit before the former boundary, its low
/// one the first after — so a note still stored as legacy fixed slices
/// meets a surrogate pair at each of them, and `ContentChunker` meets pairs
/// its surrogate rule must never cut through.
String bigBody(int codeUnits) {
  final units = <int>[];
  var n = 0;
  while (units.length < codeUnits) {
    for (final line in _lines) {
      units
        ..addAll(line.replaceAll('{n}', '$n').codeUnits)
        ..add(0x0A);
    }
    n++;
  }
  units.length = codeUnits;
  final pair = lifter.codeUnits;
  for (var at = chunkCodeUnits; at < codeUnits; at += chunkCodeUnits) {
    units[at - 1] = pair[0];
    units[at] = pair[1];
  }
  return String.fromCharCodes(units);
}

/// [body] with one character inserted 100 code units into its second slice:
/// every fixed-offset boundary after it moves by one.
///
/// Not into the first slice: the surrogate-safe cut ends it one code unit
/// short, before the [lifter] on its boundary, so an insert there makes it
/// whole and realigns every later boundary — a saving only this fixture's
/// placement gets, which would hide the cost the pin is about.
String editNearTop(String body) => _insertAt(body, chunkCodeUnits + 100);

/// [body] with one character inserted at its middle, stepped past a
/// surrogate pair rather than into it.
String editInMiddle(String body) => _insertAt(body, body.length ~/ 2);

/// [body] with one character appended: only the last slice changes.
String editAtEnd(String body) => '${body}x';

/// [codeUnits] of pseudo-random text drawn by [seed], each code unit three
/// bytes of UTF-8 that gzip keeps at about two: bodies of different seeds
/// share no chunk and none shrinks to nothing on the wire, so a push's
/// parts are cut by the bodies' own size — what `'x' * n` hid once chunks
/// were content-addressed (scalability record S6).
String noiseBody(int codeUnits, {required int seed}) {
  final random = Random(seed);
  return String.fromCharCodes([
    for (var i = 0; i < codeUnits; i++) 0x0800 + random.nextInt(0xD000),
  ]);
}

String _insertAt(String body, int offset) {
  var at = offset;
  if (at > 0 && at < body.length && _isHighSurrogate(body.codeUnitAt(at - 1))) {
    at++;
  }
  return '${body.substring(0, at)}x${body.substring(at)}';
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
