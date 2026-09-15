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

/// Whether one permission is held, refused, or not a thing on this platform.
enum AlertPermissionState {
  granted,
  denied,

  /// The platform has no such permission, or this binding cannot answer.
  /// Renders as "Not supported on this platform" rather than as a problem.
  unsupported,
}

/// The live permission picture, asked of the gateway rather than stored:
/// every one of these can change in the system settings between two frames,
/// and a cached answer would offer to fix something already fixed.
typedef AlertPermissions = ({
  AlertPermissionState notifications,
  AlertPermissionState fullScreenIntent,
  AlertPermissionState exactAlarms,
});

/// One platform entry as the OS still holds it — the id plus the payload it
/// was scheduled with.
typedef PendingAlertEntry = ({int osId, AlertPayload payload});

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

  Future<AlertPermissions> permissions();

  /// Runs the runtime notification prompt. **Only ever called from a user
  /// action** — never at app start, never from reconcile.
  Future<bool> requestNotifications();

  /// Opens the system page where full-screen alarms are allowed. Android has
  /// no prompt for it, so this is a link, not a request.
  Future<void> openFullScreenIntentSettings();

  /// Stops an alarm that is ringing right now, without touching its
  /// registration — the scheduler records the state change.
  Future<void> stopRinging(int osId);

  /// Emits while an alarm is ringing, so the app can show the alarm page.
  Stream<AlertPayload> get ringing;

  /// The alert the app was launched by, if any, for a cold-start tap. Read
  /// once at startup and queued rather than pushed: there is no navigator yet.
  Future<AlertIntent?> launchIntent();

  Future<void> dispose();
}

/// Bound where alerts cannot reach an operating system — desktop, web, every
/// widget test, and every platform in Session 2.
///
/// Reports unsupported permissions, schedules nothing and holds nothing. The
/// scheduler still plans, still diffs and still writes the registry against
/// it, which is exactly what makes the whole pipeline testable without a
/// single channel stub.
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
  Future<AlertPermissions> permissions() async => (
    notifications: AlertPermissionState.unsupported,
    fullScreenIntent: AlertPermissionState.unsupported,
    exactAlarms: AlertPermissionState.unsupported,
  );

  @override
  Future<bool> requestNotifications() async => false;

  @override
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<void> stopRinging(int osId) async {}

  @override
  Stream<AlertPayload> get ringing => const Stream<AlertPayload>.empty();

  @override
  Future<AlertIntent?> launchIntent() async => null;

  @override
  Future<void> dispose() async {}
}
