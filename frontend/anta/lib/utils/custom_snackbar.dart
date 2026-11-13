import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/snackbar_metrics.dart';
import '../widgets/automation_id.dart';
import '../widgets/overlay_snackbar.dart';

class CustomSnackbar {
  /// How long a prompt the user must read before acting on stays up — the
  /// editor's link confirm names the target: the most any action bar is
  /// given; an Undo keeps the shorter default.
  static const Duration confirmActionDuration =
      AppConstants.snackbarActionMaxDuration;

  /// Until when the bar with an action this helper last raised stands, its
  /// transitions counted; null once [hide] took it down. A bar nobody asked
  /// for — a share notice — waits this out rather than take down an Undo.
  static DateTime? get actionBarUntil => _actionBarUntil;
  static DateTime? _actionBarUntil;

  /// A test's tree goes away with its bar still standing on the wall clock.
  @visibleForTesting
  static void forgetActionBar() => _actionBarUntil = null;

  static void show(
    BuildContext context,
    String message, {
    Duration? duration,
    bool withToolbarOffset = false,
    bool overSheet = false,
  }) {
    _showSnackBar(
      context,
      content: Text(message),
      duration: duration ?? AppConstants.snackbarDuration,
      withToolbarOffset: withToolbarOffset,
      showCloseIcon: true,
      overSheet: overSheet,
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    bool withToolbarOffset = false,
  }) {
    show(
      context,
      message,
      duration: AppConstants.snackbarErrorDuration,
      withToolbarOffset: withToolbarOffset,
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    bool withToolbarOffset = false,
  }) {
    show(
      context,
      message,
      duration: AppConstants.snackbarSuccessDuration,
      withToolbarOffset: withToolbarOffset,
    );
  }

