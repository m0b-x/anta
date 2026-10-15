import '../models/event_digest.dart';

/// Synchronous, in-memory facade over the live rows of `event_digests`
/// (**v42**), published by `EventDigestService`.
///
/// The `EventAlerts` shape: read while rows are being built (the Alerts hub
/// lists digests under `CalendarPageLoaded`), so reads are O(1) and an
/// unconfigured read is silent — a surface that reads this must live under the
/// calendar's load or await the owning service itself.
abstract final class EventDigests {
  static List<EventDigest> _all = const [];
  static Map<String, EventDigest> _byId = const {};
  static int _revision = 0;

  /// Every live digest in display order. Unmodifiable.
  static List<EventDigest> get all => _all;

  /// Bumped on every republish, so a page that lists digests can rebuild on it.
  static int get revision => _revision;

  /// The digest with [id], or `null`.
  static EventDigest? byId(String id) => _byId[id];

  /// Replaces the cache wholesale. [digests] must already be unmodifiable —
  /// [all] hands it straight out.
  static void updateCache(List<EventDigest> digests) {
    _all = digests;
    _byId = {for (final digest in digests) digest.id: digest};
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: a
  /// digest leaked from a closed database would arm against the newly opened
  /// one's events.
  static void resetCache() {
    _all = const [];
    _byId = const {};
    _revision++;
  }
}
