import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/counter.dart';
import '../../services/counter_service.dart';
import 'counter_event.dart';
import 'counter_state.dart';

export 'counter_event.dart';
export 'counter_state.dart';

class CounterBloc extends Bloc<CounterEvent, CounterState> {
  final CounterService _counterService;

  CounterBloc({required CounterService counterService})
    : _counterService = counterService,
      super(const CounterInitial()) {
    on<LoadCounters>(_onLoad);
    on<AddCounter>(_onAddCounter);
    on<UpdateCounter>(_onUpdateCounter);
    on<DeleteCounter>(_onDeleteCounter);
    on<ResetCounter>(_onResetCounter);
    on<IncrementCounter>(_onIncrementCounter);
    on<DecrementCounter>(_onDecrementCounter);
    on<SetCounterValue>(_onSetCounterValue);
    on<RefreshCounters>(_onRefreshCounters);
    on<ReorderCounters>(_onReorderCounters);
    on<LoadCounterForNote>(_onLoadCounterForNote);
    on<PinCounter>(_onPinCounter);
    on<SetNoteContext>(_onSetNoteContext);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Builds the main [CounterLoaded.counterValues] map for the given [noteId]
  /// context. For per-note counters the per-note stored value is used; for
  /// global counters the in-memory global value is used.
  Future<Map<String, int>> _buildCounterValues(String? noteId) async {
    final values = <String, int>{};
    final noteValues = noteId != null
        ? await _counterService.getNoteValues(noteId)
        : <String, int>{};
    for (final c in _counterService.counters) {
      if (noteId != null && c.scope == CounterScope.perNote) {
        values[c.id] = noteValues[c.id] ?? c.startValue;
      } else {
        values[c.id] = _counterService.getGlobalValue(c.id);
      }
    }
    return values;
  }

  /// Returns true when an event's [noteId] targets a locally-picked note on a
  /// management-page card, rather than the page-level loaded note context.
  /// In that case mutations must go into [CounterLoaded.pickedNoteValues]
  /// instead of [CounterLoaded.counterValues] so other cards are unaffected.
  bool _isLocallyPickedNote(
    String counterId,
    String? noteId,
    CounterLoaded state,
  ) {
    final counter = _counterService.getCounterById(counterId);
    return counter?.scope != CounterScope.global &&
        noteId != null &&
        noteId != state.loadedNoteId;
  }

  /// Emits an updated state routing [newValue] into either
  /// [CounterLoaded.pickedNoteValues] or [CounterLoaded.counterValues]
  /// depending on whether [noteId] is a locally-picked note.
  void _emitWithUpdatedValue(
    String counterId,
    int newValue,
    String? noteId,
    CounterLoaded current,
    Emitter<CounterState> emit,
  ) {
    if (_isLocallyPickedNote(counterId, noteId, current)) {
      final key = (counterId: counterId, noteId: noteId!);
      final picked = Map<({String counterId, String noteId}), int>.from(
        current.pickedNoteValues,
      );
      picked[key] = newValue;
      emit(current.copyWith(pickedNoteValues: picked));
    } else {
      final values = Map<String, int>.from(current.counterValues);
      values[counterId] = newValue;
      emit(current.copyWith(counterValues: values));
    }
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Future<void> _onLoad(LoadCounters event, Emitter<CounterState> emit) async {
    emit(const CounterLoading());
    try {
      emit(
        CounterLoaded(
          counters: _counterService.counters,
          counterValues: await _buildCounterValues(event.noteId),
          loadedNoteId: event.noteId,
        ),
      );
    } catch (e) {
      debugPrint('[CounterBloc] Load error: $e');
      emit(CounterError(e.toString()));
    }
  }

  Future<void> _onAddCounter(
    AddCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      await _counterService.addCounter(
        name: event.name,
        startValue: event.startValue,
        step: event.step,
        scope: event.scope,
      );
      emit(
        current.copyWith(
          counters: _counterService.counters,
          counterValues: await _buildCounterValues(current.loadedNoteId),
        ),
      );
    } catch (e) {
      debugPrint('[CounterBloc] Add counter error: $e');
    }
  }

  Future<void> _onUpdateCounter(
    UpdateCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      await _counterService.updateCounter(event.counter);
      emit(current.copyWith(counters: _counterService.counters));
    } catch (e) {
      debugPrint('[CounterBloc] Update counter error: $e');
    }
  }

