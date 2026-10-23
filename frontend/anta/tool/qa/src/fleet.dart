import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'adb.dart';
import 'apk_build.dart';
import 'app_ids.dart';
import 'doctor.dart';
import 'errors.dart';
import 'pass_report.dart';
import 'paths.dart';
import 'process_runner.dart';
import 'self_build.dart';

/// Every fleet AVD's name starts with this. `qa fleet` boots, stops and
/// retunes nothing else, which is what keeps the owner's own emulators out
/// of its reach.
const String fleetPrefix = 'anta_qa_';

/// The console port the owner's windowed emulator takes when it boots
/// first; fleet AVD N sits on `5554 + 2N`, so the two never collide.
const int ownerConsolePort = 5554;

/// The emulator's console ports end at 5682, which bounds the index.
const int fleetMaxIndex = 64;

/// Threads kept free for `flutter test` while a fleet pass runs.
const int fleetReservedThreads = 8;

/// The owner's windowed emulator's share of the host.
const int ownerEmulatorThreads = 4;

/// vCPUs per fleet AVD (`hw.cpu.ncore`).
const int fleetVcpus = 4;

/// The hardware profile and image flavour every fleet AVD shares with the
/// owner's `Pixel_9_Pro`, so every coordinate in a flow holds on both.
const String fleetDeviceProfile = 'pixel_9_pro';

/// The system image's tag: the Play Store flavour the owner's AVD runs,
/// so a guest behaves like the emulator the flows were written on.
const String fleetImageTag = 'google_apis_playstore';

/// The system image's ABI: x86_64 runs natively under the hypervisor.
const String fleetImageAbi = 'x86_64';

/// The owner's AVD whose system image the fleet copies.
const String ownerReferenceAvd = 'Pixel_9_Pro';

/// The answer `avdmanager create avd` waits for when it asks whether to
/// create a custom hardware profile, even with `-d` given.
const String avdCreateStdin = 'no\n';

/// The `config.ini` keys a fleet AVD is held to: the Pixel 9 Pro screen,
/// 2 GB, four vCPUs, a 6 GB data partition and a cold boot every time, so
/// there is no quick-boot snapshot to degrade.
const Map<String, String> fleetConfigSpec = {
  'hw.ramSize': '2048',
  'hw.cpu.ncore': '4',
  'disk.dataPartition.size': '6G',
  'hw.gpu.enabled': 'yes',
  'hw.gpu.mode': 'auto',
  'hw.keyboard': 'yes',
  'fastboot.forceColdBoot': 'yes',
  'fastboot.forceFastBoot': 'no',
  'hw.lcd.density': '480',
  'hw.lcd.width': '1280',
  'hw.lcd.height': '2856',
};

/// Fleet AVD [index]'s console port; its adb port is the next one up, so
/// ports advance by two.
int fleetPort(int index) => ownerConsolePort + 2 * index;

/// Fleet AVD [index]'s name, the only names a fleet verb acts on.
String fleetName(int index) => '$fleetPrefix$index';

/// Fleet AVD [index]'s adb serial, which adb derives from its console port.
String fleetSerial(int index) => 'emulator-${fleetPort(index)}';

/// N for `anta_qa_<N>`, or null for any other name.
int? fleetIndexOf(String name) {
  final match = RegExp(r'^anta_qa_([1-9]\d*)$').firstMatch(name);
  if (match == null) return null;
  final index = int.tryParse(match.group(1)!);
  return index != null && index <= fleetMaxIndex ? index : null;
}

/// N for a fleet serial (`emulator-5556` is 1), or null for any other one,
/// the owner's `emulator-5554` included.
int? fleetIndexOfSerial(String serial) {
  final match = RegExp(r'^emulator-(\d+)$').firstMatch(serial);
  final port = match == null ? null : int.tryParse(match.group(1)!);
  if (port == null || port <= ownerConsolePort || port.isOdd) return null;
  final index = (port - ownerConsolePort) ~/ 2;
  return index <= fleetMaxIndex ? index : null;
}

/// N for what a fleet verb was given: `anta_qa_2`, a bare `2`, or (where
/// [serials] allows it) `emulator-5558`. Anything else is refused, so no
/// fleet verb can be pointed at the owner's emulator.
int parseFleetArgument(String argument, {bool serials = false}) {
  final trimmed = argument.trim();
  final bare = int.tryParse(trimmed);
  final index = bare != null
      ? (bare >= 1 && bare <= fleetMaxIndex ? bare : null)
      : (fleetIndexOf(trimmed) ??
          (serials ? fleetIndexOfSerial(trimmed) : null));
  if (index == null) {
    throw UsageFailure(
      '"$argument" is not a fleet AVD — the fleet is ${fleetName(1)}, '
      '${fleetName(2)}, … (or just the number${serials ? ', or its emulator-<port> serial' : ''}); '
      '`qa fleet` never acts on any other emulator',
    );
  }
  return index;
}

/// How many fleet AVDs this host runs at once: the threads left after
/// `flutter test` and the owner's emulator, at [fleetVcpus] each.
int fleetCapacity(int threads) => math.max(
      1,
      (threads - fleetReservedThreads - ownerEmulatorThreads) ~/ fleetVcpus,
    );

/// The count `fleet create` works to: [requested] or the capacity, and
/// above the capacity only with [force].
int fleetCount({int? requested, required int threads, required bool force}) {
  final capacity = fleetCapacity(threads);
  final count = requested ?? capacity;
  if (count < 1 || count > fleetMaxIndex) {
    throw UsageFailure('--count must be between 1 and $fleetMaxIndex');
  }
  if (count > capacity && !force) {
    throw UsageFailure(
      '--count $count is above what this host runs at once ($capacity: '
      '$threads threads − $fleetReservedThreads for `flutter test` − '
      '$ownerEmulatorThreads for the owner\'s emulator, $fleetVcpus each); '
      'add --force to make them anyway',
    );
  }
  return count;
}

String? _configKey(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('#')) return null;
  final eq = trimmed.indexOf('=');
  if (eq <= 0) return null;
  return trimmed.substring(0, eq).trim();
}

/// The value of [key] in `config.ini` lines, or null when it is not set.
String? configValue(List<String> lines, String key) {
  for (final line in lines) {
    if (_configKey(line) != key) continue;
    return line.substring(line.indexOf('=') + 1).trim();
  }
  return null;
}

/// [lines] with every [fleetConfigSpec] key set to the fleet's value:
/// a key already there is rewritten in place, a missing one appended, and
/// every other line kept as it was.
List<String> tuneConfig(List<String> lines) {
  final seen = <String>{};
  final tuned = <String>[];
  for (final line in lines) {
    final key = _configKey(line);
    if (key == null || !fleetConfigSpec.containsKey(key)) {
      tuned.add(line);
      continue;
    }
    seen.add(key);
    tuned.add('$key=${fleetConfigSpec[key]}');
  }
  for (final entry in fleetConfigSpec.entries) {
    if (!seen.contains(entry.key)) tuned.add('${entry.key}=${entry.value}');
  }
  return tuned;
}

/// Where [lines] differ from [fleetConfigSpec], one entry per key.
List<String> configDrift(List<String> lines) => [
      for (final entry in fleetConfigSpec.entries)
        if (configValue(lines, entry.key) case final value
            when value != entry.value)
          value == null
              ? '${entry.key} unset (fleet: ${entry.value})'
              : '${entry.key}=$value (fleet: ${entry.value})',
    ];

