import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
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

  /// Undoable moves, badged on the button itself as well as counted on its
  /// row: the whole point of the badge is to be visible before the menu
  /// opens.
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
        backgroundColor: colorScheme.primary,
        textColor: colorScheme.onPrimary,
        label: Text('$moveHistoryCount'),
        child: const Icon(Icons.more_vert),
      ),
      constraints: const BoxConstraints.tightFor(width: AppTheme.menuWidth),
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
          colorScheme,
          value: _FolderMenuAction.sort,
          icon: Icons.sort,
          label: l10n.sortBy,
          trailing: sortLabel,
        ),
        _row(
          colorScheme,
          value: _FolderMenuAction.select,
          icon: Icons.checklist_rounded,
          label: l10n.select,
        ),
        _row(
          colorScheme,
          value: _FolderMenuAction.moveHistory,
          icon: Icons.history,
          label: l10n.moveHistory,
          count: moveHistoryCount,
        ),
        const PopupMenuDivider(height: AppTheme.menuDividerHeight),
        if (!isRootPage) ...[
          _row(
            colorScheme,
            value: _FolderMenuAction.rename,
            icon: Icons.edit,
            label: l10n.renameFolder,
          ),
          _row(
            colorScheme,
            value: _FolderMenuAction.move,
            icon: Icons.drive_file_move_outlined,
            label: l10n.moveToFolder,
          ),
          _row(
            colorScheme,
            value: _FolderMenuAction.share,
            icon: Icons.share_rounded,
            label: l10n.shareFolder,
          ),
        ],
        _row(
          colorScheme,
          value: _FolderMenuAction.import,
          icon: Icons.file_download_outlined,
          label: l10n.importNoteOrFolder,
        ),
        if (!isRootPage) ...[
          const PopupMenuDivider(height: AppTheme.menuDividerHeight),
          _row(
            colorScheme,
            value: _FolderMenuAction.delete,
            icon: Icons.delete,
            label: l10n.deleteFolder,
            color: colorScheme.error,
          ),
        ],
        const PopupMenuDivider(height: AppTheme.menuDividerHeight),
        _row(
          colorScheme,
          value: _FolderMenuAction.settings,
          icon: Icons.settings_outlined,
          label: l10n.settings,
        ),
      ],
    );
  }

  PopupMenuItem<_FolderMenuAction> _row(
    ColorScheme colorScheme, {
    required _FolderMenuAction value,
    required IconData icon,
    required String label,
    String? trailing,
    int count = 0,
    Color? color,
  }) {
    return PopupMenuItem<_FolderMenuAction>(
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
          if (count > 0) ...[
            const SizedBox(width: 12),
            MenuCountPill(count: count),
          ],
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

/// The trailing count on a menu row: an 18 dp primary pill, not a red
/// notification badge hung off the leading glyph.
class MenuCountPill extends StatelessWidget {
  const MenuCountPill({super.key, required this.count});

  final int count;

  static const double height = 18.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      constraints: const BoxConstraints(minWidth: height),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.0,
          color: colorScheme.rowGroup,
        ),
      ),
    );
  }
}
