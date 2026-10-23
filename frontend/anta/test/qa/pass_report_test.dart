import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/pass_report.dart';

StepRecord _step(int n, String line, int ms, {bool ok = true, String output = ''}) =>
    StepRecord(n: n, line: line, ms: ms, ok: ok, output: output);

PassReport _report({
  String device = 'emulator-5556',
  (int, int)? shard,
  List<FlowRecord>? flows,
  DateTime? started,
  int? quietMs,
  int? quietAlarms,
  String? quietFailure,
}) {
  final start = started ?? DateTime.utc(2026, 10, 23, 10);
  return PassReport(
    suite: 'calendar',
    label: 'slice 1a',
    device: PassDevice(id: device, label: 'Android $device', platform: 'android'),
    host: 'windows',
    started: start,
    finished: start.add(const Duration(seconds: 12, milliseconds: 500)),
    shard: shard,
    reseed: 'flow',
    fixture: 'tool/qa/fixtures/calendar.json',
    prelude: '_prelude.txt',
    build: const {'apk': 'app-debug.apk', 'gitHash': '39b0c7d', 'builtAt': '2026-10-23T09:00:00.000Z'},
    flows: flows ??
        [
          FlowRecord(
            name: '00_open',
            status: FlowStatus.passed,
            durationMs: 5200,
            reseedMs: 4400,
            preludeMs: 600,
            steps: [
              _step(1, 'expect "Lifting session" "Morning walk"', 120, output: 'ok'),
              _step(2, 'look 00_calendar', 300),
            ],
          ),
          FlowRecord(
            name: '19_fasting_schedule',
            status: FlowStatus.failed,
            durationMs: 9100,
            reseedMs: 4600,
            preludeMs: 700,
            steps: [
              _step(1, 'tap id:calendar-more', 80),
              _step(2, 'tap "Fasting"', 100, ok: false, output: '! qa: no node "Fasting"'),
            ],
            failure: const FlowFailure(
              step: 2,
              line: 'tap "Fasting"',
              exitCode: 2,
              message: 'no node "Fasting"\nOn screen: …',
              shot: 'fail_19_fasting_schedule.png',
              dump: 'fail_19_fasting_schedule_dump.txt',
              errors: 'fail_19_fasting_schedule_errors.txt',
            ),
          ),
          const FlowRecord(name: '20_fasting_style', status: FlowStatus.skipped),
        ],
    quietMs: quietMs,
    quietAlarms: quietAlarms,
    quietFailure: quietFailure,
  );
}

