import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A restore on the welcome page writes `locale` and `theme_mode` through the
/// DAO, beneath an `AppSettingsBloc` that read them once at launch: unless
/// the root reloads it when the welcome completes, the restored language and
/// theme wait for the next launch. No test pumps the app root, so the call is
/// pinned here as text, like the rest of the root's wiring
/// (`test/services/alert_ring_end_wiring_test.dart`).
void main() {
  final source = File('lib/main.dart').readAsStringSync();

  test('completing the welcome reloads the app settings', () {
    final method = RegExp(
      r'void _onOnboardingComplete\(\) \{[\s\S]*?^  \}',
      multiLine: true,
    ).stringMatch(source);
    expect(method, isNotNull);
    expect(
      method!.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), ''),
      matches(
        RegExp(
          r'read<AppSettingsBloc>\(\)\s*\.add\(\s*const LoadAppSettings\(\)',
        ),
      ),
    );
  });
}
