import 'package:equatable/equatable.dart';

/// Where a search looks.
///
/// A folder scope is **recursive**: it stands for the folder and everything
/// under it, which the search service resolves through
/// `FolderStorageService.subtreeIds`. Nothing here holds the id set itself —
/// a subtree changes whenever a folder is created or moved, so it is read at
/// query time rather than carried in the scope.
sealed class SearchScope extends Equatable {
  const SearchScope();

  const factory SearchScope.everywhere() = EverywhereScope;

  const factory SearchScope.folder({
    required String folderId,
    required String name,
  }) = FolderScope;

  /// The folder a scope is anchored to, or `null` for [EverywhereScope].
  String? get folderId;

  @override
  List<Object?> get props => [];
}

final class EverywhereScope extends SearchScope {
  const EverywhereScope();

  @override
  String? get folderId => null;
}

final class FolderScope extends SearchScope {
  @override
  final String folderId;

  /// The folder's name as the chip should render it. Empty when the caller
  /// had no title to hand, which the chip renders as "This folder".
  final String name;

  const FolderScope({required this.folderId, required this.name});

  @override
  List<Object?> get props => [folderId, name];
}
