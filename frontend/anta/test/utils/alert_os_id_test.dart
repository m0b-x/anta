import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/utils/alert_os_id.dart';

/// The id is what makes reconcile idempotent across a process death: the app
/// has to be able to cancel an entry it scheduled in a previous run, from a
/// registry that may itself have been wiped. Everything below is therefore
/// about *stability* rather than about distribution.
void main() {
  int seedOf({
    String database = 'gym_notes',
    String alertId = 'alert-1',
    DateTime? day,
    AlertKind kind = AlertKind.scheduled,
  }) => alertOsIdSeed(
    database: database,
    alertId: alertId,
    dayUtc: day ?? DateTime.utc(2026, 9, 20),
    kind: kind,
  );

  group('the hash', () {
    test('is FNV-1a 32 over the UTF-8 bytes', () {
      // The canonical vectors, so a "harmless" refactor of the loop cannot
      // silently renumber every alert on every phone.
      expect(fnv1a32(''), 0x811c9dc5);
      expect(fnv1a32('a'), 0xe40c292c);
      expect(fnv1a32('foobar'), 0xbf9cf968);
    });

    test('is deterministic across calls', () {
      expect(seedOf(), seedOf());
    });

    test('never exceeds 31 bits', () {
      for (var i = 0; i < 500; i++) {
        final id = seedOf(alertId: 'alert-$i');
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(kAlertOsIdMask));
      }
    });

    test('changes with every field of the key', () {
      final base = seedOf();
      expect(seedOf(database: 'work'), isNot(base));
      expect(seedOf(alertId: 'alert-2'), isNot(base));
      expect(seedOf(day: DateTime.utc(2026, 9, 21)), isNot(base));
      expect(seedOf(kind: AlertKind.snooze), isNot(base));
    });

    test('the key is db|alertId|dayIso|kind', () {
      expect(
        alertOsIdKey(
          database: 'gym_notes',
          alertId: 'alert-1',
          dayUtc: DateTime.utc(2026, 9, 5),
          kind: AlertKind.snooze,
        ),
        'gym_notes|alert-1|2026-09-05|snooze',
      );
    });

    test('the day is rendered zero-padded, date only', () {
      expect(alertDayIso(DateTime.utc(2026, 1, 3)), '2026-01-03');
      expect(alertDayIso(DateTime.utc(999, 12, 31)), '0999-12-31');
    });
  });

  group('the probe', () {
    test('returns the seed when the slot is free', () {
      expect(
        resolveAlertOsId(seed: 42, isTaken: (_) => false),
        42,
      );
    });

    test('walks forward past taken slots', () {
      const taken = {42, 43, 44};
      expect(
        resolveAlertOsId(seed: 42, isTaken: taken.contains),
        45,
      );
    });

    test('wraps inside the 31-bit space', () {
      expect(
        resolveAlertOsId(
          seed: kAlertOsIdMask,
          isTaken: (candidate) => candidate == kAlertOsIdMask,
        ),
        0,
      );
    });

    test('terminates rather than looping when everything is taken', () {
      var probes = 0;
      final resolved = resolveAlertOsId(
        seed: 7,
        isTaken: (_) {
          probes++;
          return true;
        },
        maxProbes: 5,
      );

      expect(probes, 5);
      expect(resolved, 12);
    });
  });
}
