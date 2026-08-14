import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Bottom action bar shown while the folder content page is in selection mode.
/// Hosts batch operations (move, delete) for the currently selected items.
class SelectionActionBar extends StatelessWidget {
  final int count;
  final VoidCallback? onMove;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;

  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final enabled = count > 0;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Action(
                icon: Icons.drive_file_move_outline,
                label: l10n.moveSelected,
                color: colorScheme.primary,
                onPressed: enabled ? onMove : null,
              ),
              _Action(
                icon: Icons.share_outlined,
                label: l10n.shareSelected,
                color: colorScheme.primary,
                onPressed: enabled ? onShare : null,
              ),
              _Action(
                icon: Icons.delete_outline,
                label: l10n.deleteSelected,
                color: colorScheme.error,
                onPressed: enabled ? onDelete : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final c = disabled ? Theme.of(context).disabledColor : color;
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: c, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
