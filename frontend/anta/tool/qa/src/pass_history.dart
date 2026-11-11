import 'dart:io';
import 'dart:math' as math;

import 'errors.dart';
import 'pass_report.dart';
import 'paths.dart';

/// How many reports `qa pass --history` reads by default; `reap --prune`
/// keeps at least as many per suite.
const int defaultHistoryReports = 20;

/// One flow across the reports `--history` read.
class FlowHistory {
  FlowHistory(this.name);

  final String name;

  /// Reports in which the flow ran, green or red; a skipped flow did not.
  int runs = 0;
  int reds = 0;

  /// Times the pass recovered its guest after this flow failed for the
  /// fleet (each `infra` entry naming it).
  int recoveries = 0;

  /// When the newest report in which the flow was red started.
  DateTime? lastRed;

  int get greens => runs - reds;

  /// Red and green in the same window: what one pass can never show.
  bool get flaky => reds > 0 && greens > 0;

  /// Nothing worth a line of its own: green every time it ran, never
  /// recovered.
  bool get quiet => reds == 0 && recoveries == 0;
}

/// The newest [last] single-device reports of [suite] under
/// `build/qa/pass/`, newest first, and how many could not be read. A merged
/// report (`fleet pass`, `--merge`) is left out: its shards' own reports
/// are already counted, and counting both would run every flow twice.
({List<PassReport> reports, int unreadable}) readSuiteHistory(
  QaPaths paths,
  String suite, {
  int last = defaultHistoryReports,
}) {
  final root = Directory(paths.passRoot);
  if (!root.existsSync()) return (reports: const [], unreadable: 0);
  final prefix = '${QaPaths.safeId(suite)}_';
  final reports = <PassReport>[];
  var unreadable = 0;
  for (final dir in root.listSync().whereType<Directory>()) {
    if (!dir.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last
        .startsWith(prefix)) {
      continue;
    }
    final file = File(joinPath(dir.path, ['report.json']));
    if (!file.existsSync()) continue;
    try {
      final report = PassReport.decode(file.readAsStringSync());
      // `alerts_` also prefixes `alerts_pair_…`: the report names its suite.
      if (report.suite != suite || report.device == null) continue;
      reports.add(report);
    } on QaException {
      unreadable++;
    } on FileSystemException {
      unreadable++;
    } on TypeError {
      unreadable++;
    } on FormatException {
      unreadable++;
    }
  }
  reports.sort((a, b) => b.started.compareTo(a.started));
  return (reports: reports.take(last).toList(), unreadable: unreadable);
}

/// Every flow [reports] ran, by name.
List<FlowHistory> flowHistories(List<PassReport> reports) {
  final byName = <String, FlowHistory>{};
  for (final report in reports) {
    for (final flow in report.flows) {
      final history = byName.putIfAbsent(
        flow.name,
        () => FlowHistory(flow.name),
      );
      if (flow.status == FlowStatus.skipped) continue;
      history.runs++;
      if (flow.status == FlowStatus.failed) {
        history.reds++;
        final last = history.lastRed;
        if (last == null || report.started.isAfter(last)) {
          history.lastRed = report.started;
        }
      }
    }
    for (final entry in report.infra) {
      byName
          .putIfAbsent(entry.flow, () => FlowHistory(entry.flow))
          .recoveries++;
    }
  }
  return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// What `qa pass --history` prints: a header, one row per flow that was red
/// or recovered at least once (the most reds first), and the green rest as
/// one count.
List<String> historyLines(
  String suite,
  List<PassReport> reports, {
  int unreadable = 0,
}) {
  if (reports.isEmpty) {
    return [
      'history: no report of "$suite" under build/qa/pass'
          '${unreadable == 0 ? '' : ' ($unreadable unreadable)'}',
    ];
  }
  final oldest = reports
      .map((r) => r.started)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final newest = reports
      .map((r) => r.started)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final devices = reports.map((r) => r.device!.id).toSet().toList()..sort();
  final lines = [
    'history: $suite — ${reports.length} report(s) from ${_stamp(oldest)} '
        'to ${_stamp(newest)} on ${devices.join(', ')}'
        '${unreadable == 0 ? '' : ' ($unreadable unreadable, left out)'}',
  ];
  final all = flowHistories(reports);
  final noisy = all.where((f) => !f.quiet).toList()
    ..sort((a, b) {
      final reds = b.reds.compareTo(a.reds);
      if (reds != 0) return reds;
      final recoveries = b.recoveries.compareTo(a.recoveries);
      return recoveries != 0 ? recoveries : a.name.compareTo(b.name);
    });
  final green = all.length - noisy.length;
  if (noisy.isEmpty) {
    lines.add('all ${all.length} flow(s) green in every run');
    return lines;
  }
  final width = noisy.fold<int>(4, (w, f) => math.max(w, f.name.length));
  lines.add('${'flow'.padRight(width)}  runs  reds  recovered  last red');
  for (final flow in noisy) {
    final lastRed = flow.lastRed == null ? '-' : _stamp(flow.lastRed!);
    lines.add(
      '${flow.name.padRight(width)}  ${'${flow.runs}'.padLeft(4)}  '
              '${'${flow.reds}'.padLeft(4)}  ${'${flow.recoveries}'.padLeft(9)}  '
              '${lastRed.padRight(16)}${flow.flaky ? '  flaky' : ''}'
          .trimRight(),
    );
  }
  lines.add(
    green == 0
        ? 'no flow green in every run'
        : '$green other flow(s) green in every run',
  );
  return lines;
}

/// `2026-11-11 14:05`, local time.
String _stamp(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
