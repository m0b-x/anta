import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/note_metadata.dart';
import '../../repositories/note_repository.dart';
import '../../services/counter_service.dart';
import 'counter_per_note_event.dart';
import 'counter_per_note_state.dart';

class CounterPerNoteBloc
    extends Bloc<CounterPerNoteEvent, CounterPerNoteState> {
  CounterService _service;

  /// Whether the constructor was handed the live singleton — the DI case. A
  /// `DatabaseLifecycle` switch replaces that singleton beneath this bloc, so
  /// [_counterService] re-resolves it per event; a suite's `forTesting`
  /// service is not the singleton and is kept as it is (A1b review R22).
  final bool _followsSingleton;

  final NoteRepository _noteRepository;
  late final StreamSubscription<void> _serviceChanges;

  String _counterId = '';

  CounterPerNoteBloc({
    required CounterService counterService,
    required NoteRepository noteRepository,
  }) : _service = counterService,
       _followsSingleton = counterService == CounterService.instanceOrNull,
       _noteRepository = noteRepository,
       super(const CounterPerNoteInitial()) {
    on<CounterPerNoteOpened>(_onOpened);
    on<CounterPerNoteRefreshed>(_onRefreshed);
    on<CounterPerNoteAddNote>(_onAddNote);
    on<CounterPerNoteRemoveNote>(_onRemoveNote);
    on<CounterPerNoteIncrement>(_onIncrement);
    on<CounterPerNoteDecrement>(_onDecrement);
    on<CounterPerNoteSetValue>(_onSetValue);
    on<CounterPerNoteReset>(_onReset);
    on<CounterPerNoteResetAll>(_onResetAll);
    on<CounterPerNoteTogglePin>(_onTogglePin);
    on<CounterPerNoteReorder>(_onReorder);
    // Below the registrations: a broadcast stream that already held an event
    // would otherwise reach `add` before `CounterPerNoteRefreshed` has a
    // handler (A1b review R30).
    _serviceChanges = counterService.changes.listen(
      (_) => add(const CounterPerNoteRefreshed()),
    );
  }

  /// The service a handler runs against — see [_followsSingleton].
  CounterService get _counterService {
    if (!_followsSingleton) return _service;
    return _service = CounterService.instanceOrNull ?? _service;
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

  Future<void> _onRefreshed(
    CounterPerNoteRefreshed event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    if (state is! CounterPerNoteLoaded) return;
    // The entries are read from the table, and a reload keeps this page's
    // taps pending in the service; the flush writes them over the merged
    // values first.
    await _counterService.flush();
    // A refresh now arrives from a sync pull as well as from the page, and
    // must not clear a mutation error before it was read (A1b review R29).
    await _loadEntries(emit, keepError: true);
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
      _fail('AddNote', e, emit);
    }
  }

  /// The loaded state as it is now. A handler reads it after its await, never
  /// before: flutter_bloc runs handlers concurrently, and entries captured
  /// before the await would emit over a tap another handler showed meanwhile.
  CounterPerNoteLoaded? get _loaded => switch (state) {
    final CounterPerNoteLoaded loaded => loaded,
    _ => null,
  };

  /// Emits [change] applied to the entries as they are now — see [_loaded].
  void _emitEntries(
    Emitter<CounterPerNoteState> emit,
    List<NoteValueEntry> Function(List<NoteValueEntry> entries) change,
  ) {
    final latest = _loaded;
    if (latest == null) return;
    emit(latest.copyWith(entries: change(latest.entries)));
  }

  /// [entries] with [noteId]'s value set to [value].
  static List<NoteValueEntry> _withValue(
    List<NoteValueEntry> entries,
    String noteId,
    int value,
  ) => [
    for (final e in entries) e.note.id == noteId ? e.copyWith(value: value) : e,
  ];

  /// A mutation that failed: the error rides the state and [done], so no
  /// page reports it as done.
  void _fail(
    String what,
    Object error,
    Emitter<CounterPerNoteState> emit, [
    Completer<bool>? done,
  ]) {
    debugPrint('[CounterPerNoteBloc] $what error: $error');
    final latest = _loaded;
    if (latest != null) emit(latest.copyWith(lastError: error.toString()));
    done?.completeError(error);
  }

  Future<void> _onRemoveNote(
    CounterPerNoteRemoveNote event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    if (state is! CounterPerNoteLoaded) return;
    try {
      await _counterService.flush();
      await _counterService.deleteNoteValue(_counterId, event.noteId);
      _emitEntries(
        emit,
        (entries) => entries.where((e) => e.note.id != event.noteId).toList(),
      );
    } catch (e) {
      _fail('RemoveNote', e, emit);
    }
  }

  Future<void> _onIncrement(
    CounterPerNoteIncrement event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    if (state is! CounterPerNoteLoaded) return;
    try {
      final newValue = await _counterService.increment(
        _counterId,
        noteId: event.noteId,
      );
      _emitEntries(emit, (e) => _withValue(e, event.noteId, newValue));
    } catch (e) {
      _fail('Increment', e, emit);
    }
  }

  Future<void> _onDecrement(
    CounterPerNoteDecrement event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    if (state is! CounterPerNoteLoaded) return;
    try {
      final newValue = await _counterService.decrementForNote(
        _counterId,
        event.noteId,
      );
      _emitEntries(emit, (e) => _withValue(e, event.noteId, newValue));
    } catch (e) {
      _fail('Decrement', e, emit);
    }
  }

  Future<void> _onSetValue(
    CounterPerNoteSetValue event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    if (state is! CounterPerNoteLoaded) return;
    try {
      await _counterService.setValueForNote(
        _counterId,
        event.value,
        noteId: event.noteId,
      );
      _emitEntries(emit, (e) => _withValue(e, event.noteId, event.value));
    } catch (e) {
      _fail('SetValue', e, emit);
    }
  }

  /// Shows the service's value rather than the start value: a tap made right
  /// after the Reset is already counted on top of it.
  Future<void> _onReset(
    CounterPerNoteReset event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    if (state is! CounterPerNoteLoaded) {
      event.done?.complete(false);
      return;
    }
    try {
      await _counterService.resetForNote(_counterId, event.noteId);
      final value = await _counterService.getValueForNote(
        _counterId,
        event.noteId,
      );
      _emitEntries(emit, (e) => _withValue(e, event.noteId, value));
      event.done?.complete(true);
    } catch (e) {
      _fail('Reset', e, emit, event.done);
    }
  }

  Future<void> _onResetAll(
    CounterPerNoteResetAll event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = _loaded;
    if (current == null) {
      event.done?.complete(false);
      return;
    }
    try {
      final noteIds = [for (final entry in current.entries) entry.note.id];
      await Future.wait(
        noteIds.map((id) => _counterService.resetForNote(_counterId, id)),
      );
      final values = {
        for (final id in noteIds)
          id: await _counterService.getValueForNote(_counterId, id),
      };
      _emitEntries(emit, (entries) {
        var reset = entries;
        for (final MapEntry(key: id, :value) in values.entries) {
          reset = _withValue(reset, id, value);
        }
        return reset;
      });
      event.done?.complete(true);
    } catch (e) {
      _fail('ResetAll', e, emit, event.done);
    }
  }

  Future<void> _onTogglePin(
    CounterPerNoteTogglePin event,
    Emitter<CounterPerNoteState> emit,
  ) async {
    final current = _loaded;
    if (current == null) return;
    try {
      final idx = current.entries.indexWhere((e) => e.note.id == event.noteId);
      if (idx < 0) return;
      final newPinned = !current.entries[idx].isPinned;
      await _counterService.toggleNoteValuePin(
        _counterId,
        event.noteId,
        newPinned,
      );
      // A partition, not `sort`: `List.sort` is unstable past 32 elements,
      // and every position below is a synced row.
      List<NoteValueEntry> pinned(List<NoteValueEntry> entries) {
        final marked = [
          for (final e in entries)
            e.note.id == event.noteId ? e.copyWith(isPinned: newPinned) : e,
        ];
        return [
          ...marked.where((e) => e.isPinned),
          ...marked.where((e) => !e.isPinned),
        ];
      }

      final entries = pinned((_loaded ?? current).entries);
      final positions = <String, int>{};
      for (var i = 0; i < entries.length; i++) {
        positions[entries[i].note.id] = i;
      }
      await _counterService.reorderNoteValues(_counterId, positions);
      _emitEntries(emit, pinned);
    } catch (e) {
      _fail('TogglePin', e, emit);
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
      _fail('Reorder', e, emit);
    }
  }

  /// The rows give the notes, their order, their pins and the service's
  /// value as the rows were read; a note a tap reached since is in the
  /// service's cache, read with no await before the emit — the rows alone
  /// would drop a tap made during the note reads. No map is kept across an
  /// await, so a reload in between detaches nothing this emits from.
  /// [keepError] carries a mutation error not read yet over.
  Future<void> _loadEntries(
    Emitter<CounterPerNoteState> emit, {
    bool keepError = false,
  }) async {
    final counter = _counterService.getCounterById(_counterId);
    if (counter == null) {
      emit(const CounterPerNoteError(CounterPerNoteFailure.counterNotFound));
      return;
    }

    try {
      final rows = await _counterService.getOrderedNoteValuesForCounter(
        _counterId,
      );

      if (rows.isEmpty) {
        emit(
          CounterPerNoteLoaded(
            counter: counter,
            entries: const [],
            lastError: keepError ? _loaded?.lastError : null,
          ),
        );
        return;
      }

      final noteIds = rows.map((r) => r.noteId).toList();
      final notes = await _noteRepository.getNotesByIds(noteIds);
      // Flagged, as every door into the editor is: a row here opens it.
      final shares = await _noteRepository.shareCensus.read();
      final noteMap = <String, NoteMetadata>{};
      for (final note in notes) {
        noteMap[note.id] = _noteRepository.noteToMetadata(note, shares);
      }

      final entries = <NoteValueEntry>[];
      for (final row in rows) {
        final meta = noteMap[row.noteId];
        if (meta == null) continue;
        entries.add(
          NoteValueEntry(
            note: meta,
            value:
                _counterService.cachedNoteValues(row.noteId)?[_counterId] ??
                row.value,
            isPinned: row.isPinned,
          ),
        );
      }

      emit(
        CounterPerNoteLoaded(
          counter: counter,
          entries: entries,
          lastError: keepError ? _loaded?.lastError : null,
        ),
      );
    } catch (e) {
      debugPrint('[CounterPerNoteBloc] Load error: $e');
      emit(const CounterPerNoteError(CounterPerNoteFailure.loadFailed));
    }
  }

  @override
  Future<void> close() async {
    await _serviceChanges.cancel();
    return super.close();
  }
}
