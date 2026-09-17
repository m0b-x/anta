import 'dart:io';

import 'agent_client.dart';
import 'app_ids.dart';
import 'device.dart';
import 'device_select.dart';
import 'errors.dart';
import 'markers.dart';
import 'paths.dart';
import 'poll.dart';
import 'process_runner.dart';
import 'runner.dart';
import 'vm_service_client.dart';

/// The value of `KEY = value` in an xcconfig, or null when the key is absent.
String? parseXcconfigValue(String text, String key) {
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('//') || !line.startsWith(key)) continue;
    final match = RegExp('^${RegExp.escape(key)}\\s*=\\s*(.*)\$').firstMatch(line);
    if (match != null) return match.group(1)!.trim();
  }
  return null;
}

/// Pids from `ps -axo pid=,comm=` whose command is [executable].
List<int> parsePsPids(String output, String executable) {
  final pids = <int>[];
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final space = line.indexOf(RegExp(r'\s'));
    if (space == -1) continue;
    final pid = int.tryParse(line.substring(0, space));
    final command = line.substring(space).trim();
    if (pid == null || command != executable) continue;
    pids.add(pid);
  }
  return pids;
}

/// The default sandbox container documents folder for a bundle id.
String macosContainerDocuments(String home, String bundleId) => [
      home,
      'Library',
      'Containers',
      bundleId,
      'Data',
      'Documents',
    ].join(Platform.pathSeparator);

/// The desktop app: a host process, so the tool starts it, signals it and
/// reads its stdout directly; screenshots and input come from the agent.
class MacosDevice implements Device {
  MacosDevice({
    required this.paths,
    required this.runner,
    required this.productName,
    this.packageId = antaBundleId,
    Map<String, String>? environment,
  }) : _env = environment ?? Platform.environment;

  factory MacosDevice.locate({
    required QaPaths paths,
    required ProcessRunner runner,
  }) {
    final xcconfig = File(paths.macosAppInfo);
    final name = xcconfig.existsSync()
        ? parseXcconfigValue(xcconfig.readAsStringSync(), 'PRODUCT_NAME')
        : null;
    return MacosDevice(
      paths: paths,
      runner: runner,
      productName: name == null || name.isEmpty ? macosDefaultProductName : name,
    );
  }

  final QaPaths paths;
  final ProcessRunner runner;
  final String productName;
  final Map<String, String> _env;

  @override
  final String packageId;

  @override
  DeviceKind get kind => DeviceKind.macos;

  @override
  String get id => macosDeviceId;

  @override
  String get label => 'macOS desktop ($productName.app)';

  @override
  String get installHint => 'run `qa run -d macos`';

  @override
  String get logName => paths.appLog;

  @override
  bool get hasNativeCapture => false;

  String get bundlePath => paths.macosBundle(productName);

  String get executablePath =>
      [bundlePath, 'Contents', 'MacOS', productName].join(Platform.pathSeparator);

  @override
  Future<bool> isInstalled() async => File(executablePath).existsSync();

  Future<List<int>> appPids() async {
    final result = await runner.run(
      '/bin/ps',
      ['-axo', 'pid=,comm='],
      timeout: const Duration(seconds: 15),
    );
    return parsePsPids(result.stdout, executablePath);
  }

  @override
  Future<int?> appPid() async {
    final pids = await appPids();
    return pids.isEmpty ? null : pids.first;
  }

  @override
  Future<void> forceStop() async {
    final pids = await appPids();
    if (pids.isEmpty) return;
    for (final pid in pids) {
      await runner.run('/bin/kill', ['-TERM', '$pid'], timeout: const Duration(seconds: 10));
    }
    final gone = await pollUntil<bool>(
      timeout: const Duration(seconds: 4),
      interval: const Duration(milliseconds: 200),
      probe: () async {
        for (final pid in pids) {
          if (await isProcessAlive(pid, runner)) return null;
        }
        return true;
      },
    );
    if (gone == true) return;
    for (final pid in pids) {
      await runner.run('/bin/kill', ['-KILL', '$pid'], timeout: const Duration(seconds: 10));
    }
  }

  @override
  Future<AppLaunch> launchApp({required int vmServicePort}) async {
    if (!await isInstalled()) {
      throw DeviceFailure(
        '$bundlePath is not built — $installHint (a `flutter run -d macos` '
        'builds it; `flutter build macos --debug -t $driverTarget` also works)',
      );
    }
    paths.ensureBuildQa();
    File(paths.appLog).writeAsStringSync('');
    File(paths.appErr).writeAsStringSync('');
    final wrapper = writeWrapperScript(
      paths: paths,
      baseName: 'app_cmd',
      executable: executablePath,
      arguments: const [],
      posixLogPath: paths.appLog,
      environment: desktopEngineEnvironment(vmServicePort),
    );
    final pid = await startWrapperDetached(
      paths: paths,
      wrapper: wrapper,
      logPath: paths.appLog,
      errPath: paths.appErr,
      pidPath: paths.appPid,
    );
    return AppLaunch(
      pid: pid,
      vmServiceUri: vmServiceHttpUri('127.0.0.1', vmServicePort),
      description: '$executablePath (vm-service-port $vmServicePort, log '
          '${paths.appLog})',
    );
  }

  @override
  Future<void> bringToFront() async {
    await runner.run('/usr/bin/open', [bundlePath], timeout: const Duration(seconds: 30));
  }

  /// Where the app keeps its documents: what the agent last reported, else
  /// the sandbox container the entitlements imply.
  Future<String> documentsDir() async {
    final cache = File(paths.documentsCache(id));
    if (cache.existsSync()) {
      final cached = cache.readAsStringSync().trim();
      if (cached.isNotEmpty) return cached;
    }
    final home = _env['HOME'] ?? '';
    if (home.isEmpty) throw DeviceFailure('HOME is not set');
    return macosContainerDocuments(home, packageId);
  }

  @override
  Future<void> dropResetMarker() async =>
      dropResetMarkerAt(await documentsDir(), mustExist: true);

  @override
  Future<void> pushSeed(String localPath) async =>
      pushSeedTo(await documentsDir(), localPath, mustExist: true);

  @override
  Future<List<int>> screencapPng() => throw UnsupportedOnPlatform(
        'a native screenshot',
        'the macOS desktop app',
        instead: 'the agent renders the Flutter view instead, which `shot` '
            'does by default here',
      );

  @override
  Future<String> readLog({String? sinceStamp}) async =>
      readLogPair(paths.appLog, paths.appErr);

  @override
  Future<String> qaLogText({String? stamp}) async =>
      readLogPair(paths.appLog, paths.appErr);

  @override
  Future<String?> discoverVmServiceUri() async => null;

  @override
  Future<List<String>> pendingMarkers() async =>
      pendingMarkersAt(await documentsDir());

  @override
  UiDriver? get nativeDriver => null;

  @override
  Future<DeviceProbe> probe([AgentInfo? agent]) async => agentProbe(
        pid: await appPid(),
        agent: agent,
        packageId: packageId,
        awake: true,
        locked: false,
      );
}
