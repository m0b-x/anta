import '../models/content_item.dart';
import '../models/movable_item.dart';
import '../repositories/folder_repository.dart';
import '../repositories/note_repository.dart';

/// Single entry point for "reorder a unified list that mixes folders and
/// notes." Splits the merged ordering into two position maps (one per table)
/// using a shared global index space, then writes both via the underlying
/// repositories.
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

  MixedReorderService({
    required FolderRepository folderRepository,
    required NoteRepository noteRepository,
  }) : _folderRepository = folderRepository,
       _noteRepository = noteRepository;

  /// Persist [items] as the new merged ordering of folders and notes under
  /// [parentId]. Each item receives a global position equal to its index in
  /// [items], so a subsequent positionAsc fetch + client-side merge will
  /// reproduce exactly this order.
  ///
  /// [parentId] is required for note position writes (notes are always
  /// scoped to a folder); it may be null for the root page (folders only).
  Future<void> reorderMixed({
    required String? parentId,
    required List<ContentItem> items,
  }) async {
    final folderPositions = <String, int>{};
    final notePositions = <String, int>{};

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      switch (item.kind) {
        case MovableItemKind.folder:
          folderPositions[item.id] = i;
        case MovableItemKind.note:
          notePositions[item.id] = i;
      }
    }

    // Two writes, two transactions. Atomicity across both tables would
    // require an outer db.transaction; the data converges either way and
    // the optimistic local list bridges any visible gap.
    await _folderRepository.setFolderPositions(
      parentId: parentId,
      positionByFolderId: folderPositions,
    );
    if (notePositions.isNotEmpty) {
      // notePositions only non-empty when parentId is non-null, since notes
      // require a folder parent. Guard kept defensive.
      if (parentId == null) return;
      await _noteRepository.setNotePositions(
        folderId: parentId,
        positionByNoteId: notePositions,
      );
    }
  }
}
