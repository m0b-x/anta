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

  /// Get note icon color based on current theme
  static Color noteIcon(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.blue.shade700
        : Colors.blue;
  }

  /// Check if current theme is dark mode
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// Get adaptive foreground color for FAB
  static Color fabForeground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  /// Get adaptive background color for FAB
  static Color fabBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.white;
  }

  // Static colors for common UI elements
  static const Color deleteAction = Colors.red;
  static const Color dragHandle = Colors.grey;
  static const Color noteIconStatic = Colors.blue;
  static const Color folderIconStatic = Colors.amber;
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
