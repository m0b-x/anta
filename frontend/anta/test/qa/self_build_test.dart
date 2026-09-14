import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/self_build.dart';

void main() {
  final built = DateTime(2026, 9, 14, 10);

  group('decideRebuild', () {
    test('nothing to do when every source is older than the exe', () {
      final decision = decideRebuild(
        aot: true,
        disabled: false,
        exeModified: built,
        sourceModified: {
          'qa.dart': built.subtract(const Duration(minutes: 5)),
          'src/adb.dart': built.subtract(const Duration(hours: 2)),
        },
      );
      expect(decision.rebuild, isFalse);
      expect(decision.reason, isNull);
    });

    test('a newer source triggers a rebuild and is named', () {
      final decision = decideRebuild(
        aot: true,
        disabled: false,
        exeModified: built,
        sourceModified: {
          'qa.dart': built.subtract(const Duration(minutes: 5)),
          'src/device.dart': built.add(const Duration(seconds: 1)),
        },
      );
      expect(decision.rebuild, isTrue);
      expect(decision.reason, 'src/device.dart');
    });

    test('the newest source wins when several are ahead', () {
      final decision = decideRebuild(
        aot: true,
        disabled: false,
        exeModified: built,
        sourceModified: {
          'a.dart': built.add(const Duration(seconds: 1)),
          'b.dart': built.add(const Duration(minutes: 9)),
          'c.dart': built.add(const Duration(seconds: 30)),
        },
      );
      expect(decision.reason, 'b.dart');
    });

    test('a source with exactly the exe timestamp is not newer', () {
      final decision = decideRebuild(
        aot: true,
        disabled: false,
        exeModified: built,
        sourceModified: {'qa.dart': built},
      );
      expect(decision.rebuild, isFalse);
    });

    test('the JIT path never rebuilds, however stale the exe looks', () {
      final decision = decideRebuild(
        aot: false,
        disabled: false,
        exeModified: built,
        sourceModified: {'qa.dart': built.add(const Duration(days: 1))},
      );
      expect(decision.rebuild, isFalse);
    });

    test('the escape hatch stops the rebuild', () {
      final decision = decideRebuild(
        aot: true,
        disabled: true,
        exeModified: built,
        sourceModified: {'qa.dart': built.add(const Duration(days: 1))},
      );
      expect(decision.rebuild, isFalse);
      expect(noSelfRebuildEnv, 'QA_NO_SELF_REBUILD');
    });

    test('a missing exe is nothing to compare, not a rebuild', () {
      final decision = decideRebuild(
        aot: true,
        disabled: false,
        exeModified: null,
        sourceModified: {'qa.dart': built},
      );
      expect(decision.rebuild, isFalse);
    });
  });

  group('qaSourceTimes', () {
    late Directory temp;
    late QaPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_sources_');
      paths = QaPaths(temp.path);
      Directory(joinPath(paths.toolQaDir, ['src']))
          .createSync(recursive: true);
      File(joinPath(paths.toolQaDir, ['qa.dart'])).writeAsStringSync('void x;');
      File(joinPath(paths.toolQaDir, ['src', 'adb.dart']))
          .writeAsStringSync('void y;');
      File(joinPath(paths.toolQaDir, ['qa.cmd'])).writeAsStringSync('@echo off');
      File(paths.pubspecLock).writeAsStringSync('# lock');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('covers every Dart file under tool/qa plus pubspec.lock', () {
      final times = qaSourceTimes(paths);
      expect(
        times.keys.map((p) => p.split(RegExp(r'[\\/]')).last).toSet(),
        {'qa.dart', 'adb.dart', 'pubspec.lock'},
      );
    });

    test('ignores the wrapper scripts, which the exe does not embed', () {
      expect(
        qaSourceTimes(paths).keys.any((p) => p.endsWith('qa.cmd')),
        isFalse,
      );
    });
  });

  group('exe path layout', () {
    test('the swap names sit beside the exe', () {
      final paths = QaPaths(Directory.systemTemp.path);
      expect(paths.qaExeNew, '${paths.qaExe}.new');
      expect(paths.qaExeOld, '${paths.qaExe}.old');
      expect(paths.qaExe, contains('build'));
    });
  });

  group('clearStaleExe', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('anta_qa_old_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('deletes the displaced exe a previous rebuild left behind', () {
      final paths = QaPaths(temp.path);
      paths.ensureBuildQa();
      File(paths.qaExeOld).writeAsStringSync('stale');
      clearStaleExe(paths);
      expect(File(paths.qaExeOld).existsSync(), isFalse);
    });

    test('does nothing when there is none', () {
      final paths = QaPaths(temp.path);
      paths.ensureBuildQa();
      expect(() => clearStaleExe(paths), returnsNormally);
    });
  });
}
