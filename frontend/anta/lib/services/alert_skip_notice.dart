import 'package:flutter/foundation.dart';

import '../models/alert_payload.dart';

/// Holds an upcoming notice's Skip until there is a calendar to apply it on
/// (OS-3, **B6**).
///
/// The [AlertRemovalNotice] shape, for the same reason: Skip is a foreground
/// action that launches the app, and the page that owns the bloc and the
/// snackbar is not there yet when the tap arrives — so the request waits
/// here, the drain opens the calendar on the occurrence's day, and the page
/// takes the request once its state is loaded. One pending request rather
/// than a queue: a second Skip before the first is served is the same tap
/// again.
class AlertSkipNotice extends ChangeNotifier {
  static final AlertSkipNotice instance = AlertSkipNotice();

  /// How long a request waits for a page to serve it. It measures tap to
  /// serve, nothing else: a notice that outlives its alarm is prevented on the
  /// platform side (`timeoutAfter`), and a request for a day already gone is
  /// refused by `AlertSkipAction`.
  static const Duration freshness = Duration(minutes: 5);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  ({AlertPayload payload, DateTime at})? _pending;

  bool get hasPending => _pending != null;

  /// Holds [payload]'s Skip for the calendar — unless it names a database
  /// other than [activeDatabase], in which case nothing is held: two
  /// databases restored from one backup share event ids, so the id alone
  /// could find the wrong event's occurrence here (the positive check A3's
  /// removal makes, for the same reason).
  void publish(AlertPayload payload, {required String activeDatabase}) {
    if (payload.database != activeDatabase) return;
    _pending = (payload: payload, at: clock());
    notifyListeners();
  }

  /// Hands over the pending request and clears it, or null when there is
  /// none — or when it is older than [freshness].
  AlertPayload? take() {
    final pending = _pending;
    _pending = null;
    if (pending == null) return null;
    if (clock().difference(pending.at) > freshness) return null;
    return pending.payload;
  }

  @visibleForTesting
  void clearForTesting() {
    _pending = null;
    clock = DateTime.now;
  }
}
