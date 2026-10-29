import 'package:drift/drift.dart';
import '../../models/item_label.dart';
import '../database.dart';
import '../tables/folders_table.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import 'sync_dao.dart';

part 'folder_dao.g.dart';

@DriftAccessor(tables: [Folders])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(super.db);

  /// How many generations a recursive folder walk may descend before it
  /// stops. Real trees are a handful deep; the bound exists so a
  /// `parent_id` cycle — unreachable through the UI, reachable through a
  /// merge or a hand-edited database — terminates the CTE instead of
  /// spinning it forever.
  static const int maxFolderDepth = 64;

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

  /// The live folders among [ids], in one statement — what a bulk write
  /// reads back afterwards instead of one `getFolderById` per row.
  Future<List<Folder>> getFoldersByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(
      folders,
    )..where((f) => f.id.isIn(ids) & f.isDeleted.equals(false))).get();
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
      // Labelled folders first, in palette order, unlabelled last — the note
      // sort's rule, with `name` where the notes use `updated_at DESC`. There
      // is no descending variant, so `ascending` is deliberately not consulted
      // here, and this is the one folder sort that ends on `id`: the label
      // runs are wide enough that a page boundary would otherwise fall inside
      // a run of ties and re-serve or skip a row.
      case FolderSortField.label:
        query.orderBy([
          (f) => OrderingTerm(expression: _unlabelledLast),
          (f) => OrderingTerm(expression: f.label),
          (f) => OrderingTerm(expression: f.name),
          (f) => OrderingTerm(expression: f.id),
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

  /// [ownerId] is for a backup restore, whose copy keeps the archived
  /// ownership under its fresh id (D16); every other caller leaves it null.
  Future<Folder> createFolder({
    required String name,
    String? parentId,
    ItemLabel label = ItemLabel.none,
    String? ownerId,
  }) {
    return transaction(() async {
      final now = DateTime.now();
      final id = db.generateId();
      final stamp = await db.stampLocal(folders, id);

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
        label: Value(label.storageValue),
        position: Value(maxPos + 1),
        createdAt: Value(now),
        updatedAt: Value(now),
        ownerId: Value(ownerId),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
      );

      return insertFolder(companion);
    });
  }

  /// Insert a folder while preserving externally-provided audit fields.
  /// Used by the import pipeline so a round-tripped folder keeps its
  /// original `createdAt` and per-folder sort preferences. Position is
  /// still appended to the parent so the folder shows up at the end and
  /// doesn't fight existing ordering. Identity is stamped fresh and the
  /// folder is queued: an imported folder is a new local row.
  ///
  /// [updatedAt] is for a backup restore, which replays rows the sync merge
  /// converges and so has to carry their archived mtime (A3a review R62);
  /// the folder-archive path leaves it null and the row records the import
  /// as its own write event. [ownerId] is for the same restore, whose copy
  /// keeps the archived ownership under its fresh id (D16).
  Future<Folder> importFolder({
    required String name,
    String? parentId,
    required DateTime createdAt,
    DateTime? updatedAt,
    String? noteSortOrder,
    String? subfolderSortOrder,
    ItemLabel label = ItemLabel.none,
    String? ownerId,
  }) {
    return transaction(() async {
      final now = DateTime.now();
      final id = db.generateId();
      final stamp = await db.stampLocal(folders, id);

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
        label: Value(label.storageValue),
        position: Value(maxPos + 1),
        createdAt: Value(createdAt),
        // updatedAt records when this row was written locally, so an import
        // that carries no mtime of its own is a fresh write event.
        updatedAt: Value(updatedAt ?? now),
        noteSortOrder: noteSortOrder != null
            ? Value(noteSortOrder)
            : const Value.absent(),
        subfolderSortOrder: subfolderSortOrder != null
            ? Value(subfolderSortOrder)
            : const Value.absent(),
        ownerId: Value(ownerId),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
      );

      return insertFolder(companion);
    });
  }

  Future<Folder?> updateFolder({
    required String id,
    String? name,
    String? parentId,
    bool updateParent = false,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null) return null;
      // An edit that changes nothing writes nothing, so it does not read as a
      // change once devices merge.
      final renames = name != null && name != existing.name;
      final moves = updateParent && parentId != existing.parentId;
      if (!renames && !moves) return existing;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        folders,
        id,
        op: OutboxOp.forRow(isDeleted: existing.isDeleted),
      );

      final companion = FoldersCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        parentId: updateParent ? Value(parentId) : const Value.absent(),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      );

      await (update(folders)..where((f) => f.id.equals(id))).write(companion);
      return getFolderById(id);
    });
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
      final stamp = await db.stampLocal(folders, id);

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
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getFolderById(id);
    });
  }

  /// A missing or already-tombstoned folder writes nothing, so a repeat
  /// cannot churn the version a merge orders by.
  Future<void> softDeleteFolder(String id) {
    return transaction(() async {
      final now = DateTime.now();

      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return;
      final stamp = await db.stampLocal(folders, id, op: OutboxOp.tombstone);

      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  Future<void> hardDeleteFolder(String id) async {
    await (delete(folders)..where((f) => f.id.equals(id))).go();
  }

  /// Update the position of a folder
  Future<Folder?> updateFolderPosition({
    required String id,
    required int newPosition,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null) return null;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        folders,
        id,
        op: OutboxOp.forRow(isDeleted: existing.isDeleted),
      );

      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          position: Value(newPosition),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getFolderById(id);
    });
  }

  /// Writes the colour label of one folder.
  ///
  /// Shaped on [updateFolderPosition] — read the row, stamp a fresh HLC,
  /// write `version + 1` — and refuses a tombstone: a label picked from a
  /// sheet that outlived the folder would otherwise resurrect it on the next
  /// merge. `updated_at` is left alone and an unchanged label is a no-op,
  /// for the reasons `NoteDao.updateNoteLabel` gives.
  Future<Folder?> updateFolderLabel({
    required String id,
    required ItemLabel label,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return null;
      if (existing.label == label.storageValue) return existing;

      final stamp = await db.stampLocal(folders, id);

      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          label: Value(label.storageValue),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getFolderById(id);
    });
  }

  /// Labels a whole selection in **one** statement — SQLite does the
  /// `version + 1` arithmetic itself, the same way [setFolderPositions]
  /// does, so the statement count does not move with the size of the
  /// selection.
  ///
  /// Returns how many rows actually changed. Tombstones and rows already
  /// carrying [label] are skipped by the `WHERE` clause rather than by a
  /// pre-read; `updated_at` is left alone.
  Future<int> updateLabelForFolders({
    required List<String> ids,
    required ItemLabel label,
  }) async {
    if (ids.isEmpty) return 0;
    final unique = ids.toSet().toList(growable: false);
    final placeholders = List.filled(unique.length, '?').join(', ');

    return transaction(() async {
      final stamp = db.newStamp();
      final changed = await customWriteReturning(
        'UPDATE folders SET label = ?, hlc_timestamp = ?, '
        'device_id = ?, version = version + 1 '
        'WHERE id IN ($placeholders) AND is_deleted = 0 AND label <> ? '
        'RETURNING id',
        variables: [
          Variable<int>(label.storageValue),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          for (final id in unique) Variable<String>(id),
          Variable<int>(label.storageValue),
        ],
        updates: {folders},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(folders, [
        for (final row in changed) row.read<String>('id'),
      ], stamp.hlc);
      return changed.length;
    });
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
  /// same outcome the previous existence check produced. Only live rows that
  /// move are written and queued, as there.
  Future<void> setFolderPositions(Map<String, int> positionByFolderId) async {
    if (positionByFolderId.isEmpty) return;
    final now = DateTime.now();

    await transaction(() async {
      final stamp = db.newStamp();
      final moved = <String>[];
      for (final entry in positionByFolderId.entries) {
        final changed = await customUpdate(
          'UPDATE folders SET position = ?, updated_at = ?, '
          'hlc_timestamp = ?, device_id = ?, version = version + 1 '
          'WHERE id = ? AND is_deleted = 0 AND position != ?',
          variables: [
            Variable<int>(entry.value),
            Variable<DateTime>(now),
            Variable<String>(stamp.hlc),
            Variable<String>(stamp.deviceId),
            Variable<String>(entry.key),
            Variable<int>(entry.value),
          ],
          updates: {folders},
        );
        if (changed > 0) moved.add(entry.key);
      }
      await db.enqueueMany(folders, moved, stamp.hlc);
    });
  }

  /// Update sort preferences for a folder
  Future<Folder?> updateFolderSortPreferences({
    required String id,
    String? noteSortOrder,
    String? subfolderSortOrder,
    bool clearNoteSortOrder = false,
    bool clearSubfolderSortOrder = false,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null) return null;
      final nextNoteSort = clearNoteSortOrder
          ? null
          : (noteSortOrder ?? existing.noteSortOrder);
      final nextSubfolderSort = clearSubfolderSortOrder
          ? null
          : (subfolderSortOrder ?? existing.subfolderSortOrder);
      // Re-picking the sort a folder already has writes nothing.
      if (nextNoteSort == existing.noteSortOrder &&
          nextSubfolderSort == existing.subfolderSortOrder) {
        return existing;
      }

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        folders,
        id,
        op: OutboxOp.forRow(isDeleted: existing.isDeleted),
      );

      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          noteSortOrder: Value(nextNoteSort),
          subfolderSortOrder: Value(nextSubfolderSort),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getFolderById(id);
    });
  }

  Future<List<String>> getAllDescendantIds(String folderId) async {
    // Single recursive CTE replaces the previous N+1 walk
    // (one getFoldersByParent per visited folder). Excludes soft-deleted
    // rows from the traversal so a tombstoned subtree doesn't propagate
    // its (already-deleted) children.
    final rows = await db
        .customSelect(
          'WITH RECURSIVE d(id, depth) AS ('
          '  SELECT id, 0 FROM folders '
          '  WHERE parent_id = ?1 AND is_deleted = 0 '
          '  UNION ALL '
          '  SELECT f.id, d.depth + 1 FROM folders f '
          '  JOIN d ON f.parent_id = d.id '
          '  WHERE f.is_deleted = 0 AND d.depth < $maxFolderDepth'
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
      final stamp = db.newStamp();

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

      // Bulk update notes. version + 1 per row is preserved. The timestamps
      // bind as `Variable<DateTime>`: Drift stores unix seconds, and raw
      // milliseconds here once wrote values a thousand times too large (the
      // v43 migration repairs those rows).
      final stamps = <Variable>[
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        for (final id in descendantIds) Variable<String>(id),
      ];
      final noteRows = await customWriteReturning(
        'UPDATE notes SET '
        '  is_deleted = 1, '
        '  deleted_at = ?, '
        '  updated_at = ?, '
        '  hlc_timestamp = ?, '
        '  device_id = ?, '
        '  version = version + 1 '
        'WHERE folder_id IN ($placeholders) AND is_deleted = 0 '
        'RETURNING id',
        variables: stamps,
      );

      // 2. Bulk soft-delete folders themselves.
      final folderRows = await customWriteReturning(
        'UPDATE folders SET '
        '  is_deleted = 1, '
        '  deleted_at = ?, '
        '  updated_at = ?, '
        '  hlc_timestamp = ?, '
        '  device_id = ?, '
        '  version = version + 1 '
        'WHERE id IN ($placeholders) AND is_deleted = 0 '
        'RETURNING id',
        variables: stamps,
      );

      // 3. Queue exactly the rows the two updates tombstoned, under its HLC.
      await db.enqueueMany(
        db.notes,
        [for (final row in noteRows) row.read<String>('id')],
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
      await db.enqueueMany(
        folders,
        [for (final row in folderRows) row.read<String>('id')],
        stamp.hlc,
        op: OutboxOp.tombstone,
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

  /// Descendant-inclusive note counts for many folders in **one** statement.
  ///
  /// The browser draws one count per folder row, and a page of rows used to
  /// cost two queries each. A single `WITH RECURSIVE` walk carries the seed
  /// id along as `root`, so every folder reached from a seed is attributed
  /// back to it and one `GROUP BY` answers the whole page.
  ///
  /// Folders missing from the result had no live rows to count; callers read
  /// an absent key as zero. Soft-deleted folders are excluded from both the
  /// seed and the traversal, matching [getAllDescendantIds].
  Future<Map<String, int>> noteCountsWithDescendants(
    List<String> folderIds,
  ) async {
    if (folderIds.isEmpty) return const {};
    final placeholders = List.filled(folderIds.length, '?').join(',');
    final rows = await db
        .customSelect(
          'WITH RECURSIVE tree(root, id, depth) AS ('
          '  SELECT id, id, 0 FROM folders '
          '  WHERE id IN ($placeholders) AND is_deleted = 0 '
          '  UNION ALL '
          '  SELECT t.root, f.id, t.depth + 1 FROM folders f '
          '  JOIN tree t ON f.parent_id = t.id '
          '  WHERE f.is_deleted = 0 AND t.depth < $maxFolderDepth'
          ') '
          'SELECT t.root AS root, COUNT(n.id) AS note_count '
          'FROM tree t '
          'LEFT JOIN notes n ON n.folder_id = t.id AND n.is_deleted = 0 '
          'GROUP BY t.root',
          variables: [for (final id in folderIds) Variable<String>(id)],
          readsFrom: {folders, db.notes},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('root'): row.read<int>('note_count'),
    };
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

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<Folder>> getByIdsIncludingDeleted(List<String> ids) {
    return CrdtMerge.loadInChunks(
      ids,
      (chunk) => (select(folders)..where((f) => f.id.isIn(chunk))).get(),
    );
  }

  /// Merges one remote folder on the contract of [CrdtMerge.mergeRemoteRow]:
  /// every column as received, sort preferences and position included. A
  /// tombstone carries no data, so over a local row it writes the stamps, the
  /// deletion and the owner and keeps the rest. Never cascades: each
  /// descendant arrives as its own row. A live remote under another parent
  /// reports the parent it left ([MergeOutcome.moved]).
  ///
  /// A live row's parent is then repaired if the merge left it unreachable —
  /// see [_repairMergedParent]; the repair is a local write with its own
  /// stamp, so the space converges on it rather than on the parent that hid
  /// the subtree.
  Future<MergeOutcome> mergeFolder(Folder remote, {String? floor}) {
    return transaction(() async {
      final local = await getFolderById(remote.id);
      final outcome = await CrdtMerge.mergeRemoteRow(
        db,
        table: folders,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(folders).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(folders)..where((f) => f.id.equals(remote.id))).write(
              FoldersCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                updatedAt: CrdtMerge.tombstoneUpdatedAt(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            await update(folders).replace(remote);
            if (local!.parentId != remote.parentId) {
              return applied.movedFrom(local.parentId);
            }
          }
          return applied;
        },
      );
      final parentId = remote.parentId;
      if (remote.isDeleted ||
          parentId == null ||
          (outcome.result != MergeResult.inserted &&
              outcome.result != MergeResult.applied)) {
        return outcome;
      }
      if (!await _repairMergedParent(remote, parentId)) return outcome;
      if (outcome.moved || local == null) return outcome;
      return outcome.movedFrom(local.parentId);
    });
  }

  /// Re-parents the just-merged [remote] when the parent it arrived under
  /// leaves it reachable from nowhere, and returns whether it did.
  ///
  /// The browser's root list is `parent_id IS NULL` and every live list
  /// filters tombstones, so a folder whose ancestors never reach the root
  /// through a live chain appears under no parent at all — it is findable
  /// only by search, and a backup of it restores with a dangling parent.
  /// The merge itself cannot refuse the parent: stamps and columns travel
  /// verbatim, and no descendant of this row is cascaded (record §3.4).
  ///
  /// Walks the ancestors of [parentId], tombstones included, bounded by
  /// [maxFolderDepth] the way every other folder walk here is:
  ///
  /// - a chain that comes back to [remote] is a cycle (R63): two devices
  ///   each moved one folder under the other, each passing its own local
  ///   descendant check, and the pair plus everything under it left the
  ///   browser. It is cut to the root.
  /// - a chain that starts in tombstones takes the nearest live ancestor,
  ///   the root when there is none (R64): the parent was deleted here while
  ///   this row was written or moved elsewhere, and the merge never
  ///   cascades.
  /// - a chain that runs into a folder this device has not received stands:
  ///   an unknown parent is not a deleted one, and the rest of the space is
  ///   still arriving.
  ///
  /// The repair is stamped locally, so it outranks the move that caused it
  /// and the space converges on the break instead of pushing it back.
  Future<bool> _repairMergedParent(Folder remote, String parentId) async {
    final rows = await db
        .customSelect(
          'WITH RECURSIVE up(id, parent_id, is_deleted, depth) AS ('
          '  SELECT id, parent_id, is_deleted, 0 FROM folders '
          '  WHERE id = ?1 '
          '  UNION ALL '
          '  SELECT f.id, f.parent_id, f.is_deleted, up.depth + 1 '
          '  FROM folders f JOIN up ON f.id = up.parent_id '
          '  WHERE up.depth < $maxFolderDepth'
          ') SELECT id, parent_id, is_deleted FROM up ORDER BY depth',
          variables: [Variable<String>(parentId)],
          readsFrom: {folders},
        )
        .get();
    if (rows.isEmpty) return false;
    var cycle = false;
    var reachedRoot = false;
    String? liveAncestor;
    for (final row in rows) {
      final id = row.read<String>('id');
      if (id == remote.id) {
        cycle = true;
        break;
      }
      if (liveAncestor == null && row.read<int>('is_deleted') == 0) {
        liveAncestor = id;
      }
      reachedRoot = row.read<String?>('parent_id') == null;
    }
    if (!cycle && liveAncestor == parentId) return false;
    // A cycle, or every ancestor tombstoned up to the root: the row belongs
    // at the root. A walk that ran out at a folder this device has not
    // received, or at the depth bound, is left alone.
    final repaired = cycle ? null : liveAncestor;
    if (repaired == null && !cycle && !reachedRoot) return false;
    // Never during the initial merge: the local rows are still the pre-bind
    // ones, so a parent whose live envelope is later in the same pull reads
    // here as a tombstone, and the repair would flatten the subtree and push
    // that move into the space (A7 review R130). The bind's own pull brings
    // every row, and a break that survives it is repaired by the next merge
    // this row takes.
    if (await db.syncDao.getValue(SyncDao.keyBindMergePending) != null) {
      return false;
    }
    // The page advances the clock only once it has committed (R65), so this
    // stamp would otherwise be minted from a clock that has not seen the
    // move it repairs: below it on a device whose wall is behind the writing
    // one's, where the push is denied and the same move re-applies every run
    // (A7 review R131). The drift guard stays on this raise: it happens
    // inside the page's own transaction, which can still roll back with
    // nothing stored behind it (A10 review R157).
    CrdtMerge.advanceClockInTransaction(db, remote.hlcTimestamp);
    final stamp = await db.stampLocal(folders, remote.id);
    await (update(folders)..where((f) => f.id.equals(remote.id))).write(
      FoldersCompanion(
        parentId: Value(repaired),
        updatedAt: Value(DateTime.now()),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(remote.version + 1),
      ),
    );
    return true;
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

enum FolderSortField { name, createdAt, updatedAt, position, label }

/// Sorts unlabelled rows (`label = 0`, [ItemLabel.none]) after labelled ones
/// while leaving the labelled rows in palette order.
///
/// Spelled as raw SQL because it is an *ordering expression*, not a column:
/// no index can supply it, so `FolderSortField.label` sorts in a temp B-tree
/// by design. The note DAO carries the twin of this for the same reason.
const _unlabelledLast = CustomExpression<int>(
  'CASE WHEN label = 0 THEN 1 ELSE 0 END',
);
