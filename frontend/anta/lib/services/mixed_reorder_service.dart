import 'dart:async';

import '../models/content_item.dart';
import '../models/movable_item.dart';
import '../repositories/folder_repository.dart';
import '../repositories/note_repository.dart';
import '../utils/position_plan.dart' show spliceLoadedOrder;

/// Single entry point for "persist the order a drag left in the browser",
/// whose list shows a folder's subfolders and then its notes.
///
/// Folders and notes are ordered as separate kinds, each its own `position`
/// sequence (decision D9): the display groups folders first, so nothing reads
/// a position across the two tables. Each kind is planned and written in one
/// DAO transaction that sees the whole group, not just the loaded pages.
///
/// This keeps the layered architecture intact:
///
///   UI -> MixedReorderService -> {FolderRepository, NoteRepository} -> DAOs
///
/// Repositories continue to own cache invalidation and change emission, so
/// the existing bloc subscribers refresh transparently.
class MixedReorderService {
  final FolderRepository _folderRepository;
  final NoteRepository _noteRepository;

  /// The last write queued per parent. A second drag must not plan from a
  /// group the first has not finished writing: each plan reads the stored
  /// order, and both kinds of one drag land before the next drag's read.
  final Map<String?, Future<void>> _tails = {};

  MixedReorderService({
    required FolderRepository folderRepository,
    required NoteRepository noteRepository,
  }) : _folderRepository = folderRepository,
       _noteRepository = noteRepository;

  /// Persist [items] — the browser's loaded rows under [parentId], in the
  /// order the user left them — as the custom order of each kind.
  ///
  /// [foldersDescending] and [notesDescending] are the kinds' custom
  /// directions (`positionDesc`), so the reload reads back what was shown.
  /// [parentId] may be null for the root page, which holds folders only.
  /// [windowAtTop] names the kinds whose sort this drag just turned to
  /// Custom: their loaded rows were in another order than the positions, so
  /// they go on top of the group ([spliceLoadedOrder]).
  Future<void> reorderMixed({
    required String? parentId,
    required List<ContentItem> items,
    required bool foldersDescending,
    required bool notesDescending,
    Set<MovableItemKind> windowAtTop = const {},
  }) {
    final folderIds = [
      for (final item in items)
        if (item.kind == MovableItemKind.folder) item.id,
    ];
    final noteIds = [
      for (final item in items)
        if (item.kind == MovableItemKind.note) item.id,
    ];

    return _serialised(parentId, () async {
      if (folderIds.isNotEmpty) {
        await _folderRepository.applyOrder(
          parentId: parentId,
          loadedOrder: folderIds,
          descending: foldersDescending,
          windowAtTop: windowAtTop.contains(MovableItemKind.folder),
        );
      }
      // Notes always live in a folder, so a root page has none to write.
      if (noteIds.isNotEmpty && parentId != null) {
        await _noteRepository.applyOrder(
          folderId: parentId,
          loadedOrder: noteIds,
          descending: notesDescending,
          windowAtTop: windowAtTop.contains(MovableItemKind.note),
        );
      }
    });
  }

  Future<void> _serialised(String? parentId, Future<void> Function() write) {
    final previous = _tails[parentId] ?? Future<void>.value();
    final run = previous.then((_) => write());
    // The chain carries on past a failed write; the caller still sees it.
    final tail = run.catchError((Object _) {});
    _tails[parentId] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[parentId], tail)) _tails.remove(parentId);
      }),
    );
    return run;
  }
}
