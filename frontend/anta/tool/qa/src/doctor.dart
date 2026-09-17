import 'adb.dart';
import 'device.dart';

/// How a single check came out.
enum CheckStatus { ok, warn, fail }

/// One line of `qa doctor`: what was checked, how it went, and what to do.
class CheckResult {
  const CheckResult({
    required this.name,
    required this.status,
    required this.detail,
    this.fix,
    this.fixVerb,
  });

  const CheckResult.ok(this.name, this.detail)
      : status = CheckStatus.ok,
        fix = null,
        fixVerb = null;

  final String name;
  final CheckStatus status;
  final String detail;

  /// One line telling the reader how to make this check pass.
  final String? fix;

  /// The `--fix` action this check knows how to run itself.
  final DoctorFix? fixVerb;

  String get label => switch (status) {
        CheckStatus.ok => 'ok  ',
        CheckStatus.warn => 'warn',
        CheckStatus.fail => 'FAIL',
      };

  String describe() {
    final line = '$label  ${name.padRight(22)}  $detail';
    return fix == null ? line : '$line\n      → $fix';
  }

  Map<String, Object?> toJson() => {
        'check': name,
        'status': status.name,
        'detail': detail,
        'fix': fix,
      };
}

/// Repairs `doctor --fix` is allowed to attempt.
///
/// Nothing here restarts the emulator, force-stops the app or touches app
/// data; those are the owner's calls and the harness never makes them.
enum DoctorFix { wake, unphone, killUiautomator, deleteRunPid, reapServices }

/// Whether any check failed outright, which is what decides the exit code.
bool anyFailed(List<CheckResult> results) =>
    results.any((r) => r.status == CheckStatus.fail);

/// adb was located and its server answered.
CheckResult checkAdbServer({
  required String? adbPath,
  required String? failure,
  required int? deviceCount,
}) {
  if (adbPath == null) {
    return const CheckResult(
      name: 'adb binary',
      status: CheckStatus.fail,
      detail: 'not found',
      fix: 'put adb on PATH or set ANDROID_HOME / ANDROID_SDK_ROOT',
    );
  }
  if (failure != null) {
    return CheckResult(
      name: 'adb server',
      status: CheckStatus.fail,
      detail: failure,
      fix: '`adb kill-server` then retry',
    );
  }
  return CheckResult.ok(
    'adb server',
    '$adbPath answered (${deviceCount ?? 0} device row(s))',
  );
}

/// A usable device is attached.
CheckResult checkDeviceAttached(List<AdbDevice> devices) {
  final usable = devices.where((d) => d.usable).toList();
  if (usable.isNotEmpty) {
    return CheckResult.ok(
      'device',
      usable.map((d) => '${d.serial} (${d.state})').join(', '),
    );
  }
  if (devices.isEmpty) {
    return const CheckResult(
      name: 'device',
      status: CheckStatus.fail,
      detail: 'nothing attached',
      fix: 'run `qa boot`',
    );
  }
  return CheckResult(
    name: 'device',
    status: CheckStatus.fail,
    detail: devices.map((d) => '${d.serial} ${d.state}').join(', '),
    fix: unusableDeviceMessage(devices.first.serial, devices.first.state),
  );
}

/// The guest finished booting and finished setup.
CheckResult checkBootProps({
  required String bootCompleted,
  required String provisioned,
}) {
  final booted = bootCompleted.trim() == '1';
  final setUp = provisioned.trim() == '1';
  if (booted && setUp) {
    return const CheckResult.ok('boot', 'boot_completed=1 provisioned=1');
  }
  return CheckResult(
    name: 'boot',
    status: CheckStatus.fail,
    detail: 'boot_completed=${bootCompleted.trim().isEmpty ? '?' : bootCompleted.trim()} '
        'provisioned=${provisioned.trim().isEmpty ? '?' : provisioned.trim()}',
    fix: 'the guest is still coming up — wait, or `qa boot`',
  );
}

/// The screen is on and the keyguard is down.
CheckResult checkAwake(DeviceProbe probe) {
  final awake = probe.awake ?? false;
  final locked = probe.locked ?? false;
  if (awake && !locked) {
    return const CheckResult.ok('awake', 'awake=yes locked=no');
  }
  return CheckResult(
    name: 'awake',
    status: CheckStatus.fail,
    detail: 'awake=${DeviceProbe.flag(probe.awake, 'yes', 'no')} '
        'locked=${DeviceProbe.flag(probe.locked, 'yes', 'no')}',
    fix: 'run `qa wake`',
    fixVerb: DoctorFix.wake,
  );
}

/// No `wm size` override is left in force from a `boot --phone`.
CheckResult checkScreenOverride(DeviceProbe probe) {
  final screen = probe.screen;
  if (screen == null) {
    return const CheckResult(
      name: 'screen',
      status: CheckStatus.warn,
      detail: 'unknown (the device did not report it)',
    );
  }
  if (!screen.isOverridden) {
    return CheckResult.ok('screen', screen.toString());
  }
  return CheckResult(
    name: 'screen',
    status: CheckStatus.warn,
    detail: screen.toString(),
    fix: 'run `qa unphone` to drop the override',
    fixVerb: DoctorFix.unphone,
  );
}

