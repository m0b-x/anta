import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/alert_payload.dart';
import '../utils/alert_planner.dart';
import 'pending_navigation.dart';

/// Single gate deciding whether alerts can reach an operating system at all.
///
/// The [SyncAvailability] shape verbatim, and for the same reason: the two
/// alert plugins ship Android and iOS implementations only, so desktop and web
/// stay plan-only in exactly one place rather than through a platform test per
/// call site. Alert rows are still edited, saved, exported and synced there —
/// they simply ring on the phone.
///
/// [kIsWeb] is checked first because `dart:io`'s [Platform] throws on web.
abstract final class AlertAvailability {
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}

/// One platform entry as the OS still holds it — the id plus the payload it
/// was scheduled with.
typedef PendingAlertEntry = ({int osId, AlertPayload payload});

/// How a ring came to an end **without the app asking for it**.
///
/// The alarm page's Stop and Snooze go through the scheduler and are not
/// reported here — these are the two endings nothing in the app initiated.
enum AlertRingEndCause {
  /// The user pressed Stop on the platform's own notification. An
  /// acknowledgement like the alarm page's Stop, so A3 applies.
  dismissed,

  /// Nobody answered and the Silence-after setting ended the ring. Not an
  /// acknowledgement — it is reported as Missed and removes nothing.
  timedOut,

  /// The user pressed Snooze on the platform's own notification (OS-2). The
  /// alarm is still owed: the plugin re-armed it and recorded an [AlertMove],
  /// which the next reconcile writes down — so this ends the ring without
  /// settling, removing or reporting anything.
  snoozed,
}

/// One ring that ended outside the app, with the payload it rang under.
typedef AlertRingEnd = ({AlertPayload payload, AlertRingEndCause cause});

/// One deferral the platform made on its own — Snooze pressed on the plugin's
/// notification with no Dart running, or with Dart running but not asked.
///
/// [recordedAt] is what makes it identifiable: the plugin's event stream is
/// at-least-once, so the same move can arrive twice and `(osId, recordedAt)`
/// is the key that says so. The registry rewrites the row under the same os
/// id — same alert, same day, new instant, `kind = snooze` — and then
/// acknowledges the move so the plugin can drop its durable marker.
typedef AlertMove = ({int osId, DateTime nextRingAt, DateTime recordedAt});

/// One sound as the platform's own picker reported it — the value to store,
/// plus the name to show while it is stored.
///
/// The title rides along so the row that opened the picker can say what was
/// chosen without a second round trip; it is never persisted, because a phone's
/// name for a sound is the phone's to change.
typedef PickedAlertSound = ({String value, String? title});

/// The device has no ringtone picker at all.
///
/// Distinguished from a cancelled pick — which is simply `null` — because the
/// two mean opposite things to the user: one is a choice, the other is a
/// capability the phone does not have, and only the second is worth a message.
class AlertSoundPickerUnavailable implements Exception {
  const AlertSoundPickerUnavailable();

  @override
  String toString() => 'AlertSoundPickerUnavailable';
}

/// The one seam between the app and the two alarm plugins.
///
/// Everything above this — planner, scheduler, pages — is plugin-free, which
/// is what keeps `flutter test` free of channel stubs and what makes swapping
/// the Alarm tier's backend (A5's open question) a one-file change.
///
/// Bindings: `NoOpAlertGateway` (every platform in Session 2, then desktop,
/// web and tests), `AndroidAlertGateway` (Session 3), `DarwinAlertGateway`
/// (Session 9). Registered in GetIt like `AuthService` / `NoOpAuthService`,
/// because it holds no database reference and therefore nothing for the
/// `DatabaseLifecycle` contract to reset.
abstract class AlertGateway {
  const AlertGateway();

  /// Which backend this binding hands entries to — `alarm` or `notification`.
  /// Recorded on every registration so a later reconcile knows who to ask to
  /// cancel, even after the tier's backend has been switched under it.
  String get backendName;

  /// Whether [pendingEntries] reflects what the OS actually holds.
  ///
  /// False on the no-op binding, and the difference matters: OS truth is what
  /// lets reconcile drop registry rows the platform forgot, and applying that
  /// against a binding that simply knows nothing would cancel and re-register
  /// the whole horizon on every pass.
  bool get tracksPending;

