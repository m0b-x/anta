import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/doctor.dart';

DeviceProbe _probe({
  String size = 'Physical size: 1280x2856',
  String pid = '8911',
  String activity = '  topResumedActivity=ActivityRecord{1 u0 '
      'com.alexzamfir.anta/.MainActivity t59}',
  String wake = '  mWakefulness=Awake',
  String keyguard = '    isKeyguardShowing=false',
}) =>
    parseDeviceProbe([
      size,
      'Physical density: 480',
      pid,
      activity,
      wake,
      keyguard,
      '      mInputShown=false',
    ]);

void main() {
  group('checkAdbServer', () {
    test('a missing binary fails and names the environment variables', () {
      final result = checkAdbServer(
        adbPath: null,
        failure: null,
        deviceCount: null,
      );
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('ANDROID_HOME'));
    });

    test('a hung server fails with the kill-server fix', () {
      final result = checkAdbServer(
        adbPath: 'adb',
        failure: 'adb did not answer in 5s',
        deviceCount: 0,
      );
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('adb kill-server'));
    });

    test('a healthy server is ok and reports the path', () {
      final result =
          checkAdbServer(adbPath: 'C:/sdk/adb.exe', failure: null, deviceCount: 1);
      expect(result.status, CheckStatus.ok);
      expect(result.detail, contains('C:/sdk/adb.exe'));
    });
  });

  group('checkDeviceAttached', () {
    test('nothing attached fails with `qa boot`', () {
      final result = checkDeviceAttached(const []);
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('qa boot'));
    });

    test('an offline device fails with the cold-boot explanation', () {
      final result = checkDeviceAttached(
        parseDevices('List of devices attached\nemulator-5554\toffline\n'),
      );
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('cold-boot'));
    });

    test('a usable device is ok', () {
      final result = checkDeviceAttached(
        parseDevices('List of devices attached\nemulator-5554\tdevice\n'),
      );
      expect(result.status, CheckStatus.ok);
      expect(result.detail, contains('emulator-5554'));
    });
  });

  group('checkBootProps', () {
    test('both flags set is ok', () {
      expect(
        checkBootProps(bootCompleted: '1', provisioned: '1').status,
        CheckStatus.ok,
      );
    });

    test('a half-booted guest fails and shows both values', () {
      final result = checkBootProps(bootCompleted: '', provisioned: '1');
      expect(result.status, CheckStatus.fail);
      expect(result.detail, contains('boot_completed=?'));
    });
  });

  group('checkAwake', () {
    test('awake and unlocked is ok', () {
      expect(checkAwake(_probe()).status, CheckStatus.ok);
    });

    test('asleep fails and offers the wake fix', () {
      final result = checkAwake(_probe(wake: '  mWakefulness=Asleep'));
      expect(result.status, CheckStatus.fail);
      expect(result.fixVerb, DoctorFix.wake);
    });

    test('locked fails even when the screen is on', () {
      final result =
          checkAwake(_probe(keyguard: '    isKeyguardShowing=true'));
      expect(result.status, CheckStatus.fail);
      expect(result.detail, contains('locked=yes'));
    });

    test('an unreadable wakefulness line is treated as not awake', () {
      expect(checkAwake(_probe(wake: '')).status, CheckStatus.fail);
    });
  });

  group('checkScreenOverride', () {
    test('no override is ok', () {
      expect(checkScreenOverride(_probe()).status, CheckStatus.ok);
    });

    test('an override warns and offers unphone', () {
      final result = checkScreenOverride(_probe(
        size: 'Physical size: 1280x2856\nOverride size: 1080x2400',
      ));
      expect(result.status, CheckStatus.warn);
      expect(result.fixVerb, DoctorFix.unphone);
    });
  });

  group('checkAppInstalled', () {
    test('an installed debug build is ok', () {
      final result = checkAppInstalled(
        pmPath: 'package:/data/app/~~x==/base.apk',
        runAsId: 'uid=10123(u0_a123) gid=10123',
      );
      expect(result.status, CheckStatus.ok);
    });

    test('nothing installed fails with `qa run`', () {
      final result = checkAppInstalled(pmPath: '', runAsId: '');
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('qa run'));
    });

    test('a release build that refuses run-as fails on its own line', () {
      final result = checkAppInstalled(
        pmPath: 'package:/data/app/~~x==/base.apk',
        runAsId: 'run-as: package not debuggable',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.detail, contains('run-as'));
      expect(result.fix, contains('not debuggable'));
    });
  });

  group('checkAppRunning', () {
    test('running and on top is ok', () {
      expect(
        checkAppRunning(_probe(), 'com.alexzamfir.anta').status,
        CheckStatus.ok,
      );
    });

    test('no process warns with both restart paths', () {
      final result =
          checkAppRunning(_probe(pid: ''), 'com.alexzamfir.anta');
      expect(result.status, CheckStatus.warn);
      expect(result.fix, contains('qa relaunch'));
    });

    test('another app on top warns and names it', () {
      final result = checkAppRunning(
        _probe(
          activity: '  topResumedActivity=ActivityRecord{1 u0 '
              'com.google.android.apps.nexuslauncher/.NexusLauncherActivity t1}',
        ),
        'com.alexzamfir.anta',
      );
      expect(result.status, CheckStatus.warn);
      expect(result.detail, contains('nexuslauncher'));
    });
  });

  group('checkUiautomator', () {
    test('a clean dump is ok and reports its duration', () {
      final result = checkUiautomator(
        dumped: true,
        took: const Duration(milliseconds: 1800),
        leftoverPids: '',
      );
      expect(result.status, CheckStatus.ok);
      expect(result.detail, contains('1800 ms'));
    });

    test('a leftover process warns even when the dump worked', () {
      final result = checkUiautomator(
        dumped: true,
        took: const Duration(milliseconds: 900),
        leftoverPids: '10022',
      );
      expect(result.status, CheckStatus.warn);
      expect(result.fixVerb, DoctorFix.killUiautomator);
    });

    test('a failed dump with a leftover blames the leftover', () {
      final result = checkUiautomator(
        dumped: false,
        took: const Duration(seconds: 45),
        leftoverPids: '10022',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.detail, contains('10022'));
      expect(result.fixVerb, DoctorFix.killUiautomator);
    });

    test('a failed dump with no leftover blames the animation', () {
      final result = checkUiautomator(
        dumped: false,
        took: const Duration(seconds: 45),
        leftoverPids: '',
      );
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('animating'));
      expect(result.fixVerb, isNull);
    });
  });

  group('checkDataSpace', () {
    test('reads the available column of a real df line', () {
      final result = checkDataSpace(
        '/dev/block/dm-55  32847728 2369284  30330988   8% /data/user/0',
      );
      expect(result.status, CheckStatus.ok);
      expect(result.detail, '29620 MB free');
    });

    test('warns below half a gigabyte with the resize note', () {
      final result = checkDataSpace(
        '/dev/block/dm-55  32847728 32500000  300000  99% /data/user/0',
      );
      expect(result.status, CheckStatus.warn);
      expect(result.fix, contains('cannot grow in place'));
    });

    test('unreadable output warns rather than failing the run', () {
      final result = checkDataSpace('df: /data: Permission denied');
      expect(result.status, CheckStatus.warn);
      expect(result.detail, contains('Permission denied'));
    });
  });

  group('checkHostRun', () {
    test('a live run.pid and no orphans is ok', () {
      final result = checkHostRun(
        recordedPid: 2804,
        pidAlive: true,
        orphanedServices: const [],
      );
      expect(result.status, CheckStatus.ok);
    });

    test('no run.pid at all is ok', () {
      expect(
        checkHostRun(
          recordedPid: null,
          pidAlive: false,
          orphanedServices: const [],
        ).status,
        CheckStatus.ok,
      );
    });

    test('a stale run.pid warns and offers to delete it', () {
      final result = checkHostRun(
        recordedPid: 2804,
        pidAlive: false,
        orphanedServices: const [],
      );
      expect(result.status, CheckStatus.warn);
      expect(result.fixVerb, DoctorFix.deleteRunPid);
    });

    test('orphaned services warn and offer the reap', () {
      final result = checkHostRun(
        recordedPid: null,
        pidAlive: false,
        orphanedServices: const [1234, 5678],
      );
      expect(result.status, CheckStatus.warn);
      expect(result.detail, contains('1234, 5678'));
      expect(result.fixVerb, DoctorFix.reapServices);
    });
  });

  group('checkDtd', () {
    test('a recorded URI with a healthy log is ok', () {
      expect(
        checkDtd(dtd: 'ws://127.0.0.1:1/x=', runLogTail: 'Syncing files')
            .status,
        CheckStatus.ok,
      );
    });

    test('no URI warns', () {
      expect(checkDtd(dtd: '  ', runLogTail: '').status, CheckStatus.warn);
    });

    test('a lost connection warns and points at attach', () {
      final result = checkDtd(
        dtd: 'ws://127.0.0.1:1/x=',
        runLogTail: 'Lost connection to device.',
      );
      expect(result.status, CheckStatus.warn);
      expect(result.fix, contains('qa attach'));
    });
  });

  group('checkExeFreshness', () {
    test('no exe warns with build-exe', () {
      final result =
          checkExeFreshness(exists: false, stale: false, staleSource: null);
      expect(result.status, CheckStatus.warn);
      expect(result.fix, contains('qa build-exe'));
    });

    test('a fresh exe is ok', () {
      expect(
        checkExeFreshness(exists: true, stale: false, staleSource: null).status,
        CheckStatus.ok,
      );
    });

    test('a stale exe names the source that overtook it', () {
      final result = checkExeFreshness(
        exists: true,
        stale: true,
        staleSource: 'tool/qa/src/device.dart',
      );
      expect(result.status, CheckStatus.warn);
      expect(result.detail, contains('device.dart'));
    });
  });

  group('anyFailed', () {
    test('warnings alone do not fail the run', () {
      expect(
        anyFailed([
          const CheckResult.ok('a', 'fine'),
          const CheckResult(name: 'b', status: CheckStatus.warn, detail: 'eh'),
        ]),
        isFalse,
      );
    });

    test('one FAIL is enough', () {
      expect(
        anyFailed([
          const CheckResult.ok('a', 'fine'),
          const CheckResult(name: 'b', status: CheckStatus.fail, detail: 'no'),
        ]),
        isTrue,
      );
    });
  });

  group('CheckResult rendering', () {
    test('a fix is printed on its own indented line', () {
      const result = CheckResult(
        name: 'awake',
        status: CheckStatus.fail,
        detail: 'awake=no locked=yes',
        fix: 'run `qa wake`',
      );
      final lines = result.describe().split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, startsWith('FAIL'));
      expect(lines.last.trim(), startsWith('→'));
    });

    test('json carries the status name and the fix', () {
      const result = CheckResult(
        name: 'screen',
        status: CheckStatus.warn,
        detail: '1080x2400',
        fix: 'run `qa unphone`',
      );
      expect(result.toJson(), {
        'check': 'screen',
        'status': 'warn',
        'detail': '1080x2400',
        'fix': 'run `qa unphone`',
      });
    });
  });
}
