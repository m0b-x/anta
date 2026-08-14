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

  /// Bumped whenever a per-occurrence description is written or cleared.
  ///
  /// Editing one day's text changes neither the event list nor which days an
  /// event occurs on, so without this the state would compare equal to its
  /// predecessor and bloc would drop the emit — and the agenda's identity-based
  /// row memo would keep serving rows built from the old text. Threaded down to
  /// `AgendaListView` as part of its cache key.
  final int occurrenceRevision;

  const CalendarPageLoaded({
    required this.allEvents,
    required this.focusedDay,
    required this.selectedDay,
    this.format = CalendarFormat.month,
    this.hiddenCategoryIds = const {},
    this.occurrenceRevision = 0,
  });

  CalendarPageLoaded copyWith({
    List<CalendarEvent>? allEvents,
    DateTime? focusedDay,
    DateTime? selectedDay,
    CalendarFormat? format,
    Set<String>? hiddenCategoryIds,
    int? occurrenceRevision,
  }) {
    return CalendarPageLoaded(
      allEvents: allEvents ?? this.allEvents,
      focusedDay: focusedDay ?? this.focusedDay,
      selectedDay: selectedDay ?? this.selectedDay,
      format: format ?? this.format,
      hiddenCategoryIds: hiddenCategoryIds ?? this.hiddenCategoryIds,
      occurrenceRevision: occurrenceRevision ?? this.occurrenceRevision,
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
  ];
}

final class CalendarPageError extends CalendarPageState {
  final String message;

  const CalendarPageError(this.message);

  @override
  List<Object?> get props => [message];
}
