import 'dart:io';

import 'errors.dart';
import 'process_runner.dart';
import 'shell_batch.dart';

/// Locates the Android SDK command line tools without assuming PATH.
class SdkTools {
  SdkTools({Map<String, String>? environment, bool Function(String)? exists})
      : _env = environment ?? Platform.environment,
        _exists = exists ?? _defaultExists;

  final Map<String, String> _env;
  final bool Function(String) _exists;

  static bool _defaultExists(String path) => File(path).existsSync();

  static bool get _windows => Platform.isWindows;

  static String _exe(String name) => _windows ? '$name.exe' : name;

  String? findAdb() => _find('platform-tools', _exe('adb'));

  String? findEmulator() => _find('emulator', _exe('emulator'));

  String? findQemuImg() => _find('emulator', _exe('qemu-img'));

  String requireAdb() {
    final found = findAdb();
    if (found == null) {
      throw DeviceFailure(
        'adb not found. Put it on PATH or set ANDROID_HOME / ANDROID_SDK_ROOT '
        'to the SDK root (it must contain platform-tools/${_exe('adb')}).',
      );
    }
    return found;
  }

  String requireEmulator() {
    final found = findEmulator();
    if (found == null) {
      throw DeviceFailure(
        'emulator binary not found. Set ANDROID_HOME / ANDROID_SDK_ROOT to the '
        'SDK root (it must contain emulator/${_exe('emulator')}).',
      );
    }
    return found;
  }

  String? _find(String sdkSubdir, String fileName) {
    for (final root in sdkRoots()) {
      final candidate = [root, sdkSubdir, fileName].join(Platform.pathSeparator);
      if (_exists(candidate)) return candidate;
    }
    for (final dir in _pathEntries()) {
      if (dir.isEmpty) continue;
      final candidate = [dir, fileName].join(Platform.pathSeparator);
      if (_exists(candidate)) return candidate;
    }
    return null;
  }

  /// Candidate SDK roots, from the environment and the usual install spots.
  List<String> sdkRoots() {
    final roots = <String>[];
    for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final value = _env[key];
      if (value != null && value.isNotEmpty) roots.add(value);
    }
    final home = _env['LOCALAPPDATA'] ?? _env['HOME'] ?? _env['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      roots.add([home, 'Android', 'Sdk'].join(Platform.pathSeparator));
      roots.add([home, 'Library', 'Android', 'sdk'].join(Platform.pathSeparator));
    }
    return roots;
  }

  List<String> _pathEntries() {
    final path = _env['PATH'] ?? _env['Path'] ?? '';
    return path.split(_windows ? ';' : ':');
  }
}

/// Thin typed wrapper over the `adb` executable for one serial.
class Adb {
  Adb({
    required this.executable,
    required this.runner,
    this.serial,
  });

  final String executable;
  final ProcessRunner runner;
  final String? serial;

  Adb withSerial(String? newSerial) =>
      Adb(executable: executable, runner: runner, serial: newSerial);

  List<String> _prefix(List<String> args) =>
      serial == null ? args : ['-s', serial!, ...args];

  /// Runs one `adb` invocation.
  ///
  /// A timeout here is rewrapped once, because the shape it usually has on
  /// this setup is not "the command is slow" but "adbd on the guest stopped
  /// answering", and the fix for that is the owner's to make.
  Future<RunOutcome> raw(
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    bool withSerial = true,
  }) async {
    try {
      return await runner.run(
        executable,
        withSerial ? _prefix(args) : args,
        timeout: timeout,
        binary: binary,
      );
    } on QaException catch (e) {
      if (!e.message.startsWith('timed out after')) rethrow;
      throw DeviceFailure(adbTimeoutMessage(timeout, args));
    }
  }

  /// Runs several device commands inside a single `adb shell`.
  ///
  /// One `adb` process on Windows costs about as much as the commands it
  /// carries, so a probe that wants six answers asks for them at once and
  /// splits the output on [batchSeparator].
  Future<List<String>> shellBatch(
    List<ShellCommand> commands, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (commands.isEmpty) return const [];
    final result = await raw(
      ['shell', buildBatchScript(commands)],
      timeout: timeout,
    );
    return splitBatchOutput(
      result.ok ? result.stdout : result.combined,
      commands.length,
    );
  }

  Future<String> shell(
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await raw(['shell', ...args], timeout: timeout);
    if (!result.ok) {
      throw DeviceFailure(
        'adb shell ${args.join(' ')} failed (${result.exitCode}): '
        '${result.combined}',
      );
    }
    return result.stdout;
  }

  Future<String> shellLenient(
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await raw(['shell', ...args], timeout: timeout);
    return result.ok ? result.stdout : result.combined;
  }

  Future<List<int>> execOutBytes(
    List<String> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await raw(['exec-out', ...args], timeout: timeout, binary: true);
    if (!result.ok) {
      throw DeviceFailure(
        'adb exec-out ${args.join(' ')} failed (${result.exitCode}): '
        '${result.stderr}',
      );
    }
    return result.bytes ?? const <int>[];
  }

  Future<List<AdbDevice>> devices({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final result = await raw(['devices', '-l'],
        timeout: timeout, withSerial: false);
    if (!result.ok) {
      throw DeviceFailure('adb devices failed: ${result.combined}');
    }
    return parseDevices(result.stdout);
  }
}

