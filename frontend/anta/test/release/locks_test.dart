import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/process_runner.dart';
import '../../tool/release/src/locks.dart';
import '../qa/fake_process_runner.dart';

const String _rows =
    '  512 /usr/bin/java -cp /x/gradle-9.3.1/lib/gradle-daemon-main-9.3.1.jar '
    'org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.3.1\n'
    '  600 /usr/bin/java -cp /x/gradle-8.14/lib/gradle-daemon-main-8.14.jar '
    'org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.14\n';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anta_locks');
    Directory('${root.path}/android/gradle/wrapper')
        .createSync(recursive: true);
    File('${root.path}/android/gradle/wrapper/gradle-wrapper.properties')
        .writeAsStringSync(
      'distributionUrl=https\\://services.gradle.org/distributions/'
      'gradle-9.3.1-all.zip\n',
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  FakeProcessRunner posixRunner() => FakeProcessRunner()
    ..script('ps -eo pid=,command=', const RunOutcome(0, _rows, ''));

  test('staleOnly keeps the wrapper-version daemon warm', () async {
    final killed = <int>[];
    final notes = await releaseBuildLocks(
      projectRoot: root.path,
      runner: posixRunner(),
      scope: DaemonScope.staleOnly,
      windows: false,
      kill: (pid) {
        killed.add(pid);
        return true;
      },
    );
    expect(killed, [600]);
    expect(notes.single, contains('not running Gradle 9.3.1'));
    expect(notes.single, contains('pid 600'));
  });

  test('all stops every daemon before a clean build', () async {
    final killed = <int>[];
    final notes = await releaseBuildLocks(
      projectRoot: root.path,
      runner: posixRunner(),
      scope: DaemonScope.all,
      windows: false,
      kill: (pid) {
        killed.add(pid);
        return true;
      },
    );
    expect(killed, [512, 600]);
    expect(notes.single, contains('before the clean build'));
  });

  test('nothing to do says nothing', () async {
    final notes = await releaseBuildLocks(
      projectRoot: root.path,
      runner: FakeProcessRunner(),
      scope: DaemonScope.all,
      windows: false,
      kill: (_) => fail('nothing should be killed'),
    );
    expect(notes, isEmpty);
  });

  test('off Windows no Explorer sweep is attempted', () async {
    final runner = posixRunner();
    await releaseBuildLocks(
      projectRoot: root.path,
      runner: runner,
      scope: DaemonScope.staleOnly,
      windows: false,
      kill: (_) => true,
    );
    expect(runner.lines, ['ps -eo pid=,command=']);
  });

  test('on Windows the Explorer sweep follows the daemon sweep', () async {
    final runner = FakeProcessRunner();
    await releaseBuildLocks(
      projectRoot: root.path,
      runner: runner,
      scope: DaemonScope.staleOnly,
      windows: true,
      kill: (_) => true,
    );
    expect(runner.lines, hasLength(2));
    expect(runner.lines.first, contains('GradleDaemon'));
    expect(runner.lines.last, contains('Shell.Application'));
    expect(runner.lines.last, contains(r'$w.Quit()'));
  });

  group('explorerScript', () {
    test('doubles single quotes in the path and never uses double quotes', () {
      final script = explorerScript(r"D:\it's\build", close: true);
      expect(script, contains(r"'D:\it''s\build'"));
      expect(script, isNot(contains('"')));
      expect(script, contains(r'$w.Quit()'));
    });

    test('the counting variant quits nothing', () {
      expect(explorerScript(r'D:\x\build', close: false), isNot(contains('Quit')));
    });
  });
}
