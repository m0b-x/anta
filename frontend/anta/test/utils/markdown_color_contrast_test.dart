import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_callout_syntax.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/money_display_config.dart';

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

  // Every ground a note's text is drawn on, light and dark: the page, the
  // caret line's tint, and the sheets and cards (the money detail sheet,
  // the guide's "Try it" cards) on surfaceContainer.
  ColorScheme schemeOf({required bool dark}) =>
      dark ? AppTheme.darkScheme : AppTheme.lightScheme;
  final noteGrounds = <({bool dark, String name, Color color})>[
    for (final dark in [false, true])
      for (final role in ['surface', 'surfaceContainerLow', 'surfaceContainer'])
        (
          dark: dark,
          name: '${dark ? 'dark' : 'light'} $role',
          color: switch (role) {
            'surface' => schemeOf(dark: dark).surface,
            'surfaceContainerLow' => schemeOf(dark: dark).surfaceContainerLow,
            _ => schemeOf(dark: dark).surfaceContainer,
          },
        ),
  ];

  /// The text colour at [alpha], composited the way Flutter draws it.
  double dimmedContrast(
    double alpha,
    ({bool dark, String name, Color color}) g,
  ) {
    final ink = schemeOf(dark: g.dark).onSurface.withValues(alpha: alpha);
    return _contrast(Color.alphaBlend(ink, g.color), g.color);
  }

  test('a ghost placeholder clears 4.5:1 on every note ground', () {
    for (final g in noteGrounds) {
      expect(
        dimmedContrast(MarkdownConstants.hintTextAlpha, g),
        greaterThanOrEqualTo(bodyContrast),
        reason: 'ghost on the ${g.name}',
      );
    }
  });

  test('the ink these tokens are computed from is the ink drawn', () {
    for (final dark in [false, true]) {
      final theme = dark ? AppTheme.dark() : AppTheme.light();
      final onSurface = schemeOf(dark: dark).onSurface;
      // The preview and the editor read bodyLarge; the money detail sheet
      // reads bodySmall.
      expect(theme.textTheme.bodyLarge?.color, onSurface, reason: '$dark');
      expect(theme.textTheme.bodySmall?.color, onSurface, reason: '$dark');
    }
  });

  test('a running-balance echo, as the preview draws it, clears 4.5:1', () {
    const row = r'$- 40 lunch';
    for (final g in noteGrounds) {
      final builder = LineBasedMarkdownBuilder(
        style: LineMarkdownStyle.fromTheme(
          g.dark ? AppTheme.dark() : AppTheme.light(),
          16,
        ),
        colorPalette: MarkdownColorPalette.presets,
        moneyConfig: const MoneyDisplayConfig(enabled: true),
      );
      addTearDown(builder.dispose);
      builder.prepare('\$= 500 budget\n$row');
      TextSpan? echo;
      builder.buildLine(row, 1).visitChildren((span) {
        if (span is TextSpan && (span.text?.contains('=') ?? false)) {
          echo = span;
        }
        return echo == null;
      });
      final ink = echo!.style!.color!;
      expect(
        _contrast(Color.alphaBlend(ink, g.color), g.color),
        greaterThanOrEqualTo(bodyContrast),
        reason: 'the derived balance beside a typed amount on the ${g.name}',
      );
    }
  });

  test('the detail sheet\'s running balance clears 4.5:1 on the sheet', () {
    for (final dark in [false, true]) {
      final theme = dark ? AppTheme.dark() : AppTheme.light();
      final sheet = schemeOf(dark: dark).surfaceContainerLow;
      final ink = theme.textTheme.bodySmall!.color!.withValues(
        alpha: MarkdownConstants.hintTextAlpha,
      );
      expect(
        _contrast(Color.alphaBlend(ink, sheet), sheet),
        greaterThanOrEqualTo(bodyContrast),
        reason: dark ? 'dark sheet' : 'light sheet',
      );
    }
  });

  test('a revealed syntax marker clears 4.5:1 on every note ground', () {
    for (final g in noteGrounds) {
      expect(
        dimmedContrast(MarkdownConstants.syntaxMarkerAlpha, g),
        greaterThanOrEqualTo(bodyContrast),
        reason: 'marker on the ${g.name}',
      );
    }
  });

  test('every money ink clears 4.5:1 on its grounds and on its chip', () {
    for (final g in noteGrounds) {
      final inks = <String, Color>{
        'positive': MarkdownConstants.moneyPositive(dark: g.dark),
        'negative': MarkdownConstants.moneyNegative(dark: g.dark),
        'neutral': MarkdownConstants.moneyNeutral(dark: g.dark),
        'warning': MarkdownConstants.moneyWarning(dark: g.dark),
      };
      for (final ink in inks.entries) {
        expect(
          _contrast(ink.value, g.color),
          greaterThanOrEqualTo(bodyContrast),
          reason: '${ink.key} on the ${g.name}',
        );
        final chip = Color.alphaBlend(
          ink.value.withValues(
            alpha: MarkdownConstants.editorChipBackgroundAlpha,
          ),
          g.color,
        );
        expect(
          _contrast(ink.value, chip),
          greaterThanOrEqualTo(bodyContrast),
          reason: '${ink.key} on its chip over the ${g.name}',
        );
      }
      // The preview's tint under an accent: 0.10 light, 0.16 dark.
      for (final ink in inks.entries) {
        final tint = Color.alphaBlend(
          ink.value.withValues(alpha: g.dark ? 0.16 : 0.10),
          g.color,
        );
        expect(
          _contrast(ink.value, tint),
          greaterThanOrEqualTo(bodyContrast),
          reason: '${ink.key} on the preview tint over the ${g.name}',
        );
      }
      // An error row's source sits on the warning ink's 0.10 tint.
      final warn = inks['warning']!;
      final errorTint = Color.alphaBlend(warn.withValues(alpha: 0.1), g.color);
      expect(
        _contrast(warn, errorTint),
        greaterThanOrEqualTo(bodyContrast),
        reason: 'warning on the error-row tint over the ${g.name}',
      );
    }
  });

  test('a done task\'s dimmed text clears 4.5:1 on every note ground', () {
    for (final g in noteGrounds) {
      expect(
        dimmedContrast(MarkdownConstants.checkedTextOpacity, g),
        greaterThanOrEqualTo(bodyContrast),
        reason: g.name,
      );
    }
  });

  test('typed text outranks hints, and hints outrank markers', () {
    for (final g in noteGrounds) {
      final typed = dimmedContrast(1.0, g);
      final hint = dimmedContrast(MarkdownConstants.hintTextAlpha, g);
      final marker = dimmedContrast(MarkdownConstants.syntaxMarkerAlpha, g);
      expect(typed, greaterThan(hint), reason: 'typed > hint on ${g.name}');
      expect(hint, greaterThan(marker), reason: 'hint > marker on ${g.name}');
    }
  });

  test('a colour that already reads is used verbatim', () {
    final palette = MarkdownColorPalette.decode('signal=ff8b0000');
    final spec = palette.lookup('signal')!;
    expect(spec.lightText, const Color(0xFF8B0000));
  });
}