/// The app is installed and `run-as` works, which is what marker delivery
/// needs.
CheckResult checkAppInstalled({
  required String pmPath,
  required String runAsId,
}) {
  if (!pmPath.contains('package:')) {
    return const CheckResult(
      name: 'app installed',
      status: CheckStatus.fail,
      detail: 'pm path is empty',
      fix: 'run `qa run`',
    );
  }
  if (!runAsId.contains('uid=')) {
    return CheckResult(
      name: 'app installed',
      status: CheckStatus.fail,
      detail: 'installed, but `run-as` refused: ${runAsId.trim()}',
      fix: 'the installed build is not debuggable — run `qa run`',
    );
  }
  return const CheckResult.ok(
    'app installed',
    'apk present and run-as works (debug build)',
  );
}

/// The app process is alive and on top — by the resumed activity on
/// Android, by the app's own lifecycle state where the agent reported one.
CheckResult checkAppRunning(DeviceProbe probe, String packageId) {
  if (probe.appPid == null) {
    return const CheckResult(
      name: 'app running',
      status: CheckStatus.warn,
      detail: 'no process',
      fix: 'run `qa relaunch` (fast) or `qa run` (with DTD)',
    );
  }
  final lifecycle = probe.lifecycle;
  if (lifecycle != null) {
    if (lifecycle != 'resumed') {
      return CheckResult(
        name: 'app running',
        status: CheckStatus.warn,
        detail: 'pid ${probe.appPid}, lifecycle $lifecycle',
        fix: 'run `qa launch` to bring it back to the front',
      );
    }
    return CheckResult.ok('app running', 'pid ${probe.appPid}, lifecycle resumed');
  }
  final foreground = probe.foregroundPackage;
  if (probe.resumedActivity == null && probe.awake != null && foreground == null) {
    return CheckResult.ok('app running', 'pid ${probe.appPid}');
  }
  if (foreground != packageId) {
    return CheckResult(
      name: 'app running',
      status: CheckStatus.warn,
      detail: 'pid ${probe.appPid}, but the foreground is '
          '${foreground ?? 'unknown'}',
      fix: 'run `qa launch` to bring it back to the front',
    );
  }
  return CheckResult.ok(
    'app running',
    'pid ${probe.appPid}, resumed ${probe.resumedActivity}',
  );
}

/// `uiautomator dump` answers, and nothing is squatting on the service.
CheckResult checkUiautomator({
  required bool dumped,
  required Duration took,
  required String leftoverPids,
}) {
  final stale = leftoverPids.trim();
  if (!dumped) {
    return CheckResult(
      name: 'uiautomator',
      status: CheckStatus.fail,
      detail: stale.isEmpty
          ? 'dump failed after ${took.inMilliseconds} ms'
          : 'dump failed; leftover process $stale',
      fix: stale.isEmpty
          ? 'the screen may still be animating — retry'
          : 'kill the leftover: `qa doctor --fix`',
      fixVerb: stale.isEmpty ? null : DoctorFix.killUiautomator,
    );
  }
  if (stale.isNotEmpty) {
    return CheckResult(
      name: 'uiautomator',
      status: CheckStatus.warn,
      detail: 'dump ok in ${took.inMilliseconds} ms, but a uiautomator '
          'process is still registered ($stale)',
      fix: 'kill the leftover: `qa doctor --fix`',
      fixVerb: DoctorFix.killUiautomator,
    );
  }
  return CheckResult.ok('uiautomator', 'dump ok in ${took.inMilliseconds} ms');
}

/// Free space on `/data`, which cannot be grown in place on this AVD.
CheckResult checkDataSpace(String dfOutput) {
  final match = RegExp(r'\s(\d+)\s+(\d+)\s+(\d+)\s+\d+%').firstMatch(dfOutput);
  if (match == null) {
    return CheckResult(
      name: '/data space',
      status: CheckStatus.warn,
      detail: 'could not read `df /data`: ${dfOutput.trim()}',
    );
  }
  final freeMb = int.parse(match.group(3)!) ~/ 1024;
  if (freeMb >= 500) {
    return CheckResult.ok('/data space', '$freeMb MB free');
  }
  return CheckResult(
    name: '/data space',
    status: CheckStatus.warn,
    detail: '$freeMb MB free',
    fix: 'the AVD data partition cannot grow in place — wipe and restore, see '
        'the storage note in the qa-emulator skill',
  );
}

/// The host side: a stale `run.pid`, and orphaned development services.
CheckResult checkHostRun({
  required int? recordedPid,
  required bool pidAlive,
  required List<int> orphanedServices,
}) {
  final problems = <String>[];
  DoctorFix? fix;
  if (recordedPid != null && !pidAlive) {
    problems.add('run.pid names $recordedPid, which is gone');
    fix = DoctorFix.deleteRunPid;
  }
  if (orphanedServices.isNotEmpty) {
    problems.add(
      'orphaned dart development-service: ${orphanedServices.join(', ')}',
    );
    fix = DoctorFix.reapServices;
  }
  if (problems.isEmpty) {
    return CheckResult.ok(
      'host run state',
      recordedPid == null ? 'no run.pid' : 'run.pid $recordedPid is alive',
    );
  }
  return CheckResult(
    name: 'host run state',
    status: CheckStatus.warn,
    detail: problems.join('; '),
    fix: 'run `qa doctor --fix`',
    fixVerb: fix,
  );
}

