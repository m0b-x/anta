import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum _FolderMenuAction {
  sort,
  select,
  moveHistory,
  rename,
  move,
  share,
  import,
  delete,
  settings,
}

/// The browser's single app-bar menu: everything the page can do to the
/// folder it is showing, plus the drawer.
///
/// The root page has no folder of its own, so the rename/move/share/delete
/// group is dropped there rather than disabled — the callbacks for it are
/// simply absent.
class FolderOverflowMenu extends StatelessWidget {
  const FolderOverflowMenu({
    super.key,
    required this.isRootPage,
    required this.sortLabel,
    required this.moveHistoryCount,
    required this.onSortBy,
    required this.onSelect,
    required this.onMoveHistory,
    required this.onImport,
    required this.onSettings,
    this.onRenameFolder,
    this.onMoveFolder,
    this.onShareFolder,
    this.onDeleteFolder,
  });

  final bool isRootPage;

  /// The active sort order, shown as trailing text on the sort row so the
  /// menu answers "how is this list ordered?" without being opened twice.
  final String sortLabel;

  /// Undoable moves, badged on the button itself as well as on its row:
  /// the whole point of the badge is to be visible before the menu opens.
  final int moveHistoryCount;

  final VoidCallback onSortBy;
  final VoidCallback onSelect;
  final VoidCallback onMoveHistory;
  final VoidCallback onImport;
  final VoidCallback onSettings;
  final VoidCallback? onRenameFolder;
  final VoidCallback? onMoveFolder;
  final VoidCallback? onShareFolder;
  final VoidCallback? onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_FolderMenuAction>(
      icon: Badge(
        isLabelVisible: moveHistoryCount > 0,
        label: Text('$moveHistoryCount'),
        child: const Icon(Icons.more_vert),
      ),
      onSelected: (action) {
        switch (action) {
          case _FolderMenuAction.sort:
            onSortBy();
          case _FolderMenuAction.select:
            onSelect();
          case _FolderMenuAction.moveHistory:
            onMoveHistory();
          case _FolderMenuAction.rename:
            onRenameFolder?.call();
          case _FolderMenuAction.move:
            onMoveFolder?.call();
          case _FolderMenuAction.share:
            onShareFolder?.call();
          case _FolderMenuAction.import:
            onImport();
          case _FolderMenuAction.delete:
            onDeleteFolder?.call();
          case _FolderMenuAction.settings:
            onSettings();
        }
      },
      itemBuilder: (context) => [
        _row(
          value: _FolderMenuAction.sort,
          icon: Icons.sort,
          label: l10n.sortBy,
          trailing: Text(
            sortLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _row(
          value: _FolderMenuAction.select,
          icon: Icons.checklist_rounded,
          label: l10n.select,
        ),
        _row(
          value: _FolderMenuAction.moveHistory,
          icon: Icons.history,
          label: l10n.moveHistory,
          badge: moveHistoryCount,
        ),
        const PopupMenuDivider(),
        if (!isRootPage) ...[
          _row(
            value: _FolderMenuAction.rename,
            icon: Icons.edit,
            label: l10n.renameFolder,
          ),
          _row(
            value: _FolderMenuAction.move,
            icon: Icons.drive_file_move_outlined,
            label: l10n.moveToFolder,
          ),
          _row(
            value: _FolderMenuAction.share,
            icon: Icons.share_rounded,
            label: l10n.shareFolder,
          ),
        ],
        _row(
          value: _FolderMenuAction.import,
          icon: Icons.file_download_outlined,
          label: l10n.importNoteOrFolder,
        ),
        if (!isRootPage) ...[
          const PopupMenuDivider(),
          _row(
            value: _FolderMenuAction.delete,
            icon: Icons.delete,
            label: l10n.deleteFolder,
            color: colorScheme.error,
          ),
        ],
        const PopupMenuDivider(),
        _row(
          value: _FolderMenuAction.settings,
          icon: Icons.settings_outlined,
          label: l10n.settings,
        ),
      ],
    );
  }

  PopupMenuItem<_FolderMenuAction> _row({
    required _FolderMenuAction value,
    required IconData icon,
    required String label,
    Widget? trailing,
    int badge = 0,
    Color? color,
  }) {
    return PopupMenuItem<_FolderMenuAction>(
      value: value,
      child: Row(
        children: [
          badge > 0
              ? Badge(
                  label: Text('$badge'),
                  child: Icon(icon, size: 20, color: color),
                )
              : Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: color == null ? null : TextStyle(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }
}
