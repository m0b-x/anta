import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/optimized_folder/optimized_folder_bloc.dart';
import '../bloc/optimized_folder/optimized_folder_event.dart';
import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../controllers/selection_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import '../models/item_label.dart';
import '../models/movable_item.dart';
import '../services/app_navigator.dart';
import '../services/folder_storage_service.dart';
import '../services/move_coordinator.dart';
import '../utils/custom_snackbar.dart';
import 'app_dialogs.dart';
import 'content_rows.dart';
import 'label_dot.dart';
import 'label_swatch_strip.dart';

/// One folder in the browser's list.
///
/// The count is handed in rather than fetched: a page of rows used to issue
/// two queries each, and the page now reads every row's descendant-inclusive
/// note count in a single statement. A null [noteCount] means "not answered
/// yet" and draws nothing — the trailing slot keeps its width either way, so
/// a late answer moves neither the name beside it nor the rows below.
class FolderRow extends StatelessWidget {
  final Folder folder;
  final String? parentId;
  final int? noteCount;
  final RowGroupPosition groupPosition;
  final VoidCallback onReturn;
  final bool isReorderMode;
  final int? index;

  /// True while a multi-selection drag is in flight on the parent list, so a
  /// selected passenger row can dim and follow the lifted one.
  final bool isMultiDragging;

  final SelectionController? selection;
  final void Function(MovableItemRef ref)? onLongPressItem;
  final void Function(MovableItemRef ref)? onTapInSelection;
  final Future<void> Function(Folder target, Set<MovableItemRef> dropped)?
  onAcceptDrop;

  const FolderRow({
    super.key,
    required this.folder,
    required this.onReturn,
    required this.groupPosition,
    this.parentId,
    this.noteCount,
    this.isReorderMode = false,
    this.index,
    this.isMultiDragging = false,
    this.selection,
    this.onLongPressItem,
    this.onTapInSelection,
    this.onAcceptDrop,
  });

  MovableItemRef get _ref => MovableItemRef(
    kind: MovableItemKind.folder,
    id: folder.id,
    name: folder.name,
    currentParentId: parentId,
  );

  @override
  Widget build(BuildContext context) {
    final isSelecting = selection != null && selection!.isActive;
    final isSelected = selection != null && selection!.contains(_ref);
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildRow({bool isDropTarget = false}) => ContentRowShell(
      position: groupPosition,
      isSelected: isSelected,
      isDropTarget: isDropTarget,
      dividerIndent: RowMetrics.dividerIndentWithGlyph,
      child: InkWell(
        onTap: isSelecting
            ? () => onTapInSelection?.call(_ref)
            : () {
                AppNavigator.toFolder(
                  context,
                  folderId: folder.id,
                  title: folder.name,
                ).then((_) {
                  if (context.mounted) onReturn();
                });
              },
        onLongPress: () {
          if (isSelecting) {
            onTapInSelection?.call(_ref);
          } else {
            _showActionSheet(context);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RowMetrics.singleLineMinHeight,
          ),
          child: Padding(
            padding: RowMetrics.singleLinePadding,
            child: Row(
              children: [
                isSelected
                    ? Icon(
                        Icons.check_circle,
                        size: RowMetrics.glyphSize,
                        color: colorScheme.primary,
                      )
                    : Icon(
                        Icons.folder_outlined,
                        size: RowMetrics.glyphSize,
                        color: AppColors.folderIcon(context),
                      ),
                const SizedBox(width: RowMetrics.gap),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: RowMetrics.titleFontSize,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: RowMetrics.gap),
                _buildTrailing(context),
              ],
            ),
          ),
        ),
      ),
    );

