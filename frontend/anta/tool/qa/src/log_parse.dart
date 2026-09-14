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