/// `config.ini` text as lines, without the line ends or trailing blanks.
List<String> splitConfig(String text) {
  final lines = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// [lines] back as `config.ini` text, in the line ends the file had.
String joinConfig(List<String> lines, {required bool crlf}) {
  final eol = crlf ? '\r\n' : '\n';
  return '${lines.join(eol)}$eol';
}

/// The sdkmanager package an AVD's `image.sysdir.1` names
/// (`system-images\android-36\google_apis_playstore\x86_64\` gives
/// `system-images;android-36;google_apis_playstore;x86_64`).
String? imagePackageFromConfig(List<String> lines) {
  final sysdir = configValue(lines, 'image.sysdir.1');
  if (sysdir == null) return null;
  final parts =
      sysdir.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  if (parts.length != 4 || parts.first != 'system-images') return null;
  return parts.join(';');
}

/// The image `fleet create` uses: the one the owner's AVD names, else the
/// only installed `google_apis_playstore` x86_64 image ([installedApis]
/// lists the API directories that hold one).
String chooseFleetImage({
  required List<String>? ownerConfig,
  required List<String> installedApis,
}) {
  final owner = ownerConfig == null ? null : imagePackageFromConfig(ownerConfig);
  if (owner != null) return owner;
  if (installedApis.length == 1) {
    return 'system-images;${installedApis.single};$fleetImageTag;$fleetImageAbi';
  }
  throw DeviceFailure(
    installedApis.isEmpty
        ? 'no system-images/*/$fleetImageTag/$fleetImageAbi image is installed '
            'and $ownerReferenceAvd names none — install one with sdkmanager'
        : 'more than one $fleetImageTag/$fleetImageAbi image is installed '
            '(${installedApis.join(', ')}) and $ownerReferenceAvd names none '
            'to choose by',
  );
}

/// The `avdmanager` vector that makes a fleet AVD; it never carries
/// `--force`, so an existing AVD of that name is never overwritten.
List<String> avdCreateArgs(String name, String image) => [
      'create',
      'avd',
      '-n',
      name,
      '-k',
      image,
      '-d',
      fleetDeviceProfile,
    ];

/// The emulator vector for fleet AVD [index]: on its own port, with no
/// snapshot to load or save. `-gpu host` keeps the frame times of the
/// owner's emulator; `-gpu auto` without a window falls back to
/// swiftshader and burns about six host cores. It opens a window, which
/// `fleet boot` minimizes: a `-no-window` qemu keeps one host thread
/// spinning at 100 % while the guest idles (1.2 cores at boot, 2.2 after
/// hours of passes, against 0.14 minimized), whatever the other flags.
List<String> fleetEmulatorArgs(int index) => [
      '-avd',
      fleetName(index),
      '-port',
      '${fleetPort(index)}',
      '-no-audio',
      '-no-boot-anim',
      '-no-snapshot',
      '-no-metrics',
      '-gpu',
      'host',
    ];

/// Asks an emulator's console which AVD it runs.
const List<String> emuAvdNameArgs = ['emu', 'avd', 'name'];

/// Asks an emulator to shut down gracefully.
const List<String> emuKillArgs = ['emu', 'kill'];

/// What keeps a fleet device's screen on for a whole pass: the longest
/// screen-off timeout and stay-awake while powered. The emulator's own
/// boot-time attempt fails once several emulators are up ("more than one
/// emulator"), so `fleet boot` sets both on each serial it boots.
const List<List<String>> fleetKeepAwakeCommands = [
  ['settings', 'put', 'system', 'screen_off_timeout', '2147483647'],
  ['svc', 'power', 'stayon', 'true'],
];

/// What a pass needs granted that a freshly created guest lacks, by the
/// comparison with the owner's emulator (2026-10-23): POST_NOTIFICATIONS,
/// without which the app's notifications are blocked (`importance=NONE`)
/// and an alarm's full-screen ring never shows. Exact alarms
/// (`USE_EXACT_ALARM`), the full-screen intent op and the doze allowlist
/// were the same on both.
const List<({String what, List<String> command})> passGrants = [
  (
    what: 'POST_NOTIFICATIONS',
    command: ['pm', 'grant', antaPackage, 'android.permission.POST_NOTIFICATIONS'],
  ),
];

/// Whether `install` grants [passGrants]: on a fleet guest always, on any
/// other device only when asked with `--grant`, so the owner's emulator
/// and phone keep the permissions their owner chose. A guest is the
/// fleet's when its console names a fleet AVD ([consoleAvd], from
/// `adb emu avd name`), never by its port: the owner's AVD can land on
/// 5556 when it boots second.
bool grantsPassPermissions({required bool asked, required String? consoleAvd}) =>
    asked || (consoleAvd != null && fleetIndexOf(consoleAvd) != null);

/// Applies [passGrants] on [device] (an [Adb] narrowed to [serial]) and
/// returns one `granted: …` or `not granted: …` line per grant.
Future<List<String>> applyPassGrants(Adb device, String serial) async {
  final lines = <String>[];
  for (final grant in passGrants) {
    final result = await device.raw(['shell', ...grant.command]);
    final said = result.combined.trim();
    lines.add(result.ok && said.isEmpty
        ? 'granted: ${grant.what} on $serial'
        : 'not granted: ${grant.what} on $serial — ${said.isEmpty ? 'exit ${result.exitCode}' : said}');
  }
  return lines;
}

/// The AVD name in `adb emu avd name` output, or null when the console
/// did not say.
String? parseEmuAvdName(String output) {
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line == 'OK') continue;
    if (line.startsWith('KO') || line.contains(' ')) return null;
    return line;
  }
  return null;
}

/// Why `fleet stop` must leave [serial] alone, or null when its console
/// reports [expected]. Checked right before `emu kill`, because a port is
/// only a convention: anything could have been started on it.
String? stopRefusal({
  required String expected,
  required String serial,
  required String? reported,
}) {
  if (reported == expected) return null;
  return '$serial reports AVD ${reported == null ? 'nothing' : '"$reported"'}, '
      'not $expected — `fleet stop` only stops the fleet AVD it names, so '
      '$serial is left running';
}

/// The P-core mask of a hybrid CPU: the performance cores carry two
/// threads each and the efficiency cores one, so `cores < threads <
/// 2 * cores` and the first `2 * (threads - cores)` logical CPUs are the
/// P-cores. Null for a part that is not hybrid.
int? hybridAffinityMask({required int cores, required int threads}) {
  if (cores <= 0 || threads <= cores || threads >= 2 * cores) return null;
  final pLogical = 2 * (threads - cores);
  if (pLogical >= 63) return null;
  return (1 << pLogical) - 1;
}

/// A hex affinity mask as `ANTA_QA_FLEET_AFFINITY` gives it (`FFFF` or
/// `0xFFFF`).
int parseAffinityMask(String raw) {
  final text = raw.trim().toLowerCase().replaceFirst(RegExp('^0x'), '');
  final mask = int.tryParse(text, radix: 16);
  if (mask == null || mask <= 0) {
    throw UsageFailure('$fleetAffinityEnv must be a non-zero hex mask such '
        'as 0xFFFF (got "$raw")');
  }
  return mask;
}

/// [mask] as `fleet status` and `doctor` print an affinity, the way Task
/// Manager and PowerShell show one.
String hexMask(int mask) => '0x${mask.toRadixString(16).toUpperCase()}';

/// Overrides the P-core mask `fleet boot` pins the emulators to.
const String fleetAffinityEnv = 'ANTA_QA_FLEET_AFFINITY';

/// The mask `fleet boot` pins a fleet qemu to, and why, or a null mask to
/// leave the scheduler alone. Windows puts a windowless emulator on the
/// E-cores of a hybrid part, where the guest runs 1.65× slower; macOS is
/// never pinned.
({int? mask, String reason}) fleetAffinity({
  required bool windows,
  required bool disabled,
  String? override,
  int? cores,
  int? threads,
}) {
  if (!windows) return (mask: null, reason: 'never pinned off Windows');
  if (disabled) return (mask: null, reason: '--no-affinity');
  if (override != null && override.trim().isNotEmpty) {
    return (mask: parseAffinityMask(override), reason: fleetAffinityEnv);
  }
  if (cores == null || threads == null) {
    return (mask: null, reason: 'CPU topology unknown');
  }
  final mask = hybridAffinityMask(cores: cores, threads: threads);
  return mask == null
      ? (mask: null, reason: 'not a hybrid CPU ($cores cores, $threads threads)')
      : (mask: mask, reason: 'P-cores of $cores cores / $threads threads');
}

