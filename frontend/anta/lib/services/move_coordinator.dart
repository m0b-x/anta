import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/folder.dart' as model;
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/folder_picker_dialog.dart';
import 'folder_storage_service.dart';
import 'move_history_service.dart';
import 'note_storage_service.dart';
import 'recent_destinations_service.dart';

/// Outcome of a single move attempt within a batch.
class _MoveOutcome {
  final MovableItemRef ref;
  final bool success;
  final String? entryId;
  final String? skipReason;

  const _MoveOutcome.success(this.ref, this.entryId)
    : success = true,
      skipReason = null;
  const _MoveOutcome.failure(this.ref)
    : success = false,
      entryId = null,
      skipReason = 'failure';
  const _MoveOutcome.skipped(this.ref, this.skipReason)
    : success = false,
      entryId = null;
}

/// Single entry point for every move flow in the app:
///  - Single-item move via menu     → [moveFolder] / [moveNote]
///  - Batch move (selection mode)   → [moveItems]
///  - Drag-and-drop drop on folder  → [moveItemsTo]
///  - Undo from snackbar / sheet    → [undoEntry] / [undoEntryById] / [undoBatch]
///
/// Keeps history, recents, exclusion rules (no-self, no-descendants),
/// snackbars, and undo recovery in one place so call sites stay tiny.
class MoveCoordinator {
  const MoveCoordinator._();

  static const _uuid = Uuid();

  static FolderStorageService get _folderService =>
      GetIt.I<FolderStorageService>();
  static NoteStorageService get _noteService => GetIt.I<NoteStorageService>();
  static MoveHistoryService get _historyService =>
      GetIt.I<MoveHistoryService>();
  static RecentDestinationsService get _recents =>
      GetIt.I<RecentDestinationsService>();

  // ─────────────────────────────────────────────────────────────────────
  // Public: single-item entry points (kept for menu actions)
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> moveFolder(
    BuildContext context, {
    required model.Folder folder,
    required String? currentParentId,
  }) {
    return moveItems(
      context,
      items: [
        MovableItemRef(
          kind: MovableItemKind.folder,
          id: folder.id,
          name: folder.name,
          currentParentId: currentParentId,
        ),
      ],
    );
  }

