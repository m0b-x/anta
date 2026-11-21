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
/// the service reads. Every rule is the service's, the order of the share
/// writes too.
///
/// An act's write starts when the act is added ([add]); its handler, one
/// at a time, waits for it and says how it ended. So two quick ✕ are both
/// on their way before the page can close, and a close drops nothing: a
/// write ends on its own, and one that fails once the bloc has gone is said
/// by its surface's [ShareActEvent.failedPastBloc].
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
    on<ShareActEvent>((event, emit) {
      // The first of the acts started for this event whose handler has not
      // run: an act added twice is two writes, in the order added.
      for (final started in _started) {
        if (started.handled || !identical(started.event, event)) continue;
        started.handled = true;
        return _run(started, emit);
      }
      return Future<void>.value();
    }, transformer: oneAtATime);
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

  Future<void> _run(_StartedAct started, Emitter<ShareState> emit) {
    final event = started.event;
    return switch (event) {
      ShareCategoriesSet() => _act(emit, ShareAct.categoriesSet, started),
      ShareEventUnshared() => _act(
        emit,
        ShareAct.eventUnshared,
        started,
        asker: event.asker,
      ),
      ShareFolderShared() => _act(
        emit,
        ShareAct.folderShared,
        started,
        asker: event.asker,
      ),
      ShareFolderUnshared() => _act(
        emit,
        ShareAct.folderUnshared,
        started,
        asker: event.asker,
      ),
      ShareUndoRequested() => _act(
        emit,
        ShareAct.undo,
        started,
        asker: event.asker,
      ),
      ShareStopAllRequested() => _onStopAll(emit, started),
    };
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

  /// The overview reads that answered, counted, and the number of the one
  /// [_readOverview] holds ([ShareLoaded.read]).
  int _reads = 0;
  int _lastRead = 0;
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

  Future<void> _onStopAll(Emitter<ShareState> emit, _StartedAct started) async {
    final sequence = ++_outcomes;
    ShareOutcome outcome;
    try {
      final cleared = await started.write as int;
      outcome = ShareOutcome(
        sequence: sequence,
        act: ShareAct.stopAll,
        cleared: cleared,
      );
    } catch (_) {
      // Logged where the write started ([add]).
      outcome = ShareOutcome(
        sequence: sequence,
        act: ShareAct.stopAll,
        failure: ShareFailure.failed,
      );
    }
    if (!_answers(started)) return;
    _outcome = outcome;
    await _reload(emit);
    _carryOutcome(emit, sequence);
  }

  Future<void> _act(
    Emitter<ShareState> emit,
    ShareAct act,
    _StartedAct started, {
    Object? asker,
  }) async {
    final sequence = ++_outcomes;
    ShareOutcome outcome;
    try {
      final change = await started.write as ShareChange;
      outcome = ShareOutcome(
        sequence: sequence,
        act: act,
        change: change,
        asker: asker,
      );
    } on ShareRefused {
      outcome = ShareOutcome(
        sequence: sequence,
        act: act,
        failure: ShareFailure.refused,
        asker: asker,
      );
    } catch (_) {
      // Logged where the write started ([add]).
      outcome = ShareOutcome(
        sequence: sequence,
        act: act,
        failure: ShareFailure.failed,
        asker: asker,
      );
    }
    if (!_answers(started)) return;
    _outcome = outcome;
    await _reload(emit);
    _carryOutcome(emit, sequence);
  }

  /// Whether [started]'s handler says how its write ended: not once the
  /// bloc is closing, where a failure is said past it instead
  /// ([_sayPastBloc]) — by [close] when it had already failed, by the
  /// write's own end otherwise.
  bool _answers(_StartedAct started) {
    _started.remove(started);
    if (_closing) return false;
    started.said = true;
    return true;
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
        read: shown.read,
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
    int read;
    try {
      overview = await service.overview(withCounts: _opened);
      read = ++_reads;
      // A read a newer load overtook is not the last one read.
      if (load == _loads) {
        _readOverview = overview;
        _lastRead = read;
      }
    } catch (e, st) {
      // The page keeps what was last read; the next change reads again.
      // With nothing read yet, "None" would be a claim the read never made.
      debugPrint('[ShareBloc] overview not read: $e\n$st');
      final last = _readOverview;
      if (last != null) {
        overview = last;
        read = _lastRead;
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
      read: read,
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

  /// The acts whose writes have started and whose end is not yet said by
  /// their handler, oldest first: the handlers run one at a time, and those
  /// that have not run when the bloc closes never will.
  final List<_StartedAct> _started = [];

  /// Set first thing in [close]: [isClosed] turns true only at its end, and
  /// an act added in between would be refused by the closed event stream —
  /// lost, and thrown at its asker. From here on a write's failure is said
  /// past the bloc.
  bool _closing = false;

  /// Starts an act's write at once — the service writes in the order it is
  /// asked, so acts added in order land in order, and before any later
  /// write a surface or a reopened page asks for — and hands the act to its
  /// handler, which waits for that write. Added while the bloc is closing
  /// or closed, it is written all the same, and only a failure is said.
  @override
  void add(ShareEvent event) {
    if (event is! ShareActEvent) return super.add(event);
    final started = _StartedAct(event);
    started.write = _write(event);
    unawaited(
      started.write.then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          if (e is! ShareRefused) {
            debugPrint('[ShareBloc] ${event.runtimeType} failed: $e\n$st');
          }
          started.failure = e is ShareRefused
              ? ShareFailure.refused
              : ShareFailure.failed;
          if (_closing) _sayPastBloc(started);
        },
      ),
    );
    if (_closing) return;
    _started.add(started);
    super.add(event);
  }

  /// [event]'s write, asked of the service through [_resolveService]: the
  /// calls resolve in the order they were made, so they reach the service
  /// in the order the acts were added.
  Future<Object> _write(ShareActEvent event) async {
    final generation = ShareService.databaseGeneration;
    final service = await _resolveService();
    // A switch while the service resolved hands back the new database's,
    // which must not take an act asked under the old one.
    if (ShareService.databaseGeneration != generation) {
      throw const ShareDatabaseSwitched();
    }
    return switch (event) {
      ShareCategoriesSet(:final shared, :final unshared) =>
        service.changeCategoriesShared(shared: shared, unshared: unshared),
      ShareEventUnshared(:final eventId) => service.setEventShared(
        eventId,
        false,
      ),
      ShareFolderShared(:final folderId) => service.setFolderShared(
        folderId,
        true,
      ),
      ShareFolderUnshared(:final folderId) => service.setFolderShared(
        folderId,
        false,
      ),
      ShareUndoRequested(:final change) => service.undo(change),
      ShareStopAllRequested() => service.stopAll(),
    };
  }

  /// A failure its handler will not say, said once by the road its surface
  /// gave: neither the bloc nor, often, the surface is left to say it.
  void _sayPastBloc(_StartedAct started) {
    final failure = started.failure;
    if (started.said || failure == null) return;
    started.said = true;
    started.event.failedPastBloc?.call(failure);
  }

  /// Drops nothing: every act added has its write on its way. One that
  /// already failed and waits for a handler that will not run now is said
  /// past the bloc here; one still writing, when it ends ([add]).
  @override
  Future<void> close() {
    _closing = true;
    _availabilitySubscription?.cancel();
    _calendarSubscription?.cancel();
    _runsSubscription?.cancel();
    for (final started in _started) {
      _sayPastBloc(started);
    }
    _started.clear();
    return super.close();
  }
}

/// An act whose write [ShareBloc.add] started, until its handler or the
/// bloc's close has said how it ended.
final class _StartedAct {
  _StartedAct(this.event);

  final ShareActEvent event;

  /// The service's answer: a [ShareChange], or the count "Stop sharing
  /// everything" cleared.
  late final Future<Object> write;

  /// Its handler has started.
  bool handled = false;

  /// How its write failed, once it has.
  ShareFailure? failure;

  /// Its end has been said — by its outcome, or past the bloc.
  bool said = false;
}
