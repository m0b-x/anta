import '../database/database.dart';

enum FolderChangeType { created, updated, deleted, moved }

class FolderChange {
  final FolderChangeType type;
  final String folderId;
  final String? parentId;
  final String? sourceParentId;
  final Folder? folder;

  const FolderChange({
    required this.type,
    required this.folderId,
    this.parentId,
    this.sourceParentId,
    this.folder,
  });
}
