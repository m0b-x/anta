import 'package:equatable/equatable.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/calendar_event.dart';

sealed class CalendarPageState extends Equatable {
  const CalendarPageState();

  @override
  List<Object?> get props => [];
}

final class CalendarPageInitial extends CalendarPageState {
  const CalendarPageInitial();
}

final class CalendarPageLoading extends CalendarPageState {
  const CalendarPageLoading();
}

final class CalendarPageLoaded extends CalendarPageState {
  final List<CalendarEvent> allEvents;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat format;

  /// Ids of categories the user has hidden from the calendar. Empty means
  /// "show everything". Stored as a hidden set (rather than a visible set) so
  /// newly created categories are visible by default and deleting a category
  /// leaves at most a harmless stale id behind.
  final Set<String> hiddenCategoryIds;

  /// Bumped whenever per-occurrence overlay data — a description (v24) or a
  /// presence mark (v26) — is written or cleared.
  ///
  /// Editing one day's text or marking it missed changes neither the event list
  /// nor which days an event occurs on, so without this the state would compare
  /// equal to its predecessor and bloc would drop the emit — and the agenda's
  /// identity-based row memo would keep serving rows built from the old
  /// overlay. Threaded down to `AgendaListView` as part of its cache key.
  final int occurrenceRevision;

  /// Bumped whenever an occurrence is cancelled or restored (**v30**).
  ///
  /// Deliberately **not** [occurrenceRevision]. That revision contractually
  /// means "the overlay changed, do not rescan" — `UpcomingAgendaView` forwards
  /// it into its row memo but never re-runs its agenda scan on it. A skip is
  /// the opposite: the set of occurrences itself changed, so every scan must
  /// re-run. Routing both through one counter would either make every checkbox
  /// tick rescan the agenda or leave a cancelled day listed in it.
  ///
  /// Also load-bearing for the emit itself: after a skip `allEvents` is
  /// value-equal, so without a bump `Equatable` drops the state and the grid
  /// keeps drawing an occurrence that no longer exists.
  final int membershipRevision;

  /// Bumped whenever a presence mark is written or cleared (**v26**), in
  /// addition to [occurrenceRevision].
  ///
  /// Presence is the one overlay the **grid** reads: `DayBarsResolver` and
  /// `CellTintResolver` both consult `EventPresence.isMissed`, so a missed
  /// mark changes what a day cell paints. Descriptions do not — no grid
  /// surface reads `OccurrenceDescriptions`. Splitting presence out is what
  /// lets the grid skip a rebuild on a description tick while still
  /// repainting on a presence tick; without it the grid would either rebuild
  /// on every keystroke in the day panel or draw a stale missed marker.
  ///
  /// Additive on purpose: `occurrenceRevision` still bumps for presence too,
  /// so every existing consumer keeps its current semantics.
  final int presenceRevision;

  const CalendarPageLoaded({
    required this.allEvents,
    required this.focusedDay,
    required this.selectedDay,
    this.format = CalendarFormat.month,
    this.hiddenCategoryIds = const {},
    this.occurrenceRevision = 0,
    this.membershipRevision = 0,
    this.presenceRevision = 0,
  });

  /// True when nothing the calendar grid renders from has changed.
  ///
  /// Drives the grid's `buildWhen`. Deliberately every prop **except**
  /// [occurrenceRevision] — see [presenceRevision] for why presence cannot be
  /// lumped in with it. Compares the two collections by identity rather than
  /// by value: every handler that changes either builds a fresh instance, so
  /// this can over-rebuild but never under-rebuild, and a day tap does not
  /// deep-compare N events.
  bool sameGridInputs(CalendarPageLoaded other) =>
      identical(allEvents, other.allEvents) &&
      focusedDay == other.focusedDay &&
      selectedDay == other.selectedDay &&
      format == other.format &&
      identical(hiddenCategoryIds, other.hiddenCategoryIds) &&
      membershipRevision == other.membershipRevision &&
      presenceRevision == other.presenceRevision;

  CalendarPageLoaded copyWith({
    List<CalendarEvent>? allEvents,
    DateTime? focusedDay,
    DateTime? selectedDay,
    CalendarFormat? format,
    Set<String>? hiddenCategoryIds,
    int? occurrenceRevision,
    int? membershipRevision,
    int? presenceRevision,
  }) {
    return CalendarPageLoaded(
      allEvents: allEvents ?? this.allEvents,
      focusedDay: focusedDay ?? this.focusedDay,
      selectedDay: selectedDay ?? this.selectedDay,
      format: format ?? this.format,
      hiddenCategoryIds: hiddenCategoryIds ?? this.hiddenCategoryIds,
      occurrenceRevision: occurrenceRevision ?? this.occurrenceRevision,
      membershipRevision: membershipRevision ?? this.membershipRevision,
      presenceRevision: presenceRevision ?? this.presenceRevision,
    );
  }

  @override
  List<Object?> get props => [
    allEvents,
    focusedDay,
    selectedDay,
    format,
    hiddenCategoryIds,
    occurrenceRevision,
    membershipRevision,
    presenceRevision,
  ];
}

final class CalendarPageError extends CalendarPageState {
  final String message;

  const CalendarPageError(this.message);

  @override
  List<Object?> get props => [message];
}
