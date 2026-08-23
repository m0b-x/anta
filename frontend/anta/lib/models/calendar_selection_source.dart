/// What moved the calendar's selected day.
///
/// The selection is shared by the grid, the day panel and the upcoming
/// agenda's anchor, but they do not all want to follow it: re-anchoring the
/// look-ahead window from a tap on a row *inside that window* truncates the
/// list the user is reading. Tagging the dispatch is what lets the agenda
/// honour a [grid] or [navigation] selection and ignore its own [agendaRow]
/// one, without a second selection state.
enum CalendarSelectionSource {
  /// A day cell in the month grid.
  grid,

  /// A row in the upcoming agenda. Moves the selection (so the grid and the
  /// day panel follow) but never the agenda's own window.
  agendaRow,

  /// Programmatic: the initial load, "today", the month/year picker.
  navigation,
}