/// PowerShell that prints every running qemu as its pid, affinity and
/// command line, tab-separated. It holds no double quote, because the argument quoting
/// on Windows escapes them in a way `powershell -Command` misreads.
const String qemuListScript =
    r"Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'qemu-system*' } | "
    r"ForEach-Object { $a = ''; try { $a = '{0:X}' -f [int64](Get-Process -Id $_.ProcessId -ErrorAction Stop).ProcessorAffinity } catch {}; "
    r'($_.ProcessId, $a, $_.CommandLine) -join [char]9 }';

/// PowerShell that prints the host's physical cores and logical CPUs.
const String cpuTopologyScript =
    r"$c = 0; $t = 0; Get-CimInstance Win32_Processor | ForEach-Object { $c += $_.NumberOfCores; $t += $_.NumberOfLogicalProcessors }; '{0} {1}' -f $c, $t";

/// PowerShell that sets one process's affinity and prints it back in hex.
String pinScript(int pid, int mask) =>
    "\$p = Get-Process -Id $pid -ErrorAction Stop; "
    '\$p.ProcessorAffinity = [IntPtr][int64]$mask; \$p.Refresh(); '
    "'{0:X}' -f [int64]\$p.ProcessorAffinity";

/// The `user32` calls the window scripts need. It holds double quotes, so
/// those scripts go to PowerShell encoded ([encodePowerShell]).
const String _user32Type =
    "\$ProgressPreference = 'SilentlyContinue'\n"
    "Add-Type -Namespace AntaQa -Name Win32 -MemberDefinition '"
    '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); '
    '[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);'
    "'\n";

/// PowerShell that prints every running qemu as its pid and its window:
/// `headless` for the `-headless` binary, `minimized` or `visible` for a
/// window, `pending` while a windowed one has not opened it yet.
const String qemuWindowScript = '$_user32Type'
    r"Get-Process -Name 'qemu-system*' -ErrorAction SilentlyContinue | ForEach-Object { "
    r"$h = $_.MainWindowHandle; $w = 'pending'; "
    r"if ($_.ProcessName -like '*headless*') { $w = 'headless' } "
    r"elseif ($h -ne [IntPtr]::Zero) { if ([AntaQa.Win32]::IsIconic($h)) { $w = 'minimized' } else { $w = 'visible' } }; "
    r"'{0} {1}' -f $_.Id, $w }";

/// PowerShell that minimizes [pid]'s window (`SW_MINIMIZE`) once it exists
/// and prints what the window then is: `minimized`, `visible` when Windows
/// kept it up, `pending` when no window opened within 20 s, `gone` when
/// the process ended. A minimized qemu stays minimized across relaunches
/// of the app inside it.
String minimizeWindowScript(int pid) => '$_user32Type'
    '\$deadline = (Get-Date).AddSeconds(20); \$h = [IntPtr]::Zero\n'
    'while ((Get-Date) -lt \$deadline) { '
    '\$p = Get-Process -Id $pid -ErrorAction SilentlyContinue; '
    "if (\$null -eq \$p) { 'gone'; exit 0 }; "
    '\$h = \$p.MainWindowHandle; if (\$h -ne [IntPtr]::Zero) { break }; '
    'Start-Sleep -Milliseconds 250 }\n'
    "if (\$h -eq [IntPtr]::Zero) { 'pending'; exit 0 }\n"
    '[void][AntaQa.Win32]::ShowWindow(\$h, 6); Start-Sleep -Milliseconds 200\n'
    "if ([AntaQa.Win32]::IsIconic(\$h)) { 'minimized' } else { 'visible' }";

/// PowerShell that prints each of [pids]' host-GPU dedicated memory, one
/// line per GPU adapter instance (`pid_<pid>_luid_…_phys_0 <bytes>`); the
/// trailing `_` keeps `pid_12*` from matching pid 123.
String gpuMemoryScript(List<int> pids) =>
    '(Get-Counter -Counter @(${[
      for (final pid in pids) "'\\GPU Process Memory(pid_${pid}_*)\\Dedicated Usage'",
    ].join(',')}) -ErrorAction SilentlyContinue).CounterSamples | '
    r"ForEach-Object { $_.InstanceName + ' ' + [int64]$_.CookedValue }";

/// [gpuMemoryScript]'s output as bytes per pid, the adapters summed.
Map<int, int> parseGpuMemory(String output) {
  final byPid = <int, int>{};
  for (final line in output.split('\n')) {
    final match = RegExp(r'^\s*pid_(\d+)_\S*\s+(\d+)\s*$').firstMatch(line);
    if (match == null) continue;
    final pid = int.tryParse(match.group(1)!);
    final bytes = int.tryParse(match.group(2)!);
    if (pid == null || bytes == null) continue;
    byPid[pid] = (byPid[pid] ?? 0) + bytes;
  }
  return byPid;
}

/// PowerShell that prints [pid]'s CPU seconds, or nothing once it is gone.
String cpuSecondsScript(int pid) =>
    "\$p = Get-Process -Id $pid -ErrorAction SilentlyContinue; "
    "if (\$null -ne \$p) { '{0:F3}' -f \$p.CPU }";

/// Whether a qemu that is not on adb burned less than this much CPU over
/// [staleQemuSample]: a guest that is booting burns seconds per second, a
/// hung one (`detected a hanging thread 'QEMU2 main loop'`, its crash
/// window up) none at all.
const double staleQemuCpuSeconds = 0.05;

/// How long `fleet boot` watches a qemu that is up but not on adb before
/// it calls it hung.
const Duration staleQemuSample = Duration(seconds: 3);

/// Whether two [cpuSecondsScript] readings [staleQemuSample] apart show a
/// qemu doing nothing; false when either could not be read.
bool isIdleQemu(double? before, double? after) =>
    before != null && after != null && after - before < staleQemuCpuSeconds;

/// Why `fleet stop --force` must not kill [qemu] as fleet AVD [index], or
/// null when its command line names that AVD on its fleet port. The port
/// is required too: a fleet name started by hand elsewhere is not ours.
String? forceStopRefusal(QemuProcess qemu, int index) {
  final name = fleetName(index);
  if (qemu.avd != name) {
    return 'qemu ${qemu.pid} runs "${qemu.avd}", not $name — left running';
  }
  if (qemu.port != fleetPort(index)) {
    return 'qemu ${qemu.pid} runs $name on '
        '${qemu.port == null ? 'no -port' : 'port ${qemu.port}'}, not its '
        'fleet port ${fleetPort(index)} — left running';
  }
  return null;
}

/// PowerShell that kills [pid] only while it is still a qemu whose command
/// line names [avd] — read again right before the kill, so a pid reused
/// since the process list was taken is never hit — and prints `killed`,
/// `gone` or `mismatch`. `\W?` takes an optional quote around the name and
/// `\b` keeps `anta_qa_1` from matching `anta_qa_12`.
String forceStopScript(int pid, String avd) =>
    "\$p = Get-CimInstance Win32_Process -Filter 'ProcessId=$pid'; "
    "if (\$null -eq \$p) { 'gone'; exit 0 }; "
    "if (\$p.Name -like 'qemu-system*' -and \$p.CommandLine -match '-avd\\s+\\W?$avd\\b') "
    "{ Stop-Process -Id $pid -Force -ErrorAction Stop; 'killed' } else { 'mismatch' }";

/// [script] as `powershell -EncodedCommand` takes it (base64 of UTF-16LE),
/// which carries double quotes that `-Command` would get mangled on Windows.
String encodePowerShell(String script) => base64.encode([
      for (final unit in script.codeUnits) ...[unit & 0xFF, unit >> 8],
    ]);

