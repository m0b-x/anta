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

  /// A database is being replaced — a restore, an import, a download:
  /// nothing is opened beside it, and nothing more is armed or read into a
  /// database that was open when it began. The operation's own end brings
  /// the app's pass, which plans the check again.
  suspended,

  /// Whether one is being replaced could not be read from the store. Not
  /// knowing is no licence to open, and no reason to stay away either: the
  /// platform asks again, where [suspended] waits for the app.
  replacingUnknown,

  /// The database does not sync as the paired account signed in now.
  notSharing,

  /// Whether it does could not be told: Firebase did not come up, or the
  /// stored account was not restored in time. Nothing was planned or read.
  sharingUnknown,

  /// Another run holds the database and did not end when asked.
  busy,

  /// The read was asked for and was not made, for a cause that passes by
  /// itself — offline, a quota, dropped by the engine: a read is still
  /// owed. One a refusal or a sign-out ended is [read]: nothing a retry
  /// would change.
  readFailed,

  /// The app has not yet stored what its alert passes arm under, so no pass
  /// ran here and nothing was read: a read would only ask for the pass that
  /// cannot run. The app's next open stores it and plans the check.
  noArmContext,

  /// No alert depends on the partner's rows: nothing was read and no
  /// successor is scheduled.
  notWanted,

  /// The shared read ran, and the alert pass after it.
  read,

  /// The app asked for the database — its launch, or its name taken back:
  /// the run closed it and left the rest to the app, which reads the share
  /// itself.
  yielded,

  /// A later run asked for the database and this one closed it, owing
  /// nothing: the check's own run once its successor is planned — or a run
  /// that has given way [kSharedRefreshGiveWayAttempts] times in a row.
  gaveWay,

  /// A run gave way to a later run and still owes what it was started for.
  /// That one reads only if its own cause wants a read — a check's run that
  /// finds nothing wanted reads nothing — so the change a message's run was
  /// started for may still be unread; and a check's run ended before its
  /// alert pass has planned no successor. Run again after the other has
  /// ended: the check's work by the platform, a message's by the fresh work
  /// its run hands over (`fireSharedRefresh`).
  gaveWayOwed,

  /// The time limit, or the platform, ended the run where it was.
  cut,

  /// A step did not end within the grace after the run was cut: the
  /// trigger closed what it had opened, gave its name up and left the step
  /// where it was.
  abandoned,

  /// A message's work ended still owing its read
  /// [kSharedRefreshGiveWayAttempts] times in a row — a read that keeps
  /// failing, Firebase that never comes up, a pass that always outlasts
  /// the limit — and hands no further work over: each such end hands a
  /// fresh one to the platform, and a cause that never heals would do so
  /// without end. The next message starts afresh.
  retriesSpent,

  /// A step threw.
  failed;

  /// Whether the platform should run the work again on its back-off: the
  /// endings that leave a read owed for a cause that passes by itself. An
  /// ending whose cause only the person or the app can change — another
  /// schema, not paired, another database's pair, nothing stored to arm
  /// under — never asks: a work that retried on it would loop.
  bool get retry => switch (this) {
    cut ||
    abandoned ||
    failed ||
    replacingUnknown ||
    forwardFailed ||
    sharingUnknown ||
    busy ||
    readFailed ||
    gaveWayOwed => true,
    forwarded ||
    noDatabase ||
    schemaMismatch ||
    suspended ||
    notSharing ||
    noArmContext ||
    notWanted ||
    read ||
    retriesSpent ||
    yielded ||
    gaveWay => false,
  };
}

/// Whether the open database syncs as the paired account signed in now, as
/// a run can tell it.
enum SharedRefreshSharing {
  yes,

  /// Told for certain: not bound, signed out, not paired, or the pair a
  /// message named is another database's.
  no,

  /// Not told: what would say is not up yet.
  unknown,
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