  static Future<void> moveNote(
    BuildContext context, {
    required NoteMetadata metadata,
    required String currentFolderId,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final name = metadata.title.isEmpty ? l10n.untitledNote : metadata.title;
    return moveItems(
      context,
      items: [
        MovableItemRef(
          kind: MovableItemKind.note,
          id: metadata.id,
          name: name,
          currentParentId: currentFolderId,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Public: batch entry — used by selection mode AND drag-and-drop
  // ─────────────────────────────────────────────────────────────────────

  /// Open the folder picker, then move every [items] entry to the chosen
  /// destination. If [items] is empty, no-op.
  static Future<void> moveItems(
    BuildContext context, {
    required List<MovableItemRef> items,
  }) async {
    if (items.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    // Collect ids to exclude from the picker:
    //  - every selected folder (can't move into itself)
    //  - every descendant of every selected folder (no cycles)
    //  - notes don't constrain anything beyond themselves
    final excludeIds = <String>{};
    bool anyFolder = false;
    bool anyNote = false;
    for (final ref in items) {
      if (ref.kind == MovableItemKind.folder) {
        anyFolder = true;
        excludeIds.add(ref.id);
        excludeIds.addAll(await _folderService.getDescendantIds(ref.id));
      } else {
        anyNote = true;
      }
    }
    if (!context.mounted) return;

    // Notes can't live at root — if any note is in the batch, disallow root.
    final allowRoot = !anyNote;

    // Use the first item's current parent as the picker's "current" hint.
    final currentHint = items.first.currentParentId ?? '';

    final picked = await showFolderPickerDialog(
      context,
      currentFolderId: currentHint,
      excludeFolderIds: excludeIds,
      allowRoot: allowRoot,
    );
    if (picked == null || !context.mounted) return;

    final targetParentId = picked.isEmpty ? null : picked;
    if (!allowRoot && targetParentId == null) return; // safety net

    // Discard an explicit pick of a folder that's the same as the only item's
    // current parent — nothing to do.
    if (items.every((i) => (i.currentParentId ?? '') == picked)) {
      CustomSnackbar.show(context, l10n.alreadyInThisFolder);
      return;
    }

    await moveItemsTo(
      context,
      items: items,
      targetParentId: targetParentId,
      // Hint for snackbar wording.
      isFolderTypeHint: anyFolder && !anyNote,
    );
  }

  /// Move every [items] entry to [targetParentId] without prompting. Used by
  /// drag-and-drop where the destination is already known.
  static Future<void> moveItemsTo(
    BuildContext context, {
    required List<MovableItemRef> items,
    required String? targetParentId,
    bool isFolderTypeHint = false,
  }) async {
    if (items.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;

    // Resolve target folder name once.
    final targetName = targetParentId == null
        ? null
        : (await _folderService.getFolderById(targetParentId))?.name;
    if (!context.mounted) return;

    final batchId = items.length > 1 ? _uuid.v4() : null;
    final outcomes = <_MoveOutcome>[];

    for (final ref in items) {
      // Skip same-folder moves and self-moves silently.
      if ((ref.currentParentId ?? '') == (targetParentId ?? '')) {
        outcomes.add(_MoveOutcome.skipped(ref, 'same'));
        continue;
      }
      if (ref.kind == MovableItemKind.folder && ref.id == targetParentId) {
        outcomes.add(_MoveOutcome.skipped(ref, 'self'));
        continue;
      }

      // Per-parent name uniqueness: we cannot land an item in a folder
      // that already contains a sibling with the same (case-insensitive,
      // trimmed) name. Skip with a 'duplicate' reason so the snackbar can
      // tell the user how many were skipped for this reason.
      final isDuplicate = await _isDuplicateAtTarget(
        ref: ref,
        targetParentId: targetParentId,
      );
      if (isDuplicate) {
        outcomes.add(_MoveOutcome.skipped(ref, 'duplicate'));
        continue;
      }

      final sourceName = ref.currentParentId == null
          ? null
          : (await _folderService.getFolderById(ref.currentParentId!))?.name;

      final ok = await _executeMove(
        ref: ref,
        targetParentId: targetParentId,
        sourceName: sourceName,
        targetName: targetName,
        batchId: batchId,
      );
      outcomes.add(
        ok != null ? _MoveOutcome.success(ref, ok) : _MoveOutcome.failure(ref),
      );
    }

    if (!context.mounted) return;

    final successes = outcomes.where((o) => o.success).toList();
    final failures = outcomes
        .where((o) => !o.success && o.skipReason == 'failure')
        .length;
    final duplicates = outcomes
        .where((o) => !o.success && o.skipReason == 'duplicate')
        .length;

    if (successes.isEmpty) {
      // Either everything was a no-op or everything failed.
      if (failures > 0) {
        CustomSnackbar.showError(
          context,
          isFolderTypeHint ? l10n.folderMoveFailed : l10n.noteMoveFailed,
        );
      } else if (duplicates > 0) {
        CustomSnackbar.showError(
          context,
          l10n.moveSkippedDueToDuplicates(duplicates),
        );
      } else {
        CustomSnackbar.show(context, l10n.alreadyInThisFolder);
      }
      return;
    }

    // Track the destination as a recent (only on success).
    _recents.record(targetParentId);

    // Compose the snackbar message + undo action.
    final message = successes.length == 1
        ? (successes.first.ref.kind == MovableItemKind.folder
              ? l10n.folderMoved
              : l10n.noteMoved)
        : l10n.itemsMoved(successes.length);

    if (batchId != null) {
      CustomSnackbar.showWithAction(
        context,
        message: message,
        actionLabel: l10n.undo,
        onAction: () => undoBatch(context, batchId),
      );
    } else {
      final entryId = successes.first.entryId!;
      CustomSnackbar.showWithAction(
        context,
        message: message,
        actionLabel: l10n.undo,
        onAction: () => undoEntryById(context, entryId),
      );
    }

    if (failures > 0) {
      // Surface partial failure as an extra error snackbar.
      CustomSnackbar.showError(
        context,
        isFolderTypeHint ? l10n.folderMoveFailed : l10n.noteMoveFailed,
      );
    }
    if (duplicates > 0 && context.mounted) {
      CustomSnackbar.showError(
        context,
        l10n.moveSkippedDueToDuplicates(duplicates),
      );
    }
  }

  /// Returns true if landing [ref] under [targetParentId] would create a
  /// sibling with a duplicate name. Used to bail out of a move before any
  /// DB write so the snackbar can explain the skip.
  ///
  /// Notes can't live at root (callers reject that earlier), so when
  /// [targetParentId] is null the only remaining concern is folders, which
  /// are checked against root-level siblings.
  static Future<bool> _isDuplicateAtTarget({
    required MovableItemRef ref,
    required String? targetParentId,
  }) async {
    if (ref.name.trim().isEmpty) return false;
    if (ref.kind == MovableItemKind.folder) {
      return _folderService.folderNameExistsInParent(
        parentId: targetParentId,
        name: ref.name,
        excludeId: ref.id,
      );
    }
    if (targetParentId == null) return false;
    return _noteService.noteTitleExistsInFolder(
      folderId: targetParentId,
      title: ref.name,
      excludeId: ref.id,
    );
  }

  /// Execute a single move (folder or note). Returns the history entry id
  /// on success, null on failure.
  static Future<String?> _executeMove({
    required MovableItemRef ref,
    required String? targetParentId,
    required String? sourceName,
    required String? targetName,
    required String? batchId,
  }) async {
    if (ref.kind == MovableItemKind.folder) {
      // Notes can never be the parent of a folder; targetParentId is a folder id or null.
      final result = await _folderService.moveFolder(
        folderId: ref.id,
        targetParentId: targetParentId,
      );
      if (result == null) return null;
      return _historyService.addMove(
        itemType: MoveItemType.folder,
        itemId: ref.id,
        itemName: ref.name,
        sourceParentId: ref.currentParentId,
        sourceParentName: sourceName,
        targetParentId: targetParentId,
        targetParentName: targetName,
        batchId: batchId,
      );
    } else {
      // Notes cannot live at root.
      if (targetParentId == null) return null;
      final result = await _noteService.moveNote(
        noteId: ref.id,
        targetFolderId: targetParentId,
      );
      if (result == null) return null;
      return _historyService.addMove(
        itemType: MoveItemType.note,
        itemId: ref.id,
        itemName: ref.name,
        sourceParentId: ref.currentParentId,
        sourceParentName: sourceName,
        targetParentId: targetParentId,
        targetParentName: targetName,
        batchId: batchId,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Public: undo
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> undoEntryById(
    BuildContext context,
    String entryId,
  ) async {
    final entry = _historyService.history
        .where((e) => e.id == entryId)
        .firstOrNull;
    if (entry == null) return;
    return undoEntry(context, entry);
  }

  static Future<void> undoEntry(
    BuildContext context,
    MoveHistoryEntry entry,
  ) async {
    if (_historyService.isEntryUndone(entry.id)) return;

    switch (entry.itemType) {
      case MoveItemType.folder:
        await _undoFolderMove(context, entry);
      case MoveItemType.note:
        await _undoNoteMove(context, entry);
    }
  }

  /// Undo every entry in [batchId]. Stops at the first failure and reports
  /// it; entries already undone are skipped.
  static Future<void> undoBatch(BuildContext context, String batchId) async {
    final l10n = AppLocalizations.of(context)!;
    final ids = _historyService.entryIdsInBatch(batchId);
    if (ids.isEmpty) return;

    int undoneCount = 0;
    for (final id in ids) {
      if (!context.mounted) return;
      final entry = _historyService.history
          .where((e) => e.id == id)
          .firstOrNull;
      if (entry == null || entry.isUndone) continue;
      final ok = await _undoOneSilently(entry);
      if (ok) undoneCount++;
    }

    if (!context.mounted) return;
    if (undoneCount == ids.length) {
      CustomSnackbar.show(context, l10n.moveUndone);
    } else if (undoneCount > 0) {
      CustomSnackbar.show(context, l10n.moveUndone);
    } else {
      CustomSnackbar.showError(context, l10n.folderMoveFailed);
    }
  }

  /// Internal: like [_undoFolderMove]/[_undoNoteMove] but without snackbars,
  /// for use inside batch undo. Falls back to root if the source location
  /// is gone (no interactive prompt for batches).
  static Future<bool> _undoOneSilently(MoveHistoryEntry entry) async {
    String? destination = entry.sourceParentId;
    if (destination != null) {
      final exists = await _folderService.getFolderById(destination);
      if (exists == null) destination = null; // fall back to root
    }

    if (entry.itemType == MoveItemType.folder) {
      final result = await _folderService.moveFolder(
        folderId: entry.itemId,
        targetParentId: destination,
      );
      if (result == null) return false;
    } else {
      // Notes need a folder; if root fell through, try the first available folder.
      destination ??= await _firstAvailableFolderId();
      if (destination == null) return false;
      final result = await _noteService.moveNote(
        noteId: entry.itemId,
        targetFolderId: destination,
      );
      if (result == null) return false;
    }
    _historyService.markUndone(entry.id);
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Internal: single-entry undo with interactive recovery.
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> _undoFolderMove(
    BuildContext context,
    MoveHistoryEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    String? destination = entry.sourceParentId;

    if (destination != null) {
      final exists = await _folderService.getFolderById(destination);
      if (exists == null) {
        if (!context.mounted) return;
        CustomSnackbar.show(context, l10n.originalLocationGone);
        final descendantIds = await _folderService.getDescendantIds(
          entry.itemId,
        );
        if (!context.mounted) return;
        final picked = await showFolderPickerDialog(
          context,
          currentFolderId: '',
          excludeFolderIds: {entry.itemId, ...descendantIds},
        );
        destination = (picked == null || picked.isEmpty) ? null : picked;
      }
    }

    if (!context.mounted) return;

    final result = await _folderService.moveFolder(
      folderId: entry.itemId,
      targetParentId: destination,
    );
    if (!context.mounted) return;

    if (result == null) {
      CustomSnackbar.showError(context, l10n.folderMoveFailed);
      return;
    }

    _historyService.markUndone(entry.id);
    CustomSnackbar.show(context, l10n.moveUndone);
  }

  static Future<void> _undoNoteMove(
    BuildContext context,
    MoveHistoryEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    String? destination = entry.sourceParentId;

    final needsPrompt =
        destination == null ||
        (await _folderService.getFolderById(destination)) == null;

    if (needsPrompt) {
      if (!context.mounted) return;
      CustomSnackbar.show(context, l10n.originalLocationGone);
      if (!context.mounted) return;
      final picked = await showFolderPickerDialog(
        context,
        currentFolderId: '',
        allowRoot: false,
      );
      if (picked == null || picked.isEmpty) {
        destination = await _firstAvailableFolderId();
        if (destination == null) {
          if (context.mounted) {
            CustomSnackbar.show(context, l10n.moveUndoCanceled);
          }
          return;
        }
      } else {
        destination = picked;
      }
    }

    if (!context.mounted) return;

    final result = await _noteService.moveNote(
      noteId: entry.itemId,
      targetFolderId: destination,
    );
    if (!context.mounted) return;

    if (result == null) {
      CustomSnackbar.showError(context, l10n.noteMoveFailed);
      return;
    }

    _historyService.markUndone(entry.id);
    CustomSnackbar.show(context, l10n.moveUndone);
  }

  static Future<String?> _firstAvailableFolderId() async {
    final rootFolders = await _folderService.loadAllFoldersForParent(null);
    if (rootFolders.isNotEmpty) return rootFolders.first.id;
    return null;
  }
}
