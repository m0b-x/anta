/// Exit code for a usage problem (bad arguments, unknown verb).
const int exitUsage = 1;

/// Exit code for a target that could not be resolved, or resolved ambiguously.
const int exitTarget = 2;

/// Exit code for a device, adb or emulator failure.
const int exitDevice = 3;

class QaException implements Exception {
  QaException(this.message, this.code);

  final String message;
  final int code;

  @override
  String toString() => message;
}

class UsageFailure extends QaException {
  UsageFailure(String message) : super(message, exitUsage);
}

class DeviceFailure extends QaException {
  DeviceFailure(String message) : super(message, exitDevice);
}

class TargetFailure extends QaException {
  TargetFailure(String message) : super(message, exitTarget);
}

class UnsupportedOnPlatform extends QaException {
  UnsupportedOnPlatform(String what, String platform, {String? instead})
      : super(
          '$what is not available on $platform'
          '${instead == null ? '' : ' — $instead'}',
          exitUsage,
        );
}
