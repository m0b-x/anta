import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The zone Firestore's free daily quota resets in, at midnight.
const String syncQuotaResetZone = 'America/Los_Angeles';

/// The first midnight in [syncQuotaResetZone] after [at], as a local
/// [DateTime]: up to a day ahead, a day and an hour on the night the clocks
/// fall back there.
///
/// Loads the zone database only when nothing has yet: loading it again would
/// reset the local zone the alert gateway set on it.
DateTime nextSyncQuotaReset(DateTime at) {
  if (!tz.timeZoneDatabase.isInitialized) tzdata.initializeTimeZones();
  final zone = tz.getLocation(syncQuotaResetZone);
  final there = tz.TZDateTime.from(at, zone);
  final midnight = tz.TZDateTime(zone, there.year, there.month, there.day + 1);
  return DateTime.fromMicrosecondsSinceEpoch(midnight.microsecondsSinceEpoch);
}
