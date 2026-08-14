import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/note_metadata.dart';
import '../../repositories/note_repository.dart';
import '../../services/counter_service.dart';
import 'counter_per_note_event.dart';
import 'counter_per_note_state.dart';

class CounterPerNoteBloc
    extends Bloc<CounterPerNoteEvent, CounterPerNoteState> {
  final CounterService _counterService;
  final NoteRepository _noteRepository;

  String _counterId = '';

  CounterPerNoteBloc({
    required CounterService counterService,
    required NoteRepository noteRepository,
  }) : _counterService = counterService,
       _noteRepository = noteRepository,
       super(const CounterPerNoteInitial()) {
    on<CounterPerNoteOpened>(_onOpened);
    on<CounterPerNoteAddNote>(_onAddNote);
    on<CounterPerNoteRemoveNote>(_onRemoveNote);
    on<CounterPerNoteIncrement>(_onIncrement);
    on<CounterPerNoteDecrement>(_onDecrement);
    on<CounterPerNoteSetValue>(_onSetValue);
    on<CounterPerNoteReset>(_onReset);
    on<CounterPerNoteResetAll>(_onResetAll);
    on<CounterPerNoteTogglePin>(_onTogglePin);
    on<CounterPerNoteReorder>(_onReorder);
  }

  Future<void> _onOpened(
    CounterPerNoteOpened event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    _counterId = event.counterId;
    emit(const CounterPerNoteLoading());
    await _counterService.flush();
    await _loadEntries(emit);
  }

  Future<void> _onAddNote(
    CounterPerNoteAddNote event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;

    if (current.entries.any((e) => e.note.id == event.noteId)) return;

    final counter = current.counter;
    try {
      await _counterService.setValueForNote(
        _counterId,
        counter.startValue,
        noteId: event.noteId,
      );
      await _counterService.flush();
      await _loadEntries(emit);
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] AddNote error: $e');
    }
  }

  Future<void> _onRemoveNote(
    CounterPerNoteRemoveNote event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      await _counterService.flush();
      await _counterService.deleteNoteValue(_counterId, event.noteId);
      final entries = current.entries
          .where((e) => e.note.id != event.noteId)
          .toList();
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] RemoveNote error: $e');
    }
  }

  Future<void> _onIncrement(
    CounterPerNoteIncrement event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      final newValue = await _counterService.increment(
        _counterId,
        noteId: event.noteId,
      );
      final entries = current.entries.map((e) {
        if (e.note.id == event.noteId) return e.copyWith(value: newValue);
        return e;
      }).toList();
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] Increment error: $e');
    }
  }

  Future<void> _onDecrement(
    CounterPerNoteDecrement event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      final newValue = await _counterService.decrementForNote(
        _counterId,
        event.noteId,
      );
      final entries = current.entries.map((e) {
        if (e.note.id == event.noteId) return e.copyWith(value: newValue);
        return e;
      }).toList();
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] Decrement error: $e');
    }
  }

  Future<void> _onSetValue(
    CounterPerNoteSetValue event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      await _counterService.setValueForNote(
        _counterId,
        event.value,
        noteId: event.noteId,
      );
      final entries = current.entries.map((e) {
        if (e.note.id == event.noteId) return e.copyWith(value: event.value);
        return e;
      }).toList();
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] SetValue error: $e');
    }
  }

  Future<void> _onReset(
    CounterPerNoteReset event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      await _counterService.resetForNote(_counterId, event.noteId);
      final startValue = current.counter.startValue;
      final entries = current.entries.map((e) {
        if (e.note.id == event.noteId) return e.copyWith(value: startValue);
        return e;
      }).toList();
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] Reset error: $e');
    }
  }

  Future<void> _onResetAll(
    CounterPerNoteResetAll event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      final startValue = current.counter.startValue;
      await Future.wait(
        current.entries.map(
          (entry) => _counterService.resetForNote(_counterId, entry.note.id),
        ),
      );
      final entries = current.entries
          .map((e) => e.copyWith(value: startValue))
          .toList();
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] ResetAll error: $e');
    }
  }

  Future<void> _onTogglePin(
    CounterPerNoteTogglePin event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      final idx = current.entries.indexWhere((e) => e.note.id == event.noteId);
      if (idx < 0) return;
      final entry = current.entries[idx];
      final newPinned = !entry.isPinned;
      await _counterService.toggleNoteValuePin(
        _counterId,
        event.noteId,
        newPinned,
      );
      final entries = List<NoteValueEntry>.from(current.entries);
      entries[idx] = entry.copyWith(isPinned: newPinned);
      entries.sort(_entrySortComparator);
      final positions = <String, int>{};
      for (var i = 0; i < entries.length; i++) {
        positions[entries[i].note.id] = i;
      }
      await _counterService.reorderNoteValues(_counterId, positions);
      emit(current.copyWith(entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] TogglePin error: $e');
    }
  }

  Future<void> _onReorder(
    CounterPerNoteReorder event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = state;
    if (current is! CounterPerNoteLoaded) return;
    try {
      final entries = List<NoteValueEntry>.from(current.entries);
      final item = entries.removeAt(event.oldIndex);
      entries.insert(event.newIndex, item);
      emit(current.copyWith(entries: entries));
      final positions = <String, int>{};
      for (var i = 0; i < entries.length; i++) {
        positions[entries[i].note.id] = i;
      }
      await _counterService.reorderNoteValues(_counterId, positions);
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] Reorder error: $e');
    }
  }

  Future<void> _loadEntries(Emitter<CounterPerNoteState> emit) async {
    final counter = _counterService.getCounterById(_counterId);
    if (counter == null) {
      emit(const CounterPerNoteError('Counter not found'));
      return;
    }

    try {
      final rows = await _counterService.getOrderedNoteValuesForCounter(
        _counterId,
      );

      if (rows.isEmpty) {
        emit(CounterPerNoteLoaded(counter: counter, entries: const []));
        return;
      }

      final noteIds = rows.map((r) => r.noteId).toList();
      final notes = await _noteRepository.getNotesByIds(noteIds);
      final noteMap = <String, NoteMetadata>{};
      for (final note in notes) {
        noteMap[note.id] = _noteRepository.noteToMetadata(note);
      }

      final entries = <NoteValueEntry>[];
      for (final row in rows) {
        final meta = noteMap[row.noteId];
        if (meta == null) continue;
        entries.add(
          NoteValueEntry(note: meta, value: row.value, isPinned: row.isPinned),
        );
      }

      emit(CounterPerNoteLoaded(counter: counter, entries: entries));
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] Load error: $e');
      emit(CounterPerNoteError(e.toString()));
    }
  }

  static int _entrySortComparator(NoteValueEntry a, NoteValueEntry b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return 0;
  }
}
