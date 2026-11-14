import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the app's manifest says for push (`docs/cloud-shared-freshness.md`
/// §7), held here by reading the source: each line below would build, run
/// and pass every Dart suite with the wrong value in it, and only a phone
/// would show the difference.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  /// Every element of the manifest, from its `<` to its `>`, comments left
  /// out.
  final elements = [
    for (final match in RegExp(
      r'<(?!!--)[^>]*>',
    ).allMatches(manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')))
      match[0]!,
  ];

  /// The value of the `<meta-data>` named [name]; null when there is none.
  String? metaData(String name) {
    final element = elements.where(
      (e) => e.startsWith('<meta-data') && e.contains('android:name="$name"'),
    );
    if (element.length != 1) return null;
    return RegExp(r'android:value="([^"]*)"').firstMatch(element.single)?[1];
  }

  test('FCM never registers by itself: auto-init stays off, so an install '
      'that never paired never asks the platform for an address', () {
    expect(metaData('firebase_messaging_auto_init_enabled'), 'false');
  });

  test('the address is the installation id: the API that names it stays '
      'on', () {
    expect(metaData('firebase_messaging_installation_id_enabled'), 'true');
  });

  test('the permission an expedited work needs is not removed: without it '
      'the work plugin throws before it enqueues, and every message\'s work '
      'on Android 12 and later falls back to a plain one', () {
    final removed = elements.where(
      (e) =>
          e.contains('FOREGROUND_SERVICE_SHORT_SERVICE') &&
          e.contains('tools:node="remove"'),
    );
    expect(removed, isEmpty);
  });
}
