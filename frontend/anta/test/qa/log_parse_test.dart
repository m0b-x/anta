import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/log_parse.dart';

const String _realRunLog = '''
Launching test_driver/main_driver.dart on sdk gphone64 x86 64 in debug mode...
Running Gradle task 'assembleDebug'...
Running Gradle task 'assembleDebug'...                            103.3s
 Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...           1,884ms
I/flutter ( 8421): [anta] startup complete
Syncing files to device sdk gphone64 x86 64...                      88ms

Flutter run key commands.
r Hot reload.
R Hot restart.
A Dart VM Service on sdk gphone64 x86 64 is available at: http://127.0.0.1:53222/AbCdEf0123=/
The Dart Tooling Daemon is available at: ws://127.0.0.1:53230/hsK9nQ1lZ2pXvQ==
The Flutter DevTools debugger and profiler on sdk gphone64 x86 64 is available at: http://127.0.0.1:9101?uri=http://127.0.0.1:53222/AbCdEf0123=/
''';

void main() {
  group('extractUris', () {
    test('pulls both URIs out of a real run log', () {
      final uris = extractUris(_realRunLog);
      expect(uris.dtd, 'ws://127.0.0.1:53230/hsK9nQ1lZ2pXvQ==');
      expect(uris.vmService, 'http://127.0.0.1:53222/AbCdEf0123=/');
      expect(uris.complete, isTrue);
    });

    test('is incomplete while the build is still running', () {
      final uris = extractUris("Running Gradle task 'assembleDebug'...");
      expect(uris.dtd, isNull);
      expect(uris.vmService, isNull);
      expect(uris.complete, isFalse);
    });

    test('accepts the devtools_launcher wording as well', () {
      final uris = extractUris(
          'Serving the Dart Tooling Daemon at ws://127.0.0.1:1234/tok=.');
      expect(uris.dtd, 'ws://127.0.0.1:1234/tok=');
    });

    test('accepts the older debug-service wording for the VM service', () {
      final uris =
          extractUris('Debug service listening on ws://127.0.0.1:5/x=/ws');
      expect(uris.vmService, 'ws://127.0.0.1:5/x=/ws');
    });

    test('a trailing full stop is trimmed off', () {
      final uris = extractUris(
          'The Dart Tooling Daemon is available at: ws://127.0.0.1:1/a=.');
      expect(uris.dtd, 'ws://127.0.0.1:1/a=');
    });

    test('the last URI wins after a hot restart reprints them', () {
      final uris = extractUris(
        '$_realRunLog\n'
        'The Dart Tooling Daemon is available at: ws://127.0.0.1:60000/zzz=\n',
      );
      expect(uris.dtd, 'ws://127.0.0.1:60000/zzz=');
    });
  });

  group('errorLines', () {
    test('keeps exceptions and the app error hook, skips ordinary lines', () {
      final hits = errorLines('''
I/flutter ( 1): [anta] startup complete
I/flutter ( 1): [anta] error saving note: bad state
Syncing files to device...
Unhandled exception:
E/AndroidRuntime( 1): FATAL EXCEPTION: main
''');
      expect(hits, hasLength(3));
      expect(hits[0], contains('[anta] error saving note'));
      expect(hits[1], contains('Unhandled exception'));
      expect(hits[2], contains('FATAL EXCEPTION'));
    });

    test('keeps only the last N hits', () {
      final log = List.generate(80, (i) => 'Unhandled exception $i').join('\n');
      final hits = errorLines(log, limit: 10);
      expect(hits, hasLength(10));
      expect(hits.last, 'Unhandled exception 79');
    });

    test('a clean log has no hits', () {
      expect(errorLines('Syncing files to device...\nr Hot reload.'), isEmpty);
    });
  });

  group('launchFailureLine', () {
    test('catches a Gradle failure so the run does not wait out its timeout',
        () {
      final line = launchFailureLine(
        "Running Gradle task 'assembleDebug'...\n"
        'FAILURE: Build failed with an exception.\n'
        'Error: Gradle task assembleDebug failed with exit code 1\n',
      );
      expect(line, contains('FAILURE: Build failed'));
    });

    test('catches a kernel snapshot failure', () {
      expect(
        launchFailureLine('Target kernel_snapshot_program failed: Exception'),
        contains('kernel_snapshot_program'),
      );
    });

    test('catches a missing target file and a missing device', () {
      expect(launchFailureLine('Error: No devices found'), isNotNull);
      expect(
        launchFailureLine('Error: Target file "nope.dart" not found'),
        isNotNull,
      );
    });

    test('a healthy build is not a failure', () {
      expect(launchFailureLine(_realRunLog), isNull);
    });

    test('a Gradle warning about plugins is not a failure', () {
      expect(
        launchFailureLine(
          'WARNING: Your app uses the following plugins that apply Kotlin '
          'Gradle Plugin (KGP): google_sign_in_android',
        ),
        isNull,
      );
    });
  });

  group('softLaunchFailureLine', () {
    test('flags the VM service handshake race', () {
      expect(
        softLaunchFailureLine(
          'Error connecting to the service protocol: failed to connect to '
          'http://127.0.0.1:1/a=/ DartDevelopmentServiceException',
        ),
        contains('Error connecting to the service protocol'),
      );
    });

    test('flags a lost device', () {
      expect(softLaunchFailureLine('Lost connection to device.'), isNotNull);
    });

    test('is not raised by a healthy run', () {
      expect(softLaunchFailureLine(_realRunLog), isNull);
    });

    test('is kept separate from the hard failures', () {
      const soft = 'Error connecting to the service protocol: nope';
      expect(launchFailureLine(soft), isNull);
      expect(softLaunchFailureLine(soft), isNotNull);
    });
  });

  group('filterLogcat', () {
    test('keeps flutter, anta and crash lines', () {
      final kept = filterLogcat([
        'I/flutter ( 1): hello',
        'D/EGL_emulation( 2): eglMakeCurrent',
        'E/AndroidRuntime( 3): FATAL EXCEPTION',
        'I/ActivityManager: Start proc com.alexzamfir.anta',
        'V/WindowManager: relayout',
      ]);
      expect(kept, hasLength(3));
      expect(kept.any((l) => l.contains('EGL_emulation')), isFalse);
    });
  });

  group('parseQaMarkers', () {
    const captured = '''
09-14 11:24:56.136 I/flutter (10263): [IMPORTANT:flutter/shell/…] Impeller
09-14 11:24:56.172 I/flutter (10263): The Dart VM service is listening on http://127.0.0.1:38345/x=/
09-14 11:24:56.870 I/flutter (10263): [qa] reset: cleared preferences and qa.db
09-14 11:24:57.269 I/flutter (10263): [qa] seed: imported 4 folders, 3 notes
09-14 11:24:57.272 I/flutter (10263): [qa] onboarding marked completed
''';

    test('reads the three lines of a real seeded launch', () {
      final markers = parseQaMarkers(captured);
      expect(markers.reset, 'reset: cleared preferences and qa.db');
      expect(markers.seed, 'seed: imported 4 folders, 3 notes');
      expect(markers.onboarding, 'onboarding marked completed');
      expect(markers.all, hasLength(3));
      expect(markers.seedFailed, isFalse);
    });

    test('reads them out of a plain run.log too', () {
      final markers = parseQaMarkers(
        'Syncing files to device…\n'
        'I/flutter ( 7344): [qa] reset: cleared preferences and qa.db\n'
        'I/flutter ( 7344): [qa] onboarding marked completed\n',
      );
      expect(markers.reset, isNotNull);
      expect(markers.seed, isNull);
      expect(markers.all, hasLength(2));
    });

    test('a log with none of them is all null', () {
      final markers = parseQaMarkers('Running Gradle task…');
      expect(markers.reset, isNull);
      expect(markers.seed, isNull);
      expect(markers.onboarding, isNull);
      expect(markers.all, isEmpty);
      expect(markers.seedFailed, isFalse);
    });

    test('the last occurrence of a marker wins', () {
      final markers = parseQaMarkers(
        '[qa] seed: imported 1 folders, 1 notes\n'
        '[qa] seed: imported 4 folders, 3 notes\n',
      );
      expect(markers.seed, 'seed: imported 4 folders, 3 notes');
    });

    test('a rejected backup reads as a failed seed', () {
      final markers = parseQaMarkers(
        '09-14 11:32:10.648 I/flutter (11580): [qa] seed: import failed: '
        'FormatException: Unexpected character (at character 1)\n',
      );
      expect(markers.seedFailed, isTrue);
    });

    test('a seed that threw reads as a failed seed', () {
      expect(
        parseQaMarkers('[qa] seed: threw Bad state: no database').seedFailed,
        isTrue,
      );
    });

    test('a successful import is not a failure', () {
      expect(
        parseQaMarkers('[qa] seed: imported 0 folders, 0 notes').seedFailed,
        isFalse,
      );
    });
  });

  group('emulatorFatalLine', () {
    test('catches the PANIC the emulator prints for a broken AVD', () {
      expect(
        emulatorFatalLine('emulator: Android emulator version 35.1\n'
            'PANIC: Cannot find AVD system path.\n'),
        'PANIC: Cannot find AVD system path.',
      );
    });

    test('catches a second instance of the same AVD', () {
      expect(
        emulatorFatalLine(
          "emulator: ERROR: Running multiple emulators with the same AVD is "
          'an experimental feature.\n',
        ),
        isNotNull,
      );
    });

    test('catches a hypervisor failure', () {
      expect(
        emulatorFatalLine('emulator: WHPX is not installed\n'),
        isNotNull,
      );
    });

    test('catches a port clash', () {
      expect(
        emulatorFatalLine('emulator: ERROR: Address already in use\n'),
        isNotNull,
      );
    });

    test('a WARNING that happens to say "Failed to" is not fatal', () {
      expect(
        emulatorFatalLine(
          'INFO         | Created extended window in 254.935ms\n'
          'WARNING      | Failed to process .ini file '
          '/Users/alex/.android/emu-update-last-check.ini for reading.\n'
          "WARNING      | adb command 'adb -s emulator-5554 shell am "
          "start-foreground-service' failed: 'adb: device offline'\n",
        ),
        isNull,
      );
    });

    test('a healthy boot log has no fatal line', () {
      expect(
        emulatorFatalLine(
          'emulator: Android emulator version 35.1.4.0\n'
          'INFO    | Storing crashdata in: /tmp/x\n'
          'INFO    | Boot completed in 21387 ms\n',
        ),
        isNull,
      );
    });
  });

  group('known noise', () {
    test('both Firebase lines are noise, not app errors', () {
      expect(
        isKnownNoise(
          'E/FirebearStorageCryptoHelper(11893): Exception encountered while '
          'decrypting bytes:',
        ),
        isTrue,
      );
      expect(
        isKnownNoise('E/FirebearStorageCryptoHelper(11893): decryption failed'),
        isTrue,
      );
    });

    test('a real exception is not noise', () {
      expect(
        isKnownNoise('E/flutter (123): Unhandled Exception: Bad state'),
        isFalse,
      );
    });

    test('partitionKnownNoise keeps order within each half', () {
      final (real, noise) = partitionKnownNoise([
        'E/flutter: Exception A',
        'E/FirebearStorageCryptoHelper: decryption failed',
        'E/flutter: Exception B',
      ]);
      expect(real, ['E/flutter: Exception A', 'E/flutter: Exception B']);
      expect(noise, hasLength(1));
    });

    test('a clean log partitions into two empty halves', () {
      final (real, noise) = partitionKnownNoise(const []);
      expect(real, isEmpty);
      expect(noise, isEmpty);
    });
  });
}
