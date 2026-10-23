/// A process-wide scope during which sync must not run. The Phase 02 engine
/// checks [isSuspended] before every push, pull and bind, so a backup restore
/// — which unbinds, wipes and re-imports — can never interleave with a drain
/// that would push its half-imported rows or merge a pull into them.
abstract final class SyncSuspension {
  static int _depth = 0;

  static bool get isSuspended => _depth > 0;

  /// Runs [body] suspended. Re-entrant: nested scopes count, and sync resumes
  /// only when the outermost one ends, whether it returns or throws.
  static Future<T> run<T>(Future<T> Function() body) async {
    _depth++;
    try {
      return await body();
    } finally {
      _depth--;
    }
  }
}
