import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/android_alert_gateway.dart';
import 'package:anta/utils/alert_notification_content.dart';

/// The session chip is drawn in Kotlin from a map Dart sends, and the keys of
/// that map are spelled twice — once on each side — with no build step to
/// compare them. A key renamed on one side still compiles and runs: the chip
/// simply comes up without its avatar, or with a button that reads nothing.
/// The app module has no Kotlin test source set, so the two are held to each
/// other here, by reading the source.
void main() {
  final chip = File(
    'android/app/src/main/kotlin/com/alexzamfir/anta/SessionChip.kt',
  ).readAsStringSync();

  final payload = AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
    osId: 7,
    mode: AlertMode.ring,
    title: 'Leg day',
    timeLabel: '18:00',
    categoryId: 'gym',
  );
  final content = alertNotificationContent(
    AlertNotificationKind.sessionChip,
    payload,
    lookupAppLocalizations(const Locale('en')),
  );
  final arguments = sessionChipArguments(
    payload: payload,
    content: content,
    startedAt: DateTime(2026, 9, 20, 18),
  );

  test('the platform reads every key Dart sends', () {
    for (final key in arguments.keys) {
      expect(chip, contains('args["$key"]'), reason: key);
    }
  });

  test('the platform reads no key Dart does not send', () {
    final read = RegExp(
      r'args\["(\w+)"\]',
    ).allMatches(chip).map((match) => match.group(1)!).toSet();

    expect(read.difference(arguments.keys.toSet()), isEmpty);
  });

  test('the buttons are added in the order the words are written in', () {
    // Dart sends the two labels by name; the order they are drawn in is the
    // order Kotlin adds them. The grammar puts the button that settles first.
    expect(content.actions.map((action) => action.action), [
      AlertNotificationAction.done,
      AlertNotificationAction.open,
    ]);
    final done = chip.indexOf('.addAction(0, args["doneLabel"]');
    final open = chip.indexOf('.addAction(0, args["openLabel"]');

    expect(done, isNonNegative);
    expect(open, isNonNegative);
    expect(done, lessThan(open));
  });

  test(
    'the avatar is taken from the path Dart sends, and only if it reads',
    () {
      expect(chip, contains('BitmapFactory.decodeFile'));
      expect(chip, contains('if (largeIcon != null) builder.setLargeIcon'));
    },
  );

  test('the channel it is posted on is one the binding has made, and made '
      'quiet', () {
    // Kotlin builds on the id it is handed and makes no channel of its own —
    // and from Android 8 on, a notification on a channel nobody has made is
    // never posted.
    expect(chip, contains('NotificationCompat.Builder(context, channelId)'));
    expect(chip, isNot(contains('NotificationChannel')));
    expect(arguments['channelId'], kAlertQuietChannelId);

    // So the binding makes it as it comes up, at the importance the channel
    // exists for. Android freezes that where a channel is first made: any
    // higher here and the chip, the upcoming notice and the Missed notice
    // are back in the reminders' section of the shade for good — where two
    // of them together sounded and a reminder that fired beside one did not —
    // whatever their own details ask for. The class cannot be built off a
    // device, so its line is read as text.
    final gateway = File(
      'lib/services/android_alert_gateway.dart',
    ).readAsStringSync();
    final comingUp = RegExp(
      r'Future<void> _initialize\(\) async \{[\s\S]*?^  \}',
      multiLine: true,
    ).stringMatch(gateway);

    expect(comingUp, isNotNull);
    // And with no sound and no vibration of its own, which Android freezes
    // beside the importance. At low importance both are inert; they are
    // there for the phone whose owner turns the channel up — the one way to
    // get these three back on a lock screen that hides silent notifications
    // — where a channel made with the plugin's defaults (both on) would
    // sound, on the channel whose own description says it never does.
    //
    // The call is read without its comments, so that it can carry one.
    final code = comingUp!
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(
      code,
      matches(
        RegExp(
          r'createNotificationChannel\(\s*AndroidNotificationChannel\(\s*'
          r'kAlertQuietChannelId,\s*l10n\.alertsQuietChannel,\s*'
          r'description: l10n\.alertsQuietChannelDesc,\s*'
          r'importance: Importance\.low,\s*'
          r'playSound: false,\s*enableVibration: false,?\s*\),?\s*\)',
        ),
      ),
    );
  });

  group('the binding, as it posts the chip,', () {
    final binding = File(
      'lib/services/android_alert_gateway.dart',
    ).readAsStringSync();

    /// `showSessionChip` without its comment lines: from its signature to
    /// the line that is a closing brace alone at a member's indent — its
    /// parameter list closes on a brace at that indent too, with more after
    /// it.
    String posting() {
      final method = RegExp(
        r'Future<bool> showSessionChip\([\s\S]*?^  \}\r?$',
        multiLine: true,
      ).stringMatch(binding);
      expect(method, isNotNull);
      return method!
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
    }

    test('has come up, channel and all, before the platform is asked', () {
      // The chip's channel exists because the binding made it as it came up.
      // Kotlin cannot tell: `notify` does not throw for a channel nobody has
      // made, so it answers "standing" for a chip Android dropped, and
      // records the session's end for it. One line orders the two, and with
      // it gone every other case here still passes.
      final method = posting();
      final cameUp = method.indexOf('await initialize();');
      final asked = method.indexOf("'showSessionChip'");

      expect(cameUp, isNonNegative);
      expect(asked, greaterThan(cameUp));
      expect('await initialize();'.allMatches(method), hasLength(1));
    });

    test("hands over the chip's own words, the session's end as the phone "
        'writes it, and everything it was given', () {
      final method = posting();

      expect(method, contains('AlertNotificationKind.sessionChip,'));
      // The end is the session's, which no payload carries: without it the
      // chip says "Session in progress" for an event that has an end.
      expect(
        method,
        contains(
          'untilLabel: endsAt == null ? null : labels.untilLabel(endsAt),',
        ),
      );
      // And whether there is a note to open decides what its second button
      // says and does.
      expect(method, contains('linkedNote: linkedNote,'));
      expect(
        method,
        matches(
          RegExp(
            r"_platform\.invokeMethod<bool>\(\s*'showSessionChip',\s*"
            r'sessionChipArguments\(\s*payload: payload,\s*content: content,\s*'
            r'decor: decor,\s*startedAt: startedAt,\s*endsAt: endsAt,\s*'
            r'progress: progress,\s*refresh: refresh,?\s*\),?\s*\)',
          ),
        ),
      );
    });
  });
}
