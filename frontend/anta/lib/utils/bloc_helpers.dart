// Helper utilities for BLoC state management with context-aware filtering.
//
// This module provides reusable, type-safe helpers to filter BLoC states
// based on context IDs (like folderId, parentId) to prevent cross-page
// state pollution in navigation stacks.

import '../bloc/optimized_folder/optimized_folder_state.dart';
import '../bloc/optimized_note/optimized_note_state.dart';
import '../models/note_metadata.dart';

/// Mixin for states that have a parent folder context.
/// Ensures states can be filtered by which folder they belong to.
mixin ParentFolderContext {
  String? get parentId;
}

/// Mixin for states that have a folder context.
/// Ensures states can be filtered by which folder they belong to.
mixin FolderContext {
  String? get folderId;
}

/// Extension methods for folder states to check context matching.
extension OptimizedFolderStateExtensions on OptimizedFolderState {
  /// Check if this state matches the given parent folder context.
  /// Returns true if the state should trigger a rebuild for a page
  /// displaying the given parentId.
  bool matchesParentContext(String? expectedParentId) {
    if (this is OptimizedFolderLoading) {
      return (this as OptimizedFolderLoading).parentId == expectedParentId;
    }
    if (this is OptimizedFolderLoaded) {
      return (this as OptimizedFolderLoaded).parentId == expectedParentId;
    }
    if (this is OptimizedFolderError) {
      return (this as OptimizedFolderError).parentId == expectedParentId;
    }
    // OptimizedFolderInitial has no context, always matches
    return this is OptimizedFolderInitial;
  }
}

/// Extension methods for note states to check context matching.
extension OptimizedNoteStateExtensions on OptimizedNoteState {
  /// Check if this state matches the given folder context.
  /// Returns true if the state should trigger a rebuild for a page
  /// displaying the given folderId.
  bool matchesFolderContext(String? expectedFolderId) {
    if (this is OptimizedNoteLoading) {
      return (this as OptimizedNoteLoading).folderId == expectedFolderId;
    }
    if (this is OptimizedNoteLoaded) {
      return (this as OptimizedNoteLoaded).folderId == expectedFolderId;
    }
    if (this is OptimizedNoteContentLoaded) {
      return (this as OptimizedNoteContentLoaded).folderId == expectedFolderId;
    }
    if (this is OptimizedNoteError) {
      return (this as OptimizedNoteError).folderId == expectedFolderId;
    }
    // OptimizedNoteInitial and OptimizedNoteSearchResults have no folder context
    return this is OptimizedNoteInitial || this is OptimizedNoteSearchResults;
  }

  /// Check if this state has any folder context information.
  bool get hasContext {
    return this is OptimizedNoteLoading ||
        this is OptimizedNoteLoaded ||
        this is OptimizedNoteContentLoaded ||
        this is OptimizedNoteError;
  }
}

/// Factory for creating folder-scoped buildWhen predicates.
class FolderBlocFilters {
  /// Creates a buildWhen predicate that only rebuilds when states match
  /// the given parentId context.
  ///
  /// Usage:
  /// ```dart
  /// BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
  ///   buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
  ///   builder: (context, state) { ... },
  /// )
  /// ```
  static bool Function(OptimizedFolderState, OptimizedFolderState)
  forParentFolder(String? parentId) {
    return (previous, current) {
      return current.matchesParentContext(parentId);
    };
  }
}

/// Factory for creating note-scoped buildWhen predicates.
class NoteBlocFilters {
  /// Creates a buildWhen predicate that only rebuilds when states match
  /// the given folderId context.
  ///
  /// Usage:
  /// ```dart
  /// BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
  ///   buildWhen: NoteBlocFilters.forFolder(widget.folderId),
  ///   builder: (context, state) { ... },
  /// )
  /// ```
  static bool Function(OptimizedNoteState, OptimizedNoteState) forFolder(
    String? folderId,
  ) {
    return (previous, current) {
      return current.matchesFolderContext(folderId);
    };
  }

  /// Creates a buildWhen predicate for the empty state section that
  /// filters both folder and note states.
  ///
  /// Only allows rebuilds for states matching the given folderId,
  /// or states without context (like Initial).
  static bool Function(OptimizedNoteState, OptimizedNoteState) forEmptyState(
    String? folderId,
  ) {
    return (previous, current) {
      // Allow initial and search states (no folder context)
      if (!current.hasContext) return true;

      // For states with context, must match the folder
      return current.matchesFolderContext(folderId);
    };
  }
}

/// Extension methods for filtering note collections by folder.
extension NoteMetadataListExtensions on Iterable<NoteMetadata> {
  /// Filters notes to only those belonging to the specified folder.
  ///
  /// Usage:
  /// ```dart
  /// final notes = state.paginatedNotes.notes.forFolder(widget.folderId);
  /// ```
  List<NoteMetadata> forFolder(String? folderId) {
    return where((note) => note.folderId == folderId).toList();
  }

  /// Filters notes to only those NOT belonging to the specified folder.
  List<NoteMetadata> excludingFolder(String? folderId) {
    return where((note) => note.folderId != folderId).toList();
  }
}

/// Helper for extracting notes from OptimizedNoteState with proper filtering.
class NoteStateHelper {
  /// Extracts filtered notes from a state, handling both Loaded and
  /// ContentLoaded states with proper fallback logic.
  ///
  /// Returns null if state doesn't contain note lists or if folderId is null.
  ///
  /// Usage:
  /// ```dart
  /// final notes = NoteStateHelper.getNotesForFolder(state, widget.folderId);
  /// if (notes != null && notes.isNotEmpty) { ... }
  /// ```
  static List<NoteMetadata>? getNotesForFolder(
    OptimizedNoteState state,
    String? folderId,
  ) {
    if (folderId == null) return null;

    if (state is OptimizedNoteLoaded) {
      return state.paginatedNotes.notes.forFolder(folderId);
    }

    if (state is OptimizedNoteContentLoaded &&
        state.previousPaginatedNotes != null) {
      return state.previousPaginatedNotes!.notes.forFolder(folderId);
    }

    return null;
  }

  /// Checks if a given state has more items to load for the specified folder.
  static bool hasMoreForFolder(OptimizedNoteState state, String? folderId) {
    if (folderId == null) return false;

    if (state is OptimizedNoteLoaded) {
      return state.paginatedNotes.hasMore;
    }

    if (state is OptimizedNoteContentLoaded &&
        state.previousPaginatedNotes != null) {
      return state.previousPaginatedNotes!.hasMore;
    }

    return false;
  }

  /// Checks if the state is currently loading more items.
  static bool isLoadingMore(OptimizedNoteState state) {
    return state is OptimizedNoteLoaded && state.isLoadingMore;
  }
}
