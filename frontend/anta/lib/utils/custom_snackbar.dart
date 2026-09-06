import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';

class CustomSnackbar {
  static void show(
    BuildContext context,
    String message, {
    Duration? duration,
    bool withToolbarOffset = false,
  }) {
    _showSnackBar(
      context,
      content: Text(message),
      duration: duration ?? AppConstants.snackbarDuration,
      withToolbarOffset: withToolbarOffset,
      showCloseIcon: true,
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
  }) {
    // Cap so an action prompt (e.g. Undo) never lingers indefinitely.
    // Anything longer than the cap collapses down to the cap; callers
    // that pass a shorter duration are honored as-is.
    final requested = duration ?? AppConstants.snackbarActionMaxDuration;
    final capped = requested > AppConstants.snackbarActionMaxDuration
        ? AppConstants.snackbarActionMaxDuration
        : requested;

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
        onAction: onAction,
      ),
      duration: capped,
      withToolbarOffset: withToolbarOffset,
      showCloseIcon: true,
    );
  }

  static void _showSnackBar(
    BuildContext context, {
    required Widget content,
    required Duration duration,
    required bool withToolbarOffset,
    bool showCloseIcon = false,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        behavior: SnackBarBehavior.floating,
        margin: _floatingMargin(context, withToolbarOffset: withToolbarOffset),
        duration: duration,
        showCloseIcon: showCloseIcon,
      ),
    );
  }

  /// The margin every floating bar is laid out with: the shared
  /// [AppSpacing.snackbarMargin], lifted by the keyboard's height when the
  /// host [Scaffold] has opted out of avoiding the keyboard itself.
  ///
  /// `_ScaffoldLayout` anchors a floating bar's bottom edge at
  /// `min(contentBottom, size.height - minViewPadding.bottom)`
  /// (`material/scaffold.dart:1238-1241`), and `contentBottom` is the only
  /// term that knows about the IME: it subtracts `minInsets.bottom`
  /// (`scaffold.dart:1088-1091`), which carries the keyboard inset **only**
  /// while `resizeToAvoidBottomInset` is true and is forced to zero otherwise
  /// (`scaffold.dart:3220-3222`). A page that manages the inset itself — the
  /// note editor pads its own body by it, so its toolbar rides the keyboard —
  /// therefore leaves the bar anchored to the bottom of the screen, under the
  /// IME, where a tap's only feedback is invisible. That missing lift is what
  /// this adds; where the Scaffold does resize it adds nothing, because a
  /// second lift would strand the bar mid-screen.
  ///
  /// The keyboard inset is the only term added. Safe-area padding is the
  /// Scaffold's business in both branches: line 1238 already pulls a floating
  /// bar up by `minViewPadding.bottom`, which stays at the full
  /// `viewPadding.bottom` precisely when the Scaffold does not resize
  /// (`scaffold.dart:3226-3230`). Lifting by `max(viewInsets, viewPadding)` —
  /// the rule this project's bottom sheets need, since a sheet sits in a
  /// full-bleed route with nothing else applying the system inset — would
  /// count the navigation bar twice here.
  static EdgeInsets _floatingMargin(
    BuildContext context, {
    required bool withToolbarOffset,
  }) {
    final margin = AppSpacing.snackbarMargin(
      withToolbarOffset: withToolbarOffset,
    );
    final scaffold = _hostScaffold(context);
    if (scaffold?.widget.resizeToAvoidBottomInset != false) return margin;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardInset <= 0) return margin;
    return margin.copyWith(bottom: margin.bottom + keyboardInset);
  }

  /// The [Scaffold] that will lay this bar out, looked up in both directions.
  ///
  /// [Scaffold.maybeOf] only walks up (`scaffold.dart:2090-2092`), which
  /// answers for callers inside the body — sheets, list rows, `Builder`s. This
  /// app's pages, though, call in from their `State.context`, which sits
  /// *above* the Scaffold their `build` returns, so the upward lookup alone
  /// would answer null for exactly the pages that need the lift. The downward
  /// walk stops at the first [ScaffoldState], a handful of elements below a
  /// page's own context. Finding no Scaffold at all leaves the margin as it
  /// was — the bar keeps whatever position it has today.
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

  const _ActionContent({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // SnackBar uses inverse surface colors by default — match the action
    // text to the inverse primary so it reads as a tappable accent on
    // the dark snackbar background.
    final actionColor =
        theme.snackBarTheme.actionTextColor ?? theme.colorScheme.inversePrimary;

    return Row(
      children: [
        Expanded(child: Text(message)),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () {
            // Dismiss the snackbar before invoking the callback so the
            // user's confirming tap doesn't leave it lingering.
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            onAction();
          },
          style: TextButton.styleFrom(
            foregroundColor: actionColor,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            actionLabel.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
