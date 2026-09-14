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

}
