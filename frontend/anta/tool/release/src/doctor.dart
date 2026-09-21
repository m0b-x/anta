import '../../qa/src/adb.dart';
import '../../qa/src/doctor.dart';
import 'gradle_daemons.dart';
import 'signing.dart';

export '../../qa/src/doctor.dart' show CheckResult, CheckStatus, anyFailed;

/// A launcher the pipeline needs was located.
CheckResult checkTool(String name, String? path, {required String fix}) =>
    path == null
        ? CheckResult(
            name: name,
            status: CheckStatus.fail,
            detail: 'not found',
            fix: fix,
          )
        : CheckResult.ok(name, path);

/// A release build would be signed with the release keystore.
CheckResult checkSigning(SigningStatus status) => status.ready
    ? CheckResult.ok('signing', status.describe())
    : CheckResult(
        name: 'signing',
        status: CheckStatus.fail,
        detail: status.describe(),
        fix: signingRemedy,
      );

/// The gitignored Firebase files are in place.
CheckResult checkFirebaseConfig(List<String> missing) => missing.isEmpty
    ? const CheckResult.ok(
        'firebase config',
        'google-services.json and firebase_options.dart present',
      )
    : CheckResult(
        name: 'firebase config',
        status: CheckStatus.fail,
        detail: 'missing ${missing.join(', ')}',
        fix: 'run `flutterfire configure --platforms=android,ios` (the files '
            'are gitignored), or copy them from another checkout',
      );

/// No Gradle daemon of another version is sitting on build/.
CheckResult checkGradleDaemons({
  required String? wrapperVersion,
  required List<GradleDaemon> daemons,
}) {
  final stale = staleDaemons(daemons, keepVersion: wrapperVersion);
  final version = wrapperVersion ?? '?';
  if (stale.isEmpty) {
    return CheckResult.ok(
      'gradle daemons',
      daemons.isEmpty
          ? 'none running (wrapper is Gradle $version)'
          : '${daemons.length} running, all Gradle $version',
    );
  }
  return CheckResult(
    name: 'gradle daemons',
    status: CheckStatus.warn,
    detail: '${stale.length} of ${daemons.length} serve another Gradle than '
        "the wrapper's $version (pid ${stale.map((d) => d.pid).join(', ')}); "
        'they keep build/ files open and make the next R8 pass fail',
    fix: '`release doctor --fix` stops them (`release build` does so too)',
  );
}

/// Something is attached for `release install`; a warning only, since
/// `release build` needs no device.
CheckResult checkInstallTarget(List<AdbDevice> devices) {
  final usable = devices.where((d) => d.usable).toList();
  if (usable.isNotEmpty) {
    return CheckResult.ok(
      'device',
      usable
          .map((d) => '${d.serial}${d.model == null ? '' : ' (${d.model})'}')
          .join(', '),
    );
  }
  return CheckResult(
    name: 'device',
    status: CheckStatus.warn,
    detail: devices.isEmpty
        ? 'nothing attached'
        : devices.map((d) => '${d.serial} ${d.state}').join(', '),
    fix: 'only `release install` needs one: plug the phone in with USB '
        'debugging on',
  );
}

/// No Explorer window is parked inside build/ (Windows only).
CheckResult checkExplorerWindows(int count) => count == 0
    ? const CheckResult.ok('explorer windows', 'none under build\\')
    : CheckResult(
        name: 'explorer windows',
        status: CheckStatus.warn,
        detail: '$count open under build\\, which stops `flutter clean` from '
            'removing it',
        fix: 'close them, or let `release build --clean` do it',
      );
