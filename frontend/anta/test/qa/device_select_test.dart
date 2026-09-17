import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/device_select.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/simctl.dart';

const SimDevice _bootedMax = SimDevice(
  udid: 'B57A8680-5A8F-4010-96BE-7524481996B1',
  name: 'iPhone 17 Pro Max',
  state: 'Booted',
  runtime: 'iOS 26.2',
  isAvailable: true,
);

const SimDevice _shutdownPro = SimDevice(
  udid: 'A8642AB6-27CE-4181-A862-E1AA703C271F',
  name: 'iPhone 17 Pro',
  state: 'Shutdown',
  runtime: 'iOS 26.2',
  isAvailable: true,
);

const AdbDevice _emulator = AdbDevice('emulator-5554', 'device', 'sdk_gphone64');

Matcher _failsWith(String fragment) => throwsA(
      isA<DeviceFailure>().having((e) => e.message, 'message', contains(fragment)),
    );

void main() {
  group('selectDevice without a hint', () {
    test('the sole booted simulator wins', () {
      final ref = selectDevice(
        adbDevices: const [],
        simulators: const [_bootedMax, _shutdownPro],
        hostIsMac: true,
      );
      expect(ref.kind, DeviceKind.ios);
      expect(ref.id, _bootedMax.udid);
      expect(ref.label, 'iPhone 17 Pro Max (iOS 26.2)');
    });

    test('the sole adb device wins', () {
      final ref = selectDevice(
        adbDevices: const [_emulator],
        simulators: const [_shutdownPro],
        hostIsMac: true,
      );
      expect(ref.kind, DeviceKind.android);
      expect(ref.id, 'emulator-5554');
    });

    test('a simulator and an emulator together are ambiguous', () {
      expect(
        () => selectDevice(
          adbDevices: const [_emulator],
          simulators: const [_bootedMax],
          hostIsMac: true,
        ),
        _failsWith('more than one device attached'),
      );
    });

    test('the desktop is never picked implicitly', () {
      expect(
        () => selectDevice(
          adbDevices: const [],
          simulators: const [_shutdownPro],
          hostIsMac: true,
        ),
        _failsWith('pass -d macos'),
      );
    });

    test('an offline emulator explains itself instead of being ignored', () {
      expect(
        () => selectDevice(
          adbDevices: const [AdbDevice('emulator-5554', 'offline', null)],
          simulators: const [],
          hostIsMac: false,
        ),
        _failsWith('offline'),
      );
    });
  });

  group('selectDevice with a hint', () {
    test('macos needs a Mac', () {
      final ref = selectDevice(
        explicit: 'macos',
        adbDevices: const [],
        simulators: const [],
        hostIsMac: true,
      );
      expect(ref.kind, DeviceKind.macos);
      expect(ref.id, macosDeviceId);
      expect(
        () => selectDevice(
          explicit: 'macos',
          adbDevices: const [],
          simulators: const [],
          hostIsMac: false,
        ),
        _failsWith('only be driven from a Mac'),
      );
    });

    test('ios means the sole booted simulator', () {
      final ref = selectDevice(
        explicit: 'ios',
        adbDevices: const [_emulator],
        simulators: const [_bootedMax, _shutdownPro],
        hostIsMac: true,
      );
      expect(ref.id, _bootedMax.udid);
      expect(
        () => selectDevice(
          explicit: 'ios',
          adbDevices: const [],
          simulators: const [_shutdownPro],
          hostIsMac: true,
        ),
        _failsWith('no iOS simulator is booted'),
      );
    });

    test('a simulator name is matched case-insensitively', () {
      final ref = selectDevice(
        explicit: 'iphone 17 pro max',
        adbDevices: const [],
        simulators: const [_bootedMax, _shutdownPro],
        hostIsMac: true,
      );
      expect(ref.kind, DeviceKind.ios);
      expect(ref.id, _bootedMax.udid);
    });

    test('a shut-down simulator says how to boot it', () {
      expect(
        () => selectDevice(
          explicit: 'iPhone 17 Pro',
          adbDevices: const [],
          simulators: const [_bootedMax, _shutdownPro],
          hostIsMac: true,
        ),
        _failsWith('qa boot --sim "iPhone 17 Pro"'),
      );
    });

    test('the environment variable stands in for the flag', () {
      final ref = selectDevice(
        envValue: 'emulator-5554',
        adbDevices: const [_emulator],
        simulators: const [_bootedMax],
        hostIsMac: true,
      );
      expect(ref.kind, DeviceKind.android);
    });

    test('an unknown name lists what is attached', () {
      expect(
        () => selectDevice(
          explicit: 'pixel',
          adbDevices: const [_emulator],
          simulators: const [_bootedMax],
          hostIsMac: true,
        ),
        _failsWith('emulator-5554 (device)'),
      );
    });
  });

  group('describeDevices', () {
    test('lists booted simulators by default and all with --all', () {
      final some = describeDevices(
        adbDevices: const [_emulator],
        simulators: const [_bootedMax, _shutdownPro],
        hostIsMac: true,
        macosBuilt: 'built',
      );
      expect(some, hasLength(3));
      expect(some[0], startsWith('android  emulator-5554'));
      expect(some[1], contains('iPhone 17 Pro Max (iOS 26.2)'));
      expect(some[2], contains('pass -d macos'));
      final all = describeDevices(
        adbDevices: const [],
        simulators: const [_bootedMax, _shutdownPro],
        hostIsMac: false,
        all: true,
      );
      expect(all, hasLength(2));
      expect(all.last, contains('Shutdown'));
    });
  });
}
