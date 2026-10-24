import 'package:equatable/equatable.dart';

sealed class CounterPerNoteEvent extends Equatable {
  const CounterPerNoteEvent();

  @override
  List<Object?> get props => [];
}

final class CounterPerNoteOpened extends CounterPerNoteEvent {
  final String counterId;

  const CounterPerNoteOpened({required this.counterId});

  @override
  List<Object?> get props => [counterId];
}

/// Re-reads the open counter's entries in place, without the loading state:
/// fed from `CounterService.changes` when a sync pull or a restore re-read
/// the counters beneath the page.
final class CounterPerNoteRefreshed extends CounterPerNoteEvent {
  const CounterPerNoteRefreshed();
}

final class CounterPerNoteAddNote extends CounterPerNoteEvent {
  final String noteId;

  const CounterPerNoteAddNote({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class CounterPerNoteRemoveNote extends CounterPerNoteEvent {
  final String noteId;

  const CounterPerNoteRemoveNote({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class CounterPerNoteIncrement extends CounterPerNoteEvent {
  final String noteId;

  const CounterPerNoteIncrement({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class CounterPerNoteDecrement extends CounterPerNoteEvent {
  final String noteId;

  const CounterPerNoteDecrement({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class CounterPerNoteSetValue extends CounterPerNoteEvent {
  final String noteId;
  final int value;

  const CounterPerNoteSetValue({required this.noteId, required this.value});

  @override
  List<Object?> get props => [noteId, value];
}

final class CounterPerNoteReset extends CounterPerNoteEvent {
  final String noteId;

  const CounterPerNoteReset({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class CounterPerNoteResetAll extends CounterPerNoteEvent {
  const CounterPerNoteResetAll();
}

final class CounterPerNoteTogglePin extends CounterPerNoteEvent {
  final String noteId;

  const CounterPerNoteTogglePin({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class CounterPerNoteReorder extends CounterPerNoteEvent {
  final int oldIndex;
  final int newIndex;

  const CounterPerNoteReorder({required this.oldIndex, required this.newIndex});

  @override
  List<Object?> get props => [oldIndex, newIndex];
}
