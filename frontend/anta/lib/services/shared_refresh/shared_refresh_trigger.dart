import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../constants/shared_refresh_constants.dart';
import 'shared_refresh_ports.dart';
import 'shared_refresh_scheduler.dart';

/// How one trigger of the check ended.
enum SharedRefreshEnd {
  /// The app runs in this process and its own isolate did the read.
  forwarded,

  /// The app runs and its read failed or did not end in time.
  forwardFailed,

  /// The active database has no file: nothing is created for a check.
  noDatabase,

  /// The file was written at another schema than this build's — the app was
  /// updated and not opened yet: left alone until it is (decision e).
  schemaMismatch,

  /// A restore holds sync.
  suspended,

  /// The database does not sync as the paired account signed in now.
  notSharing,

  /// No alert depends on the partner's rows: nothing was read and no
  /// successor is scheduled.
  notWanted,

  /// The shared read ran, and the alert pass after it.
  read,

  /// A launch asked for the database: the run closed it and left the rest
  /// to the app, whose start reads the share itself.
  yielded,

  /// The time limit, or the platform, ended the run where it was.
  cut,

  /// A step threw.
  failed;

  /// Whether the platform should run the work again on its back-off: the
  /// endings that say nothing about whether a read is still owed.
  bool get retry => this == cut || this == failed || this == forwardFailed;
}

/// What started a trigger, carried in the work's input data under
/// [kSharedRefreshCauseKey].
enum SharedRefreshCause {
  /// The phone's own schedule.
  check,

  /// A message from the relay: the partner changed something just now.
  message;

  /// The cause a work's input names; [check] for none or an unknown one —
  /// a work scheduled by a build that carried none was the schedule's.
  static SharedRefreshCause fromInput(Map<String, dynamic>? inputData) {
    final name = inputData?[kSharedRefreshCauseKey];
    for (final cause in values) {
      if (cause.name == name) return cause;
    }
    return check;
  }

  /// The slot a work with this cause stands in, of the one its task name
  /// gives ([SharedRefreshSlot.ofTask]): the check's work is in that slot,
  /// a message's work in neither — it has a unique name of its own, so
  /// what is scheduled while it runs replaces no running work, and the
  /// check that stands is not the work that asks.
  SharedRefreshSlot? standsIn(SharedRefreshSlot named) =>
      this == message ? null : named;
}

/// What a run's alert pass found worth a read
/// (`SharedRefreshNeed.checkWorthy` / `pokeWorthy`).
typedef SharedRefreshWorth = ({bool check, bool poke});

/// Everything a run without the app touches — the platform, a file, the
/// network, the database — in the order of `docs/cloud-shared-freshness.md`
/// §6. A seam, so the order and every early end are proven against fakes.
abstract interface class SharedRefreshRunSteps {
  /// Step 1: preferences as the build reads them, and Firebase.
  Future<void> prepare();

  /// The schema the active database's file was written at; null when there
  /// is no file. Read without opening it.
  Future<int?> storedSchema();

  /// This build's schema.
  int get schema;

  /// Step 2: opens the database and registers what the run looks up.
  Future<void> open();

  /// Step 3, with [shares]: whether a restore holds sync.
  bool get suspended;

  /// Whether the database syncs as the paired account signed in now.
  Future<bool> shares();

  /// Step 4: an alert pass, which plans and schedules the successor from
  /// what it armed — only when the phone's own check is wanted, and into
  /// the slot this run is not in — and says what the pass found worth a
  /// read.
  Future<SharedRefreshWorth> planSuccessor();

  /// Steps 5 and 6: the shared read alone, then the reloads and the alert
  /// pass it asks for.
  Future<void> read();

  /// Ends [read] before its next page.
  Future<void> stopRead();

  /// Step 7: closes the database. Called whenever [open] was, however the
  /// run ended.
  Future<void> close();
}

/// One trigger of the check — the platform's scheduled work, or a message
/// that arrived with the app not in front: the app's own isolate does the
/// read when the app runs in this process, else the run without the app
/// (decision d).
class SharedRefreshTrigger {
  final SharedRefreshRunSteps _steps;
  final SharedRefreshRunPort _port;
  final Duration _limit;
  final SharedRefreshCause _cause;

  /// Where the work that fired this stands ([SharedRefreshCause.standsIn]).
  final SharedRefreshSlot? _slot;

