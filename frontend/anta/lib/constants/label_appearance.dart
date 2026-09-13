import 'package:flutter/foundation.dart';

import '../models/label_style.dart';

/// Synchronous, in-memory view over how labelled rows draw their colour,
/// populated by `LabelAppearanceService`.
///
/// Mirrors the `CalendarPalette` pattern: every browser row resolves the
/// style in O(1) with no `await` and no settings round trip per build, and
/// [style] is what lets a row already on screen repaint the moment the
/// setting changes under the settings page.
abstract final class LabelAppearance {
  /// The style every labelled row renders. Seeded from the store by
  /// `LabelAppearanceService.getInstance()` before the first browser frame,
  /// so the value here is the default only until that read lands.
  static final ValueNotifier<LabelStyle> style = ValueNotifier<LabelStyle>(
    LabelStyle.dot,
  );
}
