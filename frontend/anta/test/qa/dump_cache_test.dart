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

    test('nothing cached reads as null', () {
      expect(readDumpCache(paths), isNull);
    });

    test('an empty cache file reads as null, not as an empty tree', () {
      paths.ensureBuildQa();
      File(paths.lastDump).writeAsStringSync('   \n');
      expect(readDumpCache(paths), isNull);
    });

    test('a written dump comes back parseable, with its age', () {
      writeDumpCache(
        paths,
        File('test/qa/fixtures/folder_root_dump.xml').readAsStringSync(),
      );
      final cached = readDumpCache(paths)!;
      expect(cached.tree.nodes, isNotEmpty);
      expect(
        cached.ageFrom(DateTime.now()).inSeconds,
        lessThan(10),
      );
    });

    test('writing twice keeps only the newest tree', () {
      writeDumpCache(paths, '<hierarchy rotation="0"></hierarchy>');
      writeDumpCache(
        paths,
        File('test/qa/fixtures/search_results_dump.xml').readAsStringSync(),
      );
      expect(readDumpCache(paths)!.tree.nodes, isNotEmpty);
    });

    test('the cache lives under build/qa so a clean wipes it', () {
      writeDumpCache(paths, '<hierarchy rotation="0"></hierarchy>');
      expect(paths.lastDump, startsWith(paths.buildQa));
      expect(paths.lastDump, endsWith('last_dump.xml'));
    });
  });
}
