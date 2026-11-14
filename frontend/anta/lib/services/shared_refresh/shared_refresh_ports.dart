import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

import '../../constants/shared_refresh_constants.dart';
import 'shared_refresh_scheduler.dart';

/// The process's registry of named ports — the seam the handshake of
/// `docs/cloud-shared-freshness.md` §5 is proven through in one isolate.
abstract interface class PortRegistry {
  SendPort? lookup(String name);

  /// False when [name] is taken.
  bool register(SendPort port, String name);

  bool remove(String name);
}

/// [PortRegistry] over the engine's own `IsolateNameServer`, which every
/// isolate of the process shares and none outlives.
class IsolateNamePortRegistry implements PortRegistry {
  const IsolateNamePortRegistry();

  @override
  SendPort? lookup(String name) => IsolateNameServer.lookupPortByName(name);

  @override
  bool register(SendPort port, String name) =>
      IsolateNameServer.registerPortWithName(port, name);

  @override
  bool remove(String name) => IsolateNameServer.removePortNameMapping(name);
}

/// The words of the handshake. A message is `[verb, reply port]` — a read
/// adds the slot of the work that asks for it — and an answer is one of
/// the answers below, alone. Only strings and ports cross: the two
/// isolates are roots of engines of their own and share no heap.
abstract final class SharedRefreshWire {
  static const String ping = 'ping';
  static const String pong = 'pong';

  /// Asks the app's isolate for the shared read; answered [done] when it
  /// has ended, [failed] when it could not be run.
  static const String read = 'read';

  /// The app asks a run without it to close the database — at its launch,
  /// or as it takes its name back; answered [done]. The app reads the share
  /// itself afterwards, so the run that gives way owes nothing.
  static const String giveWay = 'yield';

  /// [giveWay] asked by a later run. A verb of its own because the run that
  /// gives way has to know who takes its place: a run reads only if its own
  /// cause wants a read, so a message's run ended by one may leave the
  /// change it was started for unread.
  static const String giveWayToRun = 'yield-to-run';
  static const String done = 'done';
  static const String failed = 'failed';
}

/// One question to [port], and its answer — null when none came within
/// [timeout]. A read carries two words more, each empty for none: the slot
/// of the work that asks, and the pair a message named.
Future<String?> _ask(
  SendPort port,
  String verb,
  Duration timeout, {
  String? word,
  String? pair,
}) async {
  final reply = ReceivePort();
  try {
    port.send([
      verb,
      reply.sendPort,
      if (word != null || pair != null) ...[word ?? '', pair ?? ''],
    ]);
    final answer = await reply.first.timeout(timeout, onTimeout: () => null);
    return answer is String ? answer : null;
  } finally {
    reply.close();
  }
}

({String verb, SendPort reply, String? word, String? pair})? _parse(
  Object? message,
) {
  String? said(String word) => word.isEmpty ? null : word;
  return switch (message) {
    [final String verb, final SendPort reply] => (
      verb: verb,
      reply: reply,
      word: null,
      pair: null,
    ),
    [
      final String verb,
      final SendPort reply,
      final String word,
      final String pair,
    ] =>
      (verb: verb, reply: reply, word: said(word), pair: said(pair)),
    _ => null,
  };
}

/// One read a trigger asked the app for, as [SharedRefreshAppPort] hands it
/// to the app.
class SharedRefreshReadAsk {
  /// The slot of the work that asks: that work is running, and must not be
  /// replaced by what the read plans. Null when the asker names none — a
  /// message's work, which stands in neither slot.
  final SharedRefreshSlot? slot;

  /// The pair a relay message named; null for the schedule's own check. A
  /// database in another pair reads nothing for it (case B13).
  final String? pair;

  SharedRefreshReadAsk._({this.slot, this.pair});

  /// Whether the asker has stopped waiting: a trigger waits for the answer
  /// as long as it may work and no longer. A read not begun by then is not
  /// begun — held back by a launch that hung, reads piled up, each asker
  /// was answered failure, and all of them ran once the app came up, each
  /// with an alert pass nobody waited for (review item 9).
  bool get givenUp => _givenUp;
  bool _givenUp = false;
}

