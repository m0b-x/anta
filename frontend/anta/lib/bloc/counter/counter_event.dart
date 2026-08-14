import 'package:equatable/equatable.dart';

import '../../models/counter.dart';

sealed class CounterEvent extends Equatable {
  const CounterEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCounters extends CounterEvent {
  final String? noteId;

  const LoadCounters({this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class AddCounter extends CounterEvent {
  final String name;
  final int startValue;
  final int step;
  final CounterScope scope;

  const AddCounter({
    required this.name,
    this.startValue = 1,
    this.step = 1,
    this.scope = CounterScope.global,
  });

  @override
  List<Object?> get props => [name, startValue, step, scope];
}

final class UpdateCounter extends CounterEvent {
  final Counter counter;

  const UpdateCounter({required this.counter});

  @override
  List<Object?> get props => [counter];
}

final class DeleteCounter extends CounterEvent {
  final String counterId;

  const DeleteCounter({required this.counterId});

  @override
  List<Object?> get props => [counterId];
}

final class ResetCounter extends CounterEvent {
  final String counterId;
  final String? noteId;

  const ResetCounter({required this.counterId, this.noteId});

  @override
  List<Object?> get props => [counterId, noteId];
}

final class IncrementCounter extends CounterEvent {
  final String counterId;
  final String? noteId;

  const IncrementCounter({required this.counterId, this.noteId});

  @override
  List<Object?> get props => [counterId, noteId];
}

final class DecrementCounter extends CounterEvent {
  final String counterId;
  final String? noteId;

  const DecrementCounter({required this.counterId, this.noteId});

  @override
  List<Object?> get props => [counterId, noteId];
}

final class SetCounterValue extends CounterEvent {
  final String counterId;
  final int value;
  final String? noteId;

  const SetCounterValue({
    required this.counterId,
    required this.value,
    this.noteId,
  });

  @override
  List<Object?> get props => [counterId, value, noteId];
}

final class RefreshCounters extends CounterEvent {
  final String? noteId;

  const RefreshCounters({this.noteId});

  @override
  List<Object?> get props => [noteId];
}

final class ReorderCounters extends CounterEvent {
  final int oldIndex;
  final int newIndex;

  const ReorderCounters({required this.oldIndex, required this.newIndex});

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

/// Loads the current value for a single counter/note pair into the bloc state
/// without affecting the main [counterValues] map. Used when a management-page
/// card picks a note locally so every mutation can route through the bloc.
final class LoadCounterForNote extends CounterEvent {
  final String counterId;
  final String noteId;

  const LoadCounterForNote({required this.counterId, required this.noteId});

  @override
  List<Object?> get props => [counterId, noteId];
}

final class PinCounter extends CounterEvent {
  final String counterId;

  const PinCounter({required this.counterId});

  @override
  List<Object?> get props => [counterId];
}

/// Centralized event to set (or clear) the note context for the counter BLoC.
///
/// When [noteId] is non-null, [CounterLoaded.counterValues] will be rebuilt
/// with per-note values for that note and [CounterLoaded.loadedNoteId] updated.
/// When [noteId] is null, the context is cleared back to global-only values.
/// Dispatch this when entering / leaving a note editor.
final class SetNoteContext extends CounterEvent {
  final String? noteId;

  const SetNoteContext({this.noteId});

  @override
  List<Object?> get props => [noteId];
}
