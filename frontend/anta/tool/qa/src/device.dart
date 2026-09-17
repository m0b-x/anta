import 'adb.dart';
import 'agent_client.dart';
import 'app_ids.dart';
import 'device_select.dart';
import 'errors.dart';
import 'gestures.dart';
import 'input_text.dart';
import 'log_parse.dart';
import 'markers.dart' as markers;
import 'poll.dart';
import 'runner.dart';
import 'shell_batch.dart';
import 'ui_tree.dart';

export 'device_select.dart' show DeviceKind, DeviceKindLabel;

/// Physical screen size in pixels, plus any `wm size` override in force.
class ScreenSize {
  const ScreenSize({
    required this.physicalWidth,
    required this.physicalHeight,
    required this.density,
    this.overrideWidth,
    this.overrideHeight,
  });

  final int physicalWidth;
  final int physicalHeight;
  final int density;
  final int? overrideWidth;
  final int? overrideHeight;

  int get width => overrideWidth ?? physicalWidth;

  int get height => overrideHeight ?? physicalHeight;

  bool get isOverridden => overrideWidth != null;

  int get widthDp => (width * 160 / density).round();

  int get heightDp => (height * 160 / density).round();

  @override
  String toString() {
    final base = '${width}x$height @${density}dpi ($widthDp x $heightDp dp)';
    return isOverridden ? '$base [override of ${physicalWidth}x$physicalHeight]' : base;
  }
}

/// Everything one batched device probe answers at once.
///
/// Each field is null when the device did not report it, which is different
/// from "reported false": an Android image that words a `dumpsys` line
/// differently should read as unknown, not as locked.
class DeviceProbe {
  const DeviceProbe({
    this.screen,
    this.appPid,
    this.resumedActivity,
    this.awake,
    this.locked,
    this.imeShown,
    this.lifecycle,
  });

  /// Null when nothing could report it — an agent platform with the app down.
  final ScreenSize? screen;
  final int? appPid;
  final String? resumedActivity;
  final bool? awake;
  final bool? locked;
  final bool? imeShown;

  /// The app's own `AppLifecycleState`, when the agent could be asked.
  final String? lifecycle;

  /// The package half of the resumed activity component.
  String? get foregroundPackage {
    final activity = resumedActivity;
    if (activity == null) return null;
    final slash = activity.indexOf('/');
    return slash <= 0 ? activity : activity.substring(0, slash);
  }

  static String flag(bool? value, String yes, String no) =>
      value == null ? '?' : (value ? yes : no);
}

/// The probe an agent-driven platform reports: the process from the
/// platform, everything else from the app itself when it answered.
DeviceProbe agentProbe({
  required int? pid,
  required AgentInfo? agent,
  required String packageId,
  bool? awake,
  bool? locked,
}) =>
    DeviceProbe(
      screen: agent?.screen,
      appPid: pid,
      resumedActivity:
          pid != null && agent?.lifecycle == 'resumed' ? packageId : null,
      awake: awake,
      locked: locked,
      imeShown: agent?.textClient,
      lifecycle: agent?.lifecycle,
    );

/// Waits until [pid] reports nothing, for a stop that must be over before a
/// launch races it.
Future<bool> awaitStopped(
  Future<int?> Function() pid, {
  Duration timeout = const Duration(seconds: 6),
}) async =>
    await pollUntil<bool>(
      timeout: timeout,
      interval: const Duration(milliseconds: 150),
      probe: () async => await pid() == null ? true : null,
    ) ??
    false;

/// Reads `wm size` and `wm density` output into a [ScreenSize].
ScreenSize parseScreenSize(String sizeOutput, String densityOutput) {
  final physical = _matchSize(sizeOutput, 'Physical size');
  final override = _matchSize(sizeOutput, 'Override size');
  if (physical == null) {
    throw DeviceFailure('could not read `wm size` output: $sizeOutput');
  }
  final dpi = RegExp(r'Physical density:\s*(\d+)').firstMatch(densityOutput);
  return ScreenSize(
    physicalWidth: physical.$1,
    physicalHeight: physical.$2,
    density: dpi == null ? 160 : int.parse(dpi.group(1)!),
    overrideWidth: override?.$1,
    overrideHeight: override?.$2,
  );
}

