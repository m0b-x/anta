import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/android_alert_gateway.dart';

/// A release build shrinks resources, and the shrinker only sees references
/// made from Android code and XML. The alert icon is named from Dart alone, so
/// without a `tools:keep` entry it is dropped from the APK — and
/// `FlutterLocalNotificationsPlugin.initialize` then throws `invalid_icon`
/// before a channel is created or an alarm scheduled. Debug builds do not
/// shrink, which is why the emulator pass was green while the phone stayed
/// silent (2026-09-21).
void main() {
  const resDir = 'android/app/src/main/res';

  test('the alert icon exists as a drawable', () {
    expect(File('$resDir/drawable/$kAlertSmallIcon.xml').existsSync(), isTrue);
  });

  test('the alert icon is kept through release resource shrinking', () {
    final keep = File('$resDir/raw/keep.xml');

    expect(keep.existsSync(), isTrue);
    expect(keep.readAsStringSync(), contains('@drawable/$kAlertSmallIcon'));
  });
}
