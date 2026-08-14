import 'package:equatable/equatable.dart';
import '../../services/folder_storage_service.dart';

abstract class OptimizedFolderEvent extends Equatable {
  const OptimizedFolderEvent();

  @override
  List<Object?> get props => [];
}

class LoadFoldersPaginated extends OptimizedFolderEvent {
  final String? parentId;
  final int page;
  final int pageSize;
  final FoldersSortOrder sortOrder;

  const LoadFoldersPaginated({
    this.parentId,
    this.page = 1,
    this.pageSize = 20,
    this.sortOrder = FoldersSortOrder.nameAsc,
  });

  @override
  List<Object?> get props => [parentId, page, pageSize, sortOrder];
}

class LoadMoreFolders extends OptimizedFolderEvent {
  final String? parentId;

  const LoadMoreFolders({this.parentId});

  @override
  List<Object?> get props => [parentId];
}

class CreateOptimizedFolder extends OptimizedFolderEvent {
  final String name;
  final String? parentId;

  const CreateOptimizedFolder({required this.name, this.parentId});

  @override
  List<Object?> get props => [name, parentId];
}

class UpdateOptimizedFolder extends OptimizedFolderEvent {
  final String folderId;
  final String? name;

  const UpdateOptimizedFolder({required this.folderId, this.name});

  @override
  List<Object?> get props => [folderId, name];
}

class DeleteOptimizedFolder extends OptimizedFolderEvent {
  final String folderId;
  final String? parentId;

  const DeleteOptimizedFolder({required this.folderId, this.parentId});

  @override
  List<Object?> get props => [folderId, parentId];
}

class RefreshFolders extends OptimizedFolderEvent {
  final String? parentId;

  const RefreshFolders({this.parentId});

  @override
  List<Object?> get props => [parentId];
}

class ReorderFolders extends OptimizedFolderEvent {
  final String? parentId;
  final List<String> orderedIds;

  const ReorderFolders({this.parentId, required this.orderedIds});

  @override
  List<Object?> get props => [parentId, orderedIds];
}
