/// How far ahead the planner is allowed to look, and how much of what it
/// finds may reach the operating system (**A7**).
///
/// Three independent ceilings, because they answer three different failure
/// modes: [perAlert] stops one daily event from filling the whole budget,
/// [days] bounds the walk itself, and [total] is the only one the platform
/// cares about — iOS refuses more than 64 pending notifications and Android
/// OEMs start dropping alarms somewhere above a few hundred.
///
/// The planner never caches, so every reconcile re-derives the window from
/// scratch; that is what makes a holiday-profile change or a skip reach the
/// OS without anything having to invalidate anything.
class AlertHorizon {
  /// Occurrence days collected per enabled alert. Two is "survives a weekend
  /// without opening the app" without spending the budget on one event.
  final int perAlert;

  /// Days walked forward from today, inclusive of today.
  final int days;

  /// Registrations actually handed to the platform, soonest first.
  final int total;

  const AlertHorizon({
    required this.perAlert,
    required this.days,
    required this.total,
  });
}

/// The shipped horizon. A value rather than three loose constants so a test
/// can narrow one axis without redefining the other two.
const AlertHorizon kAlertHorizon = AlertHorizon(
  perAlert: 2,
  days: 30,
  total: 48,
);

/// Why a registration exists — the `kind` column of `alert_registrations`.
///
/// A snooze is deliberately its own registration rather than a moved one: an
/// unrelated reconcile of the same event re-derives every `scheduled` entry
/// from the plan and would otherwise wipe a snooze the user set thirty
/// seconds ago.
enum AlertKind {
  scheduled,
  snooze;

  static AlertKind fromName(String? raw) {
    for (final kind in AlertKind.values) {
      if (kind.name == raw) return kind;
    }
    return AlertKind.scheduled;
  }
}

/// Lifecycle of one registration — the `state` column.
///
/// Only [pending] is ever handed back to the diff; everything else is history
/// kept for [kAlertRegistrationRetention] so a late-fire pass and the hub can
/// say what happened. An unknown value decodes to [cancelled], the state that
/// makes the scheduler re-plan rather than trust a row it cannot read.
enum AlertRegistrationState {
  pending,
  fired,
  stopped,
  cancelled;

  static AlertRegistrationState fromName(String? raw) {
    for (final state in AlertRegistrationState.values) {
      if (state.name == raw) return state;
    }
    return AlertRegistrationState.cancelled;
  }
}

/// How long settled registrations survive before reconcile sweeps them.
/// History that can be neither exported nor merged has no reason to outlive a
/// week.
const Duration kAlertRegistrationRetention = Duration(days: 7);

/// How long a registration whose instant has passed is treated as **in
/// flight** rather than missed (**A10**: "ring if under 30 min late").
///
/// The app cannot see a delivery. The `alarm` plugin relaunches the process
/// and only emits on `Alarm.ringing` a second or two later — after the launch
/// reconcile has already run — and the notification tier never calls back at
/// all, so a gone reminder row is indistinguishable from a delivered one.
/// Within this window a past-due row is therefore left exactly as it is:
/// still `pending`, never cancelled, never re-scheduled, never reported. The
/// ring handler settles it; nothing else may.
///
/// Also the value Session 3 passes as `androidStaleAfter`, so the app's idea
/// of "still worth ringing" and the plugin's are one number.
const Duration kLateFireGrace = Duration(minutes: 30);

/// How late a missed registration may be and still earn a quiet "Missed"
/// notification (**A10**). Past this the session it belonged to is over and
/// saying anything is noise.
const Duration kMissedAlertWindow = Duration(hours: 24);

/// The platform id space. Android notification ids and the `alarm` package's
/// ids are both signed 32-bit, so the hash is masked to 31 bits and every id
/// handed out is non-negative.
const int kAlertOsIdMask = 0x7fffffff;

/// How many linear probes a collision may take before the scheduler gives up
/// and uses the last candidate anyway.
///
/// Two ids colliding at all is a 1-in-2^31 event per pair; needing more than
/// a handful of probes cannot happen with a 48-entry horizon, so this is a
/// termination guard rather than a capacity.
const int kAlertOsIdMaxProbes = 64;

