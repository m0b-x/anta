/// One provider's contribution to a calendar day, whatever the surface
/// renders it as.
///
/// The calendar composes three of these chains for the same day — the grid's
/// bottom bars, the cell's left rail, and the day panel's summary rows — and
/// all three answer the same two structural questions: what identifies this
/// contribution across providers ([key]), and how does it rank against the
/// others ([priority]). Everything else about the three models differs.
///
/// Named so `resolveChain` can dedup and order any of them without three
/// copies of the algorithm. Lower [priority] wins in every chain.
abstract interface class ChainItem {
  /// Stable identifier used for deduplication across providers, e.g.
  /// `"weekend"`, `"holiday"`, `"event:<uuid>"`. The first provider to claim
  /// a key wins it.
  String get key;

  /// Lower sorts first. Ties keep provider order, never key order — see
  /// `resolveChain`.
  int get priority;
}
