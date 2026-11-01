import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/semantics_ids.dart';
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
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/unified_app_bars.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/settings_page_whole.dart';

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
  late _SettingWrites writes;

  /// Distinguishes successive pumps of the same page so a re-pump rebuilds
  /// from scratch. Without it the element tree reuses the existing `State` and
  /// `initState` — the only place the settings are read — never runs again.
  var pumps = 0;

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    CalendarPaletteService.reset();
    writes = _SettingWrites();
    db = await openTestDatabase(interceptor: writes);
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
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

  testWidgets('the bar carries its own id', (tester) async {
    await pumpAppearancePage(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.settingsBarAppearance),
      findsOneWidget,
    );
  });

  group('the week start', () {
    String dayName(CalendarWeekStart start, String locale) {
      final name = DateFormat.EEEE(
        locale,
      ).format(DateTime.utc(2024, 1, start.weekday));
      return toBeginningOfSentenceCase(name, locale) ?? name;
    }

    testWidgets('reads the chosen day as its value and opens a menu of every '
        'start, the current one checked; a pick writes it, the value '
        'follows and the header rotates', (tester) async {
      await settings.setCalendarWeekStart(CalendarWeekStart.monday);
      await pumpAppearancePage(tester);
      final row = find.bySemanticsIdentifier(SemanticsIds.appearanceWeekStart);
      final monday = dayName(CalendarWeekStart.monday, 'en');
      final sunday = dayName(CalendarWeekStart.sunday, 'en');
      expect(find.descendant(of: row, matching: find.text(monday)), findsOne);

      await tester.tap(row);
      await tester.pumpAndSettle();

      final items = tester
          .widgetList<FormMenuChoiceItem<CalendarWeekStart>>(
            find.byType(FormMenuChoiceItem<CalendarWeekStart>),
          )
          .toList();
      expect(items.map((item) => item.value), CalendarWeekStart.values);
      expect(items.where((item) => item.checked).map((item) => item.value), [
        CalendarWeekStart.monday,
      ]);
      for (final start in CalendarWeekStart.values) {
        expect(
          find.bySemanticsIdentifier(
            SemanticsIds.appearanceWeekStartItem(start.name),
          ),
          findsOneWidget,
          reason: start.name,
        );
      }

      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.appearanceWeekStartItem(CalendarWeekStart.sunday.name),
        ),
      );
      await tester.pumpAndSettle();
      await settleWrites(tester);

      expect(
        await tester.runAsync(settings.getCalendarWeekStart),
        CalendarWeekStart.sunday,
      );
      expect(find.descendant(of: row, matching: find.text(sunday)), findsOne);
      expect(
        headerLabels(tester).first,
        DateFormat.E('en').format(DateTime(2024, 1, 7)),
      );
    });

    testWidgets('German at 2.0 on a 360 × 780 phone puts the day under the '
        'title rather than crushing it', (tester) async {
      await settings.setCalendarWeekStart(CalendarWeekStart.saturday);
      await pumpAppearancePage(
        tester,
        size: const Size(360, 780),
        locale: const Locale('de'),
        textScale: 2.0,
      );
      final row = find.bySemanticsIdentifier(SemanticsIds.appearanceWeekStart);
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final title = lookupAppLocalizations(
        const Locale('de'),
      ).calendarWeekStartTitle;
      final value = find.descendant(
        of: row,
        matching: find.text(dayName(CalendarWeekStart.saturday, 'de')),
      );
      expect(value, findsOneWidget);
      expect(
        tester.getRect(value).top,
        greaterThanOrEqualTo(tester.getRect(find.text(title)).bottom),
      );
    });

    testWidgets('picking the day already chosen writes nothing and flashes '
        'nothing', (tester) async {
      await settings.setCalendarWeekStart(CalendarWeekStart.monday);
      await pumpAppearancePage(tester);
      final row = find.bySemanticsIdentifier(SemanticsIds.appearanceWeekStart);
      writes.keys.clear();

      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.appearanceWeekStartItem(CalendarWeekStart.monday.name),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final highlight = find.descendant(
        of: row,
        matching: find.byType(ValueChangeHighlight),
      );
      final wash = tester.widget<DecoratedBox>(
        find
            .descendant(of: highlight, matching: find.byType(DecoratedBox))
            .first,
      );
      expect((wash.decoration as BoxDecoration).color, isNull);
      await tester.pumpAndSettle();
      await settleWrites(tester);
      expect(writes.keys, isNot(contains(SettingsKeys.calendarWeekStart)));
      expect(
        await tester.runAsync(settings.getCalendarWeekStart),
        CalendarWeekStart.monday,
      );
    });
  });

  group('the tint conflict', () {
    Finder segments() => find.byType(SegmentedButton<CalendarTintConflict>);

    testWidgets('is disabled, not hidden, while the event tint is off, and '
        'offers its three choices once it is on', (tester) async {
      await settings.setCalendarEventTint(false);
      await pumpAppearancePage(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.appearanceTintConflict),
        findsOneWidget,
      );
      var button = tester.widget<SegmentedButton<CalendarTintConflict>>(
        segments(),
      );
      expect(button.onSelectionChanged, isNull);
      expect(button.segments.map((s) => s.value), CalendarTintConflict.values);
      final title = tester.widget<HighlightedText>(
        find.byWidgetPredicate(
          (w) => w is HighlightedText && w.text == 'On fasting days',
        ),
      );
      expect(title.style?.color?.a, closeTo(0.38, 0.01));

      await settings.setCalendarEventTint(true);
      await pumpAppearancePage(tester);

      button = tester.widget<SegmentedButton<CalendarTintConflict>>(segments());
      expect(button.onSelectionChanged, isNotNull);
      await tester.tap(find.text('Both'));
      await tester.pump();
      await settleWrites(tester);
      expect(
        await tester.runAsync(settings.getCalendarTintConflict),
        CalendarTintConflict.both,
      );
    });

    testWidgets('flipping the tint switch moves no row: the cell style above '
        'and the conflict row are disabled with the tint off and enabled with '
        'it on, in place', (tester) async {
      final handle = tester.ensureSemantics();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await settings.setCalendarEventTint(false);
      await pumpAppearancePage(tester);
      final tintSwitch = find.widgetWithText(
        SwitchListTile,
        l10n.calendarEventTintTitle,
      );
      final conflictRow = find.bySemanticsIdentifier(
        SemanticsIds.appearanceTintConflict,
      );
      final cellStyles = find.byType(SegmentedButton<CalendarCellStyle>);
      // The header of the section under the day cell's.
      final below = find.text(
        l10n.calendarAppearanceMarkersSection.toUpperCase(),
      );
      expect(tintSwitch, findsOneWidget);
      expect(below, findsOneWidget);

      void expectRows({required bool enabled}) {
        for (final button
            in tester.widgetList<SegmentedButton<CalendarCellStyle>>(
              cellStyles,
            )) {
          expect(button.onSelectionChanged != null, enabled);
        }
        final conflict = tester.widget<SegmentedButton<CalendarTintConflict>>(
          segments(),
        );
        expect(conflict.onSelectionChanged != null, enabled);
        for (final label in [
          l10n.calendarCellStyleSolid,
          l10n.calendarTintConflictBoth,
        ]) {
          expect(
            tester.getSemantics(find.widgetWithText(TextButton, label).first),
            isSemantics(hasEnabledState: true, isEnabled: enabled),
            reason: label,
          );
        }
      }

      expect(cellStyles, findsNWidgets(2));
      expectRows(enabled: false);
      final conflictRect = tester.getRect(conflictRow);
      final belowRect = tester.getRect(below);
      final cellRect = tester.getRect(cellStyles.first);

      await tester.tap(tintSwitch);
      await tester.pump();
      await settleWrites(tester);

      expect(await tester.runAsync(settings.getCalendarEventTint), isTrue);
      expectRows(enabled: true);
      expect(tester.getRect(conflictRow), conflictRect);
      expect(tester.getRect(below), belowRect);
      expect(tester.getRect(cellStyles.first), cellRect);

      await tester.tap(tintSwitch);
      await tester.pump();
      await settleWrites(tester);

      expectRows(enabled: false);
      expect(tester.getRect(conflictRow), conflictRect);
      expect(tester.getRect(below), belowRect);

      handle.dispose();
    });

    testWidgets('German at 2.0 on a 360 × 780 phone breaks no choice inside '
        'a word', (tester) async {
      await settings.setCalendarEventTint(true);
      await pumpAppearancePage(
        tester,
        size: const Size(360, 780),
        locale: const Locale('de'),
        textScale: 2.0,
      );
      await tester.scrollUntilVisible(
        segments(),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final labels = find.descendant(
        of: segments(),
        matching: find.byType(RichText),
      );
      expect(labels, findsNWidgets(CalendarTintConflict.values.length));
      for (final element in labels.evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(
            paragraph.getMinIntrinsicWidth(double.infinity) - 0.01,
          ),
          reason: '"${paragraph.text.toPlainText()}" breaks inside a word',
        );
      }
    });
  });

  group('reset', () {
    testWidgets('never touches the filter-chips key, whose row stayed behind', (
      tester,
    ) async {
      // Both are non-default, so a reset that runs is visible and a reset that
      // over-reaches is too.
      await settings.setCalendarTodayStyle(CalendarTodayStyle.filled);
      await settings.setCalendarShowFilterChips(false);

      await pumpAppearancePage(tester);

      // The cell-style row is built with the tint off too, so the reset sits
      // past the tall viewport's built rows.
      await tester.scrollUntilVisible(
        find.text('Reset to defaults'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
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
        'false',
      );
      expect((await settings.getCalendarAppearance()).showFilterChips, isFalse);
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

    testWidgets('shows one Appearance row, in More settings, and none of the '
        'moved controls', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.text('Preview and tune how the grid looks'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is SettingsSectionCard && w.section.id == 'pages',
          ),
          matching: find.bySemanticsIdentifier(
            SemanticsIds.calendarAppearanceOpen,
          ),
        ),
        findsOneWidget,
      );
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

    testWidgets("a fold toggled there leaves the appearance page's folds", (
      tester,
    ) async {
      // Both pages keep their folds in the one stored set. `'appearance'` is
      // the id of the section the Appearance row had before More settings —
      // the underscore is the whole difference — and stays in the set,
      // harmless.
      await settings.setCalendarSettingsCollapsedSections({
        'appearance',
        'appearance_cell',
        'appearance_rail',
      });

      await pumpSettingsPage(tester);
      await tester.tap(find.text('HOLIDAYS'));
      await settleWrites(tester);

      expect(await settings.getCalendarSettingsCollapsedSections(), {
        'appearance',
        'appearance_cell',
        'appearance_rail',
        'calendar',
      });
    });
  });

  // Last in the file: the real fonts stay registered once loaded, and every
  // case above was written against the test font.
  group('large text with real fonts', () {
    setUpAll(loadGoldenFonts);

    /// Every row on the page drawn: the cell-style pair and the conflict
    /// enabled, the rail's base row revealed (it takes `line`, the tint and
    /// `both`).
    Future<void> pumpEveryRow(WidgetTester tester, Locale locale) async {
      await settings.setCalendarEventTint(true);
      await settings.setCalendarDayRailStyle(DayRailStyle.line);
      await settings.setCalendarTintConflict(CalendarTintConflict.both);
      await pumpAppearancePage(
        tester,
        size: const Size(360, 780),
        locale: locale,
        textScale: 2.0,
      );
    }

    final choiceRows = <(Finder, int)>[
      (find.byType(SegmentedButton<CalendarTodayStyle>), 1),
      (find.byType(SegmentedButton<CalendarCellStyle>), 2),
      (find.byType(SegmentedButton<CalendarTintConflict>), 1),
      (find.byType(SegmentedButton<CalendarMarkerStyle>), 1),
      (find.byType(SegmentedButton<CalendarMissedDisplay>), 1),
      (find.byType(SegmentedButton<DayRailStyle>), 1),
      (find.byType(SegmentedButton<DayRailBasePosition>), 1),
    ];

    // Flow 25 taps these; through the kit's row the ids still merge into
    // each segment's node.
    testWidgets('the missed-display segments keep their flow ids', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAppearancePage(tester);
      final hidden = find.bySemanticsIdentifier(
        SemanticsIds.missedDisplayHidden,
      );
      await tester.scrollUntilVisible(
        hidden,
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.missedDisplayFaded),
        findsOneWidget,
      );
      await tester.tap(hidden);
      await tester.pump();
      await settleWrites(tester);
      expect(
        await tester.runAsync(settings.getCalendarMissedDisplay),
        CalendarMissedDisplay.hidden,
      );
      handle.dispose();
    });

    for (final locale in const [Locale('de'), Locale('ro')]) {
      testWidgets('${locale.languageCode} at 2.0 on a 360 × 780 phone: every '
          'choice row holds its labels whole, stacking where a word would '
          'not fit its segment', (tester) async {
        await pumpEveryRow(tester, locale);
        final list = find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first;

        for (final (row, count) in choiceRows) {
          await tester.scrollUntilVisible(row.first, 200, scrollable: list);
          await tester.pumpAndSettle();
          expect(row, findsNWidgets(count));
          // "Dezent" does not fit a third of the row: the today style
          // stacks.
          if (locale.languageCode == 'de' && row == choiceRows.first.$1) {
            expect(
              tester.widget<SegmentedButton<CalendarTodayStyle>>(row).direction,
              Axis.vertical,
            );
          }
          for (final element
              in find
                  .descendant(of: row, matching: find.byType(RichText))
                  .evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final text = paragraph.text.toPlainText();
            expect(
              paragraph.size.width,
              greaterThanOrEqualTo(paragraph.textSize.width - 0.01),
              reason: '"$text" is clipped at the side',
            );
            expect(
              paragraph.size.width,
              greaterThanOrEqualTo(
                paragraph.getMinIntrinsicWidth(double.infinity) - 0.01,
              ),
              reason: '"$text" breaks inside a word',
            );
            expectBreaksBetweenWords(paragraph);
          }
        }
        expect(tester.takeException(), isNull);
      });

      // Everything but the preview, whose weekday header cuts a long day
      // name to one line on purpose ("mar." in Romanian).
      testWidgets('${locale.languageCode} at 2.0 on a 360 × 780 phone breaks '
          'no text on the page inside a word', (tester) async {
        await pumpEveryRow(tester, locale);
        await expectPageWhole(
          tester,
          within: find.byWidgetPredicate(
            (widget) =>
                widget is SettingsAppBar ||
                widget is SettingsSearchField ||
                widget is SettingsSectionList,
          ),
        );
      });
    }
  });
}

/// Records the arguments of every settings write, so a case can pin that a
/// pick wrote nothing.
class _SettingWrites extends QueryInterceptor {
  final List<String> keys = [];

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('user_settings')) {
      keys.addAll(args.whereType<String>());
    }
    return super.runInsert(executor, statement, args);
  }
}