  /// Whether a database of this install is being replaced — the marker the
  /// app's isolate leaves for this one to read (`DatabaseReplacing`). Asked
  /// first and again before each step that writes; read only, never
  /// cleared here. Null when the store could not be read.
  Future<bool?> replacing();

  /// The schema the active database's file was written at; null when there
  /// is no file. Read without opening it, and without the launch's repairs:
  /// the active name is only read.
  Future<int?> storedSchema();

  /// This build's schema.
  int get schema;

  /// Step 2: opens the database and registers what the run looks up. A run
  /// creates no database and migrates none: a file that went, or was
  /// written at another schema, since [storedSchema] looked is said so and
  /// left as it is.
  Future<SharedRefreshOpened> open();

  /// Whether the database syncs as the paired account signed in now.
  Future<SharedRefreshSharing> shares();

  /// Step 4: an alert pass, which plans and schedules the successor from
  /// what it armed — only when the phone's own check is wanted, and into
  /// the slot this run is not in — and says what the pass found worth a
  /// read. Null when no pass could run here: the app has stored nothing to
  /// arm under yet, and a run arms nothing the app would not.
  Future<SharedRefreshWorth?> planSuccessor();

  /// Steps 5 and 6: the shared read alone, then the reloads and the alert
  /// pass it asks for. False when the read is still owed: it was not made,
  /// for a cause that passes by itself — the reader stamps a failure and
  /// returns normally, so nothing is thrown for it.
  Future<bool> read();

  /// Ends [read] before its next page.
  Future<void> stopRead();

  /// Step 7: closes the database. Called whenever [open] was, however the
  /// run ended.
  Future<void> close();

  /// The work ends asking to be run again: counts it, and answers whether
  /// the platform may — false at the [kSharedRefreshGiveWayAttempts]th time
  /// in a row, where the count starts over. The platform's own attempt
  /// count is not handed to Dart, and its back-off never gives up by
  /// itself.
  ///
  /// Like [retriesOver] and [workConsumed], asked of a trigger that may not
  /// have reached [prepare]: it finds the store by itself.
  Future<bool> retryCounted();

  /// The work ended any other way: its row of retries is over.
  Future<void> retriesOver();

  /// The check's own work ended and is not run again without the app's
  /// isolate having served it: it stands no more in the plan's memory
  /// (`SharedRefreshMemory`). A run that got as far as its open said so
  /// then; one that ended before — no database, another schema, a
  /// replacement in flight — says it here, or the memory would hold a due
  /// check that no pass may replace and no platform will run.
  Future<void> workConsumed();
}

/// How [SharedRefreshRunSteps.open] ended.
enum SharedRefreshOpened {
  opened,

  /// The file is no longer there.
  noDatabase,

  /// The file is at another schema than this build's.
  schemaMismatch,
}

/// One trigger of the check — the platform's scheduled work, or a message
/// that arrived with the app not in front: the app's own isolate does the
/// read when the app runs in this process, else the run without the app
/// (decision d).
class SharedRefreshTrigger {
  final SharedRefreshRunSteps _steps;
  final SharedRefreshRunPort _port;
  final Duration _limit;
  final Duration _grace;
  final Duration _closeBound;
  final SharedRefreshCause _cause;

  /// Where the work that fired this stands ([SharedRefreshCause.standsIn]).
  final SharedRefreshSlot? _slot;
  final String? _pair;

  /// Why the run must end before its next step, once something asked.
  SharedRefreshEnd? _cutAs;
  bool _reading = false;
  bool _forwarding = false;
  bool _opened = false;
  bool _closed = false;

  /// Whether the alert pass that plans the successor has returned: a
  /// check's run ended before it has left no check behind.
  bool _planStood = false;

  /// Runs out [_grace] after the limit or the platform cut the run.
  Timer? _abandon;

