import 'dart:convert';
import 'dart:math' as math;

import 'errors.dart';

/// The device a pass ran on.
class PassDevice {
  const PassDevice({required this.id, required this.label, required this.platform});

  factory PassDevice.fromJson(Map<String, dynamic> json) => PassDevice(
        id: json['id'] as String,
        label: json['label'] as String,
        platform: json['platform'] as String,
      );

  final String id;
  final String label;

  /// `android`, `ios` or `macos`.
  final String platform;

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'platform': platform};
}

/// One step of a flow as it ran.
class StepRecord {
  const StepRecord({
    required this.n,
    required this.line,
    required this.ms,
    required this.ok,
    required this.output,
  });

  factory StepRecord.fromJson(Map<String, dynamic> json) => StepRecord(
        n: json['n'] as int,
        line: json['line'] as String,
        ms: json['ms'] as int,
        ok: json['status'] == 'ok',
        output: json['output'] as String? ?? '',
      );

  /// 1-based position in the flow file's step lines.
  final int n;
  final String line;
  final int ms;
  final bool ok;

  /// What the step printed; stderr lines carry a `! ` marker.
  final String output;

  /// The verb, which `verbStats` groups by.
  String get verb {
    final trimmed = line.trimLeft();
    final space = trimmed.indexOf(' ');
    return space < 0 ? trimmed : trimmed.substring(0, space);
  }

  Map<String, dynamic> toJson() => {
        'n': n,
        'line': line,
        'verb': verb,
        'ms': ms,
        'status': ok ? 'ok' : 'failed',
        'output': output,
      };
}

/// Where and why a flow stopped. [step] is 0 when the reseed or the
/// prelude failed before the flow's own first step.
class FlowFailure {
  const FlowFailure({
    required this.step,
    required this.line,
    required this.exitCode,
    required this.message,
    this.shot,
    this.dump,
    this.errors,
  });

  factory FlowFailure.fromJson(Map<String, dynamic> json) => FlowFailure(
        step: json['step'] as int,
        line: json['line'] as String,
        exitCode: json['exitCode'] as int,
        message: json['message'] as String? ?? '',
        shot: json['shot'] as String?,
        dump: json['dump'] as String?,
        errors: json['errors'] as String?,
      );

  final int step;
  final String line;
  final int exitCode;
  final String message;
  final String? shot;
  final String? dump;
  final String? errors;

  FlowFailure withEvidence({String? shot, String? dump, String? errors}) =>
      FlowFailure(
        step: step,
        line: line,
        exitCode: exitCode,
        message: message,
        shot: shot,
        dump: dump,
        errors: errors,
      );

  Map<String, dynamic> toJson() => {
        'step': step,
        'line': line,
        'exitCode': exitCode,
        'message': message,
        'shot': shot,
        'dump': dump,
        'errors': errors,
      };
}

/// A flow's verdict; `skipped` is a flow the pass never started, after
/// `--stop-on-fail` or a seed that would not go in.
enum FlowStatus { passed, failed, skipped }

/// One flow of a pass.
class FlowRecord {
  const FlowRecord({
    required this.name,
    required this.status,
    this.durationMs = 0,
    this.reseedMs,
    this.preludeMs,
    this.steps = const [],
    this.failure,
  });

  factory FlowRecord.fromJson(Map<String, dynamic> json) => FlowRecord(
        name: json['name'] as String,
        status: FlowStatus.values.byName(json['status'] as String),
        durationMs: json['durationMs'] as int? ?? 0,
        reseedMs: json['reseedMs'] as int?,
        preludeMs: json['preludeMs'] as int?,
        steps: [
          for (final step in (json['steps'] as List? ?? const []))
            StepRecord.fromJson((step as Map).cast<String, dynamic>()),
        ],
        failure: json['failure'] == null
            ? null
            : FlowFailure.fromJson((json['failure'] as Map).cast<String, dynamic>()),
      );

  final String name;
  final FlowStatus status;

  /// The whole flow: its reseed and prelude included.
  final int durationMs;
  final int? reseedMs;
  final int? preludeMs;
  final List<StepRecord> steps;
  final FlowFailure? failure;

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.name,
        'durationMs': durationMs,
        'reseedMs': reseedMs,
        'preludeMs': preludeMs,
        'steps': [for (final step in steps) step.toJson()],
        'failure': failure?.toJson(),
      };
}

/// How long one verb took across a pass.
class VerbStat {
  const VerbStat({
    required this.count,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
  });

  factory VerbStat.of(List<int> samples) {
    final sorted = [...samples]..sort();
    return VerbStat(
      count: sorted.length,
      p50Ms: percentile(sorted, 50),
      p95Ms: percentile(sorted, 95),
      maxMs: sorted.isEmpty ? 0 : sorted.last,
    );
  }

