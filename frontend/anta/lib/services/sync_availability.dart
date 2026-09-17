import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/qa/qa_mode.dart';

/// Single gate deciding whether cloud sync can run on this platform.
///
/// `google_sign_in` ships no Windows or Linux implementation, so the sign-in
/// path cannot work there regardless of what the Firebase plugins support.
/// Everything sync-related routes through here rather than testing the
/// platform itself, so desktop stays local-only in exactly one place.
///
/// A QA build is local-only too unless it opts in: identity is global to the
/// install, so an automation run must not inherit the owner's session.
///
/// [kIsWeb] is checked first because `dart:io`'s [Platform] throws on web.
abstract final class SyncAvailability {
  static bool get isSupported => resolve(
        web: kIsWeb,
        phone: !kIsWeb && (Platform.isAndroid || Platform.isIOS),
        qaBuild: QaMode.enabled,
        qaAllowsCloud: QaMode.allowCloud,
      );

  static bool resolve({
    required bool web,
    required bool phone,
    required bool qaBuild,
    required bool qaAllowsCloud,
  }) {
    if (web || !phone) return false;
    return !qaBuild || qaAllowsCloud;
  }
}
