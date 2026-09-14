import 'adb.dart';
import 'errors.dart';
import 'gestures.dart';
import 'input_text.dart';
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

/// Platform-neutral surface the verbs drive. Android is implemented; the iOS
/// simulator is Phase B.
abstract class Device {
  String get id;

  Future<ScreenSize> screenSize();

  Future<void> tap(int x, int y);

  Future<void> swipePath(SwipePath path);

  Future<void> typeText(String text);

  Future<void> key(String keycode);

  Future<UiTree> dumpUi();

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

  @override
  Future<ScreenSize> screenSize() async {
    final size = await adb.shellLenient(['wm', 'size']);
    final density = await adb.shellLenient(['wm', 'density']);
    final physical = _parseSize(size, 'Physical size');
    final override = _parseSize(size, 'Override size');
    if (physical == null) {
      throw DeviceFailure('could not read `wm size` output: $size');
    }
    final dpi = RegExp(r'Physical density:\s*(\d+)').firstMatch(density);
    return ScreenSize(
      physicalWidth: physical.$1,
      physicalHeight: physical.$2,
      density: dpi == null ? 160 : int.parse(dpi.group(1)!),
      overrideWidth: override?.$1,
      overrideHeight: override?.$2,
    );
  }

  static (int, int)? _parseSize(String output, String label) {
    final match = RegExp('$label:\\s*(\\d+)x(\\d+)').firstMatch(output);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
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
  Future<UiTree> dumpUi() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      try {
        return UiTree.parse(await _rawDump());
      } on QaException catch (e) {
        lastError = e;
      }
    }
    throw DeviceFailure(
      'uiautomator dump failed three times (it fails while an animation is '
      'running — wait for the screen to settle). Last error: $lastError',
    );
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
  Future<List<int>> screencapPng() => _unsupported('shot');

  @override
  Future<int?> appPid(String packageId) => _unsupported('state');

  @override
  Future<void> forceStop(String packageId) => _unsupported('stop');

  @override
  Future<void> launchActivity(String component) => _unsupported('launch');
}
