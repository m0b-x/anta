import '../constants/app_constants.dart';

/// Discriminator for items that can participate in move/selection flows.
enum MovableItemKind { folder, note }

/// A lightweight, value-equal reference to an item that can be selected
/// and moved. Used by selection mode, drag-and-drop, and batch-move flows
/// so they remain agnostic of `Folder` / `NoteMetadata` concrete types.
class MovableItemRef {
  final MovableItemKind kind;
  final String id;

  /// Display name (folder name or note title). Used for snackbars / drag preview.
  final String name;

  /// Current parent (folder.parentId for folders, note.folderId for notes).
  /// Null for root-level folders.
  final String? currentParentId;

  const MovableItemRef({
    required this.kind,
    required this.id,
    required this.name,
    required this.currentParentId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovableItemRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// What one set-based move did with each id it was given, so the caller can
/// keep reporting per item. An id in none of the three sets was not moved
/// for another reason: it is gone, the target is gone, or the target sits
/// inside it.
class BulkMoveResult {
  const BulkMoveResult({
    this.moved = const {},
    this.duplicates = const {},
    this.unchanged = const {},
  });

  /// The ids written under the target, each mapped to the parent it left,
  /// in the order they were given.
  final Map<String, String?> moved;

  /// Ids refused because the target, or an earlier id of the same batch,
  /// already holds that name.
  final Set<String> duplicates;

  /// Ids already under the target: nothing to write.
  final Set<String> unchanged;

  /// The result of a move that wrote nothing: an empty selection, or a
  /// target that is gone.
  static const empty = BulkMoveResult();
}

/// One candidate of a bulk move as its row stands: [parentId] where it is,
/// [name] its title or name, [sqlKey] that name as `LOWER(TRIM(…))` folds it.
typedef BulkMoveCandidate = ({String? parentId, String name, String sqlKey});

/// The key the single-item check folds a mover's name to, in Dart
/// (`trim().toLowerCase()`, Unicode-aware), or null when the trimmed name is
/// empty and so exempt.
String? bulkMoveNameKey(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? null : trimmed.toLowerCase();
}

/// Sorts [ids] into a [BulkMoveResult] by the rule the single-item move
/// enforces: a mover whose Dart key ([bulkMoveNameKey]) the target already
/// holds — [taken], the target's SQL keys among those Dart keys — or an
/// earlier mover's SQL key matches is a duplicate; [blocked] ids and ids
/// missing from [found] are in no set.
BulkMoveResult planBulkMove({
  required List<String> ids,
  required Map<String, BulkMoveCandidate> found,
  required String? target,
  required Set<String> taken,
  Set<String> blocked = const {},
}) {
  final claimed = {...taken};
  final moved = <String, String?>{};
  final duplicates = <String>{};
  final unchanged = <String>{};
  for (final id in ids) {
    final row = found[id];
    if (row == null || blocked.contains(id)) continue;
    if (row.parentId == target) {
      unchanged.add(id);
      continue;
    }
    final key = bulkMoveNameKey(row.name);
    if (key != null && claimed.contains(key)) {
      duplicates.add(id);
      continue;
    }
    if (key != null) claimed.add(row.sqlKey);
    moved[id] = row.parentId;
  }
  return BulkMoveResult(
    moved: moved,
    duplicates: duplicates,
    unchanged: unchanged,
  );
}

/// [items] cut into lists of at most [AppConstants.sqlIdBatch], the one
/// ceiling every `IN (…)` list in the app binds under.
Iterable<List<T>> bulkMoveChunks<T>(List<T> items) sync* {
  const chunk = AppConstants.sqlIdBatch;
  for (var i = 0; i < items.length; i += chunk) {
    final end = i + chunk;
    yield items.sublist(i, end > items.length ? items.length : end);
  }
}
