import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/models/item_label.dart';

/// The seven label hues are graphics, not text: a 10 dp dot and, in the
/// stripe style, a 3 dp bar on the row surface. WCAG's floor for that is
/// 3:1, and the light-mode yellow and orange were below it (1.9:1 and
/// 2.5:1) until 2026-09-13. The ratio is computed here rather than pinned
/// as hex so a palette tune-up stays free as long as it clears the floor.
void main() {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color color) =>
      0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);

  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  const floor = 3.0;

  test('every light hue clears 3:1 on the light row surface', () {
    final surface = AppTheme.lightScheme.rowGroup;
    for (final label in ItemLabel.assignable) {
      final ratio = contrast(
        AppColors.labelColor(label, Brightness.light),
        surface,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(floor),
        reason:
            '${label.name} reads ${ratio.toStringAsFixed(2)}:1 on a light row',
      );
    }
  });

  test('every dark hue clears 3:1 on the dark row surface', () {
    final surface = AppTheme.darkScheme.rowGroup;
    for (final label in ItemLabel.assignable) {
      final ratio = contrast(
        AppColors.labelColor(label, Brightness.dark),
        surface,
      );
      expect(
        ratio,
        greaterThanOrEqualTo(floor),
        reason:
            '${label.name} reads ${ratio.toStringAsFixed(2)}:1 on a dark row',
      );
    }
  });
}
