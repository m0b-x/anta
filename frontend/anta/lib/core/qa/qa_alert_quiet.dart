import '../../models/alert_payload.dart';
import '../../services/alert_gateway.dart';

/// A notification standing on the shade, as [quietQaAlerts] reads it.
typedef ShownNotification = ({int id, String? tag, String? payload});

/// Takes down what the alert tier still holds from the QA run before a reset
/// launch: every ring in progress, every entry the platform holds for
/// [databaseName], and every alert notification of [databaseName] standing on
/// the shade. Returns the `[qa]` line's wording.
///
/// A reset empties the QA database, but the launch reconcile leaves a ring in
/// progress alone — it is not the plan's to cancel — so the `alarm` plugin
/// kept sounding it, kept it stored and announced it again at every launch,
/// and its boot receiver re-armed it after a reboot: a pass that died while
/// an alarm rang left the guest on the alarm page for good. Ending a ring is
/// the user's, so this runs only on a QA reset, never in a build the owner
/// runs.
///
/// Every ring is stopped: the plugin's Dart store is in the QA preference
/// namespace, so each one it reports was armed by a QA build. Pending entries
/// and the shade are the install's, shared with the owner's databases, so
/// only [databaseName]'s are touched — the reconcile's own A9 rule.
Future<String> quietQaAlerts({
  required AlertGateway gateway,
  required String databaseName,
  required Future<List<ShownNotification>> Function() shown,
  required Future<void> Function(ShownNotification notification) dismiss,
}) async {
  // Asked first: a binding answers only once it has initialized, which is
  // where it finds the rings a launch inherits.
  final entries = await gateway.pendingEntries();
  final rings = {...gateway.ringingIds};
  final stale = {
    for (final entry in entries)
      if (entry.payload.database == databaseName) entry.osId,
  }..removeAll(rings);
  for (final osId in rings) {
    await gateway.cancel(osId);
  }
  for (final osId in stale) {
    await gateway.cancel(osId);
  }
  var dismissed = 0;
  for (final notification in await shown()) {
    final payload = AlertPayload.decode(notification.payload);
    if (payload?.database != databaseName) continue;
    await dismiss(notification);
    dismissed++;
  }
  return 'stopped ${rings.length} ring(s), cancelled ${stale.length} '
      'alarm(s), took down $dismissed notification(s)';
}
