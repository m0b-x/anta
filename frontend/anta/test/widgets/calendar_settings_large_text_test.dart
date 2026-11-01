import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/fasting_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/settings_page_whole.dart';

/// Calendar settings at a large text scale. `ListTile` gives its trailing
/// whatever width it asks for and the title the rest, so the holiday set's
/// dropdown — as wide as the widest profile's name — took the whole tile in
/// German at 200 % and the page would not lay out, and a default alert read
/// back squeezed "Ganztägige Termine" to a letter a line (the Tier 2 device
/// pass). The rows now yield to their text column: the value wraps in what
/// the title's and the subtitle's longest word leave, while it fits the
/// height the tile gives a trailing there, and goes under the description
/// otherwise. The default-alert rows moved to Alert settings (D5) and their
/// cases with them, to `alert_settings_page_test.dart`.
///
/// Roboto is loaded, so a word is as wide as a phone draws it: the test
/// font's full-em glyphs made "Ganztägige" at 200 % wider than its whole
/// column, and the dropdown's "under its title" was measured on boxes. A
/// title is still asserted to be as whole as its column allows, never
/// narrower than that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two databases on purpose: the app's own, which the holiday service is
  // bound to, beside the in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const phone = Size(360, 780);

  late AppDatabase db;
  late SettingsService settings;
  late Directory tempDir;

  setUpAll(() async {
    await loadGoldenFonts();
    // `PublicHolidayService` binds to the file-backed `AppDatabase`, which
    // needs `path_provider` (the appearance page suite pays the same).
    tempDir = await Directory.systemTemp.createTemp('anta_settings_large');
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

  /// [density] is the theme's: left out, the host's — compact on a desktop,
  /// which is where these tests run, so a tile hands its trailing 48 dp;
  /// `VisualDensity.standard` is the phone's, with its 56 dp.
  Future<void> pumpPage(
    WidgetTester tester, {
    required Size surface,
    required Locale locale,
    double textScale = 1.0,
    VisualDensity? density,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: density == null ? null : ThemeData(visualDensity: density),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const CalendarSettingsPage(),
      ),
    );
    // The page spins a progress indicator while it loads, which never
    // settles; pump until it is gone.
    for (var i = 0; i < 100; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  /// Scrolls the page until [text] is built, laying every section out on
  /// the way; a layout that throws anywhere on the page surfaces here.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    for (var i = 0; i < 60; i++) {
      expect(tester.takeException(), isNull);
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    fail('"$text" never came into view');
  }

  Finder tileOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  /// The width the tile's text column has: the tile less its padding, its
  /// leading slot and the gap after it.
  double columnOf(WidgetTester tester, String title) =>
      tester.getRect(tileOf(title)).width -
      FormMetrics.settingsRowPadding.horizontal -
      FormMetrics.settingsLeadingWidth -
      FormMetrics.settingsTitleGap;

  /// [text], a line of the tile titled [title], holds its words whole, or —
  /// where one word is wider than the whole text column, which the test
  /// font can do — fills the column: it is never narrower than the row
  /// allows.
  void expectWholeWords(
    WidgetTester tester,
    String text, {
    String? title,
    Finder? finder,
  }) {
    final paragraph = tester.renderObject<RenderParagraph>(
      finder ?? find.text(text),
    );
    final longestWord = paragraph.getMinIntrinsicWidth(double.infinity);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(
        math.min(longestWord, columnOf(tester, title ?? text)) - 0.01,
      ),
      reason: '"$text" breaks inside a word',
    );
  }

  void expectTitleWhole(WidgetTester tester, String title) =>
      expectWholeWords(tester, title);

  /// Every line of [text] is painted: the paragraph is as large as the text
  /// it laid out, so nothing is cut by a box too short for it — `ListTile`
  /// caps a trailing's height, which lost a third line on the device.
  void expectUnclipped(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
      reason: '"$text" is cut short',
    );
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(paragraph.textSize.width - 0.01),
      reason: '"$text" is cut at the side',
    );
  }

  testWidgets('German at text scale 2.0 on a 360 × 780 phone with both '
      'defaults set lays out, every title as whole as its row allows and '
      'every value under its title, inside the tile', (tester) async {
    await pumpPage(
      tester,
      surface: phone,
      locale: const Locale('de'),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Feiertags-Kalender'), findsOneWidget);
    expectTitleWhole(tester, 'Feiertags-Kalender');

    // The set's name, a value the tile measures: under the description,
    // inside the tile, whole.
    const name = 'Christlich (West)';
    final description = lookupAppLocalizations(
      const Locale('de'),
    ).holidayProfileDesc;
    final holidayTile = tester.getRect(tileOf('Feiertags-Kalender'));
    final nameRect = tester.getRect(find.text(name));
    expect(
      nameRect.right,
      lessThanOrEqualTo(holidayTile.right - FormMetrics.rowEndPadding),
    );
    expect(
      nameRect.top,
      greaterThanOrEqualTo(tester.getRect(find.text(description)).bottom),
    );
    expectWholeWords(tester, name, title: 'Feiertags-Kalender');
    expectUnclipped(tester, name);

    // The one row left of the alerts section (D5), last in More settings:
    // its value line is both defaults read back, and the page lays out down
    // to it. The rows themselves are `alert_settings_page_test.dart`'s.
    await scrollTo(tester, 'Einstellungen für Erinnerungen');
    expect(tester.takeException(), isNull);
    expectTitleWhole(tester, 'Einstellungen für Erinnerungen');
    expectUnclipped(
      tester,
      'Termine mit Uhrzeit · Alarm · 10 Min. vorher\n'
      'Ganztägige Termine · Mitteilung · Am Vortag, 09:00',
    );
  });

  testWidgets('German at text scale 2.0 on a 360 × 780 phone: the holiday '
      'set\'s subtitle holds its words where the column allows', (
    tester,
  ) async {
    await pumpPage(
      tester,
      surface: phone,
      locale: const Locale('de'),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    // What the set is for (N99); the set's name is the row's value alone.
    final description = lookupAppLocalizations(
      const Locale('de'),
    ).holidayProfileDesc;
    expectWholeWords(tester, description, title: 'Feiertags-Kalender');
    expectUnclipped(tester, description);
    expect(
      find.descendant(
        of: find.byType(HighlightedText),
        matching: find.text('Christlich (West)'),
      ),
      findsNothing,
    );
  });

  testWidgets('the page reads Holidays · More settings · Filtering · Events, '
      'More settings holding Appearance · Categories · Fasting · Alert '
      'settings, and ends with no reset', (tester) async {
    await pumpPage(
      tester,
      surface: const Size(900, 2000),
      locale: const Locale('en'),
    );
    expect(tester.takeException(), isNull);

    final cards = tester
        .widgetList<SettingsSectionCard>(find.byType(SettingsSectionCard))
        .map((card) => (card.section.id, card.section.title))
        .toList();
    expect(cards, const [
      ('calendar', 'Holidays'),
      ('pages', 'More settings'),
      ('filtering', 'Filtering'),
      ('events', 'Events'),
    ]);

    double topOf(String id) =>
        tester.getTopLeft(find.bySemanticsIdentifier(id)).dy;
    Finder inCard(String section, String id) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is SettingsSectionCard && w.section.id == section,
      ),
      matching: find.bySemanticsIdentifier(id),
    );
    const pages = [
      SemanticsIds.calendarAppearanceOpen,
      SemanticsIds.calendarCategoriesOpen,
      SemanticsIds.calendarSettingsFastingOpen,
      SemanticsIds.calendarSettingsAlertsOpen,
    ];
    for (final id in pages) {
      expect(inCard('pages', id), findsOneWidget, reason: id);
    }
    for (var i = 1; i < pages.length; i++) {
      expect(topOf(pages[i]), greaterThan(topOf(pages[i - 1])));
    }
    expect(
      inCard('calendar', SemanticsIds.calendarHolidayProfile),
      findsOneWidget,
    );
    expect(
      inCard('calendar', SemanticsIds.calendarRemovedHolidaysOpen),
      findsOneWidget,
    );
    expect(
      inCard('filtering', SemanticsIds.calendarShowFilterChips),
      findsOneWidget,
    );
    for (final id in const [
      SemanticsIds.calendarEventTemplatesOpen,
      SemanticsIds.calendarDescriptionLimit,
      SemanticsIds.calendarDeleteAllEvents,
    ]) {
      expect(inCard('events', id), findsOneWidget, reason: id);
    }
    expect(find.text('Reset to defaults'), findsNothing);
  });

  // The holiday set's name was cut with an ellipsis in its dropdown at 2.0
  // ("Creștin (occidental)"); as the row's value it is whole like the rest.
  for (final locale in const [Locale('de'), Locale('ro')]) {
    testWidgets('${locale.languageCode} at text scale 2.0 on a 360 × 780 '
        'phone: every text the section list lays out is whole, top to '
        'bottom, the holiday set\'s name included', (tester) async {
      await pumpPage(
        tester,
        surface: phone,
        locale: locale,
        textScale: 2.0,
        density: VisualDensity.standard,
      );
      final name = PublicHolidays.profileNameOf(
        HolidayProfile.generic,
        lookupAppLocalizations(locale),
      );
      expect(find.text(name), findsOneWidget);
      expectUnclipped(tester, name);
      // The whole page, the bar's title and the search hint with it: the
      // German hint was cut until it said "Suchen".
      await expectPageWhole(tester);
    });
  }

  // Three traditions on, so the Fasting row's value is the longest it gets
  // short of all four: each name whole, each dot held to the name after it.
  for (final locale in const [Locale('de'), Locale('ro')]) {
    testWidgets('${locale.languageCode} at text scale 2.0 on a 360 × 780 '
        'phone with three traditions on: the page lays out to its end with '
        'no overflow, the Fasting row whole on the way, no word broken', (
      tester,
    ) async {
      const traditions = {
        FastingTradition.orthodox,
        FastingTradition.catholic,
        FastingTradition.jewish,
      };
      await tester.runAsync(() => settings.setFastingTraditions(traditions));
      await pumpPage(
        tester,
        surface: phone,
        locale: locale,
        textScale: 2.0,
        density: VisualDensity.standard,
      );
      final row = find.bySemanticsIdentifier(
        SemanticsIds.calendarSettingsFastingOpen,
      );
      await expectPageWhole(tester, within: row);

      // The pass went by the row; back up to it to see it held the three.
      await tester.scrollUntilVisible(
        row,
        -300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final l10n = lookupAppLocalizations(locale);
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            FastingSettingsPage.summary(l10n, traditions: traditions),
          ),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('the cap the page holds a value to is the constraint a tile '
      'hands its trailing, at the phone\'s density and the desktop\'s', (
    tester,
  ) async {
    for (final density in [VisualDensity.standard, VisualDensity.compact]) {
      double? handed;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(visualDensity: density),
          home: Scaffold(
            body: ListTile(
              title: const Text('A row'),
              trailing: LayoutBuilder(
                builder: (context, constraints) {
                  handed = constraints.maxHeight;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(handed, isNotNull, reason: '$density');
      expect(
        listTileTrailingCap(tester.element(find.byType(ListTile))),
        handed,
        reason: '$density',
      );
    }
  });

  testWidgets('where everything fits the holiday row is the stock tile: the '
      'set\'s name beside the title', (tester) async {
    await pumpPage(
      tester,
      surface: const Size(900, 2000),
      locale: const Locale('en'),
    );
    expect(tester.takeException(), isNull);

    const name = 'Christian (Western)';
    final trailing = tester.widget<ListTile>(tileOf('Holiday set')).trailing;
    expect(trailing, isNotNull);
    expect(
      find.descendant(of: find.byWidget(trailing!), matching: find.text(name)),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.text(name)).left,
      greaterThan(tester.getRect(find.text('Holiday set')).right),
    );
  });

  testWidgets('German at text scale 2.0 on a 360 × 780 phone: the holiday '
      'set\'s menu lists every set whole, the current one checked', (
    tester,
  ) async {
    await pumpPage(
      tester,
      surface: phone,
      locale: const Locale('de'),
      textScale: 2.0,
      density: VisualDensity.standard,
    );
    await tester.tap(find.text('Christlich (West)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final l10n = lookupAppLocalizations(const Locale('de'));
    for (final profile in HolidayProfile.values) {
      final item = find.bySemanticsIdentifier(
        SemanticsIds.calendarHolidayProfileItem(profile.name),
      );
      expect(item, findsOneWidget, reason: profile.name);
      final label = find.descendant(
        of: find.byType(FormMenuChoiceItem<HolidayProfile>),
        matching: find.text(PublicHolidays.profileNameOf(profile, l10n)),
      );
      expect(label, findsOneWidget, reason: profile.name);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
        reason: '${profile.name} is cut short',
      );
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.textSize.width - 0.01),
        reason: '${profile.name} is cut at the side',
      );
    }
    final checked = tester
        .widgetList<FormMenuChoiceItem<HolidayProfile>>(
          find.byType(FormMenuChoiceItem<HolidayProfile>),
        )
        .where((item) => item.checked)
        .map((item) => item.value);
    expect(checked, [HolidayProfile.generic]);
  });
}
