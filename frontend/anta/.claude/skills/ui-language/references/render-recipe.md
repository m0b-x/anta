# Render recipe — see a widget with real fonts without a device

Reference, not rules (added 2026-10-21). A widget test renders with the Ahem box font, so its goldens show nothing about hierarchy or size. Loading Roboto and MaterialIcons from the Flutter SDK cache into the test turns `matchesGoldenFile` into a screenshot of the real widget in the real theme, at phone width, in seconds — the designer's first step before judging a surface, and the cheapest way to compare before/after a restyle. The emulator (`qa screenshot`) stays the truth for keyboard, scrolling and a real note behind a bar.

## Recipe

1. Write `test/zz_scratch_<surface>_test.dart` (never committed; delete it and `test/scratch_goldens/` before reporting):

```dart
const _fontDir =
    '<flutter sdk>/bin/cache/artifacts/material_fonts'; // `dirname $(which flutter)`/cache/…

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf',
      'roboto-bold.ttf', 'roboto-italic.ttf', 'roboto-bolditalic.ttf']) {
    final file = File('$_fontDir/$name');
    if (file.existsSync()) {
      roboto.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(
        File('$_fontDir/materialicons-regular.otf').readAsBytesSync().buffer)));
  await icons.load();
}

testWidgets('render light 1.0', (tester) async {
  await _loadFonts();
  tester.view.physicalSize = const Size(360 * 3, 300 * 3); // phone width, dpr 3
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(), // AppTheme.dark() for the other half
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
      child: child!,
    ),
    home: Scaffold(body: /* the real widget, in every state under review */),
  ));
  await tester.pumpAndSettle();
  await expectLater(find.byType(Scaffold),
      matchesGoldenFile('scratch_goldens/<surface>_light_1.0.png'));
});
```

2. `flutter test --update-goldens test/zz_scratch_<surface>_test.dart` writes the PNGs (one `flutter test` at a time, never beside a QA run).
3. Read each PNG with the Read tool; it is an image. Loop over light/dark and 1.0 / 1.3 / 2.0 in the test so one run gives the matrix.
4. Measure with `tester.getSize(find…)` / `getRect` inside the same test when a number matters (a row height, a label's box).

## Traps

- The fonts must be loaded inside the test body (`await _loadFonts()`), before `pumpWidget`; a `setUpAll` works too.
- Keep the physical size tall enough for every state you stack, or the golden clips; a `Column` overflow is reported by `tester.takeException()`.
- Widgets that need controllers (`MarkdownBar` needs a `VocabularySuggestionController` over a `CodeLineEditingController`) are seeded the way their widget test seeds them — copy that suite's pump helper rather than inventing a fixture.
- Shadows and ink splashes render; a pressed state needs `tester.press` + `pump` before the golden.
- The PNGs are dpr 3: a 40 px row is 120 px tall in the file.
