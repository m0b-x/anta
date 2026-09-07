import 'package:flutter/material.dart';

/// Centralized color utilities for theme-aware colors
class AppColors {
  /// Get folder icon color based on current theme.
  ///
  /// Primary, not amber: the approved navigation mock carries exactly one
  /// accent, and a second hue on the folder glyph is the only thing that
  /// broke it.
  static Color folderIcon(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  /// Check if current theme is dark mode
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// The launch-failure screen, which paints before a [Theme] exists.
  static const Color deleteAction = Colors.red;
}

/// The browser's surface layering, named once so the two themes cannot drift
/// apart.
///
/// The rule the mock draws, and the one thing to remember: **the page ground
/// is one tone under the row groups, in both themes**. Light stacks `surface`
/// groups on a `surfaceContainer` ground; dark stacks `surfaceContainer`
/// groups on a `surface` ground. Reading the roles off the scheme in the same
/// order in both would invert one of them — light's `surface` is its
/// *lightest* tone, dark's is its *darkest*.
extension SurfaceRoles on ColorScheme {
  /// What a browser page paints behind its rows, and what its bars sit on.
  Color get pageGround =>
      brightness == Brightness.light ? surfaceContainer : surface;

  /// The rounded card a run of folder or note rows shares, and the browser's
  /// bottom bar.
  Color get rowGroup =>
      brightness == Brightness.light ? surface : surfaceContainer;

  /// The hairline between two rows of one group, and the line above the
  /// bottom bar. Opaque: an alpha over [rowGroup] would land on a different
  /// tone in each theme.
  Color get rowDivider => surfaceContainerHighest;

  /// Popup menus and the overlays that read as menus.
  Color get menuSurface => surfaceContainerHigh;
}
