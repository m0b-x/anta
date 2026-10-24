import '../database/database.dart';

/// What happened to a note, as the change stream tells its subscribers.
///
/// [labelled] is kept apart from [updated] because the two say different
/// things to the search index: an update means the title or body moved and
/// the note must be re-indexed, a label means neither did and the index has
/// nothing to do. Listeners that only care *which folder* changed treat the
/// two alike.
enum NoteChangeType { created, updated, deleted, moved, labelled }

class NoteChange {
  final NoteChangeType type;
  final String noteId;
  final String? folderId;
  final String? sourceFolderId;
  final Note? note;

  /// Whether a sync pull merged the change from another device, rather than
  /// this device writing it: an open editor reloads or files a copy on a
  /// remote change and must not on its own autosave (record §3.9).
  final bool remote;

  const NoteChange({
    required this.type,
    required this.noteId,
    this.folderId,
    this.sourceFolderId,
    this.note,
    this.remote = false,
  });
}
