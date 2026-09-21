import '../../qa/src/adb.dart';
import '../../qa/src/app_ids.dart';
import 'errors.dart';
import 'signing.dart';

/// Why `adb install` said no, as far as its output tells.
enum InstallProblem {
  signatureMismatch,
  versionDowngrade,
  insufficientStorage,
  userRestricted,
  deviceGone,
  unknown,
}

InstallProblem classifyInstallFailure(String output) {
  final text = output.toUpperCase();
  if (text.contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE') ||
      text.contains('SIGNATURES DO NOT MATCH') ||
      text.contains('INSTALL_FAILED_SHARED_USER_INCOMPATIBLE')) {
    return InstallProblem.signatureMismatch;
  }
  if (text.contains('INSTALL_FAILED_VERSION_DOWNGRADE')) {
    return InstallProblem.versionDowngrade;
  }
  if (text.contains('INSTALL_FAILED_INSUFFICIENT_STORAGE')) {
    return InstallProblem.insufficientStorage;
  }
  if (text.contains('INSTALL_FAILED_USER_RESTRICTED')) {
    return InstallProblem.userRestricted;
  }
  if (text.contains('DEVICE OFFLINE') ||
      text.contains('DEVICE NOT FOUND') ||
      text.contains('NO DEVICES/EMULATORS FOUND') ||
      text.contains('DEVICE UNAUTHORIZED')) {
    return InstallProblem.deviceGone;
  }
  return InstallProblem.unknown;
}

/// Turns a failed install into the sentence that says what to do.
String installFailureMessage(
  InstallProblem problem, {
  required String serial,
  required String output,
}) {
  final said = output.trim().isEmpty ? '' : ' adb said: ${output.trim()}';
  return switch (problem) {
    InstallProblem.signatureMismatch => 'the APK is signed with a different '
        'key than the $antaPackage already on $serial, so Android refuses '
        'it.$said\nEither this machine has no release keystore and built a '
        'debug-signed APK (run `release doctor`), or its keystore is not the '
        'one that built the installed app. $signingRemedy',
    InstallProblem.versionDowngrade => 'the installed $antaPackage has a '
        'higher versionCode than this APK; raise the build number in '
        'pubspec.yaml (version: x.y.z+N).$said',
    InstallProblem.insufficientStorage =>
      '$serial has no room for the APK.$said',
    InstallProblem.userRestricted => '$serial blocks installs over USB; on '
        'MIUI enable "Install via USB" under Developer options.$said',
    InstallProblem.deviceGone =>
      '$serial went away during the install.$said',
    InstallProblem.unknown => 'adb install failed on $serial.$said',
  };
}

bool isEmulatorSerial(String serial) => serial.startsWith('emulator-');

/// Picks the device to install on: an explicit serial, else the only usable
/// phone, else the only usable device of any kind.
///
/// A phone beats an emulator that happens to be running, because that is what
/// "install to device" means here; two phones need `-d`.
String selectInstallSerial({
  String? explicit,
  required List<AdbDevice> devices,
}) {
  if (explicit != null && explicit.isNotEmpty) {
    final matches = devices.where((d) => d.serial == explicit).toList();
    if (matches.isEmpty) {
      throw DeviceFailure('$explicit is not attached. ${_attached(devices)}');
    }
    if (!matches.single.usable) {
      throw DeviceFailure(
        unusableDeviceMessage(explicit, matches.single.state),
      );
    }
    return explicit;
  }
  final usable = devices.where((d) => d.usable).toList();
  final phones = usable.where((d) => !isEmulatorSerial(d.serial)).toList();
  final pool = phones.isNotEmpty ? phones : usable;
  if (pool.length == 1) return pool.single.serial;
  if (pool.length > 1) {
    throw DeviceFailure(
      'more than one device attached; pass -d <serial>. '
      'Attached: ${pool.map((d) => d.serial).join(', ')}',
    );
  }
  if (devices.isEmpty) {
    throw DeviceFailure(
      'no device attached — plug the phone in with USB debugging on',
    );
  }
  throw DeviceFailure(
    devices.map((d) => unusableDeviceMessage(d.serial, d.state)).join('; '),
  );
}

String _attached(List<AdbDevice> devices) => devices.isEmpty
    ? 'Nothing is attached.'
    : 'Attached: ${devices.map((d) => '${d.serial} (${d.state})').join(', ')}.';
