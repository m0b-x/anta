import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/main.dart';

/// U2.10 — the system bars follow the theme the app resolved, so the dark
/// theme never sits over a light navigation band.
void main() {
  Future<SystemUiOverlayStyle> pumpAndReadStyle(
    WidgetTester tester,
    ThemeMode mode,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        builder: (context, child) => AppSystemBars(child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    return tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          // The outermost region is the app's; a page's own sits below it.
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
        )
        .value;
  }

  testWidgets('the dark theme asks for light buttons and no scrim', (
    tester,
  ) async {
    final style = await pumpAndReadStyle(tester, ThemeMode.dark);

    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarColor, Colors.transparent);
  });

  testWidgets('the light theme asks for dark buttons and no scrim', (
    tester,
  ) async {
    final style = await pumpAndReadStyle(tester, ThemeMode.light);

    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarColor, Colors.transparent);
  });
}
