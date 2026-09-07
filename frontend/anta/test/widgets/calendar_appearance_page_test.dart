import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/pages/calendar_appearance_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_appearance_preview.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';

/// The appearance rows moved off `CalendarSettingsPage` for exactly one
/// reason: the live preview sat in the section's `intro:` and scrolled away
/// as the user reached the day-rail rows at the bottom — the settings
/// furthest from the thing they change. So the cases that earn a test here
/// are the ones that would let that regress: the preview must be **outside**
/// the section list's scrollable, must survive a scroll to the bottom and an
/// active search, and must repaint from the same `_appearance` the rows
/// write.
///
/// The rest pin what the split itself put at risk — the week's seven cells
/// and their rotating header, a reset that must not reach the one key whose
/// row stayed behind, and the parent's single nav row still being findable by
/// every moved row's name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SettingsService settings;

  /// Distinguishes successive pumps of the same page so a re-pump rebuilds
  /// from scratch. Without it the element tree reuses the existing `State` and
  /// `initState` — the only place the settings are read — never runs again.
  var pumps = 0;

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    CalendarPaletteService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    pumps = 0;
  });

  tearDown(() async {
    SettingsService.reset();
    CalendarPaletteService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// Pumps until [ready] holds. Both pages render a `CircularProgressIndicator`
  /// while they load and that animates forever, so `pumpAndSettle` spins on it
  /// rather than settling — the same bounded loop the calendar pages' other
  /// widget tests use, for the same reason.
  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (ready()) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('the awaited condition never held');
  }

  /// Lets a database *write* finish.
  ///
  /// `testWidgets` runs its body inside `FakeAsync`, where a drift write never
  /// completes however many frames are pumped. Only `runAsync` hands the real
  /// event loop back, so any tap that persists something has to be drained
  /// through here before the store is worth asserting on.
  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// A viewport tall enough that every row is built — most assertions here are
  /// about which rows exist, not about scrolling to them.
  Future<void> pumpAppearancePage(
    WidgetTester tester, {
    Size size = const Size(900, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: CalendarAppearancePage(key: ValueKey(pumps++)),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pump();
  }

  Finder inPreview(Finder matching) => find.descendant(
    of: find.byType(CalendarAppearancePreview),
    matching: matching,
  );

  /// The seven day-of-week labels above the strip.
  ///
  /// The header `Row` is the preview's first, so it precedes every cell in
  /// tree order and `.first` picks it out without a key.
  List<String> headerLabels(WidgetTester tester) {
    final headerRow = inPreview(find.byType(Row)).first;
    return tester
        .widgetList<Text>(
          find.descendant(of: headerRow, matching: find.byType(Text)),
        )
        .map((text) => text.data!)
        .toList();
  }

  Future<void> enterQuery(WidgetTester tester, String query) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(SettingsSearchField),
        matching: find.byType(TextField),
      ),
      query,
    );
    await tester.pump();
  }

  group('the pinned preview', () {
    testWidgets('sits outside the section list, not inside its scrollable', (
      tester,
    ) async {
      await pumpAppearancePage(tester);

      expect(find.byType(CalendarAppearancePreview), findsOneWidget);
      // The whole point of the route. A preview inside the list is a preview
      // that scrolls away — which is what this change exists to undo.
      expect(
        find.descendant(
          of: find.byType(SettingsSectionList),
          matching: find.byType(CalendarAppearancePreview),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(Scrollable),
          matching: find.byType(CalendarAppearancePreview),
        ),
        findsNothing,
      );
    });

    testWidgets('stays put when the list is scrolled to the bottom', (
      tester,
    ) async {
      // Short enough that the list genuinely overflows and has somewhere to
      // scroll to.
      await pumpAppearancePage(tester, size: const Size(400, 700));

      final before = tester.getTopLeft(find.byType(CalendarAppearancePreview));
      // Well past the content extent, so the list is pinned at its bottom
      // whatever the row heights come out to.
      await tester.drag(
        find.byType(SettingsSectionList),
        const Offset(0, -4000),
      );
      await tester.pump();

      expect(find.byType(CalendarAppearancePreview), findsOneWidget);
      expect(tester.getTopLeft(find.byType(CalendarAppearancePreview)), before);
    });

    testWidgets('survives an active search that filters the list', (
      tester,
    ) async {
      await pumpAppearancePage(tester);
      expect(find.text('Today highlight'), findsOneWidget);

      await enterQuery(tester, 'rail');

      // The query filtered the list down to the rail section...
      expect(find.text('Today highlight'), findsNothing);
      expect(find.text('Day rail'), findsWidgets);
      // ...and the preview is still on screen, which is what makes searching
      // for a control and then using it a single motion.
      expect(find.byType(CalendarAppearancePreview), findsOneWidget);
    });

    testWidgets('repaints when a row on the page changes a setting', (
      tester,
    ) async {
      await pumpAppearancePage(tester);

      expect(
        tester
            .widgetList<CalendarDayCell>(
              inPreview(find.byType(CalendarDayCell)),
            )
            .every((cell) => cell.todayStyle == CalendarTodayStyle.tonal),
        isTrue,
      );

      await tester.tap(find.text('Ring'));
      await tester.pump();

      expect(
        tester
            .widgetList<CalendarDayCell>(
              inPreview(find.byType(CalendarDayCell)),
            )
            .every((cell) => cell.todayStyle == CalendarTodayStyle.ring),
        isTrue,
      );
    });

    testWidgets('renders the seven days of a week', (tester) async {
      await pumpAppearancePage(tester);

      expect(inPreview(find.byType(CalendarDayCell)), findsNWidgets(7));
      expect(headerLabels(tester), hasLength(7));
    });

    testWidgets('the weekday header rotates with the week start', (
      tester,
    ) async {
      // Through `DateFormat`, never a hardcoded English name: the labels are
      // derived from an anchor date (2024-01-01 was a Monday) exactly as
      // `RecurrenceFormatter.weekdayShort` does, and the test has to fail if
      // that derivation changes rather than if the locale does.
      final format = DateFormat.E('en');
      final monday = format.format(DateTime(2024, 1, 1));
      final sunday = format.format(DateTime(2024, 1, 7));

      await settings.setCalendarWeekStart(CalendarWeekStart.monday);
      await pumpAppearancePage(tester);
      expect(headerLabels(tester).first, monday);
      expect(headerLabels(tester).last, sunday);

      await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
      await pumpAppearancePage(tester);
      expect(headerLabels(tester).first, sunday);
      expect(headerLabels(tester).last, format.format(DateTime(2024, 1, 6)));
    });

    testWidgets('stays a compact strip at every marker density', (
      tester,
    ) async {
      // The preview is pinned, so its height is page chrome the rows below
      // pay for on every scroll — a preview that grows past the fold defeats
      // the split it exists to justify.
      await pumpAppearancePage(tester);
      final defaultHeight = tester
          .getSize(find.byType(CalendarAppearancePreview))
          .height;
      expect(defaultHeight, 100.0);

      // 6 is the slider's maximum, so this is the tallest strip the page can
      // ever pin.
      await settings.setCalendarMaxDayBars(6);
      await pumpAppearancePage(tester);
      expect(
        tester.getSize(find.byType(CalendarAppearancePreview)).height,
        114.0,
      );
    });
  });

  group('reset', () {
    testWidgets('never touches the filter-chips key, whose row stayed behind', (
      tester,
    ) async {
      // Both are non-default, so a reset that runs is visible and a reset that
      // over-reaches is too.
      await settings.setCalendarTodayStyle(CalendarTodayStyle.filled);
      await settings.setCalendarShowFilterChips(true);

      await pumpAppearancePage(tester);

      await tester.ensureVisible(find.text('Reset to defaults'));
      await tester.pump();
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await settleWrites(tester);

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.calendarTodayStyle),
        CalendarTodayStyle.tonal.name,
      );
      // `calendarShowFilterChips` is part of the same `CalendarAppearance`
      // bundle, but its row lives on the calendar settings page's Filtering
      // section — resetting a control the user cannot see from here would be
      // a silent change.
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.calendarShowFilterChips),
        'true',
      );
      expect((await settings.getCalendarAppearance()).showFilterChips, isTrue);
    });
  });

  // `CalendarSettingsPage` resolves `PublicHolidayService`, which binds to the
  // real `AppDatabase.getInstance()` and therefore needs `path_provider`. The
  // appearance page above needs none of that, which is why only this group
  // pays for it.
  group('the calendar settings page it left behind', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_appearance_row');
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
      CalendarEventService.reset();
      await CalendarEventService.forTesting(db);
      // Warmed here, in the real async zone, rather than inside the test body:
      // `PublicHolidayService` has no `forTesting` binding, so it opens the
      // file-backed `AppDatabase`, and that open never completes under the
      // `FakeAsync` a `testWidgets` body runs in. Resolved up front it is a
      // warm singleton by the time the page's `_loadSettings` asks for it.
      await PublicHolidayService.getInstance();
    });

    tearDown(() {
      CalendarEventService.reset();
      PublicHolidayService.reset();
    });

    Future<void> pumpSettingsPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: CalendarSettingsPage(key: ValueKey(pumps++)),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await tester.pump();
    }

    testWidgets('shows one Appearance row and none of the moved controls', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      expect(find.text('Preview and tune how the grid looks'), findsOneWidget);
      expect(find.byType(CalendarAppearancePreview), findsNothing);
      for (final movedRow in const [
        'Today highlight',
        'Highlight color',
        'Day rail',
        'Week starts on',
        'Tint days by event color',
      ]) {
        expect(
          find.text(movedRow),
          findsNothing,
          reason: '"$movedRow" moved to the appearance page',
        );
      }
    });

    testWidgets('its keywords keep a moved row findable by name', (
      tester,
    ) async {
      await pumpSettingsPage(tester);

      // The one real cost of splitting the page: without the keywords, typing
      // the name of any moved row into calendar settings would find nothing.
      await enterQuery(tester, 'day rail');

      expect(find.text('Preview and tune how the grid looks'), findsOneWidget);
      expect(find.text('Holiday set'), findsNothing);
    });
  });
}
