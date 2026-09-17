import 'package:equatable/equatable.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../constants/event_presence.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_grid_filters.dart';
import '../../models/calendar_selection_source.dart';
import '../../models/event_alert.dart';

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

  /// The event's complete alert set (**v40**), or `null` to leave the alert
  /// table alone — the [SetOccurrenceSkipped] rule, for the same reason: a
  /// dispatch site that never showed alerts must not be read as one that
  /// removed them.
  final List<EventAlert>? alerts;

  const CreateCalendarEvent({required this.event, this.alerts});

  @override
  List<Object?> get props => [event, alerts];
}

final class UpdateCalendarEvent extends CalendarPageEvent {
  final CalendarEvent event;

  /// See [CreateCalendarEvent.alerts]. `null` is "untouched", an empty list is
  /// "this event has no alerts any more".
  final List<EventAlert>? alerts;

  const UpdateCalendarEvent({required this.event, this.alerts});

  @override
  List<Object?> get props => [event, alerts];
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

/// Records an explicit presence [status] for one occurrence (**v26**,
/// statuses since **v37**).
///
/// Both directions write a row: since an event can default to absent, a
/// `present` mark is a statement of its own and not the removal of one. The
/// occurrence still occurs either way, still numbers into count labels and
/// still exports. Re-recording the status a day already carries is a no-op.
///
/// Replaces v26's `SetOccurrenceMissed` / `ClearOccurrenceMissed` pair —
/// keeping "Clear" would have named a write that now inserts a row. Dropping
/// a mark back to the event's own default is `EventPresenceService.clearMark`,
/// which only the skip path calls.
final class SetOccurrencePresence extends CalendarPageEvent {
  final String eventId;
  final DateTime day;
  final PresenceStatus status;

  const SetOccurrencePresence({
    required this.eventId,
    required this.day,
    required this.status,
  });

  @override
  List<Object?> get props => [eventId, day, status];
}

/// Cancels one occurrence of a recurring event (**v30**).
///
/// Unlike [SetOccurrencePresence], this changes **membership**: the occurrence
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

/// Flips one alert's `enabled` flag from the Alerts hub (**v40**, §5.6).
///
/// Disabling keeps the row and registers nothing; enabling re-arms it. The
/// alert's own settings are never touched, which is the difference between
/// this and removing it in the editor. Setting the value an alert already has
/// is a no-op.
final class ToggleEventAlert extends CalendarPageEvent {
  final String eventId;
  final String alertId;
  final bool enabled;

  const ToggleEventAlert({
    required this.eventId,
    required this.alertId,
    required this.enabled,
  });

  @override
  List<Object?> get props => [eventId, alertId, enabled];
}
