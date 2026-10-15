import 'package:equatable/equatable.dart';

import 'calendar_event.dart';
import 'event_alert.dart';
import 'event_digest.dart';

/// One row of the Alerts hub: one alert, on one occurrence, at the instant the
/// phone will next speak up for it.
///
/// An **enabled** alert's entry is a registration the registry believes is
/// armed; a **disabled** alert's entry is what the planner says it *would* do,
/// so the switch that turned it off is still there to turn it back on. A
/// snoozed entry carries both instants — [fireAt] is the snoozed one, because
/// that is when it rings, and [originalFireAt] is what it was set for.
class AlertHubEntry extends Equatable {
  final CalendarEvent event;
  final EventAlert alert;

  /// Occurrence day, date-only UTC.
  final DateTime day;

  /// Local instant the alert next fires at.
  final DateTime fireAt;

  /// The planned instant a snooze was taken from, or null when this entry is
  /// not a snooze.
  final DateTime? originalFireAt;

  /// The platform id of a snooze registration — what cancelling it needs.
  /// Null for everything else.
  final int? snoozeOsId;

  const AlertHubEntry({
    required this.event,
    required this.alert,
    required this.day,
    required this.fireAt,
    this.originalFireAt,
    this.snoozeOsId,
  });

  bool get isSnoozed => snoozeOsId != null;

  @override
  List<Object?> get props => [
    event,
    alert,
    day,
    fireAt,
    originalFireAt,
    snoozeOsId,
  ];
}

/// One fire of a digest as the hub lists it: when it next speaks up, which
/// span it lists and how many occurrences that is.
///
/// Planned fresh rather than read from the registry, the way a disabled
/// alert's row is: a disabled digest still shows what it would do, so its
/// switch is there to turn it back on — [digest] carries the switch as it is.
class DigestHubEntry extends Equatable {
  final EventDigest digest;

  /// Local instant the digest fires at.
  final DateTime fireAt;

  /// The span it lists, date-only UTC, inclusive.
  final DateTime spanStart;
  final DateTime spanEnd;

  /// Occurrences in the span.
  final int count;

  const DigestHubEntry({
    required this.digest,
    required this.fireAt,
    required this.spanStart,
    required this.spanEnd,
    required this.count,
  });

  @override
  List<Object?> get props => [digest, fireAt, spanStart, spanEnd, count];
}

/// What became of one settled registration (OS-4, **B7**).
enum AlertOutcome {
  /// It rang and ended without the app hearing a Stop — natively, with no
  /// Dart up, or while the app was alive at the instant.
  rang,

  /// Stopped from the alarm page or the platform's own notification.
  stopped,

  /// Deferred — a snooze registration that has since settled.
  snoozed,

  /// Reported as Missed: nobody answered, or it was found late.
  missed,

  /// A reminder the platform delivered — a notification does not ring, and
  /// its row is settled by the delivery-evidence band like an alarm's.
  delivered,
}

/// One row of the hub's *Recent* section: a registration that has settled in
/// the last week, and what happened to it.
///
/// [event] and [alert] are null once removed — the row is kept, titled by the
/// hub's own fallback, because the registration is the phone's record of a
/// ring whether or not the event outlived it.
///
/// A digest's delivery (**v42**) carries [digest] and neither of the other
/// two: a digest belongs to no event.
class AlertHistoryEntry extends Equatable {
  final CalendarEvent? event;
  final EventAlert? alert;
  final EventDigest? digest;

  /// Occurrence day, date-only UTC.
  final DateTime day;

  /// Local instant it was armed for.
  final DateTime fireAt;

  /// When the registration settled — the order the section lists in.
  final DateTime settledAt;

  final AlertOutcome outcome;

  const AlertHistoryEntry({
    required this.event,
    required this.alert,
    this.digest,
    required this.day,
    required this.fireAt,
    required this.settledAt,
    required this.outcome,
  });

  @override
  List<Object?> get props => [
    event,
    alert,
    digest,
    day,
    fireAt,
    settledAt,
    outcome,
  ];
}
