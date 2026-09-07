import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/utils/markdown_color_syntax.dart';

/// E20 — a custom colour is lightness-shifted until it clears 3.0 against
/// the surface it will actually be drawn on. The guard used to resolve
/// against `#FFFFFF` / `#121212`, neither of which the app paints: the
/// real grounds are `#FEF7FF` and `#141218`, so a colour could pass the
/// check and still land under the floor once rendered.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const minContrast = 3.0;

  // Colours that need shifting on at least one theme: a near-white, a
  // near-black, and mid-tones that sit close to the floor on one side.
  const sources = <String, int>{
    'paper': 0xFFFDFDFD,
    'ink': 0xFF050505,
    'mud': 0xFF7A7A7A,
    'lime': 0xFFB8E986,
    'navy': 0xFF12224A,
  };

  test('a resolved custom colour clears 3.0 against the app surfaces', () {
    final palette = MarkdownColorPalette.decode(
      sources.entries
          .map((e) => '${e.key}=${e.value.toRadixString(16).padLeft(8, '0')}')
          .join(';'),
    );

    for (final name in sources.keys) {
      final spec = palette.lookup(name);
      expect(spec, isNotNull, reason: name);
      expect(
        _contrast(spec!.text(dark: false), AppTheme.lightScheme.surface),
        greaterThanOrEqualTo(minContrast),
        reason: '$name on the light surface',
      );
      expect(
        _contrast(spec.text(dark: true), AppTheme.darkScheme.surface),
        greaterThanOrEqualTo(minContrast),
        reason: '$name on the dark surface',
      );
    }
  });

  test('a colour that already reads is used verbatim', () {
    final palette = MarkdownColorPalette.decode('signal=ff8b0000');
    final spec = palette.lookup('signal')!;
    expect(spec.lightText, const Color(0xFF8B0000));
  });
}
