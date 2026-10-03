import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/public_holidays.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';

/// Calendar settings at a large text scale. `ListTile` gives its trailing
/// whatever width it asks for and the title the rest, so the holiday set's
/// dropdown — as wide as the widest profile's name — took the whole tile in
/// German at 200 % and the page would not lay out, and a default alert read
/// back squeezed "Ganztägige Termine" to a letter a line (the Tier 2 device
/// pass). The rows now yield to their text column: the value wraps in what
/// the title's and the subtitle's longest word leave, while it fits the
/// height the tile gives a trailing there, and goes under the description
/// otherwise.
///
/// The test font draws every glyph a full em wide, about twice a phone's
/// font, so a German word can be wider than the whole text column here
/// ("Ganztägige" at 200 %: 285 dp in 232). A title is therefore asserted to
/// be as whole as its column allows, never narrower than that.
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
      tester.getRect(tileOf(title)).width - 32 - 40 - 16;

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

  /// The lines [text] was laid out on.
  int linesOf(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    return paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        )
        .map((box) => box.top.round())
        .toSet()
        .length;
  }

  /// The value of the row titled [title] sits in the tile's trailing, beside
  /// the title, whole.
  void expectBeside(WidgetTester tester, String title, String value) {
    final tile = tester.widget<ListTile>(tileOf(title));
    expect(tile.trailing, isNotNull, reason: '"$value" is not beside');
    expect(
      find.descendant(
        of: find.byWidget(tile.trailing!),
        matching: find.text(value),
      ),
      findsOneWidget,
    );
    expectUnclipped(tester, value);
    expectWholeWords(tester, value, title: title);
  }

  /// The value of the row titled [title] sits under the description, inside
  /// the tile, whole.
  void expectUnder(WidgetTester tester, String title, String value) {
    expect(
      tester.widget<ListTile>(tileOf(title)).trailing,
      isNull,
      reason: '"$value" is not under its title',
    );
    final tile = tester.getRect(tileOf(title));
    final valueRect = tester.getRect(find.text(value));
    expect(
      valueRect.top,
      greaterThanOrEqualTo(tester.getRect(find.text(title)).bottom),
      reason: '"$value" is not under its title',
    );
    expect(valueRect.right, lessThanOrEqualTo(tile.right - 16));
    expect(valueRect.left, greaterThanOrEqualTo(tile.left + 16));
    expectUnclipped(tester, value);
    expectWholeWords(tester, value, title: title);
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
    expect(find.text('Feiertage'), findsOneWidget);
    expectTitleWhole(tester, 'Feiertage');

    // The dropdown, bounded: under its title, inside the tile, its menu
    // sized for its names and the shown name cut rather than the tile.
    final dropdown = find.byType(DropdownButton<HolidayProfile>);
    expect(dropdown, findsOneWidget);
    final holidayTile = tester.getRect(tileOf('Feiertage'));
    final dropdownRect = tester.getRect(dropdown);
    expect(dropdownRect.right, lessThanOrEqualTo(holidayTile.right - 16));
    expect(
      dropdownRect.top,
      greaterThanOrEqualTo(tester.getRect(find.text('Feiertage')).bottom),
    );
    expect(dropdownRect.height, kMinInteractiveDimension);
    final button = tester.widget<DropdownButton<HolidayProfile>>(dropdown);
    expect(button.selectedItemBuilder, isNotNull);
    expect(button.menuWidth, columnOf(tester, 'Feiertage'));
    expect(button.itemHeight, isNull);

    // The list builds its rows as they come into view, so each alert row is
    // read once the page has been scrolled down to it. The values — a
    // sentence each — wrap under their title with the text column's width,
    // never beside it, and every line of them is painted.
    for (final MapEntry(key: title, value: value) in const {
      'Termine mit Uhrzeit': 'Alarm · 10 Min. vorher',
      'Ganztägige Termine': 'Mitteilung · Am Vortag, 09:00',
      'Weckton': 'Standard-Weckton des Telefons',
    }.entries) {
      await scrollTo(tester, title);
      expect(tester.takeException(), isNull);
      expectTitleWhole(tester, title);
      expectUnder(tester, title, value);
    }
  });

  testWidgets('German at text scale 2.0 on a 360 × 780 phone with the all-day '
      'default at Alarm · a week before: that value and the alarm sound\'s '
      'are whole and uncut under their titles, and every subtitle holds its '
      'words where the column allows', (tester) async {
    await settings.setAlertDefaultAllDay((
      mode: AlertMode.ring,
      daysBefore: 7,
      dayMinute: 9 * 60,
    ));
    await pumpPage(
      tester,
      surface: phone,
      locale: const Locale('de'),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
    // The profile's name is the subtitle and the dropdown's shown item alike;
    // the subtitle is the kit's highlighted text.
    expectWholeWords(
      tester,
      'Christlich (West)',
      title: 'Feiertage',
      finder: find.descendant(
        of: find.byType(HighlightedText),
        matching: find.text('Christlich (West)'),
      ),
    );

    // Every value row, each read once scrolled to: a value taller beside the
    // title than the tile lets a trailing be is under the description, with
    // the column's width and every line of it painted; so is each subtitle's
    // word, where the column allows.
    for (final (title, value, subtitle) in const [
      (
        'Termine mit Uhrzeit',
        'Alarm · 10 Min. vorher',
        'Die Erinnerung, mit der ein neuer Termin mit Uhrzeit startet',
      ),
      (
        'Ganztägige Termine',
        'Alarm · 7 Tage vorher, 09:00',
        'Die Erinnerung, mit der ein neuer ganztägiger Termin startet',
      ),
      (
        'Weckton',
        'Standard-Weckton des Telefons',
        'Was ein Alarm spielt, wenn die Erinnerung keinen Ton nennt',
      ),
    ]) {
      await scrollTo(tester, title);
      expect(tester.takeException(), isNull);
      expectTitleWhole(tester, title);
      expectUnder(tester, title, value);
      expectWholeWords(tester, subtitle, title: title);
    }
  });

  testWidgets('a value that fits the cap the tile gives a trailing stays '
      'beside the title, one that does not goes under: one line beside at '
      '2.0, two lines under at 2.0, two lines beside at 1.0', (tester) async {
    // The phone's density, so the cap is the phone's 56 dp.
    const density = VisualDensity.standard;
    // No all-day default: "No alert" is one line at any width.
    await settings.setAlertDefaultAllDay(null);
    await pumpPage(
      tester,
      surface: const Size(600, 1000),
      locale: const Locale('en'),
      textScale: 2.0,
      density: density,
    );
    expect(tester.takeException(), isNull);
    await scrollTo(tester, 'All-day events');
    expect(tester.takeException(), isNull);

    // Two lines of the trailing style at 200 % are taller than the cap, so
    // the second line's descenders would be cut beside the title.
    const timed = 'Alarm · 10 min before';
    expectUnder(tester, 'Timed events', timed);
    expect(linesOf(tester, timed), 2);
    expectBeside(tester, 'All-day events', 'No alert');
    expect(linesOf(tester, 'No alert'), 1);
  });

  testWidgets('at 1.0 a two-line value fits the cap and stays beside the '
      'title, whole', (tester) async {
    await pumpPage(
      tester,
      surface: const Size(412, 915),
      locale: const Locale('en'),
      density: VisualDensity.standard,
    );
    expect(tester.takeException(), isNull);
    await scrollTo(tester, 'All-day events');
    expect(tester.takeException(), isNull);

    const timed = 'Alarm · 10 min before';
    expectBeside(tester, 'Timed events', timed);
    expect(linesOf(tester, timed), 2);
    const allDay = 'Reminder · The day before, 9:00 AM';
    expectBeside(tester, 'All-day events', allDay);
    expect(linesOf(tester, allDay), greaterThanOrEqualTo(2));
  });

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

  testWidgets('where everything fits the rows are the stock tile: the value '
      'and the dropdown beside the title, the dropdown untouched', (
    tester,
  ) async {
    // Wide enough for the test font's names to fit beside their titles.
    await pumpPage(
      tester,
      surface: const Size(900, 2000),
      locale: const Locale('en'),
    );
    expect(tester.takeException(), isNull);
    await scrollTo(tester, 'All-day events');

    for (final MapEntry(key: title, value: value) in const {
      'Timed events': 'Alarm · 10 min before',
      'All-day events': 'Reminder · The day before, 9:00 AM',
    }.entries) {
      final tile = tester.widget<ListTile>(tileOf(title));
      expect(tile.trailing, isNotNull, reason: title);
      expect(
        find.descendant(
          of: find.byWidget(tile.trailing!),
          matching: find.text(value),
        ),
        findsOneWidget,
      );
      // Beside the title, on the title's line.
      final titleRect = tester.getRect(find.text(title));
      final valueRect = tester.getRect(find.text(value));
      expect(valueRect.left, greaterThan(titleRect.right));
      expect(valueRect.top, lessThan(titleRect.bottom));
    }

    final dropdown = find.byType(DropdownButton<HolidayProfile>);
    expect(
      tester.widget<ListTile>(tileOf('Holiday set')).trailing,
      tester.widget(dropdown),
    );
    final button = tester.widget<DropdownButton<HolidayProfile>>(dropdown);
    expect(button.selectedItemBuilder, isNull);
    expect(button.menuWidth, isNull);
    expect(button.itemHeight, kMinInteractiveDimension);
  });
}
