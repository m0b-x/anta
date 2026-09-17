import 'dart:async';

/// Runs [probe] until it returns a non-null value or [timeout] passes,
/// pausing [interval] between attempts; the last attempt happens at the
/// deadline, so a probe that would have succeeded then is not lost.
Future<T?> pollUntil<T>({
  required Duration timeout,
  required Duration interval,
  required FutureOr<T?> Function() probe,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final result = await probe();
    if (result != null) return result;
    if (!DateTime.now().isBefore(deadline)) return null;
    await Future<void>.delayed(interval);
  }
}
