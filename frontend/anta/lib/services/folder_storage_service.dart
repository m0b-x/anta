import '../database/database.dart';
import '../database/daos/folder_dao.dart';
import '../database/daos/shared_row_dao.dart' show SharedRowException;
import '../repositories/folder_repository.dart';
import '../models/folder.dart' as model;
import '../models/item_label.dart';
import '../models/movable_item.dart';
import '../models/partner_folder_sort.dart';
import '../constants/app_constants.dart';
import 'duplicate_name_exception.dart';
import 'settings_service.dart';

/// The orderings the browser offers for a folder's subfolders.
///
/// **Append only.** A folder persists its choice as the member's `name` in
/// `folders.subfolderSortOrder`, and an older build that meets a name it does
/// not know falls back to the default rather than failing — so a member may be
/// added to the end, but never renamed, reordered or removed.
enum FoldersSortOrder {
  nameAsc,
  nameDesc,
  createdAsc,
  createdDesc,
  positionAsc,
  positionDesc,

  /// Labelled folders first in palette order, unlabelled last. There is no
  /// descending twin — reversing a palette answers no question.
  labelAsc,
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
    // The root pages the person's own folders alone: the partner's are the
    // "From {name}" group's, read whole by [loadPartnerTopFolders] — paged
    // together, a page boundary would split that group (§6.12).
    final theirs = parentId == null
        ? (await _repository.shareCensus.read()).owner
        : null;

