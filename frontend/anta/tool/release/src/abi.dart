import 'errors.dart';

/// Which Android ABIs the APK carries.
enum TargetAbi {
  all(null, 'all ABIs'),
  arm64('android-arm64', 'arm64-v8a'),
  arm('android-arm', 'armeabi-v7a'),
  x64('android-x64', 'x86_64');

  const TargetAbi(this.targetPlatform, this.label);

  /// The `--target-platform` value, or null for a fat APK.
  final String? targetPlatform;

  final String label;

  List<String> get buildFlags => targetPlatform == null
      ? const []
      : ['--target-platform', targetPlatform!];

  /// Accepts the flag spellings, the ABI names and Flutter's platform names.
  static TargetAbi parse(String value) => switch (value.trim().toLowerCase()) {
        'all' || 'fat' => TargetAbi.all,
        'arm64' || 'arm64-v8a' || 'android-arm64' => TargetAbi.arm64,
        'arm' || 'arm32' || 'armeabi-v7a' || 'android-arm' => TargetAbi.arm,
        'x64' || 'x86_64' || 'android-x64' => TargetAbi.x64,
        _ => throw UsageFailure(
            'unknown --abi "$value" (expected all, arm64, arm or x64)',
          ),
      };

  /// Maps `ro.product.cpu.abi` as adb reports it; null when Flutter has no
  /// build for it.
  static TargetAbi? fromDeviceAbi(String abi) => switch (abi.trim()) {
        'arm64-v8a' => TargetAbi.arm64,
        'armeabi-v7a' || 'armeabi' => TargetAbi.arm,
        'x86_64' => TargetAbi.x64,
        _ => null,
      };
}
