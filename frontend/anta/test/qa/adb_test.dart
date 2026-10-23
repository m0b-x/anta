import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/process_runner.dart';
import 'fake_process_runner.dart';

const String _devicesOutput = '''
List of devices attached
emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa
''';

void main() {
  group('parseDevices', () {
    test('reads the serial, the state and the model', () {
      final devices = parseDevices(_devicesOutput);
      expect(devices, hasLength(1));
      expect(devices.single.serial, 'emulator-5554');
      expect(devices.single.state, 'device');
      expect(devices.single.model, 'sdk_gphone64_x86_64');
      expect(devices.single.usable, isTrue);
    });

    test('keeps unusable rows but marks them so', () {
      final devices = parseDevices(
        'List of devices attached\nemulator-5556\toffline\nR58M\tunauthorized\n',
      );
      expect(devices.map((d) => d.state), ['offline', 'unauthorized']);
      expect(devices.every((d) => d.usable), isFalse);
    });

    test('ignores the header and daemon chatter', () {
      expect(
        parseDevices('* daemon not running; starting now at tcp:5037\n'
            'List of devices attached\n\n'),
        isEmpty,
      );
    });
  });

  group('countArmedAlarms', () {
    test('counts the pending rows, not the removal history or the stats', () {
      const dumpsys = '''
  42 pending alarms:
    RTC_WAKEUP #31: Alarm{edf8eb6 type 0 origWhen 1792803600000 whenElapsed 107671144 com.alexzamfir.anta}
      tag=*walarm*:com.alexzamfir.anta/com.gdelataillade.alarm.alarm.AlarmReceiver
    RTC_WAKEUP #32: Alarm{6bfb68d type 0 origWhen 1792806600000 whenElapsed 110671144 com.alexzamfir.anta}
    ELAPSED_WAKEUP #2: Alarm{a4384a2 type 2 origWhen 8487259 whenElapsed 8487259 com.google.android.gms}
    RTC #4: Alarm{1a2b3c4 type 1 origWhen 1 whenElapsed 1 com.alexzamfir.anta.other}
  Removal history:
    u0a217:
      #1: Reason=alarm_cancelled elapsed=-38m27s665ms rtc=2026-10-23 19:08:52.916
          type=RTC_WAKEUP tag=*walarm*:com.alexzamfir.anta/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
  Alarm Stats:
    u0a217:com.alexzamfir.anta +12ms running, 3 wakeups, 3 alarms: 0 fgs
''';
      expect(countArmedAlarms(dumpsys, 'com.alexzamfir.anta'), 2);
      expect(countArmedAlarms(dumpsys.replaceAll('RTC_WAKEUP #3', 'gone'), 'com.alexzamfir.anta'), 0);
    });
  });

  group('selectSerial', () {
    final one = parseDevices(_devicesOutput);
    final two = parseDevices('List of devices attached\n'
        'emulator-5554\tdevice\nemulator-5556\tdevice\n');

    test('an explicit -d wins over everything', () {
      expect(
        selectSerial(
          explicit: 'emulator-5556',
          envValue: 'emulator-5554',
          available: two,
        ),
        'emulator-5556',
      );
    });

    test('ANTA_QA_DEVICE is next', () {
      expect(selectSerial(envValue: 'emulator-5556', available: two),
          'emulator-5556');
    });

    test('the sole attached device is next', () {
      expect(selectSerial(available: one), 'emulator-5554');
    });

    test('two devices with no hint is a device failure listing both', () {
      expect(
        () => selectSerial(available: two),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('emulator-5554'))
            .having((e) => e.message, 'message', contains('emulator-5556'))),
      );
    });

    test('nothing attached names the verb that fixes it', () {
      expect(
        () => selectSerial(available: const []),
        throwsA(isA<DeviceFailure>().having(
          (e) => e.message,
          'message',
          'no device attached — run `qa boot`',
        )),
      );
    });

    test('an offline device is explained, not silently defaulted', () {
      final offline =
          parseDevices('List of devices attached\nemulator-5554\toffline\n');
      expect(
        () => selectSerial(available: offline),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('is offline'))
            .having((e) => e.message, 'message', contains('cold-boot'))),
      );
    });

    test('an unauthorized device points at the on-device prompt', () {
      final blocked =
          parseDevices('List of devices attached\nR58M\tunauthorized\n');
      expect(
        () => selectSerial(available: blocked),
        throwsA(isA<DeviceFailure>().having(
            (e) => e.message, 'message', contains('USB-debugging prompt'))),
      );
    });

    test('an explicit serial that is attached but unusable says which', () {
      final offline =
          parseDevices('List of devices attached\nemulator-5554\toffline\n');
      expect(
        () => selectSerial(explicit: 'emulator-5554', available: offline),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('is offline'))),
      );
    });

    test('an explicit serial that is not attached lists what is', () {
      expect(
        () => selectSerial(explicit: 'nosuch', available: one),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('nosuch is not attached'))
            .having((e) => e.message, 'message', contains('emulator-5554 (device)'))),
      );
    });

    test('the documented default serial is still the emulator name', () {
      expect(defaultSerial, 'emulator-5554');
    });
  });

  group('Adb command shape', () {
    late FakeProcessRunner fake;
    late Adb adb;

    setUp(() {
      fake = FakeProcessRunner();
      adb = Adb(executable: 'adb', runner: fake, serial: 'emulator-5554');
    });

    test('every call carries -s <serial>', () async {
      await adb.shell(['input', 'tap', '10', '20']);
      expect(fake.lines.single,
          'adb -s emulator-5554 shell input tap 10 20');
    });

    test('devices is asked without a serial', () async {
      fake.script('adb devices -l', const RunOutcome(0, _devicesOutput, ''));
      final devices = await adb.devices();
      expect(fake.lines.single, 'adb devices -l');
      expect(devices.single.serial, 'emulator-5554');
    });

    test('exec-out is requested in binary mode', () async {
      await adb.execOutBytes(['screencap', '-p']);
      expect(fake.calls.single.binary, isTrue);
      expect(fake.lines.single, 'adb -s emulator-5554 exec-out screencap -p');
    });

    test('a failing shell throws, a lenient shell returns the message',
        () async {
      final failing = Adb(
        executable: 'adb',
        runner: FakeProcessRunner(
            defaultOutcome: const RunOutcome(1, '', 'device offline')),
        serial: 'e',
      );
      expect(() => failing.shell(['true']), throwsA(isA<DeviceFailure>()));
      expect(await failing.shellLenient(['true']), contains('device offline'));
    });

    test('withSerial rebinds without losing the runner', () async {
      await adb.withSerial('other').shell(['echo']);
      expect(fake.lines.single, 'adb -s other shell echo');
    });
  });

  group('AndroidDevice', () {
    test('screenSize reads the physical size, density and override',
        () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
          0,
          'Physical size: 1280x2856\nOverride size: 1080x2400\n'
              '__QA_SEP__\nPhysical density: 480\n__QA_SEP__\n',
          '',
        ),
      );
      final device =
          AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      final size = await device.screenSize();
      expect(size.physicalWidth, 1280);
      expect(size.physicalHeight, 2856);
      expect(size.density, 480);
      expect(size.isOverridden, isTrue);
      expect(size.width, 1080);
      expect(size.height, 2400);
      expect(size.widthDp, 360);
      expect(size.heightDp, 800);
    });

    test('without an override the physical size is the size', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
          0,
          'Physical size: 1280x2856\n__QA_SEP__\nPhysical density: 480\n'
              '__QA_SEP__\n',
          '',
        ),
      );
      final size =
          await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
              .screenSize();
      expect(size.isOverridden, isFalse);
      expect(size.widthDp, 427);
    });

    test('typeTextChecked escapes before it reaches adb', () async {
      final fake = FakeProcessRunner();
      await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
          .typeTextChecked('bench press');
      expect(fake.lines.single, contains("input text 'bench%spress'"));
      expect(fake.lines.single, contains('mInputShown'));
    });

    test('key resolves the alias before it reaches adb', () async {
      final fake = FakeProcessRunner();
      await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
          .key('back');
      expect(fake.lines.single, 'adb -s e shell input keyevent KEYCODE_BACK');
    });

    test('forwardedPortsOf reads only this serial\'s tcp forwards', () {
      const listing = 'emulator-5554 tcp:51000 tcp:51000\r\n'
          'emulator-5556 tcp:52000 tcp:52000\r\n'
          'emulator-5556 tcp:52010 tcp:52010\r\n'
          'emulator-5556 localabstract:x tcp:1\r\n';
      expect(forwardedPortsOf(listing, 'emulator-5556'), [52000, 52010]);
      expect(forwardedPortsOf(listing, 'emulator-5554'), [51000]);
    });

    test('a launch removes the previous forward only when it is this device\'s',
        () async {
      final fake = FakeProcessRunner();
      fake.script('adb -s e forward --list',
          const RunOutcome(0, 'e tcp:40000 tcp:40000\nother tcp:41000 tcp:41000', ''));
      final device = AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      await device.launchApp(vmServicePort: 42000, previousVmServicePort: 40000);
      expect(fake.lines, contains('adb -s e forward --remove tcp:40000'));
      expect(fake.lines.last, 'adb -s e forward tcp:42000 tcp:42000');
      fake.calls.clear();
      await device.launchApp(vmServicePort: 43000, previousVmServicePort: 41000);
      expect(fake.lines.where((l) => l.contains('--remove')), isEmpty,
          reason: 'tcp:41000 is another device\'s listener');
    });

    test('removeForwards keeps the live one and never uses --remove-all', () async {
      final fake = FakeProcessRunner();
      fake.script('adb -s e forward --list',
          const RunOutcome(0, 'e tcp:1 tcp:1\ne tcp:2 tcp:2\ne tcp:3 tcp:3', ''));
      final device = AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'));
      expect(await device.removeForwards(keep: 2), 2);
      expect(fake.lines.where((l) => l.contains('--remove')),
          ['adb -s e forward --remove tcp:1', 'adb -s e forward --remove tcp:3']);
      expect(fake.lines.any((l) => l.contains('--remove-all')), isFalse);
    });

    test('appPid returns null when the app is not running', () async {
      final fake = FakeProcessRunner();
      final pid =
          await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
              .appPid();
      expect(pid, isNull);
    });

    test('appPid parses the first pid', () async {
      final fake = FakeProcessRunner();
      fake.script('adb -s e shell pidof com.alexzamfir.anta',
          const RunOutcome(0, '8421 8500', ''));
      final pid =
          await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
              .appPid();
      expect(pid, 8421);
    });
  });

  group('SdkTools', () {
    test('prefers ANDROID_HOME over PATH', () {
      final tools = SdkTools(
        environment: {'ANDROID_HOME': r'C:\sdk', 'PATH': r'C:\bin'},
        exists: (p) => p.contains('sdk') || p.contains('bin'),
      );
      expect(tools.findAdb(), contains(r'C:\sdk'));
    });

    test('falls back to PATH when no SDK root has it', () {
      final separator = Platform.isWindows ? ';' : ':';
      final bin = Platform.isWindows ? r'C:\bin' : '/opt/bin';
      final other = Platform.isWindows ? r'C:\other' : '/opt/other';
      final tools = SdkTools(
        environment: {'ANDROID_HOME': '/sdk', 'PATH': '$bin$separator$other'},
        exists: (p) => p.startsWith(bin),
      );
      expect(tools.findAdb(), startsWith(bin));
    });

    test('with no SDK variable, the SDK above the adb on PATH is the root', () {
      final separator = Platform.isWindows ? ';' : ':';
      final sep = Platform.pathSeparator;
      final sdk = Platform.isWindows ? r'D:\SDKs\Android\Sdk' : '/opt/android/sdk';
      final tools = '$sdk${sep}platform-tools';
      final adb = Platform.isWindows ? 'adb.exe' : 'adb';
      final emulator = Platform.isWindows ? 'emulator.exe' : 'emulator';
      final present = {'$tools$sep$adb', '$sdk${sep}emulator$sep$emulator'};
      final sdkTools = SdkTools(
        environment: {'PATH': '/usr/bin$separator$tools$sep'},
        exists: present.contains,
      );
      expect(sdkTools.sdkRoots().first, sdk);
      expect(sdkTools.findEmulator(), '$sdk${sep}emulator$sep$emulator');
    });

    test('an SDK variable still wins over the adb on PATH', () {
      final sep = Platform.pathSeparator;
      final adb = Platform.isWindows ? 'adb.exe' : 'adb';
      final tools = SdkTools(
        environment: {'ANDROID_SDK_ROOT': 'home-sdk', 'PATH': 'path-sdk${sep}platform-tools'},
        exists: (p) => p == 'path-sdk${sep}platform-tools$sep$adb',
      );
      expect(tools.sdkRoots(), isNot(contains('path-sdk')));
      expect(tools.sdkRoots().first, 'home-sdk');
    });

    test('looks for the emulator next to platform-tools', () {
      final tools = SdkTools(
        environment: {'ANDROID_SDK_ROOT': r'C:\sdk', 'PATH': ''},
        exists: (p) => p.contains('emulator'),
      );
      expect(tools.findEmulator(), contains('emulator'));
      expect(tools.findQemuImg(), contains('qemu-img'));
    });

    test('requireAdb explains how to fix a missing adb', () {
      final tools =
          SdkTools(environment: const {'PATH': ''}, exists: (_) => false);
      expect(
        tools.requireAdb,
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('ANDROID_HOME'))),
      );
    });
  });
}
