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

  group('selectSerial', () {
    final one = parseDevices(_devicesOutput);
    final two = parseDevices('List of devices attached\n'
        'emulator-5554\tdevice\nemulator-5556\tdevice\n');

    test('an explicit -d wins over everything', () {
      expect(
        selectSerial(explicit: 'R58M', envValue: 'ignored', available: two),
        'R58M',
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

    test('nothing attached falls back to the default emulator serial', () {
      expect(selectSerial(available: const []), defaultSerial);
      expect(defaultSerial, 'emulator-5554');
    });

    test('an offline device does not count as the sole device', () {
      final offline =
          parseDevices('List of devices attached\nemulator-5554\toffline\n');
      expect(selectSerial(available: offline), defaultSerial);
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
      final fake = FakeProcessRunner();
      fake.script(
        'adb -s e shell wm size',
        const RunOutcome(
            0, 'Physical size: 1280x2856\nOverride size: 1080x2400', ''),
      );
      fake.script('adb -s e shell wm density',
          const RunOutcome(0, 'Physical density: 480', ''));
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
      final fake = FakeProcessRunner();
      fake.script('adb -s e shell wm size',
          const RunOutcome(0, 'Physical size: 1280x2856', ''));
      fake.script('adb -s e shell wm density',
          const RunOutcome(0, 'Physical density: 480', ''));
      final size =
          await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
              .screenSize();
      expect(size.isOverridden, isFalse);
      expect(size.widthDp, 427);
    });

    test('typeText escapes before it reaches adb', () async {
      final fake = FakeProcessRunner();
      await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
          .typeText('bench press');
      expect(fake.lines.single, "adb -s e shell input text 'bench%spress'");
    });

    test('key resolves the alias before it reaches adb', () async {
      final fake = FakeProcessRunner();
      await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
          .key('back');
      expect(fake.lines.single, 'adb -s e shell input keyevent KEYCODE_BACK');
    });

    test('appPid returns null when the app is not running', () async {
      final fake = FakeProcessRunner();
      final pid =
          await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
              .appPid('com.alexzamfir.anta');
      expect(pid, isNull);
    });

    test('appPid parses the first pid', () async {
      final fake = FakeProcessRunner();
      fake.script('adb -s e shell pidof com.alexzamfir.anta',
          const RunOutcome(0, '8421 8500', ''));
      final pid =
          await AndroidDevice(Adb(executable: 'adb', runner: fake, serial: 'e'))
              .appPid('com.alexzamfir.anta');
      expect(pid, 8421);
    });
  });

  group('IosSimulator', () {
    test('every verb reports Phase B rather than pretending', () {
      final simulator = IosSimulator('booted');
      expect(simulator.id, 'booted');
      for (final call in <Future<Object?> Function()>[
        simulator.screenSize,
        () => simulator.tap(1, 1),
        () => simulator.typeText('x'),
        () => simulator.key('back'),
        simulator.dumpUi,
        simulator.screencapPng,
      ]) {
        expect(
          call,
          throwsA(isA<NotImplementedOnPlatform>().having((e) => e.message,
              'message', contains('not implemented on this platform'))),
        );
      }
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
      final tools = SdkTools(
        environment: {'ANDROID_HOME': r'C:\sdk', 'PATH': r'C:\bin;C:\other'},
        exists: (p) => p.startsWith(r'C:\bin'),
      );
      expect(tools.findAdb(), startsWith(r'C:\bin'));
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
