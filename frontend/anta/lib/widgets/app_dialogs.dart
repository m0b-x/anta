import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/counter.dart';
import '../services/app_navigator.dart';
import 'counter_form_dialog.dart';
import 'counter_picker_dialog.dart';
import 'icon_picker_dialog.dart';

/// Unified dialog system for the entire app.
///
/// Every dialog follows the same visual conventions:
///  - Optional leading icon (sized 48, coloured by context)
///  - Title via `AppTextStyles.dialogTitle`
///  - Consistent cancel/action button placement
///  - Destructive actions use `colorScheme.error`
///  - Loading dialogs are non-dismissible
///
/// Usage: `final result = await AppDialogs.confirm(context, ...);`
class AppDialogs {
  AppDialogs._();

  // ---------------------------------------------------------------------------
  // 1) Confirmation
  // ---------------------------------------------------------------------------

  /// Generic yes/no confirmation. Returns `true` when the user taps confirm.
  ///
  /// Set [isDestructive] to `true` to render the confirm button in error red.
  /// An optional [icon] is displayed above the title when provided.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? content,
    Widget? contentWidget,
    String? confirmText,
    String? cancelText,
    bool isDestructive = false,
    IconData? icon,
  }) async {
    assert(
      content != null || contentWidget != null,
      'Provide either content or contentWidget',
    );
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: icon != null
            ? Icon(
                icon,
                size: 48,
                color: isDestructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              )
            : null,
        title: Text(title),
        content: contentWidget ?? Text(content!),
        actions: [
          TextButton(
            onPressed: () => AppNavigator.pop(ctx, false),
            child: Text(cancelText ?? l10n.cancel),
          ),
          if (isDestructive)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => AppNavigator.pop(ctx, true),
              child: Text(confirmText ?? l10n.delete),
            )
          else
            FilledButton(
              onPressed: () => AppNavigator.pop(ctx, true),
              child: Text(confirmText ?? l10n.save),
            ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // 2) Text Input
  // ---------------------------------------------------------------------------

  /// Shows a dialog with a single [TextField]. Returns the entered text or
  /// `null` if the user cancels.
  ///
  /// Pressing Enter (onSubmitted) also confirms.
  static Future<String?> textInput(
    BuildContext context, {
    required String title,
    String? hintText,
    String? labelText,
    String initialValue = '',
    String? confirmText,
    String? cancelText,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialValue);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hintText,
            labelText: labelText,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) => AppNavigator.pop(ctx, val),
        ),
        actions: [
          TextButton(
            onPressed: () => AppNavigator.pop(ctx),
            child: Text(cancelText ?? l10n.cancel),
          ),
          FilledButton(
            onPressed: () => AppNavigator.pop(ctx, controller.text),
            child: Text(confirmText ?? l10n.save),
          ),
        ],
      ),
    );

    return result;
  }

  // ---------------------------------------------------------------------------
  // 3) Loading
  // ---------------------------------------------------------------------------

  /// Non-dismissible spinner dialog. **Caller must call `Navigator.pop`** when
  /// the async work finishes (or use [runWithLoading] instead).
  static void showLoading(BuildContext context, {required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  /// Convenience wrapper: shows a loading dialog, runs [work], then dismisses.
  ///
  /// Returns the result of [work]. If the widget is unmounted during execution
  /// the pop is skipped safely.
  static Future<T?> runWithLoading<T>(
    BuildContext context, {
    required String message,
    required Future<T> Function() work,
  }) async {
    showLoading(context, message: message);
    try {
      final result = await work();
      if (context.mounted) AppNavigator.pop(context);
      return result;
    } catch (_) {
      if (context.mounted) AppNavigator.pop(context);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // 4) Info / Action (non-dismissible)
  // ---------------------------------------------------------------------------

  /// A non-dismissible dialog with an icon, message and a single action button.
  ///
  /// Useful for "restart required" / "data deleted" screens where the user must
  /// take an explicit action.
  static Future<void> action(
    BuildContext context, {
    required String title,
    required String content,
    required String actionText,
    required VoidCallback onAction,
    IconData? icon,
    Color? iconColor,
    bool barrierDismissible = false,
  }) {
    final theme = Theme.of(context);

    return showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => PopScope(
        canPop: barrierDismissible,
        child: AlertDialog(
          icon: icon != null
              ? Icon(
                  icon,
                  size: 48,
                  color: iconColor ?? theme.colorScheme.primary,
                )
              : null,
          title: Text(title),
          content: Text(content),
          actions: [FilledButton(onPressed: onAction, child: Text(actionText))],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5) Single-choice selection
  // ---------------------------------------------------------------------------

  /// Shows a dialog with a list of labelled options. Returns the selected value
  /// of type [T] or `null` if cancelled.
  ///
  /// Each option is a `(T value, String label, [IconData? icon])` record.
  static Future<T?> choose<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label, IconData? icon})> options,
    T? currentValue,
    String? cancelText,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, i) {
              final opt = options[i];
              final isSelected = opt.value == currentValue;
              return ListTile(
                leading: opt.icon != null
                    ? Icon(
                        opt.icon,
                        color: isSelected ? theme.colorScheme.primary : null,
                      )
                    : null,
                title: Text(
                  opt.label,
                  style: isSelected
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
                selected: isSelected,
                selectedTileColor: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
                onTap: () => AppNavigator.pop(ctx, opt.value),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => AppNavigator.pop(ctx),
            child: Text(cancelText ?? l10n.cancel),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6) Radio selection (returns on tap, shows current value indicator)
  // ---------------------------------------------------------------------------

  /// Like [choose] but renders radio indicators for the current value.
  /// Best for settings where users pick one option from a small set.
  static Future<T?> radioSelect<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label, String? subtitle})> options,
    required T currentValue,
    String? cancelText,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, i) {
              final opt = options[i];
              final isSelected = opt.value == currentValue;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                title: Text(opt.label),
                subtitle: opt.subtitle != null ? Text(opt.subtitle!) : null,
                onTap: () => AppNavigator.pop(ctx, opt.value),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => AppNavigator.pop(ctx),
            child: Text(cancelText ?? l10n.cancel),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7) Counter form (create / edit)
  // ---------------------------------------------------------------------------

  /// Shows a dialog to create or edit a counter.
  ///
  /// Returns a [CounterFormResult] if the user confirms, or `null` if
  /// cancelled.  Pass [existing] to pre-fill the form for editing.
  static Future<CounterFormResult?> counterForm(
    BuildContext context, {
    Counter? existing,
  }) {
    return showCounterFormDialog(context, existing: existing);
  }

  // ---------------------------------------------------------------------------
  // 8) Counter picker
  // ---------------------------------------------------------------------------

  /// Shows a searchable, paginated dialog that lists available counters and
  /// lets the user pick one.
  static Future<Counter?> counterPicker(
    BuildContext context, {
    required List<Counter> counters,
    required Map<String, int> counterValues,
    String? noteId,
    Future<({List<Counter> counters, Map<String, int> counterValues})?>
    Function()?
    onManageCounters,
  }) {
    return showDialog<Counter>(
      context: context,
      builder: (_) => CounterPickerDialog(
        counters: counters,
        counterValues: counterValues,
        noteId: noteId,
        onManageCounters: onManageCounters,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 9) Icon picker
  // ---------------------------------------------------------------------------

  /// Shows a searchable icon-grid dialog.  Returns the picked [IconData] or
  /// `null` if cancelled.
  static Future<IconData?> iconPicker(
    BuildContext context, {
    IconData? currentIcon,
  }) {
    return showDialog<IconData>(
      context: context,
      builder: (_) => IconPickerDialog(currentIcon: currentIcon),
    );
  }
}
