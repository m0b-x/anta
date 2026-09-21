import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/release/src/doctor.dart';
import '../../tool/release/src/gradle_daemons.dart';
import '../../tool/release/src/signing.dart';

const String _complete = 'storePassword=pw\nkeyPassword=pw\nkeyAlias=anta\n'
    'storeFile=release-keystore.jks\n';

void main() {
  group('checkSigning', () {
    test('a missing keystore fails with the copy remedy', () {
      final result = checkSigning(signingStatus(
        propertiesText: null,
        appModuleDir: 'app',
        exists: (_) => true,
      ));
      expect(result.status, CheckStatus.fail);
      expect(result.fix, contains('release-keystore.jks'));
    });

    test('a ready keystore passes and names the alias', () {
      final result = checkSigning(signingStatus(
        propertiesText: _complete,
        appModuleDir: 'app',
        exists: (_) => true,
      ));
      expect(result.status, CheckStatus.ok);
      expect(result.detail, contains('alias anta'));
    });
  });

  test('checkFirebaseConfig names the missing file and flutterfire', () {
    expect(checkFirebaseConfig(const []).status, CheckStatus.ok);
    final result = checkFirebaseConfig(const ['lib/firebase_options.dart']);
    expect(result.status, CheckStatus.fail);
    expect(result.detail, contains('lib/firebase_options.dart'));
    expect(result.fix, contains('flutterfire configure'));
  });

  test('checkGradleDaemons warns only about other versions', () {
    const current = GradleDaemon(
      1,
      '/x/gradle-9.3.1/lib/gradle-daemon-main-9.3.1.jar GradleDaemon',
    );
    const old = GradleDaemon(
      2,
      '/x/gradle-8.14/lib/gradle-daemon-main-8.14.jar GradleDaemon',
    );
    expect(
      checkGradleDaemons(wrapperVersion: '9.3.1', daemons: const [current]).status,
      CheckStatus.ok,
    );
    final warn =
        checkGradleDaemons(wrapperVersion: '9.3.1', daemons: const [current, old]);
    expect(warn.status, CheckStatus.warn);
    expect(warn.detail, contains('pid 2'));
    expect(warn.fix, contains('--fix'));
    expect(
      checkGradleDaemons(wrapperVersion: '9.3.1', daemons: const []).detail,
      contains('none running'),
    );
  });

  test('checkInstallTarget: attached is ok, nothing attached only warns', () {
    final attached = checkInstallTarget(parseDevices(
      'List of devices attached\nR58M\tdevice product:a54 model:SM_A546B\n',
    ));
    expect(attached.status, CheckStatus.ok);
    expect(attached.detail, 'R58M (SM_A546B)');
    final none = checkInstallTarget(const []);
    expect(none.status, CheckStatus.warn);
    expect(none.fix, contains('release install'));
    final wedged = checkInstallTarget(parseDevices('R58M\tunauthorized\n'));
    expect(wedged.status, CheckStatus.warn);
    expect(wedged.detail, 'R58M unauthorized');
  });

  test('checkExplorerWindows counts the windows that block a clean', () {
    expect(checkExplorerWindows(0).status, CheckStatus.ok);
    final open = checkExplorerWindows(2);
    expect(open.status, CheckStatus.warn);
    expect(open.detail, startsWith('2 open'));
  });

  test('checkTool fails with the given fix when the launcher is missing', () {
    expect(checkTool('flutter', '/sdk/bin/flutter', fix: 'x').status, CheckStatus.ok);
    final missing = checkTool('flutter', null, fix: 'add it to PATH');
    expect(missing.status, CheckStatus.fail);
    expect(missing.fix, 'add it to PATH');
  });
}
