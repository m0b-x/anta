import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

import '../database/support/db_test_support.dart';

/// "Delete all events" is a wipe no bloc drove: the page sits below the
/// app-wide `CalendarBloc`, so unless the store says it moved, the bloc keeps
/// serving the deleted events for the rest of the session — and saving one of
/// them hits the DAO's update branch, which clears `is_deleted` and pushes the
/// event back to every device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The holiday service binds to the file-backed database, beside the
  // in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SettingsService settings;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_delete_all');
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
    SyncBindingService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    SyncBindingService.forTesting(db, settings);
    // The wipe refreshes all four facades; bound to the same database, or
    // each would open the file-backed one, which a test body's `FakeAsync`
    // never lets finish.
    await EventOccurrenceService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventAlertService.forTesting(db);
    final events = await CalendarEventService.forTesting(db);
    await events.upsert(
      CalendarEvent(
        id: 'e1',
        title: 'Leg day',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 1, 1),
        rule: const DailyRecurrence(),
      ),
    );
    // Warmed in the real async zone: the service opens the file-backed
    // database, which never completes under a test body's `FakeAsync`.
    await PublicHolidayService.getInstance();
  });

  tearDown(() async {
    CalendarEventService.reset();
    EventOccurrenceService.reset();
    EventPresenceService.reset();
    EventSkipService.reset();
    EventAlertService.reset();
    PublicHolidayService.reset();
    SyncBindingService.reset();
    SettingsService.reset();
    CalendarPaletteService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const CalendarSettingsPage(),
      ),
    );
    for (var i = 0; i < 100; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  /// Scrolls the page until [text] is built.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    for (var i = 0; i < 60; i++) {
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    fail('"$text" never came into view');
  }

  testWidgets('the wipe tells the store it moved', (tester) async {
    final heard = <void>[];
    final subscription = CalendarEventService.externalChanges.listen(heard.add);
    addTearDown(subscription.cancel);
    final revision = CalendarEventService.externalRevision;

    await pumpPage(tester);
    await scrollTo(tester, 'Delete all events');
    // Through the row's own callback: the row sits at the end of a long
    // scroll, and what is under test is the wipe, not the hit test.
    final row = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Delete all events'),
        matching: find.byType(ListTile),
      ),
    );
    expect(row.enabled, isTrue);
    row.onTap!();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect((await CalendarEventService.getInstance()).events, isEmpty);
    // The two halves of the signal: the revision a page re-entry reads, and
    // the stream a bloc already showing the calendar reloads on.
    expect(CalendarEventService.externalRevision, greaterThan(revision));
    expect(heard, hasLength(1));
  });
}
