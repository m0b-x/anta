/// How long the Sharing page's bind and stop steps may wait on one thing.
/// A step holds the page until it settles — a service call cannot be
/// cancelled, so there is no overall limit (reviews RC1, RC1b) — and each
/// wait the bloc owns is bounded instead (final review U-3).
abstract final class SyncLimits {
  /// Each of a step's waits on the engine — resolving it, its stop before a
  /// binding changes, its start after — and a sign-out: past it the bloc
  /// goes on, and the puller's per-page binding check keeps a run that is
  /// still finishing from writing into the new binding.
  static const Duration engineStop = Duration(seconds: 15);

  /// How long a Stop syncing tap waits for the first read of what this
  /// database shares, so its confirmation can say what the partner keeps
  /// (D25): past it the dialog opens without that sentence rather than
  /// leave the tap unanswered.
  static const Duration stopConfirmShareRead = Duration(milliseconds: 1500);
}
