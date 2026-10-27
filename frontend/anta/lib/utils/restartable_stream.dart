import 'dart:async';

/// [source]'s events, resubscribed from scratch on every event of [restarts].
///
/// A repository watch binds its DAO — and through it the database handle —
/// at subscription time, so a page mounted before a database switch would go
/// on streaming from the closed one: `rebindDatabase` re-points the handle
/// and drops the caches, but cannot re-point a live subscription (R114).
/// Firing [restarts] from the rebind brings the watch back over the new
/// database without the page knowing a switch happened.
///
/// The source completing does **not** complete this stream: the watches it
/// wraps run for as long as their listener does, and a database closing
/// behind a switch ends its streams — exactly the moment a restart is on its
/// way. Only cancelling ends it.
///
/// Broadcast, like the drift watch underneath: a repository stream is listened
/// to by every page showing the folder, and a single-subscription wrapper
/// would make the second one throw where it never did (A7 review R140). The
/// source is subscribed to while anyone is listening and dropped when the
/// last listener leaves, which is drift's own behaviour.
Stream<T> restartableStream<T>({
  required Stream<T> Function() source,
  required Stream<void> restarts,
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? inner;
  StreamSubscription<void>? trigger;

  void subscribe() {
    inner = source().listen(controller.add, onError: controller.addError);
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      subscribe();
      trigger = restarts.listen((_) async {
        final previous = inner;
        subscribe();
        await previous?.cancel();
      });
    },
    onCancel: () async {
      await trigger?.cancel();
      trigger = null;
      await inner?.cancel();
      inner = null;
    },
  );
  return controller.stream;
}
