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
///
/// [pending] is every notification the platform still holds scheduled, the
/// upcoming notices among them: what names an alarm of [databaseName] that
/// no entry does. [listed] is every id in the alarm plugin's own Dart-side
/// list, whatever its payload says.
Future<String> quietQaAlerts({
  required AlertGateway gateway,
  required String databaseName,
  required Future<List<ShownNotification>> Function() shown,
  required Future<List<ShownNotification>> Function() pending,
  Future<List<int>> Function()? listed,
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
  // What the entries cannot name. They leave a notice out — it is its
  // alarm's shadow, not an entry the plan made — and they list the alarms
  // the plugin's Dart-side list holds. An alarm that list has lost while
  // the plugin's own store still holds it is armed again at every start and
  // cancelled by nothing: a pass that died left a guest armed for good, red
  // wherever a flow expected none (device pass, 2026-11-14). Its notice,
  // kept by the notifications plugin, still names it: the alarm goes by
  // that id — a cancel reaches both stores whatever names the id — and the
  // notice with it.
  var unnamed = 0;
  try {
    for (final notification in await pending()) {
      final payload = AlertPayload.decode(notification.payload);
      if (payload == null || !payload.notice) continue;
      if (payload.database != databaseName) continue;
      if (rings.contains(payload.osId) || stale.contains(payload.osId)) {
        continue;
      }
      await gateway.cancel(payload.osId);
      await dismiss(notification);
      unnamed++;
    }
  } catch (e) {
    // The rest of the quiet stands; the harness's own count of what is
    // armed reports a guest this left unquiet.
    unnamed = -1;
  }
  // And what the plugin's list holds that the entries left out: an alarm
  // whose payload does not read as an alert, or names no database of this
  // build's. The list is in the QA preference namespace, so every id in it
  // was armed by a QA build — the rule the rings go by.
  var unread = 0;
  try {
    for (final osId in await listed?.call() ?? const <int>[]) {
      if (rings.contains(osId) || stale.contains(osId)) continue;
      await gateway.cancel(osId);
      unread++;
    }
  } catch (e) {
    unread = 0;
  }
  var dismissed = 0;
  for (final notification in await shown()) {
    final payload = AlertPayload.decode(notification.payload);
    if (payload?.database != databaseName) continue;
    await dismiss(notification);
    dismissed++;
  }
  // The harness reads the first two counts off this line
  // (`tool/qa/src/quiet.dart`): an alarm ended by its notice is one more
  // cancelled, and said so after them.
  final byNotice = unnamed > 0 ? unnamed : 0;
  return 'stopped ${rings.length} ring(s), cancelled '
      '${stale.length + byNotice + unread} alarm(s), took down $dismissed '
      'notification(s)'
      '${switch (unnamed) {
        0 => '',
        < 0 => ', pending notices not read',
        _ => ', $unnamed alarm(s) named by a notice alone',
      }}'
      '${unread == 0 ? '' : ', $unread by the plugin\'s list alone'}';
}
