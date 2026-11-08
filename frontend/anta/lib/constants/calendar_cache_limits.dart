/// Bounds on the calendar's in-memory memos that grow with where the user
/// looks rather than with what the store holds.
abstract final class CalendarCacheLimits {
  /// The most days each of `CalendarBloc`'s two per-day memos holds.
  ///
  /// A date picker or the day panel can ask for any day of 1900–2100 with no
  /// focus change, so a memo trimmed only on a month change would grow by a
  /// page of days per picker month. Past this count the oldest day outside
  /// the grid's seven-month window goes first; the window's own days (215 at
  /// most, July to January) are never evicted by the cap, so a frame never
  /// loses the cell it is painting, and a picker grid's 42 newest days
  /// outlive their frame.
  static const int maxDayCacheEntries = 512;

  /// The most event ids one pull may patch into `CalendarEventService`'s
  /// cache by key; past it the whole store is read again.
  ///
  /// The keyed read binds one parameter per id and the patch walks the cache
  /// once either way, so a pull this large — a first download, a restore on
  /// another device — gains little from the keyed path, and a statement this
  /// size stays under SQLite's older 999-variable ceiling.
  static const int maxKeyedPatchIds = 500;
}
