/// What the platform holds for the app while the app itself is closed — its
/// scheduled work and its armed alarms — read from `dumpsys`, and the line
/// the shared check logs as it ends: the evidence a pass has of a run with
/// no app to ask (`docs/cloud-shared-freshness.md` §12).
library;

/// One of the app's jobs in `dumpsys jobscheduler`.
class AppJob {
  final int id;

  /// `Run time: earliest=…` as the platform prints it (`+2h59m56s958ms`),
  /// or null when the block has none.
  final String? earliest;

  /// `Required constraints: …` without its mask (`TIMING_DELAY
  /// CONNECTIVITY`), or null.
  final String? constraints;

  /// The namespace the job was scheduled in, when it has one (WorkManager's
  /// is `androidx.work.systemjobscheduler`): `cmd jobscheduler run` finds a
  /// namespaced job only when told it (`-n`).
  final String? namespace;

  const AppJob(this.id, {this.earliest, this.constraints, this.namespace});

  @override
  String toString() =>
      '#$id earliest=${earliest ?? '?'} constraints=${constraints ?? '?'}';
}

/// A job's header line. API 36 prints a namespaced job — every one of
/// WorkManager's — with the namespace before the uid and again, between
/// two `@`, before the component:
/// `JOB androidx.work.systemjobscheduler:u0a217/7: bff8282 @androidx.work.systemjobscheduler@com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService`.
/// A job with no namespace, and every job on older platforms, is
/// `JOB #u0a217/14: 2f1c0b3 com.alexzamfir.anta/…SystemJobService`.
final RegExp _jobHeader = RegExp(
  r'^\s*JOB (?:([^\s#:]+):)?#?[^\s/:]+/(\d+): \S+ (?:@[^@\s]*@)?(\S+)\s*$',
);
final RegExp _jobConstraints = RegExp(
  r'^\s*Required constraints:\s*(.*?)(?:\s*\[0x[0-9a-fA-F]+\])?\s*$',
);
final RegExp _jobEarliest = RegExp(r'^\s*Run time: earliest=([^,]+),');

/// The jobs [package]'s own services hold in `dumpsys jobscheduler`
/// output, once each by id: WorkManager's work runs as jobs of its
/// `SystemJobService`.
List<AppJob> parseAppJobs(String dumpsys, String package) {
  final jobs = <int, AppJob>{};
  int? id;
  String? namespace;
  String? earliest;
  String? constraints;
  void close() {
    final open = id;
    if (open != null) {
      final ns = namespace;
      jobs.putIfAbsent(
        open,
        () => AppJob(
          open,
          earliest: earliest,
          constraints: constraints,
          namespace: ns,
        ),
      );
    }
    id = null;
    namespace = null;
    earliest = null;
    constraints = null;
  }

  for (final line in dumpsys.split('\n')) {
    final header = _jobHeader.firstMatch(line.trimRight());
    if (header != null) {
      close();
      if (header.group(3)!.startsWith('$package/')) {
        id = int.parse(header.group(2)!);
        namespace = header.group(1);
      }
      continue;
    }
    if (id == null) continue;
    earliest ??= _jobEarliest.firstMatch(line)?.group(1)?.trim();
    constraints ??= _jobConstraints.firstMatch(line)?.group(1)?.trim();
  }
  close();
  return jobs.values.toList()..sort((a, b) => a.id.compareTo(b.id));
}

/// What `dumpsys jobscheduler` says of [package], unparsed, for `qa work
/// --raw`: each block whose `JOB` header names it, whole, and every other
/// line that names it — how a new platform's shape is read before the
/// parser is taught it.
List<String> rawAppJobLines(String dumpsys, String package) {
  final lines = <String>[];
  var inBlock = false;
  for (final line in dumpsys.split('\n')) {
    final text = line.trimRight();
    if (RegExp(r'^\s*JOB ').hasMatch(text)) {
      inBlock = text.contains(package);
    } else if (text.isEmpty || !text.startsWith('  ')) {
      inBlock = false;
    }
    if (inBlock || text.contains(package)) lines.add(text);
  }
  return lines;
}

/// The one line `qa work` prints.
String describeAppJobs(List<AppJob> jobs) => jobs.isEmpty
    ? 'work: none'
    : 'work: ${jobs.length} scheduled  ${jobs.join('  ')}';

/// Which of the app's two alert tiers an armed alarm belongs to.
enum ArmedTier {
  /// `flutter_local_notifications`' scheduled notification.
  reminder,

  /// The alarm fork's alarm clock.
  alarm,

  /// Anything else the app armed (the alarm's upcoming notice).
  other,
}

/// One alarm of the app in `dumpsys alarm`'s pending list.
class ArmedAlarm {
  /// When it fires, in epoch milliseconds (`origWhen`).
  final int atMs;
  final ArmedTier tier;

  const ArmedAlarm(this.atMs, this.tier);
}

