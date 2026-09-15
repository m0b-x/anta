import 'dart:convert';

import '../constants/alert_constants.dart';

/// 32-bit FNV-1a over the UTF-8 bytes of [input].
///
/// Chosen over `Object.hash` and over `String.hashCode` for one reason: both
/// of those are allowed to change between Dart releases and are seeded per
/// isolate, and an alert id has to survive a process death, an app update and
/// a reboot. A registration whose id changed is an alarm the OS still holds
/// and the app can no longer cancel.
///
/// UTF-8 bytes rather than UTF-16 code units so a database named with
/// non-ASCII characters hashes the same on every platform.
int fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The date-only UTC day as `YYYY-MM-DD`, the form that goes into the hash.
///
/// Spelled out rather than taken from `DateTime.toIso8601String()` because
/// that carries a time and a `Z`, and the id must not change if the day is
/// ever handed over with a different (still date-only) representation.
String alertDayIso(DateTime dayUtc) {
  final month = dayUtc.month.toString().padLeft(2, '0');
  final day = dayUtc.day.toString().padLeft(2, '0');
  return '${dayUtc.year.toString().padLeft(4, '0')}-$month-$day';
}

/// The string the os id is derived from: `db|alertId|dayIso|kind`.
///
/// The database name leads it so two databases can never cancel each other's
/// alarms (**A9**) — which is the whole reason the payload carries `db` as
/// well.
String alertOsIdKey({
  required String database,
  required String alertId,
  required DateTime dayUtc,
  required AlertKind kind,
}) => '$database|$alertId|${alertDayIso(dayUtc)}|${kind.name}';

/// The deterministic id for one (database, alert, day, kind), before any
/// collision probe.
int alertOsIdSeed({
  required String database,
  required String alertId,
  required DateTime dayUtc,
  required AlertKind kind,
}) => fnv1a32(
  alertOsIdKey(
    database: database,
    alertId: alertId,
    dayUtc: dayUtc,
    kind: kind,
  ),
) & kAlertOsIdMask;

/// Resolves [seed] to a free id by linear probe, asking [isTaken] about each
/// candidate.
///
/// A probe result is only stable because the scheduler records it: the
/// registry row *is* the memory of which slot an alert ended up in, so the
/// next reconcile sees the same occupancy and probes to the same answer.
///
/// Wraps within the 31-bit space rather than growing past it, and gives up
/// after [kAlertOsIdMaxProbes] with the last candidate — a guaranteed
/// termination is worth more than a guaranteed-unique id at odds this long,
/// and the loser of a genuine collision is one alert firing under another's
/// registration, not a hang.
int resolveAlertOsId({
  required int seed,
  required bool Function(int candidate) isTaken,
  int maxProbes = kAlertOsIdMaxProbes,
}) {
  var candidate = seed;
  for (var probe = 0; probe < maxProbes; probe++) {
    if (!isTaken(candidate)) return candidate;
    candidate = (candidate + 1) & kAlertOsIdMask;
  }
  return candidate;
}
