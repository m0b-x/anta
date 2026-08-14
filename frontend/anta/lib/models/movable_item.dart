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
