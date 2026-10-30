import '../models/calendar_event.dart';

/// Ordering of two events falling on the same day: higher priority first —
/// P1 before P5, so **ascending** on the stored number (matching the
/// day-cell bar stack) — then all-day before timed, then by start time,
/// then by title so the order is stable across rebuilds.
///
/// The **single comparator** for same-day event order — the agenda sorts
/// occurrences with it and `EventSummaryProvider` emits day-panel entries
/// through it, so the two surfaces cannot disagree. It lives in a file of its
/// own so a pure fold (the calendar report) can order a day without pulling
/// the agenda's whole import graph in.
int compareEventsWithinDay(CalendarEvent a, CalendarEvent b) {
  final byPriority = a.priority.compareTo(b.priority);
  if (byPriority != 0) return byPriority;
  final aTime = a.time;
  final bTime = b.time;
  if (aTime == null && bTime != null) return -1;
  if (aTime != null && bTime == null) return 1;
  if (aTime != null && bTime != null) {
    final byStart = aTime.startMinute.compareTo(bTime.startMinute);
    if (byStart != 0) return byStart;
  }
  final byTitle = a.titleFold.compareTo(b.titleFold);
  return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
}