/// Asks the run that answers under [run] to close the database and waits
/// for it, at most [timeout]. The wait ends with the run's answer — or the
/// moment its name is gone, looked for every [kSharedRefreshYieldPoll]: a
/// run gives its name up once it has closed the database, and one that did
/// so a moment before the question reached it will never answer. [verb]
/// says who asks: [SharedRefreshWire.giveWay] the app,
/// [SharedRefreshWire.giveWayToRun] a later run.
///
/// With [deadAfter] the holder is pinged in the same turn, and one that has
/// neither answered the ping nor given way by then is a run killed with its
/// engine: its name is removed and the wait is over. A later run pings
/// before it asks and passes none.
///
/// True when the wait ended that way — on silence. Silence is not proof: a
/// run whose isolate was busy for longer than [deadAfter] is alive, holds
/// the database and ends only at its next step, with nothing but the
/// connection's busy timeout between it and whoever goes on. The asker is
/// told, so it can make good what such a run wrote behind it.
Future<bool> _askToGiveWay(
  PortRegistry registry,
  SendPort run,
  Duration timeout, {
  required String verb,
  Duration? deadAfter,
}) async {
  final reply = ReceivePort();
  final gone = Completer<void>();
  void end() {
    if (!gone.isCompleted) gone.complete();
  }

  final answers = reply.listen((_) => end());
  ReceivePort? pong;
  Timer? dead;
  var silent = false;
  if (deadAfter != null) {
    var alive = false;
    pong = ReceivePort()..listen((_) => alive = true);
    dead = Timer(deadAfter, () {
      if (alive || gone.isCompleted) return;
      silent = true;
      try {
        // Only the mapping that went unanswered.
        if (registry.lookup(kSharedRefreshRunPort) == run) {
          registry.remove(kSharedRefreshRunPort);
        }
      } catch (error) {
        debugPrint('[SharedRefresh] dead run\'s name not removed: $error');
      }
      end();
    });
    run.send([SharedRefreshWire.ping, pong.sendPort]);
  }
  final poll = Timer.periodic(kSharedRefreshYieldPoll, (_) {
    // A registry that cannot be asked ends the wait too: a launch waits on
    // this before it has its error hooks, and a timer that throws there
    // throws at nobody, every quarter second.
    try {
      if (registry.lookup(kSharedRefreshRunPort) != run) end();
    } catch (error) {
      debugPrint('[SharedRefresh] run\'s name not looked up: $error');
      end();
    }
  });
  final limit = Timer(timeout, end);
  try {
    run.send([verb, reply.sendPort]);
    await gone.future;
  } finally {
    poll.cancel();
    limit.cancel();
    dead?.cancel();
    pong?.close();
    await answers.cancel();
    reply.close();
  }
  return silent;
}

/// The app's side: the one isolate that holds the database while the app
/// runs, answering under [kSharedRefreshAppPort].
///
/// Opened by the launch **before** it opens the database, in the same
/// synchronous step as its look for a run in flight ([yieldRunInFlight]):
/// each side takes its own name first and looks for the other's second, so
/// of a launch and a run that start together at least one sees the other. A
/// ping is answered at once; a read waits for the app to be up, which the
/// read handed in does itself.
class SharedRefreshAppPort {
  final PortRegistry _registry;
  final Future<void> Function(SharedRefreshReadAsk ask) _read;
  final Duration _yieldTimeout;
  final Duration _deadRunAfter;
  final Duration _readLimit;
  ReceivePort? _port;

  /// [read] runs the shared read on the app's own engine and completes
  /// when it has ended — once the launch has brought the app up, which it
  /// waits for itself. It is handed what the asker said of itself, and can
  /// ask whether that one still waits ([SharedRefreshReadAsk.givenUp]).
  ///
  /// [readLimit] is how long an asker is taken to wait for its answer:
  /// a little under the trigger's own limit, the two being one build in
  /// one process ([kSharedRefreshForwardPatience]).
  SharedRefreshAppPort({
    required Future<void> Function(SharedRefreshReadAsk ask) read,
    PortRegistry registry = const IsolateNamePortRegistry(),
    Duration yieldTimeout = kSharedRefreshYieldTimeout,
    Duration deadRunAfter = kSharedRefreshDeadRunAfter,
    Duration readLimit = kSharedRefreshForwardPatience,
  }) : _read = read,
       _registry = registry,
       _yieldTimeout = yieldTimeout,
       _deadRunAfter = deadRunAfter,
       _readLimit = readLimit;

  /// Takes the name, over one a dead isolate of this process left.
  /// Synchronous. Again after a trigger took the name for stale: the port
  /// is kept and only named anew. True when the name was taken now — false
  /// when this port already held it, and when the registry refused it:
  /// nothing answers under the name then, and whoever acts on a name taken
  /// must not act on that.
  bool open() {
    final port = _port ??= ReceivePort()..listen(_onMessage);
    if (_registry.lookup(kSharedRefreshAppPort) == port.sendPort) return false;
    _registry.remove(kSharedRefreshAppPort);
    return _registry.register(port.sendPort, kSharedRefreshAppPort);
  }

