import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/pass_history.dart';
import '../../tool/qa/src/pass_report.dart';
import '../../tool/qa/src/paths.dart';

/// A report of [suite] on [device] that started [day] days into November,
/// its flows by status.
PassReport _pass(
  int day,
  Map<String, FlowStatus> flows, {
  String suite = 'browser',
  String? device = 'emulator-5556',
  List<String> recoveredIn = const [],
}) {
  final started = DateTime(2026, 11, day, 14, 5);
  return PassReport(
    suite: suite,
    label: null,
    device: device == null
        ? null
        : PassDevice(id: device, label: 'Android $device', platform: 'android'),
    devices: device == null
        ? const [
            PassDevice(id: 'emulator-5556', label: 'a', platform: 'android'),
          ]
        : null,
    host: 'windows',
    started: started,
    finished: started.add(const Duration(seconds: 15)),
    shard: null,
    reseed: 'flow',
    fixture: 'f.json',
    prelude: null,
    build: null,
    flows: [
      for (final MapEntry(:key, :value) in flows.entries)
        FlowRecord(
          name: key,
          status: value,
          recovered: recoveredIn.contains(key) && value == FlowStatus.passed,
        ),
    ],
    infra: [
      for (final flow in recoveredIn)
        InfraRecord(
          flow: flow,
          cause: 'device',
          guest: 'not on adb',
          message: 'offline',
          action: 'rerun',
          ms: 20000,
          outcome: 'green',
        ),
    ],
  );
}

const _ok = FlowStatus.passed;
const _red = FlowStatus.failed;
const _skip = FlowStatus.skipped;

void main() {
  group('flowHistories', () {
    test(
      'counts runs, reds, recoveries and the last red; skipped is no run',
      () {
        final histories = {
          for (final h in flowHistories([
            _pass(10, {'01_a': _ok, '02_b': _red, '03_c': _ok}),
            _pass(9, {'01_a': _ok, '02_b': _ok, '03_c': _skip}),
            _pass(8, {'01_a': _ok, '02_b': _red, '03_c': _red}),
            _pass(7, {'01_a': _ok, '02_b': _ok}, recoveredIn: ['01_a']),
          ]))
            h.name: h,
        };
        final a = histories['01_a']!;
        expect(
          (a.runs, a.reds, a.recoveries, a.flaky, a.quiet),
          (4, 0, 1, false, false),
        );
        final b = histories['02_b']!;
        expect((b.runs, b.reds, b.flaky), (4, 2, true));
        expect(b.lastRed, DateTime(2026, 11, 10, 14, 5));
        final c = histories['03_c']!;
        expect((c.runs, c.reds, c.flaky), (2, 1, true));
        expect(c.lastRed, DateTime(2026, 11, 8, 14, 5));
      },
    );

    test('a flow red every time it ran is not flaky, it is broken', () {
      final h = flowHistories([
        _pass(2, {'01_a': _red}),
        _pass(1, {'01_a': _red}),
      ]).single;
      expect(h.flaky, isFalse);
      expect(h.reds, 2);
    });
  });

  group('historyLines', () {
    test('noisy flows first, most reds first; the green rest as one count', () {
      final lines = historyLines('browser', [
        _pass(11, {'01_a': _ok, '02_b': _red, '03_c': _ok, '04_d': _ok}),
        _pass(10, {
          '01_a': _ok,
          '02_b': _red,
          '03_c': _red,
          '04_d': _ok,
        }, device: 'emulator-5558'),
        _pass(
          9,
          {'01_a': _ok, '02_b': _ok, '03_c': _ok, '04_d': _ok},
          recoveredIn: ['04_d'],
        ),
      ]);
      expect(
        lines.first,
        'history: browser — 3 report(s) from 2026-11-09 14:05 to '
        '2026-11-11 14:05 on emulator-5556, emulator-5558',
      );
      expect(lines[1], 'flow  runs  reds  recovered  last red');
      expect(lines[2], '02_b     3     2          0  2026-11-11 14:05  flaky');
      expect(lines[3], '03_c     3     1          0  2026-11-10 14:05  flaky');
      expect(lines[4], '04_d     3     0          1  -');
      expect(lines.last, '1 other flow(s) green in every run');
    });

    test('an all-green window is one line; no report says so', () {
      expect(
        historyLines('browser', [
          _pass(1, {'01_a': _ok, '02_b': _ok}),
        ]).last,
        'all 2 flow(s) green in every run',
      );
      expect(historyLines('browser', const []), [
        'history: no report of "browser" under build/qa/pass',
      ]);
    });
  });

  group('readSuiteHistory', () {
    late Directory root;
    late QaPaths paths;
    setUp(() {
      root = Directory.systemTemp.createTempSync('anta_qa_history_');
      paths = QaPaths(root.path);
    });
    tearDown(() => root.deleteSync(recursive: true));

    void write(String dir, String text) {
      File(joinPath(paths.passRoot, [dir, 'report.json']))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    test('the newest N of this suite, any device; merged reports, other suites '
        'and broken files left out', () {
      for (var day = 1; day <= 5; day++) {
        write(
          'browser_202611${day.toString().padLeft(2, '0')}_140500_000_emulator-5556',
          _pass(day, {'01_a': _ok}).encode(),
        );
      }
      write(
        'browser_20261106_140500_000_emulator-5558',
        _pass(6, {'01_a': _red}, device: 'emulator-5558').encode(),
      );
      write(
        'browser_20261107_140500_000_fleet',
        _pass(7, {'01_a': _red}, device: null).encode(),
      );
      // `browser_` prefixes this one's directory too.
      write(
        'browser_pair_20261108_140500_000_emulator-5556',
        _pass(8, {'01_a': _red}, suite: 'browser_pair').encode(),
      );
      write('browser_20261109_140500_000_emulator-5556', '{not json');
      File(
        joinPath(paths.passRoot, ['browser_20261110_merged.json']),
      ).writeAsStringSync(_pass(10, {'01_a': _red}).encode());

      final all = readSuiteHistory(paths, 'browser');
      expect(all.reports.map((r) => r.started.day), [6, 5, 4, 3, 2, 1]);
      expect(all.unreadable, 1);

      final last = readSuiteHistory(paths, 'browser', last: 2);
      expect(last.reports.map((r) => r.started.day), [6, 5]);
      expect(readSuiteHistory(paths, 'calendar').reports, isEmpty);
    });

    test('no pass directory at all reads as no report', () {
      final read = readSuiteHistory(paths, 'browser');
      expect(read.reports, isEmpty);
      expect(read.unreadable, 0);
    });
  });
}
