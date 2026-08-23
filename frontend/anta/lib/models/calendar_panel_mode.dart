/// What the calendar's bottom panel shows below the month grid.
///
/// Persisted by name through `SettingsService`, so [fromName] falls back to
/// [day] for values written by a newer build rather than throwing.
enum CalendarPanelMode {
  /// Entries for the selected day: events, holiday, weekend, money.
  day,

  /// The selected day drawn as an hour grid with duration-sized blocks.
  timeline,

  /// A look-ahead agenda whose window starts on today — or on the selected
  /// day, once "start from selected day" is switched on; a custom range
  /// overrides both. The filters are panel-owned and persisted, so a mode
  /// switch never loses a search.
  upcoming;

  static CalendarPanelMode fromName(String? name) {
    return CalendarPanelMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => CalendarPanelMode.day,
    );
  }
}
