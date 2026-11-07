import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/android_alert_gateway.dart';

/// A release build shrinks resources, and the shrinker only sees references
/// made from Android code and XML. Every alert finds its icon by name, at run
/// time, so without a `tools:keep` entry nothing the shrinker can see holds
/// it for them. On 2026-09-21, when nothing else named it either, it was
/// dropped from the APK — and `FlutterLocalNotificationsPlugin.initialize`
/// then threw `invalid_icon` before a channel was created or an alarm
/// scheduled. Debug builds do not shrink, which is why the emulator pass was
/// green while the phone stayed silent. The Quick Settings tile and the
/// launcher shortcut have named the drawable as a resource since, and the
/// alerts must not lean on those two staying as they are.
///
/// On 2026-11-07 the same shrinker took `default_web_client_id`, which
/// google_sign_in_android finds with `getIdentifier`, and every release build
/// failed Google sign-in with "Sign-in failed" before Android was asked for an
/// account. The app's keep list had been called `raw/keep.xml`, the name the
/// plugin uses for its own, and an app resource overrides a library's of the
/// same name.
void main() {
  const resDir = 'android/app/src/main/res';
  const keepPath = '$resDir/raw/anta_keep.xml';

  test('the alert icon exists as a drawable', () {
    expect(File('$resDir/drawable/$kAlertSmallIcon.xml').existsSync(), isTrue);
  });

  test('the alert icon is kept through release resource shrinking', () {
    final keep = File(keepPath);

    expect(keep.existsSync(), isTrue);
    expect(keep.readAsStringSync(), contains('@drawable/$kAlertSmallIcon'));
  });

  test('the Google web client id is kept through release resource '
      'shrinking', () {
    expect(
      File(keepPath).readAsStringSync(),
      contains('@string/default_web_client_id'),
    );
  });

  test('the app has no raw/keep.xml to shadow its dependencies\' keep '
      'lists', () {
    expect(File('$resDir/raw/keep.xml').existsSync(), isFalse);
  });
}
