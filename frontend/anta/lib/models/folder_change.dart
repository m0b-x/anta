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
