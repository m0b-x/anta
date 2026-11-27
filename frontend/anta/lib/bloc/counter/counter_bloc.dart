import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/counter.dart';
import '../../models/custom_markdown_shortcut.dart' show CounterOp;
import '../../services/counter_service.dart';
import 'counter_event.dart';
import 'counter_state.dart';

export 'counter_event.dart';
export 'counter_state.dart';

class CounterBloc extends Bloc<CounterEvent, CounterState> {
  CounterService _service;

  /// Whether the constructor was handed the live singleton — the DI case. A
  /// `DatabaseLifecycle` switch replaces that singleton while this bloc (the
  /// app-level one in `main.dart`, never closed) stays alive, so
  /// [_counterService] re-resolves it per event; a suite's `forTesting`
  /// service is not the singleton and is kept as it is (A1b review R22).
  final bool _followsSingleton;

  late final StreamSubscription<void> _serviceChanges;

  /// Follows [CounterService.changes]: counters a sync pull or a restore
  /// re-read beneath the service are refreshed into a loaded state at once.
  CounterBloc({required CounterService counterService})
    : _service = counterService,
      _followsSingleton = counterService == CounterService.instanceOrNull,
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
    // Below the registrations: a broadcast stream that already held an event
    // would otherwise reach `add` before `RefreshCounters` has a handler
    // (A1b review R30).
    _serviceChanges = counterService.changes.listen(
      (_) => add(const RefreshCounters()),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// The service a handler runs against — see [_followsSingleton].
  CounterService get _counterService {
    if (!_followsSingleton) return _service;
    return _service = CounterService.instanceOrNull ?? _service;
  }

  /// Builds the main [CounterLoaded.counterValues] map for the given [noteId]
  /// context. For per-note counters the per-note stored value is used; for
  /// global counters the in-memory global value is used.
  Future<Map<String, int>> _buildCounterValues(String? noteId) async {
    final notes = <String, Map<String, int>>{};
    if (noteId != null) {
      notes[noteId] = await _counterService.getNoteValues(noteId);
    }
    return _valuesOver(noteId, notes);
  }

  /// [_buildCounterValues] over note values already read: [notes] holds the
  /// service cache's own maps, which taps write into, so what this builds
  /// with no await before the emit is the service's value now.
  Map<String, int> _valuesOver(
    String? noteId,
    Map<String, Map<String, int>> notes,
  ) {
    final noteValues = noteId == null ? const <String, int>{} : notes[noteId]!;
    return {
      for (final c in _counterService.counters)
        c.id: noteId != null && c.scope == CounterScope.perNote
            ? noteValues[c.id] ?? c.startValue
            : _counterService.getGlobalValue(c.id),
    };
  }

  /// The notes whose values [latest]'s picked per-note counters show.
  Iterable<String> _pickedNotes(CounterLoaded latest) => [
    for (final key in latest.pickedNoteValues.keys)
      if (_counterService.getCounterById(key.counterId)?.scope ==
          CounterScope.perNote)
        key.noteId,
  ];

  /// The locally picked values read again, so a refresh after a sync pull
  /// does not keep showing a card's old count (S3c review F14); a pick whose
  /// counter is gone is dropped. [notes] as in [_valuesOver].
  Map<({String counterId, String noteId}), int> _pickedOver(
    Map<({String counterId, String noteId}), int> picked,
    Map<String, Map<String, int>> notes,
  ) => {
    for (final key in picked.keys)
      if (_counterService.getCounterById(key.counterId) case final counter?)
        key: counter.scope == CounterScope.global
            ? _counterService.getGlobalValue(key.counterId)
            : notes[key.noteId]![key.counterId] ?? counter.startValue,
  };

  /// Emits [build] over the state as it is once every note [notesOf] names
  /// there is in the service's cache. A pass that had to read a note reads
  /// the state again, and nothing is awaited between that last read and the
  /// emit: a tap or a note context that landed during a read is in what is
  /// shown, rather than overwritten by values built before it.
  ///
  /// The maps are taken from the cache in that last pass, never kept from a
  /// pass before it: a reload during the reads drops the cache, and a map
  /// held across it is one no later tap reaches.
  Future<void> _emitOverLatest(
    Emitter<CounterState> emit,
    Iterable<String?> Function(CounterLoaded latest) notesOf,
    CounterState Function(
      CounterLoaded latest,
      Map<String, Map<String, int>> notes,
    )
    build,
  ) async {
    while (true) {
      final latest = _loaded;
      if (latest == null) return;
      final notes = <String, Map<String, int>>{};
      final missing = <String>{};
      for (final id in notesOf(latest)) {
        if (id == null) continue;
        if (_counterService.cachedNoteValues(id) case final cached?) {
          notes[id] = cached;
        } else {
          missing.add(id);
        }
      }
      if (missing.isEmpty) {
        emit(build(latest, notes));
        return;
      }
      await Future.wait(missing.map(_counterService.getNoteValues));
    }
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

  /// The loaded state as it is now. A handler reads it after its await, never
  /// before: flutter_bloc runs handlers concurrently, and a state captured
  /// before the await would emit over what another handler showed meanwhile —
  /// a Reset or an edit finishing would put back the value a tap replaced.
  CounterLoaded? get _loaded => switch (state) {
    final CounterLoaded loaded => loaded,
    _ => null,
  };

  /// A mutation that failed: the error rides the state and [done], so no
  /// page reports it as done.
  void _fail(
    String what,
    Object error,
    Emitter<CounterState> emit, [
    Completer<Object?>? done,
  ]) {
    debugPrint('[CounterBloc] $what error: $error');
    final latest = _loaded;
    if (latest != null) emit(latest.copyWith(lastError: error.toString()));
    done?.completeError(error);
  }

  /// Emits an updated state routing [newValue] into either
  /// [CounterLoaded.pickedNoteValues] or [CounterLoaded.counterValues]
  /// depending on whether [noteId] is a locally-picked note.
  void _emitWithUpdatedValue(
    String counterId,
    int newValue,
    String? noteId,
    Emitter<CounterState> emit,
  ) {
    final current = _loaded;
    if (current == null) return;
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

  /// What a shortcut's `{cN}` token for [counterId] writes into the note on
  /// [noteId]: [op] applied, and the number the service holds after it, or
  /// null for a counter the loaded state does not know or a count that
  /// failed.
  ///
  /// The number is the service's own, never this state's plus a step: a
  /// shortcut naming one counter twice resolves its second token before the
  /// first token's event has emitted, and wrote the same number twice while
  /// the counter counted two. Each token waits for its own count, so the
  /// tokens read the service in order and the state shows the last of them
  /// by the time the note does.
  ///
  /// [unfiled] is the editor's own count of presses on per-note counters
  /// made while its note has no id: a new note is created once its first
  /// text lands, and a shortcut resolves its tokens before it inserts, so
  /// the first press in a new note always has none. Such a press is kept
  /// there, net of decrements, and counts nothing yet — a note that is never
  /// created counts nothing — and its number is the start plus a step per
  /// kept press, which is the note's value once [fileShortcutPresses] has
  /// counted them on it.
  Future<int?> shortcutValue(
    String counterId,
    CounterOp op, {
    String? noteId,
    Map<String, int>? unfiled,
  }) async {
    final loaded = _loaded;
    if (loaded == null || !loaded.counters.any((c) => c.id == counterId)) {
      return null;
    }
    final counter = _counterService.getCounterById(counterId);
    if (noteId == null &&
        unfiled != null &&
        counter != null &&
        counter.scope == CounterScope.perNote) {
      final kept =
          (unfiled[counterId] ?? 0) +
          switch (op) {
            CounterOp.increment => 1,
            CounterOp.decrement => -1,
            CounterOp.keep => 0,
          };
      unfiled[counterId] = kept;
      return counter.startValue + counter.step * kept;
    }
    final value = Completer<int?>();
    switch (op) {
      case CounterOp.increment:
        add(
          IncrementCounter(counterId: counterId, noteId: noteId, value: value),
        );
      case CounterOp.decrement:
        add(
          DecrementCounter(counterId: counterId, noteId: noteId, value: value),
        );
      case CounterOp.keep:
        try {
          return noteId == null
              ? _counterService.getGlobalValue(counterId)
              : await _counterService.getValueForNote(counterId, noteId);
        } catch (e) {
          debugPrint('[CounterBloc] Shortcut value error: $e');
          return null;
        }
    }
    try {
      return await value.future;
    } catch (_) {
      // [_fail] has logged it and carries it in the state.
      return null;
    }
  }

  /// Counts the presses [shortcutValue] kept in [unfiled] on [noteId], the
  /// id the note's create gave it, as the taps they were — and empties it.
  /// Called in the turn the editor adopts the id, so no press runs between
  /// the two: one made before is in [unfiled] and counted here, one made
  /// after adds its event behind these, and none is counted twice.
  void fileShortcutPresses(String noteId, Map<String, int> unfiled) {
    for (final MapEntry(key: counterId, value: kept) in unfiled.entries) {
      for (var i = 0; i < kept.abs(); i++) {
        add(
          kept > 0
              ? IncrementCounter(counterId: counterId, noteId: noteId)
              : DecrementCounter(counterId: counterId, noteId: noteId),
        );
      }
    }
    unfiled.clear();
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
    if (state is! CounterLoaded) return;
    try {
      await _counterService.addCounter(
        name: event.name,
        startValue: event.startValue,
        step: event.step,
        scope: event.scope,
      );
      await _emitOverLatest(
        emit,
        (latest) => [latest.loadedNoteId],
        (latest, notes) => latest.copyWith(
          counters: _counterService.counters,
          counterValues: _valuesOver(latest.loadedNoteId, notes),
        ),
      );
    } catch (e) {
      _fail('Add counter', e, emit);
    }
  }

  Future<void> _onUpdateCounter(
    UpdateCounter event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      await _counterService.updateCounter(event.counter);
      final latest = _loaded;
      if (latest == null) return;
      emit(latest.copyWith(counters: _counterService.counters));
    } catch (e) {
      _fail('Update counter', e, emit);
    }
  }

  Future<void> _onDeleteCounter(
    DeleteCounter event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) {
      event.done?.complete(false);
      return;
    }
    try {
      await _counterService.deleteCounter(event.counterId);
      final latest = _loaded;
      if (latest != null) {
        final values = Map<String, int>.from(latest.counterValues);
        values.remove(event.counterId);
        final picked = Map<({String counterId, String noteId}), int>.from(
          latest.pickedNoteValues,
        )..removeWhere((k, _) => k.counterId == event.counterId);
        emit(
          latest.copyWith(
            counters: _counterService.counters,
            counterValues: values,
            pickedNoteValues: picked,
          ),
        );
      }
      event.done?.complete(true);
    } catch (e) {
      _fail('Delete counter', e, emit, event.done);
    }
  }

  /// Shows the service's value rather than the start value: a tap made right
  /// after the Reset is already counted on top of it.
  Future<void> _onResetCounter(
    ResetCounter event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) {
      event.done?.complete(false);
      return;
    }
    try {
      final noteId = event.noteId;
      final int value;
      if (noteId != null) {
        await _counterService.resetForNote(event.counterId, noteId);
        value = await _counterService.getValueForNote(event.counterId, noteId);
      } else {
        await _counterService.resetGlobal(event.counterId);
        value = _counterService.getGlobalValue(event.counterId);
      }
      _emitWithUpdatedValue(event.counterId, value, noteId, emit);
      event.done?.complete(true);
    } catch (e) {
      _fail('Reset counter', e, emit, event.done);
    }
  }

