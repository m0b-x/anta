import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/counter.dart';
import '../services/app_navigator.dart';
import 'form_rows.dart';

/// Result returned from [showCounterFormDialog].
class CounterFormResult {
  final String name;
  final int startValue;
  final int step;
  final CounterScope scope;

  const CounterFormResult({
    required this.name,
    required this.startValue,
    required this.step,
    required this.scope,
  });
}

/// Shows a dialog to create or edit a counter.
///
/// Returns a [CounterFormResult] if the user confirms, or `null` if cancelled.
/// Pass [existing] to pre-fill the form for editing.
Future<CounterFormResult?> showCounterFormDialog(
  BuildContext context, {
  Counter? existing,
}) async {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final startController = TextEditingController(
    text: '${existing?.startValue ?? 1}',
  );
  final stepController = TextEditingController(text: '${existing?.step ?? 1}');
  var scope = existing?.scope ?? CounterScope.global;

  // The numbers the form may save, or null while a field holds none it can
  // keep: a step of 0 moves nothing, and an unreadable field used to be
  // saved as 1 (review C12). Read from the controllers at Save and after
  // the dialog, never from the last frame — the text can change between a
  // frame and the tap.
  ({int start, int step})? numbers() {
    final start = int.tryParse(startController.text);
    final step = int.tryParse(stepController.text);
    if (start == null || step == null || step == 0) return null;
    return (start: start, step: step);
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final l10n = AppLocalizations.of(ctx)!;
        final theme = Theme.of(ctx);
        final start = int.tryParse(startController.text);
        final step = int.tryParse(stepController.text);
        final startError = start == null ? l10n.counterNumberInvalid : null;
        final stepError = switch (step) {
          null => l10n.counterNumberInvalid,
          0 => l10n.counterStepZero,
          _ => null,
        };
        final errorStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        );
        // The error line keeps its room, sized for the longest reason that
        // field can give, whether it shows or not: a number retyped through
        // an empty field would otherwise move everything below it twice.
        // An `error` widget, unlike `errorText`, never reaches the field's
        // own semantics node, so the shown reason is set there as its hint
        // and is read out with the field, as a plain `errorText` would be.
        // The hint is set, if empty, while the field is valid too: a hint
        // that comes and goes rebuilds the field's node, and TalkBack's
        // focus on it with the node.
        Widget numberField(
          TextEditingController controller,
          String label,
          String? error,
          List<String> reasons,
        ) {
          final slot = FormCaptionSlot(
            candidates: [
              for (final reason in reasons) Text(reason, style: errorStyle),
            ],
            child: error == null
                ? const SizedBox.shrink()
                : Text(error, style: errorStyle),
          );
          return Semantics(
            hint: error ?? '',
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
              ],
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                helper: error == null ? slot : null,
                error: error == null ? null : slot,
              ),
              onChanged: (_) => setDialogState(() {}),
            ),
          );
        }

        return AlertDialog(
          title: Text(existing != null ? l10n.editCounter : l10n.addCounter),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10n.counterName,
                    border: const OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                numberField(startController, l10n.startValue, startError, [
                  l10n.counterNumberInvalid,
                ]),
                const SizedBox(height: 12),
                numberField(stepController, l10n.step, stepError, [
                  l10n.counterNumberInvalid,
                  l10n.counterStepZero,
                ]),
                const SizedBox(height: 12),
                Text(
                  l10n.counterScope,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<CounterScope>(
                  segments: [
                    ButtonSegment(
                      value: CounterScope.global,
                      label: Text(l10n.global),
                      icon: const Icon(Icons.public_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: CounterScope.perNote,
                      label: Text(l10n.perNote),
                      icon: const Icon(Icons.note_alt_rounded, size: 18),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (values) {
                    setDialogState(() => scope = values.first);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => AppNavigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: startError == null && stepError == null
                  ? () {
                      if (numbers() == null) {
                        setDialogState(() {});
                        return;
                      }
                      AppNavigator.pop(ctx, true);
                    }
                  : null,
              child: Text(l10n.save),
            ),
          ],
        );
      },
    ),
  );

  final name = nameController.text.trim();
  final saved = numbers();
  if (result != true || name.isEmpty || saved == null) return null;

  return CounterFormResult(
    name: name,
    startValue: saved.start,
    step: saved.step,
    scope: scope,
  );
}
