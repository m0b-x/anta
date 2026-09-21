import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/process_runner.dart';
import '../../tool/release/src/gradle_daemons.dart';
import '../qa/fake_process_runner.dart';

const String _windowsRows =
    '21600\t"D:\\IDEs\\Android Studio\\jbr\\bin\\java.exe" '
    '--add-opens=java.base/java.lang=ALL-UNNAMED -cp '
    'C:\\Users\\me\\.gradle\\wrapper\\dists\\gradle-9.3.1-all\\abc\\'
    'gradle-9.3.1\\lib\\gradle-daemon-main-9.3.1.jar '
    'org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.3.1\n'
    '10036\t"D:\\IDEs\\Android Studio\\jbr\\bin\\java.exe" -cp '
    'C:\\Users\\me\\.gradle\\wrapper\\dists\\gradle-8.14-all\\def\\'
    'gradle-8.14\\lib\\gradle-daemon-main-8.14.jar '
    'org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.14\n'
    '8964\t"D:\\IDEs\\Android Studio\\jbr\\bin\\java" -cp '
    'kotlin-compiler-embeddable-2.2.20.jar '
    'org.jetbrains.kotlin.daemon.KotlinCompileDaemon\n';

const String _posixRows =
    '  512 /usr/bin/java -Xmx8G -cp /Users/me/.gradle/wrapper/dists/'
    'gradle-9.3.1-all/xyz/gradle-9.3.1/lib/gradle-daemon-main-9.3.1.jar '
    'org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.3.1\n'
    '  600 /usr/bin/java -cp /opt/gradle-8.14/lib/gradle-daemon-main-8.14.jar '
    'org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.14\n'
    '    1 /sbin/launchd\n';

void main() {
  test('wrapperVersion reads the distributionUrl', () {
    expect(
      wrapperVersion(
        'distributionBase=GRADLE_USER_HOME\n'
        'distributionUrl=https\\://services.gradle.org/distributions/'
        'gradle-9.3.1-all.zip\n',
      ),
      '9.3.1',
    );
    expect(
      wrapperVersion(
        'distributionUrl=https\\://services.gradle.org/distributions/'
        'gradle-8.11.1-bin.zip',
      ),
      '8.11.1',
    );
    expect(wrapperVersion('nothing here'), isNull);
  });

  group('parseDaemonRows', () {
    test('keeps Gradle daemons from the PowerShell listing, not Kotlin', () {
      expect(parseDaemonRows(_windowsRows).map((d) => d.pid), [21600, 10036]);
    });

    test('reads ps output too', () {
      expect(parseDaemonRows(_posixRows).map((d) => d.pid), [512, 600]);
    });
  });

  group('staleDaemons', () {
    test('keeps the wrapper version and flags the rest', () {
      final stale = staleDaemons(
        parseDaemonRows(_windowsRows),
        keepVersion: '9.3.1',
      );
      expect(stale.map((d) => d.pid), [10036]);
    });

    test('does not let 9.3 match 9.3.1', () {
      final current = parseDaemonRows(_posixRows).first;
      expect(current.runsVersion('9.3'), isFalse);
      expect(current.runsVersion('9.3.1'), isTrue);
    });

    test('with no version to keep, every daemon is stale', () {
      expect(
        staleDaemons(parseDaemonRows(_posixRows), keepVersion: null),
        hasLength(2),
      );
    });
  });

  test('the listing commands carry no double quotes to re-tokenise', () {
    for (final windows in [true, false]) {
      expect(daemonListingCommand(windows: windows).line, isNot(contains('"')));
    }
    expect(daemonListingCommand(windows: false).line, 'ps -eo pid=,command=');
  });

  test('listGradleDaemons parses the listing; a failed listing is empty', () async {
    final runner = FakeProcessRunner()
      ..script('ps -eo pid=,command=', const RunOutcome(0, _posixRows, ''));
    expect(
      (await listGradleDaemons(runner, windows: false)).map((d) => d.pid),
      [512, 600],
    );
    final broken = FakeProcessRunner(
      defaultOutcome: const RunOutcome(1, '', 'no ps'),
    );
    expect(await listGradleDaemons(broken, windows: false), isEmpty);
  });

  test('stopDaemons reports only the pids the kill accepted', () {
    final killed = <int>[];
    final stopped = stopDaemons(
      parseDaemonRows(_posixRows),
      kill: (pid) {
        killed.add(pid);
        return pid == 600;
      },
    );
    expect(killed, [512, 600]);
    expect(stopped, [600]);
  });
}
