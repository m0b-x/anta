import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/apk_build.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import 'fake_process_runner.dart';

void main() {
  group('qa build', () {
    test('builds the debug driver APK with the QA defines', () {
      expect(buildApkArgs(), [
        'build',
        'apk',
        '--debug',
        '-t',
        'test_driver/main_driver.dart',
        '--dart-define=ANTA_QA=true',
        '--dart-define=ANTA_QA_DB=qa',
      ]);
    });

    test('--define adds dart-defines after the QA ones; --no-driver drops -t', () {
      expect(
        buildApkArgs(driver: false, extraDefines: const ['ANTA_QA_CLOUD=true']),
        [
          'build',
          'apk',
          '--debug',
          '--dart-define=ANTA_QA=true',
          '--dart-define=ANTA_QA_DB=qa',
          '--dart-define=ANTA_QA_CLOUD=true',
        ],
      );
    });
  });

  group('qa install', () {
    test('installs over what is there on the selected serial, never uninstalls', () async {
      final fake = FakeProcessRunner();
      final adb = Adb(executable: 'adb', runner: fake, serial: 'emulator-5556');
      await adb.raw(installApkArgs('build/app/outputs/flutter-apk/app-debug.apk'));
      expect(fake.lines.single,
          'adb -s emulator-5556 install -r -t build/app/outputs/flutter-apk/app-debug.apk');
    });
  });

  group('ApkRecord', () {
    late Directory temp;
    late QaPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_apk_');
      paths = QaPaths(temp.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    final record = ApkRecord(
      apk: 'app-debug.apk',
      gitHash: '39b0c7d',
      dirty: true,
      builtAt: DateTime.utc(2026, 10, 23, 9),
      defines: const ['ANTA_QA=true', 'ANTA_QA_DB=qa'],
      driver: true,
      qa: true,
    );

    test('apk.json has the documented keys and reads back', () {
      record.write(paths.apkJson);
      final read = ApkRecord.read(paths.apkJson)!;
      expect(read.toJson(), {
        'apk': 'app-debug.apk',
        'gitHash': '39b0c7d',
        'dirty': true,
        'builtAt': '2026-10-23T09:00:00.000Z',
        'defines': ['ANTA_QA=true', 'ANTA_QA_DB=qa'],
        'driver': true,
        'qa': true,
      });
      expect(read.installed(DateTime.utc(2026, 10, 23, 10)).isQaDriverBuild, isTrue);
    });

    test('the per-device copy adds installedAt', () {
      final installed = record.installed(DateTime.utc(2026, 10, 23, 9, 5));
      installed.write(paths.installedJsonFor('emulator-5556'));
      final read = ApkRecord.read(paths.installedJsonFor('emulator-5556'))!;
      expect(read.toJson()['installedAt'], '2026-10-23T09:05:00.000Z');
      expect(read.gitHash, '39b0c7d');
    });

    test('a missing or unreadable record reads as null; require says to build', () {
      expect(ApkRecord.read(paths.apkJson), isNull);
      paths.ensureBuildQa();
      File(paths.apkJson).writeAsStringSync('{not json');
      expect(ApkRecord.read(paths.apkJson), isNull);
      expect(
        () => ApkRecord.require(paths.apkJson),
        throwsA(isA<UsageFailure>().having((e) => e.message, 'message', contains('qa build'))),
      );
    });
  });

  group('stale build detection', () {
    final build = ApkRecord(
      apk: 'a.apk',
      gitHash: null,
      dirty: false,
      builtAt: DateTime(2026, 10, 23, 9),
      defines: const [],
    );

    test('a source newer than the build warns, naming it relative to the root', () {
      final warning = staleBuildWarning(
        build,
        (path: '/repo/lib/main.dart', modified: DateTime(2026, 10, 23, 9, 30)),
        projectRoot: '/repo',
      );
      expect(warning, startsWith('warning: a source of the APK changed after the installed build (lib/main.dart at'));
    });

    test('an older or equal source, or none at all, is silent', () {
      expect(staleBuildWarning(build, (path: 'x', modified: DateTime(2026, 10, 23, 8))), isNull);
      expect(staleBuildWarning(build, (path: 'x', modified: DateTime(2026, 10, 23, 9))), isNull);
      expect(staleBuildWarning(build, null), isNull);
    });

    test('newestSource finds the latest file under lib, test_driver and packages/*/lib', () {
      final root = Directory.systemTemp.createTempSync('anta_qa_src_');
      addTearDown(() => root.deleteSync(recursive: true));
      final paths = QaPaths(root.path);
      File touch(String relative, DateTime at) {
        final file = File('${root.path}/$relative')..createSync(recursive: true);
        file.setLastModifiedSync(at);
        return file;
      }

      touch('lib/main.dart', DateTime(2026, 10, 1));
      touch('test_driver/main_driver.dart', DateTime(2026, 10, 2));
      final newest = touch('packages/re_editor/lib/src/editor.dart', DateTime(2026, 10, 3));
      touch('packages/re_editor/test/editor_test.dart', DateTime(2026, 10, 9));
      touch('test/widget_test.dart', DateTime(2026, 10, 9));

      final roots = apkSourceRoots(paths);
      expect(roots.length, 3);
      final found = newestSource(roots)!;
      expect(File(found.path).absolute.uri, newest.absolute.uri);
      expect(found.modified, DateTime(2026, 10, 3));
    });

    test('the Android project, the pubspec, assets and package android/ count; '
        'what a build rewrites does not', () {
      final root = Directory.systemTemp.createTempSync('anta_qa_src_');
      addTearDown(() => root.deleteSync(recursive: true));
      final paths = QaPaths(root.path);
      File touch(String relative, DateTime at) {
        final file = File('${root.path}/$relative')..createSync(recursive: true);
        file.setLastModifiedSync(at);
        return file;
      }

      touch('lib/main.dart', DateTime(2026, 10, 1));
      touch('pubspec.yaml', DateTime(2026, 10, 2));
      touch('pubspec.lock', DateTime(2026, 10, 2));
      touch('assets/icon/app.png', DateTime(2026, 10, 2));
      touch('packages/alarm/android/src/main/AndroidManifest.xml', DateTime(2026, 10, 3));
      final newest = touch('android/app/build.gradle.kts', DateTime(2026, 10, 4));
      for (final byproduct in [
        'android/.gradle/8.0/checksums.lock',
        'android/.kotlin/sessions/x',
        'android/app/build/intermediates/x.dex',
        'android/local.properties',
        'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
        'packages/alarm/android/build/x.class',
      ]) {
        touch(byproduct, DateTime(2026, 10, 20));
      }

      final roots = apkSourceRoots(paths);
      expect(roots, containsAll([
        '${root.path}${Platform.pathSeparator}android',
        '${root.path}${Platform.pathSeparator}pubspec.yaml',
        '${root.path}${Platform.pathSeparator}pubspec.lock',
        '${root.path}${Platform.pathSeparator}assets',
      ]));
      final found = newestSource(roots)!;
      expect(File(found.path).absolute.uri, newest.absolute.uri);

      final pubspec = touch('pubspec.yaml', DateTime(2026, 10, 9));
      expect(File(newestSource(roots)!.path).absolute.uri, pubspec.absolute.uri);
    });
  });

  group('build state', () {
    test('dirty asks git only about what goes into the APK', () async {
      final runner = FakeProcessRunner()
        ..script('git rev-parse --short HEAD', const RunOutcome(0, 'abc1234\n', ''))
        ..script(
          'git status --porcelain -- lib test_driver android packages pubspec.yaml '
              'pubspec.lock assets',
          const RunOutcome(0, ' M lib/main.dart\n', ''),
        );
      final state = await gitBuildState(runner, '/repo');
      expect(state.hash, 'abc1234');
      expect(state.dirty, isTrue);
      expect(runner.lines.last, contains('-- lib test_driver android'));

      final clean = await gitBuildState(FakeProcessRunner(), '/repo');
      expect(clean.hash, isNull);
      expect(clean.dirty, isFalse);
    });

    test('qa run records the debug APK it installed, dated from the run start', () {
      final paths = QaPaths('/repo');
      final started = DateTime.utc(2026, 10, 23, 9);
      final installedAt = DateTime.utc(2026, 10, 23, 9, 2);
      final record = installedRecordForRun(
        paths: paths,
        git: (hash: 'abc1234', dirty: true),
        runStarted: started,
        defines: const ['ANTA_QA=true'],
        installedAt: installedAt,
        driver: true,
        qa: true,
      );
      expect(record.apk, File(paths.debugApk).absolute.path);
      expect(record.builtAt, started);
      expect(record.installedAt, installedAt);
      expect(record.gitHash, 'abc1234');
      expect(record.dirty, isTrue);
      expect(record.isQaDriverBuild, isTrue);
      expect(record.toJson().keys,
          ['apk', 'gitHash', 'dirty', 'builtAt', 'defines', 'installedAt', 'driver', 'qa']);
      final noDriver = installedRecordForRun(
        paths: paths,
        git: (hash: 'abc1234', dirty: false),
        runStarted: started,
        defines: const [],
        installedAt: installedAt,
        driver: false,
        qa: false,
      );
      expect(noDriver.isQaDriverBuild, isFalse, reason: '`qa run --no-driver --no-qa`');
      expect(ApkRecord.fromJson(noDriver.toJson()).isQaDriverBuild, isFalse);
      final legacy = noDriver.toJson()..remove('driver')..remove('qa');
      expect(ApkRecord.fromJson(legacy).isQaDriverBuild, isFalse,
          reason: 'a record that cannot say both is not trusted');
      expect(
        staleBuildWarning(record, (path: 'lib/a.dart', modified: started.subtract(const Duration(seconds: 1)))),
        isNull,
      );
    });
  });

  group('build refuses beside a live flutter run', () {
    late Directory root;
    late QaPaths paths;

    setUp(() {
      root = Directory.systemTemp.createTempSync('anta_qa_build_');
      paths = QaPaths(root.path)..ensureBuildQa();
    });

    tearDown(() => root.deleteSync(recursive: true));

    // Answers isProcessAlive on either host: PowerShell prints the word,
    // `kill -0` reports through its exit code.
    FakeProcessRunner aliveRunner({required bool alive}) => FakeProcessRunner(
          defaultOutcome: RunOutcome(alive ? 0 : 1, alive ? 'alive' : 'gone', ''),
        );

    test('with run.pid alive it refuses, naming the way out', () async {
      File(paths.runPid).writeAsStringSync('4242');
      final refusal = await buildRefusal(paths, aliveRunner(alive: true), force: false);
      expect(refusal, contains('pid 4242'));
      expect(refusal, contains('qa kill-run'));
      expect(refusal, contains('--force'));
    });

    test('--force, a dead pid or no run.pid let it build', () async {
      File(paths.runPid).writeAsStringSync('4242');
      expect(await buildRefusal(paths, aliveRunner(alive: true), force: true), isNull);
      expect(await buildRefusal(paths, aliveRunner(alive: false), force: false), isNull);
      File(paths.runPid).deleteSync();
      expect(await buildRefusal(paths, aliveRunner(alive: true), force: false), isNull);
    });
  });
}
