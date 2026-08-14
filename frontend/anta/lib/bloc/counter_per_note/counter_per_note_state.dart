import 'package:equatable/equatable.dart';

import '../../models/counter.dart';
import '../../models/note_metadata.dart';

class NoteValueEntry extends Equatable {
  final NoteMetadata note;
  final int value;
  final bool isPinned;

  const NoteValueEntry({
    required this.note,
    required this.value,
    this.isPinned = false,
  });

  NoteValueEntry copyWith({int? value, bool? isPinned}) {
    return NoteValueEntry(
      note: note,
      value: value ?? this.value,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  @override
  List<Object?> get props => [note, value, isPinned];
}

sealed class CounterPerNoteState extends Equatable {
  const CounterPerNoteState();

  @override
  List<Object?> get props => [];
}

final class CounterPerNoteInitial extends CounterPerNoteState {
  const CounterPerNoteInitial();
}

final class CounterPerNoteLoading extends CounterPerNoteState {
  const CounterPerNoteLoading();
}

final class CounterPerNoteLoaded extends CounterPerNoteState {
  final Counter counter;
  final List<NoteValueEntry> entries;

  /// Transient error from the last mutation.
  final String? lastError;

  const CounterPerNoteLoaded({
    required this.counter,
    required this.entries,
    this.lastError,
  });

  CounterPerNoteLoaded copyWith({
    Counter? counter,
    List<NoteValueEntry>? entries,
    String? lastError,
    bool clearError = false,
  }) {
    return CounterPerNoteLoaded(
      counter: counter ?? this.counter,
      entries: entries ?? this.entries,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [counter, entries, lastError];
}

final class CounterPerNoteError extends CounterPerNoteState {
  final String message;

  const CounterPerNoteError(this.message);

  @override
  List<Object?> get props => [message];
}
