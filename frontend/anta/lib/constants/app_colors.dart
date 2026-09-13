import 'package:flutter/material.dart';

import '../models/item_label.dart';

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

  /// The seven fixed label hues, light theme.
  ///
  /// Every hue clears 3:1 against the light row surface (`#FEF7FF`), the
  /// graphics-contrast floor a 3 dp stripe needs; yellow and orange are the
  /// two that had to be darkened for it (from `#D9B426` at 1.9:1 and
  /// `#E9862B` at 2.5:1), and they now sit where green and teal already were.
  static const Map<ItemLabel, Color> _labelLight = {
    ItemLabel.red: Color(0xFFD8434A),
    ItemLabel.orange: Color(0xFFD27318),
    ItemLabel.yellow: Color(0xFFA8890E),
    ItemLabel.green: Color(0xFF3E9B57),
    ItemLabel.teal: Color(0xFF1F9A9E),
    ItemLabel.blue: Color(0xFF3573E0),
    ItemLabel.pink: Color(0xFFD9508F),
  };

  /// The same seven, lifted for a dark ground.
  static const Map<ItemLabel, Color> _labelDark = {
    ItemLabel.red: Color(0xFFF26B70),
    ItemLabel.orange: Color(0xFFF5A455),
    ItemLabel.yellow: Color(0xFFE9CB4F),
    ItemLabel.green: Color(0xFF63C27E),
    ItemLabel.teal: Color(0xFF4BC3C6),
    ItemLabel.blue: Color(0xFF6EA6FF),
    ItemLabel.pink: Color(0xFFF07AB7),
  };

  /// The fill of a label dot, per theme.
  ///
  /// Fixed hex rather than scheme roles: a label is an identity the user
  /// assigns, and it has to read as the same colour in both themes and under
  /// any future palette change. [ItemLabel.none] has no colour — it draws
  /// nothing at all — so asking for one is a programming error.
  static Color labelColor(ItemLabel label, Brightness brightness) {
    assert(label != ItemLabel.none, 'ItemLabel.none has no colour');
    final table = brightness == Brightness.dark ? _labelDark : _labelLight;
    return table[label] ?? _labelLight[ItemLabel.red]!;
  }

  /// The hairline inside a label dot's edge. Ten percent of the opposite
  /// tone, which is what keeps yellow from dissolving into a light row.
  static Color labelRing(Brightness brightness) {
    return brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);
  }
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
