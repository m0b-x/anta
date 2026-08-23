import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/widgets/calendar_day_bars.dart';

/// The low-contrast outline exists so a pale custom colour stays visible on a
/// light cell. Judged by luminance **delta** it did the opposite: it fired on
/// six of the twelve built-in marker colours in dark mode — where every
/// saturated colour sits low on the luminance scale and is therefore "close
/// to" a near-black surface — and on none in light mode, which is the case it
/// was written for. A delta is not contrast; a ratio is.
///
/// These pin the direction: outlines appear where a marker would genuinely
/// vanish, and nowhere else.
void main() {
  /// The app's real schemes, from `main.dart`.
  final light = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
  final dark = ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  );

  Future<void> pumpBars(
    WidgetTester tester, {
    required ColorScheme scheme,
    required List<Color> colors,
    CalendarMarkerStyle style = CalendarMarkerStyle.bars,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 48,
              child: CalendarDayBars(
                style: style,
                bars: [
                  for (final (index, color) in colors.indexed)
                    DayBar(
                      key: 'bar:$index',
                      color: color,
                      priority: 0,
                      semanticLabel: 'x',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How many of the rendered markers carry an outline.
  int outlineCount(WidgetTester tester) {
    return tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => (c.decoration as BoxDecoration?)?.border != null)
        .length;
  }

  final builtIns = [
    for (final seed in CalendarCategories.builtInSeeds) Color(seed.colorValue),
  ];

  testWidgets('dark mode leaves saturated markers alone', (tester) async {
    // The regression: six of these were outlined under the luminance-delta
    // test. Every one of them clears 2:1 against a near-black surface.
    await pumpBars(tester, scheme: dark, colors: builtIns);

    expect(outlineCount(tester), 0);
  });

  testWidgets('light mode leaves saturated markers alone too', (tester) async {
    await pumpBars(tester, scheme: light, colors: builtIns);

    expect(outlineCount(tester), 0);
  });

  testWidgets('a pale marker on a light cell still gets its outline', (
    tester,
  ) async {
    // The case the feature exists for: yellow 100 on white is 1.05:1 — not a
    // marker, just a faint smudge — so it keeps the hairline.
    await pumpBars(tester, scheme: light, colors: const [Color(0xFFFFF9C4)]);

    expect(outlineCount(tester), 1);
  });

  testWidgets('a near-black marker on a dark cell gets one', (tester) async {
    // The dark-mode mirror of the same problem, which the delta test could
    // never distinguish from an ordinary saturated colour.
    await pumpBars(tester, scheme: dark, colors: const [Color(0xFF141414)]);

    expect(outlineCount(tester), 1);
  });

  testWidgets('the outline is a full pixel, centred, never inset', (
    tester,
  ) async {
    // Half a logical pixel is half a *device* pixel at dpr 1.0, which paints
    // as a grey smear instead of a line; inset, it also ate a third of a 3px
    // bar's fill. Centred keeps the fill and stays inside the 1.5px gap.
    await pumpBars(tester, scheme: light, colors: const [Color(0xFFFFF9C4)]);

    final decorated = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration as BoxDecoration?)
        .firstWhere((d) => d?.border != null)!;
    final side = decorated.border!.top;

    expect(side.width, 1.0);
    expect(side.strokeAlign, BorderSide.strokeAlignCenter);
  });

  // One theme per test: `MaterialApp` animates a theme change through
  // `AnimatedTheme`, so re-pumping into the other brightness inside a single
  // test would read an interpolated surface and judge contrast against a
  // colour the user never sees.
  testWidgets('dots leave saturated markers alone in dark mode', (
    tester,
  ) async {
    await pumpBars(
      tester,
      scheme: dark,
      colors: builtIns,
      style: CalendarMarkerStyle.dots,
    );

    expect(outlineCount(tester), 0);
  });

  testWidgets('a pale dot on a light cell still gets its outline', (
    tester,
  ) async {
    await pumpBars(
      tester,
      scheme: light,
      colors: const [Color(0xFFFFF9C4)],
      style: CalendarMarkerStyle.dots,
    );

    expect(outlineCount(tester), 1);
  });
}
