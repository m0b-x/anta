import 'package:flutter/material.dart';

class OverlaySnackbar {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    double bottomOffset = 80,
  }) {
    hide();

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + bottomOffset,
        left: 16,
        right: 16,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.inverseSurface,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              top: 14,
              bottom: 14,
              right: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    size: 20,
                  ),
                  onPressed: hide,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_currentEntry!);

    Future.delayed(duration, () {
      hide();
    });
  }

  static void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}
