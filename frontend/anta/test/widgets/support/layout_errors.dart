import 'package:flutter/foundation.dart';

/// Runs [body] and returns every error the framework reported meanwhile,
/// details included.
///
/// A layout overflow is reported to `FlutterError.onError` by the renderer,
/// and the test binding keeps only the exception for `takeException` — the
/// summary line, with no word on *which* widget overflowed. The details
/// carry the creator chain, so a suite that pins a known overflow can say
/// where it is and prove nothing else errs. The binding's handler is put
/// back whatever [body] does, so the errors captured here never reach the
/// end-of-test check.
Future<List<FlutterErrorDetails>> layoutErrorsDuring(
  Future<void> Function() body,
) async {
  final previous = FlutterError.onError;
  final captured = <FlutterErrorDetails>[];
  FlutterError.onError = captured.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return captured;
}
