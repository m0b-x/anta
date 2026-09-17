/// The service URIs a detached `flutter run` prints once it is up.
class RunUris {
  const RunUris({this.dtd, this.vmService});

  final String? dtd;
  final String? vmService;

  bool get complete => dtd != null && vmService != null;

  @override
  String toString() => 'dtd=$dtd vm=$vmService';
}

final RegExp _dtdPatterns = RegExp(
  r'(?:The Dart Tooling Daemon is available at:|Serving the Dart Tooling Daemon at)\s*(ws://\S+)',
);

final RegExp _vmPatterns = RegExp(
  r'(?:A Dart VM Service on .* is available at:|Dart VM Service is available at:|'
  r'The Dart VM service is listening on|Debug service listening on)\s*((?:ws|http)s?://\S+)',
);

/// Pulls the DTD and VM service URIs out of `flutter run --print-dtd` output.
RunUris extractUris(String logText) {
  String? clean(RegExpMatch? match) {
    if (match == null) return null;
    var uri = match.group(1)!.trim();
    while (uri.isNotEmpty && (uri.endsWith('.') || uri.endsWith(','))) {
      uri = uri.substring(0, uri.length - 1);
    }
    return uri.isEmpty ? null : uri;
  }

  return RunUris(
    dtd: clean(_dtdPatterns.allMatches(logText).lastOrNull),
    vmService: clean(_vmPatterns.allMatches(logText).lastOrNull),
  );
}

final RegExp _launchFailure = RegExp(
  r'Gradle task \w+ failed with exit code|FAILURE: Build failed with an exception|'
  r'Target \w+ failed:|^Error: No devices found|^Error: Unable to |'
  r'^Error: Target file .* not found|Installation failed|'
  r'^Application finished\.?$',
  multiLine: true,
);

final RegExp _softLaunchFailure = RegExp(
  r'Error connecting to the service protocol|'
  r'Lost connection to device|the Dart compiler exited unexpectedly',
);

/// The line that says a `flutter run` has failed for good, if the log has one.
///
/// Without this the driver would sit out its whole timeout waiting for URIs
/// that a broken build is never going to print.
String? launchFailureLine(String logText) => _firstMatching(logText, _launchFailure);

/// A line that usually but not always means the run is dead — the VM service
/// handshake can lose one race and still come up. The caller gives these a
/// grace period before treating them as fatal.
String? softLaunchFailureLine(String logText) =>
    _firstMatching(logText, _softLaunchFailure);

String? _firstMatching(String logText, RegExp pattern) {
  if (!pattern.hasMatch(logText)) return null;
  for (final line in logText.split('\n')) {
    final trimmed = line.trim();
    if (pattern.hasMatch(trimmed)) return trimmed;
  }
  return pattern.firstMatch(logText)?.group(0);
}

final RegExp _errorLine = RegExp(
  r'\[anta\].*(?:error|ERROR)|Exception|Unhandled|^E/|FATAL|'
  r'══╡ EXCEPTION CAUGHT|Error:',
  multiLine: true,
);

/// Lines of a run log that look like an app error, most recent last.
List<String> errorLines(String logText, {int limit = 50}) {
  final hits = <String>[];
  for (final line in logText.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) continue;
    if (_errorLine.hasMatch(trimmed)) hits.add(trimmed);
  }
  if (hits.length <= limit) return hits;
  return hits.sublist(hits.length - limit);
}

/// Lines a QA launch prints on the `[qa]` channel as it consumes its markers.
class QaMarkerLines {
  const QaMarkerLines({this.reset, this.seed, this.onboarding});

  /// `[qa] reset: cleared preferences and qa.db`
  final String? reset;

  /// `[qa] seed: imported 4 folders, 3 notes` — or the failure wording.
  final String? seed;

  /// `[qa] onboarding marked completed`
  final String? onboarding;

  List<String> get all =>
      [reset, seed, onboarding].whereType<String>().toList();

  /// Whether the seed line reports that the import did not happen.
  ///
  /// `QaBootstrap` prints `seed: import failed: …` for a rejected backup and
  /// `seed: threw …` for one that blew up, and both leave the database in a
  /// state the checklist below it would silently mis-read.
  bool get seedFailed {
    final line = seed;
    if (line == null) return false;
    return line.contains('import failed') || line.contains('threw');
  }

  /// Whether the reset line is the refusal `QaBootstrap` prints when the
  /// database it was asked to wipe is the owner's.
  bool get resetFailed => reset?.contains('refused') ?? false;
}

final RegExp _qaLine = RegExp(r'\[qa\]\s*(.*)$');

/// Picks the `[qa]` lines out of a run log or a logcat dump.
///
/// The same three lines reach two different places — `flutter run`'s log, and
/// logcat when the VM service handshake lost its race — so both are scanned
/// and the last occurrence of each wins.
QaMarkerLines parseQaMarkers(String text) {
  String? reset;
  String? seed;
  String? onboarding;
  for (final raw in text.split('\n')) {
    final match = _qaLine.firstMatch(raw.trimRight());
    if (match == null) continue;
    final body = match.group(1)!.trim();
    if (body.startsWith('reset')) {
      reset = body;
    } else if (body.startsWith('seed')) {
      seed = body;
    } else if (body.startsWith('onboarding')) {
      onboarding = body;
    }
  }
  return QaMarkerLines(reset: reset, seed: seed, onboarding: onboarding);
}

