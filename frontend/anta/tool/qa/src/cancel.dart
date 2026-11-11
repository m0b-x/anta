import 'dart:async';

import 'errors.dart';

/// What a call made under a cancelled [CancelToken] throws. It is a device
/// failure so every verb's existing handling turns it into one failed step,
/// never the end of the process.
class Cancelled extends DeviceFailure {
  Cancelled(String reason) : super('cancelled: $reason');
}

/// Stops one piece of work at its next device call: a flow attempt the
/// pass abandoned at its ceiling, or the whole flow loop on Ctrl+C. A Dart
/// timeout leaves the work under it running, and a step in flight (a
/// `relaunch --fresh --seed`, a `wait --timeout 210`) would otherwise go on
/// driving the device beside the pass's rerun.
///
/// The token travels in its [Zone] ([run]), so it follows the cancelled
/// work's own async chain and nothing else: the pass's evidence capture,
/// its recovery and the next attempt run outside it. The choke points
/// every verb goes through — the process runner, the VM service calls the
/// agent rides on, [pollUntil] and [pause] — check [current].
class CancelToken {
  /// A token cancelled with [parent] as well as on its own.
  CancelToken({CancelToken? parent}) {
    if (parent != null) {
      parent.onCancel(() => cancel(parent.reason ?? 'cancelled'));
    }
  }

  static final Object _zoneKey = Object();

  /// The token of the work the caller runs in, if any.
  static CancelToken? get current => Zone.current[_zoneKey] as CancelToken?;

  String? _reason;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _reason != null;

  /// Why it was cancelled; null until then.
  String? get reason => _reason;

  /// Cancels once; later calls keep the first reason. Every listener runs,
  /// and none can keep the next from running.
  void cancel(String reason) {
    if (_reason != null) return;
    _reason = reason;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } on Object {
        // A kill that fails is the process timeout's to clean up.
      }
    }
  }

  /// Runs [listener] on [cancel] (at once when already cancelled); the
  /// returned function unregisters it.
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Throws [Cancelled] once cancelled.
  void check() {
    final reason = _reason;
    if (reason != null) throw Cancelled(reason);
  }

  /// Runs [body] with this token as [current] for its whole async chain.
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});
}

/// Throws [Cancelled] when the work the caller runs in was cancelled.
void checkCancelled() => CancelToken.current?.check();

/// [work], unless the caller's work is cancelled first: then [Cancelled]
/// at once, and whatever [work] does later is dropped, its error included.
Future<T> cancellable<T>(Future<T> work) {
  final token = CancelToken.current;
  if (token == null) return work;
  token.check();
  final result = Completer<T>();
  final off = token.onCancel(() {
    if (!result.isCompleted) {
      result.completeError(Cancelled(token.reason ?? 'cancelled'));
    }
  });
  work.then(
    (value) {
      off();
      if (!result.isCompleted) result.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      off();
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future;
}

/// A delay that ends early with [Cancelled] when the caller's work is
/// cancelled: what a verb waits with between polls and settles.
Future<void> pause(Duration duration) =>
    cancellable(Future<void>.delayed(duration));