  final int count;
  final int p50Ms;
  final int p95Ms;
  final int maxMs;

  Map<String, dynamic> toJson() =>
      {'count': count, 'p50Ms': p50Ms, 'p95Ms': p95Ms, 'maxMs': maxMs};
}

/// Nearest-rank percentile of already sorted [sorted]: always one of the
/// samples, so a p95 over twenty steps is the nineteenth, not an average.
int percentile(List<int> sorted, int p) {
  if (sorted.isEmpty) return 0;
  final rank = (p / 100 * sorted.length).ceil();
  return sorted[math.max(rank, 1) - 1];
}

/// Per-verb timings over every step that ran, plus each reseed counted as
/// a `relaunch` — which is what it is, and what dominates a reseeding pass.
Map<String, VerbStat> computeVerbStats(List<FlowRecord> flows) {
  final samples = <String, List<int>>{};
  for (final flow in flows) {
    final reseed = flow.reseedMs;
    if (reseed != null) (samples['relaunch'] ??= []).add(reseed);
    for (final step in flow.steps) {
      (samples[step.verb] ??= []).add(step.ms);
    }
  }
  final verbs = samples.keys.toList()..sort();
  return {for (final verb in verbs) verb: VerbStat.of(samples[verb]!)};
}

/// One `qa pass` run, or several merged: `report.json`, a contract with the
/// agents and docs that read it, so its keys only change under a new
/// [schemaVersion].
class PassReport {
  PassReport({
    required this.suite,
    required this.label,
    required this.device,
    this.devices,
    required this.host,
    required this.started,
    required this.finished,
    required this.shard,
    required this.reseed,
    required this.fixture,
    required this.prelude,
    required this.build,
    required this.flows,
    this.partial = false,
    this.quietMs,
    this.quietAlarms,
    this.quietFailure,
    this.quietSkipped,
    this.quietDevices,
    this.quietUncounted,
  });

  factory PassReport.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != schemaVersion) {
      throw UsageFailure(
        'not a pass report of schema $schemaVersion (schema: ${json['schema']})',
      );
    }
    final shard = json['shard'] as Map?;
    return PassReport(
      suite: json['suite'] as String,
      label: json['label'] as String?,
      device: json['device'] == null
          ? null
          : PassDevice.fromJson((json['device'] as Map).cast<String, dynamic>()),
      devices: json['devices'] == null
          ? null
          : [
              for (final d in json['devices'] as List)
                PassDevice.fromJson((d as Map).cast<String, dynamic>()),
            ],
      host: json['host'] as String,
      started: DateTime.parse(json['started'] as String),
      finished: DateTime.parse(json['finished'] as String),
      shard: shard == null ? null : (shard['index'] as int, shard['count'] as int),
      reseed: json['reseed'] as String,
      fixture: json['fixture'] as String?,
      prelude: json['prelude'] as String?,
      build: (json['build'] as Map?)?.cast<String, dynamic>(),
      flows: [
        for (final flow in json['flows'] as List)
          FlowRecord.fromJson((flow as Map).cast<String, dynamic>()),
      ],
      partial: json['partial'] as bool? ?? false,
      quietMs: json['quietMs'] as int?,
      quietAlarms: json['quietAlarms'] as int?,
      quietFailure: json['quietFailure'] as String?,
      quietSkipped: json['quietSkipped'] as String?,
      quietDevices: json['quietDevices'] as int?,
      quietUncounted: json['quietUncounted'] as int?,
    );
  }

  static const int schemaVersion = 1;

  final String suite;
  final String? label;

  /// Null on a merged report, which lists [devices] instead.
  final PassDevice? device;
  final List<PassDevice>? devices;

  /// `Platform.operatingSystem` of the machine that drove the pass.
  final String host;
  final DateTime started;
  final DateTime finished;

  /// 1-based index and count, or null for a whole suite.
  final (int, int)? shard;

  /// The [ReseedMode] name the pass ran with.
  final String reseed;
  final String? fixture;
  final String? prelude;

  /// The installed build's `installed_<device>.json`, when there is one.
  final Map<String, dynamic>? build;
  final List<FlowRecord> flows;

  /// True while the pass is still running: `pass` rewrites the report
  /// after every flow, so a pass killed late still leaves the flows it
  /// finished, and only its last write says the list is complete.
  final bool partial;

  /// How long the closing `relaunch --fresh` took to leave the device
  /// quiet (the app on an empty QA database, so none of the fixture's
  /// alarms rings between passes); null when it did not run
  /// (`--keep-state`, or a report from before it existed). On a merged
  /// report, the slowest device's.
  final int? quietMs;

  /// The app's alarms still armed after that relaunch, counted from
  /// `dumpsys alarm`'s pending list; null off Android or when it was not
  /// counted. Summed over the devices of a merged report.
  final int? quietAlarms;

  /// Why the device could not be left quiet, when it could not.
  final String? quietFailure;

  /// Why the closing relaunch was not run at all: `--keep-state`, a
  /// `--no-reseed` pass (whose state is the point), or a pass that stopped
  /// on `--stop-on-fail` and keeps the red flow's screen.
  final String? quietSkipped;

  /// On a merged report, the devices whose count came back 0 and those
  /// whose count failed: a sum alone would print "0 alarms armed" over a
  /// device nobody counted. Null on a single device's report.
  final int? quietDevices;
  final int? quietUncounted;

  int get durationMs => finished.difference(started).inMilliseconds;

  int count(FlowStatus status) => flows.where((f) => f.status == status).length;

  /// A partial report is never green: the flows it lacks did not pass.
  bool get allPassed =>
      !partial && flows.isNotEmpty && count(FlowStatus.passed) == flows.length;

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'suite': suite,
        'label': label,
        'device': device?.toJson(),
        if (devices != null) 'devices': [for (final d in devices!) d.toJson()],
        'host': host,
        'started': started.toUtc().toIso8601String(),
        'finished': finished.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'partial': partial,
        'shard': shard == null ? null : {'index': shard!.$1, 'count': shard!.$2},
        'reseed': reseed,
        'fixture': fixture,
        'prelude': prelude,
        'build': build,
        'quietMs': quietMs,
        'quietAlarms': quietAlarms,
        'quietFailure': quietFailure,
        'quietSkipped': quietSkipped,
        'quietDevices': quietDevices,
        'quietUncounted': quietUncounted,
        'summary': {
          'flows': flows.length,
          'passed': count(FlowStatus.passed),
          'failed': count(FlowStatus.failed),
          'skipped': count(FlowStatus.skipped),
        },
        'flows': [for (final flow in flows) flow.toJson()],
        'verbStats': {
          for (final entry in computeVerbStats(flows).entries)
            entry.key: entry.value.toJson(),
        },
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static PassReport decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw UsageFailure('not a pass report (invalid JSON: ${e.message})');
    }
    if (json is! Map<String, dynamic>) {
      throw UsageFailure('not a pass report (expected a JSON object)');
    }
    return PassReport.fromJson(json);
  }
}

