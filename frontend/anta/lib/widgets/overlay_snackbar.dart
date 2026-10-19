import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../constants/form_metrics.dart';
import '../l10n/app_localizations.dart';

/// A message raised in the navigator's overlay rather than in a `Scaffold`:
/// the one way a confirmation shows above a modal sheet, and the one way a
/// bar keeps clearing the keyboard on a page that lays itself out around it.
///
/// `ScaffoldMessenger` hands a `SnackBar` to the page's `Scaffold`, and a
/// modal bottom sheet is a route above that page, so a bar raised while a
/// sheet is up is drawn under the sheet ("Template saved" after the editor's
/// Save as template, the Tier 2 device pass). An overlay entry inserted now
/// sits above every route of the moment. The shortcut editor's form errors
/// take the same road, over its docked toolbar.
///
/// The second reason is the keyboard. A `SnackBar` is laid out once, with a
/// fixed `margin`; a page whose `Scaffold` does not resize for the IME (the
/// note editor and the calendar page pad their own bodies) gets no lift from
/// the Scaffold, and a lift baked into the margin at show time stays where it
/// was when the keyboard goes down — a bar stranded mid-screen, which the
/// owner saw after "1 long line was formatted". This body reads the insets in
/// `build`, so it rides the keyboard up and down for as long as it shows.
///
/// The entry's widget owns the timer that takes it down, so a message still
/// up when the tree goes away leaves no timer behind — a widget test that
/// ends on a fresh confirmation would otherwise fail on it — and a message
/// raised over an earlier one cannot be cut short by the earlier one's timer.
///
/// Its look is `ThemeData.snackBarTheme`, the one the Scaffold's bars inherit,
/// so a message reads the same whichever road it took.
class OverlaySnackbar {
  static _ShownMessage? _current;

  /// The default distance from the cleared bottom edge for a message raised
  /// over a sheet: above a short sheet's header row.
  static const double sheetBottomOffset = 80;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    double bottomOffset = sheetBottomOffset,
  }) {
    showContent(
      context,
      content: Text(message),
      duration: duration,
      bottomOffset: bottomOffset,
    );
  }

  /// Raises [content] the way [show] raises a message: [bottomOffset] above
  /// whichever of the keyboard and the system bars is taller at the moment of
  /// every build, with the close button unless [showCloseIcon] is false.
  static void showContent(
    BuildContext context, {
    required Widget content,
    required Duration duration,
    double bottomOffset = sheetBottomOffset,
    bool showCloseIcon = true,
  }) {
    hide();

    late final _ShownMessage shown;
    shown = _ShownMessage(
      OverlayEntry(
        builder: (context) => OverlaySnackbarBody(
          content: content,
          duration: duration,
          bottomOffset: bottomOffset,
          showCloseIcon: showCloseIcon,
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

/// The bar [OverlaySnackbar] draws. Public so a test can find the bar a
/// non-resizing page raised by type, as it finds a `SnackBar` elsewhere.
class OverlaySnackbarBody extends StatefulWidget {
  final Widget content;
  final Duration duration;
  final double bottomOffset;
  final bool showCloseIcon;
  final VoidCallback onDismiss;

  const OverlaySnackbarBody({
    super.key,
    required this.content,
    required this.duration,
    required this.bottomOffset,
    required this.onDismiss,
    this.showCloseIcon = true,
  });

  @override
  State<OverlaySnackbarBody> createState() => _OverlaySnackbarBodyState();
}

class _OverlaySnackbarBodyState extends State<OverlaySnackbarBody> {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final barTheme = theme.snackBarTheme;
    final shape = barTheme.shape;
    final borderRadius =
        shape is RoundedRectangleBorder && shape.borderRadius is BorderRadius
        ? shape.borderRadius as BorderRadius
        : BorderRadius.circular(FormMetrics.menuRadius);
    final side = shape is RoundedRectangleBorder
        ? shape.side
        : BorderSide(color: colorScheme.outlineVariant);
    final textStyle =
        barTheme.contentTextStyle ??
        TextStyle(
          color: colorScheme.onSurface,
          fontSize: AppTheme.menuLabelSize,
        );
    // The overlay sits in a full-bleed route that applies no system inset,
    // so the bar clears the taller of the keyboard and the navigation bar
    // itself — the clearance rule every overlay of this app follows. Read
    // here, in build, the insets re-anchor the bar on every keyboard move.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final padding = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned(
      bottom: math.max(insets, padding) + widget.bottomOffset,
      left: 16,
      right: 16,
      // A live region, as a `SnackBar` is: a screen reader announces the
      // message when it appears instead of needing to find it.
      child: Semantics(
        container: true,
        liveRegion: true,
        // Only the text and the close button take a tap; the rest of the
        // box lets it through to what lies under. The box sits over whatever
        // is near the bottom of the screen — a short sheet's header ✕ lay
        // under its top edge on the device pass, dead for as long as it
        // showed. Hence a transparency over a [PhysicalModel]: a coloured
        // [Material] absorbs every hit inside its box.
        //
        // The hairline is the transparency's shape: it paints on a foreground
        // layer that takes no hit, where a `DecoratedBox` would hit-test its
        // whole box and absorb the strip again.
        child: Material(
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(borderRadius: borderRadius, side: side),
          child: PhysicalModel(
            elevation: barTheme.elevation ?? AppTheme.menuElevation,
            borderRadius: borderRadius,
            color: barTheme.backgroundColor ?? colorScheme.menuSurface,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                top: 14,
                bottom: 14,
                right: widget.showCloseIcon ? 8 : 16,
              ),
              child: Row(
                children: [
                  // A replace, as `SnackBar` does with its content: a merge
                  // into the Material's bodyMedium drew a taller line.
                  Expanded(
                    child: DefaultTextStyle(
                      style: textStyle,
                      child: widget.content,
                    ),
                  ),
                  if (widget.showCloseIcon)
                    // Its own ink layer, painted above the model's colour.
                    Material(
                      type: MaterialType.transparency,
                      child: IconButton(
                        icon: Icon(
                          Icons.close,
                          color:
                              barTheme.closeIconColor ??
                              colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        // The app always provides its localizations; a bare
                        // MaterialApp (a host in a widget test) falls back to
                        // Material's own close tooltip instead of throwing.
                        tooltip:
                            AppLocalizations.of(context)?.close ??
                            MaterialLocalizations.of(context).closeButtonTooltip,
                        onPressed: widget.onDismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
