import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../l10n/app_localizations.dart';

enum _NoteMenuAction { openFolder, editTitle, move, share, delete, settings }

/// The note editor's app-bar menu — the editor's first one.
///
/// The top row names the folder the note lives in and returns to it, which
/// is what a chain of `[[wiki links]]` needs: the folder it started from can
/// be several notes down, or not on the stack at all.
class NoteOverflowMenu extends StatelessWidget {
  const NoteOverflowMenu({
    super.key,
    required this.folderName,
    required this.onOpenFolder,
    required this.onEditTitle,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
    required this.onSettings,
  });

  /// The folder's name, or the generic "Folders" label until the read that
  /// resolves it answers.
  final String folderName;

  final VoidCallback onOpenFolder;
  final VoidCallback onEditTitle;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_NoteMenuAction>(
      icon: const Icon(Icons.more_vert),
      constraints: const BoxConstraints.tightFor(width: AppTheme.menuWidth),
      onSelected: (action) {
        switch (action) {
          case _NoteMenuAction.openFolder:
            onOpenFolder();
          case _NoteMenuAction.editTitle:
            onEditTitle();
          case _NoteMenuAction.move:
            onMove();
          case _NoteMenuAction.share:
            onShare();
          case _NoteMenuAction.delete:
            onDelete();
          case _NoteMenuAction.settings:
            onSettings();
        }
      },
      itemBuilder: (context) => [
        _row(
          colorScheme,
          value: _NoteMenuAction.openFolder,
          icon: Icons.folder_outlined,
          label: folderName,
          trailing: l10n.openFolder,
        ),
        const PopupMenuDivider(height: AppTheme.menuDividerHeight),
        _row(
          colorScheme,
          value: _NoteMenuAction.editTitle,
          icon: Icons.edit,
          label: l10n.editTitle,
        ),
        _row(
          colorScheme,
          value: _NoteMenuAction.move,
          icon: Icons.drive_file_move_outlined,
          label: l10n.moveToFolder,
        ),
        _row(
          colorScheme,
          value: _NoteMenuAction.share,
          icon: Icons.share_rounded,
          label: l10n.shareNote,
        ),
        const PopupMenuDivider(height: AppTheme.menuDividerHeight),
        _row(
          colorScheme,
          value: _NoteMenuAction.delete,
          icon: Icons.delete,
          label: l10n.deleteNote,
          color: colorScheme.error,
        ),
        const PopupMenuDivider(height: AppTheme.menuDividerHeight),
        _row(
          colorScheme,
          value: _NoteMenuAction.settings,
          icon: Icons.settings_outlined,
          label: l10n.settings,
        ),
      ],
    );
  }

  PopupMenuItem<_NoteMenuAction> _row(
    ColorScheme colorScheme, {
    required _NoteMenuAction value,
    required IconData icon,
    required String label,
    String? trailing,
    Color? color,
  }) {
    return PopupMenuItem<_NoteMenuAction>(
      value: value,
      height: AppTheme.menuItemHeight,
      child: Row(
        children: [
          Icon(
            icon,
            size: AppTheme.menuIconSize,
            color: color ?? colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: color == null ? null : TextStyle(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(
              trailing,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: AppTheme.menuTrailingSize,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
