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

  test('the tint flag rides along and reads as on when absent', () {
    final untinted = AlertPayload(
      database: 'gym_notes',
      eventId: 'e1',
      alertId: 'a1',
      dayUtcMs: 1789862400000,
      osId: 1234,
      mode: AlertMode.ring,
      title: 'Leg day',
      timeLabel: '18:00',
      colorValue: 0xFF00FF00,
      tintIcon: false,
      categoryId: 'gym',
    );

    expect(AlertPayload.decode(untinted.encode())!.tintIcon, isFalse);
    expect(untinted.copyWith(snooze: true).tintIcon, isFalse);

    // An entry armed before the flag existed carries no key: the model's own
    // default, so nothing already on the phone changes colour.
    final legacy = payloadOf().toJson()..remove('tintIcon');
    expect(AlertPayload.fromJson(legacy)!.tintIcon, isTrue);
  });

  test('the icon colour follows the in-app rule', () {
    const category = 0xFF0000FF;
    expect(payloadOf().iconColorValue(category), 0xFF00FF00);
    final untinted = AlertPayload.fromJson(
      payloadOf().toJson()..['tintIcon'] = false,
    )!;
    expect(untinted.iconColorValue(category), category);
    final plain = AlertPayload.fromJson(
      payloadOf().toJson()..['colorValue'] = null,
    )!;
    expect(plain.iconColorValue(category), category);
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

  // An entry of another database and a standing snooze are never re-armed, so
  // a payload written before these fields existed can ring long after: every
  // one of them is optional, absent from the wire while it says nothing, and
  // read back as "say what you always said".
  group('the optional facts', () {
    /// What the build before these fields wrote for [payloadOf], byte for
    /// byte — the string a phone is still holding.
    const before =
        '{"db":"gym_notes","eventId":"e1","alertId":"a1",'
        '"dayUtcMs":1789862400000,"osId":1234,"mode":"ring",'
        '"title":"Leg day","timeLabel":"18:00","colorValue":4278255360,'
        '"tintIcon":true,"iconKey":"alarm","categoryId":"gym",'
        '"removeAfterAlert":true,"snooze":true,"snoozeMin":10,'
        '"notice":false}';

    AlertPayload stamped() => payloadOf().copyWith(
      fireAtMs: DateTime(2026, 9, 20, 18).millisecondsSinceEpoch,
      reRing: true,
      whenLabel: '18:00 – 19:30',
      tintValue: 0xFF00897B,
      glyphKey: 'fitness_center',
      languageCode: 'de',
      iconFile: '/data/alert_icons/fitness_center_ff00897b.png',
    );

    test('a payload with none of them encodes to what it always did', () {
      expect(payloadOf().encode(), before);
    });

    test('and what a phone already holds decodes to the same object', () {
      final decoded = AlertPayload.decode(before);

      expect(decoded, payloadOf());
      expect(decoded!.fireAtMs, isNull);
      expect(decoded.reRing, isFalse);
      expect(decoded.whenLabel, '');
      expect(decoded.tintValue, isNull);
      expect(decoded.glyphKey, isNull);
      expect(decoded.languageCode, isNull);
      expect(decoded.iconFile, isNull);
    });

    test('every one of them survives the wire', () {
      final decoded = AlertPayload.decode(stamped().encode());

      expect(decoded, stamped());
      // Spelled out as well: `Equatable` agrees about two payloads that both
      // dropped the same field.
      expect(
        decoded!.fireAtMs,
        DateTime(2026, 9, 20, 18).millisecondsSinceEpoch,
      );
      expect(decoded.reRing, isTrue);
      expect(decoded.whenLabel, '18:00 – 19:30');
      expect(decoded.tintValue, 0xFF00897B);
      expect(decoded.glyphKey, 'fitness_center');
      expect(decoded.languageCode, 'de');
      expect(decoded.iconFile, '/data/alert_icons/fitness_center_ff00897b.png');
    });

    test('each goes on the wire under its own short key', () {
      final json = stamped().toJson();

      expect(json['fireAt'], DateTime(2026, 9, 20, 18).millisecondsSinceEpoch);
      expect(json['reRing'], isTrue);
      expect(json['when'], '18:00 – 19:30');
      expect(json['tint'], 0xFF00897B);
      expect(json['glyph'], 'fitness_center');
      expect(json['lang'], 'de');
      expect(json['iconFile'], '/data/alert_icons/fitness_center_ff00897b.png');
    });

    test('reRing is written only when true', () {
      expect(payloadOf().toJson().containsKey('reRing'), isFalse);
      expect(
        payloadOf().copyWith(reRing: false).toJson().containsKey('reRing'),
        isFalse,
      );
      expect(payloadOf().copyWith(reRing: true).toJson()['reRing'], isTrue);
      // Anything but a literal true on the wire is "not a re-ring": the mark
      // may be missing, it may never be wrong.
      for (final written in [false, null, 'true', 1]) {
        final map = payloadOf().toJson()..['reRing'] = written;
        expect(AlertPayload.fromJson(map)!.reRing, isFalse, reason: '$written');
      }
    });

    test('the event time is left out while it is empty', () {
      expect(payloadOf().toJson().containsKey('when'), isFalse);
      expect(
        payloadOf().copyWith(whenLabel: '').toJson().containsKey('when'),
        isFalse,
      );
      expect(
        payloadOf().copyWith(whenLabel: 'All day').toJson()['when'],
        'All day',
      );
    });

    test('a value of the wrong kind reads as absent, never as a crash', () {
      final map = payloadOf().toJson()
        ..['fireAt'] = '2026-09-20'
        ..['when'] = 1800
        ..['tint'] = '#00897B'
        ..['glyph'] = 7
        ..['lang'] = false
        ..['iconFile'] = const <String>[];

      final decoded = AlertPayload.fromJson(map);

      expect(decoded, payloadOf());
    });

    test('copyWith carries them, and changes only the one it is given', () {
      final moved = stamped().copyWith(
        fireAtMs: DateTime(2026, 9, 20, 18, 10).millisecondsSinceEpoch,
      );

      expect(
        moved.fireAtMs,
        DateTime(2026, 9, 20, 18, 10).millisecondsSinceEpoch,
      );
      expect(moved.reRing, isTrue);
      expect(moved.whenLabel, '18:00 – 19:30');
      expect(moved.tintValue, 0xFF00897B);
      expect(moved.glyphKey, 'fitness_center');
      expect(moved.languageCode, 'de');
      expect(moved.iconFile, '/data/alert_icons/fitness_center_ff00897b.png');
      // The mark is the one of them a copy has to be able to take back: a
      // snooze of a re-ring is not itself one.
      expect(stamped().copyWith(reRing: false).reRing, isFalse);
      expect(stamped().copyWith(osId: 7), isNot(stamped()));
      expect(stamped().copyWith(osId: 7).copyWith(osId: 1234), stamped());
    });

    test('two payloads that differ in one of them are not equal', () {
      final base = stamped();
      final others = <String, AlertPayload>{
        'fireAtMs': base.copyWith(fireAtMs: 1),
        'reRing': base.copyWith(reRing: false),
        'whenLabel': base.copyWith(whenLabel: 'All day'),
        'tintValue': base.copyWith(tintValue: 0xFF000000),
        'glyphKey': base.copyWith(glyphKey: 'alarm'),
        'languageCode': base.copyWith(languageCode: 'ro'),
        'iconFile': base.copyWith(iconFile: '/elsewhere.png'),
      };

      for (final entry in others.entries) {
        expect(entry.value, isNot(base), reason: entry.key);
      }
    });

    test('nor two that differ only in whether the colour tints the icon', () {
      // The flag was on the wire and in the constructor but missing from the
      // comparison, so two payloads that draw different avatars were equal.
      final tinted = payloadOf();
      final untinted = AlertPayload.fromJson(
        payloadOf().toJson()..['tintIcon'] = false,
      )!;

      expect(untinted.tintIcon, isFalse);
      expect(untinted, isNot(tinted));
    });

    // Whether a reminder was armed in the app's notification group, which
    // the isolate that re-posts a snoozed one can only learn from here.
    group('the group mark', () {
      test('an entry armed before it existed reads as loose, and is written '
          'back as it was', () {
        final held = AlertPayload.decode(before)!;

        expect(held.grouped, isFalse);
        expect(held.encode(), before);
        // And one armed since, by a build that stamps everything else, on a
        // phone that does not group.
        expect(AlertPayload.decode(stamped().encode())!.grouped, isFalse);
        expect(stamped().toJson().containsKey('grp'), isFalse);
      });

      test('is written only when true, under its own short key', () {
        expect(payloadOf().toJson().containsKey('grp'), isFalse);
        expect(
          payloadOf().copyWith(grouped: false).toJson().containsKey('grp'),
          isFalse,
        );
        expect(payloadOf().copyWith(grouped: true).toJson()['grp'], isTrue);
        // Anything but a literal true on the wire is the loose reminder
        // every phone had before: a group key is never guessed at.
        for (final written in [false, null, 'true', 1]) {
          final map = payloadOf().toJson()..['grp'] = written;
          expect(
            AlertPayload.fromJson(map)!.grouped,
            isFalse,
            reason: '$written',
          );
        }
      });

      test('survives the wire', () {
        final inGroup = stamped().copyWith(grouped: true);
        final decoded = AlertPayload.decode(inGroup.encode());

        expect(decoded, inGroup);
        expect(decoded!.grouped, isTrue);
      });

      test('is carried by a copy, which can also take it back', () {
        final inGroup = stamped().copyWith(grouped: true);

        // What a snooze and a moved ring are made with.
        expect(inGroup.copyWith(osId: 7, snooze: true).grouped, isTrue);
        expect(
          inGroup.copyWith(fireAtMs: 1, timeLabel: '18:10').grouped,
          isTrue,
        );
        expect(inGroup.copyWith(grouped: false).grouped, isFalse);
        expect(stamped().copyWith(osId: 7).grouped, isFalse);
      });

      test('tells two payloads apart', () {
        expect(stamped().copyWith(grouped: true), isNot(stamped()));
      });
    });
  });

  group('an inherited alert', () {
    test('is written only when true, under its own short key', () {
      expect(payloadOf().toJson().containsKey('inh'), isFalse);
      final inherited = payloadOf().copyWith(inherited: true);
      expect(inherited.toJson()['inh'], isTrue);
    });

    test('survives the wire and a copy, and reads as own when absent', () {
      final inherited = payloadOf().copyWith(inherited: true);

      expect(AlertPayload.decode(inherited.encode()), inherited);
      expect(AlertPayload.decode(inherited.encode())!.inherited, isTrue);
      expect(inherited.copyWith(osId: 9).inherited, isTrue);
      expect(AlertPayload.decode(payloadOf().encode())!.inherited, isFalse);
      expect(inherited, isNot(payloadOf()));
    });
  });

  // A digest (v42) is one more set of optional facts: an alert's payload
  // never carries them, and one written before them reads as no digest.
  group('a digest', () {
    final spanStart = DateTime.utc(2026, 10, 1).millisecondsSinceEpoch;
    final spanEnd = DateTime.utc(2026, 10, 31).millisecondsSinceEpoch;

    AlertPayload digestOf() => AlertPayload(
      database: 'gym_notes',
      eventId: '',
      alertId: 'd1',
      dayUtcMs: spanStart,
      osId: 77,
      mode: AlertMode.notify,
      title: 'Birthdays',
      timeLabel: '09:00',
      categoryId: 'birthday',
      isDigest: true,
      digestId: 'd1',
      spanStartMs: spanStart,
      spanEndMs: spanEnd,
      categoryIdsCsv: 'birthday,family',
      digestText: '2 events this month · Sun, Oct 4 · Ana, Mon, Oct 12 · Mihai',
      digestLines: const ['Sun, Oct 4 · Ana', 'Mon, Oct 12 · Mihai'],
      digestSummary: '+2 more',
    );

    test('round-trips through the wire form', () {
      final decoded = AlertPayload.decode(digestOf().encode());

      expect(decoded, digestOf());
      expect(decoded!.isDigest, isTrue);
      expect(decoded.eventId, '');
      expect(decoded.digestLines, ['Sun, Oct 4 · Ana', 'Mon, Oct 12 · Mihai']);
      expect(decoded.digestSummary, '+2 more');
      expect(decoded.categoryIdSet, {'birthday', 'family'});
    });

    test('each goes on the wire under its own short key', () {
      final json = digestOf().toJson();

      expect(json['dg'], isTrue);
      expect(json['di'], 'd1');
      expect(json['ss'], spanStart);
      expect(json['se'], spanEnd);
      expect(json['cat'], 'birthday,family');
      expect(json['dtx'], startsWith('2 events'));
      expect(json['dln'], hasLength(2));
      expect(json['dsm'], '+2 more');
    });

    test("an alert's payload carries none of them, and reads as no digest",
        () {
      final json = payloadOf().toJson();
      for (final key in ['dg', 'di', 'ss', 'se', 'cat', 'dtx', 'dln', 'dsm']) {
        expect(json.containsKey(key), isFalse, reason: key);
      }

      final decoded = AlertPayload.fromJson(json)!;
      expect(decoded.isDigest, isFalse);
      expect(decoded.digestId, isNull);
      expect(decoded.spanStartMs, isNull);
      expect(decoded.spanEndMs, isNull);
      expect(decoded.categoryIdsCsv, isNull);
      expect(decoded.categoryIdSet, isEmpty);
      expect(decoded.digestText, isNull);
      expect(decoded.digestLines, isEmpty);
      expect(decoded.digestSummary, isNull);
    });

    test("a report digest's page rides under its own key; absent is the "
        'overview', () {
      final report = AlertPayload.fromJson(
        digestOf().toJson()..['pg'] = AlertPayload.reportPage,
      )!;

      expect(report.page, 'report');
      expect(report.toJson()['pg'], 'report');
      expect(AlertPayload.decode(report.encode()), report);
      expect(report.copyWith(osId: 9).page, 'report');
      expect(report, isNot(digestOf()));

      // Without it — every entry armed before it existed — nothing changes.
      expect(digestOf().toJson().containsKey('pg'), isFalse);
      expect(AlertPayload.decode(digestOf().encode())!.page, isNull);
      expect(AlertPayload.decode(digestOf().encode()), digestOf());
      final wrongKind = digestOf().toJson()..['pg'] = 3;
      expect(AlertPayload.fromJson(wrongKind)!.page, isNull);
    });

    test('an empty event id is an identity only for a digest', () {
      expect(AlertPayload.decode(digestOf().encode()), isNotNull);
      final alert = digestOf().toJson()..remove('dg');
      expect(AlertPayload.fromJson(alert), isNull);
    });

    test('lines of the wrong kind are dropped, never a crash', () {
      final map = digestOf().toJson()..['dln'] = ['Sun, Oct 4 · Ana', 3, null];
      expect(AlertPayload.fromJson(map)!.digestLines, ['Sun, Oct 4 · Ana']);
      final broken = digestOf().toJson()..['dln'] = 'not a list';
      expect(AlertPayload.fromJson(broken)!.digestLines, isEmpty);
    });

    test('copyWith carries them', () {
      final copy = digestOf().copyWith(
        osId: 78,
        iconFile: '/data/alert_icons/cake.png',
        grouped: true,
      );

      expect(copy.isDigest, isTrue);
      expect(copy.digestId, 'd1');
      expect(copy.spanStartMs, spanStart);
      expect(copy.spanEndMs, spanEnd);
      expect(copy.categoryIdsCsv, 'birthday,family');
      expect(copy.digestText, digestOf().digestText);
      expect(copy.digestLines, digestOf().digestLines);
      expect(copy.digestSummary, '+2 more');
    });
  });
}