  /// Completed when the trigger ends without its work having returned.
  final Completer<SharedRefreshEnd> _left = Completer<SharedRefreshEnd>();
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
  ///
  /// [pair] is the pair a message named. A run without the app is told it
  /// through its steps; a forwarded read carries it to the app, which holds
  /// one database and reads for no other pair's message (case B13).
  ///
  /// [grace] is what a step in flight is given to end once the run was cut,
  /// and [closeBound] what the close of a run left behind is given.
  SharedRefreshTrigger({
    required SharedRefreshRunSteps steps,
    SharedRefreshCause cause = SharedRefreshCause.check,
    SharedRefreshSlot slot = SharedRefreshSlot.first,
    String? pair,
    SharedRefreshRunPort? port,
    Duration limit = kSharedRefreshRunLimit,
    Duration grace = kSharedRefreshAbandonGrace,
    Duration closeBound = kSharedRefreshAbandonCloseBound,
  }) : _steps = steps,
       _cause = cause,
       _slot = cause.standsIn(slot),
       _pair = pair,
       _port = port ?? SharedRefreshRunPort(),
       _limit = limit,
       _grace = grace,
       _closeBound = closeBound;

  /// Runs the trigger to its end. Never throws.
  Future<SharedRefreshEnd> fire() async {
    final limit = Timer(_limit, () => _cut(SharedRefreshEnd.cut));
    SharedRefreshEnd end;
    try {
      // Whichever comes first: the work's own end, or the moment the
      // trigger leaves it — a step that never returns otherwise held the
      // run's name for good, every later trigger ending busy and the
      // platform's stop never answered (review H3). What the work throws
      // after it was left is dropped with it.
      end = await Future.any([_work(), _left.future]);
      if (_left.isCompleted) await _close(within: _closeBound);
    } catch (error, stack) {
      debugPrint('[SharedRefresh] trigger failed: $error\n$stack');
      end = SharedRefreshEnd.failed;
    } finally {
      limit.cancel();
      _abandon?.cancel();
      // After the database is closed: this is what answers a waiting launch.
      _port.close();
      if (!_ended.isCompleted) _ended.complete();
    }
    // Once the name is given up: whoever waits for the database is not kept
    // waiting on this.
    end = await _settle(end);
    // One line per trigger, naming the path it took: what a device pass
    // reads back to tell the app's own read from the run without the app.
    debugPrint('[SharedRefresh] trigger(${_cause.name}) ended: ${end.name}');
    return end;
  }

  Future<SharedRefreshEnd> _work() async {
    // The name first, the look for the app second: a launch does the same
    // with its own, so of the two at least one sees the other. A run
    // already alive is asked to end and has ended before this one holds
    // the name — so before it opens, plans or schedules anything.
    if (!await _port.open()) return SharedRefreshEnd.busy;
    // Left while it waited for the name: the name it took is nobody's.
    if (_ended.isCompleted) {
      _port.close();
      return SharedRefreshEnd.cut;
    }
    unawaited(_port.yieldRequested.then((_) => _cut(SharedRefreshEnd.yielded)));
    // Stopped before it got here — while what precedes the trigger was
    // awaited, or the name: the app is asked for no read on behalf of a
    // work that is over. Gone on, the stop found no forward to leave, and
    // the run waited out the whole grace while the app read for nobody.
    if (_cutAs case final cut?) return cut;
    final SharedRefreshForward forward;
    _forwarding = true;
    try {
      forward = await _port.forward(limit: _limit, slot: _slot, pair: _pair);
    } finally {
      _forwarding = false;
    }
    return switch (forward) {
      SharedRefreshForward.done => SharedRefreshEnd.forwarded,
      SharedRefreshForward.failed => SharedRefreshEnd.forwardFailed,
      SharedRefreshForward.noApp => await _run(),
    };
  }

