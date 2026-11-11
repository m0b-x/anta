import 'dart:async';

/// A fake sleep for a loop the test drives on a fake clock: [advance] moves
/// the clock, and past [polls] sleeps the sleep throws. A fake sleep yields
/// only to microtasks, so a loop a bug keeps from ending would starve the
/// test's own timeout timer and hang `flutter test` for good; the ceiling
/// turns that hang into a failure that names the [loop].
Future<void> Function(Duration) boundedSleep(
  String loop,
  FutureOr<void> Function(Duration) advance, {
  int polls = 100,
}) {
  var slept = 0;
  return (d) async {
    if (++slept > polls) {
      throw StateError(
        '$loop did not end after $polls sleeps on the fake clock',
      );
    }
    await advance(d);
  };
}
