import 'package:flutter/material.dart';

/// The app's palette, declared token by token rather than derived from a seed.
///
/// These are the Material 3 **baseline** roles — the ones the approved
/// navigation mock is drawn in. `ColorScheme.fromSeed` cannot reproduce them:
/// its tonal-spot algorithm desaturates whatever it is handed, so
/// `deepPurple` lands on `#68548E` and even seeding with `#6750A4` itself
/// lands on `#65558F`. Nothing here is generated, so nothing here moves when
/// the framework retunes its harmonisation.
abstract final class AppTheme {
  /// The baseline light scheme, exactly as the mock's CSS declares it.
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF6750A4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEADDFF),
    onPrimaryContainer: Color(0xFF21005D),
    primaryFixed: Color(0xFFEADDFF),
    primaryFixedDim: Color(0xFFD0BCFF),
    onPrimaryFixed: Color(0xFF21005D),
    onPrimaryFixedVariant: Color(0xFF4F378B),
    secondary: Color(0xFF625B71),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE8DEF8),
    onSecondaryContainer: Color(0xFF1D192B),
    secondaryFixed: Color(0xFFE8DEF8),
    secondaryFixedDim: Color(0xFFCCC2DC),
    onSecondaryFixed: Color(0xFF1D192B),
    onSecondaryFixedVariant: Color(0xFF4A4458),
    tertiary: Color(0xFF7D5260),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8E4),
    onTertiaryContainer: Color(0xFF31111D),
    tertiaryFixed: Color(0xFFFFD8E4),
    tertiaryFixedDim: Color(0xFFEFB8C8),
    onTertiaryFixed: Color(0xFF31111D),
    onTertiaryFixedVariant: Color(0xFF633B48),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFEF7FF),
    onSurface: Color(0xFF1D1B20),
    surfaceDim: Color(0xFFDED8E1),
    surfaceBright: Color(0xFFFEF7FF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F2FA),
    surfaceContainer: Color(0xFFF3EDF7),
    surfaceContainerHigh: Color(0xFFECE6F0),
    surfaceContainerHighest: Color(0xFFE6E0E9),
    onSurfaceVariant: Color(0xFF49454F),
    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC4D0),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF322F35),
    onInverseSurface: Color(0xFFF5EFF7),
    inversePrimary: Color(0xFFD0BCFF),
    surfaceTint: Color(0xFF6750A4),
  );

  /// The baseline dark scheme. The fixed roles are shared with [lightScheme]
  /// by definition — that is what "fixed" means in Material 3.
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFD0BCFF),
    onPrimary: Color(0xFF381E72),
    primaryContainer: Color(0xFF4F378B),
    onPrimaryContainer: Color(0xFFEADDFF),
    primaryFixed: Color(0xFFEADDFF),
    primaryFixedDim: Color(0xFFD0BCFF),
    onPrimaryFixed: Color(0xFF21005D),
    onPrimaryFixedVariant: Color(0xFF4F378B),
    secondary: Color(0xFFCCC2DC),
    onSecondary: Color(0xFF332D41),
    secondaryContainer: Color(0xFF4A4458),
    onSecondaryContainer: Color(0xFFE8DEF8),
    secondaryFixed: Color(0xFFE8DEF8),
    secondaryFixedDim: Color(0xFFCCC2DC),
    onSecondaryFixed: Color(0xFF1D192B),
    onSecondaryFixedVariant: Color(0xFF4A4458),
    tertiary: Color(0xFFEFB8C8),
    onTertiary: Color(0xFF492532),
    tertiaryContainer: Color(0xFF633B48),
    onTertiaryContainer: Color(0xFFFFD8E4),
    tertiaryFixed: Color(0xFFFFD8E4),
    tertiaryFixedDim: Color(0xFFEFB8C8),
    onTertiaryFixed: Color(0xFF31111D),
    onTertiaryFixedVariant: Color(0xFF633B48),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF141218),
    onSurface: Color(0xFFE6E0E9),
    surfaceDim: Color(0xFF141218),
    surfaceBright: Color(0xFF3B383E),
    surfaceContainerLowest: Color(0xFF0F0D13),
    surfaceContainerLow: Color(0xFF1D1B20),
    surfaceContainer: Color(0xFF211F26),
    surfaceContainerHigh: Color(0xFF2B2930),
    surfaceContainerHighest: Color(0xFF36343B),
    onSurfaceVariant: Color(0xFFCAC4D0),
    outline: Color(0xFF938F99),
    outlineVariant: Color(0xFF49454F),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE6E0E9),
    onInverseSurface: Color(0xFF322F35),
    inversePrimary: Color(0xFF6750A4),
    surfaceTint: Color(0xFFD0BCFF),
  );

  /// Menu geometry the mock draws: 236 wide, 44 dp rows, a 15/400 label and
  /// a 20 px glyph in `onSurfaceVariant`. Declared on the theme so both
  /// overflow menus and the ancestor `showMenu` cannot drift apart.
  static const double menuWidth = 236.0;
  static const double menuItemHeight = 44.0;
  static const double menuIconSize = 20.0;
  static const double menuLabelSize = 15.0;
  static const double menuTrailingSize = 13.0;
  static const double menuDividerHeight = 13.0;
  static const double menuVerticalPadding = 6.0;

  /// Vertical breathing room around the editor toolbar's 40 dp button row,
  /// which puts the bar at the mock's 46 dp. Read by the markdown bar and
  /// by the vocabulary bar that swaps in for it — the two must stay the
  /// same height or the swap shifts the editor mid-word.
  static const double editorBarVerticalPadding = 3.0;

  /// The editor toolbar's ground: `surface` under a hairline, never a
  /// shadow. A 10 % black drop shadow is invisible on a dark ground, which
  /// is what left the toolbar unseparated from the body in dark mode.
  static BoxDecoration editorBarDecoration(ColorScheme scheme) {
    return BoxDecoration(
      color: scheme.surface,
      border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
    );
  }

  static final ThemeData _light = _themeFor(lightScheme);
  static final ThemeData _dark = _themeFor(darkScheme);

  /// The light theme `MaterialApp` is handed.
  ///
  /// One instance for the process: `MaterialApp` is rebuilt on every settings
  /// emission and a fresh `ThemeData` there invalidates every theme-keyed
  /// cache below it, the editor's render context included.
  static ThemeData light() => _light;

  /// The dark theme `MaterialApp` is handed.
  static ThemeData dark() => _dark;

  /// `scaffoldBackgroundColor` is deliberately left at its default (`surface`):
  /// the settings pages paint `surfaceContainer` cards onto it and the editor
  /// body is `surface` in the mock, so the browser's darker ground is a
  /// per-page decision made through `SurfaceRoles.pageGround`, not a global
  /// one.
  static ThemeData _themeFor(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        menuPadding: const EdgeInsets.symmetric(vertical: menuVerticalPadding),
        // Material 3 reads `labelTextStyle`; `textStyle` is the Material 2
        // slot and is never consulted under `useMaterial3`.
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            fontSize: menuLabelSize,
            fontWeight: FontWeight.w400,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
