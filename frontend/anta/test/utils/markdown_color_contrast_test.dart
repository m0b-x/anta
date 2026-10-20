import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/markdown_callout_syntax.dart';
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

  // U3.1 / U3.2 — the shared accents and a done task's text are read as
  // body text on the light page, so they hold the 4.5:1 body floor.
  const bodyContrast = 4.5;
  final lightPage = AppTheme.lightScheme.surface;
  // The editor paints no ground of its own, so a money row or a done task
  // sits on the page — or, with the cursor-line setting on, on the caret
  // line's tint.
  final lightGrounds = <String, Color>{
    'light page': lightPage,
    'cursor line': AppTheme.lightScheme.surfaceContainerLow,
  };

  test('every light callout accent clears 4.5:1 on the light grounds', () {
    for (final type in MarkdownCalloutType.values) {
      for (final ground in lightGrounds.entries) {
        expect(
          _contrast(
            MarkdownConstants.calloutAccent(type, dark: false),
            ground.value,
          ),
          greaterThanOrEqualTo(bodyContrast),
          reason: '${type.name} on the ${ground.key}',
        );
      }
    }
  });

  test('every light money accent clears 4.5:1 on the light page', () {
    final accents = <String, Color>{
      'positive': MarkdownConstants.moneyPositive(dark: false),
      'negative': MarkdownConstants.moneyNegative(dark: false),
      'neutral': MarkdownConstants.moneyNeutral(dark: false),
      'warning': MarkdownConstants.moneyWarning(dark: false),
    };
    for (final entry in accents.entries) {
      for (final ground in lightGrounds.entries) {
        expect(
          _contrast(entry.value, ground.value),
          greaterThanOrEqualTo(bodyContrast),
          reason: '${entry.key} on the ${ground.key}',
        );
      }
    }
  });

  test('a done task\'s dimmed text clears 4.5:1 on the light page', () {
    for (final ground in lightGrounds.entries) {
      final dimmed = Color.alphaBlend(
        AppTheme.lightScheme.onSurface.withValues(
          alpha: MarkdownConstants.checkedTextOpacity,
        ),
        ground.value,
      );
      expect(
        _contrast(dimmed, ground.value),
        greaterThanOrEqualTo(bodyContrast),
        reason: ground.key,
      );
    }
  });

  test('a colour that already reads is used verbatim', () {
    final palette = MarkdownColorPalette.decode('signal=ff8b0000');
    final spec = palette.lookup('signal')!;
    expect(spec.lightText, const Color(0xFF8B0000));
  });
}
