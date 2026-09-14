import 'adb.dart';
import 'errors.dart';
import 'gestures.dart';
import 'input_text.dart';
import 'shell_batch.dart';
import 'ui_tree.dart';

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
    required this.screen,
    this.appPid,
    this.resumedActivity,
    this.awake,
    this.locked,
    this.imeShown,
  });

  final ScreenSize screen;
  final int? appPid;
  final String? resumedActivity;
  final bool? awake;
  final bool? locked;
  final bool? imeShown;

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

/// Platform-neutral surface the verbs drive. Android is implemented; the iOS
/// simulator is Phase B.
abstract class Device {
  String get id;

  Future<ScreenSize> screenSize();

  /// One round trip that answers everything `state` and `doctor` need.
  Future<DeviceProbe> probe();

  Future<void> tap(int x, int y);

  Future<void> swipePath(SwipePath path);

  Future<void> typeText(String text);

  Future<void> key(String keycode);

  Future<UiTree> dumpUi();

  /// The raw accessibility XML, so the caller can cache exactly what it read.
  Future<String> dumpUiXml();

  Future<List<int>> screencapPng();

  Future<int?> appPid(String packageId);

  Future<void> forceStop(String packageId);

  Future<void> launchActivity(String component);
}

class AndroidDevice implements Device {
  AndroidDevice(this.adb, {this.packageId = 'com.alexzamfir.anta'});

  final Adb adb;
  final String packageId;

  @override
  String get id => adb.serial ?? defaultSerial;

  ScreenSize? _screenSize;

  /// One `adb shell` for both halves, then cached: the screen does not change
  /// under a single verb, and `scroll-to` used to ask for it once per swipe.
  @override
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
  Future<DeviceProbe> probe() async {
    final outputs = await adb.shellBatch(deviceProbeCommands(packageId));
    final probed = parseDeviceProbe(outputs);
    _screenSize ??= probed.screen;
    return probed;
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
  Future<bool> isInstalled() async {
    final out = await adb.shellLenient(['pm', 'path', packageId]);
    return out.contains('package:');
  }

  @override
  Future<void> tap(int x, int y) async {
    await adb.shell(['input', 'tap', '$x', '$y']);
  }

  @override
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

  @override
  Future<void> typeText(String text) async {
    await adb.shell(['input', 'text', escapeForInputText(text)]);
  }

  @override
  Future<void> key(String keycode) async {
    await adb.shell(['input', 'keyevent', resolveKeycode(keycode)]);
  }

  @override
  Future<UiTree> dumpUi() async => UiTree.parse(await dumpUiXml());

  @override
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
  Future<int?> appPid(String packageId) async {
    final out = await adb.shellLenient(['pidof', packageId]);
    final first = out.trim().split(RegExp(r'\s+')).first;
    return int.tryParse(first);
  }

  @override
  Future<void> forceStop(String packageId) async {
    await adb.shellLenient(['am', 'force-stop', packageId]);
  }

  @override
  Future<void> launchActivity(String component) async {
    final out = await adb.shellLenient(['am', 'start', '-n', component]);
    if (out.contains('Error')) {
      throw DeviceFailure('am start -n $component failed: $out');
    }
  }
}

/// Phase B placeholder so the verb layer stays platform-neutral.
class IosSimulator implements Device {
  IosSimulator(this.id);

  @override
  final String id;

  Never _unsupported(String what) => throw NotImplementedOnPlatform(what);

  @override
  Future<ScreenSize> screenSize() => _unsupported('screenSize');

  @override
  Future<DeviceProbe> probe() => _unsupported('state');

  @override
  Future<void> tap(int x, int y) => _unsupported('tap');

  @override
  Future<void> swipePath(SwipePath path) => _unsupported('swipe');

  @override
  Future<void> typeText(String text) => _unsupported('type');

  @override
  Future<void> key(String keycode) => _unsupported('key');

  @override
  Future<UiTree> dumpUi() => _unsupported('dump');

  @override
  Future<String> dumpUiXml() => _unsupported('dump');

  @override
  Future<List<int>> screencapPng() => _unsupported('shot');

  @override
  Future<int?> appPid(String packageId) => _unsupported('state');

  @override
  Future<void> forceStop(String packageId) => _unsupported('stop');

  @override
  Future<void> launchActivity(String component) => _unsupported('launch');
}
