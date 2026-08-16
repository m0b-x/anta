import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Single gate deciding whether cloud sync can run on this platform.
///
/// `google_sign_in` ships no Windows or Linux implementation, so the sign-in
/// path cannot work there regardless of what the Firebase plugins support.
/// Everything sync-related routes through here rather than testing the
/// platform itself, so desktop stays local-only in exactly one place.
///
/// [kIsWeb] is checked first because `dart:io`'s [Platform] throws on web.
abstract final class SyncAvailability {
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
