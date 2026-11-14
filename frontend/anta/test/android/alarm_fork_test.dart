import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Six of the `alarm` fork's ten patches (`packages/alarm/`) are held here,
/// by reading their source. A newer upstream copy of the file any of them
/// lives in would undo it with nothing in the app's `flutter test` failing,
/// and none of the six losses would be seen in a day's use of the app.
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
///
/// Patch 10 is on both sides and in the app: an engine that is not a
/// presenter (`AlarmPluginTest`, `alarm_non_presenter_test.dart`). Without it
/// an alarm that rings while the shared check runs with the app closed is
/// reported to the check's isolate — no page, and a silence timer that ends
/// with it — and every such run re-arms every stored alarm. What neither of
/// the fork's suites can hold is that the two sides spell one channel alike
/// and that the app's binding takes the right start, which no suite can
/// build off a device.
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

  group('an engine that is not a presenter (Patch 10)', () {
    final host = File(
      '$fork/kotlin/com/gdelataillade/alarm/alarm/AlarmPlugin.kt',
    ).readAsStringSync();
    final plugin = File('packages/alarm/lib/alarm.dart').readAsStringSync();
    final base = File(
      'packages/alarm/lib/src/base_alarm.dart',
    ).readAsStringSync();
    final binding = File(
      'lib/services/android_alert_gateway.dart',
    ).readAsStringSync();
    final registration = File('lib/core/di/injection.dart').readAsStringSync();

    /// One member of a Dart class, whole: from its signature to the first
    /// brace that closes at a member's own indent.
    String memberOf(String source, String signature) {
      final member = RegExp(
        '${RegExp.escape(signature)}[\\s\\S]*?^  \\}',
        multiLine: true,
      ).stringMatch(source);
      expect(member, isNotNull, reason: signature);
      return member!;
    }

    /// [source] without its comment lines.
    String uncommented(String source) => source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .where((line) => !line.trimLeft().startsWith('*'))
        .join('\n');

    test('the two sides say the same channel and the same word', () {
      // Hand-written beside the generated bindings, so nothing but this
      // holds the two spellings together: renamed on one side, the run's
      // start throws and its pass arms nothing — or, worse, a host that
      // answered another word leaves the run a presenter.
      const channel = 'com.gdelataillade.alarm/presenter';

      expect(
        host,
        contains('internal const val PRESENTER_CHANNEL = "$channel"'),
      );
      expect(host, contains('internal const val RESIGN = "resign"'));
      expect(
        plugin,
        matches(
          RegExp(
            "static const _presenterChannel = MethodChannel\\(\\s*'"
            "${RegExp.escape(channel)}',?\\s*\\);",
          ),
        ),
      );
      expect(
        plugin,
        contains("await _presenterChannel.invokeMethod<void>('resign');"),
      );
    });

    test('the host sets a resigned engine aside before it picks whom to '
        'tell, on the one path every report takes', () {
      final code = uncommented(host);

      // The getter is one call of the function the unit test asks, handed
      // the engines' own word on whether they present...
      expect(
        code,
        matches(
          RegExp(
            r'get\(\) = synchronized\(attached\) \{\s*'
            r'presenterAmong\(\s*attached,\s*\{ it\.presents \},\s*'
            r'\{ it\.activity != null \},\s*\{ it\.hadActivity \},\s*'
            r'\)\?\.triggerApi\s*\}',
          ),
        ),
      );
      // ...and that function sets the resigned aside before it picks.
      expect(
        code,
        contains(
          '): T? = presenterOf(presenters(attached, presents), '
          'hasActivity, hadActivity)',
        ),
      );
      expect(
        'presenterOf('.allMatches(code),
        hasLength(2),
        reason: 'its declaration and the one call',
      );
      expect('presenterAmong('.allMatches(code), hasLength(2));

      // The run's engine says so in its entry before Firebase and the
      // database come up (review R7) — right after a QA build's preferences
      // are namespaced, which the resign's own look at them must not
      // precede, and for a bound at most.
      final entry = File(
        'lib/services/shared_refresh/shared_refresh_entry.dart',
      ).readAsStringSync();
      expect(
        entry,
        matches(
          RegExp(
            r'if \(!SharedRefreshAvailability\.isSupported\) return true;\s*'
            r'QaBootstrap\.namespacePreferences\(\);\s*'
            r'await _resignAsPresenter\(resign, resignBound\);\s*'
            r'return fire\(',
          ),
        ),
      );
      expect(entry, matches(RegExp(r'fire =\s*fireSharedRefresh,')));
      expect(entry, contains('resign = _resignWithHost,'));
      expect(entry, contains('await Alarm.initWithoutPresenting();'));
      // Resigning is one way: nothing gives the word back.
      expect(
        RegExp(
          r'\bpresents = (true|false)',
        ).allMatches(code).map((write) => write.group(0)),
        ['presents = true', 'presents = false'],
        reason: 'its declaration and the resignation',
      );
      expect(
        code,
        matches(
          RegExp(
            r'if \(call\.method == RESIGN\) \{\s*presents = false\s*'
            r'result\.success\(null\)',
          ),
        ),
      );
    });

    test('the start that resigns says so first, and neither reconciles nor '
        'takes the host\'s reports', () {
      final start = memberOf(
        plugin,
        'static Future<void> initWithoutPresenting() async {',
      );

      expect(
        start.indexOf("invokeMethod<void>('resign')"),
        inInclusiveRange(0, start.indexOf('await AlarmStorage.init();')),
      );
      // `checkAlarm` sets every stored future alarm again and drains the
      // host's markers; the trigger handlers are how a ring reaches Dart.
      expect(start, isNot(contains('checkAlarm')));
      expect(start, isNot(contains('AlarmTriggerApiImpl')));
      expect(start, isNot(contains('_applyPendingEvents')));
    });

    test('and what it sets gets no fallback timer, which would announce the '
        'ring to the isolate that armed it', () {
      expect(
        uncommented(base),
        contains('if (Alarm.presents) PlatformTimers.setAlarm(settings);'),
      );
      expect(
        'PlatformTimers.setAlarm('.allMatches(uncommented(base)),
        hasLength(1),
      );
    });

    group('in the app\'s binding', () {
      const start = 'Future<void> _initialize() async {';

      test('a binding that presents nothing resigns before anything else, '
          'and never starts the plugin the presenting way', () {
        final code = uncommented(memberOf(binding, start));
        const resigns =
            'if (!presentsAlarms) await Alarm.initWithoutPresenting();';
        const leaves = 'if (!presentsAlarms) return;';
        const presents =
            'await Alarm.init(acknowledgeEventsAutomatically: '
            'false);';

        expect(
          code.trimLeft().substring(start.length).trimLeft(),
          startsWith(resigns),
        );
        // Everything of the plugin's that is the presenter's comes after
        // the line a non-presenter leaves at: its reconciliation, and both
        // of its streams.
        final left = code.indexOf(leaves);
        expect(left, isNonNegative);
        for (final presenters in [
          presents,
          'Alarm.events.listen(',
          'Alarm.ringing.listen(',
        ]) {
          expect(
            code.indexOf(presenters),
            greaterThan(left),
            reason: presenters,
          );
          expect(
            presenters.allMatches(uncommented(binding)),
            hasLength(1),
            reason: presenters,
          );
        }
        expect(
          'Alarm.initWithoutPresenting('.allMatches(uncommented(binding)),
          hasLength(1),
        );
      });

      test('it notes a ring in progress for its pass and shows it to '
          'nobody: no page, no timer, no word on the stream', () {
        final lookup = uncommented(
          memberOf(binding, 'Future<void> _reportRingsInProgress() async {'),
        );
        final noted = RegExp(
          r'if \(!presentsAlarms\) \{([\s\S]*?)\}',
        ).firstMatch(lookup);

        expect(noted, isNotNull);
        expect(
          noted!.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim(),
          '_rings[alarm.id] = _ringReport(payload, alarm); continue;',
        );
        expect(
          lookup.indexOf('if (!presentsAlarms) {'),
          lessThan(lookup.indexOf('_emitRing(')),
        );
      });

      test('the check\'s run is given the one that presents nothing, the '
          'launch the one that presents — each named, neither by default', () {
        final run = memberOf(
          registration,
          'Future<void> configureSharedRefreshRunDependencies() async {',
        ).replaceFirst(RegExp(r'^  \}', multiLine: true), '}');

        expect(run, contains('_registerAlertGateway(presentsAlarms: false);'));
        expect(
          '_registerAlertGateway(presentsAlarms: true);'.allMatches(
            registration,
          ),
          hasLength(1),
        );
        expect(
          '_registerAlertGateway(presentsAlarms: false);'.allMatches(
            registration,
          ),
          hasLength(1),
        );
        expect(
          registration,
          contains(
            'void _registerAlertGateway({required bool presentsAlarms}) {',
          ),
        );
        expect(
          registration,
          contains('AndroidAlertGateway(presentsAlarms: presentsAlarms);'),
        );
        expect(
          binding,
          contains(
            'AndroidAlertGateway({this.presentsAlarms = '
            'true}) {',
          ),
        );
      });
    });
  });
}
