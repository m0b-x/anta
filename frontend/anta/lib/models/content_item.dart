import 'folder.dart';
import 'movable_item.dart';
import 'note_metadata.dart';

/// Discriminated union representing a single entry in a unified
/// folder + note ordering.
///
/// Folders and notes live in separate tables, each with its own `position`
/// sequence, and the browser shows them as one list, folders first.
/// [ContentItem] is the in-memory wrapper the UI and [MixedReorderService]
/// pass that list around in without leaking the underlying split.
sealed class ContentItem {
  const ContentItem();

  String get id;
  MovableItemKind get kind;

  /// Convenience accessor for callers that already have a default name to
  /// display when a note title is empty.
  String displayName(String fallbackForEmptyNote);

  factory ContentItem.folder(Folder folder) = FolderItem;
  factory ContentItem.note(NoteMetadata metadata) = NoteItem;
}

class FolderItem extends ContentItem {
  final Folder folder;
  const FolderItem(this.folder);

  @override
  String get id => folder.id;

  @override
  MovableItemKind get kind => MovableItemKind.folder;

  @override
  String displayName(String _) => folder.name;
}

class NoteItem extends ContentItem {
  final NoteMetadata metadata;
  const NoteItem(this.metadata);

  @override
  String get id => metadata.id;

  @override
  MovableItemKind get kind => MovableItemKind.note;

  @override
  String displayName(String fallbackForEmptyNote) =>
      metadata.title.isEmpty ? fallbackForEmptyNote : metadata.title;
}

/// The browser's display ordering: every folder, then every note, each group
/// left in the order its own sort preference produced.
///
/// Cross-kind interleaving is not shown — folders are a group with a label of
/// their own — so each kind keeps its own `position` sequence and a reorder
/// within either group round-trips through [MixedReorderService] unchanged.
List<ContentItem> groupFoldersThenNotes({
  required List<Folder> folders,
  required List<NoteMetadata> notes,
}) {
  return [
    for (final folder in folders) FolderItem(folder),
    for (final note in notes) NoteItem(note),
  ];
}

/// Re-sorts an arbitrary unified ordering back into folders-then-notes,
/// preserving each group's relative order. A multi-selection drag can lift a
/// folder and a note together; this is what keeps the optimistic render
/// identical to what the next load will produce.
List<ContentItem> regroupFoldersThenNotes(List<ContentItem> items) {
  return [
    for (final item in items)
      if (item is FolderItem) item,
    for (final item in items)
      if (item is NoteItem) item,
  ];
}
