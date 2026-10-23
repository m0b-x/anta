import 'dart:io';

import 'package:flutter/services.dart';

/// The Roboto faces the app's text styles reach: the weights `Typography`
/// and the theme name, and the italics markdown emphasis draws.
const _robotoFaces = [
  'roboto-regular.ttf',
  'roboto-medium.ttf',
  'roboto-bold.ttf',
  'roboto-italic.ttf',
  'roboto-bolditalic.ttf',
  'roboto-light.ttf',
  'roboto-black.ttf',
];

const _iconFace = 'materialicons-regular.otf';

/// Where the SDK caches its Material fonts, relative to the SDK root.
const _fontPath = 'bin/cache/artifacts/material_fonts';

bool _loaded = false;

/// Registers Roboto and MaterialIcons from the Flutter SDK cache, so a
/// golden shows real glyphs instead of the test font's boxes.
///
/// The fonts come from the SDK the test runs on rather than from the repo:
/// they are identical on every machine with the same Flutter version, which
/// is the condition a golden already depends on, and nothing binary is
/// committed for them. Idempotent — a second call is a no-op.
Future<void> loadGoldenFonts() async {
  if (_loaded) return;
  final dir = _fontDirectory();
  final roboto = FontLoader('Roboto');
  for (final face in _robotoFaces) {
    roboto.addFont(_read(dir, face));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(_read(dir, _iconFace))).load();
  _loaded = true;
}

Future<ByteData> _read(Directory dir, String face) async {
  final bytes = await File('${dir.path}/$face').readAsBytes();
  return ByteData.sublistView(bytes);
}

/// `FLUTTER_ROOT` when `flutter test` set it; otherwise the first ancestor of
/// the running executable (the engine's `flutter_tester`, or the cached Dart
/// SDK's `dart`, both under `bin/cache`) that holds the font cache.
Directory _fontDirectory() {
  final looked = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    final dir = Directory('$root/$_fontPath');
    if (_complete(dir)) return dir;
    looked.add(dir.path);
  }
  var current = File(Platform.resolvedExecutable).parent;
  while (true) {
    final dir = Directory('${current.path}/$_fontPath');
    if (_complete(dir)) return dir;
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  looked.add('every ancestor of ${Platform.resolvedExecutable} + /$_fontPath');
  throw StateError(
    'The golden fonts are missing. Looked in: ${looked.join('; ')}. '
    'Run `flutter precache` to restore the SDK font cache.',
  );
}

bool _complete(Directory dir) => [
  ..._robotoFaces,
  _iconFace,
].every((face) => File('${dir.path}/$face').existsSync());
