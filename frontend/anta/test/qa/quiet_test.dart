import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/guest_state.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/quiet.dart';
import 'fake_process_runner.dart';
import 'fake_sleep.dart';

/// `dumpsys alarm` with [count] of the app's alarms armed.
String _dumpsys(int count) => [
  'Pending alarm batches: 1',
  for (var i = 0; i < count; i++)
    '    RTC_WAKEUP #$i: Alarm{1a2b$i type 0 origWhen 1 com.alexzamfir.anta}',
  '    RTC #9: Alarm{9f type 1 origWhen 1 com.android.other}',
].join('\n');

/// `dumpsys activity services com.alexzamfir.anta`, the plugin's ring
/// service running when [ringing] (the shape API 36 prints).
String _services({required bool ringing}) => [
  'ACTIVITY MANAGER SERVICES (dumpsys activity services)',
  if (ringing) ...[
    '  User 0 active services:',
    '  * ServiceRecord{5e1c2f0 u0 com.alexzamfir.anta/'
        'com.gdelataillade.alarm.alarm.AlarmService c:com.alexzamfir.anta}',
    '    app=ProcessRecord{a1 4242:com.alexzamfir.anta/u0a190}',
  ] else
    '  (nothing)',
].join('\n');

/// adb for fleet guest anta_qa_1 on emulator-5556: the app installed unless
/// [installed] is false, each `dumpsys alarm` answering the next of [armed]
/// (the last repeats).
class _GuestAdb extends FakeProcessRunner {
  List<int> armed = const [0];
  bool installed = true;
  int counts = 0;

  /// Whether each `dumpsys activity services` lists the ring service, in
  /// order; the last repeats. Null answers with nothing at all.
  List<bool?> ringing = const [false];
  int ringReads = 0;

  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  }) async {
    final request = RunRequest(executable, arguments);
    calls.add(request);
    switch (request.line) {
      case 'adb -s emulator-5556 shell pm path com.alexzamfir.anta':
        return installed
            ? const RunOutcome(0, 'package:/data/app/base.apk', '')
            : const RunOutcome(1, '', '');
      case 'adb -s emulator-5556 shell dumpsys alarm':
        final count = armed[counts.clamp(0, armed.length - 1)];
        counts++;
        return RunOutcome(0, _dumpsys(count), '');
      case 'adb -s emulator-5556 shell dumpsys activity services '
          'com.alexzamfir.anta':
        final ring = ringing[ringReads.clamp(0, ringing.length - 1)];
        ringReads++;
        return RunOutcome(0, ring == null ? '' : _services(ringing: ring), '');
    }
    return defaultOutcome;
  }
}

