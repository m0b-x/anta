import 'package:equatable/equatable.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/calendar_event.dart';

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

  const SelectCalendarDay({required this.day, required this.focusedDay});

  @override
  List<Object?> get props => [day, focusedDay];
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

final class ChangeHiddenCategories extends CalendarPageEvent {
  final Set<String> hiddenCategoryIds;

  const ChangeHiddenCategories({required this.hiddenCategoryIds});

  @override
  List<Object?> get props => [hiddenCategoryIds];
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
