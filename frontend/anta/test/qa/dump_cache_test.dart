import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/dump_cache.dart';
import '../../tool/qa/src/paths.dart';

void main() {
  group('describeAge', () {
    test('sub-second is "just now"', () {
      expect(describeAge(const Duration(milliseconds: 300)), 'just now');
    });

    test('seconds up to two minutes', () {
      expect(describeAge(const Duration(seconds: 4)), '4 s ago');
      expect(describeAge(const Duration(seconds: 119)), '119 s ago');
    });

    test('minutes up to two hours', () {
      expect(describeAge(const Duration(minutes: 2)), '2 min ago');
      expect(describeAge(const Duration(minutes: 119)), '119 min ago');
    });

    test('hours beyond that', () {
      expect(describeAge(const Duration(hours: 3)), '3 h ago');
    });
  });

  group('the dump cache', () {
    late Directory temp;
    late QaPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_dump_');
      paths = QaPaths(temp.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    const device = 'emulator-5556';
    const emptyTree = '<hierarchy rotation="0"></hierarchy>';
    String fixture(String name) => File('test/qa/fixtures/$name').readAsStringSync();

    test('nothing cached reads as null', () {
      expect(readDumpCache(paths, device), isNull);
      expect(readDumpCache(paths, null), isNull);
    });

    test('an empty cache file reads as null, not as an empty tree', () {
      paths.ensureBuildQa();
      File(paths.lastDumpFor(device)).writeAsStringSync('   \n');
      expect(readDumpCache(paths, device), isNull);
    });

    test('a written dump comes back parseable, with its age', () {
      writeDumpCache(paths, device, fixture('folder_root_dump.xml'));
      final cached = readDumpCache(paths, device)!;
      expect(cached.tree.nodes, isNotEmpty);
      expect(
        cached.ageFrom(DateTime.now()).inSeconds,
        lessThan(10),
      );
    });

    test('writing twice keeps only the newest tree', () {
      writeDumpCache(paths, device, emptyTree);
      writeDumpCache(paths, device, fixture('search_results_dump.xml'));
      expect(readDumpCache(paths, device)!.tree.nodes, isNotEmpty);
    });

    test('the cache lives under build/qa, one file per device', () {
      writeDumpCache(paths, device, emptyTree);
      expect(paths.lastDumpFor(device), startsWith(paths.buildQa));
      expect(paths.lastDumpFor(device), endsWith('last_dump_emulator-5556.txt'));
      expect(File(paths.lastDumpFor(device)).existsSync(), isTrue);
      expect(File(paths.lastDump).existsSync(), isFalse);
    });

    test("two devices never read each other's tree", () {
      writeDumpCache(paths, 'emulator-5554', fixture('folder_root_dump.xml'));
      writeDumpCache(paths, device, emptyTree);
      expect(readDumpCache(paths, 'emulator-5554')!.tree.nodes, isNotEmpty);
      expect(readDumpCache(paths, device)!.tree.nodes, isEmpty);
    });

    test('a shared dump from an older tool resolves until the device writes its own', () {
      paths.ensureBuildQa();
      File(paths.lastDump).writeAsStringSync(fixture('folder_root_dump.xml'));
      expect(readDumpCache(paths, device)!.tree.nodes, isNotEmpty);
      expect(readDumpCache(paths, null)!.tree.nodes, isNotEmpty);

      writeDumpCache(paths, device, emptyTree);
      expect(File(paths.lastDump).existsSync(), isFalse);
      expect(readDumpCache(paths, device)!.tree.nodes, isEmpty);
    });

    test('with no device it reads the newest per-device dump, then the shared ones', () {
      writeDumpCache(paths, 'emulator-5556', fixture('folder_root_dump.xml'));
      writeDumpCache(paths, 'emulator-5558', emptyTree);
      File(paths.lastDumpFor('emulator-5556'))
          .setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 5)));
      expect(readDumpCache(paths, null)!.tree.nodes, isEmpty);

      File(paths.lastDumpFor('emulator-5558'))
          .setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 10)));
      expect(readDumpCache(paths, null)!.tree.nodes, isNotEmpty);

      File(paths.lastDumpFor('emulator-5556')).deleteSync();
      File(paths.lastDumpFor('emulator-5558')).deleteSync();
      File(paths.lastDump).writeAsStringSync(fixture('folder_root_dump.xml'));
      expect(readDumpCache(paths, null)!.tree.nodes, isNotEmpty);
    });

    test('the oldest shared name, last_dump.xml, still counts', () {
      paths.ensureBuildQa();
      File(paths.legacyLastDump).writeAsStringSync(fixture('folder_root_dump.xml'));
      expect(readDumpCache(paths, device)!.tree.nodes, isNotEmpty);
      writeDumpCache(paths, device, emptyTree);
      expect(File(paths.legacyLastDump).existsSync(), isFalse);
    });
  });
}