    final totalCount = await _repository.getFolderCount(
      parentId,
      excludeOwner: theirs,
    );
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
      excludeOwner: theirs,
    );

    final modelFolders = await _toModels(folders);

    return PaginatedFolders(
      folders: modelFolders,
      currentPage: page,
      totalPages: totalPages,
      totalCount: totalCount,
      hasMore: page < totalPages,
    );
  }

  /// The partner's top-level folders by name, in one statement: the
  /// browser root's "From {name}" group, whole on its first frame. Nothing
  /// is read for a database that holds no shared row — the census answers.
  Future<List<model.Folder>> loadPartnerTopFolders() async {
    await initialize();
    final owner = (await _repository.shareCensus.read()).owner;
    if (owner == null) return const [];
    return _toModels(await _repository.topFoldersOf(owner));
  }

  Future<List<model.Folder>> loadAllFoldersForParent(String? parentId) async {
    await initialize();
    final folders = await _repository.getFoldersByParent(parentId);
    return _toModels(folders);
  }

  /// Load every non-deleted folder (used by the folder-name index for
  /// fast cross-tree search in the picker).
  Future<List<model.Folder>> loadAllFolders() async {
    await initialize();
    final folders = await _repository.getAllFolders();
    return _toModels(folders);
  }

  /// The live folder a note from [folderId] can be filed into: see
  /// [FolderRepository.nearestLiveFolderId].
  Future<String> nearestLiveFolderId(String folderId) async {
    await initialize();
    return _repository.nearestLiveFolderId(folderId);
  }

  /// The folder row for [folderId], or null if there is none.
  ///
  /// A soft-deleted folder is still returned by default: the row survives the
  /// delete (that is what makes it soft), and callers that hold an id — undo,
  /// move history, sync reconciliation — need to be able to see it. Pass
  /// [includeDeleted] false to ask the narrower question "is this folder still
  /// a place the user can be taken to?", which is what launch restore needs
  /// before it rebuilds a route onto it.
  Future<model.Folder?> getFolderById(
    String folderId, {
    bool includeDeleted = true,
  }) async {
    await initialize();
    final folder = await _repository.getFolderById(folderId);
    if (folder == null) return null;
    if (!includeDeleted && folder.isDeleted) return null;
    return _toModel(folder);
  }

  Future<int> getSubfolderCount(String folderId) async {
    await initialize();
    return _repository.getFolderCount(folderId);
  }

  /// How many notes live under each of [folderIds], counting every
  /// descendant folder. One statement for the whole page of rows; a folder
  /// with nothing under it is absent from the map.
  Future<Map<String, int>> getNoteCountsWithDescendants(
    List<String> folderIds,
  ) async {
    await initialize();
    return _repository.noteCountsWithDescendants(folderIds);
  }

  Future<model.Folder> createFolder({
    required String name,
    String? parentId,
    ItemLabel label = ItemLabel.none,
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
      label: label,
    );
    return _toModel(folder);
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
    ItemLabel label = ItemLabel.none,
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
      label: label,
    );
    return _toModel(folder);
  }

  /// Throws `SharedRowException` for a folder the partner shares, or into
  /// one ([updateFolder]'s re-parent): the fences would turn the write into
  /// nothing while this answered as if it were stored.
  Future<model.Folder?> updateFolder({
    required String folderId,
    String? name,
    String? parentId,
  }) async {
    await initialize();
    await ensureOwn([folderId, ?parentId]);
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
    return folder != null ? _toModel(folder) : null;
  }

  /// Writes one folder's colour label. Returns the refreshed folder, or null
  /// when it is gone or tombstoned; throws `SharedRowException` for a
  /// partner's.
  Future<model.Folder?> setFolderLabel(String folderId, ItemLabel label) async {
    await initialize();
    await ensureOwn([folderId]);
    final folder = await _repository.setLabel(folderId: folderId, label: label);
    return folder == null ? null : _toModel(folder);
  }

  /// Shares the folder [folderId] and everything under it with the partner
  /// of the pair [pairId], or stops sharing it when null
  /// (`docs/cloud-sharing-foundations.md` §3): one stamped write of the
  /// folder's mark, which the next push carries, with the folders and notes
  /// under it following it. Returns whether the mark was written — false
  /// for a folder that is gone or carries it already.
  ///
  /// The app shares a folder through `ShareService.setFolderShared`, which
  /// writes through the DAO inside its act's one transaction, so no surface
  /// ever holds a pair id; this stays for the QA seam and the tests.
  Future<bool> setFolderShared(String folderId, String? pairId) async {
    await initialize();
    return _repository.setSharedPair(folderId: folderId, pairId: pairId);
  }

  /// Labels a whole selection as one unit — one statement, one reload —
  /// rather than one write per picked row. Returns how many rows changed;
  /// throws `SharedRowException`, writing nothing, when one is a partner's.
  Future<int> setLabelForFolders(
    List<String> folderIds,
    ItemLabel label,
  ) async {
    if (folderIds.isEmpty) return 0;
    await initialize();
    await ensureOwn(folderIds);
    return _repository.setLabelForMany(folderIds: folderIds, label: label);
  }

  /// Throws `SharedRowException` for a partner's folder.
  Future<void> deleteFolder(String folderId) async {
    await initialize();
    await ensureOwn([folderId]);
    await _repository.deleteFolder(folderId);
  }

  /// Deletes a whole selection of folders, each with its subtree.
  ///
  /// One call rather than one per picked row: the cascade is already per
  /// folder in the DAO, so what this saves is the reload cycle the page used
  /// to pay for every item it deleted. Throws `SharedRowException`, deleting
  /// nothing, when one is a partner's.
  Future<void> deleteFolders(List<String> folderIds) async {
    if (folderIds.isEmpty) return;
    await initialize();
    await ensureOwn(folderIds);
    for (final folderId in folderIds) {
      await _repository.deleteFolder(folderId);
    }
  }

  /// Throws `SharedRowException` for a partner's folder, or a partner's
  /// [targetParentId]. The returned folder carries its [model.Folder.share]
  /// as it landed; the move's own snackbar reads [moveFolders]' result.
  Future<model.Folder?> moveFolder({
    required String folderId,
    required String? targetParentId,
  }) async {
    await initialize();
    await ensureOwn([folderId, ?targetParentId]);
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
    return folder != null ? _toModel(folder) : null;
  }

  /// Moves a whole selection in one transaction. Unlike [moveFolder], a
  /// name clash is not thrown: it is one item's outcome among the others, in
  /// [BulkMoveResult.duplicates]. [BulkMoveResult.shareChanges] says which
  /// folders the move shared or made private (a folder landing in a shared
  /// folder gives up its own mark, `FolderDao.moveFolder`). Throws
  /// `SharedRowException`, moving nothing, when a folder or the target is a
  /// partner's.
  Future<BulkMoveResult> moveFolders({
    required List<String> folderIds,
    required String? targetParentId,
  }) async {
    await initialize();
    await ensureOwn([...folderIds, ?targetParentId]);
    return _repository.moveFolders(
      folderIds: folderIds,
      targetParentId: targetParentId,
    );
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
  ///
  /// [stopAtDeleted] cuts the chain at the first tombstone, for a breadcrumb
  /// the user can tap: a live folder can sit under a deleted one while the
  /// sync folder repair waits, and a crumb must never name a tombstone (a
  /// data-less one is named by its id) or lead into one.
  Future<List<model.Folder>> getAncestors(
    String folderId, {
    bool stopAtDeleted = false,
  }) async {
    await initialize();
    final rows = await _ancestorRows(folderId);
    final start = stopAtDeleted
        ? rows.lastIndexWhere((folder) => folder.isDeleted) + 1
        : 0;
    return _toModels(rows.skip(start));
  }

  /// The rows behind [getAncestors], root first, tombstones included: the
  /// model drops `isDeleted`, which the callers that cut or filter need.
  Future<List<Folder>> _ancestorRows(String folderId) async {
    final chain = <Folder>[];
    final visited = <String>{folderId};
    var current = await _repository.getFolderById(folderId);
    while (current?.parentId != null) {
      final parentId = current!.parentId!;
      if (!visited.add(parentId)) break; // cycle guard
      final parent = await _repository.getFolderById(parentId);
      if (parent == null) break;
      chain.insert(0, parent);
      current = parent;
    }
    return chain;
  }

  /// Every folder id a search scoped to [folderId] should reach: the folder
  /// itself plus every descendant, from the one recursive CTE the move picker
  /// already uses. Searching "in this folder" means the subtree — a note two
  /// levels down is still inside it.
  Future<Set<String>> subtreeIds(String folderId) async {
    await initialize();
    final descendants = await _repository.getAllDescendantIds(folderId);
    return {folderId, ...descendants};
  }

  /// Display path for each of [folderIds], root-first and including the
  /// folder's own name (`['Training', 'Winter block']`), for rows that show
  /// where a note lives.
  ///
  /// Deduplicates its input and walks each folder once, so a page of twenty
  /// notes from three folders costs three chains, not twenty — and the walks
  /// share the repository's folder cache on top of that. A folder that can't
  /// be resolved is absent from the map rather than mapped to an empty list.
  ///
  /// The path stops where the crumbs stop ([getAncestors] with
  /// `stopAtDeleted`): nothing above the last tombstone, and the folder's own
  /// name only while it is live. A note can sit under a deleted folder until
  /// it is edited or moved, and a live folder under one until the folder
  /// repair runs; a path must never show a deleted folder's name, nor the id
  /// a data-less tombstone carries for one, nor a chain the crumbs and "Open
  /// folder" cannot lead into (P fix pass PF-L9).
  Future<Map<String, List<String>>> folderPathSegments(
    Iterable<String> folderIds,
  ) async {
    await initialize();
    final paths = <String, List<String>>{};
    for (final folderId in folderIds.toSet()) {
      final folder = await _repository.getFolderById(folderId);
      if (folder == null) continue;
      final ancestors = await _ancestorRows(folderId);
      final start = ancestors.lastIndexWhere((row) => row.isDeleted) + 1;
      paths[folderId] = [
        for (final segment in ancestors.skip(start)) segment.name,
        if (!folder.isDeleted) folder.name,
      ];
    }
    return paths;
  }

  /// Whether the census held now says this database holds a shared row or
  /// a mark of the person's own — from memory, false while none is held.
  /// What a browser surface asks before it reads who the partner is
  /// (`PartnerLookReader`): a database that shares nothing starts no read
  /// for it, and the next load answers again after a write let it go.
  bool get holdsShared => _repository.shareCensus.known?.isEmpty == false;

  /// Whether the folder [id] is the partner's, from memory alone — the
  /// census and the folder cache, both warm after the list that showed it
  /// — or null when either is cold: what a page opened with no word from
  /// its opener knows at its first frame.
  bool? knownFromPartner(String id) {
    final shares = _repository.shareCensus.known;
    final row = _repository.cachedFolder(id);
    if (shares == null || row == null) return null;
    return shares.isPartner(row.ownerId);
  }

  /// Whether a census is held now, so [holdsShared] answers for this
  /// database rather than for "not read yet".
  bool get censusKnown => _repository.shareCensus.known != null;

  /// [holdsShared], reading the census when none is held — one statement,
  /// and none while one is.
  Future<bool> holdsSharedRead() async =>
      !(await _repository.shareCensus.read()).isEmpty;

  Stream<FolderChange> get changes => _repository.folderChanges;

  Stream<FolderChange> changesForParent(String? parentId) =>
      _repository.folderChangesForParent(parentId);

  /// Get the total note count that would be deleted with this folder
  Future<int> getNoteCountForDeletion(String folderId) async {
    await initialize();
    return _repository.getNoteCountForDeletion(folderId);
  }

  /// Update sort preferences for a folder.
  ///
  /// A partner's folder keeps its sort in the person's own store instead
  /// ([PartnerFolderSort]): its columns are the partner's row, which the
  /// database refuses to write, and the sort is the person's choice
  /// (share surfaces §6.12). A folder of the person's own asks nothing more
  /// than the census the mapping reads anyway.
  Future<model.Folder?> updateFolderSortPreferences({
    required String folderId,
    String? noteSortOrder,
    String? subfolderSortOrder,
    bool clearNoteSortOrder = false,
    bool clearSubfolderSortOrder = false,
  }) async {
    await initialize();
    final shares = await _repository.shareCensus.read();
    if (shares.owner != null) {
      final row = await _repository.getFolderById(folderId);
      if (row != null && shares.isPartner(row.ownerId)) {
        return _setPartnerSort(
          row,
          shares,
          noteSortOrder: noteSortOrder,
          subfolderSortOrder: subfolderSortOrder,
          clearNoteSortOrder: clearNoteSortOrder,
          clearSubfolderSortOrder: clearSubfolderSortOrder,
        );
      }
    }
    final folder = await _repository.updateFolderSortPreferences(
      id: folderId,
      noteSortOrder: noteSortOrder,
      subfolderSortOrder: subfolderSortOrder,
      clearNoteSortOrder: clearNoteSortOrder,
      clearSubfolderSortOrder: clearSubfolderSortOrder,
    );
    return folder != null ? _toModel(folder) : null;
  }

  /// Throws [SharedRowException] when one of [ids] is a folder the partner
  /// shares — before a write the fences would turn into nothing while this
  /// service answered "done", and before an export (share surfaces D19: a
  /// partner's rows never leave by file). Asks the shared rows only when
  /// the database holds some ([ShareCensus]): a database that never read
  /// one pays nothing past the census it already holds.
  Future<void> ensureOwn(List<String> ids) async {
    final owner = (await _repository.shareCensus.read()).owner;
    if (owner == null) return;
    final theirs = await _repository.partnersAmong(ids, owner);
    if (theirs.isNotEmpty) throw SharedRowException('folders', theirs.first);
  }

  /// Writes the person's sort of the partner's [folder]; a column not given
  /// keeps what the folder shows now, so the stored sort is whole from its
  /// first write and the partner's later choice never shows through half
  /// of it. Read and write are one transaction: two sorts tapped in a row
  /// must not each write over the other's column.
  Future<model.Folder> _setPartnerSort(
    Folder folder,
    ShareSnapshot shares, {
    String? noteSortOrder,
    String? subfolderSortOrder,
    required bool clearNoteSortOrder,
    required bool clearSubfolderSortOrder,
  }) {
    final db = _repository.database;
    return db.transaction(() async {
      final sorts = {...await SettingsService.partnerFolderSortsOf(db)};
      final shown = _folderToModel(folder, shares, sorts);
      sorts[folder.id] = PartnerFolderSort(
        noteSortOrder: clearNoteSortOrder
            ? null
            : noteSortOrder ?? shown.noteSortOrder,
        subfolderSortOrder: clearSubfolderSortOrder
            ? null
            : subfolderSortOrder ?? shown.subfolderSortOrder,
      );
      await SettingsService.setPartnerFolderSortsOf(db, sorts);
      return _folderToModel(folder, shares, sorts);
    });
  }

  Future<model.Folder> _toModel(Folder folder) =>
      _toModels([folder]).then((models) => models.single);

  /// [folders] as models, flagged against one read of the census for all —
  /// and, when one of them is the partner's, one read of the person's sorts
  /// of the partner's folders; a database that holds none reads nothing.
  Future<List<model.Folder>> _toModels(Iterable<Folder> folders) async {
    final shares = await _repository.shareCensus.read();
    final sorts =
        shares.owner != null &&
            folders.any((folder) => shares.isPartner(folder.ownerId))
        ? await SettingsService.partnerFolderSortsOf(_repository.database)
        : const <String, PartnerFolderSort>{};
    return [
      for (final folder in folders) _folderToModel(folder, shares, sorts),
    ];
  }

  /// [sorts] are the person's own sorts of the partner's folders: one set
  /// for a partner's folder stands in for the folder's own columns, so no
  /// page reads a sort order any differently.
  model.Folder _folderToModel(
    Folder folder,
    ShareSnapshot shares,
    Map<String, PartnerFolderSort> sorts,
  ) {
    final fromPartner = shares.isPartner(folder.ownerId);
    final mine = fromPartner ? sorts[folder.id] : null;
    return model.Folder(
      id: folder.id,
      name: folder.name,
      parentId: folder.parentId,
      createdAt: folder.createdAt,
      noteSortOrder: mine == null ? folder.noteSortOrder : mine.noteSortOrder,
      subfolderSortOrder: mine == null
          ? folder.subfolderSortOrder
          : mine.subfolderSortOrder,
      position: folder.position,
      label: ItemLabel.fromStorage(folder.label),
      fromPartner: fromPartner,
      share: fromPartner
          ? model.FolderShare.none
          : shares.folderShare(folder.id),
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
      case FoldersSortOrder.labelAsc:
        return (FolderSortField.label, true);
    }
  }

  void invalidateCache() {
    _repository.invalidateAll();
  }
}
