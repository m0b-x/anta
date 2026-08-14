import 'package:equatable/equatable.dart';
import '../../models/note_metadata.dart';
import '../../services/folder_search_service.dart';

/// Sealed state class for OptimizedNoteBloc with exhaustiveness checking
sealed class OptimizedNoteState extends Equatable {
  const OptimizedNoteState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any action
final class OptimizedNoteInitial extends OptimizedNoteState {
  const OptimizedNoteInitial();
}

/// Loading state while fetching notes
final class OptimizedNoteLoading extends OptimizedNoteState {
  final String? folderId;

  const OptimizedNoteLoading({this.folderId});

  @override
  List<Object?> get props => [folderId];
}

/// Successfully loaded paginated notes
final class OptimizedNoteLoaded extends OptimizedNoteState {
  final PaginatedNotes paginatedNotes;
  final Map<String, String> loadedContent;
  final bool isLoadingMore;
  final String? folderId;

  const OptimizedNoteLoaded({
    required this.paginatedNotes,
    this.loadedContent = const {},
    this.isLoadingMore = false,
    this.folderId,
  });

  OptimizedNoteLoaded copyWith({
    PaginatedNotes? paginatedNotes,
    Map<String, String>? loadedContent,
    bool? isLoadingMore,
    String? folderId,
  }) {
    return OptimizedNoteLoaded(
      paginatedNotes: paginatedNotes ?? this.paginatedNotes,
      loadedContent: loadedContent ?? this.loadedContent,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      folderId: folderId ?? this.folderId,
    );
  }

  @override
  List<Object?> get props => [
    paginatedNotes,
    loadedContent,
    isLoadingMore,
    folderId,
  ];
}

/// Note content loaded for editing/viewing
final class OptimizedNoteContentLoaded extends OptimizedNoteState {
  final LazyNote note;
  final PaginatedNotes? previousPaginatedNotes;
  final String? folderId;

  const OptimizedNoteContentLoaded({
    required this.note,
    this.previousPaginatedNotes,
    this.folderId,
  });

  @override
  List<Object?> get props => [note, previousPaginatedNotes, folderId];
}

/// Search results state
final class OptimizedNoteSearchResults extends OptimizedNoteState {
  final List<SearchResult> results;
  final String query;
  final bool isSearching;

  const OptimizedNoteSearchResults({
    required this.results,
    required this.query,
    this.isSearching = false,
  });

  OptimizedNoteSearchResults copyWith({
    List<SearchResult>? results,
    String? query,
    bool? isSearching,
  }) {
    return OptimizedNoteSearchResults(
      results: results ?? this.results,
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [results, query, isSearching];
}

/// Emitted when a brand-new note has been persisted for the first time.
final class OptimizedNoteCreated extends OptimizedNoteState {
  final NoteMetadata metadata;

  const OptimizedNoteCreated({required this.metadata});

  @override
  List<Object?> get props => [metadata];
}

/// Error state with typed error information
final class OptimizedNoteError extends OptimizedNoteState {
  final String message;
  final String? folderId;
  final NoteErrorType errorType;

  const OptimizedNoteError(
    this.message, {
    this.folderId,
    this.errorType = NoteErrorType.unknown,
  });

  @override
  List<Object?> get props => [message, folderId, errorType];
}

/// Types of errors that can occur in note operations
enum NoteErrorType {
  notFound,
  loadFailed,
  saveFailed,
  deleteFailed,
  searchFailed,
  unknown,
}
