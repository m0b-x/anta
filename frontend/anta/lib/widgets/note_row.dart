import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../constants/label_appearance.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/selection_controller.dart';
import '../controllers/shared_note_copy.dart';
import '../l10n/app_localizations.dart';
import '../models/label_style.dart';
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../models/partner_look.dart';
import '../services/app_navigator.dart';
import '../services/move_coordinator.dart';
import '../services/note_storage_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/share_copy.dart';
import 'app_dialogs.dart';
import 'content_rows.dart';
import 'label_dot.dart';
import 'label_swatch_strip.dart';
import 'note_export_dialog.dart';
import 'row_share_mark.dart';

/// How a row says when a note was last touched.
///
/// Pure, and [now] is a parameter rather than a clock read, so the wording
/// can be table-tested across the boundaries it turns on. The near past is
/// named rather than dated — a date is only useful once "which day was that"
/// stops being obvious.
String formatRowDate({
  required DateTime date,
  required DateTime now,
  required String locale,
  required AppLocalizations l10n,
}) {
  final days = DateUtils.dateOnly(
    now,
  ).difference(DateUtils.dateOnly(date)).inDays;
  if (days == 0) return l10n.today;
  if (days == 1) return l10n.yesterday;
  if (days > 1 && days <= 6) return DateFormat.E(locale).format(date);
  if (date.year == now.year) return DateFormat.MMMd(locale).format(date);
  return DateFormat.yMMMd(locale).format(date);
}

/// One note in the browser's list.
///
/// The second line is the edit date, joined to the stored preview when
/// [showPreview] is on. The preview text is used as the note service produced
/// it — a money-ledger line keeps whatever figures it was stored with, and
/// nothing here re-parses it.
class NoteRow extends StatelessWidget {
  final NoteMetadata metadata;
  final String folderId;
  final RowGroupPosition groupPosition;
  final bool showPreview;
  final VoidCallback onReturn;
  final bool isReorderMode;
  final int? index;
  final bool isMultiDragging;

  /// The folder chain this note lives under, drawn as an eyebrow above the
  /// title.
  ///
  /// Null in a folder listing, where every row shares one folder and the lane
  /// would say the same thing on every row. An **empty string** is not the
  /// same as null: it reserves the lane while the ancestor walk is still
  /// running, so a late answer fills it in rather than resizing the row.
  final String? pathLabel;

  final SelectionController? selection;
  final void Function(MovableItemRef ref)? onLongPressItem;
  final void Function(MovableItemRef ref)? onTapInSelection;

  /// How the page draws whose a row is ([RowShareMark]); null draws the row
  /// as it always was. Only the partner's note is marked: a note of mine in
  /// a shared folder is not, its folder is.
  final PartnerLook? partnerLook;

