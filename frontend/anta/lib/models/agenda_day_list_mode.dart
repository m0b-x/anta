enum AgendaDayListMode {
  list,
  month,
  year;

  static AgendaDayListMode fromName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return list;
  }
}

/// Which months the drill-down's year overview tiles stand for.
///
/// Session-only, and deliberately without a `fromName`: a sheet always opens on
/// [upcoming], because the number the user tapped on the card is the window's
/// and the first thing they see must be that same number. Only the *mode*
/// above is persisted.
enum AgendaDayListYearScope { upcoming, thisYear }
