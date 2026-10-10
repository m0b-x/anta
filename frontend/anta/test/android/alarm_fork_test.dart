import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Five of the `alarm` fork's nine patches (`packages/alarm/`) are held here,
/// by reading their source. A newer upstream copy of the file any of them
/// lives in would undo it with nothing in the app's `flutter test` failing,
/// and none of the five losses would be seen in a day's use of the app.
///
/// Two sit where the fork's own tests cannot reach. Patch 5 is one attribute
/// of the library's manifest. Patch 6's rule is unit-tested in Kotlin
/// (`RingWakeLockTest`), but over a stand-in for the platform's lock: the
/// three places that call the rule, and the three lines that pass its calls
/// on to the real lock, are inside an Android `Service`, which that JVM-only
/// suite cannot build. Upstream ships the receiver exported and the lock in a
/// local nothing releases, and neither loss shows on a phone: one is a door
/// left open to every other app, the other five minutes of battery a ring.
///
/// The fork's own suites do reach the other three, but they run from
/// `packages/alarm` and from Gradle alone, never in the app's `flutter test`.
/// Patch 7 is Dart (`alarm_fallback_timer_test.dart`): without it a Stop or a
/// Snooze taken inside the fallback timer's 700 ms wait lets a second
/// announcement of the ring it ended through, which the page queue drops as
/// an echo — what stays behind is the id in the binding's ring set and the
/// alert's row ending `missed`. Patch 8 is Kotlin (`NotificationSettingsTest`):
/// without it every `Alarm.set` crashes the app on Android 7.0 and 7.1 — and
/// only there, so no newer phone shows the loss. Patch 9 is Dart
/// (`alarm_check_test.dart`): without it an alarm held back while another one
/// sounds is stopped by the plugin's own start, and never rings, when the app
/// is opened more than 30 s after it came due — two alarms in one minute and
/// a late look at the heads-up.
void main() {
  const fork = 'packages/alarm/android/src/main';

  group('the receiver every alarm is delivered through (Patch 5)', () {
    final manifest = File('$fork/AndroidManifest.xml').readAsStringSync();

    /// The `<receiver>` tags that name the fork's `AlarmReceiver`, each with
    /// all its attributes.
    final declared = RegExp(
      r'<receiver\b[^>]*android:name="com\.gdelataillade\.alarm\.alarm\.'
      r'AlarmReceiver"[^>]*>',
    ).allMatches(manifest).map((match) => match.group(0)!).toList();

    test('is declared once', () {
      expect(declared, hasLength(1));
    });

    test('is not exported', () {
      // Exported, and it asks for no permission: any app that knows an
      // alarm's id can then stop that alarm or snooze it with one broadcast.
      // Everything that is meant to reach it is the app's own — the
      // AlarmManager entry, the notification's buttons, an in-process
      // broadcast — and a PendingIntent is sent as the app that made it.
      expect(declared.single, contains('android:exported="false"'));
      expect(declared.single, isNot(contains('android:exported="true"')));
    });
  });

  group("the wake lock a ring holds (Patch 6), in the fork's service", () {
    final service = File(
      '$fork/kotlin/com/gdelataillade/alarm/alarm/AlarmService.kt',
    ).readAsStringSync();

    /// One function of the service, whole: from its signature to the first
    /// brace that closes at a member's own indent.
    String functionOf(String signature) {
      final function = RegExp(
        '${RegExp.escape(signature)}[\\s\\S]*?^    \\}',
        multiLine: true,
      ).stringMatch(service);
      expect(function, isNotNull, reason: signature);
      return function!;
    }

    test('is taken through the holder, where a ring starts, and nowhere '
        'else', () {
      expect(
        functionOf(
          'private fun ringAlarm(id: Int, alarmSettings: AlarmSettings) {',
        ),
        contains('ringWakeLock.acquire()'),
      );
      expect('ringWakeLock.acquire()'.allMatches(service), hasLength(1));
      // The one lock the platform is asked for is the one the holder is
      // built around: a second, taken into a local as upstream takes it,
      // would be a lock nothing can release.
      expect('newWakeLock('.allMatches(service), hasLength(1));
      expect(
        service,
        matches(
          RegExp(
            r'private val ringWakeLock = RingWakeLock \{\s*'
            r'val wakeLock = \(getSystemService\(Context\.POWER_SERVICE\) '
            r'as PowerManager\)\s*\.newWakeLock\(',
          ),
        ),
      );
    });

    test("is the platform's own: the holder's three calls are passed on to "
        'it whole', () {
      // The holder is written against an interface, and the Kotlin suite
      // builds it over a fake. The object it is handed in the service is the
      // only place its three calls become `PowerManager.WakeLock`'s, and
      // nothing builds it off a device. A release that stops there is
      // upstream's leak back, five minutes awake after a ring stopped at
      // once; an acquire that drops its argument has no bound left; and a
      // state that is not the lock's own has the holder release a lock the
      // platform already let go, or keep one it still holds.
      final adapters = RegExp(
        r'object : RingWakeLock\.Lock \{([\s\S]*?)^        \}',
        multiLine: true,
      ).allMatches(service).map((match) => match.group(1)!.trim()).toList();

      expect(adapters, hasLength(1));
      // The body whole, not each line looked for: a line left behind in a
      // comment beside its emptied replacement would still be found.
      expect(adapters.single.split(RegExp(r'\s*\n\s*')), [
        'override val isHeld: Boolean get() = wakeLock.isHeld',
        'override fun acquire(timeoutMillis: Long) = '
            'wakeLock.acquire(timeoutMillis)',
        'override fun release() = wakeLock.release()',
      ]);
    });

    test('is let go when the last ring ends, before the service stops '
        'itself', () {
      final stop = functionOf('private fun stopAlarm(id: Int) {');
      // The branch that runs once nothing sounds and nothing was promoted
      // from the queue. A ring that only hands over to the next one keeps
      // the CPU awake: the next ring's own start is what swaps the lock.
      final lastRingOver = stop.indexOf(
        '// No more queued alarms, perform full cleanup',
      );
      final release = stop.indexOf('ringWakeLock.release()');
      final stopSelf = stop.indexOf('stopSelf()');

      expect(lastRingOver, isNonNegative);
      expect(release, greaterThan(lastRingOver));
      expect(stopSelf, greaterThan(release));
      expect('ringWakeLock.release()'.allMatches(stop), hasLength(1));
    });

    test('and when the service is destroyed', () {
      // A service the system takes down mid-ring never runs the branch
      // above.
      expect(
        functionOf('override fun onDestroy() {'),
        contains('ringWakeLock.release()'),
      );
    });
  });

  group("the fallback timer's last question (Patch 7), in the plugin's "
      'Dart', () {
    final timers = File(
      'packages/alarm/lib/src/platform_timers.dart',
    ).readAsStringSync();

    /// One member of `PlatformTimers`, whole: from its signature to the first
    /// brace that closes at a member's own indent.
    String memberOf(String signature) {
      final member = RegExp(
        '${RegExp.escape(signature)}[\\s\\S]*?^  \\}',
        multiLine: true,
      ).stringMatch(timers);
      expect(member, isNotNull, reason: signature);
      return member!;
    }

    test('is whether the alarm is still scheduled as it was, asked after the '
        'wait and before the announcement', () {
      // The wait is the platform's time to report the ring, and a Stop inside
      // it takes the alarm out of the ringing set and the scheduled one
      // alike. Asked before the wait, the question still finds the alarm
      // scheduled; asked after the announcement, it comes too late.
      final rang = memberOf(
        'static Future<void> _alarmRang(AlarmSettings settings) async {',
      );
      final wait = rang.indexOf('await Future<void>.delayed(');
      final asks = rang.indexOf('if (!_isScheduledAs(settings)) {');
      final announces = rang.indexOf('Alarm.alarmRang(settings);');

      expect(wait, isNonNegative);
      expect(asks, greaterThan(wait));
      expect(announces, greaterThan(asks));

      // And a no ends it there.
      final no = RegExp(
        r'if \(!_isScheduledAs\(settings\)\) \{([\s\S]*?)^    \}',
        multiLine: true,
      ).firstMatch(rang);
      expect(no, isNotNull);
      expect(no!.group(1)!.trim(), endsWith('return;'));
    });

    test('stands before the only announcement the timers make', () {
      // A second call anywhere in the file — on the way back to the
      // foreground, say — would announce a ring without asking.
      expect('Alarm.alarmRang('.allMatches(timers), hasLength(1));
    });

    test('compares the whole settings, not the id', () {
      // The scheduled set goes by id alone, and a snooze taken in the app
      // arms the alarm again under the id it rang under: asked by id, the
      // question finds the snooze and announces the ring it put off.
      final helper = RegExp(
        r'static bool _isScheduledAs\(AlarmSettings settings\) =>([^;]*);',
      ).firstMatch(timers);
      expect(helper, isNotNull);
      expect(
        helper!.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim(),
        'Alarm.scheduled.value.alarms.any((alarm) => alarm == settings)',
      );

      // Whole, because the settings' equality is: over every field, the
      // instant a snooze moves among them.
      final model = File(
        'packages/alarm/lib/model/alarm_settings.dart',
      ).readAsStringSync();
      expect(model, contains('class AlarmSettings extends Equatable {'));
      // Equatable's `==` and no override: one that compared the id alone
      // would leave every line this group reads exactly as it is.
      expect(model, isNot(contains('operator ==')));
      final props = RegExp(
        r'List<Object\?> get props => \[([\s\S]*?)\];',
      ).firstMatch(model);
      expect(props, isNotNull);
      expect(
        props!.group(1)!.split(',').map((field) => field.trim()),
        contains('dateTime'),
      );
    });
  });

  group("the colour of a ring's notification (Patch 8), in the fork's "
      'model', () {
    /// The model's code, its comments taken out: the helper's own comment
    /// names the platform overload it stands in for, and a name is not a
    /// call.
    final code =
        File('$fork/kotlin/com/gdelataillade/alarm/models/NotificationSettings.kt')
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//.*'), '');

    test('is packed with no call into android.graphics.Color', () {
      // Upstream's `Color.argb(float, float, float, float)` is API 26 and the
      // app runs from 24, where it threw from every Alarm.set. Any other
      // `Color` call answers 0 in the fork's JVM suite, so a colour made by
      // one could not be pinned there.
      expect(code, isNot(contains('Color.argb(')));
      expect(
        code,
        isNot(
          matches(
            RegExp(r'^import android\.graphics\.Color\b', multiLine: true),
          ),
        ),
      );
    });

    test('by the helper the wire is read through', () {
      final fromWire = RegExp(
        r'fun fromWire\(e: NotificationSettingsWire\): NotificationSettings \{'
        r'[\s\S]*?^        \}',
        multiLine: true,
      ).stringMatch(code);

      expect(fromWire, isNotNull);
      expect(fromWire, contains('iconColor = packArgb(a, r, g, b)'));
    });
  });

  group("a silent alarm past due as the plugin starts (Patch 9), in the "
      "plugin's Dart", () {
    final plugin = File('packages/alarm/lib/alarm.dart').readAsStringSync();

    /// `Alarm._checkAlarm`, whole: from its signature to the first brace that
    /// closes at a member's own indent.
    String checkAlarm() {
      final member = RegExp(
        r'static Future<void> _checkAlarm\(\) async \{[\s\S]*?^  \}',
        multiLine: true,
      ).stringMatch(plugin);
      expect(member, isNotNull);
      return member!;
    }

    test('is stopped only after the host is asked whether another alarm '
        'sounds', () {
      // An alarm held back behind one that sounds is stored, past due and
      // silent, like a dead one; once stopped it is out of the host's queue
      // and never rings. The question is the host's, with no id: Dart has
      // not been told of the held alarm, and its own ringing set may not
      // have been filled yet. And it comes before the re-read, which has to
      // follow every await: a snooze landing during an await after it would
      // be stopped at the time it was snoozed from.
      final check = checkAlarm();
      final asks = check.indexOf(
        'if (android && await AndroidAlarm().isRinging()) {',
      );
      final rereads = check.indexOf(
        'final current = await getAlarm(alarm.id);',
      );
      final stops = check.indexOf('await stop(alarm.id);');

      expect(asks, isNonNegative);
      expect(rereads, greaterThan(asks));
      expect(stops, greaterThan(rereads));
      expect('await stop('.allMatches(check), hasLength(1));
    });

    test('and is left stored while one does', () {
      final yes = RegExp(
        r'if \(android && await AndroidAlarm\(\)\.isRinging\(\)\) \{'
        r'([\s\S]*?)^          \}',
        multiLine: true,
      ).firstMatch(checkAlarm());

      expect(yes, isNotNull);
      expect(yes!.group(1)!.trim(), endsWith('continue;'));
    });
  });
}