  static void showWithAction(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration? duration,
    bool withToolbarOffset = false,
    String? actionIdentifier,
    bool overSheet = false,
  }) {
    // Cap so an action prompt (e.g. Undo) never lingers indefinitely: a
    // duration past the max collapses down to it; a shorter one is honoured.
    final requested = duration ?? AppConstants.snackbarActionDefaultDuration;
    final capped = requested > AppConstants.snackbarActionMaxDuration
        ? AppConstants.snackbarActionMaxDuration
        : requested;
    // The page that raised the bar may have left by the time its action is
    // tapped — its context is then dead — while the messenger above every
    // route still holds the bar.
    final messenger = ScaffoldMessenger.maybeOf(context);

    // IMPORTANT: do NOT pass a [SnackBarAction] here. When Flutter sees a
    // non-null `SnackBar.action` AND `MediaQueryData.accessibleNavigation`
    // is true, it overrides `duration` with `Duration(days: 365)` so a
    // screen-reader user has time to act. Some platforms/host environments
    // (e.g. Windows with certain shells, some emulators) report accessible
    // navigation as true even without an active screen reader, causing
    // action snackbars to "last forever". Embedding the action button
    // inline in `content` avoids the override entirely while still
    // surfacing the action.
    _showSnackBar(
      context,
      content: _ActionContent(
        message: message,
        actionLabel: actionLabel,
        actionIdentifier: actionIdentifier,
        onAction: onAction,
        // A sheet's context may be gone by the time the action is tapped,
        // and the overlay's bar needs none to come down.
        dismiss: () {
          _actionBarUntil = null;
          OverlaySnackbar.hide();
          if (!overSheet) messenger?.hideCurrentSnackBar();
        },
      ),
      duration: capped,
      withToolbarOffset: withToolbarOffset,
      showCloseIcon: true,
      verticalPadding: SnackbarMetrics.actionBarVerticalPadding,
      overSheet: overSheet,
    );
    _actionBarUntil = DateTime.now().add(
      capped + AppConstants.snackbarTransitions,
    );
  }

  /// Takes down whatever bar is up, on either road: the overlay one a
  /// non-resizing page raised, and the Scaffold's.
  static void hide(BuildContext context) {
    _actionBarUntil = null;
    OverlaySnackbar.hide();
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  /// Raises [content] on one of two roads, both wearing `snackBarTheme`.
  ///
  /// A `SnackBar` is laid out by its `Scaffold` with a `margin` fixed at show
  /// time, and `_ScaffoldLayout` anchors a floating bar's bottom edge at
  /// `min(contentBottom, size.height - minViewPadding.bottom)`
  /// (`material/scaffold.dart:1238-1241`), where `contentBottom` is the only
  /// term that knows about the IME: it subtracts `minInsets.bottom`
  /// (`scaffold.dart:1088-1091`), which carries the keyboard inset **only**
  /// while `resizeToAvoidBottomInset` is true and is forced to zero otherwise
  /// (`scaffold.dart:3220-3222`). A page that manages the inset itself — the
  /// note editor pads its own body by it, so its toolbar rides the keyboard —
  /// therefore gets a bar anchored to the bottom of the screen, under the IME.
  /// Adding the keyboard's height to the margin once lifted it, but a margin
  /// cannot follow the keyboard down: the bar stayed a keyboard-height up in
  /// the middle of the screen after the IME closed ("1 long line was
  /// formatted", the owner's report of 2026-10-19). So on such a page the bar
  /// goes through [OverlaySnackbar], whose body reads the insets on every
  /// build and re-anchors itself; the Scaffold road stays for every page that
  /// resizes, where the Scaffold already keeps the bar above the keyboard.
  ///
  /// Safe-area padding needs no term of its own on either road: the Scaffold
  /// pulls a floating bar up by `minViewPadding.bottom`, and the overlay body
  /// clears `max(viewInsets, viewPadding)` itself, so both roads put a bar
  /// with no keyboard at the same height above the navigation bar.
  static void _showSnackBar(
    BuildContext context, {
    required Widget content,
    required Duration duration,
    required bool withToolbarOffset,
    bool showCloseIcon = false,
    double? verticalPadding,
    bool overSheet = false,
  }) {
    final margin = AppSpacing.snackbarMargin(
      withToolbarOffset: withToolbarOffset,
    );
    hide(context);
    // Raised from inside a modal sheet, the bar has to be the overlay's: the
    // Scaffold's would be drawn under the sheet.
    if (overSheet ||
        _hostScaffold(context)?.widget.resizeToAvoidBottomInset == false) {
      OverlaySnackbar.showContent(
        context,
        content: content,
        duration: duration,
        bottomOffset: overSheet
            ? OverlaySnackbar.sheetBottomOffset
            : margin.bottom,
        showCloseIcon: showCloseIcon,
        verticalPadding: verticalPadding ?? SnackbarMetrics.barVerticalPadding,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        behavior: SnackBarBehavior.floating,
        margin: margin,
        duration: duration,
        showCloseIcon: showCloseIcon,
        // A padding of our own also drops the 14 dp `SnackBar` keeps around
        // its content, which the action content restores around its text.
        padding: verticalPadding == null
            ? null
            : EdgeInsetsDirectional.only(
                start: SnackbarMetrics.barStartPadding,
                top: verticalPadding,
                bottom: verticalPadding,
              ),
      ),
    );
  }

  /// The [Scaffold] that will lay this bar out, looked up in both directions.
  ///
  /// [Scaffold.maybeOf] only walks up (`scaffold.dart:2090-2092`), which
  /// answers for callers inside the body — sheets, list rows, `Builder`s. This
  /// app's pages, though, call in from their `State.context`, which sits
  /// *above* the Scaffold their `build` returns, so the upward lookup alone
  /// would answer null for exactly the pages that need the overlay road. The
  /// downward walk stops at the first [ScaffoldState], a handful of elements
  /// below a page's own context. Finding no Scaffold at all keeps the
  /// Scaffold road — the bar keeps whatever position it has today.
  static ScaffoldState? _hostScaffold(BuildContext context) {
    final above = Scaffold.maybeOf(context);
    if (above != null) return above;

    ScaffoldState? below;
    void visit(Element element) {
      if (below != null) return;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is ScaffoldState) {
          below = state;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return below;
  }
}

/// Inline content for an action snackbar: a message text + a trailing
/// text button. Lives inside `SnackBar.content` (not `SnackBar.action`)
/// so Flutter doesn't apply its accessible-navigation duration override.
class _ActionContent extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  /// A `SemanticsIds` value on the action button for a device flow that
  /// waits for or taps it; its label is a translated word.
  final String? actionIdentifier;

  /// Takes the bar down on whichever road raised it; the confirming tap must
  /// not leave the bar lingering.
  final VoidCallback dismiss;

  const _ActionContent({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.dismiss,
    this.actionIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The bar wears the popup menu's surface, so the action is the accent a
    // menu would use on it: `primary` reads on `menuSurface` in both themes.
    final actionColor =
        theme.snackBarTheme.actionTextColor ?? theme.colorScheme.primary;

    Widget action = TextButton(
      onPressed: () {
        dismiss();
        onAction();
      },
      style: TextButton.styleFrom(
        foregroundColor: actionColor,
        padding: const EdgeInsets.symmetric(horizontal: _actionPadding),
        // A full touch target, in the label's own sentence case: the
        // 32 dp uppercase button was Material 2's.
        minimumSize: const Size(
          kMinInteractiveDimension,
          kMinInteractiveDimension,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Text(
        actionLabel,
        style: _actionStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (actionIdentifier case final id?) {
      action = AutomationId(identifier: id, child: action);
    }

    // The bar's own padding shrank around the 48 dp action; the text keeps
    // the usual distance from the bar's edges when it wraps.
    final text = Padding(
      padding: const EdgeInsets.symmetric(
        vertical:
            SnackbarMetrics.barVerticalPadding -
            SnackbarMetrics.actionBarVerticalPadding,
      ),
      child: Text(message),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_fitsBeside(context, constraints.maxWidth)) {
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: _gap),
              action,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            text,
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        );
      },
    );
  }

  static const _actionStyle = TextStyle(fontWeight: FontWeight.w600);
  static const double _actionPadding = 12;
  static const double _gap = 12;

  /// Whether the action fits beside a message that wraps without breaking a
  /// word, as `SnackBar` measures its own action's label to decide the same.
  /// When it does not — "Termin abgesagt" beside "Rückgängig" at text scale
  /// 2.0 on a 360 phone ran 61 px past the bar — the action takes its own
  /// line under the message, kept on one line.
  bool _fitsBeside(BuildContext context, double width) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final label = TextPainter(
      text: TextSpan(
        text: actionLabel,
        style: (theme.textTheme.labelLarge ?? const TextStyle()).merge(
          _actionStyle,
        ),
      ),
      textScaler: scaler,
      textDirection: direction,
      maxLines: 1,
    )..layout();
    final words = TextPainter(
      text: TextSpan(text: message, style: DefaultTextStyle.of(context).style),
      textScaler: scaler,
      textDirection: direction,
    )..layout();
    final actionWidth = math.max(
      label.width + 2 * _actionPadding,
      kMinInteractiveDimension,
    );
    final fits = words.minIntrinsicWidth + _gap + actionWidth <= width;
    label.dispose();
    words.dispose();
    return fits;
  }
}
