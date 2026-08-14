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
        margin: AppSpacing.snackbarMargin(withToolbarOffset: withToolbarOffset),
        duration: duration,
        showCloseIcon: showCloseIcon,
      ),
    );
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
