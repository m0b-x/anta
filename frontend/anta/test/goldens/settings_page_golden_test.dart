@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/label_appearance.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/label_style.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The settings page's first screen, harnessed as
/// `test/widgets/settings_page_test.dart` harnesses it.
void main() {
  late AppDatabase db;

  setUp(() async {
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    DrawerHostRegistry.clear();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    DrawerHostRegistry.clear();
    await GetIt.I.reset();
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  for (final cell in goldenCells) {
    testWidgets('settings page, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(goldenApp(cell, home: const SettingsPage()));
        await settle(tester);
      });

      expect(errors, isEmpty);
      await expectGolden('settings_page', cell);
    });
  }
}
