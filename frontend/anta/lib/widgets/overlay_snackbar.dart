import 'dart:async';

import 'package:flutter/material.dart';

/// A message raised in the navigator's overlay rather than in a `Scaffold`:
/// the one way a confirmation shows above a modal sheet.
///
/// `ScaffoldMessenger` hands a `SnackBar` to the page's `Scaffold`, and a
/// modal bottom sheet is a route above that page, so a bar raised while a
/// sheet is up is drawn under the sheet ("Template saved" after the editor's
/// Save as template, the Tier 2 device pass). An overlay entry inserted now
/// sits above every route of the moment. The shortcut editor's form errors
/// take the same road, over its docked toolbar.
///
/// The entry's widget owns the timer that takes it down, so a message still
/// up when the tree goes away leaves no timer behind — a widget test that
/// ends on a fresh confirmation would otherwise fail on it — and a message
/// raised over an earlier one cannot be cut short by the earlier one's timer.
class OverlaySnackbar {
  static _ShownMessage? _current;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    double bottomOffset = 80,
  }) {
    hide();

    late final _ShownMessage shown;
    shown = _ShownMessage(
      OverlayEntry(
        builder: (context) => _OverlaySnackbarBody(
          message: message,
          duration: duration,
          bottomOffset: bottomOffset,
          onDismiss: () => _remove(shown),
        ),
      ),
    );
    _current = shown;
    Overlay.of(context).insert(shown.entry);
  }

  static void hide() {
    final shown = _current;
    if (shown == null) return;
    _remove(shown);
  }

  /// Takes a message down once, whichever of its timer, its close button and
  /// [hide] asks first: an entry removed twice is a framework assertion.
  static void _remove(_ShownMessage shown) {
    if (shown.removed) return;
    shown.removed = true;
    if (identical(_current, shown)) _current = null;
    shown.entry.remove();
    shown.entry.dispose();
  }
}

class _ShownMessage {
  final OverlayEntry entry;
  bool removed = false;

  _ShownMessage(this.entry);
}

class _OverlaySnackbarBody extends StatefulWidget {
  final String message;
  final Duration duration;
  final double bottomOffset;
  final VoidCallback onDismiss;

  const _OverlaySnackbarBody({
    required this.message,
    required this.duration,
    required this.bottomOffset,
    required this.onDismiss,
  });

  @override
  State<_OverlaySnackbarBody> createState() => _OverlaySnackbarBodyState();
}

class _OverlaySnackbarBodyState extends State<_OverlaySnackbarBody> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      bottom: MediaQuery.viewInsetsOf(context).bottom + widget.bottomOffset,
      left: 16,
      right: 16,
      // A live region, as a `SnackBar` is: a screen reader announces the
      // message when it appears instead of needing to find it.
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(4),
          color: colorScheme.inverseSurface,
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
                    widget.message,
                    style: TextStyle(
                      color: colorScheme.onInverseSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: colorScheme.onInverseSurface,
                    size: 20,
                  ),
                  onPressed: widget.onDismiss,
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
  }
}