  /// Why the run must end before its next step, once something asked.
  SharedRefreshEnd? _cutAs;
  bool _reading = false;
  final Completer<void> _ended = Completer<void>();

  /// [cause] decides what a run without the app reads for: the schedule's
  /// own check reads when the check is wanted, a message when an alert of
  /// mine stands on any event of the partner's — the one they just moved
  /// may be a past one. Either way only a wanted check leaves a successor.
  ///
  /// [slot] is the one the task that fired this names: for the check's own
  /// work the app is told it with a forwarded read, so the pass after that
  /// read schedules into the other and leaves this work standing until it
  /// is answered. A message's work stands in neither, and the app is told
  /// none.
  SharedRefreshTrigger({
    required SharedRefreshRunSteps steps,
    SharedRefreshCause cause = SharedRefreshCause.check,
    SharedRefreshSlot slot = SharedRefreshSlot.first,
    SharedRefreshRunPort? port,
    Duration limit = kSharedRefreshRunLimit,
  }) : _steps = steps,
       _cause = cause,
       _slot = cause.standsIn(slot),
       _port = port ?? SharedRefreshRunPort(),
       _limit = limit;

  /// Runs the trigger to its end. Never throws.
  Future<SharedRefreshEnd> fire() async {
    // The name first, the look for the app second: a launch does the same
    // with its own, so of the two at least one sees the other.
    _port.open();
    final limit = Timer(_limit, () => _cut(SharedRefreshEnd.cut));
    unawaited(_port.yieldRequested.then((_) => _cut(SharedRefreshEnd.yielded)));
    SharedRefreshEnd end;
    try {
      end = switch (await _port.forward(limit: _limit, slot: _slot)) {
        SharedRefreshForward.done => SharedRefreshEnd.forwarded,
        SharedRefreshForward.failed => SharedRefreshEnd.forwardFailed,
        SharedRefreshForward.noApp => await _run(),
      };
    } catch (error, stack) {
      debugPrint('[SharedRefresh] trigger failed: $error\n$stack');
      end = SharedRefreshEnd.failed;
    } finally {
      limit.cancel();
      // After the database is closed: this is what answers a waiting launch.
      _port.close();
      if (!_ended.isCompleted) _ended.complete();
    }
    // One line per trigger, naming the path it took: what a device pass
    // reads back to tell the app's own read from the run without the app.
    debugPrint('[SharedRefresh] trigger(${_cause.name}) ended: ${end.name}');
    return end;
  }

  /// The platform stopped the work: the run ends before its next step, and
  /// this completes once the database is closed — the platform tears the
  /// isolate down when its stop handler returns.
  Future<void> stop() {
    _cut(SharedRefreshEnd.cut);
    return _ended.future;
  }

  void _cut(SharedRefreshEnd as) {
    if (_cutAs != null || _ended.isCompleted) return;
    _cutAs = as;
    if (_reading) {
      unawaited(
        _steps.stopRead().catchError((Object error, StackTrace stack) {
          debugPrint('[SharedRefresh] read not stopped: $error\n$stack');
        }),
      );
    }
  }

  Future<SharedRefreshEnd> _run() async {
    var opened = false;
    try {
      await _steps.prepare();
      final stored = await _steps.storedSchema();
      if (stored == null) return SharedRefreshEnd.noDatabase;
      if (stored != _steps.schema) return SharedRefreshEnd.schemaMismatch;
      if (_cutAs case final cut?) return cut;
      // Before the open: one that throws midway is still closed.
      opened = true;
      await _steps.open();
      if (_cutAs case final cut?) return cut;
      if (_steps.suspended) return SharedRefreshEnd.suspended;
      if (!await _steps.shares()) return SharedRefreshEnd.notSharing;
      if (_cutAs case final cut?) return cut;
      // Before the read, so a run killed inside it has planned the next.
      final worth = await _steps.planSuccessor();
      final wanted = _cause == SharedRefreshCause.message
          ? worth.poke
          : worth.check;
      if (!wanted) return SharedRefreshEnd.notWanted;
      if (_cutAs case final cut?) return cut;
      _reading = true;
      try {
        await _steps.read();
      } finally {
        _reading = false;
      }
      return _cutAs ?? SharedRefreshEnd.read;
    } finally {
      if (opened) {
        try {
          await _steps.close();
        } catch (error, stack) {
          debugPrint('[SharedRefresh] database not closed: $error\n$stack');
        }
      }
    }
  }
}