  /// The os ids of rings in progress — everything emitted on [ringing] that
  /// has not been stopped or snoozed yet.
  ///
  /// Reconcile seeds its cancel set with these. The `alarm` package keeps a
  /// ringing entry in its storage until `Alarm.stop`, so it still appears in
  /// [pendingEntries] with a fire instant now in the past, and once the ring
  /// handler has marked its row `fired` the registry no longer calls it in
  /// flight either — without this a resume reconcile two seconds into the
  /// ring would find an entry nobody planned and silence it.
  Set<int> get ringingIds => const {};

  /// Whether this platform has a picker over the phone's **own** alarm sounds.
  ///
  /// False everywhere but Android today, which hides "Choose from phone"
  /// rather than offering a button that cannot do anything. The phone's
  /// default alarm needs no picker and is offered everywhere; a stored URI is
  /// still honoured as far as it can be, and degrades to that default here.
  bool get supportsSoundPicker => false;

  /// Opens the platform's own sound picker, seeded with [current], and answers
  /// what came back — `null` when the user cancelled.
  ///
  /// Throws [AlertSoundPickerUnavailable] when the device has no picker at all.
  /// Every other failure answers `null`: a picker that could not be opened for
  /// some transient reason is, from where the user is standing, a pick that did
  /// not happen.
  Future<PickedAlertSound?> pickSystemSound(String? current) async => null;

  /// The phone's own name for a stored sound value, or `null` when this device
  /// cannot resolve it — which is the answer a URI from another phone gets, and
  /// what the editor turns into "not available here".
  Future<String?> soundTitle(String value) async => null;

  /// Re-reads everything a ring will be armed **under** that the platform owns
  /// rather than the plan — today the phone's alarm volume — and returns a
  /// short token describing it.
  ///
  /// Called once at the top of every pass that schedules, **before** any
  /// [schedule], and the answer is what that whole pass arms with: a binding
  /// may cache what it read here so the platform is asked once rather than once
  /// per fire, and so the token recorded in the registry cannot describe
  /// something other than what was actually armed.
  ///
  /// The scheduler stores it per registration and compares it on the next pass,
  /// which is how an alarm whose instant never moved is still re-armed when the
  /// phone's volume crosses the floor. It must therefore be **stable** — equal
  /// inputs, equal token — and **coarse**: a token that changed with every
  /// nudge of the volume key would re-arm the horizon every time.
  Future<String> refreshArmContext() async => backendName;

  /// Hands one planned fire to the platform. Returns false when the platform
  /// refused it (a revoked exact-alarm permission, a plugin exception); the
  /// scheduler records nothing for a refusal, so the next reconcile tries
  /// again.
  ///
  /// [noticeAt] is when the fire's upcoming notice is posted (OS-3), already
  /// decided by the scheduler's `noticeInstantFor`; null means none, and a
  /// binding then takes down any notice it still holds for this id — the
  /// lead turned off reaches standing alarms through the arm signature and
  /// lands here. The notice is the alarm's shadow, never a registration.
  Future<bool> schedule(
    PlannedFire fire,
    AlertPayload payload, {
    DateTime? noticeAt,
  });

  /// Cancels one entry by the id it was scheduled under. Cancelling an id the
  /// platform does not hold is a no-op, never an error — a process death
  /// between the cancel and the registry write has to be replayable.
  Future<void> cancel(int osId);

  /// Every entry the platform still holds for this app, payloads included.
  ///
  /// Payloads, not bare ids, because reconcile has to tell an entry of the
  /// **active** database from one belonging to another (A9) and only the
  /// payload carries that.
  Future<List<PendingAlertEntry>> pendingEntries();

  /// The ids of [pendingEntries]. The §3.1 spelling, derived so the platform
  /// is only asked once per reconcile.
  Future<Set<int>> pendingIds() async {
    final entries = await pendingEntries();
    return {for (final entry in entries) entry.osId};
  }

  /// Posts the quiet "Missed: {title} at {time}" notification of A10. Takes
  /// the payload alone, so the body can be composed without opening a
  /// database — and so a background isolate could post it.
  Future<void> showMissed(AlertPayload payload);

  /// Stops an alarm that is ringing right now, without touching its
  /// registration — the scheduler records the state change.
  Future<void> stopRinging(int osId);

  /// Emits while an alarm is ringing, so the app can show the alarm page.
  Stream<AlertPayload> get ringing;

