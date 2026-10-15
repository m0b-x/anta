import 'dart:ui' as ui;

import 'package:alarm/alarm.dart' show NotificationSettings;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/alert_sound.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/android_alert_gateway.dart';
import 'package:anta/utils/alert_notification_content.dart';
import 'package:anta/utils/alert_os_id.dart';
import 'package:anta/utils/alert_planner.dart';
import 'package:anta/widgets/event_avatar.dart';

/// How the Android binding posts each kind of alert notification.
///
/// `AndroidAlertGateway` itself cannot be built off a device, so everything
/// it decides about what a notification looks like sits above the class as
/// pure functions it only calls: the details each kind is posted with, the
/// snoozed re-post the background isolate makes, the arm context, and the
/// name and size of the avatar's file. They are what this suite pins — the
/// words themselves are `alert_notification_content_test.dart`'s.
///
/// The ids are spelled as literals here on purpose: an action id is matched
/// in a background isolate against what the platform stored days ago, and a
/// constant renamed on both sides at once would still pass.
void main() {
  final en = lookupAppLocalizations(const ui.Locale('en'));
  final de = lookupAppLocalizations(const ui.Locale('de'));

  final day = DateTime.utc(2026, 9, 20);
  final due = DateTime(2026, 9, 20, 18);

  /// A reminder at the start of "Stretch", 18:00 for a quarter of an hour,
  /// armed by a build that stamps everything.
  AlertPayload payloadOf({
    AlertMode mode = AlertMode.notify,
    String excerpt = 'Hips and hamstrings.',
    String? languageCode = 'en',
    int? tintValue = 0xFF00897B,
    String? iconFile,
    int osId = 4242,
  }) => AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: day.millisecondsSinceEpoch,
    osId: osId,
    mode: mode,
    title: 'Stretch',
    timeLabel: '18:00',
    categoryId: 'gym',
    snoozeMinutes: 5,
    excerpt: excerpt,
    fireAtMs: due.millisecondsSinceEpoch,
    whenLabel: '18:00 – 18:15',
    tintValue: tintValue,
    glyphKey: 'self_improvement',
    languageCode: languageCode,
    iconFile: iconFile,
  );

  const teal = ui.Color(0xFF00897B);
  const avatar = '/data/files/alert_icons/materialicons_e0f0_ff00897b_144.png';
  const AlertDecor dressed = (color: teal, iconFile: avatar);

  AlertNotificationContent contentOf(
    AlertNotificationKind kind, {
    AlertPayload? payload,
    AppLocalizations? strings,
    String? dayLabel,
  }) => alertNotificationContent(
    kind,
    payload ?? payloadOf(),
    strings ?? en,
    dayLabel: dayLabel,
  );

  List<String> idsOf(AndroidNotificationDetails details) => [
    for (final action in details.actions ?? const <AndroidNotificationAction>[])
      action.id,
  ];

  List<String> labelsOf(AndroidNotificationDetails details) => [
    for (final action in details.actions ?? const <AndroidNotificationAction>[])
      action.title,
  ];

  String? bigTextOf(AndroidNotificationDetails details) =>
      (details.styleInformation as BigTextStyleInformation?)?.bigText;

  String? largeIconOf(AndroidNotificationDetails details) =>
      (details.largeIcon as FilePathAndroidBitmap?)?.data;

  group('a reminder', () {
    final details = alertReminderDetails(
      en,
      contentOf(AlertNotificationKind.reminder),
      decor: dressed,
    );

    test('interrupts, on the reminder channel', () {
      expect(details.channelId, 'alerts_reminder');
      expect(details.importance, Importance.high);
      expect(details.priority, Priority.high);
      expect(details.category, AndroidNotificationCategory.reminder);
      expect(details.silent, isFalse);
      expect(details.icon, 'ic_alert');
      // Dated by its posting, standing until answered, and nothing of an
      // alarm's about it.
      expect(details.when, isNull);
      expect(details.timeoutAfter, isNull);
      expect(details.ongoing, isFalse);
      expect(details.fullScreenIntent, isFalse);
      expect(details.groupKey, isNull);
    });

    test("wears the event's colour and its avatar, as a file", () {
      expect(details.color, teal);
      expect(largeIconOf(details), avatar);
    });

    test('offers Done, then Snooze, both answered with no app at all', () {
      expect(idsOf(details), ['alert_done', 'alert_snooze']);
      expect(labelsOf(details), ['Done', 'Snooze 5 min']);
      for (final action in details.actions!) {
        // False is what routes an action to the background isolate even
        // while the app is in front.
        expect(action.showsUserInterface, isFalse, reason: action.id);
        expect(action.cancelNotification, isTrue, reason: action.id);
      }
    });

    test('expanded, shows the text line and the description under it', () {
      // The platform draws big text in place of the collapsed text, so the
      // style has to hold both.
      expect(
        bigTextOf(details),
        'Reminder · 18:00 – 18:15\nHips and hamstrings.',
      );
    });

    test('with no description has nothing to expand to', () {
      final plain = alertReminderDetails(
        en,
        contentOf(
          AlertNotificationKind.reminder,
          payload: payloadOf(excerpt: ''),
        ),
        decor: dressed,
      );

      expect(plain.styleInformation, isNull);
    });

    test('is posted bare when there is no decor to give it', () {
      final bare = alertReminderDetails(
        en,
        contentOf(AlertNotificationKind.reminder),
      );

      expect(bare.color, isNull);
      expect(bare.largeIcon, isNull);
      expect(idsOf(bare), ['alert_done', 'alert_snooze']);
    });

    test('labels its buttons in the language it is given', () {
      final german = alertReminderDetails(
        de,
        contentOf(AlertNotificationKind.reminder, strings: de),
        decor: dressed,
      );

      expect(labelsOf(german), ['Erledigt', '5 Min. schlummern']);
      expect(idsOf(german), ['alert_done', 'alert_snooze']);
    });

    test('left loose, says nothing of a group', () {
      // What it is posted as unless it is told otherwise: the reminder of a
      // phone below Android 16, and of a phone that could not say which
      // Android it is.
      expect(details.groupKey, isNull);
      expect(details.setAsGroupSummary, isFalse);
      // The plugin's own default, which it hands the platform only beside a
      // group key.
      expect(details.groupAlertBehavior, GroupAlertBehavior.all);
    });

    group("armed in the app's group", () {
      final grouped = alertReminderDetails(
        en,
        contentOf(AlertNotificationKind.reminder),
        decor: dressed,
        grouped: true,
      );

      test('names the group and alerts for itself', () {
        // The literal, as an action id is: the platform keeps the key of a
        // standing reminder, and the next one has to name the same.
        expect(grouped.groupKey, 'anta.alerts');
        expect(kAlertGroupKey, 'anta.alerts');
        expect(grouped.groupAlertBehavior, GroupAlertBehavior.children);
      });

      test('is never the summary of it', () {
        // A summary is what the key was chosen to do without: it would stay
        // behind as a row of its own once its last child left.
        expect(grouped.setAsGroupSummary, isFalse);
      });

      test('is in everything else the reminder it would be loose', () {
        expect(grouped.channelId, 'alerts_reminder');
        expect(grouped.importance, Importance.high);
        expect(grouped.priority, Priority.high);
        expect(grouped.category, AndroidNotificationCategory.reminder);
        expect(grouped.silent, isFalse);
        expect(grouped.color, teal);
        expect(largeIconOf(grouped), avatar);
        expect(idsOf(grouped), ['alert_done', 'alert_snooze']);
        expect(labelsOf(grouped), ['Done', 'Snooze 5 min']);
        expect(bigTextOf(grouped), bigTextOf(details));
      });
    });

    group('by Android release', () {
      AndroidNotificationDetails armedOn(int? sdkInt) => alertReminderDetails(
        en,
        contentOf(AlertNotificationKind.reminder),
        decor: dressed,
        grouped: alertRemindersGroupedOn(sdkInt),
      );

      test('is in the group from Android 16 on', () {
        expect(kAlertGroupMinSdk, 36);
        for (final sdkInt in [36, 37, 40]) {
          expect(alertRemindersGroupedOn(sdkInt), isTrue, reason: '$sdkInt');
          expect(armedOn(sdkInt).groupKey, 'anta.alerts', reason: '$sdkInt');
          expect(
            armedOn(sdkInt).groupAlertBehavior,
            GroupAlertBehavior.children,
            reason: '$sdkInt',
          );
        }
      });

      test('is loose below it, where nothing is bundled by force', () {
        for (final sdkInt in [24, 33, 34, 35]) {
          expect(alertRemindersGroupedOn(sdkInt), isFalse, reason: '$sdkInt');
          expect(armedOn(sdkInt).groupKey, isNull, reason: '$sdkInt');
        }
      });

      test('is loose when the release could not be read', () {
        // The safe answer: the reminder every phone posted before the group.
        expect(alertRemindersGroupedOn(null), isFalse);
        expect(armedOn(null).groupKey, isNull);
      });
    });
  });

  group('the upcoming notice', () {
    final content = contentOf(
      AlertNotificationKind.notice,
      payload: payloadOf(mode: AlertMode.ring),
    );
    final details = alertNoticeDetails(
      en,
      content,
      decor: dressed,
      timeoutAfterMillis: noticeTimeoutMillis(
        noticeAt: DateTime(2026, 9, 20, 16),
        fireAt: due,
      ),
    );

    test('is quiet: on the quiet channel, and still flagged silent', () {
      // It shared the reminder channel until 2026-10, where the flag alone
      // had to keep it quiet and, beside a second quiet notification, did
      // not.
      expect(details.channelId, 'alerts_quiet');
      expect(details.silent, isTrue);
      expect(details.importance, Importance.low);
      expect(details.priority, Priority.low);
      expect(details.category, AndroidNotificationCategory.reminder);
      expect(details.icon, 'ic_alert');
      expect(details.when, isNull);
    });

    test('names no group: the reminders\' is not for the quiet kinds', () {
      expect(details.groupKey, isNull);
      expect(details.setAsGroupSummary, isFalse);
    });

    test('goes at the instant of the alarm it announces', () {
      expect(details.timeoutAfter, const Duration(hours: 2).inMilliseconds);
    });

    test("wears the event's colour and its avatar", () {
      expect(details.color, teal);
      expect(largeIconOf(details), avatar);
    });

    test('offers Skip, then Open, and both bring the app up', () {
      expect(idsOf(details), ['alert_skip', 'alert_open']);
      expect(labelsOf(details), ['Skip', 'Open']);
      for (final action in details.actions!) {
        // Skip changes the plan, which the background isolate never does.
        expect(action.showsUserInterface, isTrue, reason: action.id);
        expect(action.cancelNotification, isTrue, reason: action.id);
      }
    });

    test('expanded, shows its line and the description under it', () {
      expect(bigTextOf(details), 'Alarm at 18:00\nHips and hamstrings.');
    });
  });

  group('a Missed notice', () {
    final content = contentOf(
      AlertNotificationKind.missed,
      payload: payloadOf(mode: AlertMode.ring),
    );
    final details = alertMissedDetails(
      en,
      content,
      decor: dressed,
      dueAtMs: due.millisecondsSinceEpoch,
    );

    test('is quiet: on the quiet channel, and still flagged silent', () {
      // It asked for low importance alone at first, on the reminder channel,
      // whose importance is frozen at high; then for the flag, which held
      // only while it stood alone.
      expect(details.channelId, 'alerts_quiet');
      expect(details.silent, isTrue);
      expect(details.importance, Importance.low);
      expect(details.priority, Priority.low);
      expect(details.icon, 'ic_alert');
    });

    test('names no group', () {
      expect(details.groupKey, isNull);
      expect(details.setAsGroupSummary, isFalse);
    });

    test('is dated by the alarm it reports on, not by when it was noticed', () {
      expect(details.when, due.millisecondsSinceEpoch);
      expect(details.showWhen, isTrue);
    });

    test('for an entry that names no instant is dated by its posting', () {
      final older = alertMissedDetails(en, content, dueAtMs: null);

      expect(older.when, isNull);
      expect(older.silent, isTrue);
    });

    test("wears the event's colour and its avatar, and has no button", () {
      expect(details.color, teal);
      expect(largeIconOf(details), avatar);
      expect(details.actions, isNull);
      expect(details.timeoutAfter, isNull);
    });

    test('expanded, shows its line and the description under it', () {
      expect(bigTextOf(details), 'Missed · 18:00\nHips and hamstrings.');
    });
  });

  group('a digest', () {
    final digest = AlertPayload(
      database: 'gym_notes',
      eventId: '',
      alertId: 'd1',
      dayUtcMs: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
      osId: 4343,
      mode: AlertMode.notify,
      title: 'Birthdays',
      timeLabel: '09:00',
      categoryId: 'birthday',
      isDigest: true,
      digestText: '7 events this month · Sun, Oct 4 · Ana, …',
      digestLines: const [
        'Sun, Oct 4 · Ana · Year 30',
        'Mon, Oct 12 · Mihai',
        'Tue, Oct 13 · Ioana',
        'Wed, Oct 14 · Dan',
        'Thu, Oct 15 · Elena',
      ],
      digestSummary: '+2 more',
    );
    final content = contentOf(AlertNotificationKind.digest, payload: digest);
    final details = alertDigestDetails(en, content, decor: dressed);

    InboxStyleInformation? inboxOf(AndroidNotificationDetails details) =>
        details.styleInformation as InboxStyleInformation?;

    test('sounds without peeking, on the digest channel', () {
      expect(details.channelId, 'alerts_digest');
      expect(details.channelName, 'Digests');
      expect(details.channelDescription, 'Bundled summaries of upcoming events');
      expect(details.importance, Importance.defaultImportance);
      expect(details.priority, Priority.defaultPriority);
      expect(details.category, AndroidNotificationCategory.event);
      expect(details.icon, 'ic_alert');
      expect(details.silent, isFalse);
      expect(details.autoCancel, isTrue);
      expect(details.fullScreenIntent, isFalse);
    });

    test('lists its lines under its title, with how many more', () {
      final inbox = inboxOf(details)!;
      expect(inbox.lines, digest.digestLines);
      expect(inbox.contentTitle, 'Birthdays');
      expect(inbox.summaryText, '+2 more');
    });

    test('has no button: the tap is the overview', () {
      expect(idsOf(details), isEmpty);
    });

    test('wears the one category\'s colour and avatar it is given', () {
      expect(details.color, teal);
      expect(largeIconOf(details), avatar);
      final bare = alertDigestDetails(en, content);
      expect(bare.color, isNull);
      expect(bare.largeIcon, isNull);
    });

    test('an empty span is its text alone, with no list', () {
      final empty = alertDigestDetails(
        en,
        contentOf(
          AlertNotificationKind.digest,
          payload: AlertPayload(
            database: 'gym_notes',
            eventId: '',
            alertId: 'd1',
            dayUtcMs: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
            osId: 4343,
            mode: AlertMode.notify,
            title: 'Birthdays',
            timeLabel: '09:00',
            categoryId: 'birthday',
            isDigest: true,
            digestText: 'No events this month',
          ),
        ),
      );
      expect(empty.styleInformation, isNull);
    });

    test('is grouped by the reminders\' rule, never as a summary', () {
      final grouped = alertDigestDetails(en, content, grouped: true);
      expect(grouped.groupKey, kAlertGroupKey);
      expect(grouped.groupAlertBehavior, GroupAlertBehavior.children);
      expect(grouped.setAsGroupSummary, isFalse);
      expect(details.groupKey, isNull);
      expect(details.groupAlertBehavior, GroupAlertBehavior.all);
    });

    test('names its channel in the language it is given', () {
      expect(alertDigestDetails(de, content).channelName, 'Zusammenfassungen');
    });
  });

  group('the fallback alarm', () {
    final details = alertFallbackAlarmDetails(
      en,
      contentOf(
        AlertNotificationKind.fallbackAlarm,
        payload: payloadOf(mode: AlertMode.ring),
      ),
      decor: dressed,
      timeoutAfterMillis: const Duration(minutes: 10).inMilliseconds,
    );

    test(
      'rings: its own channel, the alarm stream, insistent, full screen',
      () {
        expect(details.channelId, 'alerts_alarm_v2');
        expect(details.importance, Importance.max);
        expect(details.priority, Priority.max);
        expect(details.category, AndroidNotificationCategory.alarm);
        expect(details.audioAttributesUsage, AudioAttributesUsage.alarm);
        expect(details.fullScreenIntent, isTrue);
        expect(details.ongoing, isTrue);
        expect(details.autoCancel, isFalse);
        expect(details.visibility, NotificationVisibility.public);
        // `Notification.FLAG_INSISTENT`.
        expect(details.additionalFlags, [4]);
        expect(details.silent, isFalse);
        expect(details.icon, 'ic_alert');
      },
    );

    test('is silenced by the platform after the Silence-after setting', () {
      expect(details.timeoutAfter, const Duration(minutes: 10).inMilliseconds);
    });

    test(
      'offers Stop alone, under the id the isolate answers by cancelling',
      () {
        expect(idsOf(details), ['alert_done']);
        expect(labelsOf(details), ['Stop']);
        expect(details.actions!.single.showsUserInterface, isFalse);
      },
    );

    test("wears the event's colour and avatar, and expands to its line and "
        'the description', () {
      expect(details.color, teal);
      expect(largeIconOf(details), avatar);
      expect(bigTextOf(details), 'Alarm · 18:00 – 18:15\nHips and hamstrings.');
    });

    test('stays out of the reminders\' group', () {
      // Whether an insistent sound outlasts the platform gathering a group's
      // members was never seen, so the alarm is posted as it always was.
      expect(details.groupKey, isNull);
      expect(details.setAsGroupSummary, isFalse);
    });
  });

  group("the ring's own notification", () {
    final content = contentOf(
      AlertNotificationKind.ring,
      payload: payloadOf(mode: AlertMode.ring),
    );
    final NotificationSettings settings = alertRingSettings(content, teal);

    test('hands the plugin its title, its text and both button labels', () {
      expect(settings.title, 'Stretch');
      expect(settings.body, 'Alarm · 18:00 – 18:15');
      expect(settings.stopButton, 'Stop');
      expect(settings.androidSnoozeButton, 'Snooze 5 min');
    });

    test('names the monochrome icon and the one colour the plugin takes', () {
      expect(settings.icon, 'ic_alert');
      expect(settings.iconColor, teal);
    });

    test('leaves what a swipe does, and what stays after the ring, alone', () {
      // The plugin's own defaults; neither is this rework's to move.
      expect(settings.androidStopAlarmOnDismiss, isTrue);
      expect(settings.keepNotificationAfterAlarmEnds, isFalse);
    });
  });

  group('the session chip', () {
    final payload = payloadOf(mode: AlertMode.ring);
    final startedAt = DateTime(2026, 9, 20, 18, 0, 30);
    final endsAt = DateTime(2026, 9, 20, 18, 15);

    Map<String, Object?> argumentsOf({
      bool linkedNote = true,
      String? untilLabel = '18:15',
      AlertDecor decor = dressed,
      bool refresh = false,
      int? progress = 40,
      AppLocalizations? strings,
    }) => sessionChipArguments(
      payload: payload,
      content: alertNotificationContent(
        AlertNotificationKind.sessionChip,
        payload,
        strings ?? en,
        untilLabel: untilLabel,
        linkedNote: linkedNote,
      ),
      decor: decor,
      startedAt: startedAt,
      endsAt: untilLabel == null ? null : endsAt,
      progress: progress,
      refresh: refresh,
    );

    test('crosses to the platform under exactly these keys', () {
      expect(argumentsOf().keys, [
        'payload',
        'refresh',
        'channelId',
        'title',
        'text',
        'doneLabel',
        'openLabel',
        'startedAtMs',
        'endsAtMs',
        'progress',
        'color',
        'largeIcon',
      ]);
    });

    test('says what the session is and when it ends', () {
      final arguments = argumentsOf();

      expect(arguments['title'], 'Stretch');
      expect(arguments['text'], 'Until 18:15');
      expect(arguments['channelId'], 'alerts_quiet');
      expect(arguments['startedAtMs'], startedAt.millisecondsSinceEpoch);
      expect(arguments['endsAtMs'], endsAt.millisecondsSinceEpoch);
      expect(arguments['progress'], 40);
      expect(arguments['refresh'], isFalse);
      // The payload rides along for the tap: it names the event to open.
      expect(AlertPayload.decode(arguments['payload'] as String?), payload);
    });

    test('labels Done, and the note or the event for the second button', () {
      expect(argumentsOf()['doneLabel'], 'Done');
      expect(argumentsOf()['openLabel'], 'Open note');
      expect(argumentsOf(linkedNote: false)['openLabel'], 'Open event');
      expect(argumentsOf(strings: de)['doneLabel'], 'Erledigt');
      expect(argumentsOf(strings: de)['openLabel'], 'Notiz öffnen');
      expect(
        argumentsOf(strings: de, linkedNote: false)['openLabel'],
        'Termin öffnen',
      );
    });

    test("carries the event's colour and the path of its avatar", () {
      expect(argumentsOf()['color'], 0xFF00897B);
      expect(argumentsOf()['largeIcon'], avatar);
    });

    test('with no end, no avatar and no colour still crosses whole', () {
      final arguments = argumentsOf(
        untilLabel: null,
        progress: null,
        decor: (color: null, iconFile: null),
        refresh: true,
      );

      expect(arguments['text'], 'Session in progress');
      expect(arguments['endsAtMs'], isNull);
      expect(arguments['progress'], isNull);
      expect(arguments['color'], isNull);
      expect(arguments['largeIcon'], isNull);
      expect(arguments['refresh'], isTrue);
      expect(arguments['doneLabel'], 'Done');
    });
  });

  group('the decor a payload vouches for', () {
    test('is the tint and the icon file stamped into it', () {
      final decor = alertDecorOf(payloadOf(iconFile: avatar));

      expect(decor.color, teal);
      expect(decor.iconFile, avatar);
    });

    test('is nothing for an entry armed before either was stamped', () {
      // In the background isolate there is no category facade to fall back
      // on, so the re-post of such an entry goes without, as it always did.
      final decor = alertDecorOf(payloadOf(tintValue: null));

      expect(decor.color, isNull);
      expect(decor.iconFile, isNull);
    });
  });

  group('a reminder snoozed from the shade', () {
    final now = DateTime(2026, 9, 20, 18, 0, 20);
    final armed = payloadOf(iconFile: avatar);
    final snoozeId = resolveAlertOsId(
      seed: alertOsIdSeed(
        database: 'gym_notes',
        alertId: 'a1',
        dayUtc: day,
        kind: AlertKind.snooze,
      ),
      isTaken: (_) => false,
    );

    test('comes back after the snooze length, under the snooze id', () {
      final repost = snoozedRepost(armed, now, en);

      expect(repost.at, DateTime(2026, 9, 20, 18, 5, 20));
      expect(repost.osId, snoozeId);
      expect(repost.osId, isNot(armed.osId));
      expect(repost.payload.osId, snoozeId);
    });

    test("an inherited alert's snooze is seeded by its event, as the "
        "scheduler's is (v42)", () {
      // One category alert on two events of one day: snoozed from the shade,
      // each comes back under an id of its own.
      int seededFor(String eventId) => resolveAlertOsId(
        seed: alertOsIdSeed(
          database: 'gym_notes',
          alertId: 'a1',
          eventId: eventId,
          dayUtc: day,
          kind: AlertKind.snooze,
        ),
        isTaken: (_) => false,
      );
      final inherited = armed.copyWith(inherited: true);

      final repost = snoozedRepost(inherited, now, en);

      expect(repost.osId, seededFor('e1'));
      expect(repost.osId, isNot(snoozeId));
      expect(repost.payload.inherited, isTrue);
      expect(snoozedRepostTitleOnly(inherited, now).osId, seededFor('e1'));
    });

    test('says it was snoozed, and still names the event\'s time', () {
      final repost = snoozedRepost(armed, now, en);

      expect(repost.title, 'Stretch');
      expect(repost.body, 'Snoozed · 18:00 – 18:15');
      expect(
        bigTextOf(repost.details),
        'Snoozed · 18:00 – 18:15\nHips and hamstrings.',
      );
    });

    test('keeps its colour, its avatar and both buttons', () {
      final repost = snoozedRepost(armed, now, en);

      expect(repost.details.color, teal);
      expect(largeIconOf(repost.details), avatar);
      expect(idsOf(repost.details), ['alert_done', 'alert_snooze']);
      expect(labelsOf(repost.details), ['Done', 'Snooze 5 min']);
      expect(repost.details.channelId, 'alerts_reminder');
      expect(repost.details.importance, Importance.high);
      expect(repost.details.silent, isFalse);
    });

    test(
      'is written in the language it is handed, whatever the phone is in',
      () {
        // The isolate hands it the language the entry's payload names.
        final repost = snoozedRepost(
          armed.copyWith(languageCode: 'de'),
          now,
          de,
        );

        expect(repost.body, 'Geschlummert · 18:00 – 18:15');
        expect(labelsOf(repost.details), ['Erledigt', '5 Min. schlummern']);
        expect(
          bigTextOf(repost.details),
          'Geschlummert · 18:00 – 18:15\nHips and hamstrings.',
        );
      },
    );

    test('carries a payload that is a snooze, due at its own instant, and '
        'otherwise what it was', () {
      final repost = snoozedRepost(armed, now, en);

      expect(
        repost.payload,
        armed.copyWith(
          osId: snoozeId,
          snooze: true,
          fireAtMs: DateTime(2026, 9, 20, 18, 5, 20).millisecondsSinceEpoch,
        ),
      );
      // Spelled out as well: what a second Snooze re-posts from.
      expect(repost.payload.snooze, isTrue);
      expect(repost.payload.tintValue, 0xFF00897B);
      expect(repost.payload.iconFile, avatar);
      expect(repost.payload.excerpt, 'Hips and hamstrings.');
      expect(repost.payload.whenLabel, '18:00 – 18:15');
      expect(repost.payload.timeLabel, '18:00');
      expect(repost.payload.languageCode, 'en');
      expect(repost.payload.snoozeMinutes, 5);
      // And it survives the wire form the platform keeps it in.
      expect(AlertPayload.decode(repost.payload.encode()), repost.payload);
    });

    test('snoozed again, lands on the same entry with the same words', () {
      final first = snoozedRepost(armed, now, en);
      final later = DateTime(2026, 9, 20, 18, 5, 40);
      final second = snoozedRepost(first.payload, later, en);

      expect(second.osId, first.osId);
      expect(second.at, DateTime(2026, 9, 20, 18, 10, 40));
      expect(second.body, first.body);
      expect(second.details.color, teal);
      expect(largeIconOf(second.details), avatar);
      expect(
        second.payload.fireAtMs,
        DateTime(2026, 9, 20, 18, 10, 40).millisecondsSinceEpoch,
      );
    });

    test('for an entry armed by an older build comes back as it always did, '
        'in the new words', () {
      // No event time, no tint, no icon file, no language: the due time is
      // the one line it carries, and nothing dresses it.
      const older = AlertPayload(
        database: 'gym_notes',
        eventId: 'e1',
        alertId: 'a1',
        dayUtcMs: 1789862400000,
        osId: 4242,
        mode: AlertMode.notify,
        title: 'Stretch',
        timeLabel: '18:00',
        categoryId: 'gym',
      );
      final repost = snoozedRepost(older, now, en);

      expect(repost.title, 'Stretch');
      expect(repost.body, 'Snoozed · 18:00');
      expect(repost.details.color, isNull);
      expect(repost.details.largeIcon, isNull);
      expect(repost.details.styleInformation, isNull);
      expect(idsOf(repost.details), ['alert_done', 'alert_snooze']);
      expect(repost.payload.snooze, isTrue);
      expect(repost.at, now.add(const Duration(minutes: 10)));
    });

    // The isolate cannot ask which Android it is running on, so the entry
    // says which shape it was armed in and the re-post takes that one.
    group('by the shape it was armed in', () {
      final inGroup = armed.copyWith(grouped: true);

      test('armed in the group, comes back in it', () {
        final repost = snoozedRepost(inGroup, now, en);

        expect(repost.details.groupKey, 'anta.alerts');
        expect(repost.details.groupAlertBehavior, GroupAlertBehavior.children);
        expect(repost.details.setAsGroupSummary, isFalse);
        // Loose, it would be bundled at post beside a reminder still
        // standing, and come back without a sound.
        expect(repost.details.channelId, 'alerts_reminder');
        expect(repost.details.importance, Importance.high);
        expect(repost.details.silent, isFalse);
        expect(repost.body, 'Snoozed · 18:00 – 18:15');
      });

      test('and says so to the snooze after it', () {
        final first = snoozedRepost(inGroup, now, en);

        expect(first.payload.grouped, isTrue);
        // Through the wire form the platform keeps the re-post in.
        final held = AlertPayload.decode(first.payload.encode())!;
        expect(held.grouped, isTrue);

        final second = snoozedRepost(
          held,
          DateTime(2026, 9, 20, 18, 5, 40),
          en,
        );
        expect(second.details.groupKey, 'anta.alerts');
        expect(second.details.groupAlertBehavior, GroupAlertBehavior.children);
        expect(second.payload.grouped, isTrue);
      });

      test('armed loose, comes back loose', () {
        // A phone below Android 16, or an entry armed before the group
        // existed and never armed again.
        final repost = snoozedRepost(armed, now, en);

        expect(armed.grouped, isFalse);
        expect(repost.details.groupKey, isNull);
        expect(repost.details.setAsGroupSummary, isFalse);
        expect(repost.payload.grouped, isFalse);
        expect(repost.payload.toJson().containsKey('grp'), isFalse);
      });
    });

    group('whose words could not be put together', () {
      final repost = snoozedRepostTitleOnly(armed, now);

      test('still comes back, when it was asked to and where', () {
        expect(repost.at, DateTime(2026, 9, 20, 18, 5, 20));
        expect(repost.osId, snoozeId);
        expect(repost.payload, snoozedRepost(armed, now, en).payload);
      });

      test('with its title, its colour and its avatar', () {
        expect(repost.title, 'Stretch');
        expect(repost.details.color, teal);
        expect(largeIconOf(repost.details), avatar);
        expect(repost.details.channelId, 'alerts_reminder');
        expect(repost.details.importance, Importance.high);
        expect(repost.details.category, AndroidNotificationCategory.reminder);
        expect(repost.details.icon, 'ic_alert');
      });

      test('and nothing that takes a string: no text, no button', () {
        expect(repost.body, isNull);
        expect(repost.details.actions, isNull);
        expect(repost.details.styleInformation, isNull);
      });

      test('in the group when it was armed in it, and loose when it was '
          'not', () {
        // A bare reminder is still a reminder: left loose where the entry
        // was grouped, it would lose its sound beside another one as well as
        // its words.
        final inGroup = snoozedRepostTitleOnly(
          armed.copyWith(grouped: true),
          now,
        );

        expect(inGroup.details.groupKey, 'anta.alerts');
        expect(inGroup.details.groupAlertBehavior, GroupAlertBehavior.children);
        expect(inGroup.details.setAsGroupSummary, isFalse);
        expect(inGroup.payload.grouped, isTrue);

        expect(repost.details.groupKey, isNull);
        expect(repost.details.setAsGroupSummary, isFalse);
        expect(repost.payload.grouped, isFalse);
      });
    });

    // `snoozedRepost` writes in whatever language it is handed. Which one
    // that is, and what happens when its words cannot be had, is decided a
    // step above it, in the one function the isolate calls — so that is the
    // one called here, with nothing handed to it but the payload.
    group('as the background isolate posts it again', () {
      void expectTitleOnly(SnoozedRepost repost) {
        expect(repost.title, 'Stretch');
        expect(repost.body, isNull);
        expect(repost.details.actions, isNull);
        expect(repost.details.styleInformation, isNull);
        // Still the snooze that was asked for, dressed as the reminder was.
        expect(repost.osId, snoozeId);
        expect(repost.at, DateTime(2026, 9, 20, 18, 5, 20));
        expect(repost.payload, snoozedRepost(armed, now, en).payload);
        expect(repost.details.color, teal);
        expect(largeIconOf(repost.details), avatar);
      }

      test("is written in the language its payload names, not the phone's", () {
        // The test device is in English.
        final repost = snoozedRepostFor(
          armed.copyWith(languageCode: 'de'),
          now,
        );

        expect(repost.title, 'Stretch');
        expect(repost.body, 'Geschlummert · 18:00 – 18:15');
        expect(labelsOf(repost.details), ['Erledigt', '5 Min. schlummern']);
        expect(
          bigTextOf(repost.details),
          'Geschlummert · 18:00 – 18:15\nHips and hamstrings.',
        );
        expect(repost.osId, snoozeId);
        expect(repost.payload.languageCode, 'de');
      });

      test('asks for the strings of that language, and once', () {
        final asked = <String?>[];
        snoozedRepostFor(
          armed.copyWith(languageCode: 'ro'),
          now,
          stringsFor: (languageCode) {
            asked.add(languageCode);
            return en;
          },
        );

        expect(asked, ['ro']);
      });

      testWidgets(
        "for an entry that names no language is written in the phone's",
        (tester) async {
          // Armed before payloads named one: the isolate has no database to
          // read the app's own setting from.
          tester.platformDispatcher.localeTestValue = const ui.Locale(
            'ro',
            'RO',
          );
          addTearDown(tester.platformDispatcher.clearLocaleTestValue);

          final repost = snoozedRepostFor(
            payloadOf(languageCode: null, iconFile: avatar),
            now,
          );

          expect(repost.body, 'Amânată · 18:00 – 18:15');
          expect(labelsOf(repost.details), ['Gata', 'Amână 5 min']);
        },
      );

      test('comes back with its title alone when its strings cannot be '
          'had', () {
        expectTitleOnly(
          snoozedRepostFor(
            armed,
            now,
            stringsFor: (_) => throw StateError('no strings in this isolate'),
          ),
        );
      });

      test('and when putting its words together throws', () {
        expectTitleOnly(
          snoozedRepostFor(armed, now, stringsFor: (_) => _NoStrings()),
        );
      });

      test('is in the group its payload says it was armed in, with its '
          'words and without them', () {
        final inGroup = armed.copyWith(grouped: true);

        final worded = snoozedRepostFor(inGroup, now);
        expect(worded.body, 'Snoozed · 18:00 – 18:15');
        expect(worded.details.groupKey, 'anta.alerts');
        expect(worded.details.groupAlertBehavior, GroupAlertBehavior.children);

        final bare = snoozedRepostFor(
          inGroup,
          now,
          stringsFor: (_) => throw StateError('no strings in this isolate'),
        );
        expect(bare.body, isNull);
        expect(bare.details.groupKey, 'anta.alerts');
        expect(bare.details.groupAlertBehavior, GroupAlertBehavior.children);
        expect(bare.details.setAsGroupSummary, isFalse);

        expect(snoozedRepostFor(armed, now).details.groupKey, isNull);
      });
    });
  });

  group('the arm context', () {
    String contextOf({
      String backend = 'alarm',
      AlertRingVolume volume = AlertRingVolume.follow,
      String language = 'en',
      bool use24Hour = false,
    }) => alertArmContext(
      backend: backend,
      volume: volume,
      language: language,
      use24Hour: use24Hour,
    );

    test('is spelled backend, loudness, grammar, language, clock', () {
      expect(contextOf(), 'alarm~g4.en.h');
      expect(contextOf(use24Hour: true), 'alarm~g4.en.H');
      expect(
        contextOf(
          volume: AlertRingVolume.floor,
          language: 'de',
          use24Hour: true,
        ),
        'alarm@floor~g4.de.H',
      );
      expect(
        contextOf(backend: 'notification', language: 'ro'),
        'notification~g4.ro.h',
      );
    });

    test('carries the grammar token, which no earlier build recorded', () {
      // The whole of what makes the first pass after the upgrade write every
      // planned entry again: a reminder's row held the bare backend name, an
      // alarm's the backend and then its sound.
      expect(kAlertArmGrammarToken, '~g4');
      expect(contextOf(), isNot('alarm'));
      expect(contextOf(), contains(kAlertArmGrammarToken));
      expect(contextOf(volume: AlertRingVolume.floor), isNot('alarm@floor'));
    });

    test('is no context an earlier grammar of the redraw recorded', () {
      // Each froze into an entry something the next one changed. `~g2` armed
      // a reminder loose and an alarm's notice on the reminder channel;
      // `~g3` wrote an event on another day with its day after its time,
      // where a notification's one line cut the day. So every row signed
      // with either has to read as out of date once: armed again in the
      // group, with the notice on the quiet channel, the day first.
      for (final context in [
        contextOf(),
        contextOf(use24Hour: true),
        contextOf(volume: AlertRingVolume.floor, language: 'de'),
        contextOf(backend: 'notification', language: 'ro'),
      ]) {
        expect(context, isNot(contains('~g2')), reason: context);
        expect(context, isNot(contains('~g3')), reason: context);
      }
      expect(contextOf(), isNot('alarm~g2.en.h'));
      expect(contextOf(), isNot('alarm~g3.en.h'));
    });

    test('moves with the language an entry is written in', () {
      expect(contextOf(language: 'de'), isNot(contextOf(language: 'en')));
      expect(contextOf(language: 'ro'), isNot(contextOf(language: 'de')));
    });

    test('moves with the clock the phone is on', () {
      expect(contextOf(use24Hour: true), isNot(contextOf(use24Hour: false)));
    });

    test('still moves with the volume bucket and the backend', () {
      expect(
        contextOf(volume: AlertRingVolume.floor),
        isNot(contextOf(volume: AlertRingVolume.follow)),
      );
      expect(contextOf(backend: 'notification'), isNot(contextOf()));
    });

    test('is stable: equal inputs, equal token', () {
      // Or the diff would write the same entries again on every pass.
      expect(
        contextOf(language: 'de', use24Hour: true),
        contextOf(language: 'de', use24Hour: true),
      );
    });

    test('is what both tiers are signed with', () {
      PlannedFire fireOf(AlertMode mode) => PlannedFire(
        event: CalendarEvent(
          id: 'e1',
          title: 'Stretch',
          categoryId: 'gym',
          startDate: day,
          rule: const OneTimeRecurrence(),
          time: const EventTime(startMinute: 18 * 60),
        ),
        alert: EventAlert(id: 'a1', eventId: 'e1', mode: mode),
        day: day,
        fireAt: due,
        sound: const AlertSoundSystemDefault(),
      );
      String signatureOf(AlertMode mode, String context) => alertArmSignature(
        context: context,
        fire: fireOf(mode),
        snoozeMinutes: 10,
        noticeLeadMinutes: 120,
      );

      // A reminder's signature is the context and nothing more, which is why
      // the words' token had to go into the context: there was nowhere else
      // a changed language could reach a reminder from.
      expect(signatureOf(AlertMode.notify, contextOf()), 'alarm~g4.en.h');
      expect(
        signatureOf(AlertMode.notify, contextOf(language: 'de')),
        isNot(signatureOf(AlertMode.notify, contextOf())),
      );
      expect(
        signatureOf(AlertMode.ring, contextOf()),
        'alarm~g4.en.h#system:default~clock~10~n120',
      );
      expect(
        signatureOf(AlertMode.ring, contextOf(use24Hour: true)),
        isNot(signatureOf(AlertMode.ring, contextOf())),
      );
    });
  });

  group("the avatar's file", () {
    const dumbbell = IconData(0xe28d, fontFamily: 'MaterialIcons');

    test('is as large as the platform draws a large icon on this screen', () {
      expect(kAlertLargeIconDp, 48);
      expect(alertLargeIconPixels(1), 48);
      expect(alertLargeIconPixels(2), 96);
      expect(alertLargeIconPixels(2.625), 126);
      expect(alertLargeIconPixels(3), 144);
      expect(alertLargeIconPixels(4), 192);
    });

    test('is bounded at both ends', () {
      expect(alertLargeIconPixels(0.75), 48);
      expect(alertLargeIconPixels(5), 192);
      expect(alertLargeIconPixels(400), 192);
    });

    test('takes a usual density when the engine has no view to ask', () {
      for (final unknown in [null, 0.0, -2.0, double.nan, double.infinity]) {
        expect(alertLargeIconPixels(unknown), 144, reason: '$unknown');
      }
    });

    test("draws its glyph at the in-app avatar's own share of the disc", () {
      // 24 in a disc of 40.
      expect(EventAvatar.iconSize / (EventAvatar.radius * 2), 0.6);
      expect(alertLargeIconGlyphSize(144), closeTo(86.4, 0.0001));
      expect(alertLargeIconGlyphSize(48), closeTo(28.8, 0.0001));
    });

    test('is named by its glyph, its colour, its size and how it is drawn', () {
      // The last two parts are the disc's alpha out of 255 and the glyph's
      // size in pixels, as the in-app avatar's constants give them today.
      expect(
        alertLargeIconFileName(dumbbell, teal, 144),
        'materialicons_e28d_ff00897b_144_a41_g86.png',
      );
      // A letter or a digit is a glyph of no icon font.
      expect(
        alertLargeIconFileName(const IconData(0x41), teal, 144),
        'text_41_ff00897b_144_a41_g86.png',
      );
      expect(
        alertLargeIconFileName(
          const IconData(
            0xf101,
            fontFamily: 'Custom Icons',
            fontPackage: 'my_pkg',
          ),
          const ui.Color(0x80112233),
          96,
        ),
        'mypkgcustomicons_f101_80112233_96_a41_g58.png',
      );
    });

    test("says how it was drawn in the in-app avatar's own numbers", () {
      // A file found under a name is never drawn again. So the day the
      // avatar's fill or its glyph changes, the name has to change with it,
      // by itself — or every avatar a phone has already drawn keeps its old
      // look for good, beside new ones for every colour it has not met yet.
      for (final pixels in [48, 96, 126, 144, 192]) {
        expect(
          alertLargeIconFileName(dumbbell, teal, pixels),
          'materialicons_e28d_ff00897b_$pixels'
          '_a${(EventAvatar.backgroundAlpha * 255).round()}'
          '_g${alertLargeIconGlyphSize(pixels).round()}.png',
          reason: '$pixels',
        );
      }
    });

    test('is one file for one avatar, and another for any other', () {
      final name = alertLargeIconFileName(dumbbell, teal, 144);

      expect(alertLargeIconFileName(dumbbell, teal, 144), name);
      expect(
        alertLargeIconFileName(dumbbell, const ui.Color(0xFF00897C), 144),
        isNot(name),
      );
      expect(alertLargeIconFileName(dumbbell, teal, 126), isNot(name));
      expect(
        alertLargeIconFileName(
          const IconData(0xe28e, fontFamily: 'MaterialIcons'),
          teal,
          144,
        ),
        isNot(name),
      );
    });

    test('has a name of its own for every way an avatar can differ', () {
      const other = IconData(0xe28e, fontFamily: 'MaterialIcons');
      const otherFont = IconData(0xe28d, fontFamily: 'OtherIcons');
      final names = [
        alertLargeIconFileName(dumbbell, teal, 144),
        // The glyph, and the font it is a glyph of.
        alertLargeIconFileName(other, teal, 144),
        alertLargeIconFileName(otherFont, teal, 144),
        // The colour, its alpha included.
        alertLargeIconFileName(dumbbell, const ui.Color(0xFF00897C), 144),
        alertLargeIconFileName(dumbbell, const ui.Color(0xFE00897B), 144),
        // The size of the bitmap.
        alertLargeIconFileName(dumbbell, teal, 126),
        // The disc's alpha and the glyph's size: how it is drawn.
        alertLargeIconFileName(dumbbell, teal, 144, discAlpha: 0.2),
        alertLargeIconFileName(dumbbell, teal, 144, glyphSize: 80),
      ];

      expect(names.toSet(), hasLength(names.length), reason: '$names');
      expect(names[6], 'materialicons_e28d_ff00897b_144_a51_g86.png');
      expect(names[7], 'materialicons_e28d_ff00897b_144_a41_g80.png');
    });

    test('has a name any file system takes', () {
      final safe = RegExp(r'^[a-z0-9_]+\.png$');

      for (final icon in const [
        dumbbell,
        IconData(0x41),
        IconData(0x1F3CB, fontFamily: 'Weird/Font:Name*', fontPackage: 'a.b'),
      ]) {
        expect(
          alertLargeIconFileName(icon, teal, 144),
          matches(safe),
          reason: '$icon',
        );
      }
    });

    testWidgets("is the in-app avatar: the glyph on a disc of its own colour "
        "at the avatar's alpha", (tester) async {
      const pixels = 96;
      final pixelsOf = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        paintAlertLargeIcon(
          Canvas(recorder),
          const IconData(0x41),
          teal,
          pixels,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(pixels, pixels);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        image.dispose();
        picture.dispose();
        return data!;
      });

      List<int> rgbaAt(int x, int y) {
        final offset = (y * pixels + x) * 4;
        return [for (var i = 0; i < 4; i++) pixelsOf!.getUint8(offset + i)];
      }

      // Outside the disc there is nothing: the platform shows the shade.
      for (final corner in [
        (0, 0),
        (pixels - 1, 0),
        (0, pixels - 1),
        (pixels - 1, pixels - 1),
      ]) {
        expect(rgbaAt(corner.$1, corner.$2)[3], 0, reason: '$corner');
      }
      // On the disc, clear of the glyph — which takes the middle 60 % — the
      // tint at the in-app avatar's alpha.
      final disc = rgbaAt(pixels ~/ 2, 4);
      expect(disc[3], closeTo(EventAvatar.backgroundAlpha * 255, 1.5));
      expect(disc[0], closeTo(0x00, 4));
      expect(disc[1], closeTo(0x89, 4));
      expect(disc[2], closeTo(0x7B, 4));
      // And the glyph itself in the full colour: the test font draws every
      // glyph as a filled box, so its middle is solid.
      expect(rgbaAt(pixels ~/ 2, pixels ~/ 2), [0x00, 0x89, 0x7B, 0xFF]);
    });
  });
}

/// Localizations that were found and cannot be read: every string throws.
class _NoStrings extends Fake implements AppLocalizations {}
