import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two patches of the `alarm` fork (`packages/alarm/`) sit where its own
/// tests cannot reach. Patch 5 is one attribute of the library's manifest.
/// Patch 6's rule is unit-tested in Kotlin (`RingWakeLockTest`), but over a
/// stand-in for the platform's lock: the three places that call the rule, and
/// the three lines that pass its calls on to the real lock, are inside an
/// Android `Service`, which that JVM-only suite cannot build.
///
/// Either is undone, with nothing failing, by taking a newer upstream copy of
/// its file — upstream ships the receiver exported and the lock in a local
/// nothing releases — and neither loss shows on a phone: one is a door left
/// open to every other app, the other five minutes of battery a ring. So the
/// two are held here, by reading the source.
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
}