  /// Counts a run that gave way and still owes what it was started for, and
  /// ends the row of them at any other end.
  ///
  /// The app — at any moment before the end — reads the share itself:
  /// [SharedRefreshEnd.yielded], for either cause. A later run reads only
  /// if its own cause wants a read, so the run it ended may owe: a
  /// message's run its read, and a check's run its successor while the
  /// pass that plans it had not returned — ended there with no retry, the
  /// phone was left with no check at all (review H5). Either is run again,
  /// three attempts in a row at most, counted by [SharedRefreshRunSteps]
  /// so a work that keeps finding a run ends.
  ///
  /// Every other end clears the count, the ones that never reached the
  /// run's first step included — a read the app made, a name a live run
  /// held: counted across them, two give-ways weeks apart were "in a row"
  /// (review H8).
  ///
  /// A message's work counts every end that asks for a retry, not the
  /// give-ways alone: each such end has a fresh work handed over, so a
  /// cause that never heals — a row that throws in every read, Firebase
  /// that never comes up — would hand works over without end (review R3).
  /// At the cap it ends
  /// [SharedRefreshEnd.retriesSpent]. The check's work counts its give-ways
  /// only: its retry chain and its successor replace each other, two works
  /// at most, and the platform's back-off spaces the rest.
  ///
  /// And a check's work that ends here for good, unserved by the app, is
  /// said to stand no more ([SharedRefreshRunSteps.workConsumed]).
  Future<SharedRefreshEnd> _settle(SharedRefreshEnd end) async {
    final message = _cause == SharedRefreshCause.message;
    if (end == SharedRefreshEnd.yielded && !_port.yieldAskedByApp) {
      end = message || !_planStood
          ? SharedRefreshEnd.gaveWayOwed
          : SharedRefreshEnd.gaveWay;
    }
    // A retrying end of a message's work the platform stopped is not
    // counted. What it answers is not acted on: superseded by a newer
    // message's work, its "one more" is that work's to count — and this
    // isolate, still winding down, could write it after the newer run had
    // cleared the row, leaving a count no work stands for. Only that: any
    // other end of a stopped run ends the row like every such end — a run
    // that had read when the stop came, as a newer message's hand-over
    // stops whatever runs, must not leave two standing for the next work's
    // first failed read to end the row on.
    if (message && _stoppedByPlatform && end.retry) return end;
    final counted =
        end == SharedRefreshEnd.gaveWayOwed || (message && end.retry);
    try {
      if (!counted) {
        await _steps.retriesOver().timeout(_closeBound);
      } else if (!await _steps.retryCounted().timeout(_closeBound)) {
        end = _spent(end);
      }
    } catch (error, stack) {
      // Uncounted, an end is not retried: a count that cannot be kept must
      // not become a work that never ends.
      debugPrint('[SharedRefresh] retry not counted: $error\n$stack');
      if (counted) end = _spent(end);
    }
    // The app's isolate says so itself for a read it served.
    if (!message && !end.retry && end != SharedRefreshEnd.forwarded) {
      try {
        await _steps.workConsumed().timeout(_closeBound);
      } catch (error, stack) {
        debugPrint('[SharedRefresh] work not written off: $error\n$stack');
      }
    }
    return end;
  }

  static SharedRefreshEnd _spent(SharedRefreshEnd end) =>
      end == SharedRefreshEnd.gaveWayOwed
      ? SharedRefreshEnd.gaveWay
      : SharedRefreshEnd.retriesSpent;

  /// The platform stopped the work: the run ends before its next step, and
  /// this completes once the database is closed — the platform tears the
  /// isolate down when its stop handler returns. A step that does not end
  /// within the grace is left where it is, and a wait for the app's own
  /// read is over at once: the app goes on reading for itself.
  Future<void> stop() {
    _stoppedByPlatform = true;
    _cut(SharedRefreshEnd.cut);
    if (_forwarding) _leave(SharedRefreshEnd.cut);
    return _ended.future;
  }

  /// Whether the platform stopped this work ([stop]) — its time was up, a
  /// constraint went, or a newer work took its place. What such a work
  /// answers changes nothing, and it hands nothing over (`fireSharedRefresh`).
  bool get stoppedByPlatform => _stoppedByPlatform;
  bool _stoppedByPlatform = false;

