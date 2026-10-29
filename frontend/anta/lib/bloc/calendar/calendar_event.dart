import 'package:equatable/equatable.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../constants/event_presence.dart';
import '../../models/calendar_event.dart';
import '../../models/calendar_grid_filters.dart';
import '../../models/calendar_selection_source.dart';
import '../../models/event_alert.dart';
import '../../models/event_digest.dart';
import '../../services/alert_removal_notice.dart';

sealed class CalendarPageEvent extends Equatable {
  const CalendarPageEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCalendarEvents extends CalendarPageEvent {
  const LoadCalendarEvents();
}

/// The event store changed behind the bloc — a restore, or rows a pull
/// merged. Fed from `CalendarEventService.externalChanges`; reloads in place
/// while the calendar is loaded.
final class ExternalCalendarChange extends CalendarPageEvent {
  const ExternalCalendarChange();
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

  /// The alert ids the dispatch site was looking at when it built [alerts], so
  /// the write tombstones only those — see
  /// `EventAlertService.replaceForEvent`. `null` is "the whole set as it
  /// stands", which is what a create means: there is nothing there yet.
  final Set<String>? knownAlertIds;

  const CreateCalendarEvent({
    required this.event,
    this.alerts,
    this.knownAlertIds,
  });

  @override
  List<Object?> get props => [event, alerts, knownAlertIds];
}

final class UpdateCalendarEvent extends CalendarPageEvent {
  final CalendarEvent event;

  /// See [CreateCalendarEvent.alerts]. `null` is "untouched", an empty list is
  /// "this event has no alerts any more".
  final List<EventAlert>? alerts;

  /// See [CreateCalendarEvent.knownAlertIds]. The editor seeds it in
  /// `initState`, so an alert a sync pull added while the form was open
  /// survives a Save that never showed it.
  final Set<String>? knownAlertIds;

  const UpdateCalendarEvent({
    required this.event,
    this.alerts,
    this.knownAlertIds,
  });

  @override
  List<Object?> get props => [event, alerts, knownAlertIds];
}

/// A3's Undo: the event an acknowledged alarm deleted, put back with the four
/// child row sets the cascade took with it, under one HLC.
///
/// Its own event rather than a [CreateCalendarEvent] with more fields: a
/// create means "there is nothing there yet", while this writes over four
/// tables of tombstones and is the one dispatch that does.
final class RestoreRemovedEvent extends CalendarPageEvent {
  /// The notice the removal published, taken by the page that offers Undo.
  final RemovedEventNotice notice;

  const RestoreRemovedEvent({required this.notice});

  @override
  List<Object?> get props => [notice];
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

/// Makes [days] the event's whole set of cancelled occurrences — what the
/// editor's Skipped days picker left behind, as one event.
///
/// Its own event rather than one [SetOccurrenceSkipped] or
/// [ClearOccurrenceSkipped] per changed day, because a term's worth of days
/// cost a transaction, an HLC, a day-cache rescan, an alert reconcile and a
/// state emit each. The two single-day events stay for the surfaces that
/// really do cancel one day — the day panel and the alert notice's undo.
final class SetOccurrenceSkips extends CalendarPageEvent {
  final String eventId;
  final Set<DateTime> days;

  const SetOccurrenceSkips({required this.eventId, required this.days});

  @override
  List<Object?> get props => [eventId, days];
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

/// A category's alerts were saved by the category editor (**v42**), which
/// writes them itself through `EventAlertService.replaceForCategory`.
///
/// Carries nothing: the write has already landed and the scheduler already
/// re-plans. What is left is the calendar's row badges and the Alerts hub,
/// which read the facade inside memoized rows and re-read on a revision.
final class CategoryAlertsChanged extends CalendarPageEvent {
  const CategoryAlertsChanged();
}

/// Saves a digest from the digest sheet (**v42**): a create when its id is
/// empty — the service mints the id and the position — else an update in
/// place, skipped when it equals the stored digest. A create past
/// `kDigestHorizon.maxDigests` is refused and changes nothing.
final class SaveEventDigest extends CalendarPageEvent {
  final EventDigest digest;

  const SaveEventDigest(this.digest);

  @override
  List<Object?> get props => [digest];
}

/// Deletes a digest (a tombstone) after the sheet's confirmation.
final class DeleteEventDigest extends CalendarPageEvent {
  final String id;

  const DeleteEventDigest(this.id);

  @override
  List<Object?> get props => [id];
}

/// The hub switch on a digest's row: kept either way, armed only while on.
/// Setting the value a digest already has is a no-op.
final class ToggleEventDigest extends CalendarPageEvent {
  final String id;
  final bool enabled;

  const ToggleEventDigest(this.id, {required this.enabled});

  @override
  List<Object?> get props => [id, enabled];
}
