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

## What the render can and cannot show (verified 2026-10-21, `design-practices.md` §9)

- **Fonts.** Load them inside the test body (`await _loadFonts()`) or a `setUpAll`, before the first pump, under the exact family names `Roboto` and `MaterialIcons`; anything unregistered renders in the FlutterTest box font (ascent 0.75 em / descent 0.25 em), which shifts every baseline. Emoji, Noto fallbacks and ro diacritics outside Roboto's coverage are not in the SDK cache — judge glyph coverage on the device. The device resolves Roboto through the system font manager (variable axes since 3.41), so line metrics may differ by a pixel: specs carry ±1 dp tolerances. A text style with **no `fontFamily`** stays in the box font even with Roboto loaded — `popupMenuTheme.labelTextStyle` is one, so every `showMenu` / `showFormMenu` / `showFormMenuAbove` row renders as squares and fills its menu to the 280 cap (the heading menu's "280 wide" of 2026-10-22); for the render, copy the theme with that style's family set to `Roboto` and change nothing else. On the phone the null family resolves to Roboto, so this is a test artefact only.
- **Shadows are off.** `AutomatedTestWidgetsFlutterBinding` sets `debugDisableShadows = true`: cards, menus and elevated chips render flat. Never judge depth or elevation from a render; ink splashes do render (`tester.press` + `pump` before the golden; force a ripple with debug colours when it must be visible).
- **Text scale.** `TextScaler.linear(x)` is linear; Android 14+ scales non-linearly (AOSP 200 % table: 8→16, 11→22, 14→26, 16→28, 22→35, 100→100). For device parity at 2.0 implement a `TextScaler` subclass over that table (copy the full lookup from AOSP `frameworks/base/core/java/android/content/res/FontScaleConverterFactory.java`, interpolating between entries as it does) and pass it as `textScaler:`; a surface's own `withClampedTextScaling` still applies inside the render.
- **Keyboard and system bars.** `tester.view.viewInsets = const FakeViewPadding(bottom: …)` (physical px; the IME is ≈300–350 dp on a Pixel 9 Pro) and `viewPadding` for gesture vs 3-button navigation; `physicalSize` 360 × 780 logical at dpr 3 is the phone cell, the default view is 800 × 600.
- **Platform.** `defaultTargetPlatform` is android under `flutter test` whatever the host; override it for a desktop render and set `FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional` before requesting focus to see a focus ring.
- **Motion** is invisible in one frame: pump fixed intervals and golden each frame, or assert the controller's duration and curve against `Durations` / `Easing`.
- **Controllers.** A widget that needs them (`MarkdownBar` needs a `VocabularySuggestionController` over a `CodeLineEditingController`) is seeded the way its own widget test seeds it — copy that suite's pump helper rather than inventing a fixture.
- **Size.** Keep the physical size tall enough for every state you stack, or the golden clips; a `Column` overflow is reported by `tester.takeException()`. `matchesGoldenFile(finder)` captures at **1x** whatever `devicePixelRatio` says (checked 2026-10-22): for a 3x PNG take `RenderRepaintBoundary.toImage(pixelRatio: 3)` on a `RepaintBoundary` around the surface and write the bytes yourself; then a 48 dp row is 144 px tall in the file.
- **Reading the PNG.** Claude Code resizes images to fit 2000 × 2000 px before sending, so a tall matrix loses pixel detail: crop with `magick in.png -crop WxH+X+Y +repage -filter point -resize 300% out.png` (ImageMagick 7.1.2 is `magick`; `convert` on Windows is the NTFS volume tool). Vision judges hierarchy and balance; numbers come from `tester.getRect` / `getSize`, `RenderParagraph` metrics and token values in the same test.
- **Failures.** When `matchesGoldenFile` fails, `LocalFileComparator` writes `masterImage`, `testImage`, `isolatedDiff` and `maskedDiff` PNGs under `failures/` — Read those instead of comparing two renders by eye.
- **Never commit** the scratch test or a golden: goldens differ across OS, Flutter version and renderer; they are local evidence. Delete `test/zz_scratch_*` and `test/scratch_goldens/` before reporting, and never run the scratch test beside the whole suite or a QA run.
