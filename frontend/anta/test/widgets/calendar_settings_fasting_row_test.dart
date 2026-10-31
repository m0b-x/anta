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
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/fasting_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import 'support/page_route_recorder.dart';

/// Calendar settings' one Fasting row (D6): its value line names the
/// traditions on, on one line, or "Off", it opens Fasting settings stamped,
/// and it reads the traditions back when that page pops — the fasting rows
/// themselves are `fasting_settings_page_test.dart`'s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app's own database, which the holiday service is bound to, beside
  // the in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SettingsService settings;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_fasting_row');
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
      find.bySemanticsIdentifier(SemanticsIds.calendarSettingsFastingOpen);

  void expectRowSays(String text) => expect(
    find.descendant(of: row(), matching: find.text(text)),
    findsOneWidget,
  );

  group('the value line', () {
    /// [FastingSettingsPage.summary] in English.
    Future<String> summaryOf(
      WidgetTester tester, {
      Set<FastingTradition> traditions = const {},
    }) async {
      late String summary;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              summary = FastingSettingsPage.summary(
                AppLocalizations.of(context)!,
                traditions: traditions,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return summary;
    }

    testWidgets('no tradition on: "Off"', (tester) async {
      expect(await summaryOf(tester), 'Off');
    });

    testWidgets('one tradition on: its name alone', (tester) async {
      expect(
        await summaryOf(tester, traditions: const {FastingTradition.orthodox}),
        'Orthodox',
      );
    });

    testWidgets('several on: their names in the switches\' order, on one '
        'line, each dot held to the name after it', (tester) async {
      expect(
        await summaryOf(
          tester,
          traditions: const {
            FastingTradition.jewish,
            FastingTradition.orthodox,
            FastingTradition.catholic,
          },
        ),
        'Orthodox\u00A0· Catholic\u00A0· Jewish',
      );
    });
  });

  testWidgets('the row opens Fasting settings, stamped', (tester) async {
    final observer = PageRouteRecorder();
    await pumpPage(tester, observers: [observer]);
    observer.pushed.clear();

    await tester.ensureVisible(row());
    await tester.pump();
    await tester.tap(row());
    await settle(tester);

    expect(
      observer.pushed.single.settings.arguments,
      const NavDestination(NavDestinationKind.fastingSettings),
    );
    expect(find.byType(FastingSettingsPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the page\'s search finds the row by the words of the rows '
      'that moved behind it, and drops it for a word it does not hold', (
    tester,
  ) async {
    await pumpPage(tester);
    final field = find.descendant(
      of: find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
      matching: find.byType(TextField),
    );
    final alertsRow = find.bySemanticsIdentifier(
      SemanticsIds.calendarSettingsAlertsOpen,
    );
    expect(alertsRow, findsOneWidget);

    for (final query in const ['Multi-day', 'Look on the calendar']) {
      await tester.enterText(field, query);
      await tester.pump();
      expect(row(), findsOneWidget, reason: query);
      expect(alertsRow, findsNothing, reason: query);
    }

    await tester.enterText(field, 'snooze');
    await tester.pump();
    expect(row(), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a tradition changed while Fasting settings is up shows on the '
      'row after the pop, the practice not read', (tester) async {
    await pumpPage(tester);
    expectRowSays('Off');

    await tester.ensureVisible(row());
    await tester.pump();
    await tester.tap(row());
    await settle(tester);
    expect(find.byType(FastingSettingsPage), findsOneWidget);

    await tester.runAsync(() async {
      await settings.setFastingTraditions(const {FastingTradition.catholic});
      await settings.setFastingSchedule(
        const FastingSchedule(weekdays: {DateTime.friday}),
      );
    });
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);

    expect(find.byType(FastingSettingsPage), findsNothing);
    expectRowSays('Catholic');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
