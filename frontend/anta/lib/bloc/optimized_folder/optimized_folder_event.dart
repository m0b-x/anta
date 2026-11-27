import 'dart:async';

import 'package:equatable/equatable.dart';
import '../../constants/app_constants.dart';
import '../../models/item_label.dart';
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

  /// [pageSize] defaults to the whole parent ([AppConstants.folderLoadCeiling]):
  /// the browser draws a parent's folders in one load and never dispatches
  /// [LoadMoreFolders], so a page size of twenty left every folder past the
  /// twentieth unreachable.
  const LoadFoldersPaginated({
    this.parentId,
    this.page = 1,
    this.pageSize = AppConstants.folderLoadCeiling,
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

/// Writes one folder's colour label. Separate from [UpdateOptimizedFolder]
/// because a label is not a name: it skips the duplicate-name check, which a
/// colour cannot affect.
class SetOptimizedFolderLabel extends OptimizedFolderEvent {
  final String folderId;
  final ItemLabel label;

  const SetOptimizedFolderLabel({required this.folderId, required this.label});

  @override
  List<Object?> get props => [folderId, label];
}

/// Labels a whole selection as one unit: one statement, one reload — the
/// shape [DeleteOptimizedFolders] uses for the same reason.
class SetOptimizedFoldersLabel extends OptimizedFolderEvent {
  final List<String> folderIds;
  final ItemLabel label;

  const SetOptimizedFoldersLabel({
    required this.folderIds,
    required this.label,
  });

  @override
  List<Object?> get props => [folderIds, label];
}

class DeleteOptimizedFolder extends OptimizedFolderEvent {
  final String folderId;
  final String? parentId;

  const DeleteOptimizedFolder({required this.folderId, this.parentId});

  @override
  List<Object?> get props => [folderId, parentId];
}

/// Deletes a whole selection as one unit: one pass, one reload. The per-item
/// event issued in a loop cost a full page reload per picked row.
class DeleteOptimizedFolders extends OptimizedFolderEvent {
  final List<String> folderIds;
  final String? parentId;

  const DeleteOptimizedFolders({required this.folderIds, this.parentId});

  @override
  List<Object?> get props => [folderIds, parentId];
}

class RefreshFolders extends OptimizedFolderEvent {
  /// The parent to read again; null is the root, never "whichever parent the
  /// bloc has open" — once a child page had loaded, that reading left the
  /// root with no way to be named.
  final String? parentId;

  /// The order of the page that asked. Null only from the bloc's own
  /// coalescer, which refreshes the open parent in the order it was loaded
  /// in; a page passes its own, so a parent is never read in the order
  /// another page left behind. A parent or an order other than the open
  /// one re-aims the bloc there.
  final FoldersSortOrder? sortOrder;

  const RefreshFolders({required this.parentId, this.sortOrder});

  @override
  List<Object?> get props => [parentId, sortOrder];
}

/// Reads [parentId]'s folders in [sortOrder] and answers through [done],
/// for a page that is not in front: the bloc emits nothing and stays aimed
/// where it is. A page a launch restore builds under another has no rows of
/// its own until it is revealed, and the reveal must not show a spinner —
/// with predictive back the page underneath is on screen for as long as the
/// gesture is held.
class PeekFolders extends OptimizedFolderEvent {
  final String? parentId;
  final FoldersSortOrder sortOrder;
  final Completer<PaginatedFolders> done;

  // ignore: prefer_const_constructors_in_immutables
  PeekFolders({
    required this.parentId,
    required this.sortOrder,
    required this.done,
  });

  @override
  List<Object?> get props => [parentId, sortOrder];
}