  /// The deferrals the platform recorded since the last call, and clears
  /// them. Applied by the scheduler inside its serialized chain, never here:
  /// a binding awaits only its own initialization, so a reconcile that calls
  /// this from inside the chain cannot wait on itself. Empty wherever no
  /// plugin can snooze on its own.
  Future<List<AlertMove>> takeMoves() async => const [];

  /// Tells the platform the app has durably written [move] down, so its
  /// marker can go. Called after the registry write, never before it, and
  /// safe to repeat.
  Future<void> acknowledgeMove(AlertMove move) async {}

  /// Emits when a ring ends by a route the app did not take — the platform
  /// notification's own Stop, the Silence-after timeout, or a native Snooze.
  ///
  /// Without it a ring stopped from the notification leaves its registration
  /// `fired` forever: the next occurrence is never re-armed, A3 never runs and
  /// an alarm page that is up keeps offering Stop for a ring that is over.
  Stream<AlertRingEnd> get ringEnded => const Stream<AlertRingEnd>.empty();

  /// When this process started, or null where the platform cannot say.
  ///
  /// Delivery evidence for the Missed path. An alarm can ring and be stopped
  /// entirely natively, with no Dart running to mark its row; but a process
  /// that was already alive at the fire instant was neither force-stopped nor
  /// switched off, so the platform did deliver to it.
  Future<DateTime?> processStartedAt() async => null;

  /// The alert the app was launched by, if any, for a cold-start tap. Read
  /// once at startup and queued rather than pushed: there is no navigator yet.
  ///
  /// Also answers the phone's own "next alarm" surface: an alarm-clock entry's
  /// show intent (Patch 1 of the `alarm` fork) launching the app cold reads as
  /// an [OpenAlertsHubIntent], asked for **after** the notification launch
  /// details so a tap on a notification always wins.
  Future<AlertIntent?> launchIntent();

  /// Emits when the phone's "next alarm" surface — the lock-screen line,
  /// Quick Settings — opens an app that is already running, through the show
  /// intent every alarm-clock entry carries. The listener queues an
  /// [OpenAlertsHubIntent]; a cold launch by the same intent is reported by
  /// [launchIntent] instead. Empty wherever nothing arms alarm clocks.
  Stream<void> get showAlarms => const Stream<void>.empty();

  /// Posts — or, with [refresh], re-posts — the session chip (**B8**, OS-5):
  /// the one ongoing notification saying the session an acknowledged alarm
  /// belongs to is under way, counting from [startedAt] and, when [endsAt] is
  /// known, with [progress] percent of it behind. Answers whether the chip
  /// stands on the shade afterwards: a refresh of a chip the user has taken
  /// down with *Done* is refused rather than re-posted, and that refusal is
  /// how the Dart side learns of a Done that ran with no Dart at all.
  /// `SessionChip` decides when and once; a binding only draws it. False,
  /// wherever nothing can be pinned to the shade.
  Future<bool> showSessionChip(
    AlertPayload payload, {
    required DateTime startedAt,
    DateTime? endsAt,
    int? progress,
    bool refresh = false,
  }) async => false;

  /// Takes the session chip down, whether or not this process posted it.
  Future<void> clearSessionChip() async {}

  Future<void> dispose();
}

/// Bound where alerts cannot reach an operating system — desktop, web, every
/// widget test, and every platform in Session 2.
///
/// Schedules nothing and holds nothing. The scheduler still plans, still diffs
/// and still writes the registry against it, which is exactly what makes the
/// whole pipeline testable without a single channel stub. What the operating
/// system allows is not asked here at all: that is `PermissionGateway`.
class NoOpAlertGateway extends AlertGateway {
  const NoOpAlertGateway();

  @override
  String get backendName => 'none';

  @override
  bool get tracksPending => false;

  @override
  Future<bool> schedule(
    PlannedFire fire,
    AlertPayload payload, {
    DateTime? noticeAt,
  }) async => true;

  @override
  Future<void> cancel(int osId) async {}

  @override
  Future<List<PendingAlertEntry>> pendingEntries() async => const [];

  @override
  Future<void> showMissed(AlertPayload payload) async {}

  @override
  Future<void> stopRinging(int osId) async {}

  @override
  Stream<AlertPayload> get ringing => const Stream<AlertPayload>.empty();

  @override
  Future<AlertIntent?> launchIntent() async => null;

  @override
  Future<void> dispose() async {}
}
