import 'folder.dart';
import 'movable_item.dart';
import 'note_metadata.dart';

/// Discriminated union representing a single entry in a unified
/// folder + note ordering.
///
/// Folders and notes live in separate tables with separate `position`
/// columns, but the user-visible order in selection / position mode is a
/// single shared sequence. [ContentItem] is the in-memory wrapper used by
/// the UI and by [MixedReorderService] to operate on that unified sequence
/// without leaking the underlying split.
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
/// Cross-kind interleaving is no longer shown — folders are a group with a
/// label of their own — but the two `position` columns still share one index
/// space, so a reorder within either group round-trips through
/// [MixedReorderService] unchanged.
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

/// Stable client-side merge of two already-sorted (by `position` ascending)
/// lists into a single unified ordering. When both items share the same
/// position, folders win the tie so the result is deterministic.
List<ContentItem> mergeByPosition({
  required List<Folder> folders,
  required List<NoteMetadata> notes,
}) {
  final result = <ContentItem>[];
  var i = 0;
  var j = 0;
  while (i < folders.length && j < notes.length) {
    if (folders[i].position <= notes[j].position) {
      result.add(FolderItem(folders[i++]));
    } else {
      result.add(NoteItem(notes[j++]));
    }
  }
  while (i < folders.length) {
    result.add(FolderItem(folders[i++]));
  }
  while (j < notes.length) {
    result.add(NoteItem(notes[j++]));
  }
  return result;
}
