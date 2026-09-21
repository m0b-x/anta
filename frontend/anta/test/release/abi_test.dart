import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/src/abi.dart';
import '../../tool/release/src/errors.dart';

void main() {
  group('TargetAbi.parse', () {
    test('accepts flag spellings, ABI names and Flutter platform names', () {
      expect(TargetAbi.parse('arm64'), TargetAbi.arm64);
      expect(TargetAbi.parse('arm64-v8a'), TargetAbi.arm64);
      expect(TargetAbi.parse('android-arm64'), TargetAbi.arm64);
      expect(TargetAbi.parse('ARM'), TargetAbi.arm);
      expect(TargetAbi.parse('x86_64'), TargetAbi.x64);
      expect(TargetAbi.parse(' all '), TargetAbi.all);
    });

    test('rejects anything else as a usage error', () {
      expect(() => TargetAbi.parse('mips'), throwsA(isA<UsageFailure>()));
    });
  });

  group('TargetAbi.fromDeviceAbi', () {
    test('maps what getprop reports', () {
      expect(TargetAbi.fromDeviceAbi('arm64-v8a\n'), TargetAbi.arm64);
      expect(TargetAbi.fromDeviceAbi('armeabi-v7a'), TargetAbi.arm);
      expect(TargetAbi.fromDeviceAbi('x86_64'), TargetAbi.x64);
    });

    test('has no answer for 32-bit x86', () {
      expect(TargetAbi.fromDeviceAbi('x86'), isNull);
    });
  });

  test('only a narrowed ABI adds --target-platform', () {
    expect(TargetAbi.all.buildFlags, isEmpty);
    expect(TargetAbi.arm64.buildFlags, ['--target-platform', 'android-arm64']);
    expect(TargetAbi.x64.buildFlags, ['--target-platform', 'android-x64']);
  });
}
