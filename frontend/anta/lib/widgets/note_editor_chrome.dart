import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../l10n/app_localizations.dart';

typedef NoteEditorStats = ({int lineCount, int charCount});

const NoteEditorStats emptyNoteEditorStats = (lineCount: 1, charCount: 0);

class ValueListenableAppBar<T> extends StatelessWidget
    implements PreferredSizeWidget {
  final ValueListenable<T> valueListenable;
  final PreferredSizeWidget Function(BuildContext context, T value) builder;

  @override
  final Size preferredSize;

  const ValueListenableAppBar({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.preferredSize = const Size.fromHeight(kToolbarHeight),
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: valueListenable,
      builder: (context, value, _) => builder(context, value),
    );
  }
}

class NoteEditorStatsBar extends StatelessWidget {
  final ValueListenable<NoteEditorStats> stats;
  final int fallbackCharCount;
  final int chunkCount;
  final bool isCompressed;

  const NoteEditorStatsBar({
    super.key,
    required this.stats,
    required this.fallbackCharCount,
    required this.chunkCount,
    required this.isCompressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final labelStyle = TextStyle(
      fontSize: 11,
      color: colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      color: colorScheme.surfaceContainerHighest,
      child: ValueListenableBuilder<NoteEditorStats>(
        valueListenable: stats,
        builder: (context, value, _) {
          final charCount = value.charCount > 0
              ? value.charCount
              : fallbackCharCount;
          return Row(
            children: [
              Text(l10n.noteStats(charCount, chunkCount), style: labelStyle),
              if (isCompressed) ...[
                const SizedBox(width: 8),
                Icon(Icons.compress, size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  l10n.compressedNote,
                  style: TextStyle(fontSize: 11, color: colorScheme.primary),
                ),
              ],
              const Spacer(),
              Text(l10n.lineCount(value.lineCount), style: labelStyle),
            ],
          );
        },
      ),
    );
  }
}