/// The lowest alarm-stream level a ring may start from, 0..1.
///
/// **A floor, not a level (2026-09-21).** A ring used to be armed at a flat
/// 0.8, which overrode the phone's own alarm slider for the duration of every
/// ring — an alarm app deciding it knows better than the user's volume key.
/// Alarms now *follow* the stream (the `alarm` package leaves it alone when it
/// is handed no volume at all), and this is the single case that still takes
/// it over: a slider left at or near zero would otherwise be an alarm that
/// silently does not wake anyone.
const double kAlertRingFloorVolume = 0.3;

/// How loud one ring will be armed — the only two answers, and the only thing
/// about the phone's volume the registry remembers.
///
/// A **bucket**, never the raw fraction: the decision is made when the alarm is
/// armed, which may be days before it rings, so it has to be re-taken whenever
/// the app reconciles. Recording the fraction would re-arm the whole horizon on
/// every nudge of the volume key; recording which side of [kAlertRingFloorVolume]
/// it fell on re-arms only when that actually changes what the phone will do.
enum AlertRingVolume {
  /// Hand the plugin no volume: the ring plays at whatever the alarm stream is
  /// set to when it fires, and nothing is restored afterwards because nothing
  /// was changed.
  follow,

  /// Arm at [kAlertRingFloorVolume]. The `alarm` package raises the stream for
  /// the length of the ring and puts it back after.
  floor,
}

/// Which of the two [AlertRingVolume] answers a measured alarm-stream level
/// earns. **Pure**, and the one definition of "too quiet to wake anyone".
///
/// [fraction] is the stream's current level over its maximum, or `null` when
/// the platform could not be asked — which follows the phone, because refusing
/// to arm an alarm over a volume query is far worse than arming a quiet one.
AlertRingVolume alertRingVolumeFor(double? fraction) {
  if (fraction == null) return AlertRingVolume.follow;
  return fraction < kAlertRingFloorVolume
      ? AlertRingVolume.floor
      : AlertRingVolume.follow;
}

/// How long a ring takes to fade up to full. Applied by the `alarm` package to
/// its own media player, **not** to the stream, so it is independent of
/// [AlertRingVolume] and still works when the level is the phone's own. A fade
/// rather than a jump, because the first second of an alarm is heard at arm's
/// length.
const Duration kAlertRingFade = Duration(seconds: 3);

/// Keeps "Missed" notice ids out of the registration id space.
///
/// A Missed notice reports on a registration and is derived from its id so
/// reporting the same miss twice replaces the notice instead of stacking two;
/// the salt is what stops that derivation from landing on a live entry and
/// cancelling it.
const int kAlertMissedIdSalt = 0x4d495353;

/// The token an alarm-tier arm signature ends with since the `alarm` fork
/// (OS-1, 2026-09-22), naming the shape the fork gives an entry: armed with
/// `setAlarmClock`, a picked sound handed over as its raw URI.
///
/// It differs from every token a pre-fork build recorded, and that is its
/// whole job: the first pass after the upgrade re-arms every standing
/// alarm-tier row under its existing os id. Those rows were armed with
/// `setExactAndAllowWhileIdle` and, for a picked sound, with a file under
/// `files/alert_sounds` that this build deletes — and the plugin's own
/// `Alarm.init()` re-sets each stored entry exactly as it was, stale path
/// included, so without a re-arm the diff's fast path would keep both until
/// something unrelated happened to move the fire. A reminder token stays bare.
const String kAlertArmClockToken = '~clock';

/// How far ahead the Calendar settings page's `Test alarm` is armed.
///
/// Long enough to lock the phone and watch what a real ring does to a locked
/// screen, short enough that nobody has to wait for it.
const Duration kAlertTestAlarmDelay = Duration(seconds: 10);

/// Key prefix the `alarm` package stores its Dart-side list of armed alarms
/// under, in `SharedPreferences` (`AlarmStorage.prefix`). Spelled here so the
/// QA reset can spare those entries without importing the plugin.
const String kAlarmPluginStoragePrefix = '__alarm_id__';