/// What a fleet qemu shows on the host desktop.
enum QemuWindow {
  headless,
  minimized,
  visible,
  pending;

  static QemuWindow? parse(String word) =>
      values.where((w) => w.name == word.trim()).firstOrNull;
}

/// The windows [qemuWindowScript] printed, by pid.
Map<int, QemuWindow> parseQemuWindows(String output) => {
      for (final line in output.split('\n'))
        if (RegExp(r'^\s*(\d+)\s+(\w+)\s*$').firstMatch(line) case final match?)
          int.parse(match.group(1)!): ?QemuWindow.parse(match.group(2)!),
    };

/// One running emulator's qemu, found by its command line.
class QemuProcess {
  const QemuProcess({
    required this.pid,
    required this.avd,
    this.port,
    this.affinity,
    this.window,
  });

  final int pid;
  final String avd;
  final int? port;

  /// The process affinity mask; null off Windows or when it was not
  /// readable.
  final int? affinity;

  /// [QemuWindow.headless] from the command line alone; whether a
  /// windowed one is minimized only once [FleetHost.qemuProcesses] was
  /// asked for the windows, else null.
  final QemuWindow? window;

  QemuProcess withWindow(QemuWindow? value) => QemuProcess(
        pid: pid,
        avd: avd,
        port: port,
        affinity: affinity,
        window: value ?? window,
      );
}

QemuProcess? _qemuFrom(int pid, String commandLine, int? affinity) {
  if (!commandLine.contains('qemu-system')) return null;
  final avd = RegExp(r'-avd\s+"?([^\s"]+)').firstMatch(commandLine)?.group(1);
  if (avd == null) return null;
  final port = RegExp(r'-port\s+(\d+)').firstMatch(commandLine)?.group(1);
  final headless = RegExp(r'qemu-system-[\w]+-headless|\s-no-window\b')
      .hasMatch(commandLine);
  return QemuProcess(
    pid: pid,
    avd: avd,
    port: port == null ? null : int.parse(port),
    affinity: affinity,
    window: headless ? QemuWindow.headless : null,
  );
}

/// Parses [qemuListScript]'s output (tab-separated) or `ps -o pid=,command=`
/// (space-separated) into the emulators it shows.
List<QemuProcess> parseQemuList(String output) {
  final found = <QemuProcess>[];
  for (final raw in output.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.trim().isEmpty) continue;
    QemuProcess? qemu;
    if (line.contains('\t')) {
      final parts = line.split('\t');
      final pid = int.tryParse(parts[0].trim());
      if (pid == null || parts.length < 3) continue;
      final hex = parts[1].trim();
      qemu = _qemuFrom(
        pid,
        parts.sublist(2).join('\t'),
        hex.isEmpty ? null : int.tryParse(hex, radix: 16),
      );
    } else {
      final match = RegExp(r'^\s*(\d+)\s+(.*)$').firstMatch(line);
      if (match == null) continue;
      qemu = _qemuFrom(int.parse(match.group(1)!), match.group(2)!, null);
    }
    if (qemu != null) found.add(qemu);
  }
  return found;
}

/// `cores threads` from [cpuTopologyScript], or null when unreadable.
({int cores, int threads})? parseCpuTopology(String output) {
  final match = RegExp(r'(\d+)\s+(\d+)').firstMatch(output);
  if (match == null) return null;
  final cores = int.parse(match.group(1)!);
  final threads = int.parse(match.group(2)!);
  return cores > 0 && threads > 0 ? (cores: cores, threads: threads) : null;
}

/// Where a fleet AVD stands.
enum FleetState {
  notCreated('not created'),
  stopped('stopped'),
  booting('booting'),
  device('device'),
  offline('offline');

  const FleetState(this.label);

  final String label;
}

/// The state from what adb, the guest and the process list say.
/// [bootCompleted] is only asked of a device adb lists as `device`.
FleetState fleetStateOf({
  required bool created,
  required String? adbState,
  required bool? bootCompleted,
  required bool qemuAlive,
}) {
  if (!created) return FleetState.notCreated;
  if (adbState == 'device') {
    return bootCompleted == true ? FleetState.device : FleetState.booting;
  }
  if (adbState != null) return FleetState.offline;
  return qemuAlive ? FleetState.booting : FleetState.stopped;
}

/// One fleet AVD as `fleet status` reports it.
class FleetMember {
  const FleetMember({
    required this.index,
    required this.created,
    required this.state,
    this.qemu,
    this.installed,
    this.heldBy,
    this.launches,
    this.gpuBytes,
  });

  final int index;
  final bool created;
  final FleetState state;
  final QemuProcess? qemu;

  /// What `qa install` recorded for this AVD's serial.
  final ApkRecord? installed;

  /// The AVD another emulator on this member's port reports, when it is
  /// not this one.
  final String? heldBy;

  /// The app launches counted on this guest; null when none was.
  final FleetLaunches? launches;

  /// Its qemu's host-GPU dedicated memory; null off Windows or unread.
  final int? gpuBytes;

  FleetMember withGpu(int? bytes) => FleetMember(
        index: index,
        created: created,
        state: state,
        qemu: qemu,
        installed: installed,
        heldBy: heldBy,
        launches: launches,
        gpuBytes: bytes,
      );

  String get name => fleetName(index);
  String get serial => fleetSerial(index);
  int get port => fleetPort(index);

  /// Up, booted and answering as itself: what `install` and `pass` use.
  bool get ready => state == FleetState.device && heldBy == null;

  String get stateText =>
      heldBy == null ? state.label : 'port held by $heldBy';

  Map<String, Object?> toJson(ApkRecord? built) => {
        'name': name,
        'serial': serial,
        'port': port,
        'state': heldBy == null ? state.label : 'held',
        'heldBy': heldBy,
        'app': created ? appStatus(installed, built) : null,
        'installed': installed?.toJson(),
        'qemuPid': qemu?.pid,
        'affinity': qemu?.affinity == null ? null : hexMask(qemu!.affinity!),
        'window': qemu?.window?.name,
        'launches': launches?.count,
        'launchesSinceBoot': launches?.sinceBoot,
        'gpuMb': gpuBytes == null ? null : megabytes(gpuBytes!),
      };
}

/// Whether [installed] is the build `apk.json` records (or a newer one),
/// and a QA driver build: a `qa run --no-driver` record is never current.
bool isCurrentInstall(ApkRecord? installed, ApkRecord? built) =>
    installed != null &&
    built != null &&
    installed.isQaDriverBuild &&
    !built.builtAt.isAfter(installed.builtAt);

/// What a pass says about a device whose install record is not a QA driver
/// build, before it treats the device as having nothing installed.
const String notDriverBuildWarning =
    'warning: the installed build is not a QA driver build';

/// [bytes] in whole MB, as `fleet status` prints the GPU counter.
int megabytes(int bytes) => bytes ~/ (1024 * 1024);

/// The app launches after which `fleet pass` and `fleet install` recycle a
/// guest (`fleet stop` + `fleet boot`, ≈ 20 s) before they start. Measured
/// 2026-10-23: every launch grows the qemu's host-GPU allocation by
/// ≈ 370–445 MB that only a reboot gives back, every verb slows with it (a
/// reseed 5.6 s on a fresh guest, 10 s two hours later), and anta_qa_2 hung
/// at ≈ 130 launches (58.7 GB). A sharded calendar pass is ≈ 10 launches per
/// guest, so 40 is four passes, under a third of the way to that hang.
const int fleetRecycleLaunches = 40;

/// The qemu GPU counter above which a guest is recycled however many
/// launches were counted: about what [fleetRecycleLaunches] grows it to,
/// and the guard for a guest whose launches nobody counted (booted before
/// the counter existed, or driven by hand).
const int fleetRecycleGpuBytes = 16 * 1024 * 1024 * 1024;

