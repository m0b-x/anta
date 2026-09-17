import 'adb.dart';
import 'errors.dart';
import 'simctl.dart';

enum DeviceKind { android, ios, macos }

extension DeviceKindLabel on DeviceKind {
  String get label => switch (this) {
        DeviceKind.android => 'android',
        DeviceKind.ios => 'ios',
        DeviceKind.macos => 'macos',
      };
}

const String macosDeviceId = 'macos';

class DeviceRef {
  const DeviceRef({required this.kind, required this.id, required this.label});

  final DeviceKind kind;
  final String id;
  final String label;

  @override
  String toString() => '$id ($label)';
}

DeviceRef selectDevice({
  String? explicit,
  String? envValue,
  required List<AdbDevice> adbDevices,
  required List<SimDevice> simulators,
  required bool hostIsMac,
}) {
  final wanted = _firstNonEmpty(explicit, envValue);
  if (wanted != null) {
    return _selectExplicit(
      wanted,
      adbDevices: adbDevices,
      simulators: simulators,
      hostIsMac: hostIsMac,
    );
  }
  final booted = simulators.where((s) => s.booted).toList();
  final usable = adbDevices.where((d) => d.usable).toList();
  final candidates = <DeviceRef>[
    for (final d in usable) _androidRef(d),
    for (final s in booted) _iosRef(s),
  ];
  if (candidates.length == 1) return candidates.single;
  if (candidates.length > 1) {
    throw DeviceFailure(
      'more than one device attached; pass -d/--device or set ANTA_QA_DEVICE. '
      'Attached: ${candidates.map((c) => c.id).join(', ')}',
    );
  }
  final unusable = adbDevices.where((d) => !d.usable).toList();
  if (unusable.isNotEmpty) {
    throw DeviceFailure(
      unusable.map((d) => unusableDeviceMessage(d.serial, d.state)).join('; '),
    );
  }
  throw DeviceFailure(
    'no device attached — run `qa boot`'
    '${hostIsMac ? ' (an iOS simulator, or an AVD with --avd), or pass -d macos for the desktop app' : ''}',
  );
}

DeviceRef _selectExplicit(
  String wanted, {
  required List<AdbDevice> adbDevices,
  required List<SimDevice> simulators,
  required bool hostIsMac,
}) {
  final lower = wanted.toLowerCase();
  if (lower == macosDeviceId) {
    if (!hostIsMac) {
      throw DeviceFailure('the macOS desktop app can only be driven from a Mac');
    }
    return const DeviceRef(
      kind: DeviceKind.macos,
      id: macosDeviceId,
      label: 'macOS desktop',
    );
  }
  if (lower == 'ios') {
    final booted = simulators.where((s) => s.booted).toList();
    if (booted.length == 1) return _iosRef(booted.single);
    if (booted.isEmpty) {
      throw DeviceFailure(
        'no iOS simulator is booted — run `qa boot`'
        '${simulators.isEmpty ? '' : ' (installed: ${simulators.map((s) => s.name).join(', ')})'}',
      );
    }
    throw DeviceFailure(
      'more than one simulator is booted; pass its name or UDID: '
      '${booted.map((s) => '${s.name} (${s.udid})').join(', ')}',
    );
  }
  if (lower == 'android') {
    final usable = adbDevices.where((d) => d.usable).toList();
    if (usable.length == 1) return _androidRef(usable.single);
    return _androidRef(AdbDevice(
      selectSerial(available: adbDevices),
      'device',
      null,
    ));
  }
  for (final device in adbDevices) {
    if (device.serial == wanted) {
      return _androidRef(AdbDevice(
        selectSerial(explicit: wanted, available: adbDevices),
        device.state,
        device.model,
      ));
    }
  }
  final byUdid = simulators.where((s) => s.udid.toLowerCase() == lower).toList();
  final byName = simulators.where((s) => s.name.toLowerCase() == lower).toList();
  final matches = byUdid.isNotEmpty ? byUdid : byName;
  if (matches.isNotEmpty) {
    final booted = matches.where((s) => s.booted).toList();
    if (booted.length == 1) return _iosRef(booted.single);
    if (booted.isEmpty) {
      throw DeviceFailure(
        '${matches.first.name} (${matches.first.udid}) is ${matches.first.state} '
        '— run `qa boot --sim "${matches.first.name}"`',
      );
    }
    throw DeviceFailure(
      '"$wanted" names ${booted.length} booted simulators; pass the UDID: '
      '${booted.map((s) => s.udid).join(', ')}',
    );
  }
  if (adbDevices.isEmpty && simulators.isEmpty) {
    throw DeviceFailure('$wanted is not attached. Nothing is attached — run `qa boot`.');
  }
  throw DeviceFailure(
    '$wanted is not attached. Attached: '
    '${[
      ...adbDevices.map((d) => '${d.serial} (${d.state})'),
      ...simulators.where((s) => s.booted).map((s) => '${s.name} (${s.udid})'),
    ].join(', ')}'
    '${hostIsMac ? '; the desktop app is `-d macos`' : ''}',
  );
}

DeviceRef _androidRef(AdbDevice device) => DeviceRef(
      kind: DeviceKind.android,
      id: device.serial,
      label: device.model == null ? 'Android' : 'Android ${device.model}',
    );

DeviceRef _iosRef(SimDevice sim) => DeviceRef(
      kind: DeviceKind.ios,
      id: sim.udid,
      label: '${sim.name} (${sim.runtime})',
    );

String? _firstNonEmpty(String? a, String? b) {
  if (a != null && a.isNotEmpty) return a;
  if (b != null && b.isNotEmpty) return b;
  return null;
}

List<String> describeDevices({
  required List<AdbDevice> adbDevices,
  required List<SimDevice> simulators,
  required bool hostIsMac,
  bool all = false,
  String? macosBuilt,
}) {
  final lines = <String>[];
  for (final device in adbDevices) {
    lines.add('android  ${device.serial.padRight(38)}  ${device.state.padRight(9)}'
        '${device.model == null ? '' : '  model:${device.model}'}');
  }
  for (final sim in simulators) {
    if (!all && !sim.booted) continue;
    lines.add('ios      ${sim.udid.padRight(38)}  ${sim.state.padRight(9)}  '
        '${sim.name} (${sim.runtime})');
  }
  if (hostIsMac) {
    lines.add('macos    ${macosDeviceId.padRight(38)}  ${'desktop'.padRight(9)}  '
        'pass -d macos${macosBuilt == null ? '' : '  ($macosBuilt)'}');
  }
  return lines;
}