  /// Asks a run in flight to close the database and waits for it, at most
  /// [kSharedRefreshYieldTimeout] — and pings it in the same turn: a holder
  /// that has neither answered nor given way within
  /// [kSharedRefreshDeadRunAfter] is a dead run's name, removed here so
  /// that this launch goes on and the next finds none. Null, and so nothing
  /// to await, when no run holds the name — every ordinary launch.
  ///
  /// True when the holder was only silent: its name is gone, and it may
  /// have been a live run that was busy — the caller owes what such a run
  /// wrote behind it a catch-up. False for a holder that answered or gave
  /// way.
  Future<bool>? yieldRunInFlight() {
    final run = _registry.lookup(kSharedRefreshRunPort);
    if (run == null) return null;
    return _askToGiveWay(
      _registry,
      run,
      _yieldTimeout,
      verb: SharedRefreshWire.giveWay,
      deadAfter: _deadRunAfter,
    );
  }

  /// Gives the name up and keeps the port: [open] names it again. Only a
  /// name this port holds — one a later launch took is that launch's.
  void giveUpName() {
    final port = _port;
    if (port == null) return;
    if (_registry.lookup(kSharedRefreshAppPort) == port.sendPort) {
      _registry.remove(kSharedRefreshAppPort);
    }
  }

  void close() {
    final port = _port;
    if (port == null) return;
    giveUpName();
    _port = null;
    port.close();
  }

  void _onMessage(Object? message) {
    final asked = _parse(message);
    if (asked == null) return;
    switch (asked.verb) {
      case SharedRefreshWire.ping:
        asked.reply.send(SharedRefreshWire.pong);
      case SharedRefreshWire.read:
        // No word is no slot. Both sides are one build in one process, so
        // a word is always a slot's own name.
        final word = asked.word;
        final ask = SharedRefreshReadAsk._(
          slot: word == null ? null : SharedRefreshSlot.ofTask(word),
          pair: asked.pair,
        );
        final patience = Timer(_readLimit, () => ask._givenUp = true);
        unawaited(
          _read(ask)
              .then<void>(
                (_) => asked.reply.send(SharedRefreshWire.done),
                onError: (Object error, StackTrace stack) {
                  debugPrint('[SharedRefresh] forwarded read failed: $error');
                  asked.reply.send(SharedRefreshWire.failed);
                },
              )
              .whenComplete(patience.cancel),
        );
    }
  }
}

/// How a trigger's question of the app ended.
enum SharedRefreshForward {
  /// No app answers in this process: the run goes on without it.
  noApp,

  /// The app's isolate did the read.
  done,

  /// The app is there and its read failed, or did not end in time.
  failed,
}

/// A trigger's side: the name a run without the app holds
/// ([kSharedRefreshRunPort]), and its questions of the app.
class SharedRefreshRunPort {
  final PortRegistry _registry;
  final Duration _pingTimeout;
  ReceivePort? _port;
  final List<SendPort> _yieldAsked = [];
  final Completer<void> _yield = Completer<void>();

  final Duration _yieldTimeout;

  SharedRefreshRunPort({
    PortRegistry registry = const IsolateNamePortRegistry(),
    Duration pingTimeout = kSharedRefreshPingTimeout,
    Duration yieldTimeout = kSharedRefreshYieldTimeout,
  }) : _registry = registry,
       _pingTimeout = pingTimeout,
       _yieldTimeout = yieldTimeout;

