import 'package:drift/drift.dart';
import '../../models/item_label.dart';
import '../../models/movable_item.dart';
import '../../utils/position_plan.dart';
import '../database.dart';
import '../tables/folders_table.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import 'sync_dao.dart';

part 'folder_dao.g.dart';

/// One folder of a backup restore, for [FolderDao.importFolders]: the
/// archived identity it is copied from, then [FolderDao.importFolder]'s
/// arguments.
typedef FolderImportEntry = ({
  String? archivedId,
  String? parentId,
  String name,
  DateTime createdAt,
  DateTime? updatedAt,
  String? noteSortOrder,
  String? subfolderSortOrder,
  ItemLabel label,
  String? ownerId,
});

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

  /// In the user's manual order, ties on `id` as every folder sort ends: the
  /// move picker lists these and the move undo files a note into the first
  /// one, so the order must be the same on every device a sync copies the
  /// folders to — rowid order, which this had, is not.
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
    query.orderBy([
      (f) => OrderingTerm.asc(f.position),
      (f) => OrderingTerm.asc(f.id),
    ]);
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

    // Every sort ends on `id`, as the note sorts do. Two devices creating a
    // subfolder in one parent both take `max(position) + 1` and the position
    // syncs verbatim, and `created_at` is stored to the second, so ties are
    // ordinary; without `id` they fall to insertion order, which differs per
    // device — and so would the list, a page boundary and every later drag
    // (R71).
    switch (sortField) {
      case FolderSortField.name:
        query.orderBy([
          (f) => OrderingTerm(expression: f.name, mode: orderMode),
          (f) => OrderingTerm(expression: f.id),
        ]);
      case FolderSortField.createdAt:
        query.orderBy([
          (f) => OrderingTerm(expression: f.createdAt, mode: orderMode),
          (f) => OrderingTerm(expression: f.id),
        ]);
      case FolderSortField.updatedAt:
        query.orderBy([
          (f) => OrderingTerm(expression: f.updatedAt, mode: orderMode),
          (f) => OrderingTerm(expression: f.id),
        ]);
      case FolderSortField.position:
        query.orderBy([
          (f) => OrderingTerm(expression: f.position, mode: orderMode),
          (f) => OrderingTerm(expression: f.id),
        ]);
      // Labelled folders first, in palette order, unlabelled last — the note
      // sort's rule, with `name` where the notes use `updated_at DESC`. There
      // is no descending variant, so `ascending` is deliberately not consulted
      // here.
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
      // By name, where every other write of a shared row does nothing: the
      // insert would be skipped, and this would answer with a folder that
      // does not exist.
      if (parentId != null) {
        await db.sharedRowDao.ensureOwn('folders', parentId);
      }
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
      final maxPos = maxPosResult.read(folders.position.max());

      final companion = FoldersCompanion(
        id: Value(id),
        name: Value(name),
        parentId: Value(parentId),
        label: Value(label.storageValue),
        position: Value(nextPosition(maxPos)),
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
      // As [createFolder]: nothing of the person's own is stored under a
      // shared folder, and the import has to hear why.
      if (parentId != null) {
        await db.sharedRowDao.ensureOwn('folders', parentId);
      }
      final now = DateTime.now();
      final id = db.generateId();
      final stamp = await db.stampLocal(folders, id);
      final maxPos = await _maxLivePosition(parentId);

      final companion = FoldersCompanion(
        id: Value(id),
        name: Value(name),
        parentId: Value(parentId),
        label: Value(label.storageValue),
        position: Value(nextPosition(maxPos)),
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

  /// [importFolder] for a whole backup restore, in one transaction and one
  /// batch: one transaction per row made a large tree's restore pay a commit
  /// and a handful of isolate round trips per folder.
  ///
  /// [entries] come parents first; an entry's `parentId` names an earlier
  /// entry by its `archivedId` (the copy that entry became), else an
  /// existing folder as written — only a live one: a parent that is neither
  /// would leave the folder under an id that exists nowhere, invisible in the
  /// browser, so it restores at the root instead, as a note does. Positions
  /// append to each parent exactly as [importFolder] row by row would, stamps
  /// are minted in entry order. Returns each entry's new id, in entry order.
  Future<List<String>> importFolders(List<FolderImportEntry> entries) {
    if (entries.isEmpty) return Future.value(const []);
    return transaction(() async {
      final now = DateTime.now();
      final copies = <String, String>{};
      final unarchivedParents = <String, String?>{};
      final created = <String>{};
      final appendAt = <String?, int>{};
      final ids = <String>[];
      final companions = <FoldersCompanion>[];
      Future<String?> restoredParentId(String archived) async {
        final copy = copies[archived];
        if (copy != null) return copy;
        if (unarchivedParents.containsKey(archived)) {
          return unarchivedParents[archived];
        }
        final live = await getFoldersByIds([archived]);
        return unarchivedParents[archived] = live.isEmpty ? null : archived;
      }

      for (final entry in entries) {
        final archivedParent = entry.parentId;
        final parentId = archivedParent == null
            ? null
            : await restoredParentId(archivedParent);
        if (!appendAt.containsKey(parentId)) {
          appendAt[parentId] = created.contains(parentId)
              ? 0
              : nextPosition(await _maxLivePosition(parentId));
        }
        final position = appendAt[parentId]!;
        appendAt[parentId] = nextPosition(position);

        final id = db.generateId();
        created.add(id);
        ids.add(id);
        final archivedId = entry.archivedId;
        if (archivedId != null) copies[archivedId] = id;
        companions.add(
          FoldersCompanion(
            id: Value(id),
            name: Value(entry.name),
            parentId: Value(parentId),
            label: Value(entry.label.storageValue),
            position: Value(position),
            createdAt: Value(entry.createdAt),
            updatedAt: Value(entry.updatedAt ?? now),
            noteSortOrder: entry.noteSortOrder != null
                ? Value(entry.noteSortOrder)
                : const Value.absent(),
            subfolderSortOrder: entry.subfolderSortOrder != null
                ? Value(entry.subfolderSortOrder)
                : const Value.absent(),
            ownerId: Value(entry.ownerId),
            version: const Value(1),
            isDeleted: const Value(false),
          ),
        );
      }

      final stamps = [for (final _ in companions) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < companions.length; i++) {
          final stamp = stamps[i];
          b.insert(
            folders,
            companions[i].copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
            ),
          );
          db.enqueueIn(b, folders, ids[i], stamp.hlc);
        }
      });
      return ids;
    });
  }

  Future<int?> _maxLivePosition(String? parentId) async {
    final maxPosQuery = selectOnly(folders)
      ..addColumns([folders.position.max()]);
    if (parentId == null) {
      maxPosQuery.where(folders.parentId.isNull());
    } else {
      maxPosQuery.where(folders.parentId.equals(parentId));
    }
    maxPosQuery.where(folders.isDeleted.equals(false));
    final maxPosResult = await maxPosQuery.getSingle();
    return maxPosResult.read(folders.position.max());
  }

  /// Renames or re-parents one folder, and refuses a tombstone, as
  /// [updateFolderPosition] and [updateFolderSortPreferences] do: a page or a
  /// sheet can outlive the folder another device deleted, and a write would
  /// re-stamp its tombstone with this device's id and a fresh HLC, a delete
  /// it never made. The notes repair once read that id as "this device
  /// deleted the folder" and brought the folder's notes back everywhere
  /// (P fix pass PF-H1).
  Future<Folder?> updateFolder({
    required String id,
    String? name,
    String? parentId,
    bool updateParent = false,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return null;
      // An edit that changes nothing writes nothing, so it does not read as a
      // change once devices merge.
      final renames = name != null && name != existing.name;
      final moves = updateParent && parentId != existing.parentId;
      if (!renames && !moves) return existing;

      final shared = moves ? await _sharedPairOf(id) : null;
      final now = DateTime.now();
      final stamp = await db.stampLocal(folders, id);

      final companion = FoldersCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        parentId: updateParent ? Value(parentId) : const Value.absent(),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      );

      await (update(folders)..where((f) => f.id.equals(id))).write(companion);
      if (moves) await _requeueSubtreeIfShareChanged(id, shared);
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

      final shared = await _sharedPairOf(id);
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
      final maxPos = maxPosResult.read(folders.position.max());

      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          parentId: Value(targetParentId),
          position: Value(nextPosition(maxPos)),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      await _requeueSubtreeIfShareChanged(id, shared);
      return getFolderById(id);
    });
  }

  /// Moves a whole selection of folders under [targetParentId] (the root
  /// when null) in one transaction, under one HLC — the folder twin of
  /// [NoteDao.moveNotes].
  ///
  /// The sibling-name rule [folderNameExistsInParent] enforces for one folder
  /// holds per item, the root included: a folder whose name the target
  /// already holds, or one an earlier folder of [ids] claims, is reported in
  /// [BulkMoveResult.duplicates] and stays where it is. A folder that is the
  /// target or one of its ancestors cannot move under it and is left out of
  /// every set, as [moveFolder] returns null for it.
  Future<BulkMoveResult> moveFolders(
    List<String> ids,
    String? targetParentId,
  ) async {
    final unique = ids.toSet().toList(growable: false);
    if (unique.isEmpty) return BulkMoveResult.empty;
    final now = DateTime.now();

    return transaction(() async {
      final blocked = <String>{};
      if (targetParentId != null) {
        final target = await getFolderById(targetParentId);
        if (target == null || target.isDeleted) return BulkMoveResult.empty;
        // The target's own chain upwards: a folder on it would become its own
        // ancestor. Walked up rather than down each selected subtree, so it
        // is one statement however many folders were picked.
        final chain = await customSelect(
          'WITH RECURSIVE a(id, depth) AS ('
          '  SELECT ?1, 0 '
          '  UNION ALL '
          '  SELECT f.parent_id, a.depth + 1 FROM folders f '
          '  JOIN a ON f.id = a.id '
          '  WHERE f.parent_id IS NOT NULL AND a.depth < $maxFolderDepth'
          ') SELECT id FROM a',
          variables: [Variable<String>(targetParentId)],
          readsFrom: {folders},
        ).get();
        blocked.addAll([for (final row in chain) row.read<String>('id')]);
      }

      final found = <String, BulkMoveCandidate>{};
      for (final chunk in bulkMoveChunks(unique)) {
        final rows = await customSelect(
          'SELECT id, parent_id, name, LOWER(TRIM(name)) AS sql_key '
          'FROM folders WHERE id IN '
          '(${List.filled(chunk.length, '?').join(', ')}) AND is_deleted = 0',
          variables: [for (final id in chunk) Variable<String>(id)],
          readsFrom: {folders},
        ).get();
        for (final row in rows) {
          found[row.read<String>('id')] = (
            parentId: row.read<String?>('parent_id'),
            name: row.read<String>('name'),
            sqlKey: row.read<String>('sql_key'),
          );
        }
      }
      // The movers' names folded in Dart and bound as the single-folder
      // check binds its key; `COALESCE` matches idx_folders_parent_lname.
      final keys = {
        for (final row in found.values)
          if (row.parentId != targetParentId) ?bulkMoveNameKey(row.name),
      }.toList();
      final taken = <String>{};
      for (final chunk in bulkMoveChunks(keys)) {
        final rows = await customSelect(
          'SELECT DISTINCT LOWER(TRIM(name)) AS sql_key FROM folders '
          "WHERE COALESCE(parent_id, '') = ? AND is_deleted = 0 "
          'AND LOWER(TRIM(name)) IN '
          '(${List.filled(chunk.length, '?').join(', ')})',
          variables: [
            Variable<String>(targetParentId ?? ''),
            for (final key in chunk) Variable<String>(key),
          ],
          readsFrom: {folders},
        ).get();
        taken.addAll([for (final row in rows) row.read<String>('sql_key')]);
      }
      final plan = planBulkMove(
        ids: unique,
        found: found,
        target: targetParentId,
        taken: taken,
        blocked: blocked,
      );
      final moved = plan.moved;
      if (moved.isEmpty) return plan;

      final shared = await sharedPairsOf(moved.keys);
      var last = await _maxLivePosition(targetParentId);
      final stamp = db.newStamp();
      await batch((b) {
        for (final id in moved.keys) {
          b.update(
            folders,
            FoldersCompanion.custom(
              parentId: Variable<String>(targetParentId),
              position: Variable<int>(last = nextPosition(last)),
              updatedAt: Variable<DateTime>(now),
              hlcTimestamp: Variable<String>(stamp.hlc),
              deviceId: Variable<String>(stamp.deviceId),
              version: folders.version + const Constant(1),
            ),
            where: (f) => f.id.equals(id),
          );
        }
      });
      await db.enqueueMany(folders, moved.keys, stamp.hlc);
      // What each moved folder shares its subtree into follows the place it
      // landed in: the rows under it say so only once they are pushed again.
      final landed = await sharedPairsOf(moved.keys);
      for (final id in moved.keys) {
        if (landed[id] != shared[id]) await _requeueSubtree(id);
      }
      return plan;
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

  /// Update the position of a folder; a tombstone is refused, for the reason
  /// [updateFolder] gives.
  Future<Folder?> updateFolderPosition({
    required String id,
    required int newPosition,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return null;

      final now = DateTime.now();
      final stamp = await db.stampLocal(folders, id);

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
  /// `version + 1` arithmetic itself, the same way [applyOrder]
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

  /// Writes the custom order a drag left in [parentId]'s subfolders (the
  /// root when null), returning the ids whose position changed — the folder
  /// twin of [NoteDao.applyOrder], read, planned and written in one
  /// transaction the same way.
  Future<List<String>> applyOrder({
    required String? parentId,
    required List<String> loadedOrder,
    required bool descending,
    bool windowAtTop = false,
  }) async {
    if (loadedOrder.isEmpty) return const [];

    return transaction(() async {
      final direction = descending ? 'DESC' : 'ASC';
      final rows = await customSelect(
        'SELECT id, position FROM folders '
        'WHERE ${parentId == null ? 'parent_id IS NULL' : 'parent_id = ?'} '
        'AND is_deleted = 0 ORDER BY position $direction, id',
        variables: [if (parentId != null) Variable<String>(parentId)],
        readsFrom: {folders},
      ).get();
      final current = <PositionedId>[
        for (final row in rows)
          (id: row.read<String>('id'), position: row.read<int>('position')),
      ];
      final changes = planGappedPositions(
        current: current,
        order: spliceLoadedOrder(
          displayOrder: [for (final row in current) row.id],
          loadedOrder: loadedOrder,
          windowAtTop: windowAtTop,
        ),
        descending: descending,
      );
      if (changes.isEmpty) return const <String>[];

      final stamp = db.newStamp();
      await batch((b) {
        for (final MapEntry(key: id, value: position) in changes.entries) {
          b.update(
            folders,
            FoldersCompanion.custom(
              position: Variable<int>(position),
              hlcTimestamp: Variable<String>(stamp.hlc),
              deviceId: Variable<String>(stamp.deviceId),
              version: folders.version + const Constant(1),
            ),
            where: (f) => f.id.equals(id) & f.isDeleted.equals(false),
          );
        }
      });
      final moved = changes.keys.toList(growable: false);
      await db.enqueueMany(folders, moved, stamp.hlc);
      return moved;
    });
  }

  /// Update sort preferences for a folder; a tombstone is refused, for the
  /// reason [updateFolder] gives — the sort menu of a page left open on a
  /// folder another device deleted.
  Future<Folder?> updateFolderSortPreferences({
    required String id,
    String? noteSortOrder,
    String? subfolderSortOrder,
    bool clearNoteSortOrder = false,
    bool clearSubfolderSortOrder = false,
  }) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return null;
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
      final stamp = await db.stampLocal(folders, id);

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

      // 1. Bulk soft-delete notes in any of these folders.
      final placeholders = List.filled(descendantIds.length, '?').join(',');

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
      final noteIds = [for (final row in noteRows) row.read<String>('id')];
      await db.contentChunkDao.deleteChunksForNotes(noteIds);
      if (noteIds.isNotEmpty) {
        await db.counterDao.tombstoneValuesOfDeletedNotes(stamp, now);
      }

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
        noteIds,
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

  /// The pair each folder among [ids] is shared into, by id: its own mark,
  /// else the mark of the nearest folder above it; a folder under no mark
  /// has no entry (`docs/cloud-sharing-foundations.md` §3). Tombstones are
  /// walked like any row, and keep their place in what is shared — the
  /// partner has to hear of a delete.
  ///
  /// One statement when nothing is shared, which is nearly always; else the
  /// table's ids and parents once, however many folders are asked for. The
  /// walk is bounded by [maxFolderDepth], as every folder walk here is.
  Future<Map<String, String>> sharedPairsOf(Iterable<String> ids) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return const {};
    final marked = await customSelect(
      'SELECT id, shared_pair FROM folders WHERE shared_pair IS NOT NULL',
      readsFrom: {folders},
    ).get();
    if (marked.isEmpty) return const {};
    final marks = {
      for (final row in marked)
        row.read<String>('id'): row.read<String>('shared_pair'),
    };
    final parents = {
      for (final row in await customSelect(
        'SELECT id, parent_id FROM folders',
        readsFrom: {folders},
      ).get())
        row.read<String>('id'): row.read<String?>('parent_id'),
    };
    final pairs = <String, String>{};
    for (final id in wanted) {
      String? at = id;
      for (var depth = 0; at != null && depth <= maxFolderDepth; depth++) {
        final pair = marks[at];
        if (pair != null) {
          pairs[id] = pair;
          break;
        }
        at = parents[at];
      }
    }
    return pairs;
  }

  /// The newest stamp among each folder of [ids] and the folders above it,
  /// by id — the newest write this device holds that decides what the
  /// folder, and a note in it, is shared into: a mark set or cleared and a
  /// move are each a write of a folder on that chain
  /// (`SyncTableBinding.shareStamps`). An unknown id has no entry; the walk
  /// is bounded by [maxFolderDepth].
  Future<Map<String, String>> shareStampsOf(Iterable<String> ids) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return const {};
    final rows = {
      for (final row in await customSelect(
        'SELECT id, parent_id, hlc_timestamp FROM folders',
        readsFrom: {folders},
      ).get())
        row.read<String>('id'): (
          parent: row.read<String?>('parent_id'),
          hlc: row.read<String>('hlc_timestamp'),
        ),
    };
    final stamps = <String, String>{};
    for (final id in wanted) {
      String? newest;
      String? at = id;
      for (var depth = 0; at != null && depth <= maxFolderDepth; depth++) {
        final row = rows[at];
        if (row == null) break;
        if (newest == null || row.hlc.compareTo(newest) > 0) newest = row.hlc;
        at = row.parent;
      }
      if (newest != null) stamps[id] = newest;
    }
    return stamps;
  }

  /// The pair this database's shared notes are shared into — what a push
  /// writes on the space document, by which a partner may fetch the text
  /// of a note shared with them (`docs/cloud-sharing-foundations.md` §4) —
  /// or null when no live folder carries a mark. A database shares into one
  /// pair ([setSharedPair]); two devices marking at once can leave two for
  /// a moment, and then every device names the same one.
  Future<String?> sharedPairOfNotes() async {
    final row = await customSelect(
      'SELECT MAX(shared_pair) AS pair FROM folders '
      'WHERE shared_pair IS NOT NULL AND is_deleted = 0',
      readsFrom: {folders},
    ).getSingle();
    return row.read<String?>('pair');
  }

  /// Shares the live folder [id] and everything under it into [pairId], or
  /// takes its mark away when null — the one writer of `shared_pair` on
  /// this table (`docs/cloud-sharing-foundations.md` §3). A stamped write
  /// of the one column, so the owner's other devices merge the mark like
  /// any edit; `updated_at` is left alone, as a label's write leaves it.
  ///
  /// Setting a mark clears, in the same transaction and under the same
  /// stamp, every mark inside the folder's own subtree — the outer one now
  /// covers them — and every mark of another pair, here and on
  /// `calendar_events`: a database shares into one pair.
  ///
  /// The folders and notes under it are queued again at the stamps they
  /// carry ([_requeueSubtree]): their documents say who may read them from
  /// this mark, and only a push writes that.
  ///
  /// A missing or tombstoned folder writes nothing, and neither does a mark
  /// the folder already carries — though the marks of other pairs are
  /// cleared even then. Returns whether the folder's mark was written.
  Future<bool> setSharedPair(String id, String? pairId) {
    return transaction(() async {
      final existing = await getFolderById(id);
      if (existing == null || existing.isDeleted) return false;
      // Another account's folder is theirs to share.
      if (await db.sharedRowDao.isShared('folders', id)) return false;
      // One stamp for the whole act: the mark and whatever it clears.
      final stamp = db.newStamp();
      if (pairId != null) {
        await clearOtherPairs(pairId, stamp);
        await db.calendarEventDao.clearOtherPairs(pairId, stamp);
      }
      if (existing.sharedPair == pairId) return false;
      if (pairId != null) {
        await _clearMarks(
          stamp,
          where: 'shared_pair IS NOT NULL AND id IN (${_descendantsOf('?3')})',
          variables: [Variable<String>(id)],
          requeue: false,
        );
      }
      await db.enqueue(folders, id, stamp.hlc);
      await (update(folders)..where((f) => f.id.equals(id))).write(
        FoldersCompanion(
          sharedPair: Value(pairId),
          sharedStamp: Value(stamp.hlc),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      await _requeueSubtree(id);
      return true;
    });
  }

  /// Clears, under [stamp], the mark of every folder shared into another
  /// pair than [pairId] — every mark there is when null — each row queued
  /// and its subtree queued again: its half of "a database shares into one
  /// pair", called inside the transaction of the write that sets a mark
  /// ([setSharedPair], [CalendarEventDao.setSharedPair]) and when the
  /// account's pair is found changed or ended. Tombstones too: their
  /// documents would go on naming a pair this database no longer shares
  /// into. Returns how many it cleared.
  Future<int> clearOtherPairs(String? pairId, CrdtStamp stamp) => _clearMarks(
    stamp,
    where: 'shared_pair IS NOT NULL AND shared_pair IS NOT ?3',
    variables: [Variable<String>(pairId)],
    requeue: true,
  );

  /// Clears every share mark of a pair other than [pairId] — every mark
  /// there is when null — on folders and on events alike, under one stamp:
  /// what the account's pair, as the server shows it, leaves standing
  /// (`docs/cloud-sharing-foundations.md` §2 c). A share must not outlive
  /// its pair on the owner's side either, and a merge alone can leave two
  /// pairs' marks side by side. Returns how many marks it cleared.
  Future<int> clearSharesExcept(String? pairId) {
    return transaction(() async {
      final stamp = db.newStamp();
      final folders = await _clearMarks(
        stamp,
        where: 'shared_pair IS NOT NULL AND shared_pair IS NOT ?3',
        variables: [Variable<String>(pairId)],
        requeue: true,
      );
      return folders + await db.calendarEventDao.clearOtherPairs(pairId, stamp);
    });
  }

  /// Sets `shared_pair` to NULL under [stamp] on the folders [where]
  /// selects — its numbered parameters start at `?3`, bound from
  /// [variables] — and queues each; [requeue] queues their subtrees again
  /// too, for a mark no outer write's own re-queue covers. Returns how many
  /// it cleared.
  Future<int> _clearMarks(
    CrdtStamp stamp, {
    required String where,
    required List<Variable<Object>> variables,
    required bool requeue,
  }) async {
    final cleared = await customWriteReturning(
      'UPDATE folders SET shared_pair = NULL, shared_stamp = ?1, '
      'hlc_timestamp = ?1, device_id = ?2, version = version + 1 '
      'WHERE $where RETURNING id, is_deleted',
      variables: [
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        ...variables,
      ],
      updates: {folders},
      updateKind: UpdateKind.update,
    );
    if (cleared.isEmpty) return 0;
    for (final deleted in const [false, true]) {
      await db.enqueueMany(
        folders,
        [
          for (final row in cleared)
            if (row.read<bool>('is_deleted') == deleted) row.read<String>('id'),
        ],
        stamp.hlc,
        op: OutboxOp.forRow(isDeleted: deleted),
      );
    }
    if (requeue) {
      for (final row in cleared) {
        await _requeueSubtree(row.read<String>('id'));
      }
    }
    return cleared.length;
  }

  /// A query for the ids of every folder under the folder bound at
  /// [folder] (a numbered parameter), tombstones included — unlike
  /// [getAllDescendantIds], whose walk a tombstone ends: a deleted folder's
  /// document says who may read it too.
  static String _descendantsOf(String folder) =>
      'WITH RECURSIVE d(id, depth) AS ('
      '  SELECT id, 0 FROM folders WHERE parent_id = $folder '
      '  UNION ALL '
      '  SELECT f.id, d.depth + 1 FROM folders f '
      '  JOIN d ON f.parent_id = d.id WHERE d.depth < $maxFolderDepth'
      ') SELECT id FROM d';

  /// Queues again, at the stamps they carry, every folder and note under
  /// the folder [id], tombstones included: their documents say who may read
  /// them from the nearest mark above, and only a push writes that
  /// ([CrdtWrite.requeueRows]). Every one this device may push — its own,
  /// whatever `owner_id` spells that as ([SyncDao.mineSql]) — and never a
  /// row another account shares with it. The folder itself is its caller's
  /// write.
  Future<void> _requeueSubtree(String id) async {
    final under = _descendantsOf('?2');
    const own = SyncDao.mineSql;
    final folder = [Variable<String>(id)];
    await db.requeueRows(
      folders,
      rows: 'id IN ($under) AND $own',
      variables: folder,
    );
    await db.requeueRows(
      db.notes,
      rows: '(folder_id = ?2 OR folder_id IN ($under)) AND $own',
      variables: folder,
    );
  }

  /// The pair the folder [id] is shared into as it stands — its own mark or
  /// the nearest above it — for a write that may move it under another.
  Future<String?> _sharedPairOf(String id) async =>
      (await sharedPairsOf([id]))[id];

  /// Queues the subtree of [id] again when the pair it is shared into is no
  /// longer [before], the one it had ahead of a move or a merge.
  Future<void> _requeueSubtreeIfShareChanged(String id, String? before) async {
    if (await _sharedPairOf(id) != before) await _requeueSubtree(id);
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
  ///
  /// The share mark is settled apart from the row ([CrdtMerge.mergeMark]):
  /// the mark stamped later stands whichever side's row won, so a rename or
  /// a move made where a share's end had not arrived cannot bring the share
  /// back. A tombstone carries no mark, and the one here stands.
  ///
  /// A merge that changes what the folder shares its subtree into — its
  /// mark, or the place it hangs in, the repair's included — queues this
  /// device's copies of the rows under it again ([_requeueSubtree]): a
  /// device that pushed one before it had merged the change wrote a
  /// document that says the old grant, and only the device holding the row
  /// can say it again. A folder that arrives new brings nothing to queue
  /// unless it carries a mark itself. What it shared into before is read
  /// only when the merge can change it: the row is written, or the two
  /// marks differ.
  ///
  /// [shared] merges a folder another account shares with this one
  /// (`docs/cloud-sharing-foundations.md` §5): the owner's copy wins
  /// whatever the stamps say, it carries no mark here — its caller took the
  /// owner's off — and nothing is repaired or queued: a write of this
  /// device's own on that account's row would never be sent, and would only
  /// hide the owner's next change of it.
  Future<MergeOutcome> mergeFolder(
    Folder remote, {
    String? floor,
    bool shared = false,
  }) {
    return transaction(() async {
      final local = await getFolderById(remote.id);
      if (shared) {
        final merged = await _mergeFolder(
          remote,
          local,
          CrdtMerge.everyStamp,
          repairs: false,
        );
        return merged.outcome;
      }
      final live = !remote.isDeleted;
      final writes =
          live &&
          CrdtMerge.remoteWrites(
            remoteHlc: remote.hlcTimestamp,
            localHlc: local?.hlcTimestamp,
            floor: floor,
          );
      final marksDiffer =
          live &&
          local != null &&
          (local.sharedPair != remote.sharedPair ||
              local.sharedStamp != remote.sharedStamp);
      final sharedBefore = local != null && (writes || marksDiffer)
          ? await _sharedPairOf(remote.id)
          : null;
      final (:outcome, :repaired) = await _mergeFolder(remote, local, floor);
      if (!live) return outcome;
      final kept = await CrdtMerge.mergeMark(
        db,
        table: folders,
        rowKey: remote.id,
        local: local == null
            ? null
            : (pair: local.sharedPair, stamp: local.sharedStamp),
        remote: (pair: remote.sharedPair, stamp: remote.sharedStamp),
        result: outcome.result,
        write: (mark) =>
            (update(folders)..where((f) => f.id.equals(remote.id))).write(
              FoldersCompanion(
                sharedPair: Value(mark.pair),
                sharedStamp: Value(mark.stamp),
              ),
            ),
      );
      final wrote =
          outcome.result == MergeResult.inserted ||
          outcome.result == MergeResult.applied;
      if (local == null
          ? kept.pair != null || repaired
          : wrote || marksDiffer) {
        await _requeueSubtreeIfShareChanged(remote.id, sharedBefore);
      }
      return outcome;
    });
  }

  /// [mergeFolder]'s merge and repair, inside its transaction, with whether
  /// the repair re-parented the row; none is attempted unless [repairs].
  Future<({MergeOutcome outcome, bool repaired})> _mergeFolder(
    Folder remote,
    Folder? local,
    String? floor, {
    bool repairs = true,
  }) async {
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
    if (!repairs ||
        remote.isDeleted ||
        parentId == null ||
        (outcome.result != MergeResult.inserted &&
            outcome.result != MergeResult.applied)) {
      return (outcome: outcome, repaired: false);
    }
    if (!await _repairMergedParent(remote, parentId)) {
      return (outcome: outcome, repaired: false);
    }
    if (outcome.moved || local == null) {
      return (outcome: outcome, repaired: true);
    }
    return (outcome: outcome.movedFrom(local.parentId), repaired: true);
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
    query.orderBy([
      (f) => OrderingTerm.asc(f.name),
      (f) => OrderingTerm.asc(f.id),
    ]);
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
