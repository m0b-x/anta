import 'dart:async';

import 'package:equatable/equatable.dart';
import '../../services/note_storage_service.dart';

abstract class OptimizedNoteEvent extends Equatable {
  const OptimizedNoteEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotesPaginated extends OptimizedNoteEvent {
  final String? folderId;
  final int page;
  final int pageSize;
  final NotesSortOrder sortOrder;

  const LoadNotesPaginated({
    this.folderId,
    this.page = 1,
    this.pageSize = 20,
    this.sortOrder = NotesSortOrder.updatedDesc,
  });

  @override
  List<Object?> get props => [folderId, page, pageSize, sortOrder];
}

class LoadMoreNotes extends OptimizedNoteEvent {
  final String? folderId;

  const LoadMoreNotes({this.folderId});

  @override
  List<Object?> get props => [folderId];
}

class LoadNoteContent extends OptimizedNoteEvent {
  final String noteId;

  const LoadNoteContent(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class CreateOptimizedNote extends OptimizedNoteEvent {
  final String folderId;
  final String title;
  final String content;

  const CreateOptimizedNote({
    required this.folderId,
    required this.title,
    required this.content,
  });

  @override
  List<Object?> get props => [folderId, title, content];
}

class UpdateOptimizedNote extends OptimizedNoteEvent {
  final String noteId;
  final String? title;
  final String? content;
  final Completer<void>? completer;

  // ignore: prefer_const_constructors_in_immutables
  UpdateOptimizedNote({
    required this.noteId,
    this.title,
    this.content,
    this.completer,
  });

  @override
  List<Object?> get props => [noteId, title, content];
}

class DeleteOptimizedNote extends OptimizedNoteEvent {
  final String noteId;

  const DeleteOptimizedNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class SearchNotes extends OptimizedNoteEvent {
  final String query;
  final String? folderId;

  const SearchNotes({required this.query, this.folderId});

  @override
  List<Object?> get props => [query, folderId];
}

class QuickSearchNotes extends OptimizedNoteEvent {
  final String query;
  final String? folderId;

  const QuickSearchNotes({required this.query, this.folderId});

  @override
  List<Object?> get props => [query, folderId];
}

class ClearSearch extends OptimizedNoteEvent {
  const ClearSearch();
}

class RefreshNotes extends OptimizedNoteEvent {
  final String? folderId;

  const RefreshNotes({this.folderId});

  @override
  List<Object?> get props => [folderId];
}

class ReorderNotes extends OptimizedNoteEvent {
  final String folderId;
  final List<String> orderedIds;

  const ReorderNotes({required this.folderId, required this.orderedIds});

  @override
  List<Object?> get props => [folderId, orderedIds];
}
