import 'package:flutter/foundation.dart';

/// Holds a request for the quick-alarm sheet until there is a calendar page to
/// open it on (OS-5, **B9**).
///
/// The [AlertSkipNotice] shape, for the same reason: the Quick Settings tile
/// and the launcher shortcut start the activity with the `QUICK_ALARM` action,
/// the drain opens the calendar, and the page that owns the sheet guard, the
/// bloc and the snackbar is not there yet when the tap arrives — so the
/// request waits here and the page takes it once it is up and loaded. One
/// pending request rather than a queue: a second tap before the first is
/// served is the same tap again.
class QuickAlarmRequest extends ChangeNotifier {
  static final QuickAlarmRequest instance = QuickAlarmRequest();

  /// How long a request waits for a page to serve it — tap to serve. A tile
  /// tapped and then abandoned must not open a sheet on a calendar visited
  /// an hour later.
  static const Duration freshness = Duration(minutes: 5);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  DateTime? _pendingAt;

  bool get hasPending => _pendingAt != null;

  void publish() {
    _pendingAt = clock();
    notifyListeners();
  }

  /// Hands over the pending request and clears it: true when there was one
  /// no older than [freshness].
  bool take() {
    final at = _pendingAt;
    _pendingAt = null;
    if (at == null) return false;
    return clock().difference(at) <= freshness;
  }

  @visibleForTesting
  void clearForTesting() {
    _pendingAt = null;
    clock = DateTime.now;
  }
}