  void _leave(SharedRefreshEnd as) {
    if (!_left.isCompleted) _left.complete(as);
  }

  void _cut(SharedRefreshEnd as) {
    if (_ended.isCompleted) return;
    // Armed by the limit and the platform alone, and over an earlier cut
    // too: a run asked to give way and then stuck is bounded like any.
    if (as == SharedRefreshEnd.cut) {
      _abandon ??= Timer(_grace, () => _leave(SharedRefreshEnd.abandoned));
    }
    if (_cutAs != null) return;
    _cutAs = as;
    if (_reading) {
      unawaited(
        _steps.stopRead().catchError((Object error, StackTrace stack) {
          debugPrint('[SharedRefresh] read not stopped: $error\n$stack');
        }),
      );
    }
  }

  /// The marker, asked again before each step that writes: a restore or an
  /// import that began after the run's first look must not find the run
  /// arming or reading into the database it replaces.
  Future<SharedRefreshEnd?> _replaced() async =>
      switch (await _steps.replacing()) {
        null => SharedRefreshEnd.replacingUnknown,
        true => SharedRefreshEnd.suspended,
        false => null,
      };

  /// Once, whoever asks: the run's own end, or the trigger leaving a run
  /// that did not end — which gives the close a bound.
  Future<void> _close({Duration? within}) async {
    if (!_opened || _closed) return;
    _closed = true;
    try {
      final closing = _steps.close();
      await (within == null ? closing : closing.timeout(within));
    } catch (error, stack) {
      debugPrint('[SharedRefresh] database not closed: $error\n$stack');
    }
  }

  Future<SharedRefreshEnd> _run() async {
    try {
      await _steps.prepare();
      if (await _replaced() case final end?) return end;
      final stored = await _steps.storedSchema();
      if (stored == null) return SharedRefreshEnd.noDatabase;
      if (stored != _steps.schema) return SharedRefreshEnd.schemaMismatch;
      if (_cutAs case final cut?) return cut;
      // Before the open: one that throws midway is still closed.
      _opened = true;
      final found = await _steps.open();
      // Returned after the trigger had left it: the close made then found
      // nothing open yet, so what this opened is closed now — and nothing
      // more is done. The work was ended for a retry, and stands.
      if (_left.isCompleted) {
        try {
          await _steps.close().timeout(_closeBound);
        } catch (error, stack) {
          debugPrint('[SharedRefresh] late open not closed: $error\n$stack');
        }
        return SharedRefreshEnd.abandoned;
      }
      switch (found) {
        case SharedRefreshOpened.noDatabase:
          return SharedRefreshEnd.noDatabase;
        case SharedRefreshOpened.schemaMismatch:
          return SharedRefreshEnd.schemaMismatch;
        case SharedRefreshOpened.opened:
      }
      if (_cutAs case final cut?) return cut;
      switch (await _steps.shares()) {
        case SharedRefreshSharing.no:
          return SharedRefreshEnd.notSharing;
        case SharedRefreshSharing.unknown:
          return SharedRefreshEnd.sharingUnknown;
        case SharedRefreshSharing.yes:
      }
      if (_cutAs case final cut?) return cut;
      if (await _replaced() case final end?) return end;
      // Before the read, so a run killed inside it has planned the next.
      final worth = await _steps.planSuccessor();
      _planStood = true;
      if (worth == null) return SharedRefreshEnd.noArmContext;
      final wanted = _cause == SharedRefreshCause.message
          ? worth.poke
          : worth.check;
      if (!wanted) return SharedRefreshEnd.notWanted;
      if (_cutAs case final cut?) return cut;
      if (await _replaced() case final end?) return end;
      _reading = true;
      final bool made;
      try {
        made = await _steps.read();
      } finally {
        _reading = false;
      }
      return _cutAs ??
          (made ? SharedRefreshEnd.read : SharedRefreshEnd.readFailed);
    } finally {
      await _close();
    }
  }
}
