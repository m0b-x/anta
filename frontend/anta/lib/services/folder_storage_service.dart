import '../database/database.dart';
import '../database/daos/folder_dao.dart';
import '../repositories/folder_repository.dart';
import '../models/folder.dart' as model;
import '../constants/app_constants.dart';
import 'duplicate_name_exception.dart';

enum FoldersSortOrder {
  nameAsc,
  nameDesc,
  createdAsc,
  createdDesc,
  positionAsc,
  positionDesc,
}

class PaginatedFolders {
  final List<model.Folder> folders;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasMore;

  const PaginatedFolders({
    required this.folders,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.hasMore,
  });

  PaginatedFolders copyWith({
    List<model.Folder>? folders,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    bool? hasMore,
  }) {
    return PaginatedFolders(
      folders: folders ?? this.folders,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class FolderStorageService {
  static const int defaultPageSize = AppConstants.defaultPageSize;

  final FolderRepository _repository;
  bool _isInitialized = false;

  FolderStorageService({required FolderRepository repository})
    : _repository = repository;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  Future<PaginatedFolders> loadFoldersPaginated({
    String? parentId,
    int page = 1,
    int pageSize = defaultPageSize,
    FoldersSortOrder sortOrder = FoldersSortOrder.nameAsc,
  }) async {
    await initialize();

    final totalCount = await _repository.getFolderCount(parentId);
    final totalPages = (totalCount / pageSize).ceil().clamp(
      1,
      double.maxFinite.toInt(),
    );
    final offset = (page - 1) * pageSize;

    final (sortField, ascending) = _mapSortOrder(sortOrder);

    final folders = await _repository.getFoldersPaginated(
      parentId: parentId,
      limit: pageSize,
      offset: offset,
      sortField: sortField,
      ascending: ascending,
    );

    final modelFolders = folders.map(_folderToModel).toList();

    return PaginatedFolders(
      folders: modelFolders,
      currentPage: page,
      totalPages: totalPages,
      totalCount: totalCount,
      hasMore: page < totalPages,
    );
  }

  Future<List<model.Folder>> loadAllFoldersForParent(String? parentId) async {
    await initialize();
    final folders = await _repository.getFoldersByParent(parentId);
    return folders.map(_folderToModel).toList();
  }

  /// Load every non-deleted folder (used by the folder-name index for
  /// fast cross-tree search in the picker).
  Future<List<model.Folder>> loadAllFolders() async {
    await initialize();
    final folders = await _repository.getAllFolders();
    return folders.map(_folderToModel).toList();
  }

  Future<model.Folder?> getFolderById(String folderId) async {
    await initialize();
    final folder = await _repository.getFolderById(folderId);
    return folder != null ? _folderToModel(folder) : null;
  }

  Future<int> getSubfolderCount(String folderId) async {
    await initialize();
    return _repository.getFolderCount(folderId);
  }

  Future<model.Folder> createFolder({
    required String name,
    String? parentId,
  }) async {
    await initialize();
    // Enforce per-parent name uniqueness at the data-layer boundary so no
    // caller (UI dialog, sync handler, future code path) can bypass it.
    if (await folderNameExistsInParent(parentId: parentId, name: name)) {
      throw DuplicateNameException(
        kind: DuplicateNameKind.folder,
        name: name.trim(),
        parentId: parentId,
      );
    }
    final folder = await _repository.createFolder(
      name: name,
      parentId: parentId,
    );
    return _folderToModel(folder);
  }

  /// Service-level entry point for the import pipeline. Performs the same
  /// uniqueness check as [createFolder] but routes through
  /// [FolderRepository.importFolder] so the original `createdAt` and
  /// per-folder sort preferences from the source archive are preserved.
  Future<model.Folder> importFolder({
    required String name,
    String? parentId,
    required DateTime createdAt,
    String? noteSortOrder,
    String? subfolderSortOrder,
  }) async {
    await initialize();
    if (await folderNameExistsInParent(parentId: parentId, name: name)) {
      throw DuplicateNameException(
        kind: DuplicateNameKind.folder,
        name: name.trim(),
        parentId: parentId,
      );
    }
    final folder = await _repository.importFolder(
      name: name,
      parentId: parentId,
      createdAt: createdAt,
      noteSortOrder: noteSortOrder,
      subfolderSortOrder: subfolderSortOrder,
    );
    return _folderToModel(folder);
  }

  Future<model.Folder?> updateFolder({
    required String folderId,
    String? name,
    String? parentId,
  }) async {
    await initialize();
    // Only run the uniqueness check when something that affects the
    // parent+name pair is actually changing. If neither name nor parent
    // is being touched there's nothing to validate.
    if (name != null || parentId != null) {
      final existing = await getFolderById(folderId);
      if (existing != null) {
        final effectiveName = name ?? existing.name;
        final effectiveParent = parentId ?? existing.parentId;
        final nameChanged =
            effectiveName.trim().toLowerCase() !=
            existing.name.trim().toLowerCase();
        final parentChanged = effectiveParent != existing.parentId;
        if (nameChanged || parentChanged) {
          if (await folderNameExistsInParent(
            parentId: effectiveParent,
            name: effectiveName,
            excludeId: folderId,
          )) {
            throw DuplicateNameException(
              kind: DuplicateNameKind.folder,
              name: effectiveName.trim(),
              parentId: effectiveParent,
            );
          }
        }
      }
    }
    final folder = await _repository.updateFolder(
      id: folderId,
      name: name,
      parentId: parentId,
      updateParent: parentId != null,
    );
    return folder != null ? _folderToModel(folder) : null;
  }

  Future<void> deleteFolder(String folderId) async {
    await initialize();
    await _repository.deleteFolder(folderId);
  }

  Future<model.Folder?> moveFolder({
    required String folderId,
    required String? targetParentId,
  }) async {
    await initialize();
    final existing = await getFolderById(folderId);
    if (existing != null && existing.parentId != targetParentId) {
      if (await folderNameExistsInParent(
        parentId: targetParentId,
        name: existing.name,
        excludeId: folderId,
      )) {
        throw DuplicateNameException(
          kind: DuplicateNameKind.folder,
          name: existing.name.trim(),
          parentId: targetParentId,
        );
      }
    }
    final folder = await _repository.moveFolder(
      folderId: folderId,
      targetParentId: targetParentId,
    );
    return folder != null ? _folderToModel(folder) : null;
  }

  Future<List<String>> getDescendantIds(String folderId) async {
    await initialize();
    return _repository.getAllDescendantIds(folderId);
  }

  /// Returns true if a non-deleted folder named [name] (case-insensitive,
  /// trimmed) already exists under [parentId]. Optionally exclude one
  /// folder id (used for rename: "is the new name taken by anything OTHER
  /// than this folder?").
  ///
  /// Backed by the `idx_folders_parent_lname` expression index, so this
  /// is an O(log n) lookup regardless of sibling count. Empty / whitespace
  /// names are never reported as duplicates so the editor and dialogs
  /// can call this even before the user has typed anything.
  Future<bool> folderNameExistsInParent({
    required String? parentId,
    required String name,
    String? excludeId,
  }) async {
    await initialize();
    return _repository.folderNameExistsInParent(
      parentId: parentId,
      name: name,
      excludeId: excludeId,
    );
  }

  /// Walks up from [folderId] to the root, returning the ancestor chain
  /// ordered from root → direct parent of [folderId]. The folder itself
  /// is NOT included. Returns an empty list when [folderId] is at root,
  /// is missing, or its chain can't be resolved.
  ///
  /// Defensive against pathological data: a `visited` set bounds the walk
  /// so a cyclic `parentId` link can't loop forever.
  Future<List<model.Folder>> getAncestors(String folderId) async {
    await initialize();
    final chain = <model.Folder>[];
    final visited = <String>{folderId};
    var current = await getFolderById(folderId);
    while (current?.parentId != null) {
      final parentId = current!.parentId!;
      if (!visited.add(parentId)) break; // cycle guard
      final parent = await getFolderById(parentId);
      if (parent == null) break;
      chain.insert(0, parent);
      current = parent;
    }
    return chain;
  }

  Stream<FolderChange> get changes => _repository.folderChanges;

  Stream<FolderChange> changesForParent(String? parentId) =>
      _repository.folderChangesForParent(parentId);

  /// Get the total note count that would be deleted with this folder
  Future<int> getNoteCountForDeletion(String folderId) async {
    await initialize();
    return _repository.getNoteCountForDeletion(folderId);
  }

  /// Reorder folders within a parent
  Future<void> reorderFolders({
    String? parentId,
    required List<String> orderedIds,
  }) async {
    await initialize();
    await _repository.reorderFolders(
      parentId: parentId,
      orderedIds: orderedIds,
    );
  }

  /// Update sort preferences for a folder
  Future<model.Folder?> updateFolderSortPreferences({
    required String folderId,
    String? noteSortOrder,
    String? subfolderSortOrder,
    bool clearNoteSortOrder = false,
    bool clearSubfolderSortOrder = false,
  }) async {
    await initialize();
    final folder = await _repository.updateFolderSortPreferences(
      id: folderId,
      noteSortOrder: noteSortOrder,
      subfolderSortOrder: subfolderSortOrder,
      clearNoteSortOrder: clearNoteSortOrder,
      clearSubfolderSortOrder: clearSubfolderSortOrder,
    );
    return folder != null ? _folderToModel(folder) : null;
  }

  model.Folder _folderToModel(Folder folder) {
    return model.Folder(
      id: folder.id,
      name: folder.name,
      parentId: folder.parentId,
      createdAt: folder.createdAt,
      noteSortOrder: folder.noteSortOrder,
      subfolderSortOrder: folder.subfolderSortOrder,
      position: folder.position,
    );
  }

  (FolderSortField, bool) _mapSortOrder(FoldersSortOrder sortOrder) {
    switch (sortOrder) {
      case FoldersSortOrder.nameAsc:
        return (FolderSortField.name, true);
      case FoldersSortOrder.nameDesc:
        return (FolderSortField.name, false);
      case FoldersSortOrder.createdAsc:
        return (FolderSortField.createdAt, true);
      case FoldersSortOrder.createdDesc:
        return (FolderSortField.createdAt, false);
      case FoldersSortOrder.positionAsc:
        return (FolderSortField.position, true);
      case FoldersSortOrder.positionDesc:
        return (FolderSortField.position, false);
    }
  }

  void invalidateCache() {
    _repository.invalidateAll();
  }
}
