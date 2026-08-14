import 'package:equatable/equatable.dart';
import '../../services/folder_storage_service.dart';

/// Sealed state class for OptimizedFolderBloc with exhaustiveness checking
sealed class OptimizedFolderState extends Equatable {
  const OptimizedFolderState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any action
final class OptimizedFolderInitial extends OptimizedFolderState {
  const OptimizedFolderInitial();
}

/// Loading state while fetching folders
final class OptimizedFolderLoading extends OptimizedFolderState {
  final String? parentId;

  const OptimizedFolderLoading({this.parentId});

  @override
  List<Object?> get props => [parentId];
}

/// Successfully loaded paginated folders
final class OptimizedFolderLoaded extends OptimizedFolderState {
  final PaginatedFolders paginatedFolders;
  final bool isLoadingMore;
  final String? parentId;

  const OptimizedFolderLoaded({
    required this.paginatedFolders,
    this.isLoadingMore = false,
    this.parentId,
  });

  OptimizedFolderLoaded copyWith({
    PaginatedFolders? paginatedFolders,
    bool? isLoadingMore,
    String? parentId,
  }) {
    return OptimizedFolderLoaded(
      paginatedFolders: paginatedFolders ?? this.paginatedFolders,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      parentId: parentId ?? this.parentId,
    );
  }

  @override
  List<Object?> get props => [paginatedFolders, isLoadingMore, parentId];
}

/// Error state with typed error information
final class OptimizedFolderError extends OptimizedFolderState {
  final String message;
  final String? parentId;
  final FolderErrorType errorType;

  const OptimizedFolderError(
    this.message, {
    this.parentId,
    this.errorType = FolderErrorType.unknown,
  });

  @override
  List<Object?> get props => [message, parentId, errorType];
}

/// Types of errors that can occur in folder operations
enum FolderErrorType {
  notFound,
  loadFailed,
  createFailed,
  updateFailed,
  deleteFailed,
  unknown,
}