void main() {
  group('report.json', () {
    test('carries exactly the contract keys', () {
      final json = jsonDecode(_report(shard: (1, 3)).encode()) as Map<String, dynamic>;
      expect(json.keys, [
        'schema', 'suite', 'label', 'device', 'host', 'started', 'finished',
        'durationMs', 'partial', 'shard', 'reseed', 'fixture', 'prelude', 'build',
        'quietMs', 'quietAlarms', 'quietFailure', 'quietSkipped', 'quietDevices',
        'quietUncounted', 'summary', 'flows', 'verbStats',
      ]);
      expect(json['quietMs'], isNull, reason: 'a pass that did not end quiet says so by null');
      expect(json['partial'], isFalse);
      expect(json['schema'], 1);
      expect(json['device'], {'id': 'emulator-5556', 'label': 'Android emulator-5556', 'platform': 'android'});
      expect(json['started'], '2026-10-23T10:00:00.000Z');
      expect(json['durationMs'], 12500);
      expect(json['shard'], {'index': 1, 'count': 3});
      expect(json['summary'], {'flows': 3, 'passed': 1, 'failed': 1, 'skipped': 1});

      final flows = (json['flows'] as List).cast<Map<String, dynamic>>();
      expect(flows.first.keys, [
        'name', 'status', 'durationMs', 'reseedMs', 'preludeMs', 'steps', 'failure',
      ]);
      expect(flows.first['failure'], isNull);
      final step = (flows[1]['steps'] as List)[1] as Map<String, dynamic>;
      expect(step, {
        'n': 2,
        'line': 'tap "Fasting"',
        'verb': 'tap',
        'ms': 100,
        'status': 'failed',
        'output': '! qa: no node "Fasting"',
      });
      expect((flows[1]['failure'] as Map).keys, [
        'step', 'line', 'exitCode', 'message', 'shot', 'dump', 'errors',
      ]);
      expect(flows[2]['status'], 'skipped');
      expect(flows[2]['reseedMs'], isNull);
    });

    test('a whole-suite run has shard null and no devices key', () {
      final json = jsonDecode(_report().encode()) as Map<String, dynamic>;
      expect(json['shard'], isNull);
      expect(json.containsKey('devices'), isFalse);
    });

    test('decodes back to the same report', () {
      final text = _report(shard: (2, 3)).encode();
      expect(PassReport.decode(text).encode(), text);
    });

    test('refuses what is not a schema 1 report', () {
      expect(() => PassReport.decode('[]'), throwsA(isA<UsageFailure>()));
      expect(() => PassReport.decode('{"schema":2}'), throwsA(isA<UsageFailure>()));
      expect(() => PassReport.decode('not json'), throwsA(isA<UsageFailure>()));
    });
  });

  group('verbStats', () {
    test('nearest-rank percentiles over each verb, reseeds counted as relaunch', () {
      final taps = [for (var ms = 10; ms <= 200; ms += 10) ms];
      final stats = computeVerbStats([
        FlowRecord(
          name: 'a',
          status: FlowStatus.passed,
          reseedMs: 4000,
          steps: [for (final (i, ms) in taps.reversed.indexed) _step(i + 1, 'tap id:x', ms)],
        ),
        FlowRecord(
          name: 'b',
          status: FlowStatus.passed,
          reseedMs: 5000,
          steps: [_step(1, 'wait id:y --timeout 5', 700)],
        ),
      ]);
      expect(stats.keys, ['relaunch', 'tap', 'wait']);
      final tap = stats['tap']!;
      expect(tap.count, 20);
      expect(tap.p50Ms, 100);
      expect(tap.p95Ms, 190);
      expect(tap.maxMs, 200);
      expect(stats['relaunch']!.toJson(), {'count': 2, 'p50Ms': 4000, 'p95Ms': 5000, 'maxMs': 5000});
      expect(stats['wait']!.toJson(), {'count': 1, 'p50Ms': 700, 'p95Ms': 700, 'maxMs': 700});
    });

    test('percentile of nothing is zero, of one sample is that sample', () {
      expect(percentile(const [], 95), 0);
      expect(percentile(const [42], 50), 42);
    });

    test('the report carries them under verbStats', () {
      final json = jsonDecode(_report().encode()) as Map<String, dynamic>;
      expect((json['verbStats'] as Map).keys, ['expect', 'look', 'relaunch', 'tap']);
      expect(json['verbStats']['tap'], {'count': 2, 'p50Ms': 80, 'p95Ms': 100, 'maxMs': 100});
    });
  });

  group('summary', () {
    test('one line per flow, the verdict, then the verb table', () {
      final lines = summaryLines(_report(), reportPath: 'build/qa/pass/x/report.json');
      expect(lines[0], 'ok    00_open${' ' * 16}5200 ms');
      expect(
        lines[1],
        'FAIL  19_fasting_schedule    9100 ms  step 2: tap "Fasting" — no node "Fasting"',
      );
      expect(lines[2], 'skip  20_fasting_style');
      expect(lines[3], 'pass: 1/3 green in 12.5 s on emulator-5556 — report build/qa/pass/x/report.json');
      expect(lines[4], 'verb      count    p50    p95    max  (ms)');
      expect(lines[5], 'expect        1    120    120    120');
      expect(lines.length, 9);
    });

    test('the quiet line follows the verdict: armed count, failure, or nothing', () {
      PassReport quiet({int? ms, int? alarms, String? failure}) =>
          _report(quietMs: ms, quietAlarms: alarms, quietFailure: failure);

      final lines = summaryLines(quiet(ms: 5400, alarms: 0), reportPath: 'r.json');
      expect(lines[4], 'device left quiet (0 alarms armed) in 5.4 s');
      expect(quietLine(quiet(ms: 5400, alarms: 2)),
          'device not left quiet: 2 alarm(s) of the app still armed after relaunch --fresh (5.4 s)');
      expect(quietLine(quiet(ms: 900)), 'device left quiet in 0.9 s (alarms not counted)');
      expect(quietLine(quiet(ms: 900, failure: 'relaunch --fresh: the reset was refused\nmore')),
          'device not left quiet: relaunch --fresh: the reset was refused');
      expect(quietLine(quiet()), isNull, reason: 'a report from before the quiet step');
      expect(PassReport.decode(quiet(ms: 5400, alarms: 0).encode()).quietAlarms, 0);
    });

    test('a skipped quiet step says why', () {
      final skipped = PassReport.decode(_report().encode().replaceFirst(
            '"quietSkipped": null',
            '"quietSkipped": "--no-reseed ran on the app\'s own state, which stays"',
          ));
      expect(quietLine(skipped),
          "quiet relaunch skipped: --no-reseed ran on the app's own state, which stays");
      expect(summaryLines(skipped, reportPath: 'r.json'),
          contains(startsWith('quiet relaunch skipped: ')));
      expect(mergeReports([skipped, skipped]).quietSkipped, skipped.quietSkipped);
    });

    test('a partial report is never green and says so under the verdict', () {
      final green = _report(flows: [
        const FlowRecord(name: '00_open', status: FlowStatus.passed, durationMs: 5),
      ]);
      expect(green.allPassed, isTrue);
      final killed = PassReport.decode(
        green.encode().replaceFirst('"partial": false', '"partial": true'),
      );
      expect(killed.allPassed, isFalse);
      final lines = summaryLines(killed, reportPath: 'r.json');
      expect(lines[1], startsWith('pass: 1/1 green'));
      expect(lines[2], partialLine);
      expect(lines[2], 'PARTIAL — the pass did not finish');
      expect(summaryLines(green, reportPath: 'r.json'), isNot(contains(partialLine)));
    });
  });

  group('headline', () {
    test('the first line, or the first two when the first introduces the second', () {
      expect(headline('no node "x"\nOn screen: a | b'), 'no node "x"');
      expect(
        headline('1 expectation(s) failed after 5s:\n  missing "id:fasting-extra-days"\n'),
        '1 expectation(s) failed after 5s: missing "id:fasting-extra-days"',
      );
      expect(headline(''), '');
    });

    test('a long line is capped with an ellipsis', () {
      final capped = headline('a' * 400);
      expect(capped.length, 160);
      expect(capped, endsWith('…'));
    });
  });

  group('merge', () {
    test('concatenates flows in name order, sums the summary, lists the devices', () {
      final a = _report(
        device: 'emulator-5556',
        shard: (1, 2),
        flows: [const FlowRecord(name: '02_b', status: FlowStatus.passed, durationMs: 10)],
      );
      final b = _report(
        device: 'emulator-5558',
        shard: (2, 2),
        started: DateTime.utc(2026, 10, 23, 9, 59, 50),
        flows: [
          const FlowRecord(name: '01_a', status: FlowStatus.passed, durationMs: 10),
          const FlowRecord(
            name: '03_c',
            status: FlowStatus.failed,
            failure: FlowFailure(step: 1, line: 'tap x', exitCode: 2, message: 'gone'),
          ),
        ],
      );
      final merged = mergeReports([a, b]);
      final json = jsonDecode(merged.encode()) as Map<String, dynamic>;
      expect(json['shard'], isNull);
      expect(json['device'], isNull);
      expect((json['devices'] as List).map((d) => (d as Map)['id']), ['emulator-5556', 'emulator-5558']);
      expect(json['summary'], {'flows': 3, 'passed': 2, 'failed': 1, 'skipped': 0});
      expect((json['flows'] as List).map((f) => (f as Map)['name']), ['01_a', '02_b', '03_c']);
      expect(json['started'], '2026-10-23T09:59:50.000Z');
      expect(json['durationMs'], 22500);
      final lines = summaryLines(merged, reportPath: 'm.json');
      expect(lines[3], 'pass: 2/3 green in 22.5 s on emulator-5556, emulator-5558 — report m.json');

      expect(PassReport.decode(merged.encode()).devices!.length, 2);
    });

    test('a flow two reports carry is kept once, from the report given last', () {
      final shard = _report(flows: [
        const FlowRecord(name: '01_a', status: FlowStatus.passed, durationMs: 10),
        const FlowRecord(
          name: '02_b',
          status: FlowStatus.failed,
          failure: FlowFailure(step: 1, line: 'tap x', exitCode: 2, message: 'gone'),
        ),
      ]);
      final rerun = _report(flows: [
        const FlowRecord(name: '02_b', status: FlowStatus.passed, durationMs: 30),
      ]);
      expect(duplicateFlowNames([shard, rerun]), ['02_b']);
      expect(duplicateFlowNames([shard]), isEmpty);
      final merged = mergeReports([shard, rerun]);
      expect(merged.flows.map((f) => f.name), ['01_a', '02_b']);
      expect(merged.flows.last.status, FlowStatus.passed);
      expect(merged.allPassed, isTrue);
    });

    test('a partial shard makes the merge partial; the flag reads back', () {
      final killed = PassReport.decode(
        _report().encode().replaceFirst('"partial": false', '"partial": true'),
      );
      expect(killed.partial, isTrue);
      expect(mergeReports([_report(), killed]).partial, isTrue);
      expect(mergeReports([_report()]).partial, isFalse);
      final old = PassReport.decode(
        _report().encode().replaceFirst('"partial": false,', ''),
      );
      expect(old.partial, isFalse);
    });

    test('quiet: the slowest device, the alarms summed, failures joined', () {
      final a = _report(quietMs: 5200, quietAlarms: 0);
      final b = _report(device: 'emulator-5558', quietMs: 6100, quietAlarms: 1);
      final merged = mergeReports([a, b]);
      expect(merged.quietMs, 6100);
      expect(merged.quietAlarms, 1);
      expect(merged.quietFailure, isNull);
      expect(quietLine(merged), startsWith('devices not left quiet: 1 alarm(s)'));
      expect(quietLine(mergeReports([a, a])), 'devices left quiet (0 alarms armed) in 5.2 s');
      final failed = _report(quietMs: 900, quietFailure: 'relaunch --fresh: exit 3');
      expect(mergeReports([a, failed]).quietFailure, 'relaunch --fresh: exit 3');
      expect(mergeReports([_report()]).quietMs, isNull);
    });

    test('quiet: a device whose count failed is counted as such, never as 0', () {
      final a = _report(quietMs: 5200, quietAlarms: 0);
      final b = _report(device: 'emulator-5558', quietMs: 6100, quietAlarms: 0);
      final c = _report(device: 'emulator-5560', quietMs: 4000);
      final merged = mergeReports([a, b, c]);
      expect(merged.quietDevices, 2);
      expect(merged.quietUncounted, 1);
      expect(quietLine(merged), '2 devices quiet, 1 not counted in 6.1 s');
      final armed = _report(device: 'emulator-5562', quietMs: 3000, quietAlarms: 2);
      expect(quietLine(mergeReports([a, c, armed])),
          'devices not left quiet: 2 alarm(s) of the app still armed after '
          'relaunch --fresh, 1 not counted (5.2 s)');
      expect(quietLine(mergeReports([c, c])), 'devices left quiet in 4.0 s (alarms not counted)');
      final again = mergeReports([merged, _report(device: 'emulator-5562', quietMs: 100, quietAlarms: 0)]);
      expect((again.quietDevices, again.quietUncounted), (3, 1),
          reason: 'a merged report merged again keeps its own counts');
    });

    test('refuses reports of two suites, or none', () {
      final other = PassReport.decode(
        _report().encode().replaceFirst('"suite": "calendar"', '"suite": "alerts"'),
      );
      expect(() => mergeReports([_report(), other]), throwsA(isA<UsageFailure>()));
      expect(() => mergeReports(const []), throwsA(isA<UsageFailure>()));
    });
  });
}