/// The app launches a fleet guest has served: since `fleet boot` started
/// it ([sinceBoot]), or since the first one counted for a guest booted
/// before the counter existed. `launchInstalled` is the one place the
/// harness starts the app, and it counts every start there.
class FleetLaunches {
  const FleetLaunches({required this.count, required this.sinceBoot});

  final int count;
  final bool sinceBoot;

  /// The count as `fleet status` prints it: `12+` when the boot predates it.
  String get label => sinceBoot ? '$count' : '$count+';

  static FleetLaunches? read(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic>) return null;
      final count = json['launches'];
      if (count is! int) return null;
      return FleetLaunches(count: count, sinceBoot: json['sinceBoot'] == true);
    } on Object {
      return null;
    }
  }

  static void _write(String path, FleetLaunches value, DateTime at) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'launches': value.count,
        'sinceBoot': value.sinceBoot,
        'updated': at.toUtc().toIso8601String(),
      }));
  }

  /// Zero, from a boot `fleet boot` just made.
  static void reset(String path, DateTime at) =>
      _write(path, const FleetLaunches(count: 0, sinceBoot: true), at);

  /// One launch more; returns the new count.
  static FleetLaunches record(String path, DateTime at) {
    final before = read(path);
    final after = FleetLaunches(
      count: (before?.count ?? 0) + 1,
      sinceBoot: before?.sinceBoot ?? false,
    );
    _write(path, after, at);
    return after;
  }
}

/// Why [member] is due a recycle before a pass or an install, or null when
/// it is healthy (or nothing is known about it).
String? recycleReason(FleetMember member) {
  final launches = member.launches;
  if (launches != null && launches.count > fleetRecycleLaunches) {
    return '${launches.label} app launches since boot (over $fleetRecycleLaunches)';
  }
  final gpu = member.gpuBytes;
  if (gpu != null && gpu > fleetRecycleGpuBytes) {
    return 'its qemu holds ${megabytes(gpu)} MB of GPU memory '
        '(over ${megabytes(fleetRecycleGpuBytes)} MB)';
  }
  return null;
}

/// Which of [members] `fleet pass` and `fleet install` recycle first, and
/// the line each one gets: `recycling` when [enabled], a warning under
/// `--no-recycle`.
({List<FleetMember> recycle, List<String> lines}) planRecycle(
  List<FleetMember> members, {
  required bool enabled,
}) {
  final recycle = <FleetMember>[];
  final lines = <String>[];
  for (final member in members) {
    final reason = recycleReason(member);
    if (reason == null) continue;
    if (enabled) {
      recycle.add(member);
      lines.add('recycling ${member.name} (${member.serial}): $reason');
    } else {
      lines.add('warning: ${member.name} (${member.serial}) is due a recycle '
          '($reason) — --no-recycle keeps it running');
    }
  }
  return (recycle: recycle, lines: lines);
}

String _stamp(DateTime? at) {
  if (at == null) return '?';
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _buildName(ApkRecord record) =>
    '${record.gitHash ?? 'no-hash'}${record.dirty ? '+dirty' : ''}';

/// The app column of `fleet status`: what is installed and whether
/// `apk.json` has moved past it.
String appStatus(ApkRecord? installed, ApkRecord? built) {
  if (installed == null) return 'not installed';
  final what = '${_buildName(installed)} ${_stamp(installed.installedAt)}';
  if (built != null && built.builtAt.isAfter(installed.builtAt)) {
    return 'stale $what (apk.json has ${_buildName(built)} '
        'built ${_stamp(built.builtAt)})';
  }
  return 'installed $what';
}

/// One `fleet status` line.
String fleetStatusLine(
  FleetMember member,
  ApkRecord? built, {
  required bool showAffinity,
}) {
  final qemu = member.qemu;
  final affinity = !showAffinity || qemu == null
      ? ''
      : ' affinity=${qemu.affinity == null ? '?' : hexMask(qemu.affinity!)}';
  final window = qemu?.window == null ? '' : ' window=${qemu!.window!.name}';
  final launches = member.launches;
  final gpu = member.gpuBytes;
  final health = [
    if (launches != null) 'launches=${launches.label}',
    if (gpu != null) 'gpu=${megabytes(gpu)} MB',
  ].join(' ');
  return [
    member.name.padRight(10),
    member.serial.padRight(14),
    member.stateText.padRight(12),
    member.created ? 'app ${appStatus(member.installed, built)}' : 'app -',
    qemu == null ? '' : 'qemu ${qemu.pid}$affinity$window',
    if (qemu != null) health,
  ].join('  ').trimRight();
}

/// One line for an AVD that is not the fleet's: listed, never acted on.
String ownerStatusLine(String avd, QemuProcess? qemu) =>
    'owner       ${avd.padRight(14)}  '
    '${qemu == null ? 'stopped' : 'running (qemu ${qemu.pid}${qemu.port == null ? '' : ', port ${qemu.port}'})'}'
    '  — not the fleet\'s; never acted on';

/// The `fleet` line of `qa doctor`. A booted fleet qemu off [pinMask] on a
/// hybrid host warns: its guest runs on the E-cores. A headless one warns
/// too: it keeps a host thread spinning while the guest idles. So does one
/// due a recycle ([recycleReason]): it slows every verb and heads for a hang.
CheckResult checkFleet(List<FleetMember> members, {int? pinMask}) {
  if (!members.any((m) => m.created)) {
    return CheckResult.ok(
      'fleet',
      'no fleet AVDs — `qa fleet create` makes ${members.length}',
    );
  }
  final unpinned = <String>[];
  final headless = <String>[];
  final worn = <String>[];
  final parts = <String>[];
  for (final member in members) {
    var text = '${member.name} ${member.stateText}';
    final qemu = member.qemu;
    if (pinMask != null && qemu != null) {
      final pinned = qemu.affinity == pinMask;
      text += pinned ? ' pinned' : ' unpinned';
      if (!pinned) unpinned.add(member.name);
    }
    if (qemu?.window == QemuWindow.headless) {
      text += ' headless';
      headless.add(member.name);
    }
    final launches = member.launches;
    if (qemu != null && launches != null) text += ' launches=${launches.label}';
    if (qemu != null && member.gpuBytes != null) {
      text += ' gpu=${megabytes(member.gpuBytes!)} MB';
    }
    if (qemu != null && recycleReason(member) != null) {
      text += ' due a recycle';
      worn.add(member.name);
    }
    parts.add(text);
  }
  final detail = '${members.length} AVDs: ${parts.join(', ')}';
  if (unpinned.isEmpty && headless.isEmpty && worn.isEmpty) {
    return CheckResult.ok('fleet', detail);
  }
  return CheckResult(
    name: 'fleet',
    status: CheckStatus.warn,
    detail: detail,
    fix: [
      if (worn.isNotEmpty)
        '${worn.join(', ')} ${worn.length == 1 ? 'is' : 'are'} past the '
            'health threshold ($fleetRecycleLaunches launches or '
            '${megabytes(fleetRecycleGpuBytes)} MB of GPU memory) — `qa fleet '
            'pass` and `qa fleet install` recycle it first; by hand: ${[
          for (final name in worn) '`qa fleet stop $name`, `qa fleet boot $name`',
        ].join('; ')}',
      if (headless.isNotEmpty)
        '${headless.join(', ')} ${headless.length == 1 ? 'runs' : 'run'} '
            'headless, which spins a host core while idle — re-boot it '
            'windowed: ${[
          for (final name in headless) '`qa fleet stop $name`, `qa fleet boot $name`',
        ].join('; ')}',
      if (unpinned.isNotEmpty)
        '`qa fleet boot ${unpinned.join(' ')}` pins a running fleet AVD to '
            'the P-cores (${hexMask(pinMask!)}) without restarting it',
    ].join('; '),
  );
}

