import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The system bars over every page, keyed on the theme the app resolved
/// rather than the phone's: under the dark theme the navigation band would
/// otherwise keep the launch style's dark buttons over a light scrim (U2.10).
/// A page with its own region (an app bar's status bar, the ring screen's
/// ground) still wins where it is drawn.
class AppSystemBars extends StatelessWidget {
  /// Wraps [child], the app's navigator.
  const AppSystemBars({super.key, required this.child});

  /// The app's navigator.
  final Widget child;

  /// The style over a ground of [brightness]: transparent bars, buttons in
  /// the opposite brightness, and no contrast scrim, which Android paints as
  /// a light band under the dark theme.
  static SystemUiOverlayStyle over(Brightness brightness) {
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS names the bar's background, not its icons.
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: over(Theme.of(context).brightness),
      child: child,
    );
  }
}
