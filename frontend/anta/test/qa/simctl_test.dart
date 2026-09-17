import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/simctl.dart';
import 'fake_process_runner.dart';

/// Trimmed from `xcrun simctl list devices --json` on 2026-09-16.
const String _listJson = '''
{
  "devices" : {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-2" : [
      {
        "dataPath" : "/Users/alex/Library/Developer/CoreSimulator/Devices/A8642AB6/data",
        "udid" : "A8642AB6-27CE-4181-A862-E1AA703C271F",
        "isAvailable" : true,
        "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        "state" : "Shutdown",
        "name" : "iPhone 17 Pro"
      },
      {
        "lastBootedAt" : "2026-09-16T17:00:41Z",
        "dataPath" : "/Users/alex/Library/Developer/CoreSimulator/Devices/B57A8680/data",
        "udid" : "B57A8680-5A8F-4010-96BE-7524481996B1",
        "isAvailable" : true,
        "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max",
        "state" : "Booted",
        "name" : "iPhone 17 Pro Max"
      },
      {
        "udid" : "84AFB9DA-C03F-4503-B4CE-DD5AF12FA3D7",
        "isAvailable" : false,
        "state" : "Shutdown",
        "name" : "iPad Pro 13-inch (M5)"
      }
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-26-0" : []
  }
}
''';

void main() {
  group('parseSimctlDevices', () {
    test('flattens runtimes, booted first, and keeps the data path', () {
      final devices = parseSimctlDevices(_listJson);
      expect(devices, hasLength(3));
      expect(devices.first.name, 'iPhone 17 Pro Max');
      expect(devices.first.booted, isTrue);
      expect(devices.first.runtime, 'iOS 26.2');
      expect(devices.first.dataPath, endsWith('B57A8680/data'));
      expect(devices.first.isIPhone, isTrue);
      final ipad = devices.singleWhere((d) => d.name.startsWith('iPad'));
      expect(ipad.isAvailable, isFalse);
      expect(ipad.isIPhone, isFalse);
      expect(devices.where((d) => d.booted), hasLength(1));
    });

    test('rejects output that is not JSON with a device failure', () {
      expect(
        () => parseSimctlDevices('xcrun: error: unable to find utility'),
        throwsA(isA<DeviceFailure>()),
      );
    });

    test('rejects JSON without a devices map', () {
      expect(() => parseSimctlDevices('{"runtimes": []}'),
          throwsA(isA<DeviceFailure>()));
    });
  });

  group('simRuntimeLabel', () {
    test('turns the runtime identifier into a readable version', () {
      expect(simRuntimeLabel('com.apple.CoreSimulator.SimRuntime.iOS-26-2'),
          'iOS 26.2');
      expect(simRuntimeLabel('com.apple.CoreSimulator.SimRuntime.iOS-18-0-1'),
          'iOS 18.0.1');
      expect(simRuntimeLabel('com.apple.CoreSimulator.SimRuntime.watchOS-26-0'),
          'watchOS 26.0');
    });

    test('passes anything unrecognised through untouched', () {
      expect(simRuntimeLabel('custom'), 'custom');
    });
  });

  group('parseSimctlLaunchPid', () {
    test('reads the pid simctl launch prints', () {
      expect(parseSimctlLaunchPid('com.alexzamfir.anta: 4272'), 4272);
      expect(parseSimctlLaunchPid('com.alexzamfir.anta: 4272\n'), 4272);
    });

    test('is null when there is no pid', () {
      expect(parseSimctlLaunchPid('An error was encountered'), isNull);
    });
  });

  group('parseLaunchctlPid', () {
    const listing = '1392\t0\tUIKitApplication:com.apple.Spotlight[2861][rb-legacy]\n'
        '4272\t0\tUIKitApplication:com.alexzamfir.anta[360d][rb-legacy]\n'
        '-\t0\tcom.apple.something\n';

    test('finds the app row and nothing else', () {
      expect(parseLaunchctlPid(listing, 'com.alexzamfir.anta'), 4272);
      expect(parseLaunchctlPid(listing, 'com.alexzamfir.anta.other'), isNull);
    });

    test('a bundle that is listed without a pid reads as not running', () {
      expect(
        parseLaunchctlPid('-\t0\tUIKitApplication:com.alexzamfir.anta[1][x]',
            'com.alexzamfir.anta'),
        isNull,
      );
    });
  });

  test('iosLogPredicate scopes to the executable and the Flutter sender', () {
    final predicate = iosLogPredicate('Runner');
    expect(predicate, contains('processImagePath ENDSWITH "Runner"'));
    expect(predicate, contains('senderImagePath ENDSWITH "/Flutter"'));
  });

  group('Simctl', () {
    test('launch passes the app arguments after the bundle id', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(0, 'com.alexzamfir.anta: 99', ''),
      );
      final simctl = Simctl(runner: fake, xcrun: 'xcrun');
      final pid = await simctl.launch(
        'UDID',
        'com.alexzamfir.anta',
        appArguments: const ['--vm-service-port=1234'],
      );
      expect(pid, 99);
      expect(fake.lines.single,
          'xcrun simctl launch --terminate-running-process UDID com.alexzamfir.anta --vm-service-port=1234');
    });

    test('launch without terminate brings a running app forward', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(0, 'com.alexzamfir.anta: 99', ''),
      );
      await Simctl(runner: fake, xcrun: 'xcrun')
          .launch('UDID', 'com.alexzamfir.anta', terminateRunning: false);
      expect(fake.lines.single, isNot(contains('--terminate-running-process')));
    });

    test('a failed launch is a device failure quoting simctl', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(1, '', 'Unable to launch'),
      );
      expect(
        () => Simctl(runner: fake, xcrun: 'xcrun').launch('UDID', 'x'),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('Unable to launch'))),
      );
    });

    test('appContainer is null when the app is not installed', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(2, '', 'No such file or directory'),
      );
      expect(
        await Simctl(runner: fake, xcrun: 'xcrun')
            .appContainer('UDID', 'x', 'data'),
        isNull,
      );
    });

    test('screenshotPng asks for PNG on stdout', () async {
      final fake = FakeProcessRunner();
      fake.script(
        'xcrun simctl io UDID screenshot --type=png -',
        const RunOutcome(0, '', '', bytes: [0x89, 0x50]),
      );
      final bytes = await Simctl(runner: fake, xcrun: 'xcrun').screenshotPng('UDID');
      expect(bytes, [0x89, 0x50]);
      expect(fake.calls.single.binary, isTrue);
    });

    test('logShow reads the last minutes at info and debug level', () async {
      final fake = FakeProcessRunner(defaultOutcome: const RunOutcome(0, 'line', ''));
      await Simctl(runner: fake, xcrun: 'xcrun').logShow(
        'UDID',
        predicate: 'p',
        last: const Duration(minutes: 3),
      );
      expect(fake.calls.single.arguments,
          containsAllInOrder(['log', 'show', '--last', '3m', '--info', '--debug']));
    });
  });
}
