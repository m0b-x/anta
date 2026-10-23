@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The calendar settings page's first screen, harnessed and seeded as
/// `test/widgets/calendar_settings_large_text_test.dart` does it: both
/// default alerts set, so their rows read back a value.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app's own database, which the holiday service is bound to, beside
  // the in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_golden_cal_settings');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    CalendarPaletteService.reset();
    CalendarEventService.reset();
    db = await openTestDatabase();
    final settings = SettingsService.forTesting(db);
    await CalendarEventService.forTesting(db);
    // Warmed in the real async zone: the service opens the file-backed
    // database, which never completes under a test body's `FakeAsync`.
    await PublicHolidayService.getInstance();
    await settings.setAlertDefaultTimed((
      mode: AlertMode.ring,
      offsetMinutes: 10,
    ));
    await settings.setAlertDefaultAllDay((
      mode: AlertMode.notify,
      daysBefore: 1,
      dayMinute: 9 * 60,
    ));
  });

  tearDown(() async {
    CalendarEventService.reset();
    PublicHolidayService.reset();
    SettingsService.reset();
    CalendarPaletteService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  for (final cell in goldenCells) {
    testWidgets('calendar settings page, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          goldenApp(cell, home: const CalendarSettingsPage()),
        );
        // The page spins a progress indicator while it loads, which never
        // settles; pump until it is gone.
        for (var i = 0; i < 100; i++) {
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump();
      });

      expect(errors, isEmpty);
      await expectGolden('calendar_settings', cell);
    });
  }
}
