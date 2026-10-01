import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `KeyboardInsetGuard` protects nothing unless the app root mounts it, and
/// no widget test pumps the app root: `main.dart` brings up Firebase, the
/// database and every app-wide bloc. Its wiring is three lines that would
/// compile, pass every other suite and bring the floating bottom bar back if
/// any of them went missing, so they are pinned as text.
void main() {
  final source = File('lib/main.dart').readAsStringSync();

  test('the app root mounts the guard in MaterialApp.builder, which is what '
      'puts it above the navigator', () {
    expect(
      source,
      matches(
        RegExp(r'builder:\s*\(context, child\)\s*=>\s*KeyboardInsetGuard\('),
      ),
    );
  });

  test('the guard is handed the platform resync', () {
    expect(source, contains('onSettled: const WindowInsetsResync().request'));
  });

  test('the app still drops focus when it is paused — what leaves nothing '
      'focused on resume, so the guard can refuse a stuck inset at once', () {
    expect(
      source,
      matches(
        RegExp(
          r'if \(state == AppLifecycleState\.paused\) \{\s*'
          r'FocusManager\.instance\.primaryFocus\?\.unfocus\(\);',
        ),
      ),
    );
  });
}