/// Whether the DTD URI on disk still belongs to a live run.
CheckResult checkDtd({required String dtd, required String runLogTail}) {
  if (dtd.trim().isEmpty) {
    return const CheckResult(
      name: 'dtd',
      status: CheckStatus.warn,
      detail: 'no URI recorded',
      fix: 'run `qa run` or `qa attach` when you need Driver',
    );
  }
  if (runLogTail.contains('Lost connection to device')) {
    return CheckResult(
      name: 'dtd',
      status: CheckStatus.warn,
      detail: '${dtd.trim()} — but run.log ends in "Lost connection to device"',
      fix: 'run `qa attach`',
    );
  }
  return CheckResult.ok('dtd', dtd.trim());
}

/// Whether the compiled tool matches the sources on disk.
CheckResult checkExeFreshness({
  required bool exists,
  required bool stale,
  required String? staleSource,
}) {
  if (!exists) {
    return const CheckResult(
      name: 'qa.exe',
      status: CheckStatus.warn,
      detail: 'not compiled yet',
      fix: 'run `qa build-exe` (the wrappers do it for you on first use)',
    );
  }
  if (!stale) return const CheckResult.ok('qa.exe', 'up to date');
  return CheckResult(
    name: 'qa.exe',
    status: CheckStatus.warn,
    detail: 'older than ${staleSource ?? 'the sources'}',
    fix: 'run `qa build-exe`',
  );
}

/// Xcode's command line tools are present, which is what every simulator
/// verb shells out to.
CheckResult checkXcrun({required bool available}) => available
    ? const CheckResult.ok('xcrun', '/usr/bin/xcrun present')
    : const CheckResult(
        name: 'xcrun',
        status: CheckStatus.fail,
        detail: '/usr/bin/xcrun missing',
        fix: 'install the Xcode command line tools: `xcode-select --install`',
      );

/// The chosen simulator is booted.
CheckResult checkSimulator({
  required String name,
  required String state,
  required String runtime,
}) {
  if (state == 'Booted') {
    return CheckResult.ok('simulator', '$name ($runtime) booted');
  }
  return CheckResult(
    name: 'simulator',
    status: CheckStatus.fail,
    detail: '$name is $state',
    fix: 'run `qa boot --sim "$name"`',
  );
}

/// The app bundle exists where the platform keeps it.
CheckResult checkAppBundle({
  required String? path,
  required String platform,
  required String fix,
}) {
  if (path == null) {
    return CheckResult(
      name: 'app installed',
      status: CheckStatus.fail,
      detail: 'no bundle for the $platform',
      fix: fix,
    );
  }
  return CheckResult.ok('app installed', path);
}

/// The in-app agent answered over the VM service.
CheckResult checkAgent({
  required String? vmUri,
  required String? failure,
  required int? roundTripMs,
  required String? summary,
  required bool? qaMode,
  bool? cloud,
}) {
  if (vmUri == null || vmUri.isEmpty) {
    return const CheckResult(
      name: 'agent',
      status: CheckStatus.warn,
      detail: 'no VM service URI recorded',
      fix: 'run `qa run` or `qa relaunch` — every verb on this platform goes '
          'through the agent',
    );
  }
  if (failure != null) {
    return CheckResult(
      name: 'agent',
      status: CheckStatus.fail,
      detail: failure,
      fix: 'run `qa relaunch` to start the driver build and record a fresh URI',
    );
  }
  if (qaMode == false) {
    return CheckResult(
      name: 'agent',
      status: CheckStatus.fail,
      detail: 'answered, but the app is NOT a QA build: $summary',
      fix: 'it is reading the owner database — restart with `qa run`',
    );
  }
  if (cloud == true) {
    return CheckResult(
      name: 'agent',
      status: CheckStatus.warn,
      detail: 'answered, and this QA build can reach Firebase: $summary',
      fix: 'it acts as whoever is signed in on this install — rebuild '
          'without ANTA_QA_CLOUD unless sync itself is under test',
    );
  }
  return CheckResult.ok(
    'agent',
    'answered in ${roundTripMs ?? 0} ms  ${summary ?? ''}'.trimRight(),
  );
}

/// Marker files still waiting in the documents directory. Not a failure —
/// the next QA launch consumes them — but a non-QA build ignores them, and
/// a forgotten seed silently replaces the next run's data.
CheckResult checkPendingMarkers(List<String> pending) {
  if (pending.isEmpty) return const CheckResult.ok('markers', 'none pending');
  return CheckResult(
    name: 'markers',
    status: CheckStatus.warn,
    detail: '${pending.join(', ')} pending in the documents directory',
    fix: 'the next QA launch applies them (a non-QA build ignores them); '
        '`qa relaunch` now, or delete them if they are stale',
  );
}
