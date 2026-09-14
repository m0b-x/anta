import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/shell_batch.dart';
import 'fake_process_runner.dart';

/// Real output from `emulator-5554`, Android 16, captured 2026-09-14.
const List<String> _realProbe = [
  'Physical size: 1280x2856',
  'Physical density: 480',
  '8911',
  '    topResumedActivity=ActivityRecord{209481557 u0 '
      'com.alexzamfir.anta/.MainActivity t59}',
  '  mWakefulness=Awake',
  '    isKeyguardShowing=false',
  '      mInputShown=false',
];

void main() {
  group('parseScreenSize', () {
    test('reads the physical size and density', () {
      final size = parseScreenSize(
        'Physical size: 1280x2856',
        'Physical density: 480',
      );
      expect(size.width, 1280);
      expect(size.height, 2856);
      expect(size.density, 480);
      expect(size.isOverridden, isFalse);
      expect(size.widthDp, 427);
      expect(size.heightDp, 952);
    });

    test('an override wins for the working size but keeps the physical one', () {
      final size = parseScreenSize(
        'Physical size: 1280x2856\nOverride size: 1080x2400',
        'Physical density: 480',
      );
      expect(size.isOverridden, isTrue);
      expect(size.width, 1080);
      expect(size.physicalWidth, 1280);
      expect(size.toString(), contains('override of 1280x2856'));
    });

    test('unreadable output is a device failure that quotes what came back', () {
      expect(
        () => parseScreenSize('cmd: not found', ''),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('cmd: not found'))),
      );
    });

    test('a missing density falls back to 160 rather than dividing by zero', () {
      expect(parseScreenSize('Physical size: 100x200', '').density, 160);
    });
  });

  group('parseResumedActivity', () {
    test('pulls the component out of an ActivityRecord line', () {
      expect(
        parseResumedActivity(_realProbe[3]),
        'com.alexzamfir.anta/.MainActivity',
      );
    });

    test('reads the older mResumedActivity wording too', () {
      expect(
        parseResumedActivity(
            '  mResumedActivity: ActivityRecord{1 u0 com.foo/.Bar t1}'),
        'com.foo/.Bar',
      );
    });

    test('nothing on an empty line', () {
      expect(parseResumedActivity(''), isNull);
    });
  });

  group('parseDeviceProbe', () {
    test('reads every field of a real probe', () {
      final probe = parseDeviceProbe(_realProbe);
      expect(probe.screen.width, 1280);
      expect(probe.appPid, 8911);
      expect(probe.resumedActivity, 'com.alexzamfir.anta/.MainActivity');
      expect(probe.foregroundPackage, 'com.alexzamfir.anta');
      expect(probe.awake, isTrue);
      expect(probe.locked, isFalse);
      expect(probe.imeShown, isFalse);
    });

    test('a missing dumpsys line reads as unknown, not as false', () {
      final probe = parseDeviceProbe([
        _realProbe[0],
        _realProbe[1],
        '',
        '',
        '',
        '',
        '',
      ]);
      expect(probe.appPid, isNull);
      expect(probe.resumedActivity, isNull);
      expect(probe.foregroundPackage, isNull);
      expect(probe.awake, isNull);
      expect(probe.locked, isNull);
      expect(probe.imeShown, isNull);
    });

    test('an asleep, locked device with the keyboard up reads that way', () {
      final probe = parseDeviceProbe([
        _realProbe[0],
        _realProbe[1],
        '',
        '',
        '  mWakefulness=Asleep',
        '    isKeyguardShowing=true',
        '      mInputShown=true',
      ]);
      expect(probe.awake, isFalse);
      expect(probe.locked, isTrue);
      expect(probe.imeShown, isTrue);
    });

    test('a short output list does not throw', () {
      expect(
        () => parseDeviceProbe([_realProbe[0], _realProbe[1]]),
        returnsNormally,
      );
    });

    test('flag() words the unknown state as a question mark', () {
      expect(DeviceProbe.flag(null, 'yes', 'no'), '?');
      expect(DeviceProbe.flag(true, 'up', 'down'), 'up');
      expect(DeviceProbe.flag(false, 'up', 'down'), 'down');
    });
  });

  group('deviceProbeCommands', () {
    final commands = deviceProbeCommands('com.alexzamfir.anta');

    test('asks for exactly the seven things parseDeviceProbe reads', () {
      expect(commands, hasLength(_realProbe.length));
    });

    test('every dumpsys read is piped into the device grep', () {
      final dumpsys = commands.where((c) => c.script.contains('dumpsys'));
      expect(dumpsys, hasLength(4));
      for (final command in dumpsys) {
        expect(command.script, contains('| grep -m1'));
        expect(command.script, contains('2>/dev/null'));
      }
    });

    test('the package id reaches the pidof call', () {
      expect(
        buildBatchScript(commands),
        contains("'pidof' 'com.alexzamfir.anta'"),
      );
    });
  });

  group('AndroidDevice round trips', () {
    test('screenSize is one batched call and is then cached', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
          0,
          'Physical size: 1280x2856\n__QA_SEP__\nPhysical density: 480\n'
              '__QA_SEP__\n',
          '',
        ),
      );
      final device =
          AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      expect((await device.screenSize()).width, 1280);
      expect((await device.screenSize()).width, 1280);
      expect(fake.calls, hasLength(1));
    });

    test('probe is one batched call and seeds the screen cache', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: RunOutcome(
          0,
          '${_realProbe.join('\n__QA_SEP__\n')}\n__QA_SEP__\n',
          '',
        ),
      );
      final device =
          AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      final probe = await device.probe();
      expect(probe.appPid, 8911);
      await device.screenSize();
      expect(fake.calls, hasLength(1));
    });

    test('isInstalled reads pm path', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
            0, 'package:/data/app/~~abc==/base.apk', ''),
      );
      final device =
          AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      expect(await device.isInstalled(), isTrue);
      expect(fake.lines.single, 'adb -s e shell pm path com.alexzamfir.anta');
    });

    test('isInstalled is false when pm path says nothing', () async {
      final device = AndroidDevice(Adb(
        executable: 'adb',
        runner: FakeProcessRunner(defaultOutcome: const RunOutcome(1, '', '')),
        serial: 'e',
      ));
      expect(await device.isInstalled(), isFalse);
    });

    test('typeTextChecked batches the IME probe with the typing', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
            0, '  mInputShown=true\n__QA_SEP__\n__QA_SEP__\n', ''),
      );
      final device =
          AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      expect(await device.typeTextChecked('squat'), isTrue);
      expect(fake.calls, hasLength(1));
      expect(fake.lines.single, contains("input text 'squat'"));
      expect(fake.lines.single, isNot(contains(r"\'")));
    });

    test('typeTextChecked reports a missing keyboard', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
            0, '  mInputShown=false\n__QA_SEP__\n__QA_SEP__\n', ''),
      );
      final device =
          AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      expect(await device.typeTextChecked('squat'), isFalse);
    });
  });

  group('the leftover uiautomator probe', () {
    test('brackets the first letter so it cannot match its own shell', () {
      expect(leftoverUiautomatorProbe, contains('[u]iautomator'));
      expect(leftoverUiautomatorProbe, isNot(contains(' uiautomator')));
      expect(killLeftoverUiautomator, contains('[u]iautomator'));
    });
  });
}
