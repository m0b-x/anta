import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/qa.dart' show FlowsCommand;
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/suite.dart';

void main() {
  group('SuiteManifest.parse', () {
    test('defaults: reseed per flow, shardable, no prelude, no settings', () {
      final manifest = SuiteManifest.parse(
        'fixture=tool/qa/fixtures/basic.json\n',
        suite: 'basic',
      );
      expect(manifest.fixture, 'tool/qa/fixtures/basic.json');
      expect(manifest.reseed, ReseedMode.flow);
      expect(manifest.shard, isTrue);
      expect(manifest.prelude, isNull);
      expect(manifest.settings, isEmpty);
    });

    test('every key, comments, blank lines and CRLF', () {
      final manifest = SuiteManifest.parse(
        '# a comment\r\n'
        'fixture=tool/qa/fixtures/alerts.json\r\n'
        '\r\n'
        'reseed=suite\r\n'
        'shard=no\r\n'
        'settings=locale=de\r\n'
        'settings=theme_mode=dark\r\n'
        'prelude=_prelude.txt\r\n',
        suite: 'alerts',
      );
      expect(manifest.reseed, ReseedMode.suite);
      expect(manifest.shard, isFalse);
      expect(manifest.settings, ['locale=de', 'theme_mode=dark']);
      expect(manifest.prelude, '_prelude.txt');
    });

    test('an empty manifest parses, with no fixture', () {
      expect(SuiteManifest.parse('', suite: 's').fixture, isNull);
    });

    Matcher usage(String fragment) => throwsA(
          isA<UsageFailure>().having((e) => e.message, 'message', contains(fragment)),
        );

    test('an unknown key is refused, naming the line and the known keys', () {
      expect(
        () => SuiteManifest.parse('fixture=a.json\nreseeds=flow\n', suite: 'cal'),
        usage('_suite.txt of "cal", line 2: unknown key "reseeds" (known: fixture, '
            'reseed, shard, settings, prelude)'),
      );
    });

    test('bad values are refused', () {
      expect(() => SuiteManifest.parse('reseed=always', suite: 's'),
          usage('reseed must be flow, suite or none (got "always")'));
      expect(() => SuiteManifest.parse('shard=true', suite: 's'),
          usage('shard must be yes or no (got "true")'));
      expect(() => SuiteManifest.parse('settings=locale', suite: 's'),
          usage('--setting takes key=value'));
      expect(() => SuiteManifest.parse('fixture=', suite: 's'),
          usage('"fixture" has no value'));
      expect(() => SuiteManifest.parse('just words', suite: 's'),
          usage('expected key=value'));
    });

    test('a key other than settings may appear once', () {
      expect(() => SuiteManifest.parse('reseed=flow\nreseed=none', suite: 's'),
          usage('"reseed" is set twice'));
    });

    test('the shipped manifests parse to what their suites need', () {
      final flows = 'tool/qa/flows';
      final calendar = SuiteManifest.load(flows, 'calendar');
      expect(calendar.fixture, 'tool/qa/fixtures/calendar.json');
      expect(calendar.reseed, ReseedMode.flow);
      expect(calendar.shard, isTrue);
      expect(File('$flows/calendar/${calendar.prelude}').existsSync(), isTrue);
      for (final suite in ['alerts', 'alerts_pair']) {
        final manifest = SuiteManifest.load(flows, suite);
        expect(manifest.fixture, 'tool/qa/fixtures/$suite.json');
        expect(File(manifest.fixture!).existsSync(), isTrue);
        expect(manifest.reseed, ReseedMode.suite);
        expect(manifest.shard, isFalse);
        expect(manifest.prelude, isNull);
      }
    });

    test('a suite without a manifest is a usage failure that names qa flows', () {
      expect(() => SuiteManifest.load('tool/qa/flows', 'nope'), usage('qa flows nope'));
    });
  });

  group('flow selection', () {
    final flows = [for (var i = 0; i < 26; i++) i.toString().padLeft(2, '0')];
    const shardable = SuiteManifest(suite: 'calendar');
    const whole = SuiteManifest(suite: 'alerts', shard: false);

    test('parseShard takes 1-based i/n', () {
      expect(parseShard('2/3'), (2, 3));
      for (final bad in ['0/3', '4/3', '1/0', '3', 'a/b', '1/3/1']) {
        expect(() => parseShard(bad), throwsA(isA<UsageFailure>()), reason: bad);
      }
    });

    test('1/3, 2/3 and 3/3 partition the flows and cover all of them', () {
      final shards = [
        for (var i = 1; i <= 3; i++)
          selectFlows(flows.reversed.toList(), manifest: shardable, shard: (i, 3)),
      ];
      expect(shards[0].take(3), ['00', '03', '06']);
      expect(shards[1].take(3), ['01', '04', '07']);
      expect(shards[2].take(3), ['02', '05', '08']);
      expect(shards.map((s) => s.length), [9, 9, 8]);
      final all = shards.expand((s) => s).toList()..sort();
      expect(all, flows);
      expect(all.toSet().length, flows.length);
    });

    test('a suite that says shard=no refuses n > 1 but runs as 1/1', () {
      expect(
        () => selectFlows(flows, manifest: whole, shard: (1, 2)),
        throwsA(isA<UsageFailure>()
            .having((e) => e.message, 'message', contains('shard=no'))),
      );
      expect(selectFlows(flows, manifest: whole, shard: (1, 1)), flows);
    });

    test('named flows run in name order, .txt or not, and the shard applies after', () {
      expect(
        selectFlows(flows, manifest: shardable, wanted: ['19', '03.txt', '20']),
        ['03', '19', '20'],
      );
      expect(
        selectFlows(flows, manifest: shardable, wanted: ['19', '03', '20'], shard: (2, 2)),
        ['19'],
      );
    });

    test('an unknown flow name is refused with the ones there are', () {
      expect(
        () => selectFlows(['00_open'], manifest: shardable, wanted: ['01_new']),
        throwsA(isA<UsageFailure>().having(
            (e) => e.message, 'message', contains('no flow "01_new" in "calendar" (have: 00_open)'))),
      );
    });
  });

  group('suite files are not flows', () {
    late Directory flowsDir;

    setUp(() {
      flowsDir = Directory.systemTemp.createTempSync('anta_qa_suite_');
      final suite = Directory('${flowsDir.path}/demo')..createSync();
      for (final name in ['_suite.txt', '_prelude.txt', '00_open.txt', '01_next.txt', 'notes.md']) {
        File('${suite.path}/$name').writeAsStringSync(
          name == '_suite.txt' ? 'fixture=f.json\nprelude=_prelude.txt\n' : 'wait id:x\n',
        );
      }
    });

    tearDown(() => flowsDir.deleteSync(recursive: true));

    test('isFlowFileName and flowNameOf', () {
      expect(isFlowFileName('00_open.txt'), isTrue);
      expect(isFlowFileName('_suite.txt'), isFalse);
      expect(isFlowFileName('_prelude.txt'), isFalse);
      expect(isFlowFileName('notes.md'), isFalse);
      expect(flowNameOf('00_open.txt'), '00_open');
    });

    test('qa flows leaves _*.txt out of a directory run', () {
      final files = FlowsCommand.resolveFlows(flowsDir.path, 'demo')
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(files, ['00_open.txt', '01_next.txt']);
    });

    test('qa flows runs the prelude before a whole directory and its first flow', () {
      expect(
        FlowsCommand.preludeFor(flowsDir.path, 'demo')!.uri.pathSegments.last,
        '_prelude.txt',
      );
      for (final first in ['demo/00_open', 'demo/00_open.txt', r'demo\00_open']) {
        expect(
          FlowsCommand.preludeFor(flowsDir.path, first)!.uri.pathSegments.last,
          '_prelude.txt',
          reason: first,
        );
      }
      expect(FlowsCommand.preludeFor(flowsDir.path, 'demo/01_next'), isNull);
    });

    test('--prelude runs it before any single flow', () {
      expect(
        FlowsCommand.preludeFor(flowsDir.path, 'demo/01_next', force: true)!
            .uri
            .pathSegments
            .last,
        '_prelude.txt',
      );
    });

    test('a directory without a manifest has no prelude', () {
      Directory('${flowsDir.path}/bare').createSync();
      expect(FlowsCommand.preludeFor(flowsDir.path, 'bare'), isNull);
    });
  });
}