/// Flow names that more than one of [reports] carries, in name order:
/// shards that overlap, or a red flow re-run with `--only` and merged in.
List<String> duplicateFlowNames(List<PassReport> reports) {
  final seen = <String>{};
  final repeated = <String>{};
  for (final report in reports) {
    for (final flow in report.flows) {
      if (!seen.add(flow.name)) repeated.add(flow.name);
    }
  }
  return repeated.toList()..sort();
}

/// The shards of one suite as one report: flows in name order, the
/// earliest start and the latest finish, every device that took part. A
/// flow several reports carry is kept once, from the report given last,
/// so a re-run merged after its shard replaces it.
PassReport mergeReports(List<PassReport> reports) {
  if (reports.isEmpty) throw UsageFailure('--merge needs at least one report');
  final suites = reports.map((r) => r.suite).toSet();
  if (suites.length > 1) {
    throw UsageFailure('--merge takes reports of one suite (got ${suites.join(', ')})');
  }
  final devices = <String, PassDevice>{};
  for (final report in reports) {
    for (final device in [?report.device, ...?report.devices]) {
      devices.putIfAbsent(device.id, () => device);
    }
  }
  final first = reports.first;
  final byName = <String, FlowRecord>{
    for (final report in reports)
      for (final flow in report.flows) flow.name: flow,
  };
  final quietFailures = reports.map((r) => r.quietFailure).nonNulls.toList();
  final skipped = reports.map((r) => r.quietSkipped).nonNulls.toSet();
  // A device's quiet ran when it has a time and no failure; one whose
  // count failed is told apart from one that counted nothing.
  final ran = reports.where((r) => r.quietMs != null && r.quietFailure == null);
  final anyRan = ran.isNotEmpty;
  int deviceCount(PassReport r) => r.devices?.length ?? 1;
  return PassReport(
    suite: first.suite,
    label: reports.map((r) => r.label).nonNulls.firstOrNull,
    device: null,
    devices: devices.values.toList(),
    host: first.host,
    started: reports.map((r) => r.started).reduce((a, b) => a.isBefore(b) ? a : b),
    finished: reports.map((r) => r.finished).reduce((a, b) => a.isAfter(b) ? a : b),
    shard: null,
    reseed: first.reseed,
    fixture: first.fixture,
    prelude: first.prelude,
    build: first.build,
    flows: byName.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
    partial: reports.any((r) => r.partial),
    quietMs: reports.map((r) => r.quietMs).nonNulls.fold<int?>(
        null, (slowest, ms) => slowest == null ? ms : math.max(slowest, ms)),
    quietAlarms: reports.map((r) => r.quietAlarms).nonNulls.fold<int?>(
        null, (sum, count) => (sum ?? 0) + count),
    quietFailure: quietFailures.isEmpty ? null : quietFailures.join('; '),
    quietSkipped: skipped.isEmpty ? null : skipped.join('; '),
    quietDevices: !anyRan
        ? null
        : ran.fold<int>(0, (sum, r) => sum + (r.quietDevices ??
            (r.quietAlarms == 0 ? deviceCount(r) : 0))),
    quietUncounted: !anyRan
        ? null
        : ran.fold<int>(0, (sum, r) => sum + (r.quietUncounted ??
            (r.quietAlarms == null ? deviceCount(r) : 0))),
  );
}

