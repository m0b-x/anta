import '../database/database.dart';

enum NoteChangeType { created, updated, deleted, moved }

class NoteChange {
  final NoteChangeType type;
  final String noteId;
  final String? folderId;
  final String? sourceFolderId;
  final Note? note;

  const NoteChange({
    required this.type,
    required this.noteId,
    this.folderId,
    this.sourceFolderId,
    this.note,
  });
}