/// What `fleet pass` runs on, and what it has to say about the rest.
class FleetPick {
  const FleetPick({
    required this.members,
    required this.warnings,
    required this.refused,
    this.note,
  });

  final List<FleetMember> members;
  final List<String> warnings;

  /// Devices left out, each with the reason.
  final List<String> refused;

  /// Set when a `shard=no` suite was narrowed to one device.
  final String? note;
}

/// Picks the devices of a fleet pass: the ready fleet AVDs (or the
/// [wanted] ones), each with an install; a build older than `apk.json`
/// is used with a warning, a device with nothing installed is left out,
/// and a suite that must not be sharded runs whole on the first one.
FleetPick pickPassDevices({
  required List<FleetMember> members,
  required ApkRecord? built,
  required String suite,
  required bool shardable,
  List<int>? wanted,
}) {
  final warnings = <String>[];
  final refused = <String>[];
  final candidates = <FleetMember>[];
  if (wanted == null) {
    candidates.addAll(members.where((m) => m.ready));
  } else {
    for (final index in wanted) {
      final member = members.where((m) => m.index == index).firstOrNull;
      if (member == null || !member.ready) {
        refused.add('${fleetName(index)}: not up '
            '(${member?.stateText ?? 'not created'}) — `qa fleet boot ${fleetName(index)}`');
        continue;
      }
      if (!candidates.contains(member)) candidates.add(member);
    }
  }
  final picked = <FleetMember>[];
  for (final member in candidates) {
    final installed = member.installed;
    if (installed == null) {
      refused.add('${member.name} (${member.serial}): nothing installed — '
          '`qa fleet install`');
      continue;
    }
    if (!installed.isQaDriverBuild) {
      refused.add('${member.name} (${member.serial}): '
          '${notDriverBuildWarning.replaceFirst('warning: ', '')} — '
          '`qa fleet install --build`');
      continue;
    }
    if (built == null) {
      warnings.add('warning: no build/qa/apk.json — cannot tell whether '
          '${member.name} runs the current build (${_buildName(installed)})');
    } else if (!isCurrentInstall(installed, built)) {
      warnings.add('warning: ${member.name} runs ${_buildName(installed)} '
          'built ${_stamp(installed.builtAt)}, older than apk.json\'s '
          '${_buildName(built)} — `qa fleet install` to test the newer one');
    }
    picked.add(member);
  }
  String? note;
  if (!shardable && picked.length > 1) {
    note = '"$suite" says shard=no — its flows share one seed in order, so '
        'it runs whole on ${picked.first.name} (${picked.first.serial}) only';
    picked.removeRange(1, picked.length);
  }
  return FleetPick(
    members: picked,
    warnings: warnings,
    refused: refused,
    note: note,
  );
}

/// The global options a child `qa` inherits: its device, and the parent's
/// `--via` and `--verbose`.
List<String> qaChildGlobals({String? serial, String? via, bool verbose = false}) => [
      if (serial != null) ...['-d', serial],
      if (via != null) '--via=$via',
      if (verbose) '--verbose',
    ];

/// The `qa build` a `fleet install --build` runs first, with no device: one
/// APK serves every guest.
List<String> fleetBuildChildArgs({String? via, bool verbose = false}) =>
    [...qaChildGlobals(via: via, verbose: verbose), 'build'];

/// One guest's `qa -d <serial> install`, run in parallel with the others.
List<String> fleetInstallChildArgs(
  String serial, {
  String? via,
  bool verbose = false,
}) =>
    [...qaChildGlobals(serial: serial, via: via, verbose: verbose), 'install'];

/// The `qa fleet boot <name>` a recycle runs after its stop: the boot path
/// with its pin, its minimized window and its launch-count reset.
List<String> fleetBootChildArgs(String name, {bool verbose = false}) =>
    [...qaChildGlobals(verbose: verbose), 'fleet', 'boot', name];

/// One shard of a fleet pass: `qa -d <serial> pass <suite> --shard i/n`,
/// its report also written to [jsonPath] so the parent can merge it
/// without parsing output.
List<String> fleetPassChildArgs({
  required String serial,
  required String suite,
  required (int, int)? shard,
  required String jsonPath,
  String? label,
  bool stopOnFail = false,
  bool keepState = false,
  String? via,
  bool verbose = false,
}) =>
    [
      ...qaChildGlobals(serial: serial, via: via, verbose: verbose),
      'pass',
      suite,
      if (shard != null) '--shard=${shard.$1}/${shard.$2}',
      '--json=$jsonPath',
      if (label != null && label.isNotEmpty) '--label=$label',
      if (stopOnFail) '--stop-on-fail',
      if (keepState) '--keep-state',
    ];

/// The lines of a child pass worth echoing live: each flow's verdict, the
/// shard's own verdict line, whether it left its device quiet (or why it
/// did not try), and that its report is partial.
bool isPassProgressLine(String line) =>
    RegExp(r'^=== .+: (?:ok|FAILED)').hasMatch(line) ||
    RegExp(r'^pass: \d+/\d+ green').hasMatch(line) ||
    RegExp(r'^devices? (?:left|not left) ').hasMatch(line) ||
    line.startsWith('quiet relaunch skipped') ||
    line.startsWith(partialLine);

/// How to start this tool again as a child: the compiled exe when this
/// process is one, `dart run tool/qa/qa.dart` under `dart run`.
({String executable, List<String> leading}) qaSelfCommand({
  required String resolvedExecutable,
  required String qaExe,
  required bool qaExeExists,
  required String script,
}) {
  final name = resolvedExecutable.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (name != 'dart' && name != 'dart.exe') {
    return (
      executable: qaExeExists ? qaExe : resolvedExecutable,
      leading: const <String>[],
    );
  }
  return (executable: resolvedExecutable, leading: ['run', script]);
}

/// How a child `qa` ended.
class ChildOutcome {
  const ChildOutcome({
    required this.exitCode,
    required this.took,
    required this.started,
  });

  final int exitCode;
  final Duration took;

  /// False when the process could not be started at all.
  final bool started;
}

/// Runs a child `qa`, teeing its output to [logPath] and handing every
/// line to [onLine] as it arrives. The child skips its own self-rebuild:
/// the parent already did it, and three children racing to compile would
/// only queue on the lock.
Future<ChildOutcome> runQaChild({
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  String? logPath,
  required void Function(String line, bool isError) onLine,
}) async {
  final started = DateTime.now();
  IOSink? log;
  if (logPath != null) {
    final file = File(logPath)..parent.createSync(recursive: true);
    log = file.openWrite();
  }
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: {noSelfRebuildEnv: '1'},
    );
  } on ProcessException catch (e) {
    log?.writeln('! cannot start $executable: ${e.message}');
    await log?.close();
    onLine('cannot start $executable: ${e.message}', true);
    return ChildOutcome(
      exitCode: exitDevice,
      took: DateTime.now().difference(started),
      started: false,
    );
  }
  unawaited(process.stdin.close());
  Future<void> pump(Stream<List<int>> stream, bool isError) => stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach((line) {
        log?.writeln(isError ? '! $line' : line);
        onLine(line, isError);
      });
  await Future.wait([pump(process.stdout, false), pump(process.stderr, true)]);
  final code = await process.exitCode;
  await log?.flush();
  await log?.close();
  return ChildOutcome(
    exitCode: code,
    took: DateTime.now().difference(started),
    started: true,
  );
}

