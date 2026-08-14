import 'package:equatable/equatable.dart';

import '../../models/note_metadata.dart';

sealed class NotePickerState extends Equatable {
  const NotePickerState();

  @override
  List<Object?> get props => [];
}

final class NotePickerInitial extends NotePickerState {
  const NotePickerInitial();
}

final class NotePickerLoading extends NotePickerState {
  final String query;
  final int page;

  const NotePickerLoading({this.query = '', this.page = 1});

  @override
  List<Object?> get props => [query, page];
}

final class NotePickerLoaded extends NotePickerState {
  final PaginatedNotes paginatedNotes;
  final String query;

  const NotePickerLoaded({required this.paginatedNotes, this.query = ''});

  @override
  List<Object?> get props => [paginatedNotes, query];
}

final class NotePickerError extends NotePickerState {
  final String message;

  const NotePickerError(this.message);

  @override
  List<Object?> get props => [message];
}
