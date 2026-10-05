import 'package:flutter/foundation.dart';

/// Tells the calendar that the alarm page's Keep changed an event.
///
/// Keep clears "remove after it rings" through `CalendarEventService`, and a
/// service write tells nobody: the app-wide `CalendarBloc` went on holding
/// the event as it was, and the day panel kept saying "removed after it
/// rings" under an event the user had just kept, until the next launch.
///
/// The [AlertSkipNotice] shape, for the same reason: the page that owns the
/// bloc is usually not on screen when Keep is pressed — an alarm page is over
/// it, or the ring came up over a note — so what happened waits here until
/// there is a calendar to reload. Not in GetIt, like the other notices: the
/// ring path holds no container and this holds no database.
///
/// A flag where the other notices hold a payload. The calendar's answer is a
/// reload of the open database's events whichever one was kept, and the
/// controller publishes only for an event of that database — so there is
/// nothing to carry, nothing that could name the wrong event, and nothing
/// that goes stale: a reload asked for an hour ago is still the right
/// reload, which is why this notice has no freshness window.
class AlertKeepNotice extends ChangeNotifier {
  static final AlertKeepNotice instance = AlertKeepNotice();

  bool _pending = false;

  bool get hasPending => _pending;

  /// Records that an event of the open database was kept.
  void publish() {
    _pending = true;
    notifyListeners();
  }

  /// Answers whether a reload is owed, and clears it.
  bool take() {
    final pending = _pending;
    _pending = false;
    return pending;
  }

  /// Drops everything. Test-only: the notice is a process-global static, so
  /// a suite that leaves one behind would reload the next one's calendar.
  @visibleForTesting
  void clearForTesting() => _pending = false;
}
