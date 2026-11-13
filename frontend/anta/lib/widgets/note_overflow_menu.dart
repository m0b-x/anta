import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import 'automation_id.dart';
import '../l10n/app_localizations.dart';

enum _NoteMenuAction {
  openFolder,
  editTitle,
  move,
  label,
  share,
  copyToMine,
  delete,
  settings,
}

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
    this.onLabel,
    required this.onShare,
    required this.onDelete,
    required this.onSettings,
    this.fromPartner = false,
    this.onCopyToMine,
  });

  /// The folder's name, or the generic "Folders" label until the read that
  /// resolves it answers.
  final String folderName;

  final VoidCallback onOpenFolder;
  final VoidCallback onEditTitle;
  final VoidCallback onMove;

  /// Opens the colour-label picker, or `null` while there is nothing to
  /// label — a note the early create has not persisted yet has no row to
  /// carry a colour, so the row shows disabled: the menu keeps its shape
  /// from the first keystroke on.
  final VoidCallback? onLabel;

  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onSettings;

  /// A note the partner shares (share surfaces §6.13, D19): the entries that
  /// would write it or send it out — Edit title, Move, Label, Send a copy,
  /// Delete — stay in place disabled, and "Copy to my notes" follows Send a
  /// copy. False keeps today's menu.
  final bool fromPartner;

  /// "Copy to my notes", read only while [fromPartner]; null draws the
  /// entry disabled.
  final VoidCallback? onCopyToMine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return AutomationId(
      identifier: SemanticsIds.editorMore,
      child: _buildMenu(context, l10n, colorScheme),
    );
  }

  Widget _buildMenu(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
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
          case _NoteMenuAction.label:
            onLabel?.call();
          case _NoteMenuAction.share:
            onShare();
          case _NoteMenuAction.copyToMine:
            onCopyToMine?.call();
          case _NoteMenuAction.delete:
            onDelete();
          case _NoteMenuAction.settings:
            onSettings();
        }
      },
      itemBuilder: (context) {
        final writable = !fromPartner;
        return [
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
            enabled: writable,
          ),
          _row(
            colorScheme,
            value: _NoteMenuAction.move,
            icon: Icons.drive_file_move_outlined,
            label: l10n.moveToFolder,
            enabled: writable,
          ),
          _row(
            colorScheme,
            value: _NoteMenuAction.label,
            icon: Icons.label_outline,
            label: l10n.labelAction,
            enabled: writable && onLabel != null,
          ),
          _row(
            colorScheme,
            value: _NoteMenuAction.share,
            icon: Icons.share_rounded,
            label: l10n.shareNote,
            enabled: writable,
          ),
          if (!writable)
            _row(
              colorScheme,
              value: _NoteMenuAction.copyToMine,
              icon: Icons.content_copy_rounded,
              label: l10n.sharedNoteCopy,
              identifier: SemanticsIds.sharedNoteCopy,
              enabled: onCopyToMine != null,
            ),
          const PopupMenuDivider(height: AppTheme.menuDividerHeight),
          // Disabled, it draws as every off row does: red would read as live.
          _row(
            colorScheme,
            value: _NoteMenuAction.delete,
            icon: Icons.delete,
            label: l10n.deleteNote,
            color: writable ? colorScheme.error : null,
            enabled: writable,
          ),
          const PopupMenuDivider(height: AppTheme.menuDividerHeight),
          _row(
            colorScheme,
            value: _NoteMenuAction.settings,
            icon: Icons.settings_outlined,
            label: l10n.settings,
          ),
        ];
      },
    );
  }

  PopupMenuItem<_NoteMenuAction> _row(
    ColorScheme colorScheme, {
    required _NoteMenuAction value,
    required IconData icon,
    required String label,
    String? trailing,
    Color? color,
    bool enabled = true,
    String? identifier,
  }) {
    final row = Row(
      children: [
        Icon(
          icon,
          size: AppTheme.menuIconSize,
          // A disabled row's glyph dims with its label.
          color: (color ?? colorScheme.onSurfaceVariant).withValues(
            alpha: enabled ? 1 : FormMetrics.disabledOpacity,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            // The menu's label style has no disabled state of its own: an
            // off row's words dim with its glyph, or a write reads as live.
            style: !enabled
                ? TextStyle(
                    color: colorScheme.onSurface.withValues(
                      alpha: FormMetrics.disabledOpacity,
                    ),
                  )
                : color == null
                ? null
                : TextStyle(color: color),
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
    );
    return PopupMenuItem<_NoteMenuAction>(
      value: value,
      enabled: enabled,
      height: AppTheme.menuItemHeight,
      child: identifier == null
          ? row
          : Semantics(identifier: identifier, child: row),
    );
  }
}
