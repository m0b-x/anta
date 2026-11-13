import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import '../services/share_service.dart' show ShareAvailability, ShareReady;
import '../utils/share_copy.dart';
import 'form_menu_item.dart';

enum _FolderMenuAction {
  sort,
  select,
  moveHistory,
  rename,
  move,
  sharePartner,
  share,
  import,
  delete,
  settings,
}

/// A folder's "Share with {name}" entry as its page resolved it
/// (`docs/cloud-share-surfaces-roadmap.md` §6.11, §16.8): the words, whether
/// a tap does anything, the one line that says why not, and the tick of a
/// folder shared by its own mark. The menu and the row's sheet draw the
/// same value.
class FolderShareEntry {
  const FolderShareEntry({
    required this.label,
    this.enabled = true,
    this.caption,
    this.checked = false,
  });

  final String label;
  final bool enabled;
  final String? caption;
  final bool checked;

  /// The entry for [folder] while [availability] holds: absent when there
  /// is no partner or the folder is the partner's; "Shared with {name}",
  /// disabled and captioned with the folder whose mark covers it
  /// ([folderName] names it); disabled with "Turn on sync to share" while
  /// this database does not sync; else "Share with {name}", ticked as
  /// "Shared with {name}" while the folder's own mark is set.
  static FolderShareEntry? resolve(
    AppLocalizations l10n,
    Folder folder, {
    required ShareAvailability? availability,
    required String? Function(String id) folderName,
  }) {
    final audience = availability?.audience;
    if (audience == null || folder.fromPartner) return null;
    final name = ShareCopy.partnerName(l10n, audience.displayName);
    final share = folder.share;
    if (share.throughFolderId case final outer?) {
      final outerName = folderName(outer);
      return FolderShareEntry(
        label: l10n.sharedWithPartner(name),
        enabled: false,
        caption: outerName == null ? null : l10n.shareThroughFolder(outerName),
      );
    }
    final ready = availability is ShareReady;
    return FolderShareEntry(
      label: share.isByMark
          ? l10n.sharedWithPartner(name)
          : l10n.shareWithPartner(name),
      enabled: ready,
      caption: ready ? null : l10n.shareNeedsSync,
      checked: share.isByMark,
    );
  }
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
    this.readOnly = false,
    this.partnerShare,
    this.onPartnerShare,
    this.beforeOpen,
  });

  final bool isRootPage;

  /// The page shows the partner's folder: every entry that writes — and
  /// Select, which leads only to writes — is drawn disabled, not hidden; the
  /// line under the page's bar says why (§16.8 fb).
  final bool readOnly;

  /// The share entry, drawn directly above "Send a copy"; null leaves it
  /// out — not paired, or the partner's folder (§16.8 fe).
  final FolderShareEntry? partnerShare;
  final VoidCallback? onPartnerShare;

  /// Run before the menu opens, while the page does not yet know whether
  /// the database is paired: the menu then opens once it knows, with its
  /// share entry in place, and never changes height while open.
  final Future<void> Function()? beforeOpen;

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

    return _OpensWhenReady<_FolderMenuAction>(
      beforeOpen: beforeOpen,
      button: (key) => _menuButton(key, l10n, colorScheme),
    );
  }

  PopupMenuButton<_FolderMenuAction> _menuButton(
    Key key,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return PopupMenuButton<_FolderMenuAction>(
      key: key,
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
          case _FolderMenuAction.sharePartner:
            onPartnerShare?.call();
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
          enabled: !readOnly,
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
            enabled: !readOnly,
          ),
          _row(
            colorScheme,
            value: _FolderMenuAction.move,
            icon: Icons.drive_file_move_outlined,
            label: l10n.moveToFolder,
            enabled: !readOnly,
          ),
          if (partnerShare case final entry?) _partnerShareRow(entry),
          _row(
            colorScheme,
            value: _FolderMenuAction.share,
            icon: Icons.share_rounded,
            label: l10n.shareFolder,
            enabled: !readOnly,
          ),
        ],
        _row(
          colorScheme,
          value: _FolderMenuAction.import,
          icon: Icons.file_download_outlined,
          label: l10n.importNoteOrFolder,
          enabled: !readOnly,
        ),
        if (!isRootPage) ...[
          const PopupMenuDivider(height: AppTheme.menuDividerHeight),
          _row(
            colorScheme,
            value: _FolderMenuAction.delete,
            icon: Icons.delete,
            label: l10n.deleteFolder,
            // A disabled Delete reads as off, not as a danger.
            color: readOnly ? null : colorScheme.error,
            enabled: !readOnly,
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
    bool enabled = true,
  }) {
    return PopupMenuItem<_FolderMenuAction>(
      value: value,
      enabled: enabled,
      height: AppTheme.menuItemHeight,
      child: Row(
        children: [
          Icon(
            icon,
            size: AppTheme.menuIconSize,
            // A disabled row's glyph dims with its label, as the note
            // menu's does.
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
          if (count > 0) ...[
            const SizedBox(width: 12),
            MenuCountPill(count: count),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 12),
            // Gives way at large text rather than pushing the row past the
            // menu's width.
            Flexible(
              child: Text(
                trailing,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTheme.menuTrailingSize,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The share entry in the menu's own anatomy, its caption at full
  /// strength and its tick in `primary` ([FormMenuItemRow]).
  PopupMenuItem<_FolderMenuAction> _partnerShareRow(FolderShareEntry entry) {
    return PopupMenuItem<_FolderMenuAction>(
      value: _FolderMenuAction.sharePartner,
      enabled: entry.enabled,
      height: AppTheme.menuItemHeight,
      child: IconTheme.merge(
        data: IconThemeData(
          opacity: entry.enabled ? 1 : FormMetrics.disabledOpacity,
        ),
        child: FormMenuItemRow(
          identifier: SemanticsIds.folderMenuShare,
          icon: Icons.group_rounded,
          label: entry.label,
          caption: entry.caption,
          checked: entry.checked,
          enabled: entry.enabled,
        ),
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

/// A popup menu button that, while [beforeOpen] is set, runs it on a tap
/// and opens the menu only after the frame that follows it — so the items
/// are built from what it learned. The button's own tap and its semantics
/// tap are both routed through it; without [beforeOpen] the button is
/// itself, untouched.
class _OpensWhenReady<T> extends StatefulWidget {
  const _OpensWhenReady({required this.beforeOpen, required this.button});

  final Future<void> Function()? beforeOpen;
  final PopupMenuButton<T> Function(Key key) button;

  @override
  State<_OpensWhenReady<T>> createState() => _OpensWhenReadyState<T>();
}

class _OpensWhenReadyState<T> extends State<_OpensWhenReady<T>> {
  final GlobalKey<PopupMenuButtonState<T>> _key = GlobalKey();
  bool _opening = false;

  Future<void> _open() async {
    final beforeOpen = widget.beforeOpen;
    if (_opening || beforeOpen == null) return;
    _opening = true;
    try {
      await beforeOpen();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) _key.currentState?.showButtonMenu();
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asking = widget.beforeOpen != null;
    return Stack(
      children: [
        ExcludeSemantics(excluding: asking, child: widget.button(_key)),
        if (asking)
          Positioned.fill(
            child: Semantics(
              button: true,
              label: MaterialLocalizations.of(context).showMenuTooltip,
              onTap: _open,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _open,
              ),
            ),
          ),
      ],
    );
  }
}