final RegExp _emulatorFatal = RegExp(
  r'PANIC:|ERROR\s+\||emulator: ERROR|Could not launch|already running|'
  r'is already in use|hypervisor|WHPX|HAXM|Failed to|Address already in use',
);

final RegExp _emulatorChatter = RegExp(r'^(?:INFO|WARNING|VERBOSE|DEBUG)\s*\|');

/// The line that says a just-started emulator is not going to come up.
///
/// Without it `boot` waits out its whole six minutes on a failure the
/// emulator announced in its first second. Lines the emulator itself files
/// as INFO or WARNING never count: `WARNING | Failed to process .ini file`
/// is routine on a fresh machine and the guest boots fine behind it.
String? emulatorFatalLine(String logText) {
  for (final raw in logText.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || _emulatorChatter.hasMatch(line)) continue;
    if (_emulatorFatal.hasMatch(line)) return line;
  }
  return null;
}

/// Log lines that look like errors but are not the app's fault.
/// Firebase with no signed-in user logs two lines, not one — the "Exception
/// encountered" header and the "decryption failed" body — so the whole tag is
/// the pattern.
final List<RegExp> knownNoisePatterns = [
  RegExp('FirebearStorageCryptoHelper'),
];

/// Whether a line is one of the errors that is always there and never means
/// anything — Firebase with no signed-in user, so far.
bool isKnownNoise(String line) =>
    knownNoisePatterns.any((pattern) => pattern.hasMatch(line));

/// Splits error hits into the ones worth reading and the ones that are noise.
(List<String>, List<String>) partitionKnownNoise(List<String> hits) {
  final real = <String>[];
  final noise = <String>[];
  for (final hit in hits) {
    (isKnownNoise(hit) ? noise : real).add(hit);
  }
  return (real, noise);
}

final RegExp _logcatNoise = RegExp(
  r'flutter|anta|AndroidRuntime|FATAL|^\s*E/|\bE\s+\w',
  caseSensitive: false,
);

/// Keeps the logcat lines worth reading for a Flutter app.
List<String> filterLogcat(List<String> lines) =>
    lines.where((line) => _logcatNoise.hasMatch(line)).toList();

extension _Last<T> on Iterable<T> {
  T? get lastOrNull {
    T? found;
    for (final item in this) {
      found = item;
    }
    return found;
  }
}

final RegExp _appVmServiceLine = RegExp(
  r'(?:Dart VM [Ss]ervice is listening on|VM Service is available at:?)\s*((?:http|ws)s?://\S+)',
);

/// The last VM service URI an app announced in a device log, for driving an
/// app that was started outside this tool (an IDE run, a tap on the icon).
String? vmServiceUriFromLog(String logText) {
  String? found;
  for (final match in _appVmServiceLine.allMatches(logText)) {
    var uri = match.group(1)!.trim();
    while (uri.isNotEmpty && (uri.endsWith('.') || uri.endsWith(','))) {
      uri = uri.substring(0, uri.length - 1);
    }
    if (uri.isNotEmpty) found = uri;
  }
  return found;
}

final RegExp _hotReloadDone = RegExp(
  r'Reloaded \d+ (?:of \d+ )?librar|Restarted application|Hot restart performed',
);

final RegExp _hotReloadFailed = RegExp(
  r'Hot reload rejected|Hot reload was rejected|Try again after fixing|'
  r'^\S+\.dart:\d+:\d+: Error: |Unable to hot reload|Compilation error|Hot restart failed',
);

/// What the run log appended after a hot reload or restart was requested:
/// the line that says it finished, the line that says it failed, or null
/// while it is still going.
(bool ok, String line)? hotReloadOutcome(String appendedText) {
  for (final raw in appendedText.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_hotReloadFailed.hasMatch(line)) return (false, line);
    if (_hotReloadDone.hasMatch(line)) return (true, line);
  }
  return null;
}

final List<(RegExp, String)> _secretPatterns = [
  (RegExp(r'AIza[0-9A-Za-z_-]{20,}'), 'AIza…[redacted-api-key]'),
  (RegExp(r'[0-9]{6,}-[0-9a-z]{16,}\.apps\.googleusercontent\.com'),
      '[redacted-oauth-client].apps.googleusercontent.com'),
  (RegExp(r'\b1:[0-9]{6,}:(android|ios|web):[0-9a-f]{8,}'), '[redacted-firebase-app-id]'),
  (RegExp(r'ya29\.[0-9A-Za-z_-]{10,}'), '[redacted-oauth-token]'),
  (RegExp(r'eyJ[0-9A-Za-z_-]{8,}\.[0-9A-Za-z_-]{8,}\.[0-9A-Za-z_-]{8,}'), '[redacted-jwt]'),
  (RegExp(r'(bearer|authorization:?)\s+[0-9A-Za-z._~+/=-]{16,}', caseSensitive: false),
      '[redacted-credential]'),
  (RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'),
      '[redacted-private-key]'),
  (RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '[redacted-email]'),
];

/// Masks credentials and personal identifiers in text the tool is about to
/// print. Everything this tool prints ends up in an agent's transcript, so a
/// log line is the one place a key or an address could leave the machine.
String redactSecrets(String text) {
  var out = text;
  for (final (pattern, replacement) in _secretPatterns) {
    out = out.replaceAll(pattern, replacement);
  }
  return out;
}