/// Where the AVDs live: `ANDROID_AVD_HOME`, else `ANDROID_USER_HOME/avd`,
/// else `ANDROID_SDK_HOME/.android/avd`, else `~/.android/avd`.
String fleetAvdHome(Map<String, String> env, {required bool windows}) {
  String? set(String key) {
    final value = env[key];
    return value == null || value.isEmpty ? null : value;
  }

  final explicit = set('ANDROID_AVD_HOME');
  if (explicit != null) return explicit;
  final user = set('ANDROID_USER_HOME');
  if (user != null) return joinPath(user, ['avd']);
  final sdkHome = set('ANDROID_SDK_HOME');
  if (sdkHome != null) return joinPath(sdkHome, ['.android', 'avd']);
  final home = windows
      ? (set('USERPROFILE') ?? set('HOME') ?? '.')
      : (set('HOME') ?? '.');
  return joinPath(home, ['.android', 'avd']);
}

/// The SDK root above an `adb` found on PATH: `<sdk>/platform-tools/adb`.
String sdkRootFromAdb(String adbPath) {
  final parts = adbPath.split(RegExp(r'[\\/]'));
  if (parts.length < 3) return '.';
  return parts.sublist(0, parts.length - 2).join(Platform.pathSeparator);
}

/// The SDK root: the first of [SdkTools.sdkRoots] that exists, else the
/// one above the `adb` on PATH — neither `ANDROID_HOME` nor
/// `ANDROID_SDK_ROOT` is set on every machine this runs on.
String? fleetSdkRoot(SdkTools sdk) {
  for (final root in sdk.sdkRoots()) {
    if (Directory(joinPath(root, ['platform-tools'])).existsSync() ||
        Directory(joinPath(root, ['emulator'])).existsSync()) {
      return root;
    }
  }
  final adb = sdk.findAdb();
  return adb == null ? null : sdkRootFromAdb(adb);
}

/// The fleet's view of the host: the AVD directory, the SDK tools, adb
/// and the process list. Every command it runs goes through [runner].
class FleetHost {
  FleetHost({
    required this.runner,
    required this.adb,
    required this.avdHome,
    required this.sdkRoot,
    required this.windows,
    this.pollEvery = const Duration(seconds: 1),
  });

  final ProcessRunner runner;

  /// adb with no serial; [Adb.withSerial] narrows it per member.
  final Adb adb;
  final String avdHome;
  final String? sdkRoot;
  final bool windows;
  final Duration pollEvery;

  String? _sdkFile(List<String> parts) {
    final root = sdkRoot;
    if (root == null) return null;
    final path = joinPath(root, parts);
    return File(path).existsSync() ? path : null;
  }

  String? get emulatorPath =>
      _sdkFile(['emulator', windows ? 'emulator.exe' : 'emulator']);

