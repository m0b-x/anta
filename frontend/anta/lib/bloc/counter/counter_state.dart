import 'package:equatable/equatable.dart';

import '../../models/counter.dart';

sealed class CounterState extends Equatable {
  const CounterState();

  @override
  List<Object?> get props => [];
}

final class CounterInitial extends CounterState {
  const CounterInitial();
}

final class CounterLoading extends CounterState {
  const CounterLoading();
}

final class CounterLoaded extends CounterState {
  final List<Counter> counters;
  final Map<String, int> counterValues;

  /// The noteId context that was used when [counterValues] was last loaded.
  /// Stored explicitly so bloc handlers never rely on hidden mutable state.
  final String? loadedNoteId;

  /// Values for counters whose note was picked locally on a management-page
  /// card. Kept separate from [counterValues] so a single card's local pick
  /// never pollutes the shared view for all other cards.
  final Map<({String counterId, String noteId}), int> pickedNoteValues;

  /// Transient error from the last mutation. Cleared on the next successful
  /// operation. UI can listen for non-null values to show a snackbar.
  final String? lastError;

  const CounterLoaded({
    this.counters = const [],
    this.counterValues = const {},
    this.loadedNoteId,
    this.pickedNoteValues = const {},
    this.lastError,
  });

  CounterLoaded copyWith({
    List<Counter>? counters,
    Map<String, int>? counterValues,
    String? loadedNoteId,
    bool clearLoadedNoteId = false,
    Map<({String counterId, String noteId}), int>? pickedNoteValues,
    String? lastError,
    bool clearError = false,
  }) {
    return CounterLoaded(
      counters: counters ?? this.counters,
      counterValues: counterValues ?? this.counterValues,
      loadedNoteId: clearLoadedNoteId
          ? null
          : (loadedNoteId ?? this.loadedNoteId),
      pickedNoteValues: pickedNoteValues ?? this.pickedNoteValues,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [
    counters,
    counterValues,
    loadedNoteId,
    pickedNoteValues,
    lastError,
  ];
}

final class CounterError extends CounterState {
  final String message;

  const CounterError(this.message);

  @override
  List<Object?> get props => [message];
}