/// One row of `adb devices -l`.
class AdbDevice {
  const AdbDevice(this.serial, this.state, this.model);

  final String serial;
  final String state;
  final String? model;

  bool get usable => state == 'device';

  @override
  String toString() =>
      '$serial  $state${model == null ? '' : '  model:$model'}';
}

List<AdbDevice> parseDevices(String output) {
  final devices = <AdbDevice>[];
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('List of devices')) continue;
    if (line.startsWith('*')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    String? model;
    for (final part in parts.skip(2)) {
      if (part.startsWith('model:')) model = part.substring(6);
    }
    devices.add(AdbDevice(parts[0], parts[1], model));
  }
  return devices;
}

/// The emulator this harness was built around; still the name in the docs.
const String defaultSerial = 'emulator-5554';

/// What to say about an `adb` call that never came back.
///
/// The quick-boot snapshot trap makes this the likeliest failure on this
/// setup, and the only cure is a cold boot the owner has to do themselves.
String adbTimeoutMessage(Duration timeout, List<String> args) =>
    'adb did not answer in ${timeout.inSeconds}s (${args.join(' ')}) — the '
    "emulator's adbd may be degraded (quick-boot snapshot trap: the owner "
    'must cold-boot it; never do it from this tool). Run `qa doctor`.';

/// Explains one unusable `adb devices` state in terms of what to do next.
String unusableDeviceMessage(String serial, String state) => switch (state) {
      'offline' => '$serial is offline — adbd on the guest is wedged; the '
          'owner has to close and cold-boot the emulator (this tool never '
          'restarts it)',
      'unauthorized' =>
        '$serial is unauthorized — accept the USB-debugging prompt on the '
            'device',
      _ => '$serial is in state "$state", not "device"',
    };

/// Chooses which serial to talk to: explicit flag, env, then the sole device.
///
/// There is no silent default any more. A verb that runs against nothing
/// attached used to fail deep inside the first `adb shell` with whatever that
/// command happened to say; now it fails here, saying what is actually wrong.
String selectSerial({
  String? explicit,
  String? envValue,
  required List<AdbDevice> available,
}) {
  final wanted = (explicit != null && explicit.isNotEmpty)
      ? explicit
      : ((envValue != null && envValue.isNotEmpty) ? envValue : null);
  if (wanted != null) {
    for (final device in available) {
      if (device.serial != wanted) continue;
      if (device.usable) return wanted;
      throw DeviceFailure(unusableDeviceMessage(wanted, device.state));
    }
    throw DeviceFailure(
      '$wanted is not attached. ${_attachedSummary(available)}',
    );
  }
  final usable = available.where((d) => d.usable).toList();
  if (usable.length == 1) return usable.single.serial;
  if (usable.length > 1) {
    throw DeviceFailure(
      'more than one device attached; pass -d/--device or set ANTA_QA_DEVICE. '
      'Attached: ${usable.map((d) => d.serial).join(', ')}',
    );
  }
  if (available.isEmpty) {
    throw DeviceFailure('no device attached — run `qa boot`');
  }
  throw DeviceFailure(
    available
        .map((d) => unusableDeviceMessage(d.serial, d.state))
        .join('; '),
  );
}

String _attachedSummary(List<AdbDevice> available) => available.isEmpty
    ? 'Nothing is attached — run `qa boot`.'
    : 'Attached: ${available.map((d) => '${d.serial} (${d.state})').join(', ')}.';