void main() {
  late _GuestAdb runner;
  late Adb adb;
  late List<List<String>> relaunched;
  late DateTime clock;

  ChildOutcome exited(int code, {bool timedOut = false}) => ChildOutcome(
    exitCode: code,
    took: Duration.zero,
    started: true,
    timedOut: timedOut,
  );

  /// What the relaunch child prints, the app's `[qa]` lines among it.
  List<String> printed(int rings, int cancelled) => [
    'qa_reset marker dropped',
    '[qa] reset: cleared preferences and qa.db',
    '[qa] quiet: stopped $rings ring(s), cancelled $cancelled alarm(s), '
        'took down 0 notification(s)',
    '[qa] onboarding marked completed',
  ];

  Future<GuestQuiet> quiet({
    bool always = false,
    ChildOutcome? outcome,
    List<String>? lines,
  }) => quietGuest(
    adb: adb,
    always: always,
    relaunch: (arguments, limit, onLine) async {
      relaunched.add(arguments);
      (lines ?? printed(0, 0)).forEach(onLine);
      return outcome ?? exited(0);
    },
    sleep: boundedSleep('the quiet loop', (d) => clock = clock.add(d)),
    clock: () => clock,
  );

  setUp(() {
    runner = _GuestAdb();
    adb = Adb(executable: 'adb', runner: runner, serial: 'emulator-5556');
    relaunched = [];
    clock = DateTime.utc(2026, 11, 11, 9);
  });

  group('quietGuest', () {
    test('counts first and relaunches nothing when nothing is armed', () async {
      final result = await quiet();
      expect(relaunched, isEmpty);
      expect(result.ok, isTrue);
      expect(quietWorthSaying(result), isFalse);
      expect(
        result.line('anta_qa_1', 'before the stop'),
        'quiet: no app alarm armed on anta_qa_1 before the stop',
      );
    });

    test('relaunches fresh, without a seed, and counts again', () async {
      runner.armed = [3, 1, 0];
      final result = await quiet();
      expect(relaunched, [
        ['-d', 'emulator-5556', 'relaunch', '--fresh', '--await-quiet'],
      ]);
      expect((result.before, result.after, result.ok), (3, 0, true));
      expect(
        result.line('anta_qa_1', 'before the stop'),
        'quiet: 3 alarm(s) on anta_qa_1 cancelled before the stop',
      );
    });

    test('always relaunches, for a guest whose pass died', () async {
      await quiet(always: true);
      expect(relaunched, hasLength(1));
    });

    test('a stop\'s quiet reports what the app took off its stores', () async {
      // Found live: a force-stopped app shows nothing armed while the plugin
      // still stores every alarm, and the boot after the stop re-armed 7.
      final result = await quiet(always: true, lines: printed(0, 7));
      expect((result.before, result.app?.cancelled, result.ok), (0, 7, true));
      expect(quietWorthSaying(result), isTrue);
      expect(
        result.line('anta_qa_1', 'before the stop'),
        'quiet: 7 alarm(s) on anta_qa_1 cancelled before the stop',
      );
    });

    test('a stop\'s quiet that ended nothing says nothing', () async {
      final result = await quiet(always: true);
      expect(result.ok, isTrue);
      expect(quietWorthSaying(result), isFalse);
    });

    test(
      'a relaunch without the app\'s quiet line is a failed quiet',
      () async {
        // The count after a force-stop reads quiet whatever the app did, so
        // only the app's own line says its stores were emptied.
        runner.armed = [6, 0];
        runner.ringing = [true, false];
        final result = await quiet(
          lines: const [
            'qa_reset marker dropped',
            '[qa] reset: cleared preferences and qa.db',
          ],
        );
        expect(result.ok, isFalse);
        expect(quietWorthSaying(result), isTrue);
        expect(
          result.line('anta_qa_1', 'before the stop'),
          startsWith(
            'warning: quiet: anta_qa_1 was not quieted before the stop — the '
            'app never said it had quieted itself',
          ),
        );
      },
    );

    test('the app\'s own failure is the quiet\'s failure', () async {
      final result = await quiet(
        always: true,
        lines: const ['[qa] quiet threw StateError: no binding'],
      );
      expect(result.failure, 'quiet threw StateError: no binding');
    });

    test('reads the app\'s quiet line, and only that one', () {
      expect(parseAppQuiet(printed(1, 6)), (rings: 1, cancelled: 6));
      expect(parseAppQuiet(const ['[qa] reset: cleared preferences']), isNull);
    });

    test('a relaunch past its limit is a failure, never a throw', () async {
      runner.armed = [2];
      final result = await quiet(outcome: exited(3, timedOut: true));
      expect(result.ok, isFalse);
      expect(
        result.line('anta_qa_1', 'before the stop'),
        'warning: quiet: anta_qa_1 was not quieted before the stop — the '
        'relaunch ran past 20 s',
      );
    });

    test('alarms still armed at the limit are a failure', () async {
      runner.armed = [2];
      final result = await quiet();
      expect(result.after, 2);
      expect(result.ok, isFalse);
    });

    test('a ring in progress with nothing armed is no quiet guest', () async {
      // Found live: a dead pass's alarm rang on with the armed count at 0,
      // and a count-gated quiet skipped the guest.
      runner.ringing = [true, false];
      final result = await quiet(lines: printed(1, 0));
      expect(relaunched, hasLength(1));
      expect((result.before, result.ringing, result.ok), (0, true, true));
      expect(
        result.line('anta_qa_1', 'before the stop'),
        'quiet: 0 alarm(s) and a ring in progress on anta_qa_1 cancelled '
        'before the stop',
      );
    });

    test('a ring that outlives the relaunch is a failure', () async {
      runner.ringing = [true];
      final result = await quiet();
      expect(result.ok, isFalse);
      expect(result.failure, 'an alarm still ringing after it');
    });

    test('a services dump that did not answer never reads as silent', () async {
      runner.ringing = [null];
      final result = await quiet();
      expect(relaunched, isEmpty);
      expect(result.ok, isFalse);
    });

    test('the ring service is read from its own record only', () {
      expect(
        ringServiceRunning(_services(ringing: true), 'com.alexzamfir.anta'),
        isTrue,
      );
      expect(
        ringServiceRunning(_services(ringing: false), 'com.alexzamfir.anta'),
        isFalse,
      );
      expect(
        ringServiceRunning(_services(ringing: true), 'com.android.other'),
        isFalse,
      );
    });

    test('a guest without the QA app is left as it is', () async {
      runner.installed = false;
      final result = await quiet(always: true);
      expect(relaunched, isEmpty);
      expect(result.skipped, isNotNull);
      expect(runner.lines, isNot(contains(contains('dumpsys'))));
    });

    test(
      'an adb that cannot answer is a failure, not "not installed"',
      () async {
        final silent = FakeProcessRunner(
          defaultOutcome: const RunOutcome(
            1,
            '',
            "error: device 'x' not found",
          ),
        );
        final result = await quietGuest(
          adb: Adb(executable: 'adb', runner: silent, serial: 'emulator-5556'),
          relaunch: (_, _, _) async => exited(0),
        );
        expect(result.ok, isFalse);
        expect(result.skipped, isNull);
      },
    );
  });

  group('after a boot', () {
    late Directory root;
    late QaPaths paths;
    late FleetHost host;
    late List<String> said;
    late List<String> quieted;

    Future<void> afterBoot() => quietAfterBoot(
      host: host,
      paths: paths,
      index: 1,
      quiet: (serial) async {
        quieted.add(serial);
        return const GuestQuiet(before: 2, after: 0, relaunched: true);
      },
      say: said.add,
      sleep: boundedSleep(
        'the boot-receiver wait',
        (d) => clock = clock.add(d),
      ),
      clock: () => clock,
    );

    setUp(() {
      root = Directory.systemTemp.createTempSync('anta_qa_quiet_boot_');
      paths = QaPaths(root.path)..ensureFleetState();
      host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: joinPath(root.path, ['avd']),
        sdkRoot: null,
        windows: false,
      );
      said = [];
      quieted = [];
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('waits for the boot receiver, then quiets what it re-armed', () async {
      runner.armed = [0, 0, 2];
      await afterBoot();
      expect(runner.counts, 3, reason: 'the receiver gets its moment');
      expect(quieted, ['emulator-5556']);
      expect(said, ['quiet: 2 alarm(s) on anta_qa_1 cancelled after the boot']);
    });

    test('a stored alarm the receiver rang at once is quieted too', () async {
      runner.ringing = [false, true];
      await afterBoot();
      expect(quieted, ['emulator-5556']);
    });

    test('says so when the receiver re-armed nothing', () async {
      await afterBoot();
      expect(quieted, isEmpty);
      expect(said, ['quiet: no app alarm armed on anta_qa_1 after the boot']);
      expect(
        clock.difference(DateTime.utc(2026, 11, 11, 9)),
        greaterThanOrEqualTo(bootReceiverWait),
      );
    });

    test('a guest someone holds is the holder\'s to reseed', () async {
      runner.armed = [2];
      GuestState.take(
        paths.guestStateFor('anta_qa_1'),
        GuestHold(pid: 4711, verb: 'pass', since: clock),
      );
      // The liveness probe prints nothing: the holder could not be
      // checked, and an unknown holder still holds.
      await afterBoot();
      expect(quieted, isEmpty);
      expect(said, isEmpty);
      expect(runner.lines, isNot(contains(contains('dumpsys'))));
    });
  });

  test(
    'a child past its limit is killed and reported as timed out',
    () async {
      final started = DateTime.now();
      final outcome = await runQaChild(
        executable: 'cmd',
        arguments: ['/c', 'ping', '-n', '30', '127.0.0.1'],
        workingDirectory: Directory.systemTemp.path,
        timeout: const Duration(seconds: 1),
        onLine: (_, _) {},
      );
      expect(outcome.timedOut, isTrue);
      expect(outcome.exitCode, isNot(0));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 10)),
      );
    },
    skip: Platform.isWindows ? false : 'cmd and ping -n are Windows-only',
  );
}