  const NoteRow({
    super.key,
    required this.metadata,
    required this.folderId,
    required this.groupPosition,
    required this.onReturn,
    this.pathLabel,
    this.showPreview = true,
    this.isReorderMode = false,
    this.index,
    this.isMultiDragging = false,
    this.selection,
    this.onLongPressItem,
    this.onTapInSelection,
    this.partnerLook,
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

  /// Every row subscribes, labelled or not: the root widget is then the same
  /// type whatever the label, so giving a note its first label rebuilds the
  /// row in place instead of remounting it (which would drop an in-flight
  /// drag over it). A style flip rebuilds the visible rows once, which a
  /// list this size does not notice.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LabelStyle>(
      valueListenable: LabelAppearance.style,
      builder: (context, style, _) => _buildRow(
        context,
        LabelRowDecoration.resolve(
          context,
          label: metadata.label,
          style: style,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, LabelRowDecoration decoration) {
    final l10n = AppLocalizations.of(context)!;
    final ref = _refFor(context);
    final isSelecting = selection != null && selection!.isActive;
    final isSelected = selection != null && selection!.contains(ref);
    final colorScheme = Theme.of(context).colorScheme;
    final path = pathLabel;
    final mark = RowShareMark.forNote(metadata, partnerLook, l10n);
    Widget labelled(Widget content) => mark?.labelled(content) ?? content;

    final row = ContentRowShell(
      position: groupPosition,
      isSelected: isSelected,
      edgeStripe: decoration.stripeColor,
      edgeStripeSemantics: decoration.stripeSemantics,
      child: InkWell(
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
          } else {
            _showActionSheet(context);
          }
        },
        child: labelled(
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: RowMetrics.twoLineMinHeight,
            ),
            child: Padding(
              padding: RowMetrics.twoLinePadding,
              child: Row(
                children: [
                  if (isSelected) ...[
                    Icon(
                      Icons.check_circle,
                      size: RowMetrics.glyphSize,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: RowMetrics.gap),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (path != null)
                          Text(
                            path.isEmpty ? ' ' : path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: RowMetrics.pathLaneFontSize,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          metadata.title.isEmpty
                              ? l10n.untitledNote
                              : metadata.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: RowMetrics.titleFontSize,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: RowMetrics.lineGap),
                        _buildSecondLine(context, l10n, colorScheme, mark),
                      ],
                    ),
                  ),
                  if (decoration.showsDot) ...[
                    const SizedBox(width: RowMetrics.gap),
                    LabelDot(label: metadata.label),
                  ],
                  if (isReorderMode) ...[
                    const SizedBox(width: RowMetrics.gap),
                    Semantics(
                      container: true,
                      identifier: SemanticsIds.browserDragHandle(index ?? 0),
                      child: ReorderableDragStartListener(
                        index: index ?? 0,
                        child: Icon(
                          Icons.drag_handle,
                          size: RowMetrics.glyphSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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

    // A container, not a merge: the drag handle stays a node of its own.
    return Semantics(
      container: true,
      identifier: SemanticsIds.browserRow(metadata.id),
      child: result,
    );
  }

  /// The date, then the preview it introduces. One [Text.rich] rather than
  /// two widgets so the pair shares a single line and a single ellipsis: the
  /// date is what the row always says, and the preview is what fills whatever
  /// is left of the line. The partner's face, when [mark] draws one, leads
  /// it.
  Widget _buildSecondLine(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    RowShareMark? mark,
  ) {
    final date = formatRowDate(
      date: metadata.updatedAt,
      now: DateTime.now(),
      locale: Localizations.localeOf(context).toString(),
      l10n: l10n,
    );
    final preview = showPreview
        ? metadata.preview
              .split('\n')
              .map((line) => line.trim())
              .firstWhere((line) => line.isNotEmpty, orElse: () => '')
        : '';

    return Text.rich(
      TextSpan(
        children: [
          ?mark?.inlineFace(),
          TextSpan(
            text: date,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          if (preview.isNotEmpty) TextSpan(text: ' · $preview'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: RowMetrics.secondLineFontSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// The rename / move / share / delete sheet a long-press raises, with
  /// *Select* at the top where the page offers a selection mode — the row's
  /// own menu button is gone, so this is the only way into either.
  /// The partner's note raises the same sheet with every write disabled and
  /// the reason at its top in place of the colour strip (§16.8), and one
  /// act of its own: "Copy to my notes" (ff).
  void _showActionSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enterSelection = onLongPressItem;
    final ref = _refFor(context);
    final theirs = metadata.fromPartner;
    showRowActionSheet(
      context,
      title: metadata.title.isEmpty ? l10n.untitledNote : metadata.title,
      headerBuilder: (sheetContext) => theirs
          ? SharedReadOnlyLine(
              partner: partnerLook?.partner,
              text: l10n.shareOnlyPartnerChanges(
                ShareCopy.partnerName(l10n, partnerLook?.name),
              ),
              banded: false,
            )
          : LabelSwatchStrip(
              value: metadata.label,
              onChanged: (label) {
                Navigator.of(sheetContext).pop();
                if (label == metadata.label) return;
                context.read<OptimizedNoteBloc>().add(
                  SetOptimizedNoteLabel(noteId: metadata.id, label: label),
                );
              },
            ),
      actions: [
        if (enterSelection != null || theirs)
          RowAction(
            icon: Icons.check_circle_outline,
            label: l10n.select,
            identifier: SemanticsIds.rowActionSelect,
            enabled: !theirs,
            onSelected: () => enterSelection?.call(ref),
          ),
        RowAction(
          icon: Icons.edit_rounded,
          label: l10n.rename,
          enabled: !theirs,
          onSelected: () => _showRenameDialog(context),
        ),
        RowAction(
          icon: Icons.drive_file_move_outlined,
          label: l10n.moveToFolder,
          enabled: !theirs,
          onSelected: () => MoveCoordinator.moveNote(
            context,
            metadata: metadata,
            currentFolderId: folderId,
          ),
        ),
        RowAction(
          icon: Icons.share_rounded,
          label: l10n.shareNote,
          enabled: !theirs,
          onSelected: () => _showExportFormatDialog(context),
        ),
        if (theirs)
          RowAction(
            icon: Icons.content_copy_rounded,
            label: l10n.sharedNoteCopy,
            identifier: SemanticsIds.rowActionCopyToMine,
            onSelected: () => unawaited(
              copySharedNoteToMine(
                context,
                metadata,
                partnerName: partnerLook?.name,
              ),
            ),
          ),
        RowAction(
          icon: Icons.delete_rounded,
          label: l10n.delete,
          isDestructive: true,
          enabled: !theirs,
          onSelected: () => _confirmDelete(context),
        ),
      ],
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

  /// Asks first unless "Confirm before delete" is off (record D24).
  void _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = await SettingsService.getInstance();
    final confirm = await settings.getConfirmDelete();
    if (!context.mounted) return;
    if (confirm) {
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
    }
    context.read<OptimizedNoteBloc>().add(DeleteOptimizedNote(metadata.id));
  }
}
