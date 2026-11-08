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
    final outcomes = await _executeMoves(
      items: items,
      targetParentId: targetParentId,
      targetName: targetName,
      batchId: batchId,
    );

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

  /// Moves every [items] entry under [targetParentId] — the folders in one
  /// transaction, the notes in another — and records the successes in the
  /// history, one undo unit for the batch.
  ///
  /// Same-folder and self moves are skipped before any write. The rest go to
  /// the set-based moves, which decide per item: moved, a sibling already
  /// holds that name (`duplicate`, the target's or an earlier item's), or
  /// gone (`failure`). Notes cannot live at the root, so a note bound there
  /// fails.
  static Future<List<_MoveOutcome>> _executeMoves({
    required List<MovableItemRef> items,
    required String? targetParentId,
    required String? targetName,
    required String? batchId,
  }) async {
    final skipped = <MovableItemRef, String>{};
    final folderIds = <String>[];
    final noteIds = <String>[];
    for (final ref in items) {
      if ((ref.currentParentId ?? '') == (targetParentId ?? '')) {
        skipped[ref] = 'same';
      } else if (ref.kind == MovableItemKind.folder &&
          ref.id == targetParentId) {
        skipped[ref] = 'self';
      } else if (ref.kind == MovableItemKind.folder) {
        folderIds.add(ref.id);
      } else {
        noteIds.add(ref.id);
      }
    }

    final folders = folderIds.isEmpty
        ? BulkMoveResult.empty
        : await _guarded(
            () => _folderService.moveFolders(
              folderIds: folderIds,
              targetParentId: targetParentId,
            ),
          );
    final notes = noteIds.isEmpty || targetParentId == null
        ? BulkMoveResult.empty
        : await _guarded(
            () => _noteService.moveNotes(
              noteIds: noteIds,
              targetFolderId: targetParentId,
            ),
          );

    // One name lookup per distinct source folder, not one per item.
    final sourceNames = <String?, String?>{null: null};
    for (final result in [folders, notes]) {
      for (final source in result.moved.values) {
        if (sourceNames.containsKey(source)) continue;
        sourceNames[source] = (await _folderService.getFolderById(
          source!,
        ))?.name;
      }
    }

    final outcomes = <_MoveOutcome>[];
    final history = <MoveHistoryItem>[];
    for (final ref in items) {
      final reason = skipped[ref];
      if (reason != null) {
        outcomes.add(_MoveOutcome.skipped(ref, reason));
        continue;
      }
      final isFolder = ref.kind == MovableItemKind.folder;
      final result = isFolder ? folders : notes;
      if (result.moved.containsKey(ref.id)) {
        final source = result.moved[ref.id];
        history.add((
          itemType: isFolder ? MoveItemType.folder : MoveItemType.note,
          itemId: ref.id,
          itemName: ref.name,
          sourceParentId: source,
          sourceParentName: sourceNames[source],
        ));
        outcomes.add(_MoveOutcome.success(ref, null));
      } else if (result.duplicates.contains(ref.id)) {
        outcomes.add(_MoveOutcome.skipped(ref, 'duplicate'));
      } else if (result.unchanged.contains(ref.id)) {
        outcomes.add(_MoveOutcome.skipped(ref, 'same'));
      } else {
        outcomes.add(_MoveOutcome.failure(ref));
      }
    }

    if (history.isEmpty) return outcomes;
    if (batchId != null) {
      _historyService.addMoves(
        history,
        targetParentId: targetParentId,
        targetParentName: targetName,
        batchId: batchId,
      );
      return outcomes;
    }
    final item = history.single;
    final entryId = _historyService.addMove(
      itemType: item.itemType,
      itemId: item.itemId,
      itemName: item.itemName,
      sourceParentId: item.sourceParentId,
      sourceParentName: item.sourceParentName,
      targetParentId: targetParentId,
      targetParentName: targetName,
    );
    return [
      for (final outcome in outcomes)
        outcome.success ? _MoveOutcome.success(outcome.ref, entryId) : outcome,
    ];
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

  /// Undo every entry of the unit [batchId], whatever its size: each source
  /// folder takes its items back in one set-based move. No prompt for a
  /// batch — a folder whose source is gone goes back to the root, a note to
  /// the first available folder.
  ///
  /// "Move undone" is said only when the whole unit went back; otherwise the
  /// items a sibling's name kept out are counted with the move's own
  /// duplicate wording, and any other item that stayed is reported as a
  /// failed move.
  static Future<void> undoBatch(BuildContext context, String batchId) async {
    final l10n = AppLocalizations.of(context)!;
    final entries = [
      for (final entry in _historyService.history)
        if (entry.batchId == batchId && !entry.isUndone) entry,
    ];
    if (entries.isEmpty) return;

    final live = <String?, bool>{null: false};
    String? fallbackFolder;
    var fallbackLoaded = false;
    final groups = <(MoveItemType, String?), List<MoveHistoryEntry>>{};
    for (final entry in entries) {
      final source = entry.sourceParentId;
      if (!live.containsKey(source)) {
        // A tombstone is gone too: the move into it would be refused.
        live[source] =
            await _folderService.getFolderById(
              source!,
              includeDeleted: false,
            ) !=
            null;
      }
      String? destination = live[source]! ? source : null;
      if (entry.itemType == MoveItemType.note && destination == null) {
        if (!fallbackLoaded) {
          fallbackFolder = await _firstAvailableFolderId();
          fallbackLoaded = true;
        }
        destination = fallbackFolder;
      }
      groups.putIfAbsent((entry.itemType, destination), () => []).add(entry);
    }

    final restored = <String>[];
    var duplicates = 0;
    var anyFolderFailed = false;
    var anyNoteFailed = false;
    for (final MapEntry(key: (type, destination), value: group)
        in groups.entries) {
      final ids = [for (final entry in group) entry.itemId];
      final isFolder = type == MoveItemType.folder;
      final BulkMoveResult result;
      if (isFolder) {
        result = await _guarded(
          () => _folderService.moveFolders(
            folderIds: ids,
            targetParentId: destination,
          ),
        );
      } else if (destination != null) {
        final target = destination;
        result = await _guarded(
          () => _noteService.moveNotes(noteIds: ids, targetFolderId: target),
        );
      } else {
        result = BulkMoveResult.empty;
      }
      for (final entry in group) {
        final id = entry.itemId;
        if (result.moved.containsKey(id) || result.unchanged.contains(id)) {
          restored.add(entry.id);
        } else if (result.duplicates.contains(id)) {
          duplicates++;
        } else if (isFolder) {
          anyFolderFailed = true;
        } else {
          anyNoteFailed = true;
        }
      }
    }
    _historyService.markAllUndone(restored);

    if (!context.mounted) return;
    if (restored.length == entries.length) {
      CustomSnackbar.show(context, l10n.moveUndone);
      return;
    }
    if (duplicates > 0) {
      CustomSnackbar.showError(
        context,
        l10n.moveSkippedDueToDuplicates(duplicates),
      );
    }
    if (anyFolderFailed || anyNoteFailed) {
      CustomSnackbar.showError(
        context,
        anyFolderFailed ? l10n.folderMoveFailed : l10n.noteMoveFailed,
      );
    }
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

  /// Runs one set-based move, reading a database failure as "nothing moved":
  /// its items then report through the failure snackbar every other unmoved
  /// item uses, rather than the error escaping an Undo tap unseen.
  static Future<BulkMoveResult> _guarded(
    Future<BulkMoveResult> Function() move,
  ) async {
    try {
      return await move();
    } catch (e, st) {
      debugPrint('[MoveCoordinator] bulk move failed: $e\n$st');
      return BulkMoveResult.empty;
    }
  }

  static Future<String?> _firstAvailableFolderId() async {
    final rootFolders = await _folderService.loadAllFoldersForParent(null);
    if (rootFolders.isNotEmpty) return rootFolders.first.id;
    return null;
  }
}
