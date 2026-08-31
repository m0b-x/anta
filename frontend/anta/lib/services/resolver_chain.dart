import '../models/chain_item.dart';

/// Folds a provider chain's contributions into one deduplicated,
/// priority-ordered list.
///
/// The single implementation behind `DayBarsResolver.resolve`,
/// `DayRailResolver.resolve` and `DaySummaryResolver.resolve`. It used to be
/// three byte-identical copies differing only in element type, which meant a
/// fix to the ordering rule had to land in three places or the grid, the rail
/// and the day panel would start disagreeing about the same day — the exact
/// divergence `eventInDayRail` was factored out to prevent on the membership
/// side.
///
/// Two rules, both load-bearing:
///
/// **Dedup by key, first provider wins.** Providers are ordered by
/// specificity, so an event's own contribution beats a contextual one that
/// happens to share its key.
///
/// **Stable sort by priority.** `List.sort` is *not* stable, so ties are
/// broken by insertion index rather than falling through to a key comparison.
/// Providers therefore control the order of their own equal-priority items —
/// events arrive pre-sorted by `EventAgenda.compareWithinDay`, which a key
/// sort on `event:<uuid>` used to scramble into id order.
///
/// [contributions] is iterated exactly once and may be lazy, so callers can
/// pass `providers.map(...)` without materializing an intermediate list on a
/// path that runs for every visible cell.
List<T> resolveChain<T extends ChainItem>(Iterable<Iterable<T>> contributions) {
  final byKey = <String, T>{};
  for (final contribution in contributions) {
    for (final item in contribution) {
      byKey.putIfAbsent(item.key, () => item);
    }
  }
  final items = byKey.values.toList();
  final order = [for (var i = 0; i < items.length; i++) (i, items[i])]
    ..sort((a, b) {
      final byPriority = a.$2.priority.compareTo(b.$2.priority);
      return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
    });
  return [for (final (_, item) in order) item];
}
