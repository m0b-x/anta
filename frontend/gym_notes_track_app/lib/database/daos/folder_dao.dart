import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/folders_table.dart';
import '../crdt/hlc.dart';

part 'folder_dao.g.dart';

@DriftAccessor(tables: [Folders])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(super.db);

  Future<List<Folder>> getAllFolders({bool includeDeleted = false}) {
    final query = select(folders);
    if (!includeDeleted) {
      query.where((f) => f.isDeleted.equals(false));
    }
    return query.get();
  }

  Future<List<Folder>> getFoldersByParent(
    String? parentId, {
    bool includeDeleted = false,
  }) {
    final query = select(folders);
    if (parentId == null) {
      query.where((f) => f.parentId.isNull());
    } else {
      query.where((f) => f.parentId.equals(parentId));
    }
    if (!includeDeleted) {
      query.where((f) => f.isDeleted.equals(false));
    }
    return query.get();
  }

  Future<Folder?> getFolderById(String id) {
    return (select(folders)..where((f) => f.id.equals(id))).getSingleOrNull();
  }

  Future<int> getFolderCount(
    String? parentId, {
    bool includeDeleted = false,
  }) async {
    final countExp = folders.id.count();
    final query = selectOnly(folders)..addColumns([countExp]);

    if (parentId == null) {
      query.where(folders.parentId.isNull());
    } else {
      query.where(folders.parentId.equals(parentId));
    }

    if (!includeDeleted) {
      query.where(folders.isDeleted.equals(false));
    }

    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  Future<List<Folder>> getFoldersPaginated({
    String? parentId,
    required int limit,
    required int offset,
    required FolderSortField sortField,
    required bool ascending,
  }) {
    final query = select(folders);

    if (parentId == null) {
      query.where((f) => f.parentId.isNull());
    } else {
      query.where((f) => f.parentId.equals(parentId));
    }
    query.where((f) => f.isDeleted.equals(false));

    final orderMode = ascending ? OrderingMode.asc : OrderingMode.desc;

    switch (sortField) {
      case FolderSortField.name:
        query.orderBy([
          (f) => OrderingTerm(expression: f.name, mode: orderMode),
        ]);
      case FolderSortField.createdAt:
        query.orderBy([
          (f) => OrderingTerm(expression: f.createdAt, mode: orderMode),
        ]);
      case FolderSortField.updatedAt:
        query.orderBy([
          (f) => OrderingTerm(expression: f.updatedAt, mode: orderMode),
        ]);
      case FolderSortField.position:
        query.orderBy([
          (f) => OrderingTerm(expression: f.position, mode: orderMode),
        ]);
    }

    query.limit(limit, offset: offset);
    return query.get();
  }

  Future<Folder> insertFolder(FoldersCompanion folder) async {
    await into(folders).insert(folder);
    return (select(
      folders,
    )..where((f) => f.id.equals(folder.id.value))).getSingle();
  }

  Future<Folder> createFolder({required String name, String? parentId}) async {
    final now = DateTime.now();
    final id = db.generateId();
    final hlc = db.generateHlc();

    // Get the next position for this parent
    final maxPosQuery = selectOnly(folders)
      ..addColumns([folders.position.max()]);
    if (parentId == null) {
      maxPosQuery.where(folders.parentId.isNull());
    } else {
      maxPosQuery.where(folders.parentId.equals(parentId));
    }
    maxPosQuery.where(folders.isDeleted.equals(false));
    final maxPosResult = await maxPosQuery.getSingle();
    final maxPos = maxPosResult.read(folders.position.max()) ?? -1;

    final companion = FoldersCompanion(
      id: Value(id),
      name: Value(name),
      parentId: Value(parentId),
      position: Value(maxPos + 1),
      createdAt: Value(now),
      updatedAt: Value(now),
      hlcTimestamp: Value(hlc),
      deviceId: Value(db.deviceId),
      version: const Value(1),
      isDeleted: const Value(false),
    );

    return insertFolder(companion);
  }

  /// Insert a folder while preserving externally-provided audit fields.
  /// Used by the import pipeline so a round-tripped folder keeps its
  /// original `createdAt` and per-folder sort preferences. Position is
  /// still appended to the parent so the folder shows up at the end and
  /// doesn't fight existing ordering.
  Future<Folder> importFolder({
    required String name,
    String? parentId,
    required DateTime createdAt,
    String? noteSortOrder,
    String? subfolderSortOrder,
  }) async {
    final now = DateTime.now();
    final id = db.generateId();
    final hlc = db.generateHlc();

    final maxPosQuery = selectOnly(folders)
      ..addColumns([folders.position.max()]);
    if (parentId == null) {
      maxPosQuery.where(folders.parentId.isNull());
    } else {
      maxPosQuery.where(folders.parentId.equals(parentId));
    }
    maxPosQuery.where(folders.isDeleted.equals(false));
    final maxPosResult = await maxPosQuery.getSingle();
    final maxPos = maxPosResult.read(folders.position.max()) ?? -1;

    final companion = FoldersCompanion(
      id: Value(id),
      name: Value(name),
      parentId: Value(parentId),
      position: Value(maxPos + 1),
      createdAt: Value(createdAt),
      // updatedAt records when this row was written locally; the import
      // is a fresh write event so `now` is the correct semantic.
      updatedAt: Value(now),
      noteSortOrder: noteSortOrder != null
          ? Value(noteSortOrder)
          : const Value.absent(),
      subfolderSortOrder: subfolderSortOrder != null
          ? Value(subfolderSortOrder)
          : const Value.absent(),
      hlcTimestamp: Value(hlc),
      deviceId: Value(db.deviceId),
      version: const Value(1),
      isDeleted: const Value(false),
    );

    return insertFolder(companion);
  }

  Future<Folder?> updateFolder({
    required String id,
    String? name,
    String? parentId,
    bool updateParent = false,
  }) async {
    final existing = await getFolderById(id);
    if (existing == null) return null;

    final now = DateTime.now();
    final hlc = db.generateHlc();

    final companion = FoldersCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      parentId: updateParent ? Value(parentId) : const Value.absent(),
      updatedAt: Value(now),
      hlcTimestamp: Value(hlc),
      deviceId: Value(db.deviceId),
      version: Value(existing.version + 1),
    );

    await (update(folders)..where((f) => f.id.equals(id))).write(companion);
    return getFolderById(id);
  }

  Future<Folder?> moveFolder({
    required String id,
    required String? targetParentId,
  }) async {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return null;

      if (targetParentId != null) {
        if (targetParentId == id) return null;
        final target = await getFolderById(targetParentId);
        if (target == null || target.isDeleted) return null;
        final descendants = await getAllDescendantIds(id);
        if (descendants.contains(targetParentId)) return null;
      }

      if (existing.parentId == targetParentId) return existing;

      final now = DateTime.now();
      final hlc = db.generateHlc();

      final maxPosQuery = selectOnly(folders)
        ..addColumns([folders.position.max()]);
      if (targetParentId == null) {
        maxPosQuery.where(folders.parentId.isNull());
      } else {
        maxPosQuery.where(folders.parentId.equals(targetParentId));
      }
      maxPosQuery.where(folders.isDeleted.equals(false));
      final maxPosResult = await maxPosQuery.getSingle();
      final maxPos = maxPosResult.read(folders.position.max()) ?? -1;

      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          parentId: Value(targetParentId),
          position: Value(maxPos + 1),
          updatedAt: Value(now),
          hlcTimestamp: Value(hlc),
          deviceId: Value(db.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getFolderById(id);
    });
  }

  Future<void> softDeleteFolder(String id) async {
    final now = DateTime.now();
    final hlc = db.generateHlc();

    final existing = await getFolderById(id);
    if (existing == null) return;

    await (update(folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
        version: Value(existing.version + 1),
      ),
    );
  }

  Future<void> hardDeleteFolder(String id) async {
    await (delete(folders)..where((f) => f.id.equals(id))).go();
  }

  /// Update the position of a folder
  Future<Folder?> updateFolderPosition({
    required String id,
    required int newPosition,
  }) async {
    final existing = await getFolderById(id);
    if (existing == null) return null;

    final now = DateTime.now();
    final hlc = db.generateHlc();

    await (update(folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        position: Value(newPosition),
        updatedAt: Value(now),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
        version: Value(existing.version + 1),
      ),
    );
    return getFolderById(id);
  }

  /// Reorder folders within a parent
  Future<void> reorderFolders({
    String? parentId,
    required List<String> orderedIds,
  }) async {
    final positions = {
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    await setFolderPositions(positions);
  }

  /// Write explicit positions for a set of folders. Used by the mixed
  /// reorder service to assign global (folder + note interleaved) positions
  /// without forcing the caller to pass dense 0..N ranges per kind.
  /// Bumps `version` in SQL rather than reading each row first — see
  /// [NoteDao.setNotePositions] for why. A missing id updates zero rows, the
  /// same outcome the previous existence check produced.
  Future<void> setFolderPositions(Map<String, int> positionByFolderId) async {
    if (positionByFolderId.isEmpty) return;
    final now = DateTime.now();
    final hlc = db.generateHlc();

    await transaction(() async {
      for (final entry in positionByFolderId.entries) {
        await customUpdate(
          'UPDATE folders SET position = ?, updated_at = ?, '
          'hlc_timestamp = ?, device_id = ?, version = version + 1 '
          'WHERE id = ?',
          variables: [
            Variable<int>(entry.value),
            Variable<DateTime>(now),
            Variable<String>(hlc),
            Variable<String>(db.deviceId),
            Variable<String>(entry.key),
          ],
          updates: {folders},
        );
      }
    });
  }

  /// Update sort preferences for a folder
  Future<Folder?> updateFolderSortPreferences({
    required String id,
    String? noteSortOrder,
    String? subfolderSortOrder,
    bool clearNoteSortOrder = false,
    bool clearSubfolderSortOrder = false,
  }) async {
    final existing = await getFolderById(id);
    if (existing == null) return null;

    final now = DateTime.now();
    final hlc = db.generateHlc();

    await (update(folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        noteSortOrder: clearNoteSortOrder
            ? const Value(null)
            : (noteSortOrder != null
                  ? Value(noteSortOrder)
                  : const Value.absent()),
        subfolderSortOrder: clearSubfolderSortOrder
            ? const Value(null)
            : (subfolderSortOrder != null
                  ? Value(subfolderSortOrder)
                  : const Value.absent()),
        updatedAt: Value(now),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
        version: Value(existing.version + 1),
      ),
    );
    return getFolderById(id);
  }

  Future<List<String>> getAllDescendantIds(String folderId) async {
    // Single recursive CTE replaces the previous N+1 walk
    // (one getFoldersByParent per visited folder). Excludes soft-deleted
    // rows from the traversal so a tombstoned subtree doesn't propagate
    // its (already-deleted) children.
    final rows = await db
        .customSelect(
          'WITH RECURSIVE d(id) AS ('
          '  SELECT id FROM folders '
          '  WHERE parent_id = ?1 AND is_deleted = 0 '
          '  UNION ALL '
          '  SELECT f.id FROM folders f '
          '  JOIN d ON f.parent_id = d.id '
          '  WHERE f.is_deleted = 0'
          ') SELECT id FROM d',
          variables: [Variable<String>(folderId)],
          readsFrom: {folders},
        )
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  Future<void> softDeleteFolderWithDescendants(String folderId) async {
    // Collect the full id set in one CTE query, then issue exactly two
    // batched UPDATE statements inside a single transaction:
    //  (1) soft-delete every note whose folder is in the set
    //  (2) soft-delete every folder in the set
    // This replaces an N+1 pattern that issued one update per folder and
    // one per note (potentially hundreds of round-trips for deep trees).
    final descendantIds = await getAllDescendantIds(folderId);
    descendantIds.add(folderId);

    if (descendantIds.isEmpty) return;

    await transaction(() async {
      final now = DateTime.now();
      final hlc = db.generateHlc();

      // 1. Bulk soft-delete notes in any of these folders. We need to
      //    update FTS rowids first because softDeleteNote's FTS removal
      //    happens per-row; we replicate that with a single statement.
      final placeholders = List.filled(descendantIds.length, '?').join(',');

      // Remove affected notes from FTS by rowid lookup. This uses the
      // notes_fts contentless trigger pattern: we delete by rowid
      // explicitly so the search index stays consistent.
      await db.customStatement(
        'DELETE FROM notes_fts WHERE rowid IN ('
        '  SELECT rowid FROM notes '
        '  WHERE folder_id IN ($placeholders) AND is_deleted = 0'
        ')',
        [for (final id in descendantIds) id],
      );

      // Bulk update notes. version + 1 per row is preserved.
      await db.customStatement(
        'UPDATE notes SET '
        '  is_deleted = 1, '
        '  deleted_at = ?, '
        '  updated_at = ?, '
        '  hlc_timestamp = ?, '
        '  device_id = ?, '
        '  version = version + 1 '
        'WHERE folder_id IN ($placeholders) AND is_deleted = 0',
        [
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          hlc,
          db.deviceId,
          ...descendantIds,
        ],
      );

      // 2. Bulk soft-delete folders themselves.
      await db.customStatement(
        'UPDATE folders SET '
        '  is_deleted = 1, '
        '  deleted_at = ?, '
        '  updated_at = ?, '
        '  hlc_timestamp = ?, '
        '  device_id = ?, '
        '  version = version + 1 '
        'WHERE id IN ($placeholders) AND is_deleted = 0',
        [
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
          hlc,
          db.deviceId,
          ...descendantIds,
        ],
      );
    });
  }

  /// Returns true if a non-deleted folder with the same case-insensitive,
  /// trimmed [name] already exists under [parentId]. Indexed by
  /// `idx_folders_parent_lname`. [excludeId] is honored for rename flows
  /// so a folder isn't reported as a duplicate of itself.
  Future<bool> folderNameExistsInParent({
    required String? parentId,
    required String name,
    String? excludeId,
  }) async {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // COALESCE matches the index expression so the planner uses
    // idx_folders_parent_lname; a plain `parent_id IS NULL` would force
    // a scan because indexed NULLs are distinct in SQLite.
    //
    // We pass an empty string for a missing excludeId because folder ids
    // are non-empty UUIDs, so `id <> ''` is always true and the predicate
    // becomes a no-op without needing nullable Variable bindings (which
    // customSelect's List<Variable<Object>> type doesn't accept).
    final result = await db
        .customSelect(
          "SELECT 1 FROM folders "
          "WHERE COALESCE(parent_id, '') = ?1 "
          "AND LOWER(TRIM(name)) = ?2 "
          "AND is_deleted = 0 "
          "AND id <> ?3 "
          "LIMIT 1",
          variables: [
            Variable<String>(parentId ?? ''),
            Variable<String>(normalized),
            Variable<String>(excludeId ?? ''),
          ],
          readsFrom: {folders},
        )
        .getSingleOrNull();
    return result != null;
  }

  /// Get total note count for a folder and all its descendants (for delete preview)
  Future<int> getNoteCountWithDescendants(String folderId) async {
    final descendantIds = await getAllDescendantIds(folderId);
    descendantIds.add(folderId);

    return db.noteDao.getNoteCountInFolders(descendantIds);
  }

  Future<List<Folder>> getFoldersSince(String hlcTimestamp) {
    return (select(
      folders,
    )..where((f) => f.hlcTimestamp.isBiggerThanValue(hlcTimestamp))).get();
  }

  Future<void> mergeFolder(Folder remote) async {
    final local = await getFolderById(remote.id);

    if (local == null) {
      await into(folders).insert(
        FoldersCompanion(
          id: Value(remote.id),
          name: Value(remote.name),
          parentId: Value(remote.parentId),
          createdAt: Value(remote.createdAt),
          updatedAt: Value(remote.updatedAt),
          hlcTimestamp: Value(remote.hlcTimestamp),
          deviceId: Value(remote.deviceId),
          version: Value(remote.version),
          isDeleted: Value(remote.isDeleted),
          deletedAt: Value(remote.deletedAt),
          noteSortOrder: Value(remote.noteSortOrder),
          subfolderSortOrder: Value(remote.subfolderSortOrder),
        ),
      );
      return;
    }

    final localHlc = HlcTimestamp.parse(local.hlcTimestamp);
    final remoteHlc = HlcTimestamp.parse(remote.hlcTimestamp);

    if (remoteHlc > localHlc) {
      await (update(folders)..where((f) => f.id.equals(remote.id))).write(
        FoldersCompanion(
          name: Value(remote.name),
          parentId: Value(remote.parentId),
          updatedAt: Value(remote.updatedAt),
          hlcTimestamp: Value(remote.hlcTimestamp),
          deviceId: Value(remote.deviceId),
          version: Value(remote.version),
          isDeleted: Value(remote.isDeleted),
          deletedAt: Value(remote.deletedAt),
          noteSortOrder: Value(remote.noteSortOrder),
          subfolderSortOrder: Value(remote.subfolderSortOrder),
        ),
      );
      db.hlc.update(remoteHlc);
    }
  }

  Stream<List<Folder>> watchFoldersByParent(String? parentId) {
    final query = select(folders);
    if (parentId == null) {
      query.where((f) => f.parentId.isNull());
    } else {
      query.where((f) => f.parentId.equals(parentId));
    }
    query.where((f) => f.isDeleted.equals(false));
    query.orderBy([(f) => OrderingTerm.asc(f.name)]);
    return query.watch();
  }

  Stream<Folder?> watchFolderById(String id) {
    return (select(folders)..where((f) => f.id.equals(id))).watchSingleOrNull();
  }
}

enum FolderSortField { name, createdAt, updatedAt, position }
