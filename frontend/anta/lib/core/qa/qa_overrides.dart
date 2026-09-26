import 'package:flutter/widgets.dart';

import 'qa_mode.dart';

/// Run-time knobs the QA agent turns on a driver build, so a device pass can
/// walk the accessibility matrix (text scale, and through the settings bloc
/// locale and theme) without a rebuild or a relaunch.
///
/// Only [QaTextScale] reads these, and `main.dart` mounts it only when
/// [QaMode.enabled] — a normal build never instantiates the notifier.
abstract final class QaOverrides {
  /// A text scale factor to impose over the platform's, or `null` for none.
  static final ValueNotifier<double?> textScale = ValueNotifier<double?>(
    QaMode.initialTextScale,
  );
}

/// Applies [QaOverrides.textScale] over the platform's text scale for the
/// whole subtree — mounted by `MaterialApp.builder` in a QA build.
class QaTextScale extends StatelessWidget {
  const QaTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: QaOverrides.textScale,
      builder: (context, scale, _) {
        if (scale == null) return child;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child,
        );
      },
    );
  }
}
