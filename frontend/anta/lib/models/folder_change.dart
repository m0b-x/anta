import '../database/database.dart';

/// What happened to a folder, as the change stream tells its subscribers.
///
/// [labelled] is kept apart from [updated] so the folder-name index can
/// ignore it: a colour changes no name.
enum FolderChangeType { created, updated, deleted, moved, labelled }

class FolderChange {
  final FolderChangeType type;
  final String folderId;
  final String? parentId;
  final String? sourceParentId;
  final Folder? folder;

  /// Whether a sync pull merged the change from another device, rather than
  /// this device writing it.
  ///
  /// Nothing reads it yet — it is symmetry with `NoteChange.remote`, which the
  /// editor does read. Kept for the first folder surface that needs to tell a
  /// merge apart from a local write; not load-bearing (review 2026-10-26, R42).
  final bool remote;

  const FolderChange({
    required this.type,
    required this.folderId,
    this.parentId,
    this.sourceParentId,
    this.folder,
    this.remote = false,
  });
}