  String? get avdmanagerPath {
    final name = windows ? 'avdmanager.bat' : 'avdmanager';
    final latest = _sdkFile(['cmdline-tools', 'latest', 'bin', name]);
    if (latest != null) return latest;
    final root = sdkRoot;
    final tools = root == null ? null : Directory(joinPath(root, ['cmdline-tools']));
    if (tools != null && tools.existsSync()) {
      final versions = tools.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final dir in versions) {
        final candidate = joinPath(dir.path, ['bin', name]);
        if (File(candidate).existsSync()) return candidate;
      }
    }
    return _sdkFile(['tools', 'bin', name]);
  }

  /// The API directories under `system-images` that hold the fleet's
  /// image flavour.
  List<String> installedImageApis() {
    final root = sdkRoot;
    if (root == null) return const [];
    final images = Directory(joinPath(root, ['system-images']));
    if (!images.existsSync()) return const [];
    return [
      for (final api in images.listSync().whereType<Directory>())
        if (Directory(joinPath(api.path, [fleetImageTag, fleetImageAbi]))
            .existsSync())
          api.uri.pathSegments.where((s) => s.isNotEmpty).last,
    ]..sort();
  }

  String configPath(String avd) => joinPath(avdHome, ['$avd.avd', 'config.ini']);

  bool isCreated(String avd) =>
      File(joinPath(avdHome, ['$avd.ini'])).existsSync() &&
      File(configPath(avd)).existsSync();

  /// Every AVD the directory holds, by its `.ini`.
  List<String> avdNames() {
    final dir = Directory(avdHome);
    if (!dir.existsSync()) return const [];
    return [
      for (final file in dir.listSync().whereType<File>())
        if (file.uri.pathSegments.last.endsWith('.ini'))
          file.uri.pathSegments.last.replaceFirst(RegExp(r'\.ini$'), ''),
    ]..sort();
  }

  /// The fleet indices that exist, in order.
  List<int> createdIndices() => [
        for (final name in avdNames())
          if (fleetIndexOf(name) case final index? when isCreated(name)) index,
      ]..sort();

  Future<RunOutcome> _powershell(String script) => runner.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        timeout: const Duration(seconds: 30),
      );

  Future<RunOutcome> _powershellEncoded(String script) => runner.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encodePowerShell(script)],
        timeout: const Duration(seconds: 40),
      );

  /// Every running qemu; with [windowStates] on Windows, each windowed
  /// one also says whether it is minimized (one more PowerShell call, so
  /// only `fleet status` asks).
  Future<List<QemuProcess>> qemuProcesses({bool windowStates = false}) async {
    final result = windows
        ? await _powershell(qemuListScript)
        : await runner.run('/bin/ps', ['-axww', '-o', 'pid=,command=']);
    final found = result.ok ? parseQemuList(result.stdout) : const <QemuProcess>[];
    if (!windowStates || !windows || found.isEmpty) return found;
    final states = await _powershellEncoded(qemuWindowScript);
    if (!states.ok) return found;
    final byPid = parseQemuWindows(states.stdout);
    return [for (final qemu in found) qemu.withWindow(byPid[qemu.pid])];
  }

  /// Minimizes [pid]'s window once it opens and returns what it then is,
  /// or null when PowerShell could not tell (and off Windows).
  Future<QemuWindow?> minimize(int pid) async {
    if (!windows) return null;
    final result = await _powershellEncoded(minimizeWindowScript(pid));
    if (!result.ok) return null;
    final lines = result.stdout.trim().split('\n');
    return QemuWindow.parse(lines.last);
  }

  Future<({int cores, int threads})?> cpuTopology() async {
    if (!windows) return null;
    final result = await _powershell(cpuTopologyScript);
    return result.ok ? parseCpuTopology(result.stdout) : null;
  }

  /// Pins [pid] to [mask] and returns the mask it reads back, or null
  /// when Windows refused.
  Future<int?> pin(int pid, int mask) async {
    final result = await _powershell(pinScript(pid, mask));
    if (!result.ok) return null;
    return int.tryParse(result.stdout.trim(), radix: 16);
  }

  Future<String?> avdNameOn(String serial) async {
    final result = await adb.withSerial(serial).raw(emuAvdNameArgs);
    return result.ok ? parseEmuAvdName(result.stdout) : null;
  }

  /// Applies [fleetKeepAwakeCommands] on [serial], refusing any serial
  /// outside the fleet's ports so the owner's emulator keeps its own
  /// display settings.
  Future<void> keepAwake(String serial) async {
    if (fleetIndexOfSerial(serial) == null) {
      throw UsageFailure('$serial is not a fleet serial — its display '
          'settings are left alone');
    }
    final device = adb.withSerial(serial);
    for (final command in fleetKeepAwakeCommands) {
      await device.shell(command);
    }
  }

  /// Fleet AVDs 1 to [upTo] (and any created beyond it), each with its
  /// state, qemu and install record.
  Future<List<FleetMember>> members({
    required int upTo,
    required QaPaths paths,
    List<AdbDevice>? devices,
    List<QemuProcess>? qemus,
  }) async {
    final attached = devices ?? await adb.devices();
    final processes = qemus ?? await qemuProcesses();
    final created = createdIndices();
    final count = math.max(upTo, created.isEmpty ? 0 : created.last);
    final members = <FleetMember>[];
    for (var index = 1; index <= count; index++) {
      final name = fleetName(index);
      final serial = fleetSerial(index);
      final row = attached.where((d) => d.serial == serial).firstOrNull;
      String? heldBy;
      bool? bootCompleted;
      if (row != null && row.usable) {
        final reported = await avdNameOn(serial);
        if (reported != name) {
          heldBy = reported ?? 'an emulator that does not name its AVD';
        } else {
          final props = await adb
              .withSerial(serial)
              .shellLenient(['getprop', 'sys.boot_completed']);
          bootCompleted = props.trim() == '1';
        }
      }
      final qemu = processes.where((q) => q.avd == name).firstOrNull;
      members.add(FleetMember(
        index: index,
        created: created.contains(index),
        state: fleetStateOf(
          created: created.contains(index),
          adbState: row?.state,
          bootCompleted: bootCompleted,
          qemuAlive: qemu != null,
        ),
        qemu: qemu,
        installed: ApkRecord.read(paths.installedJsonFor(serial)),
        heldBy: heldBy,
        launches: FleetLaunches.read(paths.launchesJsonFor(serial)),
      ));
    }
    return members;
  }

  /// [members] with each running qemu's GPU counter filled in, in one
  /// PowerShell call; unchanged off Windows or when the counter is unread.
  Future<List<FleetMember>> withGpu(List<FleetMember> members) async {
    final pids = [for (final m in members) ?m.qemu?.pid];
    if (!windows || pids.isEmpty) return members;
    final result = await _powershell(gpuMemoryScript(pids));
    if (!result.ok) return members;
    final byPid = parseGpuMemory(result.stdout);
    return [
      for (final m in members) m.qemu == null ? m : m.withGpu(byPid[m.qemu!.pid]),
    ];
  }

  /// [pid]'s CPU seconds so far, or null off Windows or once it is gone.
  Future<double?> cpuSeconds(int pid) async {
    if (!windows) return null;
    final result = await _powershell(cpuSecondsScript(pid));
    return result.ok ? double.tryParse(result.stdout.trim()) : null;
  }

  /// Makes fleet AVD [index] when it is missing, or reports (and with
  /// [retune] rewrites) how an existing one differs from the spec.
  /// [image] is only needed for a missing AVD.
  Future<String> create(
    int index, {
    required bool retune,
    required String? Function() image,
  }) async {
    final name = fleetName(index);
    if (isCreated(name)) {
      final file = File(configPath(name));
      final text = file.readAsStringSync();
      final lines = splitConfig(text);
      final drift = configDrift(lines);
      if (drift.isEmpty) return 'exists: $name — matches the fleet spec';
      if (!retune) {
        return 'exists: $name — differs from the fleet spec: '
            '${drift.join(', ')}; `--retune` writes the spec';
      }
      file.writeAsStringSync(
        joinConfig(tuneConfig(lines), crlf: text.contains('\r\n')),
      );
      return 'retuned: $name — ${drift.join(', ')}';
    }
    final package = image();
    if (package == null) {
      throw DeviceFailure('no system image to create $name from');
    }
    final avdmanager = avdmanagerPath ??
        (throw DeviceFailure(
          'avdmanager not found under ${sdkRoot ?? 'the Android SDK'} '
          '(cmdline-tools/latest/bin) — install the command-line tools',
        ));
    final started = DateTime.now();
    final result = await runner.run(
      avdmanager,
      avdCreateArgs(name, package),
      stdin: avdCreateStdin,
      timeout: const Duration(minutes: 3),
    );
    if (!result.ok || !isCreated(name)) {
      throw DeviceFailure(
        'avdmanager could not create $name (exit ${result.exitCode}):\n'
        '${result.combined}',
      );
    }
    final file = File(configPath(name));
    final text = file.readAsStringSync();
    file.writeAsStringSync(
      joinConfig(tuneConfig(splitConfig(text)), crlf: text.contains('\r\n')),
    );
    final seconds = DateTime.now().difference(started).inSeconds;
    return 'created: $name — $package, $fleetDeviceProfile, fleet spec '
        'written ($seconds s)';
  }

  /// Stops fleet AVD [index] through its console, only after the console
  /// says it runs that AVD, and waits until adb and the process list no
  /// longer show it.
  Future<String> stop(int index, {Duration timeout = const Duration(seconds: 60)}) async {
    final name = fleetName(index);
    final serial = fleetSerial(index);
    final started = DateTime.now();
    final row = (await adb.devices()).where((d) => d.serial == serial).firstOrNull;
    if (row == null) {
      final qemu = (await qemuProcesses()).where((q) => q.avd == name).firstOrNull;
      if (qemu != null) {
        throw DeviceFailure('$name (qemu ${qemu.pid}) is still coming up and '
            'not on adb yet — stop it once `qa fleet status` shows it, or, '
            'when it is hung, `qa fleet stop $name --force`');
      }
      return 'stopped: $name was not running';
    }
    final refusal = stopRefusal(
      expected: name,
      serial: serial,
      reported: await avdNameOn(serial),
    );
    if (refusal != null) throw DeviceFailure(refusal);
    final kill = await adb.withSerial(serial).raw(emuKillArgs);
    if (!kill.ok) {
      throw DeviceFailure('adb -s $serial emu kill failed: ${kill.combined}');
    }
    final deadline = started.add(timeout);
    var gone = false;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollEvery);
      if ((await adb.devices()).any((d) => d.serial == serial)) continue;
      if ((await qemuProcesses()).any((q) => q.avd == name)) continue;
      gone = true;
      break;
    }
    if (!gone) {
      throw DeviceFailure('$name was asked to stop but $serial is still '
          'there after ${timeout.inSeconds} s');
    }
    final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
    return 'stopped: $name ($serial) in ${seconds.toStringAsFixed(1)} s';
  }

  /// `fleet stop --force`: a hung guest (`detected a hanging thread 'QEMU2
  /// main loop'`) is off adb and never answers its console, and its
  /// crash-report window keeps the next boot from starting, so its qemu is
  /// killed — only when adb does not list it as usable, and only after the
  /// process's own command line names this AVD on its fleet port. The one
  /// process kill the fleet does; a guest adb lists goes the console way.
  Future<String> forceStop(int index, {Duration timeout = const Duration(seconds: 60)}) async {
    final name = fleetName(index);
    final serial = fleetSerial(index);
    final row = (await adb.devices()).where((d) => d.serial == serial).firstOrNull;
    if (row != null && row.usable) return stop(index, timeout: timeout);
    final qemu = (await qemuProcesses()).where((q) => q.avd == name).firstOrNull;
    if (qemu == null) return 'stopped: $name was not running';
    final refusal = forceStopRefusal(qemu, index);
    if (refusal != null) throw DeviceFailure(refusal);
    final started = DateTime.now();
    if (windows) {
      final result = await _powershell(forceStopScript(qemu.pid, name));
      final said = result.stdout.trim();
      if (said == 'mismatch') {
        throw DeviceFailure('qemu ${qemu.pid} no longer names $name — left running');
      }
      if (!result.ok || (said != 'killed' && said != 'gone')) {
        throw DeviceFailure('could not kill qemu ${qemu.pid} of $name: '
            '${result.combined.isEmpty ? 'exit ${result.exitCode}' : result.combined}');
      }
    } else {
      final again = (await qemuProcesses()).where((q) => q.pid == qemu.pid).firstOrNull;
      if (again == null) return 'stopped: $name was not running';
      final stillRefused = forceStopRefusal(again, index);
      if (stillRefused != null) throw DeviceFailure(stillRefused);
      Process.killPid(qemu.pid, ProcessSignal.sigkill);
    }
    final deadline = started.add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!(await qemuProcesses()).any((q) => q.avd == name)) {
        final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
        return 'stopped: $name (qemu ${qemu.pid} killed, it was not on adb) '
            'in ${seconds.toStringAsFixed(1)} s';
      }
      await Future<void>.delayed(pollEvery);
    }
    throw DeviceFailure('qemu ${qemu.pid} of $name was killed but is still '
        'listed after ${timeout.inSeconds} s');
  }
}
