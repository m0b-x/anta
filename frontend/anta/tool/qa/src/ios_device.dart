import 'dart:io';

import 'agent_client.dart';
import 'app_ids.dart';
import 'device.dart';
import 'errors.dart';
import 'log_parse.dart';
import 'markers.dart';
import 'runner.dart';
import 'simctl.dart';
import 'vm_service_client.dart';

/// An iOS simulator, driven through `xcrun simctl` for process control and
/// screenshots and through the in-app agent for everything else.
class IosDevice implements Device {
  IosDevice({
    required this.simctl,
    required this.sim,
    this.packageId = antaBundleId,
    this.executableName = iosExecutableName,
  });

  final Simctl simctl;
  final SimDevice sim;

  @override
  final String packageId;

  final String executableName;

  String? _appPath;
  String? _dataPath;

  @override
  DeviceKind get kind => DeviceKind.ios;

  @override
  String get id => sim.udid;

  @override
  String get label => '${sim.name} (${sim.runtime})';

  @override
  String get installHint => 'run `qa run -d ${sim.udid}`';

  @override
  String get logName => 'simulator log';

  @override
  bool get hasNativeCapture => true;

  Future<String?> appPath() async =>
      _appPath ??= await simctl.appContainer(sim.udid, packageId, 'app');

  Future<String?> dataPath() async =>
      _dataPath ??= await simctl.appContainer(sim.udid, packageId, 'data');

  /// The app's Documents directory on the host filesystem — the simulator's
  /// data container is a plain folder, so markers are ordinary file writes.
  Future<String> documentsDir() async {
    final data = await dataPath();
    if (data == null) {
      throw DeviceFailure(
        '$packageId is not installed on ${sim.name} — $installHint',
      );
    }
    return '$data${Platform.pathSeparator}Documents';
  }

  @override
  Future<bool> isInstalled() async => await appPath() != null;

  @override
  Future<int?> appPid() async =>
      parseLaunchctlPid(await simctl.launchctlList(sim.udid), packageId);

  @override
  Future<void> forceStop() async {
    await simctl.terminate(sim.udid, packageId);
    await awaitStopped(appPid);
  }

  @override
  Future<AppLaunch> launchApp({required int vmServicePort}) async {
    final pid = await simctl.launch(
      sim.udid,
      packageId,
      appArguments: iosLaunchArguments(vmServicePort),
    );
    return AppLaunch(
      pid: pid,
      vmServiceUri: vmServiceHttpUri('127.0.0.1', vmServicePort),
      description: 'xcrun simctl launch $packageId '
          '(vm-service-port $vmServicePort)',
    );
  }

  @override
  Future<void> bringToFront() =>
      simctl.launch(sim.udid, packageId, terminateRunning: false);

  @override
  Future<void> dropResetMarker() async =>
      dropResetMarkerAt(await documentsDir());

  @override
  Future<void> pushSeed(String localPath) async =>
      pushSeedTo(await documentsDir(), localPath);

  @override
  Future<List<int>> screencapPng() => simctl.screenshotPng(sim.udid);

  @override
  Future<String> readLog({String? sinceStamp}) => simctl.logShow(
        sim.udid,
        predicate: iosLogPredicate(executableName),
        last: const Duration(minutes: 10),
      );

  /// Scoped to the running process where there is one, so a previous
  /// launch's `[qa]` lines cannot be mistaken for this one's.
  @override
  Future<String> qaLogText({String? stamp}) async {
    final pid = await appPid();
    return simctl.logShow(
      sim.udid,
      predicate: pid == null
          ? iosLogPredicate(executableName)
          : 'processID == $pid AND (${iosLogPredicate(executableName)})',
      last: const Duration(minutes: 5),
    );
  }

  @override
  Future<String?> discoverVmServiceUri() async {
    if (await appPid() == null) return null;
    final log = await simctl.logShow(
      sim.udid,
      predicate: 'processImagePath ENDSWITH "$executableName" AND '
          'eventMessage CONTAINS "VM"',
      last: const Duration(minutes: 30),
    );
    return vmServiceUriFromLog(log);
  }

  @override
  Future<List<String>> pendingMarkers() async {
    if (await dataPath() == null) return const [];
    return pendingMarkersAt(await documentsDir());
  }

  @override
  UiDriver? get nativeDriver => null;

  @override
  Future<DeviceProbe> probe([AgentInfo? agent]) async => agentProbe(
        pid: await appPid(),
        agent: agent,
        packageId: packageId,
        awake: sim.booted,
      );
}

/// Width and height from a PNG header, without decoding the image.
(int, int)? pngSize(List<int> bytes) {
  if (bytes.length < 24) return null;
  if (bytes[0] != 0x89 || bytes[1] != 0x50 || bytes[2] != 0x4E || bytes[3] != 0x47) {
    return null;
  }
  int read(int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
  return (read(16), read(20));
}
