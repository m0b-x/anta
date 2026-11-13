import 'dart:async';

/// An event transformer that runs one handler to its end before the next
/// starts, in the order the events were added — without ever pausing the
/// events.
///
/// Not `events.asyncExpand(mapper)`: `asyncExpand` keeps the bloc's event
/// subscription paused while a handler runs, and `Bloc.close()` first waits
/// for its event stream's done event to reach every listener — a paused one
/// receives nothing until it resumes. A close during a handler that awaits
/// a slow write therefore waited for that write, and forever for one that
/// never answers; the events queued behind it ran before the close
/// returned, into a bloc already on its way out.
///
/// Here the events are taken as they arrive and chained on a future. A
/// close completes at once: the running handler is never cancelled — it
/// ends on its own, its later emits dropped by the bloc — and the events
/// that have not started yet never run. A bloc that must not lose such an
/// event hands it over in its own `close` (`ShareBloc`'s queued Undo).
Stream<E> oneAtATime<E>(Stream<E> events, Stream<E> Function(E) mapper) {
  StreamSubscription<E>? source;
  var tail = Future<void>.value();
  var cancelled = false;
  late final StreamController<E> out;
  out = StreamController<E>(
    onListen: () => source = events.listen(
      (event) => tail = tail.then(
        (_) => cancelled ? null : mapper(event).drain<void>(),
      ),
      onError: out.addError,
      onDone: () => tail.whenComplete(out.close),
    ),
    onCancel: () {
      cancelled = true;
      return source?.cancel();
    },
  );
  return out.stream;
}
