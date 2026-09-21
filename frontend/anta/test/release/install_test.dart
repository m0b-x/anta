import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/release/src/install.dart';

const String _mismatch = 'adb: failed to install app-release.apk: Failure '
    '[INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package com.alexzamfir.anta '
    'signatures do not match newer version; ignoring!]';

void main() {
  group('classifyInstallFailure', () {
    test('a signature mismatch is the Mac-built APK over the Windows app', () {
      expect(classifyInstallFailure(_mismatch), InstallProblem.signatureMismatch);
    });

    test('the other adb verdicts map one to one', () {
      expect(
        classifyInstallFailure('Failure [INSTALL_FAILED_VERSION_DOWNGRADE]'),
        InstallProblem.versionDowngrade,
      );
      expect(
        classifyInstallFailure('Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]'),
        InstallProblem.insufficientStorage,
      );
      expect(
        classifyInstallFailure(
          'Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]',
        ),
        InstallProblem.userRestricted,
      );
      expect(
        classifyInstallFailure('adb: error: device offline'),
        InstallProblem.deviceGone,
      );
      expect(classifyInstallFailure('something else'), InstallProblem.unknown);
    });
  });

  test('the signature message names the files to copy and the data loss', () {
    final message = installFailureMessage(
      InstallProblem.signatureMismatch,
      serial: 'R58M',
      output: _mismatch,
    );
    expect(message, contains('android/key.properties'));
    expect(message, contains('release-keystore.jks'));
    expect(message, contains('wipe'));
    expect(message, contains('R58M'));
    expect(message, contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
  });

  test('an empty adb output adds no "adb said"', () {
    expect(
      installFailureMessage(InstallProblem.unknown, serial: 'X', output: ' '),
      'adb install failed on X.',
    );
  });

  group('selectInstallSerial', () {
    final phoneAndEmulator = parseDevices(
      'List of devices attached\n'
      'emulator-5554\tdevice product:sdk model:sdk_gphone64_x86_64\n'
      'R58M12345\tdevice product:a54 model:SM_A546B\n',
    );

    test('a phone wins over a running emulator', () {
      expect(selectInstallSerial(devices: phoneAndEmulator), 'R58M12345');
    });

    test('an emulator alone is fine', () {
      expect(
        selectInstallSerial(
          devices: parseDevices('List of devices attached\nemulator-5554\tdevice\n'),
        ),
        'emulator-5554',
      );
    });

    test('two phones need -d', () {
      expect(
        () => selectInstallSerial(
          devices: parseDevices('List of devices attached\nA\tdevice\nB\tdevice\n'),
        ),
        throwsA(
          isA<DeviceFailure>()
              .having((e) => e.message, 'message', contains('-d <serial>')),
        ),
      );
    });

    test('an explicit serial must be attached and usable', () {
      expect(
        selectInstallSerial(explicit: 'emulator-5554', devices: phoneAndEmulator),
        'emulator-5554',
      );
      expect(
        () => selectInstallSerial(explicit: 'nope', devices: phoneAndEmulator),
        throwsA(isA<DeviceFailure>()),
      );
      expect(
        () => selectInstallSerial(
          explicit: 'X',
          devices: parseDevices('List of devices attached\nX\tunauthorized\n'),
        ),
        throwsA(
          isA<DeviceFailure>()
              .having((e) => e.message, 'message', contains('unauthorized')),
        ),
      );
    });

    test('nothing attached says to plug the phone in', () {
      expect(
        () => selectInstallSerial(devices: const []),
        throwsA(
          isA<DeviceFailure>()
              .having((e) => e.message, 'message', contains('USB debugging')),
        ),
      );
    });
  });
}
