import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/models/event_digest.dart';

/// [EventDigest] is stored as one payload blob beside its row columns, so the
/// codec is what has to hold: a round trip keeps every field, and anything a
/// newer build or a damaged row could write decodes to a digest that still
/// fires sensibly instead of throwing.
void main() {
  EventDigest decode(Object? payload, {String name = ''}) =>
      EventDigest.fromRow(
        id: 'd1',
        name: name,
        payload: payload is String ? payload : jsonEncode(payload),
      );

  group('payload', () {
    test('round-trips every field', () {
      const digest = EventDigest(
        id: 'd1',
        name: 'Birthdays',
        cadence: DigestCadence.weekly,
        anchor: DateTime.sunday,
        minute: 20 * 60,
        leadDays: 1,
        categoryIds: {'birthday', 'family'},
        includeEmpty: true,
        enabled: false,
        sortOrder: 3,
      );

      final decoded = EventDigest.fromRow(
        id: digest.id,
        name: digest.name,
        payload: digest.encodePayload(),
        enabled: digest.enabled,
        sortOrder: digest.sortOrder,
      );

      expect(decoded, digest);
    });

    test('carries none of the row columns', () {
      const digest = EventDigest(id: 'd1', name: 'Named', sortOrder: 4);
      final payload = jsonDecode(digest.encodePayload()) as Map;
      expect(payload.keys, isNot(contains('id')));
      expect(payload.keys, isNot(contains('name')));
      expect(payload.keys, isNot(contains('enabled')));
      expect(payload.keys, isNot(contains('sortOrder')));
    });

    test('one digest writes one blob whatever the category order', () {
      const a = EventDigest(id: 'd1', categoryIds: {'b', 'a', 'c'});
      const b = EventDigest(id: 'd1', categoryIds: {'c', 'b', 'a'});
      expect(a.encodePayload(), b.encodePayload());
    });

    test('an unknown cadence is monthly', () {
      final decoded = decode({'cadence': 'hourly', 'anchor': 12});
      expect(decoded.cadence, DigestCadence.monthly);
      expect(decoded.anchor, 12);
    });

    test('an unknown key is ignored', () {
      final decoded = decode({'cadence': 'daily', 'mode': 'ring'});
      expect(decoded.cadence, DigestCadence.daily);
    });
  });

  group('clamps', () {
    test('a weekly anchor stays within Monday..Sunday', () {
      expect(
        decode({'cadence': 'weekly', 'anchor': 0}).anchor,
        DateTime.monday,
      );
      expect(
        decode({'cadence': 'weekly', 'anchor': 9}).anchor,
        DateTime.sunday,
      );
      expect(decode({'cadence': 'weekly'}).anchor, DateTime.monday);
    });

    test('a monthly anchor stays within the days every month has', () {
      expect(decode({'cadence': 'monthly', 'anchor': 31}).anchor, 28);
      expect(decode({'cadence': 'monthly', 'anchor': -2}).anchor, 1);
      expect(decode({'cadence': 'monthly'}).anchor, 1);
    });

    test('a daily digest has no anchor', () {
      expect(decode({'cadence': 'daily', 'anchor': 5}).anchor, 0);
    });

    test('the minute stays within the day', () {
      expect(decode({'minute': 2000}).minute, Duration.minutesPerDay - 1);
      expect(decode({'minute': -1}).minute, 0);
      expect(decode({'minute': 'nine'}).minute, kDefaultAlertDayMinute);
    });

    test('the lead stays within a week', () {
      expect(decode({'leadDays': 30}).leadDays, EventDigest.maxLeadDays);
      expect(decode({'leadDays': -1}).leadDays, 0);
      expect(decode({'leadDays': 1}).leadDays, 1);
    });

    test('a malformed category list keeps only real ids', () {
      final decoded = decode({
        'categories': ['birthday', '', 7, null, 'gym'],
      });
      expect(decoded.categoryIds, {'birthday', 'gym'});
      expect(decode({'categories': 'birthday'}).categoryIds, isEmpty);
    });
  });

  group('an unreadable payload', () {
    for (final payload in ['', 'not json', '[1, 2]', '"monthly"']) {
      test('"$payload" is monthly on the 1st at 09:00 over everything', () {
        final decoded = decode(payload, name: 'Kept');

        expect(decoded.name, 'Kept', reason: 'the row survives its payload');
        expect(decoded.cadence, DigestCadence.monthly);
        expect(decoded.anchor, 1);
        expect(decoded.minute, kDefaultAlertDayMinute);
        expect(decoded.leadDays, 0);
        expect(decoded.categoryIds, isEmpty);
        expect(decoded.includeEmpty, isFalse);
      });
    }
  });

  group('a payload this version cannot read decodes disabled', () {
    EventDigest enabledRow(String payload) =>
        EventDigest.fromRow(id: 'd1', name: '', payload: payload);

    test('an empty or malformed payload, whatever the row says', () {
      expect(enabledRow('').enabled, isFalse);
      expect(enabledRow('not json').enabled, isFalse);
      expect(enabledRow('[1, 2]').enabled, isFalse);
    });

    test('an unknown or absent cadence', () {
      expect(enabledRow('{"cadence":"hourly"}').enabled, isFalse);
      expect(enabledRow('{"minute":480}').enabled, isFalse);
    });

    test('a cadence it knows keeps the row\'s switch', () {
      for (final cadence in DigestCadence.values) {
        final payload = '{"cadence":"${cadence.name}"}';
        expect(enabledRow(payload).enabled, isTrue, reason: cadence.name);
        expect(
          EventDigest.fromRow(
            id: 'd1',
            name: '',
            payload: payload,
            enabled: false,
          ).enabled,
          isFalse,
        );
      }
    });
  });

  test('DigestCadence.fromName reads every name and nothing else', () {
    for (final cadence in DigestCadence.values) {
      expect(DigestCadence.fromName(cadence.name), cadence);
    }
    expect(DigestCadence.fromName(null), DigestCadence.monthly);
  });
}
