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
    await events.upsert(
      CalendarEvent(
        id: 'e2',
        title: 'Dentist',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 2, 3),
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

  /// Opens the confirm through the row's own callback: the row sits at the
  /// end of a long scroll, and what is under test is the wipe, not the hit
  /// test.
  Future<void> openConfirm(WidgetTester tester) async {
    await scrollTo(tester, 'Delete all events');
    final row = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Delete all events'),
        matching: find.byType(ListTile),
      ),
    );
    expect(row.enabled, isTrue);
    row.onTap!();
    await tester.pumpAndSettle();
  }

  Future<List<CalendarEventRow>> seededRows(WidgetTester tester) async =>
      (await tester.runAsync(
        () => db.calendarEventDao.getByIdsIncludingDeleted(const ['e1', 'e2']),
      ))!;

  testWidgets('confirm tombstones every event and the count re-reads', (
    tester,
  ) async {
    await pumpPage(tester);
    await openConfirm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // A soft wipe: both rows are still there, each a tombstone the sync push
    // can carry — a hard delete would leave the other devices holding them.
    final rows = await seededRows(tester);
    expect(rows.map((r) => r.id), unorderedEquals(['e1', 'e2']));
    expect(rows.every((r) => r.isDeleted), isTrue);
    expect(await tester.runAsync(db.calendarEventDao.getAll), isEmpty);

    // The page's own count went to zero: the row says so and stops offering
    // a second wipe.
    expect(find.text('No events to delete'), findsOneWidget);
    final row = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Delete all events'),
        matching: find.byType(ListTile),
      ),
    );
    expect(row.enabled, isFalse);
  });

  testWidgets('cancel writes nothing', (tester) async {
    final revision = CalendarEventService.externalRevision;

    await pumpPage(tester);
    await openConfirm(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    final rows = await seededRows(tester);
    expect(rows, hasLength(2));
    expect(rows.any((r) => r.isDeleted), isFalse);
    expect((await CalendarEventService.getInstance()).events, hasLength(2));
    expect(CalendarEventService.externalRevision, revision);
    expect(find.text('No events to delete'), findsNothing);
  });

  testWidgets('the wipe tells the store it moved', (tester) async {
    final heard = <void>[];
    final subscription = CalendarEventService.externalChanges.listen(heard.add);
    addTearDown(subscription.cancel);
    final revision = CalendarEventService.externalRevision;

    await pumpPage(tester);
    await openConfirm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect((await CalendarEventService.getInstance()).events, isEmpty);
    // The two halves of the signal: the revision a page re-entry reads, and
    // the stream a bloc already showing the calendar reloads on.
    expect(CalendarEventService.externalRevision, greaterThan(revision));
    expect(heard, hasLength(1));
  });
}
