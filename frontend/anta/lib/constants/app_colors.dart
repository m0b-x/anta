import 'package:flutter/material.dart';

/// Centralized color utilities for theme-aware colors
class AppColors {
  /// Get folder icon color based on current theme
  static Color folderIcon(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.amber.shade700
        : Colors.amber;
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
