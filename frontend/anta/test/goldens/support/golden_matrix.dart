import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';

/// One device a surface is drawn on: a theme, a language, a text scale and a
/// phone's logical size.
class GoldenCell {
  const GoldenCell({
    required this.dark,
    required this.locale,
    required this.textScale,
    required this.size,
  });

  final bool dark;
  final Locale locale;
  final double textScale;
  final Size size;

  ThemeData get theme => dark ? AppTheme.dark() : AppTheme.light();

  /// `light_en_1.0_360x780`: the part of a golden's file name the cell owns.
  String get label =>
      '${dark ? 'dark' : 'light'}_${locale.languageCode}_'
      '${textScale.toStringAsFixed(1)}_'
      '${size.width.toInt()}x${size.height.toInt()}';
}

/// The visual matrix (`docs/qa-pass-rework.md` decision H): the plain phone,
/// the hardest one — dark, the longest language, the largest text on the
/// small screen — and the large phone in the language with diacritics.
const goldenCells = [
  GoldenCell(
    dark: false,
    locale: Locale('en'),
    textScale: 1.0,
    size: Size(360, 780),
  ),
  GoldenCell(
    dark: true,
    locale: Locale('de'),
    textScale: 2.0,
    size: Size(360, 780),
  ),
  GoldenCell(
    dark: false,
    locale: Locale('ro'),
    textScale: 1.3,
    size: Size(412, 915),
  ),
];

/// The golden's path, relative to `test/goldens/`.
String goldenName(String surface, GoldenCell cell) =>
    'images/${surface}_${cell.label}.png';

/// Sizes the test view to [cell]'s phone at 1×, so the PNG has the cell's
/// logical size and stays small.
void setGoldenSurface(WidgetTester tester, GoldenCell cell) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = cell.size;
  addTearDown(tester.view.reset);
}

/// The app a surface is drawn in for [cell]: its theme, its language and its
/// text scale, without the debug banner a phone never shows.
MaterialApp goldenApp(
  GoldenCell cell, {
  required Widget home,
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: cell.theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: cell.locale,
    navigatorObservers: navigatorObservers,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(cell.textScale)),
      child: child!,
    ),
    home: home,
  );
}

/// Compares the whole app against [surface]'s golden for [cell].
Future<void> expectGolden(String surface, GoldenCell cell) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile(goldenName(surface, cell)),
);