  Future<void> _onDeleteCounter(
    DeleteCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      await _counterService.deleteCounter(event.counterId);
      final values = Map<String, int>.from(current.counterValues);
      values.remove(event.counterId);
      final picked = Map<({String counterId, String noteId}), int>.from(
        current.pickedNoteValues,
      )..removeWhere((k, _) => k.counterId == event.counterId);
      emit(
        current.copyWith(
          counters: _counterService.counters,
          counterValues: values,
          pickedNoteValues: picked,
        ),
      );
    } catch (e) {
      debugPrint('[CounterBloc] Delete counter error: $e');
    }
  }

  Future<void> _onResetCounter(
    ResetCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      if (event.noteId != null) {
        await _counterService.resetForNote(event.counterId, event.noteId!);
      } else {
        await _counterService.resetGlobal(event.counterId);
      }
      final counter = _counterService.getCounterById(event.counterId);
      if (counter != null) {
        _emitWithUpdatedValue(
          event.counterId,
          counter.startValue,
          event.noteId,
          current,
          emit,
        );
      }
    } catch (e) {
      debugPrint('[CounterBloc] Reset counter error: $e');
    }
  }

  Future<void> _onIncrementCounter(
    IncrementCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      final newValue = await _counterService.increment(
        event.counterId,
        noteId: event.noteId,
      );
      _emitWithUpdatedValue(
        event.counterId,
        newValue,
        event.noteId,
        current,
        emit,
      );
    } catch (e) {
      debugPrint('[CounterBloc] Increment counter error: $e');
    }
  }

  Future<void> _onDecrementCounter(
    DecrementCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      final noteId = event.noteId;
      final int newValue;
      if (noteId != null) {
        newValue = await _counterService.decrementForNote(
          event.counterId,
          noteId,
        );
      } else {
        newValue = await _counterService.decrementGlobal(event.counterId);
      }
      _emitWithUpdatedValue(event.counterId, newValue, noteId, current, emit);
    } catch (e) {
      debugPrint('[CounterBloc] Decrement counter error: $e');
    }
  }

  Future<void> _onSetCounterValue(
    SetCounterValue event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      await _counterService.setValueForNote(
        event.counterId,
        event.value,
        noteId: event.noteId,
      );
      _emitWithUpdatedValue(
        event.counterId,
        event.value,
        event.noteId,
        current,
        emit,
      );
    } catch (e) {
      debugPrint('[CounterBloc] Set counter value error: $e');
    }
  }

  Future<void> _onRefreshCounters(
    RefreshCounters event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    final noteId = event.noteId ?? current.loadedNoteId;
    emit(
      CounterLoaded(
        counters: _counterService.counters,
        counterValues: await _buildCounterValues(noteId),
        loadedNoteId: noteId,
        pickedNoteValues: current.pickedNoteValues,
      ),
    );
  }

  Future<void> _onReorderCounters(
    ReorderCounters event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      await _counterService.reorderCounters(event.oldIndex, event.newIndex);
      emit(current.copyWith(counters: _counterService.counters));
    } catch (e) {
      debugPrint('[CounterBloc] Reorder counters error: $e');
    }
  }

  Future<void> _onLoadCounterForNote(
    LoadCounterForNote event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      final value = await _counterService.getValueForNote(
        event.counterId,
        event.noteId,
      );
      final key = (counterId: event.counterId, noteId: event.noteId);
      final picked = Map<({String counterId, String noteId}), int>.from(
        current.pickedNoteValues,
      );
      picked[key] = value;
      emit(current.copyWith(pickedNoteValues: picked));
    } catch (e) {
      debugPrint('[CounterBloc] LoadCounterForNote error: $e');
    }
  }

  Future<void> _onPinCounter(
    PinCounter event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    try {
      await _counterService.toggleCounterPin(event.counterId);
      emit(current.copyWith(counters: _counterService.counters));
    } catch (e) {
      debugPrint('[CounterBloc] PinCounter error: $e');
    }
  }

  /// Sets (or clears) the active note context. Rebuilds [counterValues] so
  /// per-note counters reflect the target note (or fall back to global values
  /// when [event.noteId] is null). This is the single, centralized point for
  /// switching note context — all pages should dispatch this event instead of
  /// manually passing noteId to [RefreshCounters] or [LoadCounters].
  Future<void> _onSetNoteContext(
    SetNoteContext event,
    Emitter<CounterState> emit,
  ) async {
    final current = state;
    if (current is! CounterLoaded) return;
    emit(
      CounterLoaded(
        counters: _counterService.counters,
        counterValues: await _buildCounterValues(event.noteId),
        loadedNoteId: event.noteId,
        pickedNoteValues: current.pickedNoteValues,
      ),
    );
  }
}