(int, int)? _matchSize(String output, String label) {
  final match = RegExp('$label:\\s*(\\d+)x(\\d+)').firstMatch(output);
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// Finds a `uiautomator` that is registered but should not be.
///
/// The bracket is load-bearing: `adb shell pgrep -f uiautomator` matches the
/// very shell that is running it, so the plain form always reports a leftover
/// and never means anything. `[u]iautomator` is a regex that matches the real
/// process and not the literal text in this command line.
const String leftoverUiautomatorProbe = "pgrep -f '[u]iautomator' || true";

/// Kills that leftover, with the same bracket for the same reason.
const String killLeftoverUiautomator = "pkill -f '[u]iautomator' || true";

/// The commands [parseDeviceProbe] expects, in order.
///
/// The `dumpsys` reads are piped into the device's own `grep` so only one line
/// crosses the adb connection instead of the whole service dump, and stderr is
/// dropped because `dumpsys` complains loudly when `grep -m1` closes the pipe
/// on it.
List<ShellCommand> deviceProbeCommands(String packageId) => [
      const ShellCommand(['wm', 'size']),
      const ShellCommand(['wm', 'density']),
      ShellCommand(['pidof', packageId]),
      const ShellCommand.raw(
        'dumpsys activity activities 2>/dev/null | '
        "grep -m1 -E 'mResumedActivity|topResumedActivity'",
      ),
      const ShellCommand.raw(
        'dumpsys power 2>/dev/null | grep -m1 mWakefulness',
      ),
      const ShellCommand.raw(
        'dumpsys window 2>/dev/null | grep -m1 isKeyguardShowing',
      ),
      const ShellCommand.raw(
        'dumpsys input_method 2>/dev/null | grep -m1 mInputShown',
      ),
    ];

/// Turns the seven probe outputs into one [DeviceProbe].
DeviceProbe parseDeviceProbe(List<String> outputs) {
  String at(int index) => index < outputs.length ? outputs[index] : '';
  return DeviceProbe(
    screen: parseScreenSize(at(0), at(1)),
    appPid: int.tryParse(at(2).trim().split(RegExp(r'\s+')).first),
    resumedActivity: parseResumedActivity(at(3)),
    awake: _boolFrom(at(4), RegExp(r'mWakefulness=(\w+)'), 'Awake'),
    locked: _boolFrom(at(5), RegExp(r'isKeyguardShowing=(\w+)'), 'true'),
    imeShown: _boolFrom(at(6), RegExp(r'mInputShown=(\w+)'), 'true'),
  );
}

/// The `package/.Activity` component named by a `dumpsys activity` line.
String? parseResumedActivity(String line) {
  final match = RegExp(r'([A-Za-z0-9_.]+/[A-Za-z0-9_.]+)').firstMatch(line);
  return match?.group(1);
}

bool? _boolFrom(String output, RegExp pattern, String trueValue) {
  final match = pattern.firstMatch(output);
  if (match == null) return null;
  return match.group(1) == trueValue;
}

/// Which see-and-act layer the verbs use: `auto` is the native one where a
/// platform has it (adb on Android) and the agent everywhere else.
enum ViaMode { auto, agent, native }

ViaMode parseViaMode(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
      '' || 'auto' => ViaMode.auto,
      'agent' => ViaMode.agent,
      'native' || 'adb' => ViaMode.native,
      _ => throw UsageFailure(
          '--via must be auto, agent or native (got "$raw")',
        ),
    };

/// One accessibility capture: the raw text that goes into the cache and the
/// tree parsed from it.
class UiDump {
  const UiDump({required this.raw, required this.tree});

  final String raw;
  final UiTree tree;
}

/// What a `type` reported back, for the one-line summary and the warning.
class TypeOutcome {
  const TypeOutcome({this.imeShown, this.text, this.selection});

  final bool? imeShown;
  final String? text;
  final int? selection;
}

/// The see-and-act surface every verb drives: the Android accessibility
/// service over adb, or the in-app agent over the VM service.
abstract class UiDriver {
  String get name;

  Duration get pollInterval;

  /// How long an acting verb pauses before `--shot`/`--dump` when it did not
  /// `--wait`: zero for a layer whose ops already settle the frame.
  Duration get settleAfterAction;

  Future<ScreenSize> screenSize();

  Future<UiDump> dump();

  Future<void> tap(int x, int y);

  Future<void> longPress(int x, int y, int ms);

  Future<void> swipePath(SwipePath path);

  Future<void> drag(int x1, int y1, int x2, int y2, {required int holdMs, required int moveMs});

  Future<TypeOutcome> typeText(String text, {bool replace = false});

  Future<void> clear();

  Future<String> key(String name);
}

/// A started app process and where its VM service will answer.
class AppLaunch {
  const AppLaunch({
    required this.vmServiceUri,
    required this.description,
    this.pid,
  });

  final String vmServiceUri;
  final String description;
  final int? pid;
}

/// Platform plumbing for one attached device: process control, markers,
/// native screenshots and logs. Input goes through a [UiDriver].
abstract class Device {
  DeviceKind get kind;

  String get id;

  String get label;

  String get packageId;

  /// How the platform log is named in `errors` output.
  String get logName;

  /// Whether [screencapPng] exists here; otherwise the agent renders shots.
  bool get hasNativeCapture;

  Future<DeviceProbe> probe([AgentInfo? agent]);

  Future<bool> isInstalled();

  Future<int?> appPid();

  /// Stops the app and returns once its process is gone (or the wait ran out).
  Future<void> forceStop();

  Future<AppLaunch> launchApp({required int vmServicePort});

  Future<void> bringToFront();

  Future<void> dropResetMarker();

  Future<void> pushSeed(String localPath);

  Future<List<int>> screencapPng();

  Future<String> readLog({String? sinceStamp});

  Future<String> qaLogText({String? stamp});

  /// The VM service URI an app started outside this tool announced in the
  /// platform log, made reachable from the host; null when there is none.
  Future<String?> discoverVmServiceUri();

  /// Marker files waiting in the documents directory for the next QA launch.
  Future<List<String>> pendingMarkers();

  UiDriver? get nativeDriver;

  String get installHint;
}

class AndroidDevice implements Device {
  AndroidDevice(this.adb, {this.packageId = antaPackage});

  final Adb adb;

  @override
  final String packageId;

  @override
  DeviceKind get kind => DeviceKind.android;

  @override
  String get id => adb.serial ?? defaultSerial;

  @override
  String get label => 'Android $id';

  @override
  String get installHint => 'run `qa run`';

  @override
  String get logName => lastQaLogPid == null ? 'logcat' : 'logcat(pid $lastQaLogPid)';

  @override
  bool get hasNativeCapture => true;

  ScreenSize? _screenSize;

  /// One `adb shell` for both halves, then cached: the screen does not change
  /// under a single verb, and `scroll-to` used to ask for it once per swipe.
  Future<ScreenSize> screenSize() async {
    final cached = _screenSize;
    if (cached != null) return cached;
    final outputs = await adb.shellBatch(const [
      ShellCommand(['wm', 'size']),
      ShellCommand(['wm', 'density']),
    ]);
    return _screenSize = parseScreenSize(outputs[0], outputs[1]);
  }

  @override
  Future<DeviceProbe> probe([AgentInfo? agent]) async {
    final outputs = await adb.shellBatch(deviceProbeCommands(packageId));
    final probed = parseDeviceProbe(outputs);
    _screenSize ??= probed.screen;
    return probed;
  }

  Future<void> wake() async {
    await adb.shellBatch(const [
      ShellCommand(['input', 'keyevent', 'KEYCODE_WAKEUP']),
      ShellCommand(['wm', 'dismiss-keyguard']),
    ]);
  }

  Future<ScreenSize> resetScreenOverride() async {
    await adb.shellLenient(['wm', 'size', 'reset']);
    _screenSize = null;
    return screenSize();
  }

  /// Whether an IME is showing, for the warning `type` prints when it is not.
  ///
  /// Batched with the `input text` itself so the check costs no extra round
  /// trip; the warning is printed after both have run.
  Future<bool?> typeTextChecked(String text) async {
    final outputs = await adb.shellBatch([
      const ShellCommand.raw(
        'dumpsys input_method 2>/dev/null | grep -m1 mInputShown',
      ),
      // Raw, because [escapeForInputText] has already quoted the payload for
      // the device shell; quoting it a second time types the quotes.
      ShellCommand.raw('input text ${escapeForInputText(text)}'),
    ]);
    return _boolFrom(outputs[0], RegExp(r'mInputShown=(\w+)'), 'true');
  }

  /// Whether the package has an APK installed, from `pm path`.
  @override
  Future<bool> isInstalled() async {
    final out = await adb.shellLenient(['pm', 'path', packageId]);
    return out.contains('package:');
  }

  Future<void> tap(int x, int y) async {
    await adb.shell(['input', 'tap', '$x', '$y']);
  }

  Future<void> swipePath(SwipePath path) async {
    await adb.shell([
      'input',
      'swipe',
      '${path.x1}',
      '${path.y1}',
      '${path.x2}',
      '${path.y2}',
      '${path.durationMs}',
    ]);
  }

  Future<void> key(String keycode) async {
    await adb.shell(['input', 'keyevent', resolveKeycode(keycode)]);
  }

  Future<String> dumpUiXml() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      try {
        final xml = await _rawDump();
        UiTree.parse(xml);
        return xml;
      } on QaException catch (e) {
        lastError = e;
      }
    }
    throw DeviceFailure(
      'uiautomator dump failed three times. ${await _dumpFailureCause()} '
      'Last error: $lastError',
    );
  }

  /// Which of the two known causes this failure is, so the agent does not
  /// have to guess or spend a call finding out.
  Future<String> _dumpFailureCause() async {
    try {
      final leftover = await adb.shellLenient(
        [leftoverUiautomatorProbe],
        timeout: const Duration(seconds: 10),
      );
      if (leftover.trim().isNotEmpty) {
        return 'A leftover uiautomator is registered (pid '
            '${leftover.trim().split(RegExp(r'\s+')).join(', ')}) — run '
            '`qa doctor --fix`.';
      }
    } on QaException {
      return 'It fails while an animation is running — wait for the screen to '
          'settle.';
    }
    return 'No leftover uiautomator process, so this is the animation case: '
        'wait for the screen to settle and try again.';
  }

  Future<String> _rawDump() async {
    final direct = await adb.raw(
      ['exec-out', 'uiautomator', 'dump', '/dev/tty'],
      timeout: const Duration(seconds: 45),
    );
    if (direct.ok && direct.stdout.contains('<hierarchy')) return direct.stdout;
    await adb.shellLenient(
      ['uiautomator', 'dump', '/sdcard/window_dump.xml'],
      timeout: const Duration(seconds: 45),
    );
    return adb.shellLenient(['cat', '/sdcard/window_dump.xml']);
  }

  @override
  Future<List<int>> screencapPng() =>
      adb.execOutBytes(['screencap', '-p'], timeout: const Duration(seconds: 60));

  @override
  Future<int?> appPid() async {
    final out = await adb.shellLenient(['pidof', packageId]);
    final first = out.trim().split(RegExp(r'\s+')).first;
    return int.tryParse(first);
  }

  @override
  Future<void> forceStop() async {
    await adb.shellLenient(['am', 'force-stop', packageId]);
    await awaitStopped(appPid);
  }

  Future<void> launchActivity(String component, {List<String> extras = const []}) async {
    final out = await adb.shellLenient(['am', 'start', '-n', component, ...extras]);
    if (out.contains('Error')) {
      throw DeviceFailure('am start -n $component failed: $out');
    }
  }

  @override
  Future<AppLaunch> launchApp({required int vmServicePort}) async {
    await launchActivity(antaActivity, extras: androidLaunchExtras(vmServicePort));
    final forward = await adb.raw(
      ['forward', 'tcp:$vmServicePort', 'tcp:$vmServicePort'],
      timeout: const Duration(seconds: 20),
    );
    if (!forward.ok) {
      throw DeviceFailure(
        'adb forward tcp:$vmServicePort failed: ${forward.combined}',
      );
    }
    return AppLaunch(
      vmServiceUri: 'http://127.0.0.1:$vmServicePort/',
      description: 'am start -n $antaActivity (vm-service-port $vmServicePort, '
          'forwarded to the host)',
    );
  }

  @override
  Future<void> bringToFront() => launchActivity(antaActivity);

  @override
  Future<void> dropResetMarker() => markers.dropResetMarker(adb, packageId: packageId);

  @override
  Future<void> pushSeed(String localPath) =>
      markers.pushSeed(adb, localPath, packageId: packageId);

  /// `adb logcat`, not `adb shell logcat`: the device shell would split the
  /// space inside a `-T "MM-DD HH:MM:SS.mmm"` timestamp into two arguments.
  @override
  Future<String> readLog({String? sinceStamp}) async {
    final result = await adb.raw(
      [
        'logcat',
        '-d',
        '-v',
        'time',
        if (sinceStamp != null) ...['-T', sinceStamp],
      ],
      timeout: const Duration(seconds: 60),
    );
    return result.combined;
  }

  /// Scoped to the app's pid when there is one: the pid is new after every
  /// force-stop, so a previous launch's lines cannot be mistaken for this
  /// one's, and nothing depends on the host and the guest agreeing on the time.
  @override
  Future<String> qaLogText({String? stamp}) async {
    final pid = await appPid();
    lastQaLogPid = pid;
    final result = await adb.raw(
      [
        'logcat',
        '-d',
        '-v',
        'time',
        if (pid != null)
          '--pid=$pid'
        else if (stamp != null)
          ...['-T', stamp, '-s', 'flutter:V']
        else
          ...['-s', 'flutter:V'],
      ],
      timeout: const Duration(seconds: 60),
    );
    return result.combined;
  }

  int? lastQaLogPid;

  @override
  Future<String?> discoverVmServiceUri() async {
    final pid = await appPid();
    if (pid == null) return null;
    final log = await adb.raw(
      ['logcat', '-d', '-v', 'time', '--pid=$pid'],
      timeout: const Duration(seconds: 60),
    );
    final announced = vmServiceUriFromLog(log.combined);
    if (announced == null) return null;
    final port = Uri.tryParse(announced)?.port;
    if (port == null || port == 0) return null;
    final forward = await adb.raw(
      ['forward', 'tcp:$port', 'tcp:$port'],
      timeout: const Duration(seconds: 20),
    );
    if (!forward.ok) return null;
    return Uri.parse(announced).replace(host: '127.0.0.1', port: port).toString();
  }

  @override
  Future<List<String>> pendingMarkers() async {
    final listing = await adb.shellLenient(
      ['run-as', packageId, 'ls', markers.antaDocsDir],
      timeout: const Duration(seconds: 20),
    );
    return [
      for (final name in const [markers.resetMarker, markers.seedMarker])
        if (listing.split(RegExp(r'\s+')).contains(name)) name,
    ];
  }

  @override
  UiDriver? get nativeDriver => AdbUiDriver(this);
}

