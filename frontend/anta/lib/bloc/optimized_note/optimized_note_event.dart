import 'dart:async';

import 'package:equatable/equatable.dart';
import '../../models/item_label.dart';
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

/// Writes one note's colour label. Separate from [UpdateOptimizedNote]
/// because a label is not a title or a body: it skips the duplicate-title
/// check and the search re-index, neither of which a colour can affect.
class SetOptimizedNoteLabel extends OptimizedNoteEvent {
  final String noteId;
  final ItemLabel label;

  const SetOptimizedNoteLabel({required this.noteId, required this.label});

  @override
  List<Object?> get props => [noteId, label];
}

/// Labels a whole selection as one unit: one statement, one reload — the
/// shape [DeleteOptimizedNotes] uses for the same reason.
class SetOptimizedNotesLabel extends OptimizedNoteEvent {
  final List<String> noteIds;
  final ItemLabel label;

  const SetOptimizedNotesLabel({required this.noteIds, required this.label});

  @override
  List<Object?> get props => [noteIds, label];
}

class DeleteOptimizedNote extends OptimizedNoteEvent {
  final String noteId;

  const DeleteOptimizedNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

/// Deletes a whole selection as one unit: one transaction, one reload. The
/// per-item event issued in a loop cost a full page reload per picked row.
class DeleteOptimizedNotes extends OptimizedNoteEvent {
  final List<String> noteIds;

  const DeleteOptimizedNotes(this.noteIds);

  @override
  List<Object?> get props => [noteIds];
}

/// Warms the content cache for rows the user is about to open. Carries no
/// state of its own — it exists so a page can ask through the bloc instead of
/// reaching past it into the repository.
class PreloadNoteContent extends OptimizedNoteEvent {
  final List<String> noteIds;

  const PreloadNoteContent(this.noteIds);

  @override
  List<Object?> get props => [noteIds];
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
