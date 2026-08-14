import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/move_coordinator.dart';
import '../services/move_history_service.dart';
import 'app_dialogs.dart';

void showMoveHistorySheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _MoveHistorySheet(),
  );
}

class _MoveHistorySheet extends StatefulWidget {
  const _MoveHistorySheet();

  @override
  State<_MoveHistorySheet> createState() => _MoveHistorySheetState();
}

class _MoveHistorySheetState extends State<_MoveHistorySheet> {
  final MoveHistoryService _historyService = GetIt.I<MoveHistoryService>();
  late StreamSubscription<int> _subscription;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _subscription = _historyService.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.clearHistory,
      content: l10n.clearMoveHistoryConfirm,
      isDestructive: true,
      confirmText: l10n.clearHistory,
    );
    if (confirmed) {
      _historyService.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final history = _historyService.history;

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.75,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.history, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.moveHistory,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: _confirmClear,
                    child: Text(l10n.clearHistory),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: history.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.noMoveHistory,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entry = history[index];
                      return _buildEntry(context, entry, colorScheme, l10n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(
    BuildContext context,
    MoveHistoryEntry entry,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final isNote = entry.itemType == MoveItemType.note;
    final targetName = entry.targetParentName ?? l10n.rootFolder;
    final timeDiff = DateTime.now().difference(entry.timestamp);
    final timeText = _formatTimeDiff(timeDiff, l10n);

    return ListTile(
      leading: Icon(
        isNote ? Icons.note_outlined : Icons.folder_outlined,
        color: entry.isUndone
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
            : null,
      ),
      title: Text(
        entry.itemName,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          decoration: entry.isUndone ? TextDecoration.lineThrough : null,
          color: entry.isUndone
              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
              : null,
        ),
      ),
      subtitle: Text(
        entry.isUndone ? l10n.undone : l10n.movedToTarget(targetName),
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: entry.isUndone ? 0.3 : 0.7,
          ),
        ),
      ),
      trailing: entry.isUndone
          ? Text(
              timeText,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.undo, size: 20, color: colorScheme.primary),
                  onPressed: () => MoveCoordinator.undoEntry(context, entry),
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.undo,
                ),
              ],
            ),
      dense: true,
    );
  }

  String _formatTimeDiff(Duration diff, AppLocalizations l10n) {
    if (diff.inSeconds < 60) return l10n.timeLessThanMinute;
    if (diff.inMinutes < 60) return l10n.timeMinutes(diff.inMinutes);
    if (diff.inHours < 24) return l10n.timeHours(diff.inHours);
    return l10n.timeDays(diff.inDays);
  }
}
