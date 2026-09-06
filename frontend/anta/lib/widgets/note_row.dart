import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../constants/note_card_action.dart';
import '../controllers/selection_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../services/app_navigator.dart';
import '../services/move_coordinator.dart';
import '../services/note_storage_service.dart';
import '../utils/custom_snackbar.dart';
import 'app_dialogs.dart';
import 'content_rows.dart';
import 'note_export_dialog.dart';

/// One note in the browser's list.
///
/// The second line is the edit date, joined to the first line of the stored
/// preview when [showPreview] is on. The preview text is used as the note
/// service produced it — a money-ledger line keeps whatever figures it was
/// stored with, and nothing here re-parses it.
class NoteRow extends StatelessWidget {
  final NoteMetadata metadata;
  final String folderId;
  final RowGroupPosition groupPosition;
  final bool showPreview;
  final VoidCallback onReturn;
  final bool isReorderMode;
  final int? index;
  final bool isMultiDragging;

  final SelectionController? selection;
  final void Function(MovableItemRef ref)? onLongPressItem;
  final void Function(MovableItemRef ref)? onTapInSelection;

  const NoteRow({
    super.key,
    required this.metadata,
    required this.folderId,
    required this.groupPosition,
    required this.onReturn,
    this.showPreview = true,
    this.isReorderMode = false,
    this.index,
    this.isMultiDragging = false,
    this.selection,
    this.onLongPressItem,
    this.onTapInSelection,
  });

  MovableItemRef _refFor(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MovableItemRef(
      kind: MovableItemKind.note,
      id: metadata.id,
      name: metadata.title.isEmpty ? l10n.untitledNote : metadata.title,
      currentParentId: folderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = _refFor(context);
    final isSelecting = selection != null && selection!.isActive;
    final isSelected = selection != null && selection!.contains(ref);
    final colorScheme = Theme.of(context).colorScheme;

    final row = ContentRowShell(
      position: groupPosition,
      isSelected: isSelected,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: isSelected
            ? Icon(Icons.check_circle, color: colorScheme.primary)
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  if (metadata.isCompressed)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(
                        Icons.compress,
                        size: 12,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
        title: Text(
          metadata.title.isEmpty ? l10n.untitledNote : metadata.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          _secondLine(context, l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        trailing: _buildTrailing(context, isSelecting),
        onTap: isSelecting
            ? () => onTapInSelection?.call(ref)
            : () {
                AppNavigator.toNoteEditorInstant(
                  context,
                  folderId: folderId,
                  noteId: metadata.id,
                  metadata: metadata,
                ).then((_) {
                  if (context.mounted) onReturn();
                });
              },
        onLongPress: () {
          if (isSelecting) {
            onTapInSelection?.call(ref);
          } else if (onLongPressItem != null) {
            onLongPressItem!(ref);
          } else {
            _showOptionsBottomSheet(context);
          }
        },
      ),
    );

    Widget result = row;
    if (isSelecting && isSelected) {
      result = LongPressDraggable<Set<MovableItemRef>>(
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

  String _secondLine(BuildContext context, AppLocalizations l10n) {
    final date = _formatDate(context, metadata.updatedAt);
    if (!showPreview) return date;
    final firstLine = metadata.preview
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return date;
    return '$date  ·  $firstLine';
  }

  /// Locale-aware and compact: the time for something edited today, the day
  /// and month within this year, the full short date beyond it.
  String _formatDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return DateFormat.Hm(locale).format(date);
    if (date.year == now.year) return DateFormat.MMMd(locale).format(date);
    return DateFormat.yMMMd(locale).format(date);
  }

  Widget? _buildTrailing(BuildContext context, bool isSelecting) {
    if (isReorderMode) {
      return ReorderableDragStartListener(
        index: index ?? 0,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.drag_handle, color: Colors.grey),
        ),
      );
    }
    if (isSelecting) return null;
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<NoteCardAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case NoteCardAction.rename:
            _showRenameDialog(context);
          case NoteCardAction.move:
            MoveCoordinator.moveNote(
              context,
              metadata: metadata,
              currentFolderId: folderId,
            );
          case NoteCardAction.share:
            _showExportFormatDialog(context);
          case NoteCardAction.delete:
            _confirmDelete(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: NoteCardAction.rename,
          child: _menuRow(Icons.edit, l10n.rename),
        ),
        PopupMenuItem(
          value: NoteCardAction.move,
          child: _menuRow(Icons.drive_file_move_outlined, l10n.moveToFolder),
        ),
        PopupMenuItem(
          value: NoteCardAction.share,
          child: _menuRow(Icons.share, l10n.shareNote),
        ),
        PopupMenuItem(
          value: NoteCardAction.delete,
          child: _menuRow(Icons.delete, l10n.delete, isDestructive: true),
        ),
      ],
    );
  }

  Widget _menuRow(IconData icon, String label, {bool isDestructive = false}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: isDestructive ? Colors.red : null),
        const SizedBox(width: 12),
        Text(
          label,
          style: isDestructive ? const TextStyle(color: Colors.red) : null,
        ),
      ],
    );
  }

  void _showOptionsBottomSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                metadata.title.isEmpty ? l10n.untitledNote : metadata.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(l10n.rename),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _showRenameDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(l10n.moveToFolder),
              onTap: () {
                AppNavigator.pop(sheetContext);
                MoveCoordinator.moveNote(
                  context,
                  metadata: metadata,
                  currentFolderId: folderId,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text(l10n.shareNote),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _showExportFormatDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: colorScheme.error),
              title: Text(
                l10n.delete,
                style: TextStyle(color: colorScheme.error),
              ),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _confirmDelete(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showExportFormatDialog(BuildContext context) async {
    final format = await NoteExportDialog.chooseFormat(context);
    if (format == null || !context.mounted) return;
    context.read<ImportExportBloc>().add(
      ExportNoteRequested(metadata: metadata, format: format, share: true),
    );
  }

  void _showRenameDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await AppDialogs.textInput(
      context,
      title: l10n.renameNote,
      hintText: l10n.enterNewName,
      initialValue: metadata.title,
    );
    if (name == null || !context.mounted) return;
    final trimmed = name.trim();
    if (trimmed.toLowerCase() == metadata.title.trim().toLowerCase()) return;
    if (trimmed.isNotEmpty) {
      final exists = await GetIt.I<NoteStorageService>()
          .noteTitleExistsInFolder(
            folderId: folderId,
            title: trimmed,
            excludeId: metadata.id,
          );
      if (!context.mounted) return;
      if (exists) {
        CustomSnackbar.showError(context, l10n.noteTitleAlreadyExists(trimmed));
        return;
      }
    }
    context.read<OptimizedNoteBloc>().add(
      UpdateOptimizedNote(noteId: metadata.id, title: trimmed),
    );
  }

  void _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteNote,
      content: l10n.deleteNoteConfirm(
        metadata.title.isEmpty ? l10n.deleteThisNote : metadata.title,
      ),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    context.read<OptimizedNoteBloc>().add(DeleteOptimizedNote(metadata.id));
  }
}
