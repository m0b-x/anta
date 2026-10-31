import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/alert_settings_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// Calendar settings' one Alerts row (D5): its value line names each default
/// by the shape it serves, it opens Alert settings stamped, and it reads the
/// defaults back when that page pops — the alert rows themselves are
/// `alert_settings_page_test.dart`'s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app's own database, which the holiday service is bound to, beside
  // the in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SettingsService settings;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_alerts_row');
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
    settings = SettingsService.forTesting(db);
    await CalendarEventService.forTesting(db);
    // Warmed in the real async zone: the service opens the file-backed
    // database, which never completes under a test body's `FakeAsync`.
    await PublicHolidayService.getInstance();
  });

  tearDown(() async {
    CalendarEventService.reset();
    PublicHolidayService.reset();
    SettingsService.reset();
    CalendarPaletteService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// Drift's futures never complete under `FakeAsync` alone, so every step
  /// interleaves real time with pumped frames.
  Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<NavigatorObserver> observers = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        navigatorObservers: observers,
        home: const CalendarSettingsPage(),
      ),
    );
    await settle(tester);
  }

  Finder row() =>
      find.bySemanticsIdentifier(SemanticsIds.calendarSettingsAlertsOpen);

  void expectRowSays(String text) => expect(
    find.descendant(of: row(), matching: find.text(text)),
    findsOneWidget,
  );

  group('the value line', () {
    /// [AlertSettingsPage.defaultsSummary] in English.
    Future<String> summaryOf(
      WidgetTester tester, {
      TimedAlertDefault? timed,
      AllDayAlertDefault? allDay,
    }) async {
      late String summary;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              summary = AlertSettingsPage.defaultsSummary(
                context,
                timed: timed,
                allDay: allDay,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return summary;
    }

    testWidgets('both set: each line named by its row\'s title', (
      tester,
    ) async {
      expect(
        await summaryOf(
          tester,
          timed: (mode: AlertMode.notify, offsetMinutes: 10),
          allDay: (mode: AlertMode.ring, daysBefore: 1, dayMinute: 9 * 60),
        ),
        'Timed events · Reminder · 10 min before\n'
        'All-day events · Alarm · The day before, 9:00 AM',
      );
    });

    testWidgets('one set: the other line reads "No alert", still named', (
      tester,
    ) async {
      expect(
        await summaryOf(
          tester,
          timed: (mode: AlertMode.notify, offsetMinutes: 10),
        ),
        'Timed events · Reminder · 10 min before\n'
        'All-day events · No alert',
      );
    });

    testWidgets('neither set: "No alert" once', (tester) async {
      expect(await summaryOf(tester), 'No alert');
    });
  });

  testWidgets('the row opens Alert settings, stamped', (tester) async {
    final observer = _RecordingObserver();
    await pumpPage(tester, observers: [observer]);
    observer.pushed.clear();

    await tester.ensureVisible(row());
    await tester.pump();
    await tester.tap(row());
    await settle(tester);

    expect(
      observer.pushed.single.settings.arguments,
      const NavDestination(NavDestinationKind.alertSettings),
    );
    expect(find.byType(AlertSettingsPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a default changed while Alert settings is up shows on the row '
      'after the pop', (tester) async {
    await pumpPage(tester);
    expectRowSays('No alert');

    await tester.ensureVisible(row());
    await tester.pump();
    await tester.tap(row());
    await settle(tester);
    expect(find.byType(AlertSettingsPage), findsOneWidget);

    await tester.runAsync(
      () => settings.setAlertDefaultTimed((
        mode: AlertMode.ring,
        offsetMinutes: 30,
      )),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);

    expect(find.byType(AlertSettingsPage), findsNothing);
    expectRowSays(
      'Timed events · Alarm · 30 min before\n'
      'All-day events · No alert',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pushed.add(route);
  }
}
