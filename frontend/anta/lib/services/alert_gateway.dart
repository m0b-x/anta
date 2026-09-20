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
}

/// One ring that ended outside the app, with the payload it rang under.
typedef AlertRingEnd = ({AlertPayload payload, AlertRingEndCause cause});

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

  /// Hands one planned fire to the platform. Returns false when the platform
  /// refused it (a revoked exact-alarm permission, a plugin exception); the
  /// scheduler records nothing for a refusal, so the next reconcile tries
  /// again.
  Future<bool> schedule(PlannedFire fire, AlertPayload payload);

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

  /// Emits when a ring ends by a route the app did not take — the platform
  /// notification's own Stop, or the Silence-after timeout.
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
  Future<AlertIntent?> launchIntent();

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
  Future<bool> schedule(PlannedFire fire, AlertPayload payload) async => true;

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