/// The `uiautomator` + `input` layer, which works on any Android build.
class AdbUiDriver implements UiDriver {
  AdbUiDriver(this.device);

  final AndroidDevice device;

  @override
  String get name => 'adb';

  @override
  Duration get pollInterval => const Duration(milliseconds: 400);

  @override
  Duration get settleAfterAction => const Duration(milliseconds: 300);

  @override
  Future<ScreenSize> screenSize() => device.screenSize();

  @override
  Future<UiDump> dump() async {
    final xml = await device.dumpUiXml();
    return UiDump(raw: xml, tree: UiTree.parse(xml));
  }

  @override
  Future<void> tap(int x, int y) => device.tap(x, y);

  @override
  Future<void> longPress(int x, int y, int ms) =>
      device.swipePath(SwipePath(x, y, x, y, ms));

  @override
  Future<void> swipePath(SwipePath path) => device.swipePath(path);

  @override
  Future<void> drag(int x1, int y1, int x2, int y2, {required int holdMs, required int moveMs}) =>
      throw UnsupportedOnPlatform('drag', 'the adb input path',
          instead: 'use `--via agent` (the driver build from `qa run`)');

  @override
  Future<TypeOutcome> typeText(String text, {bool replace = false}) async {
    if (replace) {
      throw UnsupportedOnPlatform(
        '--replace',
        'the adb input path',
        instead: 'use `--via agent`, or clear the field first',
      );
    }
    return TypeOutcome(imeShown: await device.typeTextChecked(text));
  }

  @override
  Future<void> clear() => throw UnsupportedOnPlatform('clear', 'the adb input path',
      instead: 'use `--via agent`, or `key del` repeatedly');

  @override
  Future<String> key(String name) async {
    final keycode = resolveKeycode(name);
    await device.key(name);
    return keycode;
  }
}
