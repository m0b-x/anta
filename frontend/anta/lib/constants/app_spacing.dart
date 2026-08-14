import 'package:flutter/material.dart';

/// Centralized spacing and padding constants
class AppSpacing {
  // Base spacing values
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 32.0;

  // Common EdgeInsets patterns
  static const EdgeInsets zero = EdgeInsets.zero;

  // All sides
  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);
  static const EdgeInsets allXl = EdgeInsets.all(xl);
  static const EdgeInsets allXxl = EdgeInsets.all(xxl);

  // Symmetric
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);

  // Common combinations
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: sm,
  );
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: sm,
  );
  static const EdgeInsets dialogPadding = EdgeInsets.all(lg);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: md,
  );
  static const EdgeInsets listItemMargin = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: sm,
  );
  static const EdgeInsets dialogContentPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: xs,
  );
  static const EdgeInsets toolbarPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: md,
  );

  // Bottom sheet
  static const EdgeInsets bottomSheetPadding = EdgeInsets.all(lg);
  static const EdgeInsets bottomSheetItemPadding = EdgeInsets.symmetric(
    vertical: md,
  );

  // Specific use cases
  static const EdgeInsets checkboxPadding = EdgeInsets.only(
    right: sm,
    top: xxs,
  );
  static const EdgeInsets iconPadding = EdgeInsets.only(right: sm);

  // Toolbar offset for snackbars
  static const double toolbarOffset = 70.0;
  static EdgeInsets snackbarMargin({bool withToolbarOffset = false}) {
    return EdgeInsets.only(
      left: lg,
      right: lg,
      bottom: withToolbarOffset ? toolbarOffset : lg,
    );
  }
}
