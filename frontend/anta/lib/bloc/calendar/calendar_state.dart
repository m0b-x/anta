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

  const CalendarPageLoaded({
    required this.allEvents,
    required this.focusedDay,
    required this.selectedDay,
    this.format = CalendarFormat.month,
    this.hiddenCategoryIds = const {},
    this.occurrenceRevision = 0,
    this.membershipRevision = 0,
  });

  CalendarPageLoaded copyWith({
    List<CalendarEvent>? allEvents,
    DateTime? focusedDay,
    DateTime? selectedDay,
    CalendarFormat? format,
    Set<String>? hiddenCategoryIds,
    int? occurrenceRevision,
    int? membershipRevision,
  }) {
    return CalendarPageLoaded(
      allEvents: allEvents ?? this.allEvents,
      focusedDay: focusedDay ?? this.focusedDay,
      selectedDay: selectedDay ?? this.selectedDay,
      format: format ?? this.format,
      hiddenCategoryIds: hiddenCategoryIds ?? this.hiddenCategoryIds,
      occurrenceRevision: occurrenceRevision ?? this.occurrenceRevision,
      membershipRevision: membershipRevision ?? this.membershipRevision,
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
  ];
}

final class CalendarPageError extends CalendarPageState {
  final String message;

  const CalendarPageError(this.message);

  @override
  List<Object?> get props => [message];
}