  Future<void> _onIncrementCounter(
    IncrementCounter event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) {
      event.value?.complete(null);
      return;
    }
    try {
      final newValue = await _counterService.increment(
        event.counterId,
        noteId: event.noteId,
      );
      _emitWithUpdatedValue(event.counterId, newValue, event.noteId, emit);
      event.value?.complete(newValue);
    } catch (e) {
      _fail('Increment counter', e, emit, event.value);
    }
  }

  Future<void> _onDecrementCounter(
    DecrementCounter event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) {
      event.value?.complete(null);
      return;
    }
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
      _emitWithUpdatedValue(event.counterId, newValue, noteId, emit);
      event.value?.complete(newValue);
    } catch (e) {
      _fail('Decrement counter', e, emit, event.value);
    }
  }

  Future<void> _onSetCounterValue(
    SetCounterValue event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      await _counterService.setValueForNote(
        event.counterId,
        event.value,
        noteId: event.noteId,
      );
      _emitWithUpdatedValue(event.counterId, event.value, event.noteId, emit);
    } catch (e) {
      _fail('Set counter value', e, emit);
    }
  }

  Future<void> _onRefreshCounters(
    RefreshCounters event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      await _emitOverLatest(
        emit,
        (latest) => [
          event.noteId ?? latest.loadedNoteId,
          ..._pickedNotes(latest),
        ],
        (latest, notes) {
          final noteId = event.noteId ?? latest.loadedNoteId;
          return CounterLoaded(
            counters: _counterService.counters,
            counterValues: _valuesOver(noteId, notes),
            loadedNoteId: noteId,
            pickedNoteValues: _pickedOver(latest.pickedNoteValues, notes),
            // A refresh now arrives from a sync pull as well as from the
            // page, and must not clear a mutation error before it was read
            // (A1b review R29).
            lastError: latest.lastError,
          );
        },
      );
    } catch (e) {
      _fail('Refresh counters', e, emit);
    }
  }

  Future<void> _onReorderCounters(
    ReorderCounters event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      await _counterService.reorderCounters(event.oldIndex, event.newIndex);
      final latest = _loaded;
      if (latest == null) return;
      emit(latest.copyWith(counters: _counterService.counters));
    } catch (e) {
      _fail('Reorder counters', e, emit);
    }
  }

  Future<void> _onLoadCounterForNote(
    LoadCounterForNote event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      final value = await _counterService.getValueForNote(
        event.counterId,
        event.noteId,
      );
      final latest = _loaded;
      if (latest == null) return;
      final key = (counterId: event.counterId, noteId: event.noteId);
      final picked = Map<({String counterId, String noteId}), int>.from(
        latest.pickedNoteValues,
      );
      picked[key] = value;
      emit(latest.copyWith(pickedNoteValues: picked));
    } catch (e) {
      _fail('LoadCounterForNote', e, emit);
    }
  }

  Future<void> _onPinCounter(
    PinCounter event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      await _counterService.toggleCounterPin(event.counterId);
      final latest = _loaded;
      if (latest == null) return;
      emit(latest.copyWith(counters: _counterService.counters));
    } catch (e) {
      _fail('PinCounter', e, emit);
    }
  }

  /// Sets (or clears) the active note context. Rebuilds [counterValues] so
  /// per-note counters reflect the target note (or fall back to global values
  /// when [event.noteId] is null). This is the single, centralized point for
  /// switching note context — all pages should dispatch this event instead of
  /// manually passing noteId to [RefreshCounters] or [LoadCounters].
  ///
  /// A note whose values could not be read still becomes the context, with
  /// its per-note counters left out rather than the previous note's values
  /// standing in for them: the next refresh reads it again, and a tap on it
  /// shows the service's count.
  Future<void> _onSetNoteContext(
    SetNoteContext event,
    Emitter<CounterState> emit,
  ) async {
    if (state is! CounterLoaded) return;
    try {
      await _emitOverLatest(
        emit,
        (_) => [event.noteId],
        (latest, notes) => CounterLoaded(
          counters: _counterService.counters,
          counterValues: _valuesOver(event.noteId, notes),
          loadedNoteId: event.noteId,
          pickedNoteValues: latest.pickedNoteValues,
          // As a refresh's: a context switch is not the next successful write
          // the error waits for.
          lastError: latest.lastError,
        ),
      );
    } catch (e) {
      debugPrint('[CounterBloc] Set note context error: $e');
      final latest = _loaded;
      if (latest == null) return;
      emit(
        CounterLoaded(
          counters: _counterService.counters,
          counterValues: {
            for (final c in _counterService.counters)
              if (c.scope == CounterScope.global)
                c.id: _counterService.getGlobalValue(c.id),
          },
          loadedNoteId: event.noteId,
          pickedNoteValues: latest.pickedNoteValues,
          lastError: e.toString(),
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _serviceChanges.cancel();
    return super.close();
  }
}
