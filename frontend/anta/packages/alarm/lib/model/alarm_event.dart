import 'package:alarm/src/generated/platform_bindings.g.dart';
import 'package:equatable/equatable.dart';

/// Why the host changed an alarm without the application asking.
enum AlarmEventCause {
  /// The user deferred the alarm from the notification or the ring screen.
  snooze,

  /// The platform refused to let the ring start.
  ///
  /// Android forbids starting a media playback foreground service from
  /// `BOOT_COMPLETED`, and the refusal follows the attribution rather than the
  /// caller, so an ordinary alarm delivered inside the boot window is refused
  /// too. Paired with [AlarmMoved] the alarm was re-armed just past that
  /// window, because ringing late beats not ringing. Paired with [AlarmDropped]
  /// the retry was refused as well, which means the boot window was not the
  /// cause and waiting longer would not have helped.
  platformRefusal,

  /// The alarm's time had already passed while the device was off, so it was
  /// discarded at boot rather than sounded hours late.
  staleAtBoot,
}

/// Something the host did to an alarm on its own.
///
/// These decisions are taken in contexts with no Flutter engine — a native
/// notification action, a full screen intent, the boot receiver — so they
/// cannot be reported by a callback at the time. The host records them durably
/// and the next `Alarm.init()` drains them, which is why an event can arrive
/// long after it happened.
///
/// Reaches applications on `Alarm.events`. Match on the subtype to know what
/// happened to the alarm, and read [cause] to know why.
sealed class AlarmEvent extends Equatable {
  const AlarmEvent({
    required this.id,
    required this.cause,
    required this.recordedAt,
  });

  /// Builds the event described by [wire].
  factory AlarmEvent.fromWire(AlarmEventWire wire) {
    final cause = switch (wire.cause) {
      AlarmEventCauseWire.snooze => AlarmEventCause.snooze,
      AlarmEventCauseWire.platformRefusal => AlarmEventCause.platformRefusal,
      AlarmEventCauseWire.staleAtBoot => AlarmEventCause.staleAtBoot,
    };
    final recordedAt =
        DateTime.fromMillisecondsSinceEpoch(wire.recordedAtMillis);
    final at = DateTime.fromMillisecondsSinceEpoch(wire.atMillis);

    return switch (wire.verb) {
      AlarmEventVerbWire.moved => AlarmMoved(
          id: wire.alarmId,
          cause: cause,
          recordedAt: recordedAt,
          nextRingAt: at,
        ),
      AlarmEventVerbWire.dropped => AlarmDropped(
          id: wire.alarmId,
          cause: cause,
          recordedAt: recordedAt,
          scheduledFor: at,
        ),
    };
  }

  /// Id of the alarm this happened to.
  final int id;

  /// Why the host did it.
  final AlarmEventCause cause;

  /// When the host recorded this, which may be well before it was delivered.
  final DateTime recordedAt;
}

/// The alarm is still owed, and now rings at [nextRingAt].
final class AlarmMoved extends AlarmEvent {
  /// Creates an [AlarmMoved].
  const AlarmMoved({
    required super.id,
    required super.cause,
    required super.recordedAt,
    required this.nextRingAt,
  });

  /// When the alarm rings now.
  final DateTime nextRingAt;

  @override
  List<Object?> get props => [id, cause, recordedAt, nextRingAt];
}

/// The alarm is gone and will not ring.
///
/// The plugin has already removed it, so there is nothing to cancel. This
/// exists so an application can tell its user in its own words — the plugin
/// deliberately posts nothing, because a notification it owns would sit outside
/// the app's own records and could not be rewritten or cancelled by it.
final class AlarmDropped extends AlarmEvent {
  /// Creates an [AlarmDropped].
  const AlarmDropped({
    required super.id,
    required super.cause,
    required super.recordedAt,
    required this.scheduledFor,
  });

  /// When the alarm should have rung.
  final DateTime scheduledFor;

  @override
  List<Object?> get props => [id, cause, recordedAt, scheduledFor];
}
