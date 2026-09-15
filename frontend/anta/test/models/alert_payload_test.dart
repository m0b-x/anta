import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';

/// The payload is the only thing that survives a reboot, a force stop and a
/// database switch: the alarm page draws from it alone, and reconcile decides
/// whether an entry is even ours by reading its `db`. Both directions of the
/// codec therefore have to be total — a truncated or foreign string must read
/// as "not ours" rather than throw inside a platform callback.
void main() {
  AlertPayload payloadOf() => const AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: 1789862400000,
    osId: 1234,
    mode: AlertMode.ring,
    title: 'Leg day',
    timeLabel: '18:00',
    colorValue: 0xFF00FF00,
    iconKey: 'alarm',
    categoryId: 'gym',
    removeAfterAlert: true,
    snooze: true,
  );

  test('round-trips through the wire form', () {
    final payload = payloadOf();

    expect(AlertPayload.decode(payload.encode()), payload);
  });

  test('the occurrence day comes back as date-only UTC', () {
    expect(payloadOf().dayUtc, DateTime.utc(2026, 9, 20));
    expect(payloadOf().dayUtc.isUtc, isTrue);
  });

  test('isAlarm follows the mode', () {
    expect(payloadOf().isAlarm, isTrue);
    expect(
      AlertPayload.decode(
        payloadOf().copyWith().encode().replaceAll('"ring"', '"notify"'),
      )!.isAlarm,
      isFalse,
    );
  });

  test('copyWith changes only what it is given', () {
    final snoozed = payloadOf().copyWith(osId: 99, snooze: false);

    expect(snoozed.osId, 99);
    expect(snoozed.snooze, isFalse);
    expect(snoozed.eventId, 'e1');
    expect(snoozed.title, 'Leg day');
    expect(snoozed.removeAfterAlert, isTrue);
  });

  group('decoding what a platform hands back', () {
    test('null, empty and non-JSON read as not ours', () {
      expect(AlertPayload.decode(null), isNull);
      expect(AlertPayload.decode(''), isNull);
      expect(AlertPayload.decode('not json at all'), isNull);
      expect(AlertPayload.decode('[1, 2, 3]'), isNull);
    });

    test('a missing identity field rejects the whole payload', () {
      for (final key in ['db', 'eventId', 'alertId', 'osId', 'dayUtcMs']) {
        final map = payloadOf().toJson()..remove(key);
        expect(
          AlertPayload.fromJson(map),
          isNull,
          reason: '$key is part of the identity',
        );
      }
    });

    test('a missing presentation field falls back rather than rejecting', () {
      final map = payloadOf().toJson()
        ..remove('title')
        ..remove('timeLabel')
        ..remove('colorValue')
        ..remove('iconKey')
        ..remove('categoryId')
        ..remove('mode')
        ..remove('removeAfterAlert')
        ..remove('snooze');

      final decoded = AlertPayload.fromJson(map);

      // An entry written by a newer build is still an alarm that has to be
      // stoppable, so identity survives and everything else degrades.
      expect(decoded, isNotNull);
      expect(decoded!.eventId, 'e1');
      expect(decoded.title, '');
      expect(decoded.timeLabel, '');
      expect(decoded.colorValue, isNull);
      expect(decoded.iconKey, isNull);
      expect(decoded.categoryId, 'other');
      expect(decoded.mode, AlertMode.notify);
      expect(decoded.removeAfterAlert, isFalse);
      expect(decoded.snooze, isFalse);
    });

    test('an unknown mode decodes to the quieter tier', () {
      final map = payloadOf().toJson()..['mode'] = 'klaxon';

      expect(AlertPayload.fromJson(map)!.mode, AlertMode.notify);
    });
  });
}
