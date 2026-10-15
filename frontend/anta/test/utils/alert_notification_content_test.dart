import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/utils/alert_notification_content.dart';

/// The words of every alert notification, in the one grammar they share
/// (`docs/alert-surfaces-redesign-roadmap.md` §3.5): the event's title; under
/// it what the notification is and the time it is about; the description's
/// first line added under that when it is expanded; the button that settles
/// first.
///
/// **Every literal here is what a phone shows.** The composer is the first
/// place a notification's words can be tested at all — the binding that posts
/// them cannot be constructed off a device — and it was written in two steps:
/// first it reproduced, word for word, what the binding composed inline
/// (titles such as "Missed: Leg day" over "It was due at 07:00", a reminder
/// whose text was the minute it fired, Snooze before Done), pinned by this
/// suite as it then stood; then it was changed to the grammar below and these
/// pins with it, on purpose.
///
/// The times are literals too, because the composer formats nothing: it
/// places lines that were written when the entry was armed.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));
  final ro = lookupAppLocalizations(const Locale('ro'));

  /// An entry of an event at 18:00 that lasts an hour and a half, due ten
  /// minutes ahead of it — so the alarm's own time and the event's are two
  /// different lines.
  AlertPayload payloadOf({
    AlertMode mode = AlertMode.ring,
    String eventId = 'e1',
    String title = 'Leg day',
    String timeLabel = '17:50',
    String whenLabel = '18:00 – 19:30',
    String excerpt = '',
    int snoozeMinutes = 10,
  }) => AlertPayload(
    database: 'gym_notes',
    eventId: eventId,
    alertId: 'a1',
    dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
    osId: 7,
    mode: mode,
    title: title,
    timeLabel: timeLabel,
    categoryId: 'gym',
    excerpt: excerpt,
    snoozeMinutes: snoozeMinutes,
    fireAtMs: DateTime(2026, 9, 20, 17, 50).millisecondsSinceEpoch,
    whenLabel: whenLabel,
    tintValue: 0xFF00897B,
    glyphKey: 'fitness_center',
    languageCode: 'en',
  );

  /// What a build from before the payload carried the event's time, a tint
  /// or a language armed: the due time is all it has.
  AlertPayload olderOf({
    AlertMode mode = AlertMode.ring,
    String excerpt = '',
  }) => AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
    osId: 7,
    mode: mode,
    title: 'Leg day',
    timeLabel: '17:50',
    categoryId: 'gym',
    excerpt: excerpt,
  );

  List<String> labels(AlertNotificationContent content) => [
    for (final action in content.actions) action.label,
  ];

  List<AlertNotificationAction> actions(AlertNotificationContent content) => [
    for (final action in content.actions) action.action,
  ];

  group('the ring', () {
    AlertNotificationContent ring(
      AppLocalizations strings, [
      AlertPayload? payload,
    ]) => alertNotificationContent(
      AlertNotificationKind.ring,
      payload ?? payloadOf(excerpt: 'Squats first.'),
      strings,
    );

    test("is the event's title over what it is and the event's own time", () {
      expect(ring(en).title, 'Leg day');
      expect(ring(en).text, 'Alarm · 18:00 – 19:30');
      expect(ring(de).text, 'Alarm · 18:00 – 19:30');
      expect(ring(ro).text, 'Alarmă · 18:00 – 19:30');
    });

    test('has nothing to expand to: the plugin draws two lines', () {
      expect(ring(en).expandedText, isNull);
    });

    test('offers Stop, then a Snooze that names its length', () {
      expect(actions(ring(en)), [
        AlertNotificationAction.stop,
        AlertNotificationAction.snooze,
      ]);
      expect(labels(ring(en)), ['Stop', 'Snooze 10 min']);
      expect(labels(ring(de)), ['Stopp', '10 Min. schlummern']);
      expect(labels(ring(ro)), ['Oprește', 'Amână 10 min']);
      expect(
        labels(ring(en, payloadOf(snoozeMinutes: 1))).last,
        'Snooze 1 min',
      );
      // Romanian counts in three forms.
      expect(labels(ring(ro, payloadOf(snoozeMinutes: 1))).last, 'Amână 1 min');
      expect(
        labels(ring(ro, payloadOf(snoozeMinutes: 20))).last,
        'Amână 20 de min',
      );
    });

    test(
      "names the alarm's own time where the event's would only repeat it",
      () {
        // An alert at the event's start leaves the event's time out of its
        // payload, as a repeat of the due time.
        final atStart = payloadOf(timeLabel: '18:00', whenLabel: '');

        expect(ring(en, atStart).text, 'Alarm · 18:00');
      },
    );

    test('carries the day when the event is not on the day it rings', () {
      // The labels write that day first, so placed after the kind it is what
      // a one-line row still shows when the platform cuts the end of it.
      final dayBefore = payloadOf(
        timeLabel: '09:00',
        whenLabel: 'Mon, Sep 21 · All day',
      );

      expect(ring(en, dayBefore).text, 'Alarm · Mon, Sep 21 · All day');
    });
  });

  group('a test ring', () {
    final testRing = payloadOf(
      eventId: AlertPayload.testEventId,
      // What the settings page arms it with: its own button's label.
      title: 'Test alarm in 10 s',
      timeLabel: '7:05 PM',
      whenLabel: '',
    );

    test('is called a test alarm, never by the button that armed it', () {
      final content = alertNotificationContent(
        AlertNotificationKind.ring,
        testRing,
        en,
      );

      expect(content.title, 'Test alarm');
      expect(content.text, 'Alarm · 7:05 PM');
      expect(labels(content), ['Stop', 'Snooze 10 min']);
      expect(
        alertNotificationContent(
          AlertNotificationKind.ring,
          testRing,
          de,
        ).title,
        'Testalarm',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.ring,
          testRing,
          ro,
        ).title,
        'Alarmă de test',
      );
    });

    test('is called that by every kind', () {
      for (final kind in AlertNotificationKind.values) {
        expect(
          alertNotificationContent(kind, testRing, en).title,
          'Test alarm',
          reason: kind.name,
        );
      }
    });
  });

  group('the reminder', () {
    AlertNotificationContent reminder(
      AppLocalizations strings, {
      String excerpt = 'Squats first.',
    }) => alertNotificationContent(
      AlertNotificationKind.reminder,
      payloadOf(mode: AlertMode.notify, excerpt: excerpt),
      strings,
    );

    test("is the event's title over what it is and the event's own time, "
        'not the minute it fired', () {
      // The header's own clock already says when it fired.
      expect(reminder(en).title, 'Leg day');
      expect(reminder(en).text, 'Reminder · 18:00 – 19:30');
      expect(reminder(de).text, 'Mitteilung · 18:00 – 19:30');
      expect(reminder(ro).text, 'Notificare · 18:00 – 19:30');
    });

    test('expanded, keeps that line and adds the description under it', () {
      expect(
        reminder(en).expandedText,
        'Reminder · 18:00 – 19:30\nSquats first.',
      );
      expect(
        reminder(de).expandedText,
        'Mitteilung · 18:00 – 19:30\nSquats first.',
      );
      // Nothing to add, nothing to expand to.
      expect(reminder(en, excerpt: '').expandedText, isNull);
    });

    test('offers Done, then a Snooze that names its length', () {
      expect(actions(reminder(en)), [
        AlertNotificationAction.done,
        AlertNotificationAction.snooze,
      ]);
      expect(labels(reminder(en)), ['Done', 'Snooze 10 min']);
      expect(labels(reminder(de)), ['Erledigt', '10 Min. schlummern']);
      expect(labels(reminder(ro)), ['Gata', 'Amână 10 min']);
    });
  });

  group('a reminder that was snoozed', () {
    AlertNotificationContent snoozed(AppLocalizations strings) =>
        alertNotificationContent(
          AlertNotificationKind.snoozed,
          payloadOf(mode: AlertMode.notify, excerpt: 'Squats first.'),
          strings,
        );

    test('says so, and still names the event\'s time', () {
      expect(snoozed(en).title, 'Leg day');
      expect(snoozed(en).text, 'Snoozed · 18:00 – 19:30');
      expect(snoozed(de).text, 'Geschlummert · 18:00 – 19:30');
      expect(snoozed(ro).text, 'Amânată · 18:00 – 19:30');
    });

    test('keeps everything the reminder had: its description and both '
        'buttons', () {
      expect(
        snoozed(en).expandedText,
        'Snoozed · 18:00 – 19:30\nSquats first.',
      );
      expect(labels(snoozed(en)), ['Done', 'Snooze 10 min']);
      expect(labels(snoozed(de)), ['Erledigt', '10 Min. schlummern']);
      expect(labels(snoozed(ro)), ['Gata', 'Amână 10 min']);
    });
  });

  group('the upcoming notice', () {
    AlertNotificationContent notice(
      AppLocalizations strings, {
      String? dayLabel,
      String excerpt = 'Squats first.',
    }) => alertNotificationContent(
      AlertNotificationKind.notice,
      payloadOf(excerpt: excerpt),
      strings,
      dayLabel: dayLabel,
    );

    test("is the event's title over the time its alarm will ring at", () {
      // The alarm's own time, not the event's: the notice is about a ring
      // that is ahead.
      expect(notice(en).title, 'Leg day');
      expect(notice(en).text, 'Alarm at 17:50');
      expect(notice(de).text, 'Alarm um 17:50');
      expect(notice(ro).text, 'Alarmă la 17:50');
    });

    test('names the day too when the alarm is not due on the day it is '
        'posted', () {
      expect(
        notice(en, dayLabel: 'Mon, Sep 21').text,
        'Alarm at 17:50, Mon, Sep 21',
      );
      expect(
        notice(de, dayLabel: 'Mo., 21. Sept.').text,
        'Alarm um 17:50, Mo., 21. Sept.',
      );
      expect(
        notice(ro, dayLabel: 'lun., 21 sept.').text,
        'Alarmă la 17:50, lun., 21 sept.',
      );
    });

    test('expanded, adds the description under that line', () {
      expect(notice(en).expandedText, 'Alarm at 17:50\nSquats first.');
      expect(
        notice(en, dayLabel: 'Mon, Sep 21').expandedText,
        'Alarm at 17:50, Mon, Sep 21\nSquats first.',
      );
      expect(notice(en, excerpt: '').expandedText, isNull);
    });

    test('offers Skip, then Open', () {
      expect(actions(notice(en)), [
        AlertNotificationAction.skip,
        AlertNotificationAction.open,
      ]);
      expect(labels(notice(en)), ['Skip', 'Open']);
      expect(labels(notice(de)), ['Überspringen', 'Öffnen']);
      expect(labels(notice(ro)), ['Sari', 'Deschide']);
    });
  });

  group('Missed', () {
    AlertNotificationContent missed(
      AppLocalizations strings, {
      String excerpt = 'Squats first.',
    }) => alertNotificationContent(
      AlertNotificationKind.missed,
      payloadOf(excerpt: excerpt),
      strings,
    );

    test("is the event's title over the time the alarm was due at", () {
      expect(missed(en).title, 'Leg day');
      expect(missed(en).text, 'Missed · 17:50');
      expect(missed(de).text, 'Verpasst · 17:50');
      expect(missed(ro).text, 'Ratată · 17:50');
    });

    test('expanded, adds the description under that line', () {
      expect(missed(en).expandedText, 'Missed · 17:50\nSquats first.');
      expect(missed(en, excerpt: '').expandedText, isNull);
    });

    test('has no button: there is nothing left to answer', () {
      expect(missed(en).actions, isEmpty);
    });
  });

  group('the session chip', () {
    AlertNotificationContent chip(
      AppLocalizations strings, {
      String? untilLabel,
      bool linkedNote = false,
    }) => alertNotificationContent(
      AlertNotificationKind.sessionChip,
      payloadOf(excerpt: 'Squats first.'),
      strings,
      untilLabel: untilLabel,
      linkedNote: linkedNote,
    );

    test("is the event's title over when the session ends", () {
      expect(chip(en, untilLabel: '19:30').title, 'Leg day');
      expect(chip(en, untilLabel: '19:30').text, 'Until 19:30');
      expect(chip(en, untilLabel: '7:30 PM').text, 'Until 7:30 PM');
      expect(chip(de, untilLabel: '19:30').text, 'Bis 19:30');
      expect(chip(ro, untilLabel: '19:30').text, 'Până la 19:30');
    });

    test('says a session is under way when the event has no end', () {
      expect(chip(en).text, 'Session in progress');
      expect(chip(de).text, 'Einheit läuft');
      expect(chip(ro).text, 'Sesiune în curs');
    });

    test('offers Done, then the note when the event links one', () {
      final linked = chip(en, linkedNote: true);

      expect(actions(linked), [
        AlertNotificationAction.done,
        AlertNotificationAction.open,
      ]);
      expect(labels(linked), ['Done', 'Open note']);
      expect(labels(chip(de, linkedNote: true)), ['Erledigt', 'Notiz öffnen']);
      expect(labels(chip(ro, linkedNote: true)), ['Gata', 'Deschide notița']);
    });

    test('offers the event itself when there is no note to open', () {
      // It read "Open note" whatever it opened, and opened the event's day.
      expect(labels(chip(en)), ['Done', 'Open event']);
      expect(labels(chip(de)), ['Erledigt', 'Termin öffnen']);
      expect(labels(chip(ro)), ['Gata', 'Deschide evenimentul']);
    });

    test('expands to nothing', () {
      expect(chip(en, untilLabel: '19:30').expandedText, isNull);
    });
  });

  group('a digest', () {
    // Its words were written whole when it was armed (`digestNotificationContent`);
    // here they are only placed, in any language the call names.
    final digest = AlertPayload(
      database: 'gym_notes',
      eventId: '',
      alertId: 'd1',
      dayUtcMs: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
      osId: 9,
      mode: AlertMode.notify,
      title: 'Birthdays',
      timeLabel: '09:00',
      categoryId: 'birthday',
      isDigest: true,
      digestText: '2 events this month · Sun, Oct 4 · Ana, Mon, Oct 12 · Mihai',
      digestLines: const ['Sun, Oct 4 · Ana', 'Mon, Oct 12 · Mihai'],
      digestSummary: '+1 more',
    );

    test('places the title, the text, the lines and the summary it carries',
        () {
      for (final strings in [en, de]) {
        final content = alertNotificationContent(
          AlertNotificationKind.digest,
          digest,
          strings,
        );
        expect(content.title, 'Birthdays');
        expect(content.text, digest.digestText);
        expect(content.lines, digest.digestLines);
        expect(content.summary, '+1 more');
        expect(content.expandedText, isNull);
        expect(content.actions, isEmpty);
      }
    });

    test('a payload that lost its words is an empty line, never a crash', () {
      final bare = AlertPayload.fromJson(
        digest.toJson()
          ..remove('dtx')
          ..remove('dln')
          ..remove('dsm'),
      )!;
      final content = alertNotificationContent(
        AlertNotificationKind.digest,
        bare,
        en,
      );

      expect(content.text, '');
      expect(content.lines, isEmpty);
      expect(content.summary, isNull);
    });

    test('every other kind has no lines', () {
      for (final kind in AlertNotificationKind.values) {
        if (kind == AlertNotificationKind.digest) continue;
        final content = alertNotificationContent(kind, payloadOf(), en);
        expect(content.lines, isEmpty, reason: kind.name);
        expect(content.summary, isNull, reason: kind.name);
      }
    });
  });

  group('the fallback alarm', () {
    AlertNotificationContent fallback(AppLocalizations strings) =>
        alertNotificationContent(
          AlertNotificationKind.fallbackAlarm,
          payloadOf(excerpt: 'Squats first.'),
          strings,
        );

    test("reads as the ring does, with the description when expanded", () {
      expect(fallback(en).title, 'Leg day');
      expect(fallback(en).text, 'Alarm · 18:00 – 19:30');
      expect(fallback(ro).text, 'Alarmă · 18:00 – 19:30');
      expect(fallback(en).expandedText, 'Alarm · 18:00 – 19:30\nSquats first.');
    });

    test('offers Stop alone', () {
      expect(actions(fallback(en)), [AlertNotificationAction.stop]);
      expect(labels(fallback(en)), ['Stop']);
      expect(labels(fallback(de)), ['Stopp']);
      expect(labels(fallback(ro)), ['Oprește']);
    });
  });

  group('an entry armed by an older build', () {
    // Another database's entries and standing snoozes are never armed again,
    // so a payload with none of the newer lines can be posted for years.
    test('names the one time it carries, wherever a time is named', () {
      expect(
        alertNotificationContent(
          AlertNotificationKind.ring,
          olderOf(),
          en,
        ).text,
        'Alarm · 17:50',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.reminder,
          olderOf(mode: AlertMode.notify),
          en,
        ).text,
        'Reminder · 17:50',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.snoozed,
          olderOf(mode: AlertMode.notify),
          de,
        ).text,
        'Geschlummert · 17:50',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.notice,
          olderOf(),
          ro,
        ).text,
        'Alarmă la 17:50',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.missed,
          olderOf(),
          en,
        ).text,
        'Missed · 17:50',
      );
    });

    test('still expands to its description', () {
      expect(
        alertNotificationContent(
          AlertNotificationKind.reminder,
          olderOf(mode: AlertMode.notify, excerpt: 'Squats first.'),
          en,
        ).expandedText,
        'Reminder · 17:50\nSquats first.',
      );
    });
  });

  group('an event nobody titled', () {
    test('is named by its tier, in the language of the notification', () {
      final alarm = payloadOf(title: '');
      final reminder = payloadOf(mode: AlertMode.notify, title: '   ');

      expect(
        alertNotificationContent(AlertNotificationKind.ring, alarm, en).title,
        'Alarm',
      );
      expect(
        alertNotificationContent(AlertNotificationKind.notice, alarm, ro).title,
        'Alarmă',
      );
      expect(
        alertNotificationContent(AlertNotificationKind.missed, alarm, de).title,
        'Alarm',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.sessionChip,
          alarm,
          en,
        ).title,
        'Alarm',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.reminder,
          reminder,
          en,
        ).title,
        'Reminder',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.snoozed,
          reminder,
          de,
        ).title,
        'Mitteilung',
      );
    });
  });

  group('an entry that carries no time at all', () {
    // A payload the platform truncated decodes with empty lines.
    final timeless = payloadOf(timeLabel: '', whenLabel: '');

    test('names what it is and trails no separator', () {
      expect(
        alertNotificationContent(AlertNotificationKind.ring, timeless, en).text,
        'Alarm',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.reminder,
          timeless,
          en,
        ).text,
        'Reminder',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.snoozed,
          timeless,
          de,
        ).text,
        'Geschlummert',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.missed,
          timeless,
          ro,
        ).text,
        'Ratată',
      );
      expect(
        alertNotificationContent(
          AlertNotificationKind.notice,
          timeless,
          en,
          dayLabel: 'Mon, Sep 21',
        ).text,
        'Alarm',
      );
    });
  });

  test('a content answers for each of its buttons by what it does', () {
    final reminder = alertNotificationContent(
      AlertNotificationKind.reminder,
      payloadOf(mode: AlertMode.notify),
      en,
    );

    expect(reminder.labelOf(AlertNotificationAction.done), 'Done');
    expect(reminder.labelOf(AlertNotificationAction.snooze), 'Snooze 10 min');
    expect(reminder.labelOf(AlertNotificationAction.stop), isNull);
  });

  test('the composer reads nothing but the payload and the strings', () {
    // What lets the reminder's Snooze call it from an isolate with no
    // database and no date symbols: the same payload gives the same words
    // after a trip through the wire form the platform stores.
    final payload = payloadOf(mode: AlertMode.notify, excerpt: 'Squats first.');
    final decoded = AlertPayload.decode(payload.encode())!;

    for (final kind in AlertNotificationKind.values) {
      final direct = alertNotificationContent(kind, payload, de);
      final wired = alertNotificationContent(kind, decoded, de);
      expect(wired.title, direct.title, reason: kind.name);
      expect(wired.text, direct.text, reason: kind.name);
      expect(wired.expandedText, direct.expandedText, reason: kind.name);
      expect(labels(wired), labels(direct), reason: kind.name);
    }
  });
}