    Widget wrapDraggable(Widget row) {
      if (!(isSelecting && isSelected)) return row;
      return LongPressDraggable<Set<MovableItemRef>>(
        data: selection!.items,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          color: Colors.transparent,
          child: DragFeedbackChip(count: selection!.count),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: row),
        child: row,
      );
    }

    Widget result = wrapDraggable(buildRow());

    if (onAcceptDrop != null) {
      final idle = result;
      result = DragTarget<Set<MovableItemRef>>(
        onWillAcceptWithDetails: (details) => !details.data.any(
          (r) => r.kind == MovableItemKind.folder && r.id == folder.id,
        ),
        onAcceptWithDetails: (details) => onAcceptDrop!(folder, details.data),
        builder: (context, candidate, rejected) {
          if (candidate.isEmpty) return idle;
          return wrapDraggable(buildRow(isDropTarget: true));
        },
      );
    }

    if (isMultiDragging && isSelected) {
      result = AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: 0.96,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: 0.55,
          child: result,
        ),
      );
    }

    return result;
  }

  Widget _buildTrailing(BuildContext context) {
    final trailing = isReorderMode
        ? ReorderableDragStartListener(
            index: index ?? 0,
            child: Icon(
              Icons.drag_handle,
              size: RowMetrics.glyphSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        : RowCountChevron(count: noteCount);

    if (folder.label == ItemLabel.none) return trailing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LabelDot(label: folder.label),
        const SizedBox(width: RowMetrics.gap),
        trailing,
      ],
    );
  }

  /// The rename / move / share / delete sheet a long-press raises, with
  /// *Select* at the top where the page offers a selection mode — the row's
  /// own menu button is gone, so this is the only way into either.
  void _showActionSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enterSelection = onLongPressItem;
    showRowActionSheet(
      context,
      title: folder.name,
      headerBuilder: (sheetContext) => LabelSwatchStrip(
        value: folder.label,
        onChanged: (label) {
          Navigator.of(sheetContext).pop();
          if (label == folder.label) return;
          context.read<OptimizedFolderBloc>().add(
            SetOptimizedFolderLabel(folderId: folder.id, label: label),
          );
        },
      ),
      actions: [
        if (enterSelection != null)
          RowAction(
            icon: Icons.check_circle_outline,
            label: l10n.select,
            onSelected: () => enterSelection(_ref),
          ),
        RowAction(
          icon: Icons.edit_rounded,
          label: l10n.rename,
          onSelected: () => _showRenameDialog(context),
        ),
        RowAction(
          icon: Icons.drive_file_move_outlined,
          label: l10n.moveToFolder,
          onSelected: () => MoveCoordinator.moveFolder(
            context,
            folder: folder,
            currentParentId: parentId,
          ),
        ),
        RowAction(
          icon: Icons.share_rounded,
          label: l10n.shareFolder,
          onSelected: () => context.read<ImportExportBloc>().add(
            ExportFolderRequested(folderId: folder.id, share: true),
          ),
        ),
        RowAction(
          icon: Icons.delete_rounded,
          label: l10n.delete,
          isDestructive: true,
          onSelected: () => _confirmDelete(context),
        ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await AppDialogs.textInput(
      context,
      title: l10n.renameFolder,
      hintText: l10n.enterNewName,
      initialValue: folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;
    final trimmed = name.trim();
    if (trimmed.toLowerCase() == folder.name.trim().toLowerCase()) return;
    final exists = await GetIt.I<FolderStorageService>()
        .folderNameExistsInParent(
          parentId: parentId,
          name: trimmed,
          excludeId: folder.id,
        );
    if (!context.mounted) return;
    if (exists) {
      CustomSnackbar.showError(context, l10n.folderNameAlreadyExists(trimmed));
      return;
    }
    context.read<OptimizedFolderBloc>().add(
      UpdateOptimizedFolder(folderId: folder.id, name: trimmed),
    );
  }

  void _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    AppDialogs.showLoading(context, message: l10n.loadingContent);
    final noteCount = await GetIt.I<FolderStorageService>()
        .getNoteCountForDeletion(folder.id);
    if (!context.mounted) return;
    AppNavigator.pop(context);

    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteFolder,
      content: noteCount > 0
          ? l10n.deleteFolderWithNotesConfirm(folder.name, noteCount)
          : l10n.deleteFolderConfirm(folder.name),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    context.read<OptimizedFolderBloc>().add(
      DeleteOptimizedFolder(folderId: folder.id, parentId: parentId),
    );
  }
}
