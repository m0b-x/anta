import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/counter.dart';
import '../services/app_navigator.dart';

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

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final l10n = AppLocalizations.of(ctx)!;
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
                TextField(
                  controller: startController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.startValue,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stepController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.step,
                    border: const OutlineInputBorder(),
                  ),
                ),
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
              onPressed: () => AppNavigator.pop(ctx, true),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    ),
  );

  final name = nameController.text.trim();
  final startValue = int.tryParse(startController.text) ?? 1;
  final step = int.tryParse(stepController.text) ?? 1;

  if (result != true || name.isEmpty) return null;

  return CounterFormResult(
    name: name,
    startValue: startValue,
    step: step,
    scope: scope,
  );
}
