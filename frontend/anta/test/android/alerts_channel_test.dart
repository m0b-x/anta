import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/android_alert_gateway.dart';

/// The binding asks the activity which Android the phone runs, to decide
/// whether a reminder is posted in the app's own notification group — and it
/// takes an unanswered call for "below Android 16", because a reminder armed
/// loose is the shape every phone had before. So a method renamed on one side
/// alone would compile, run, and leave every reminder on an Android 16 phone
/// silenced beside another one, with one line in the log to say so. The app
/// module has no Kotlin test source set, so the two sides are held to each
/// other here, by reading the source.
///
/// What the binding makes of the answer is read here as well, for a like
/// reason: `AndroidAlertGateway` cannot be built off a device. The rule it
/// puts the level to and the details that rule leads to are pure, and pinned
/// on levels a suite hands them (`android_alert_notifications_test.dart`).
/// The lines that hand them the phone's own are the class's, and each would
/// compile and pass every one of those suites, and every saved flow, with the
/// wrong thing in it.
///
/// So would the rest of what the class decides for itself, which is read
/// here too: where a pass takes the app's language from — read the wrong
/// way, that one line switches databases under the running app — and which
/// of the pure pieces each kind of notification is handed.
void main() {
  final activity = File(
    'android/app/src/main/kotlin/com/alexzamfir/anta/MainActivity.kt',
  ).readAsStringSync();
  final gateway = File(
    'lib/services/android_alert_gateway.dart',
  ).readAsStringSync();

  /// What the activity answers on the alerts channel: its handler's `when`,
  /// up to where the next channel is registered.
  String alertsHandler() {
    final start = activity.indexOf('alerts.setMethodCallHandler');
    final end = activity.indexOf(
      'MethodChannel(messenger, PERMISSIONS_CHANNEL)',
    );
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    return activity.substring(start, end);
  }

  /// One method of the binding, whole: from its signature to the first brace
  /// that closes at a member's own indent.
  String methodOf(String signature) {
    final method = RegExp(
      '${RegExp.escape(signature)}[\\s\\S]*?^  \\}',
      multiLine: true,
    ).stringMatch(gateway);
    expect(method, isNotNull, reason: signature);
    return method!;
  }

  /// [source] without its comment lines: a comment may name a call without
  /// making it, and may stand between two arguments of one.
  String uncommented(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  final gatewayCode = uncommented(gateway);

  /// The code of one method of the binding.
  String codeOf(String signature) => uncommented(methodOf(signature));

  group('the language an entry is written in', () {
    const pass = 'Future<String> refreshArmContext() async {';
    const reread = 'Future<String?> _rereadLanguageCode() async {';

    test('is read again on every pass through the settings singleton, and '
        'never by asking which database is active', () {
      // `AppDatabase.getInstance()` is this app's database switch: whenever
      // the stored active name differs from the database that is open — the
      // open one renamed in Settings, or a switch waiting behind its "close
      // ANTA and open it again" dialog — the call closes the connection that
      // every repository and service GetIt holds is bound to. A pass runs
      // two seconds after every resume and after every calendar save, so a
      // read that went that way carried the switch out under the running
      // app: folders stopped loading and the note being edited could no
      // longer be saved. The settings singleton is bound to the database
      // that is open, and asks nothing.
      final method = methodOf(pass);

      expect(method, contains('_languageCode = await _rereadLanguageCode();'));
      expect(method, isNot(contains('_readLanguageCode(')));
      expect(method, isNot(contains('AppDatabase')));
      expect(
        methodOf(reread),
        contains('(await SettingsService.getInstance()).getLocaleCode()'),
      );
      expect(methodOf(reread), isNot(contains('AppDatabase')));
    });

    test('stays as it was when that read fails', () {
      // Every answer the reader can give, in the order it is written: the
      // row, and — for a read that threw — the language it already had. Null
      // there would be "follow the device": one bad query would move the arm
      // context, and the pass would write every standing entry again in a
      // language nobody chose.
      final answers = [
        for (final answer in RegExp(
          r'\breturn ([^;]+);',
        ).allMatches(methodOf(reread)))
          answer.group(1),
      ];

      expect(answers, [
        'await (await SettingsService.getInstance()).getLocaleCode()',
        '_languageCode',
      ]);
    });

    test('is read off the database itself once, where the binding comes '
        'up', () {
      // The one place it may be: inside `configureDependencies()`, where the
      // database has just been opened under the stored name and the settings
      // singleton may not exist yet.
      const direct = 'Future<String?> _readLanguageCode() async {';

      expect('AppDatabase.getInstance('.allMatches(gatewayCode), hasLength(1));
      expect(methodOf(direct), contains('await AppDatabase.getInstance()'));
      expect(
        RegExp(r'\b_readLanguageCode\(').allMatches(gatewayCode),
        hasLength(2),
        reason: 'its declaration and one call',
      );
      expect(
        methodOf('Future<void> _initialize() async {'),
        contains('_languageCode = await _readLanguageCode();'),
      );
    });

    test('and only the first time it comes up: a start that is retried keeps '
        'the language it has', () {
      // `initialize()` keeps no failure, and every scheduling pass asks for
      // it. On a binding whose start keeps failing — the release shrinker's
      // dropped icon did exactly that, 2026-09-21 — a read on every start is
      // a read on every pass, by the one call that carries a stored database
      // switch out under the running app. What the first start read is
      // corrected by the per-pass re-read, like any other change.
      expect(
        codeOf('Future<void> _initialize() async {'),
        matches(
          RegExp(
            r'if \(!_languageReadAtStart\) \{\s*'
            r'_languageReadAtStart = true;\s*'
            r'_languageCode = await _readLanguageCode\(\);\s*\}',
          ),
        ),
      );
      // Marked before the read is awaited, and never taken back: the start
      // that failed after it is the very one that must not read again.
      expect(
        RegExp(r'\b_languageReadAtStart\s*=(?!=)').allMatches(gatewayCode),
        hasLength(2),
        reason: 'its declaration and the mark',
      );
      expect(gatewayCode, contains('bool _languageReadAtStart = false;'));
    });

    test('moves the arm context as what the pass will write in, and on which '
        'clock', () {
      // The labels of the pass, built from the language just read, and the
      // same two facts of them in the token: a fixed language here, or the
      // setting in place of what it resolves to, and a change of language or
      // of the phone's clock would stop re-arming what already stands.
      final method = codeOf(pass);

      expect(
        method,
        contains('final labels = _labels = _labelsFor(_languageCode);'),
      );
      expect(
        method,
        matches(
          RegExp(
            r'return alertArmContext\(\s*backend: backendName,\s*'
            r'volume: _ringVolume,\s*language: labels\.languageCode,\s*'
            r'use24Hour: labels\.use24Hour,?\s*\);',
          ),
        ),
      );
    });
  });

  test("the activity answers the method the binding asks the phone's "
      'Android release with', () {
    expect(alertsHandler(), contains('"$kAlertSdkLevelMethod" ->'));
  });

  test('and answers it with the API level itself', () {
    // An int, which is what the binding reads it as: a string or a release
    // name would arrive as null there, and null is "not Android 16".
    expect(
      alertsHandler(),
      contains(
        '"$kAlertSdkLevelMethod" -> result.success(Build.VERSION.SDK_INT)',
      ),
    );
  });

  test('the binding asks for it by that name, as an int', () {
    expect(
      gateway,
      contains('_platform.invokeMethod<int>(kAlertSdkLevelMethod)'),
    );
  });

  group('with the answer, the binding', () {
    const asks = 'Future<bool> _groupsReminders() async {';
    const arms = 'Future<bool> _scheduleNotification(';

    test('puts the level it read to the rule, and answers as the rule '
        'does', () {
      final method = methodOf(asks);

      expect(
        method,
        contains(
          'final sdkInt = '
          'await _platform.invokeMethod<int>(kAlertSdkLevelMethod);',
        ),
      );
      // The one rule, which the notifications suite pins release by release:
      // a second reading of the level written out here would be pinned by
      // nothing.
      expect(
        method,
        contains('return _remindersGrouped = alertRemindersGroupedOn(sdkInt);'),
      );
    });

    test('never says yes by itself: an answer that came back empty and a '
        'call that threw both arm loose', () {
      // Every answer the method can give, in the order it is written: the one
      // it already has, no for an empty answer, the rule's for a level, no
      // for a call that threw. Loose is the reminder every phone posted
      // before the group; in the group on a release nobody could name is a
      // guess.
      final answers = [
        for (final answer in RegExp(
          r'\breturn ([^;]+);',
        ).allMatches(methodOf(asks)))
          answer.group(1),
      ];

      expect(answers, [
        'known',
        'false',
        '_remindersGrouped = alertRemindersGroupedOn(sdkInt)',
        'false',
      ]);
    });

    test('remembers an answer and never a failure', () {
      // Written once in the whole file, by the rule's own line. A no kept
      // from one bad round trip at launch would arm every reminder of the
      // process loose, and a yes written anywhere else is nobody's answer.
      expect(
        RegExp(r'_remindersGrouped\s*[?|&^]*=(?!=)').allMatches(gateway),
        hasLength(1),
      );
    });

    test('asks for a reminder alone, so the fallback alarm stays loose', () {
      // Whether an insistent sound outlasts the platform gathering the
      // group's members was never seen.
      expect(
        methodOf(arms),
        contains('final grouped = !alarmTier && await _groupsReminders();'),
      );
    });

    test('stamps it into the payload the platform keeps for the reminder', () {
      // Its Snooze posts the reminder again from that payload alone, in an
      // isolate that cannot ask which Android it is on: left out here, a
      // snoozed reminder comes back loose on Android 16, and silenced beside
      // one still standing.
      final method = methodOf(arms);

      expect(
        method,
        matches(
          RegExp(
            r'final carried = alarmTier\s*\? payload\s*: payload\.copyWith\('
            r'iconFile: decor\.iconFile, grouped: grouped\);',
          ),
        ),
      );
      expect(method, contains('payload: carried.encode(),'));
    });

    test('posts the reminder as the same answer says', () {
      // The details are what the platform posts and the stamp is what the
      // Snooze posts again: on two answers a reminder would leave in one
      // shape and come back in the other.
      expect(
        methodOf(arms),
        matches(
          RegExp(
            r'alertReminderDetails\(\s*l10n,\s*content,\s*decor: decor,\s*'
            r'grouped: grouped,?\s*\)',
          ),
        ),
      );
    });
  });

  group('each of the other kinds is handed the pieces written for it:', () {
    // How each kind is posted is a pure function with a suite of its own, and
    // so are its words. Which function a kind is handed, and with what, is
    // one line of the class per kind — and a notice posted with a reminder's
    // details, or a Missed dated by nothing, passes every one of those
    // suites and both saved passes, which read no channel and no shade.

    test('the upcoming notice its own words, the day it is for, and the '
        'details that take it down when its alarm is due', () {
      final method = codeOf('Future<void> _armNotice(');

      expect(method, contains('AlertNotificationKind.notice,'));
      // A notice can be posted the evening before: without its day, "07:00"
      // there reads as a time already gone.
      expect(
        method,
        contains(
          'dayLabel: labels.dayLabel(fireAt: fireAt, noticeAt: noticeAt),',
        ),
      );
      // On the quiet channel, and gone at the alarm's instant — a notice
      // that outlived its alarm would offer to skip a ring that has rung.
      expect(
        method,
        matches(
          RegExp(
            r'android: alertNoticeDetails\(\s*l10n,\s*content,\s*'
            r'decor: decor,\s*timeoutAfterMillis: noticeTimeoutMillis\(\s*'
            r'noticeAt: noticeAt,\s*fireAt: fireAt,?\s*\),?\s*\)',
          ),
        ),
      );
    });

    test('the ring its own words, and a volume that never raises the '
        "phone's own panel over the alarm page", () {
      final method = codeOf(
        'Future<bool> _scheduleAlarm(PlannedFire fire, AlertPayload payload) '
        'async {',
      );

      expect(method, contains('AlertNotificationKind.ring,'));
      expect(
        method,
        contains(
          'notificationSettings: alertRingSettings(content, _tintOf(payload)),',
        ),
      );
      // The plugin's default is on: the panel then comes up at the start of
      // a ring in the floor bucket and again at its end, over the page both
      // times.
      expect(
        method,
        matches(
          RegExp(
            r'volumeSettings: VolumeSettings\.fade\(\s*'
            r'fadeDuration: kAlertRingFade,\s*'
            r'volume: _ringVolume == AlertRingVolume\.floor\s*'
            r'\? kAlertRingFloorVolume\s*: null,\s*'
            r'showSystemUI: false,?\s*\)',
          ),
        ),
      );
    });

    test('a Missed notice its own words and details, dated by the alarm it '
        'reports', () {
      final method = codeOf(
        'Future<void> showMissed(AlertPayload payload) async {',
      );

      expect(method, contains('AlertNotificationKind.missed,'));
      // The quiet channel is in these details and in no other: a reminder's
      // would make it sound, which is what it did until it had its own.
      // And the instant is the entry's own due one, not the posting's.
      expect(
        method,
        matches(
          RegExp(
            r'android: alertMissedDetails\(\s*l10n,\s*content,\s*'
            r'decor: decor,\s*dueAtMs: payload\.fireAtMs,?\s*\)',
          ),
        ),
      );
    });
  });
}
