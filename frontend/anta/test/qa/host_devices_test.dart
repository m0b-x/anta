import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/ios_device.dart';
import '../../tool/qa/src/macos_device.dart';
import '../../tool/qa/src/markers.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/runner.dart';
import 'fake_process_runner.dart';

void main() {
  group('parseXcconfigValue', () {
    const text = '// The application\'s name.\n'
        'PRODUCT_NAME = ANTA\n'
        '\n'
        'PRODUCT_BUNDLE_IDENTIFIER = com.alexzamfir.anta\n'
        'PRODUCT_COPYRIGHT = Copyright © 2026 Alex Zamfir. All rights reserved.\n';

    test('reads a value and ignores comments', () {
      expect(parseXcconfigValue(text, 'PRODUCT_NAME'), 'ANTA');
      expect(parseXcconfigValue(text, 'PRODUCT_BUNDLE_IDENTIFIER'),
          'com.alexzamfir.anta');
      expect(parseXcconfigValue(text, 'MISSING'), isNull);
    });

    test('a key that prefixes another is not confused with it', () {
      expect(parseXcconfigValue(text, 'PRODUCT'), isNull);
    });
  });

  group('parsePsPids', () {
    const listing = '  412 /sbin/launchd\n'
        '16257 /Users/alex/anta/build/macos/Build/Products/Debug/ANTA.app/Contents/MacOS/ANTA\n'
        '16300 /Applications/Utilities/Terminal.app/Contents/MacOS/Terminal\n'
        '16301 /Users/alex/anta/build/macos/Build/Products/Debug/ANTA.app/Contents/MacOS/ANTA\n';

    test('matches only the exact executable path', () {
      expect(
        parsePsPids(listing,
            '/Users/alex/anta/build/macos/Build/Products/Debug/ANTA.app/Contents/MacOS/ANTA'),
        [16257, 16301],
      );
      expect(parsePsPids(listing, '/nope'), isEmpty);
    });
  });

  test('macosContainerDocuments is the sandbox Documents folder', () {
    expect(
      macosContainerDocuments('/Users/alex', 'com.alexzamfir.anta'),
      ['/Users/alex', 'Library', 'Containers', 'com.alexzamfir.anta', 'Data', 'Documents']
          .join(Platform.pathSeparator),
    );
  });

  group('engine switches', () {
    test('Android extras carry the port and the debug flags', () {
      final extras = androidLaunchExtras(5555);
      expect(extras, containsAllInOrder(['--ei', 'vm-service-port', '5555']));
      expect(extras, containsAllInOrder(['--ez', 'disable-service-auth-codes', 'true']));
      expect(extras, containsAllInOrder(['--ez', 'enable-checked-mode', 'true']));
    });

    test('iOS argv uses the double-dash switch form', () {
      expect(iosLaunchArguments(5555), contains('--vm-service-port=5555'));
      expect(iosLaunchArguments(5555), contains('--disable-service-auth-codes'));
      expect(iosLaunchArguments(5555), contains('--enable-checked-mode'));
    });

    test('desktop env numbers the switches the way the embedding reads them', () {
      final env = desktopEngineEnvironment(5555);
      final count = int.parse(env['FLUTTER_ENGINE_SWITCHES']!);
      expect(count, 5);
      final switches = [for (var i = 1; i <= count; i++) env['FLUTTER_ENGINE_SWITCH_$i']];
      expect(switches, contains('vm-service-port=5555'));
      expect(switches, contains('disable-service-auth-codes=true'));
      expect(switches, contains('enable-dart-profiling=true'));
    });
  });

  group('parseOrphanedServices', () {
    test('only development services re-parented to launchd count', () {
      const ps = '  100     1 /usr/local/dart development-service --port 0\n'
          '  101   100 /usr/local/dart development-service --port 0\n'
          '  102     1 /Applications/Xcode.app/Contents/MacOS/Xcode\n'
          '  103  4021 dart development-service\n';
      expect(parseOrphanedServices(ps), [100]);
    });
  });

  group('pngSize', () {
    test('reads the IHDR dimensions', () {
      final bytes = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        0, 0, 0x05, 0x28, 0, 0, 0x0B, 0x34,
      ];
      expect(pngSize(bytes), (1320, 2868));
    });

    test('is null for anything that is not a PNG', () {
      expect(pngSize([1, 2, 3]), isNull);
      expect(pngSize(List<int>.filled(30, 0)), isNull);
    });
  });

  group('host-side markers', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('qa_markers');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('the reset marker is an empty file in the documents dir', () async {
      final docs = '${temp.path}/Documents';
      await dropResetMarkerAt(docs);
      final marker = File('$docs/$resetMarker');
      expect(marker.existsSync(), isTrue);
      expect(marker.lengthSync(), 0);
    });

    test('the seed is copied under the marker name', () async {
      final fixture = File('${temp.path}/seed.json')..writeAsStringSync('{"v":7}');
      final docs = '${temp.path}/Documents';
      await pushSeedTo(docs, fixture.path);
      expect(File('$docs/$seedMarker').readAsStringSync(), '{"v":7}');
    });

    test('a missing fixture is a usage failure', () {
      expect(
        () => pushSeedTo(temp.path, '${temp.path}/nope.json'),
        throwsA(isA<UsageFailure>()),
      );
    });

    test('a container that does not exist yet is refused, never created', () {
      final docs = '${temp.path}/missing/Container/Documents';
      expect(
        () => dropResetMarkerAt(docs, mustExist: true),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('launch the app once'))),
      );
      expect(Directory(docs).existsSync(), isFalse);
    });
  });

  group('MacosDevice', () {
    late Directory temp;
    late QaPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('qa_macos');
      File('${temp.path}/pubspec.yaml').writeAsStringSync('name: anta');
      paths = QaPaths(temp.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('locate reads the product name from AppInfo.xcconfig', () {
      File(paths.macosAppInfo)
        ..createSync(recursive: true)
        ..writeAsStringSync('PRODUCT_NAME = Anta Desktop\n');
      final device = MacosDevice.locate(paths: paths, runner: FakeProcessRunner());
      expect(device.productName, 'Anta Desktop');
      expect(device.bundlePath, endsWith('Anta Desktop.app'));
      expect(device.executablePath, endsWith('Contents/MacOS/Anta Desktop'));
    });

    test('locate falls back to the default product name', () {
      final device = MacosDevice.locate(paths: paths, runner: FakeProcessRunner());
      expect(device.productName, 'ANTA');
    });

    test('appPid reads ps for the built executable', () async {
      final fake = FakeProcessRunner();
      final device = MacosDevice(
        paths: paths,
        runner: fake,
        productName: 'ANTA',
        environment: const {'HOME': '/Users/alex'},
      );
      fake.script(
        '/bin/ps -axo pid=,comm=',
        RunOutcome(0, '77 ${device.executablePath}\n78 /bin/zsh', ''),
      );
      expect(await device.appPid(), 77);
      expect(await device.isInstalled(), isFalse);
    });

    test('documentsDir prefers what the agent reported and remembers it', () async {
      final device = MacosDevice(
        paths: paths,
        runner: FakeProcessRunner(),
        productName: 'ANTA',
        environment: const {'HOME': '/Users/alex'},
      );
      expect(
        await device.documentsDir(),
        macosContainerDocuments('/Users/alex', 'com.alexzamfir.anta'),
      );
      expect(File(paths.documentsCache('macos')).existsSync(), isFalse);
    });

    test('a native screenshot is refused with the agent as the answer', () {
      final device = MacosDevice(paths: paths, runner: FakeProcessRunner(), productName: 'ANTA');
      expect(device.screencapPng, throwsA(isA<UnsupportedOnPlatform>()));
    });
  });
}
