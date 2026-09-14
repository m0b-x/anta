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

/// The line that says a just-started emulator is not going to come up.
///
/// Without it `boot` waits out its whole six minutes on a failure the
/// emulator announced in its first second.
String? emulatorFatalLine(String logText) =>
    _firstMatching(logText, _emulatorFatal);

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