/// The alarms [package] holds armed in `dumpsys alarm` output, soonest
/// first, each told by tier from its block: an `Alarm clock:` line is the
/// alarm tier's, the notification plugin's receiver the reminder tier's.
List<ArmedAlarm> parseArmedAlarms(String dumpsys, String package) {
  final header = RegExp(
    r'^\s*[A-Z_]+ #\d+: Alarm\{\S+ type \d+ origWhen (\d+) [^}]*\s' +
        RegExp.escape(package) +
        r'\}',
  );
  final anyHeader = RegExp(r'^\s*[A-Z_]+ #\d+: Alarm\{');
  final alarms = <ArmedAlarm>[];
  int? at;
  var tier = ArmedTier.other;
  void close() {
    final open = at;
    if (open != null) alarms.add(ArmedAlarm(open, tier));
    at = null;
    tier = ArmedTier.other;
  }

  for (final line in dumpsys.split('\n')) {
    if (anyHeader.hasMatch(line)) {
      close();
      final own = header.firstMatch(line);
      if (own != null) at = int.parse(own.group(1)!);
      continue;
    }
    if (at == null) continue;
    if (line.trim().isEmpty) {
      close();
    } else if (line.contains('Alarm clock:') ||
        line.contains('.alarm.AlarmReceiver')) {
      tier = ArmedTier.alarm;
    } else if (line.contains('ScheduledNotificationReceiver') &&
        tier == ArmedTier.other) {
      tier = ArmedTier.reminder;
    }
  }
  close();
  return alarms..sort((a, b) => a.atMs.compareTo(b.atMs));
}

/// The instants of [alarms] of [tier] — every tier but `other` when null —
/// soonest first.
List<int> armedInstants(List<ArmedAlarm> alarms, ArmedTier? tier) => [
  for (final alarm in alarms)
    if (tier == null ? alarm.tier != ArmedTier.other : alarm.tier == tier)
      alarm.atMs,
];

/// The one line `qa armed` prints: each tier's instants in UTC.
String describeArmed(List<ArmedAlarm> alarms) {
  String list(ArmedTier tier) {
    final at = armedInstants(alarms, tier);
    if (at.isEmpty) return 'none';
    return at
        .map(
          (ms) => DateTime.fromMillisecondsSinceEpoch(
            ms,
            isUtc: true,
          ).toIso8601String().substring(0, 16),
        )
        .join(' ');
  }

  return 'armed: reminder=${list(ArmedTier.reminder)}  '
      'alarm=${list(ArmedTier.alarm)}';
}

/// What `qa armed --capture` remembers and `--expect` reads back.
String encodeInstants(List<int> instants) => instants.join(',');

List<int> decodeInstants(String captured) => [
  for (final part in captured.split(',')) ?int.tryParse(part.trim()),
];

/// Why [now] does not meet [expectation], or null when it does.
///
/// `none` and `some` speak of [now] alone. `same:<name>` and
/// `shifted:<name>:<seconds>` compare it with what was captured as
/// `<name>` ([captures]), instant by instant from the soonest, over as many
/// as both hold — the horizon may add or drop one at its far end between
/// two reads — and never over none.
String? armedExpectationFailure(
  String expectation,
  List<int> now,
  Map<String, String> captures,
) {
  final parts = expectation.split(':');
  switch (parts.first) {
    case 'none':
      return now.isEmpty ? null : '${now.length} armed, expected none';
    case 'some':
      return now.isEmpty ? 'nothing armed' : null;
    case 'same' || 'shifted':
      final shifted = parts.first == 'shifted';
      if (parts.length != (shifted ? 3 : 2)) {
        return '--expect ${parts.first} takes '
            '${shifted ? 'shifted:<name>:<seconds>' : 'same:<name>'}';
      }
      final captured = captures[parts[1]];
      if (captured == null) return 'nothing was captured as "${parts[1]}"';
      final seconds = shifted ? int.tryParse(parts[2]) : 0;
      if (seconds == null) return 'not a number of seconds: "${parts[2]}"';
      final before = decodeInstants(captured);
      if (before.isEmpty) return '"${parts[1]}" captured nothing armed';
      if (now.isEmpty) return 'nothing armed now';
      final overlap = before.length < now.length ? before.length : now.length;
      for (var i = 0; i < overlap; i++) {
        final moved = (now[i] - before[i]) ~/ 1000;
        if (moved != seconds) {
          return 'instant ${i + 1} of $overlap moved by $moved s, '
              'expected $seconds s';
        }
      }
      return null;
  }
  return 'unknown --expect "$expectation" '
      '(none, some, same:<name>, shifted:<name>:<seconds>)';
}

final RegExp _triggerEnded = RegExp(
  r'\[SharedRefresh\] trigger\((\w+)\) ended: (\w+)',
);

/// How the last trigger of the shared check in [log] ended — `read`,
/// `forwarded`, `notWanted`, … — or null when none ended there.
String? lastSharedRefreshEnding(String log) {
  String? ending;
  for (final match in _triggerEnded.allMatches(log)) {
    ending = match.group(2);
  }
  return ending;
}