/// The line that says whether a pass left its device (or, merged, its
/// devices) quiet, or why it did not try; null for a report from before
/// the closing relaunch existed.
String? quietLine(PassReport report) {
  final who = report.device == null ? 'devices' : 'device';
  final failure = report.quietFailure;
  if (failure != null) return '$who not left quiet: ${headline(failure)}';
  final ms = report.quietMs;
  if (ms == null) {
    final skipped = report.quietSkipped;
    return skipped == null ? null : 'quiet relaunch skipped: $skipped';
  }
  final took = '${(ms / 1000).toStringAsFixed(1)} s';
  final alarms = report.quietAlarms;
  final uncounted = report.quietUncounted ?? 0;
  final quiet = report.quietDevices ?? 0;
  if (alarms == null || (uncounted > 0 && quiet == 0 && alarms == 0)) {
    return '$who left quiet in $took (alarms not counted)';
  }
  final notCounted = uncounted == 0 ? '' : ', $uncounted not counted';
  if (alarms == 0) {
    return uncounted == 0
        ? '$who left quiet (0 alarms armed) in $took'
        : '$quiet device${quiet == 1 ? '' : 's'} quiet$notCounted in $took';
  }
  return '$who not left quiet: $alarms alarm(s) of the app still armed '
      'after relaunch --fresh$notCounted ($took)';
}

/// A failure message cut to one summary line: its first line, joined with
/// the second when the first only introduces it (`expect` says "… failed
/// after 5s:" and names the miss below), and capped so a wait's listing of
/// the whole screen does not swamp the table. The report keeps it whole.
String headline(String message, {int max = 160}) {
  final lines = message.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return '';
  var text = lines.first;
  if (text.endsWith(':') && lines.length > 1) text = '$text ${lines[1]}';
  return text.length <= max ? text : '${text.substring(0, max - 1)}…';
}

/// What the summary of a report still marked partial says: its process
/// ended (killed, crashed, its host gone) before the last write, so the
/// flows it lists are not the suite.
const String partialLine = 'PARTIAL — the pass did not finish';

/// What `qa pass` prints at the end, and what `--summary` and `--merge`
/// print: one line per flow, the verdict line, then the verb table.
List<String> summaryLines(PassReport report, {required String reportPath}) {
  final width = report.flows.fold<int>(0, (w, f) => math.max(w, f.name.length));
  final lines = <String>[];
  for (final flow in report.flows) {
    final mark = switch (flow.status) {
      FlowStatus.passed => 'ok  ',
      FlowStatus.failed => 'FAIL',
      FlowStatus.skipped => 'skip',
    };
    final failure = flow.failure;
    final ms = flow.status == FlowStatus.skipped ? '' : '${flow.durationMs} ms';
    final tail = failure == null
        ? ''
        : '  step ${failure.step}: ${failure.line} — ${headline(failure.message)}';
    lines.add('$mark  ${flow.name.padRight(width)}  ${ms.padLeft(9)}$tail'.trimRight());
  }
  final ids = report.device != null
      ? report.device!.id
      : (report.devices ?? const []).map((d) => d.id).join(', ');
  final seconds = (report.durationMs / 1000).toStringAsFixed(1);
  lines.add('pass: ${report.count(FlowStatus.passed)}/${report.flows.length} '
      'green in $seconds s on $ids — report $reportPath');
  if (report.partial) lines.add(partialLine);
  final quiet = quietLine(report);
  if (quiet != null) lines.add(quiet);
  final stats = computeVerbStats(report.flows);
  if (stats.isNotEmpty) {
    final verbWidth = stats.keys.fold<int>(4, (w, v) => math.max(w, v.length));
    lines.add('${'verb'.padRight(verbWidth)}  count    p50    p95    max  (ms)');
    stats.forEach((verb, stat) {
      lines.add('${verb.padRight(verbWidth)}  ${'${stat.count}'.padLeft(5)}  '
          '${'${stat.p50Ms}'.padLeft(5)}  ${'${stat.p95Ms}'.padLeft(5)}  '
          '${'${stat.maxMs}'.padLeft(5)}');
    });
  }
  return lines;
}
