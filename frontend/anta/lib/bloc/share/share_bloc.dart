import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/share_overview.dart';
import '../one_at_a_time.dart';
import '../../models/share_settings.dart';
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

  /// Sent [ShareOpened]: this bloc serves the Sharing page, and every load
  /// from then on reads the tick sheet's counts, which a summary never
  /// shows.
  bool _opened = false;

  ShareBloc({
    Future<ShareService> Function()? service,
    Stream<Object?>? calendarChanges,
  }) : _resolveService = service ?? ShareService.getInstance,
       _calendarChanges =
           calendarChanges ?? CalendarEventService.externalChanges,
       super(const ShareInitial()) {
    on<ShareOpened>(_onOpened);
    on<ShareLoadRequested>((_, emit) {
      _followCalendar();
      return _reload(emit);
    });
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
        ShareFolderShared(:final folderId) => _act(
          emit,
          ShareAct.folderShared,
          (service) => service.setFolderShared(folderId, true),
        ),
        ShareFolderUnshared(:final folderId) => _act(
          emit,
          ShareAct.folderUnshared,
          (service) => service.setFolderShared(folderId, false),
        ),
        // One the close handed over is written there, never twice.
        ShareUndoRequested(:final change) =>
          _queuedUndos.remove(event)
              ? _act(emit, ShareAct.undo, (service) => service.undo(change))
              : Future<void>.value(),
        ShareStopAllRequested() => _onStopAll(emit),
      },
      transformer: oneAtATime,
    );
    on<ShareCategoryShownSet>(
      (event, emit) => _set(
        emit,
        'category shown',
        // A hide that takes my alerts off is said by the service's notice,
        // which needs neither this bloc nor its sheet alive when it lands.
        (service) => service.setCategoryShown(event.categoryId, event.shown),
        shows: (state) => state.copyWith(
          overview: state.overview.withPartnerShown(
            event.categoryId,
            event.shown,
          ),
        ),
      ),
    );
    on<ShareEventLookSet>(
      (event, emit) => _set(
        emit,
        'look',
        (service) => service.setEventLook(event.look),
        shows: (state) =>
            state.copyWith(look: state.look.copyWith(eventLook: event.look)),
      ),
    );
    on<ShareNoteLookSet>(
      (event, emit) => _set(
        emit,
        'note look',
        (service) => service.setNoteLook(event.look),
        shows: (state) =>
            state.copyWith(look: state.look.copyWith(noteLook: event.look)),
      ),
    );
    on<ShareMarkMineSet>(
      (event, emit) => _set(
        emit,
        'mark mine',
        (service) => service.setMarkMine(event.markMine),
        shows: (state) =>
            state.copyWith(look: state.look.copyWith(markMine: event.markMine)),
      ),
    );
    on<ShareAlertsSet>(
      (event, emit) => _set(
        emit,
        'alerts',
        (service) => service.setAlerts(event.alerts),
        shows: (state) => state.copyWith(alerts: event.alerts),
      ),
    );
    on<ShareArmedCountRequested>(_onArmedCount);
    on<SharePartnerEventHeldRequested>(_onEventHeld);
  }

  Future<void> _onEventHeld(
    SharePartnerEventHeldRequested event,
    Emitter<ShareState> emit,
  ) async {
    var held = true;
    try {
      held = await (await _resolve()).isFromPartner(
        'calendar_events',
        event.eventId,
      );
    } catch (e, st) {
      debugPrint('[ShareBloc] partner event not looked up: $e\n$st');
    }
    if (!event.answer.isCompleted) event.answer.complete(held);
  }

  Future<void> _onArmedCount(
    ShareArmedCountRequested event,
    Emitter<ShareState> emit,
  ) async {
    var armed = 0;
    try {
      armed = await (await _resolve()).armedOnPartner();
    } catch (e, st) {
      debugPrint('[ShareBloc] armed alerts not counted: $e\n$st');
    }
    if (!event.answer.isCompleted) event.answer.complete(armed);
  }

  /// What the settings writes in flight will have stored, oldest first,
  /// laid over every state emitted until each has landed. A switch shows
  /// its new value from the tap — hiding a category reloads the calendar's
  /// events before the write answers — and the read that follows an earlier
  /// write cannot draw a later, still unwritten one back for a frame.
  final List<ShareLoaded Function(ShareLoaded state)> _pending = [];

  /// What the last reads that answered returned — never the state on screen,
  /// which carries [_pending]: a read that fails after a write that failed
  /// falls back to these, so a value never stored is not drawn as if it
  /// were once its write has given up.
  ShareOverview? _readOverview;
  ShareLook _readLook = const ShareLook();
  ShareAlerts _readAlerts = ShareAlerts.own;

  /// A receiver's setting: shown at once ([shows]), written, then the state
  /// read back from what is stored — so a write that failed shows the value
  /// that stands. No outcome: nothing here has a snackbar or an undo.
  Future<void> _set(
    Emitter<ShareState> emit,
    String what,
    Future<void> Function(ShareService service) write, {
    required ShareLoaded Function(ShareLoaded state) shows,
  }) async {
    _pending.add(shows);
    final shown = state;
    if (shown is ShareLoaded) emit(shows(shown));
    try {
      await write(await _resolve());
    } catch (e, st) {
      debugPrint('[ShareBloc] $what not written: $e\n$st');
    } finally {
      _pending.remove(shows);
    }
    await _reload(emit);
  }

  /// Marks set or cleared while a surface stays open — an act elsewhere, the
  /// reader clearing them — reach it through the calendar's changes, the
  /// summary's as much as the page's. Once, and never by a closed bloc: an
  /// event opened or loaded and the bloc closed in one turn still runs its
  /// handler, and what a late subscription heard would be added to a
  /// closed bloc.
  void _followCalendar() {
    if (isClosed) return;
    _calendarSubscription ??= _calendarChanges.listen(
      (_) => add(const ShareSourcesChanged()),
    );
  }

  Future<void> _onOpened(ShareOpened event, Emitter<ShareState> emit) async {
    _opened = true;
    _followCalendar();
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
    _carryOutcome(emit, sequence);
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
    _carryOutcome(emit, sequence);
  }

  /// The act [sequence] answered is said whatever the reload after it did:
  /// one that could not reach the service, or failed its first read, emits
  /// nothing new, and the bar — the act's Undo with it — would be lost. The
  /// state on screen is shown again carrying it; a listener keyed on the
  /// sequence says it once, whichever state brought it first.
  void _carryOutcome(Emitter<ShareState> emit, int sequence) {
    final shown = state;
    final outcome = _outcome;
    if (emit.isDone || outcome == null || outcome.sequence != sequence) return;
    if (shown is! ShareLoaded || shown.outcome?.sequence == sequence) return;
    emit(
      ShareLoaded(
        availability: shown.availability,
        overview: shown.overview,
        look: shown.look,
        alerts: shown.alerts,
        outcome: outcome,
      ),
    );
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
      overview = await service.overview(withCounts: _opened);
      // A read a newer load overtook is not the last one read.
      if (load == _loads) _readOverview = overview;
    } catch (e, st) {
      // The page keeps what was last read; the next change reads again.
      // With nothing read yet, "None" would be a claim the read never made.
      debugPrint('[ShareBloc] overview not read: $e\n$st');
      final last = _readOverview;
      if (last != null) {
        overview = last;
      } else {
        if (load == _loads) emit(const ShareLoadFailed());
        return;
      }
    }
    final availability = service.availability;
    // Only while paired: Sync & sharing loads this for an account that
    // never paired too, and it must read nothing more for it.
    if (availability is! ShareNotPaired) {
      try {
        final look = await service.looks();
        if (load == _loads) _readLook = look;
        final alerts = await service.alerts();
        if (load == _loads) _readAlerts = alerts;
      } catch (e, st) {
        debugPrint('[ShareBloc] settings not read: $e\n$st');
      }
    }
    if (load != _loads) return;
    var next = ShareLoaded(
      availability: availability,
      overview: overview,
      look: _readLook,
      alerts: _readAlerts,
      outcome: _outcome,
    );
    for (final shows in _pending) {
      next = shows(next);
    }
    emit(next);
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

  /// The Undos added and not yet started, oldest first: the acts run one at
  /// a time, and an Undo queued behind a running one would be dropped with
  /// the queue when the bloc closes.
  final List<ShareUndoRequested> _queuedUndos = [];

  @override
  void add(ShareEvent event) {
    if (event is ShareUndoRequested && !isClosed) _queuedUndos.add(event);
    super.add(event);
  }

  /// An Undo still queued is written the way an Undo tapped after its bloc
  /// has gone is — through the surface's own road when it gave one, which
  /// says a failure on the app's messenger, else through the service.
  @override
  Future<void> close() {
    _availabilitySubscription?.cancel();
    _calendarSubscription?.cancel();
    _runsSubscription?.cancel();
    final orphaned = List.of(_queuedUndos);
    _queuedUndos.clear();
    for (final undo in orphaned) {
      unawaited(_writeOrphaned(undo));
    }
    return super.close();
  }

  Future<void> _writeOrphaned(ShareUndoRequested undo) async {
    try {
      final pastBloc = undo.pastBloc;
      if (pastBloc != null) {
        await pastBloc(undo.change);
      } else {
        await (await _resolveService()).undo(undo.change);
      }
    } catch (e, st) {
      debugPrint('[ShareBloc] queued undo not written: $e\n$st');
    }
  }
}
