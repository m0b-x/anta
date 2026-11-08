import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import 'automation_id.dart';
import '../l10n/app_localizations.dart';
import '../models/counter.dart';
import '../services/app_navigator.dart';
import 'counter_form_dialog.dart';
import 'counter_picker_dialog.dart';
import 'icon_picker_dialog.dart';

/// What [AppDialogs.progress] shows: the index of its current step, the
/// bar's share (`null` draws it indeterminate), and whether Cancel takes a
/// tap.
typedef ProgressDialogState = ({int step, double? fraction, bool canCancel});

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
  /// [confirmIdentifier] replaces the shared [SemanticsIds.sheetConfirm] for
  /// a confirm a device flow must not mistake for another dialog's.
  ///
  /// Scrollable: at 200 % in German or Romanian a two-sentence body is taller
  /// than the dialog may grow, and a fixed dialog cut its last line off with
  /// nothing to say so (the sync Merge and Stop confirms, review D2-1). A
  /// body that fits lays out as before; [contentWidget] must not scroll
  /// itself. Its title and actions are every kit dialog's ([_title],
  /// [_actions]).
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? content,
    Widget? contentWidget,
    String? confirmText,
    String? cancelText,
    bool isDestructive = false,
    IconData? icon,
    String? confirmIdentifier,
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
        scrollable: true,
        icon: icon != null
            ? Icon(
                icon,
                size: 48,
                color: isDestructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              )
            : null,
        title: _title(Text(title)),
        content: contentWidget ?? Text(content!),
        actions: _actions([
          AutomationId(
            identifier: SemanticsIds.sheetCancel,
            child: TextButton(
              onPressed: () => AppNavigator.pop(ctx, false),
              child: Text(cancelText ?? l10n.cancel),
            ),
          ),
          AutomationId(
            identifier: confirmIdentifier ?? SemanticsIds.sheetConfirm,
            child: isDestructive
                ? FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => AppNavigator.pop(ctx, true),
                    child: Text(confirmText ?? l10n.delete),
                  )
                : FilledButton(
                    onPressed: () => AppNavigator.pop(ctx, true),
                    child: Text(confirmText ?? l10n.save),
                  ),
          ),
        ]),
      ),
    );
    return result ?? false;
  }

  /// The form sheets' leave guard — the event editor's and the description
  /// sheet's — asked only once the caller knows the form is dirty. Returns
  /// `true` to leave.
  ///
  /// Not [confirm]: that dialog carries a body line and a filled confirm, and
  /// here the title is the whole message and the confirm is tonal — the text
  /// being dropped is unsaved, not stored, so it earns neither the delete red
  /// nor the commit's fill (the calendar-ui rule for a destructive
  /// confirmation). One copy, so the two sheets cannot phrase the same
  /// question differently.
  static Future<bool> confirmDiscard(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          // The title merges into the dialog's own title node, so the id
          // marks the question a flow waits for.
          title: Semantics(
            identifier: SemanticsIds.unsavedDialog,
            child: _title(Text(l10n.unsavedChanges)),
          ),
          actions: _actions([
            AutomationId(
              identifier: SemanticsIds.unsavedKeepEditing,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.keepEditing),
              ),
            ),
            AutomationId(
              identifier: SemanticsIds.unsavedDiscard,
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.discardChanges),
              ),
            ),
          ]),
        );
      },
    );
    return discard ?? false;
  }

  // ---------------------------------------------------------------------------
  // 2) Text Input
  // ---------------------------------------------------------------------------

  /// Shows a dialog with a single [TextField]. Returns the entered text or
  /// `null` if the user cancels.
  ///
  /// Pressing Enter (onSubmitted) also confirms.
  ///
  /// [selectAll] opens with [initialValue] selected whole, so a suggested
  /// name is replaced by typing and kept by Save — a starting point, never
  /// something to delete first. Without [allowEmpty] confirm is disabled, and
  /// Enter does nothing, while the trimmed text is empty.
  ///
  /// [warningFor] is asked on every keystroke for a line under the field in
  /// the error colour, as `FormTitleRow.warning` warns: a remark that never
  /// blocks confirm — a saved list's duplicate name is confusing, not
  /// corrupting, and blocking it would break "rename A, then reuse A's old
  /// name". It is drawn in the counter's own style, so beside a counter it
  /// shares the counter's line and the dialog does not move under the finger
  /// as it appears; the caption's 13 px on an 18 px line grew the row.
  /// [warningRefresh] asks again when it notifies, for a [warningFor] whose
  /// answer lands after the keystroke (a lookup in the database).
  ///
  /// [fieldIdentifier] and [confirmIdentifier] are `SemanticsIds` for a
  /// device script; the confirm button's falls back to the generic
  /// `sheet-confirm`.
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
    bool selectAll = false,
    bool allowEmpty = true,
    String? Function(String text)? warningFor,
    Listenable? warningRefresh,
    String? fieldIdentifier,
    String? confirmIdentifier,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialValue);
    if (selectAll) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialValue.length,
      );
    }
    bool canConfirm() => allowEmpty || controller.text.trim().isNotEmpty;
    void confirm(BuildContext ctx) {
      if (canConfirm()) AppNavigator.pop(ctx, controller.text);
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _title(Text(title)),
        content: ListenableBuilder(
          listenable: warningRefresh == null
              ? controller
              : Listenable.merge([controller, warningRefresh]),
          builder: (context, _) {
            final warning = warningFor?.call(controller.text);
            final colorScheme = Theme.of(context).colorScheme;
            final field = TextField(
              controller: controller,
              autofocus: true,
              maxLength: maxLength,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              decoration: InputDecoration(
                hintText: hintText,
                labelText: labelText,
                border: const OutlineInputBorder(),
                // The helper line's default is the counter's `bodySmall`;
                // only the colour changes, and only while a warning is up.
                // The counter takes its colour from the helper's style, so
                // it is set apart or it reads red beside no warning at all.
                helperText: warning,
                helperStyle: warning == null
                    ? null
                    : TextStyle(color: colorScheme.error),
                counterStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              onSubmitted: (_) => confirm(ctx),
            );
            return fieldIdentifier == null
                ? field
                : AutomationId(identifier: fieldIdentifier, child: field);
          },
        ),
        actions: _actions([
          AutomationId(
            identifier: SemanticsIds.sheetCancel,
            child: TextButton(
              onPressed: () => AppNavigator.pop(ctx),
              child: Text(cancelText ?? l10n.cancel),
            ),
          ),
          AutomationId(
            identifier: confirmIdentifier ?? SemanticsIds.sheetConfirm,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => FilledButton(
                onPressed: canConfirm() ? () => confirm(ctx) : null,
                child: Text(confirmText ?? l10n.save),
              ),
            ),
          ),
        ]),
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

  /// A non-dismissible dialog over work that reports itself through
  /// [listenable] and [read]: one line per entry of [steps], a bar under it
  /// — determinate on a fraction, indeterminate on `null` — and a Cancel
  /// that calls [onCancel], disabled, never hidden, while the step cannot be
  /// stopped. Every step's line is laid out and only the current one shown
  /// and spoken, so a switch never changes the dialog's height. **The
  /// caller pops it** when the work settles, as with [showLoading]; the
  /// future completes once it is gone.
  static Future<void> progress(
    BuildContext context, {
    required List<String> steps,
    required Listenable listenable,
    required ProgressDialogState Function() read,
    required VoidCallback onCancel,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final state = read();
            return AlertDialog(
              scrollable: true,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: IndexedStack(
                      index: state.step,
                      children: [for (final step in steps) Text(step)],
                    ),
                  ),
                  const SizedBox(height: FormMetrics.dialogProgressGap),
                  LinearProgressIndicator(value: state.fraction),
                ],
              ),
              actions: _actions([
                AutomationId(
                  identifier: SemanticsIds.sheetCancel,
                  child: TextButton(
                    onPressed: state.canCancel ? onCancel : null,
                    child: Text(l10n.cancel),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4) Info / Action (non-dismissible)
  // ---------------------------------------------------------------------------

  /// A non-dismissible dialog with an icon, message and a single action button.
  ///
  /// Useful for "restart required" / "data deleted" screens where the user must
  /// take an explicit action. [actionIdentifier] puts a `SemanticsIds` value
  /// on the button, for a flow that must answer this dialog and no other.
  static Future<void> action(
    BuildContext context, {
    required String title,
    required String content,
    required String actionText,
    required VoidCallback onAction,
    IconData? icon,
    Color? iconColor,
    bool barrierDismissible = false,
    String? actionIdentifier,
  }) {
    final theme = Theme.of(context);
    final Widget button = FilledButton(
      onPressed: onAction,
      child: Text(actionText),
    );

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
          title: _title(Text(title)),
          content: Text(content),
          actions: _actions([
            if (actionIdentifier case final id?)
              AutomationId(identifier: id, child: button)
            else
              button,
          ]),
        ),
      ),
    );
  }

  /// The app's About: its mark, its name over its version, one line of what
  /// it is, and the licences. Not Flutter's `showAboutDialog`, whose small
  /// icon slot and Material-only close word sit outside the conventions
  /// above; the caller passes the version from `kAppVersion`, so no literal
  /// can drift at a release bump (S16). [icon] is the app's mark — the
  /// launcher art, not a glyph (D10) — drawn in a 48 dp square and silent to
  /// a screen reader, which hears the name beneath it.
  static Future<void> about(
    BuildContext context, {
    required Widget icon,
    required String name,
    required String version,
    required String description,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Named, or Android announces the route as Flutter's generic "Alert".
        semanticLabel: l10n.about,
        // The two actions stack at the end rather than the start when German
        // or Romanian at 2.0 leaves them no room side by side.
        actionsOverflowAlignment: OverflowBarAlignment.end,
        // Centred: the dialog stretches its icon slot to the dialog's width.
        icon: ExcludeSemantics(
          child: Center(child: SizedBox.square(dimension: 48, child: icon)),
        ),
        // The title merges into the dialog's own title node, so the id marks
        // the dialog a flow waits for, and the version is read beside it.
        title: Semantics(
          identifier: SemanticsIds.aboutDialog,
          header: true,
          child: _title(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name),
                Text(
                  version,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        content: Text(description),
        actions: _actions([
          TextButton(
            onPressed: () => showLicensePage(
              context: ctx,
              applicationName: name,
              applicationVersion: version,
            ),
            child: Text(materialL10n.viewLicensesButtonLabel),
          ),
          AutomationId(
            identifier: SemanticsIds.sheetCancel,
            child: TextButton(
              onPressed: () => AppNavigator.pop(ctx),
              child: Text(l10n.close),
            ),
          ),
        ]),
      ),
    );
  }

  static Widget _identifiedTitle(String title, String? identifier) {
    if (identifier == null) return _title(Text(title));
    return Semantics(identifier: identifier, child: _title(Text(title)));
  }

  /// Every kit dialog's title: its text scale clamped at
  /// [FormMetrics.dialogTitleMaxTextScale], or at 200 % a German or Romanian
  /// title broke mid-word ("zusammenf|ühren?", review D3-3), and medium
  /// weight at every scale, since clamped it is barely larger than a body
  /// that keeps the full scale and weight is what keeps it the title (D4-2).
  /// A part of [title] with a style of its own (the About's version) keeps
  /// that style's weight.
  static Widget _title(Widget title) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: FormMetrics.dialogTitleMaxTextScale,
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w500),
      child: title,
    ),
  );

  /// Every kit dialog's action buttons, their labels' scale clamped at
  /// [FormMetrics.dialogActionMaxTextScale]: a one-word label in a button
  /// broke mid-word at 200 % ("Zusammenführ|en", review D3-3).
  static List<Widget> _actions(List<Widget> actions) => [
    for (final action in actions)
      MediaQuery.withClampedTextScaling(
        maxScaleFactor: FormMetrics.dialogActionMaxTextScale,
        child: action,
      ),
  ];

  // ---------------------------------------------------------------------------
  // 5) Single-choice selection
  // ---------------------------------------------------------------------------

  /// Shows a dialog with a list of labelled options. Returns the selected value
  /// of type [T] or `null` if cancelled.
  ///
  /// Each option is a `(T value, String label, [IconData? icon])` record.
  /// [identifier] marks the title, as [about]'s, for a flow to wait on.
  static Future<T?> choose<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label, IconData? icon})> options,
    T? currentValue,
    String? cancelText,
    String? identifier,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _identifiedTitle(title, identifier),
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
        actions: _actions([
          TextButton(
            onPressed: () => AppNavigator.pop(ctx),
            child: Text(cancelText ?? l10n.cancel),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6) Radio selection (returns on tap, shows current value indicator)
  // ---------------------------------------------------------------------------

  /// Like [choose] but renders radio indicators for the current value.
  /// Best for settings where users pick one option from a small set.
  /// [identifier] marks the title, as [choose]'s.
  static Future<T?> radioSelect<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label, String? subtitle})> options,
    required T currentValue,
    String? cancelText,
    String? identifier,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _identifiedTitle(title, identifier),
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
        actions: _actions([
          TextButton(
            onPressed: () => AppNavigator.pop(ctx),
            child: Text(cancelText ?? l10n.cancel),
          ),
        ]),
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
