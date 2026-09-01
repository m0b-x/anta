import 'package:equatable/equatable.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/calendar_event.dart';
import '../../models/calendar_grid_filters.dart';
import '../../models/calendar_selection_source.dart';

sealed class CalendarPageEvent extends Equatable {
  const CalendarPageEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCalendarEvents extends CalendarPageEvent {
  const LoadCalendarEvents();
}

final class SelectCalendarDay extends CalendarPageEvent {
  final DateTime day;
  final DateTime focusedDay;

  /// Which surface moved the selection. Required so a new dispatch site has to
  /// say, rather than silently inheriting a default that would make the agenda
  /// re-anchor on its own rows again.
  final CalendarSelectionSource source;

  const SelectCalendarDay({
    required this.day,
    required this.focusedDay,
    required this.source,
  });

  @override
  List<Object?> get props => [day, focusedDay, source];
}

final class ChangeFocusedDay extends CalendarPageEvent {
  final DateTime focusedDay;

  const ChangeFocusedDay({required this.focusedDay});

  @override
  List<Object?> get props => [focusedDay];
}

final class ChangeCalendarFormat extends CalendarPageEvent {
  final CalendarFormat format;

  const ChangeCalendarFormat({required this.format});

  @override
  List<Object?> get props => [format];
}

final class ChangeCalendarFilters extends CalendarPageEvent {
  final CalendarGridFilters filters;

  const ChangeCalendarFilters({required this.filters});

  @override
  List<Object?> get props => [filters];
}

final class CreateCalendarEvent extends CalendarPageEvent {
  final CalendarEvent event;

  const CreateCalendarEvent({required this.event});

  @override
  List<Object?> get props => [event];
}

final class UpdateCalendarEvent extends CalendarPageEvent {
  final CalendarEvent event;

  const UpdateCalendarEvent({required this.event});

  @override
  List<Object?> get props => [event];
}

final class DeleteCalendarEvent extends CalendarPageEvent {
  final String eventId;

  const DeleteCalendarEvent({required this.eventId});

  @override
  List<Object?> get props => [eventId];
}

/// Writes one occurrence's description override (**v24**).
///
/// An empty [description] is meaningful — it blanks that day rather than
/// falling back to the event's template. Use [ClearOccurrenceDescription] to
/// return the day to the template.
final class SetOccurrenceDescription extends CalendarPageEvent {
  final String eventId;
  final DateTime day;
  final String description;

  const SetOccurrenceDescription({
    required this.eventId,
    required this.day,
    required this.description,
  });

  @override
  List<Object?> get props => [eventId, day, description];
}

/// Deletes one occurrence's override, returning that day to the event's
/// template. Distinct from writing an empty string.
final class ClearOccurrenceDescription extends CalendarPageEvent {
  final String eventId;
  final DateTime day;

  const ClearOccurrenceDescription({required this.eventId, required this.day});

  @override
  List<Object?> get props => [eventId, day];
}

/// Marks one occurrence as missed (**v26**).
///
/// Records an exception to implicit attendance; the occurrence still occurs,
/// still numbers into count labels and still exports. Marking an already
/// missed day is a no-op.
final class SetOccurrenceMissed extends CalendarPageEvent {
  final String eventId;
  final DateTime day;

  const SetOccurrenceMissed({required this.eventId, required this.day});

  @override
  List<Object?> get props => [eventId, day];
}

/// Returns one occurrence to present, tombstoning its absence row. Un-marking
/// a day that was never marked is a no-op.
final class ClearOccurrenceMissed extends CalendarPageEvent {
  final String eventId;
  final DateTime day;

  const ClearOccurrenceMissed({required this.eventId, required this.day});

  @override
  List<Object?> get props => [eventId, day];
}

/// Cancels one occurrence of a recurring event (**v30**).
///
/// Unlike [SetOccurrenceMissed], this changes **membership**: the occurrence
/// stops existing on every surface, including `.ics` export. A one-time event
/// cannot be skipped — deleting it is the equivalent — and cancelling an
/// already-cancelled day is a no-op.
final class SetOccurrenceSkipped extends CalendarPageEvent {
  final String eventId;
  final DateTime day;

  const SetOccurrenceSkipped({required this.eventId, required this.day});

  @override
  List<Object?> get props => [eventId, day];
}

/// Restores one cancelled occurrence, tombstoning its skip row. Restoring a
/// day that was never cancelled is a no-op.
final class ClearOccurrenceSkipped extends CalendarPageEvent {
  final String eventId;
  final DateTime day;

  const ClearOccurrenceSkipped({required this.eventId, required this.day});

  @override
  List<Object?> get props => [eventId, day];
}
