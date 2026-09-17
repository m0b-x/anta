import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'process_runner.dart';

const String xcrunPath = '/usr/bin/xcrun';

bool xcrunAvailable({bool Function(String)? exists}) =>
    Platform.isMacOS && (exists ?? _fileExists)(xcrunPath);

bool _fileExists(String path) => File(path).existsSync();

class SimDevice {
  const SimDevice({
    required this.udid,
    required this.name,
    required this.state,
    required this.runtime,
    required this.isAvailable,
    this.dataPath,
  });

  final String udid;
  final String name;
  final String state;
  final String runtime;
  final bool isAvailable;
  final String? dataPath;

  bool get booted => state == 'Booted';

  bool get isIPhone => name.toLowerCase().startsWith('iphone');

  @override
  String toString() => '$udid  $state  $name ($runtime)';
}

String simRuntimeLabel(String identifier) {
  final last = identifier.split('.').last;
  final match = RegExp(r'^([A-Za-z]+)-(\d+)(?:-(\d+))?(?:-(\d+))?$').firstMatch(last);
  if (match == null) return last;
  final parts = [match.group(2), match.group(3), match.group(4)]
      .whereType<String>()
      .join('.');
  return '${match.group(1)} $parts';
}

List<SimDevice> parseSimctlDevices(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw DeviceFailure('simctl list devices returned no JSON: ${e.message}');
  }
  if (decoded is! Map || decoded['devices'] is! Map) {
    throw DeviceFailure('simctl list devices returned an unexpected shape');
  }
  final devices = <SimDevice>[];
  (decoded['devices'] as Map).forEach((runtime, list) {
    if (list is! List) return;
    for (final entry in list) {
      if (entry is! Map) continue;
      final udid = entry['udid'];
      if (udid is! String) continue;
      devices.add(SimDevice(
        udid: udid,
        name: '${entry['name'] ?? udid}',
        state: '${entry['state'] ?? 'unknown'}',
        runtime: simRuntimeLabel('$runtime'),
        isAvailable: entry['isAvailable'] == true,
        dataPath: entry['dataPath'] as String?,
      ));
    }
  });
  devices.sort((a, b) {
    if (a.booted != b.booted) return a.booted ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return devices;
}

int? parseSimctlLaunchPid(String output) {
  final match = RegExp(r':\s*(\d+)\s*$', multiLine: true).firstMatch(output.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? parseLaunchctlPid(String listOutput, String bundleId) {
  for (final line in listOutput.split('\n')) {
    if (!line.contains('UIKitApplication:$bundleId[')) continue;
    final pid = int.tryParse(line.trim().split(RegExp(r'\s+')).first);
    if (pid != null && pid > 0) return pid;
  }
  return null;
}

String iosLogPredicate(String executable) =>
    'processImagePath ENDSWITH "$executable" AND '
    '(senderImagePath ENDSWITH "/Flutter" OR eventMessage CONTAINS "flutter")';

class Simctl {
  Simctl({required this.runner, this.xcrun = xcrunPath});

  final ProcessRunner runner;
  final String xcrun;

  Future<RunOutcome> _run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
  }) =>
      runner.run(xcrun, ['simctl', ...args], timeout: timeout, binary: binary);

  Future<List<SimDevice>> devices({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final result = await _run(['list', 'devices', '--json'], timeout: timeout);
    if (!result.ok) {
      throw DeviceFailure('xcrun simctl list failed: ${result.combined}');
    }
    return parseSimctlDevices(result.stdout);
  }

  Future<void> boot(String udid) async {
    final result = await _run(['boot', udid], timeout: const Duration(seconds: 90));
    if (!result.ok && !result.combined.contains('current state: Booted')) {
      throw DeviceFailure('xcrun simctl boot $udid failed: ${result.combined}');
    }
  }

  Future<void> waitBooted(
    String udid, {
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final result = await _run(['bootstatus', udid, '-b'], timeout: timeout);
    if (!result.ok) {
      throw DeviceFailure(
        'the simulator $udid did not finish booting: ${result.combined}',
      );
    }
  }

  Future<void> openSimulatorApp(String udid) async {
    await runner.run(
      '/usr/bin/open',
      ['-a', 'Simulator', '--args', '-CurrentDeviceUDID', udid],
      timeout: const Duration(seconds: 30),
    );
  }

  Future<String?> appContainer(
    String udid,
    String bundleId,
    String kind,
  ) async {
    final result = await _run(['get_app_container', udid, bundleId, kind]);
    if (!result.ok) return null;
    final path = result.stdout.trim();
    return path.isEmpty ? null : path;
  }

  Future<int?> launch(
    String udid,
    String bundleId, {
    List<String> appArguments = const [],
    bool terminateRunning = true,
  }) async {
    final result = await _run(
      [
        'launch',
        if (terminateRunning) '--terminate-running-process',
        udid,
        bundleId,
        ...appArguments,
      ],
      timeout: const Duration(seconds: 90),
    );
    if (!result.ok) {
      throw DeviceFailure(
        'xcrun simctl launch $bundleId failed: ${result.combined}',
      );
    }
    return parseSimctlLaunchPid(result.stdout);
  }

  Future<void> terminate(String udid, String bundleId) async {
    await _run(['terminate', udid, bundleId], timeout: const Duration(seconds: 30));
  }

  Future<List<int>> screenshotPng(String udid) async {
    final result = await _run(
      ['io', udid, 'screenshot', '--type=png', '-'],
      timeout: const Duration(seconds: 30),
      binary: true,
    );
    if (!result.ok) {
      throw DeviceFailure('xcrun simctl io screenshot failed: ${result.stderr}');
    }
    return result.bytes ?? const [];
  }

  Future<String> launchctlList(String udid) async {
    final result = await _run(['spawn', udid, 'launchctl', 'list']);
    return result.ok ? result.stdout : '';
  }

  Future<String> logShow(
    String udid, {
    required String predicate,
    Duration last = const Duration(minutes: 5),
  }) async {
    final minutes = last.inMinutes < 1 ? 1 : last.inMinutes;
    final result = await _run(
      [
        'spawn',
        udid,
        'log',
        'show',
        '--last',
        '${minutes}m',
        '--info',
        '--debug',
        '--style',
        'compact',
        '--predicate',
        predicate,
      ],
      timeout: const Duration(seconds: 90),
    );
    return result.ok ? result.stdout : result.combined;
  }
}