  /// Takes the name, before the run looks for the app and long before it
  /// touches the database. With nobody under it — every ordinary run — in
  /// the caller's own synchronous turn, which is what the handshake's
  /// "name first, look second" rests on.
  ///
  /// A name that is held is never simply taken: a second run that took it
  /// left the first holding the database under no name, and a launch then
  /// waited only for the newer one (review item 6). The holder is pinged.
  /// One that answers is a live run: it is asked to end and waited for, at
  /// most [kSharedRefreshYieldTimeout]. One that does not is a run killed
  /// with its engine, and its name is removed.
  ///
  /// False when a live run still holds the name after that — this one must
  /// not go on beside it.
  Future<bool> open() async {
    if (_port != null) return true;
    final port = ReceivePort();
    for (var round = 0; round < kSharedRefreshPings; round++) {
      final held = _registry.lookup(kSharedRefreshRunPort);
      if (held != null) {
        // As patient as the question of the app: a run busy for two seconds
        // is not a dead one.
        var alive = false;
        for (var ping = 0; ping < kSharedRefreshPings && !alive; ping++) {
          alive =
              await _ask(held, SharedRefreshWire.ping, _pingTimeout) ==
              SharedRefreshWire.pong;
        }
        if (alive) {
          await _askToGiveWay(
            _registry,
            held,
            _yieldTimeout,
            verb: SharedRefreshWire.giveWayToRun,
          );
          if (_registry.lookup(kSharedRefreshRunPort) == held) break;
        } else if (_registry.lookup(kSharedRefreshRunPort) == held) {
          _registry.remove(kSharedRefreshRunPort);
        }
      }
      // Refused when another run took the name while this one waited: the
      // next round asks that one.
      if (_registry.register(port.sendPort, kSharedRefreshRunPort)) {
        _port = port..listen(_onMessage);
        return true;
      }
    }
    port.close();
    return false;
  }

  /// Whether the app or a later run asked for the database.
  bool get yieldAsked => _yield.isCompleted;

  /// Whether the app is among those that asked — at any moment, before or
  /// after a run did: the app reads the share itself, so a run that gave
  /// way to it owes nothing. Kept past [close].
  bool get yieldAskedByApp => _yieldAskedByApp;
  bool _yieldAskedByApp = false;

  /// Completes when the app or a later run asks for the database.
  Future<void> get yieldRequested => _yield.future;

  /// Asks the app's isolate to do the read. A name nobody answers under
  /// within [kSharedRefreshPingTimeout] is a dead isolate's and is removed.
  /// [limit] bounds the wait for the read itself; [slot] is the one the
  /// work that asks is running in, which the app is told — null for a
  /// message's work, and then nothing is said of a slot. [pair] is the one
  /// a message named, told the same way: the app reads for it only when the
  /// database it holds is in that pair.
  Future<SharedRefreshForward> forward({
    required Duration limit,
    SharedRefreshSlot? slot,
    String? pair,
  }) async {
    // One unanswered ping is a main isolate that stalled for two seconds —
    // a restore, a long frame — and taking that for a dead app put a second
    // writer beside a live one (review item 4). Every round asks whoever
    // holds the name then: a launch may have named a live port since.
    SendPort? app;
    var answered = false;
    for (var ping = 0; ping < kSharedRefreshPings && !answered; ping++) {
      app = _registry.lookup(kSharedRefreshAppPort);
      if (app == null) return SharedRefreshForward.noApp;
      answered =
          await _ask(app, SharedRefreshWire.ping, _pingTimeout) ==
          SharedRefreshWire.pong;
    }
    if (app == null) return SharedRefreshForward.noApp;
    if (!answered) {
      // Only the mapping that went unanswered.
      if (_registry.lookup(kSharedRefreshAppPort) == app) {
        _registry.remove(kSharedRefreshAppPort);
      }
      return SharedRefreshForward.noApp;
    }
    // The app holds the database, or is about to: nothing here will, so a
    // launch waiting on this run is let go before the read is asked for.
    close();
    final answer = await _ask(
      app,
      SharedRefreshWire.read,
      limit,
      word: slot?.workName,
      pair: pair,
    );
    return answer == SharedRefreshWire.done
        ? SharedRefreshForward.done
        : SharedRefreshForward.failed;
  }

  /// Gives the name up and answers every launch that waits: the database is
  /// closed, or was never opened. Safe to call twice.
  void close() {
    final port = _port;
    if (port == null) return;
    _port = null;
    if (_registry.lookup(kSharedRefreshRunPort) == port.sendPort) {
      _registry.remove(kSharedRefreshRunPort);
    }
    for (final reply in _yieldAsked) {
      reply.send(SharedRefreshWire.done);
    }
    _yieldAsked.clear();
    port.close();
  }

  void _onMessage(Object? message) {
    final asked = _parse(message);
    if (asked == null) return;
    switch (asked.verb) {
      // What tells a later run that this one is alive, not a name a killed
      // engine left behind.
      case SharedRefreshWire.ping:
        asked.reply.send(SharedRefreshWire.pong);
      case SharedRefreshWire.giveWay || SharedRefreshWire.giveWayToRun:
        if (asked.verb == SharedRefreshWire.giveWay) _yieldAskedByApp = true;
        _yieldAsked.add(asked.reply);
        if (!_yield.isCompleted) _yield.complete();
    }
  }
}
