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

  /// Asks a run without the app to close the database; answered [done].
  static const String giveWay = 'yield';
  static const String done = 'done';
  static const String failed = 'failed';
}

/// One question to [port], and its answer — null when none came within
/// [timeout].
Future<String?> _ask(
  SendPort port,
  String verb,
  Duration timeout, {
  String? word,
}) async {
  final reply = ReceivePort();
  try {
    port.send([verb, reply.sendPort, ?word]);
    final answer = await reply.first.timeout(timeout, onTimeout: () => null);
    return answer is String ? answer : null;
  } finally {
    reply.close();
  }
}

({String verb, SendPort reply, String? word})? _parse(Object? message) {
  return switch (message) {
    [final String verb, final SendPort reply] => (
      verb: verb,
      reply: reply,
      word: null,
    ),
    [final String verb, final SendPort reply, final String word] => (
      verb: verb,
      reply: reply,
      word: word,
    ),
    _ => null,
  };
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
  final Future<void> Function(SharedRefreshSlot? slot) _read;
  final Duration _yieldTimeout;
  ReceivePort? _port;

  /// [read] runs the shared read on the app's own engine and completes
  /// when it has ended — once the launch has brought the app up, which it
  /// waits for itself. It is handed the slot of the work that asks: that
  /// work is running, and must not be replaced by what the read plans.
  /// Null when the asker names none — a message's work, which stands in
  /// neither slot.
  SharedRefreshAppPort({
    required Future<void> Function(SharedRefreshSlot? slot) read,
    PortRegistry registry = const IsolateNamePortRegistry(),
    Duration yieldTimeout = kSharedRefreshYieldTimeout,
  }) : _read = read,
       _registry = registry,
       _yieldTimeout = yieldTimeout;

  /// Takes the name, over one a dead isolate of this process left.
  /// Synchronous. Again after a trigger took the name for stale: the port
  /// is kept and only named anew.
  void open() {
    final port = _port ??= ReceivePort()..listen(_onMessage);
    if (_registry.lookup(kSharedRefreshAppPort) == port.sendPort) return;
    _registry.remove(kSharedRefreshAppPort);
    _registry.register(port.sendPort, kSharedRefreshAppPort);
  }

  /// Asks a run in flight to close the database and waits for it, at most
  /// [kSharedRefreshYieldTimeout]. Null, and so nothing to await, when no
  /// run holds the name — every ordinary launch.
  Future<void>? yieldRunInFlight() {
    final run = _registry.lookup(kSharedRefreshRunPort);
    if (run == null) return null;
    return _awaitYield(run);
  }

  /// The wait ends with the run's answer — or the moment its name is gone,
  /// looked for every [kSharedRefreshYieldPoll]: a run gives its name up
  /// once it has closed the database, and one that did so a moment before
  /// the question reached it will never answer.
  Future<void> _awaitYield(SendPort run) async {
    final reply = ReceivePort();
    final gone = Completer<void>();
    void end() {
      if (!gone.isCompleted) gone.complete();
    }

    final answers = reply.listen((_) => end());
    final poll = Timer.periodic(kSharedRefreshYieldPoll, (_) {
      if (_registry.lookup(kSharedRefreshRunPort) == null) end();
    });
    final limit = Timer(_yieldTimeout, end);
    try {
      run.send([SharedRefreshWire.giveWay, reply.sendPort]);
      await gone.future;
    } finally {
      poll.cancel();
      limit.cancel();
      await answers.cancel();
      reply.close();
    }
  }

  void close() {
    final port = _port;
    if (port == null) return;
    _port = null;
    if (_registry.lookup(kSharedRefreshAppPort) == port.sendPort) {
      _registry.remove(kSharedRefreshAppPort);
    }
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
        unawaited(
          _read(word == null ? null : SharedRefreshSlot.ofTask(word)).then<void>(
            (_) => asked.reply.send(SharedRefreshWire.done),
            onError: (Object error, StackTrace stack) {
              debugPrint('[SharedRefresh] forwarded read failed: $error');
              asked.reply.send(SharedRefreshWire.failed);
            },
          ),
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

  SharedRefreshRunPort({
    PortRegistry registry = const IsolateNamePortRegistry(),
    Duration pingTimeout = kSharedRefreshPingTimeout,
  }) : _registry = registry,
       _pingTimeout = pingTimeout;

  /// Takes the name, before the run looks for the app and long before it
  /// touches the database. Over a stale one: a run that was killed with its
  /// engine left its name behind.
  void open() {
    if (_port != null) return;
    final port = _port = ReceivePort()..listen(_onMessage);
    _registry.remove(kSharedRefreshRunPort);
    _registry.register(port.sendPort, kSharedRefreshRunPort);
  }

  /// Whether a launch asked for the database.
  bool get yieldAsked => _yield.isCompleted;

  /// Completes when a launch asks for the database.
  Future<void> get yieldRequested => _yield.future;

  /// Asks the app's isolate to do the read. A name nobody answers under
  /// within [kSharedRefreshPingTimeout] is a dead isolate's and is removed.
  /// [limit] bounds the wait for the read itself; [slot] is the one the
  /// work that asks is running in, which the app is told — null for a
  /// message's work, and then nothing is said of a slot.
  Future<SharedRefreshForward> forward({
    required Duration limit,
    SharedRefreshSlot? slot,
  }) async {
    final app = _registry.lookup(kSharedRefreshAppPort);
    if (app == null) return SharedRefreshForward.noApp;
    final pong = await _ask(app, SharedRefreshWire.ping, _pingTimeout);
    if (pong != SharedRefreshWire.pong) {
      // Only the mapping that went unanswered: a launch may have named a
      // live port since.
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
    if (asked == null || asked.verb != SharedRefreshWire.giveWay) return;
    _yieldAsked.add(asked.reply);
    if (!_yield.isCompleted) _yield.complete();
  }
}
