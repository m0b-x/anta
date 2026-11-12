import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/share_overview.dart';
import '../../services/calendar_event_service.dart';
import '../../services/share_service.dart';
import 'share_event.dart';
import 'share_state.dart';

export 'share_event.dart';
export 'share_state.dart';

/// The Sharing page's bloc (`docs/cloud-share-surfaces-roadmap.md` §6.1):
/// it routes the page's intents to [ShareService] and holds the overview
/// the service reads. Every rule is the service's.
class ShareBloc extends Bloc<ShareEvent, ShareState> {
  final Future<ShareService> Function() _resolveService;
  final Stream<Object?> _calendarChanges;

  ShareService? _service;
  StreamSubscription<ShareAvailability>? _availabilitySubscription;
  StreamSubscription<Object?>? _calendarSubscription;

  /// The ends of sync runs, followed from the Sharing page's open on: a
  /// share leaves, or the partner's rows arrive, in a run of its own.
  StreamSubscription<void>? _runsSubscription;

  /// Loads started, so one that lands after a newer one is dropped.
  int _loads = 0;

  /// The last act's outcome, which every later load carries: a reload that
  /// overtook the act's own must not drop its snackbar.
  ShareOutcome? _outcome;
  int _outcomes = 0;

  ShareBloc({
    Future<ShareService> Function()? service,
    Stream<Object?>? calendarChanges,
  }) : _resolveService = service ?? ShareService.getInstance,
       _calendarChanges =
           calendarChanges ?? CalendarEventService.externalChanges,
       super(const ShareInitial()) {
    on<ShareOpened>(_onOpened);
    on<ShareLoadRequested>((_, emit) => _reload(emit));
    on<ShareSourcesChanged>((_, emit) => _reload(emit));
    on<ShareActEvent>(
      (event, emit) => switch (event) {
        ShareCategoriesSet(:final ids) => _act(
          emit,
          ShareAct.categoriesSet,
          (service) => service.setCategoriesShared(ids),
        ),
        ShareEventUnshared(:final eventId) => _act(
          emit,
          ShareAct.eventUnshared,
          (service) => service.setEventShared(eventId, false),
        ),
        ShareUndoRequested(:final change) => _act(
          emit,
          ShareAct.undo,
          (service) => service.undo(change),
        ),
        ShareStopAllRequested() => _onStopAll(emit),
      },
      transformer: _oneAtATime,
    );
  }

  /// Runs one act to its end before the next starts, in the order they
  /// were added (`CalendarBloc._oneAtATime`).
  static Stream<E> _oneAtATime<E>(
    Stream<E> events,
    Stream<E> Function(E) mapper,
  ) => events.asyncExpand(mapper);

  Future<void> _onOpened(ShareOpened event, Emitter<ShareState> emit) async {
    _calendarSubscription ??= _calendarChanges.listen(
      (_) => add(const ShareSourcesChanged()),
    );
    await _reload(emit);
    final ShareService service;
    try {
      service = await _resolve();
    } catch (e, st) {
      debugPrint('[ShareBloc] shared read not asked for: $e\n$st');
      return;
    }
    // Closed while the service resolved: nothing to show a read to.
    if (isClosed) return;
    if (_runsSubscription == null) _followRuns(service);
    try {
      await service.refreshShared();
    } catch (e, st) {
      debugPrint('[ShareBloc] shared read not asked for: $e\n$st');
    }
    // The read has ended, or was not needed: "Updated" and "Could not
    // check" say what it found.
    if (!isClosed) await _reload(emit);
  }

  Future<void> _onStopAll(Emitter<ShareState> emit) async {
    final sequence = ++_outcomes;
    try {
      final cleared = await (await _resolve()).stopAll();
      _outcome = ShareOutcome(
        sequence: sequence,
        act: ShareAct.stopAll,
        cleared: cleared,
      );
    } catch (e, st) {
      debugPrint('[ShareBloc] stop all failed: $e\n$st');
      _outcome = ShareOutcome(
        sequence: sequence,
        act: ShareAct.stopAll,
        failure: ShareFailure.failed,
      );
    }
    await _reload(emit);
  }

  Future<void> _act(
    Emitter<ShareState> emit,
    ShareAct act,
    Future<ShareChange> Function(ShareService service) write,
  ) async {
    final sequence = ++_outcomes;
    try {
      final change = await write(await _resolve());
      _outcome = ShareOutcome(sequence: sequence, act: act, change: change);
    } on ShareRefused {
      _outcome = ShareOutcome(
        sequence: sequence,
        act: act,
        failure: ShareFailure.refused,
      );
    } catch (e, st) {
      debugPrint('[ShareBloc] ${act.name} failed: $e\n$st');
      _outcome = ShareOutcome(
        sequence: sequence,
        act: act,
        failure: ShareFailure.failed,
      );
    }
    await _reload(emit);
  }

  Future<void> _reload(Emitter<ShareState> emit) async {
    final load = ++_loads;
    final ShareService service;
    try {
      service = await _resolve();
    } catch (e, st) {
      debugPrint('[ShareBloc] sharing not opened: $e\n$st');
      if (load == _loads && state is! ShareLoaded) {
        emit(const ShareLoadFailed());
      }
      return;
    }
    ShareOverview overview;
    try {
      overview = await service.overview();
    } catch (e, st) {
      // The page keeps what it showed; the next change reads again. With
      // nothing shown yet, "None" would be a claim the read never made.
      debugPrint('[ShareBloc] overview not read: $e\n$st');
      final current = state;
      if (current is ShareLoaded) {
        overview = current.overview;
      } else {
        if (load == _loads) emit(const ShareLoadFailed());
        return;
      }
    }
    if (load != _loads) return;
    emit(
      ShareLoaded(
        availability: service.availability,
        overview: overview,
        outcome: _outcome,
      ),
    );
  }

  /// Re-resolved every time, as `PairingBloc` does: a database switch
  /// replaces the service, and a held one would read a closed database.
  /// A bloc closed while the service resolved subscribes to nothing: what
  /// it heard would be added to a closed bloc.
  Future<ShareService> _resolve() async {
    final service = await _resolveService();
    if (isClosed || identical(service, _service)) return service;
    _service = service;
    unawaited(_availabilitySubscription?.cancel());
    // The replayed first value is the one the caller is about to read.
    _availabilitySubscription = service.changes
        .skip(1)
        .listen((_) => add(const ShareSourcesChanged()));
    if (_runsSubscription != null) _followRuns(service);
    return service;
  }

  void _followRuns(ShareService service) {
    unawaited(_runsSubscription?.cancel());
    _runsSubscription = service.runsEnded.listen(
      (_) => add(const ShareSourcesChanged()),
    );
  }

  @override
  Future<void> close() {
    _availabilitySubscription?.cancel();
    _calendarSubscription?.cancel();
    _runsSubscription?.cancel();
    return super.close();
  }
}
