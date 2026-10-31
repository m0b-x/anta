import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/pages/fasting_settings_page.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/fasting_schedule_sheet.dart';
import 'package:anta/widgets/fasting_style_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/fasting_schedule_robot.dart';
import 'support/fasting_settings_robot.dart';
import 'support/fasting_style_robot.dart';
import 'support/page_route_recorder.dart';
import 'support/settings_page_whole.dart';

/// Fasting settings (D6): the rows that left Calendar settings, re-pinned on
/// their own page — the tradition switches, each look row and the practice
/// row through their live sheets, the multi-day fasts switch — every one
/// disabled rather than hidden while it has nothing to act on (S14), the
/// N109 caption swapping in a slot that never moves the switch, the
/// how-it-works row, the fold set, and the large-text cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  late AppDatabase db;
  late SettingsService settings;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    CalendarPaletteService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// The app's own theme, light or [dark]. [density] is the theme's: left
  /// out, the host's — compact on a desktop, which is where these tests run;
  /// `VisualDensity.standard` is the phone's.
  Future<void> pumpPage(
    WidgetTester tester, {
    Size surface = const Size(800, 3000),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    VisualDensity? density,
    List<NavigatorObserver> observers = const [],
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: density == null ? theme : theme.copyWith(visualDensity: density),
        navigatorObservers: observers,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const FastingSettingsPage(),
      ),
    );
    await FastingSettingsRobot(tester).settle();
  }

  Future<void> seedTraditions(Set<FastingTradition> traditions) =>
      settings.setFastingTraditions(traditions);

  Future<void> teardownApp(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  String lookId(FastingTradition tradition) =>
      SemanticsIds.calendarFastingStyleOpen(tradition.name);

  String switchId(FastingTradition tradition) =>
      SemanticsIds.fastingTraditionSwitch(tradition.name);

  String styleSummary(FastingTraditionStyle style) =>
      '${FastingCalendar.styleNameOf(style.style, l10n)}\u00A0· '
      '${FastingCalendar.placementNameOf(style.placement, l10n)}';

  /// The row [id] shows [text] somewhere inside it.
  void expectRowSays(String id, String text) => expect(
    find.descendant(
      of: find.bySemanticsIdentifier(id),
      matching: find.text(text),
    ),
    findsOneWidget,
  );

  /// Row [id] is on screen and disabled as the language draws it: no tap,
  /// announced disabled, its title in the theme's disabled grey and, on a
  /// row with a leading [glyph] (a sub-row has none), that glyph at 38 %.
  void expectDisabled(
    WidgetTester tester,
    String id,
    String title, {
    bool glyph = false,
  }) {
    final robot = FastingSettingsRobot(tester);
    expect(robot.row(id), findsOneWidget, reason: id);
    expect(robot.isEnabled(id), isFalse, reason: id);
    final theme = Theme.of(tester.element(find.byType(FastingSettingsPage)));
    expect(robot.textColor(id, title), theme.disabledColor, reason: id);
    if (glyph) {
      expect(
        robot.glyphColor(id)!.a,
        closeTo(FormMetrics.disabledOpacity, 0.01),
        reason: id,
      );
    }
  }

  void expectEnabled(WidgetTester tester, String id) {
    final robot = FastingSettingsRobot(tester);
    expect(robot.row(id), findsOneWidget, reason: id);
    expect(robot.isEnabled(id), isTrue, reason: id);
  }

  group('the page', () {
    testWidgets('three sections in order — Traditions, Your practice, How it '
        'works — every row with its id, under the bar\'s', (tester) async {
      await pumpPage(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsBarFasting),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.fastingSettingsList),
        findsOneWidget,
      );
      final headers = [
        l10n.fastingSectionTraditions,
        l10n.fastingPracticeRow,
        l10n.calendarGuideHowItWorks,
      ];
      final tops = [
        for (final title in headers)
          tester.getTopLeft(find.text(title.toUpperCase())).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: headers[i]);
      }
      // Each tradition's switch, then its look row right under it, and
      // Orthodox's multi-day fasts under its look row.
      var previous = tops.first;
      for (final tradition in FastingTradition.values) {
        for (final id in [
          switchId(tradition),
          lookId(tradition),
          if (tradition == FastingTradition.orthodox)
            SemanticsIds.fastingGreatFastsSwitch,
        ]) {
          final top = tester.getTopLeft(find.bySemanticsIdentifier(id)).dy;
          expect(top, greaterThan(previous), reason: id);
          expect(top, lessThan(tops[1]), reason: id);
          previous = top;
        }
      }
      for (final id in const [
        SemanticsIds.calendarFastingScheduleOpen,
        SemanticsIds.fastingSettingsHowItWorksOpen,
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
      expectRowSays(lookId(FastingTradition.orthodox), l10n.fastingLookRow);
      expectRowSays(
        SemanticsIds.calendarFastingScheduleOpen,
        l10n.fastingPracticeRow,
      );
      expectRowSays(
        SemanticsIds.fastingSettingsHowItWorksOpen,
        l10n.calendarGuidePageFasting,
      );

      await teardownApp(tester);
    });

    testWidgets('with no tradition on, nothing is hidden: every look row, '
        'Multi-day fasts and Your practice stand disabled', (tester) async {
      await pumpPage(tester);

      for (final tradition in FastingTradition.values) {
        expectEnabled(tester, switchId(tradition));
        expectDisabled(tester, lookId(tradition), l10n.fastingLookRow);
      }
      expectDisabled(
        tester,
        SemanticsIds.fastingGreatFastsSwitch,
        l10n.fastingOrthodoxGreatFasts,
      );
      expectDisabled(
        tester,
        SemanticsIds.calendarFastingScheduleOpen,
        l10n.fastingPracticeRow,
        glyph: true,
      );

      // A tap on a disabled row opens nothing.
      await FastingSettingsRobot(
        tester,
      ).tapRow(lookId(FastingTradition.orthodox));
      await FastingSettingsRobot(
        tester,
      ).tapRow(SemanticsIds.calendarFastingScheduleOpen);
      expect(find.byType(FastingStyleSheet), findsNothing);
      expect(find.byType(FastingScheduleSheet), findsNothing);

      await teardownApp(tester);
    });

    testWidgets('a sub-row has no glyph: its title and caption start in its '
        'switch\'s title column', (tester) async {
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester, density: VisualDensity.standard);

      double leftOf(String id, String text) => tester
          .getTopLeft(
            find.descendant(of: robot.row(id), matching: find.text(text)).last,
          )
          .dx;

      for (final tradition in FastingTradition.values) {
        final column = leftOf(
          switchId(tradition),
          FastingCalendar.traditionNameOf(tradition, l10n),
        );
        final subRows = {
          lookId(tradition): [
            l10n.fastingLookRow,
            styleSummary(const FastingTraditionStyle()),
          ],
          if (tradition == FastingTradition.orthodox)
            SemanticsIds.fastingGreatFastsSwitch: [
              l10n.fastingOrthodoxGreatFasts,
              l10n.fastingOrthodoxGreatFastsDesc,
            ],
        };
        for (final MapEntry(key: id, value: texts) in subRows.entries) {
          expect(robot.tile(id).leading, isNull, reason: id);
          for (final text in texts) {
            expect(leftOf(id, text), column, reason: '$id: $text');
          }
        }
      }

      await teardownApp(tester);
    });

    testWidgets('a fold is kept under the fasting_ prefix in the calendar '
        'settings set, beside that page\'s own `fasting` fold, which folds '
        'nothing here', (tester) async {
      final robot = FastingSettingsRobot(tester);
      await tester.runAsync(
        () => settings.setCalendarSettingsCollapsedSections(const {'fasting'}),
      );
      await pumpPage(tester);
      expect(robot.row(switchId(FastingTradition.orthodox)), findsOneWidget);

      await robot.toggleSection(l10n.fastingSectionTraditions);

      expect(robot.row(switchId(FastingTradition.orthodox)), findsNothing);
      expect(
        robot.row(SemanticsIds.calendarFastingScheduleOpen),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(settings.getCalendarSettingsCollapsedSections),
        {'fasting', 'fasting_traditions'},
      );

      await robot.toggleSection(l10n.fastingSectionTraditions);
      expect(
        await tester.runAsync(settings.getCalendarSettingsCollapsedSections),
        {'fasting'},
      );

      await teardownApp(tester);
    });
  });

  group('traditions', () {
    testWidgets('turning Catholic on writes the traditions and enables its '
        'look row and Your practice; the others stay as they were', (
      tester,
    ) async {
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);

      await robot.toggle(switchId(FastingTradition.catholic));

      expect(await tester.runAsync(settings.getFastingTraditions), {
        FastingTradition.catholic,
      });
      expectEnabled(tester, lookId(FastingTradition.catholic));
      expectEnabled(tester, SemanticsIds.calendarFastingScheduleOpen);
      expectDisabled(
        tester,
        lookId(FastingTradition.orthodox),
        l10n.fastingLookRow,
      );
      expectDisabled(
        tester,
        SemanticsIds.fastingGreatFastsSwitch,
        l10n.fastingOrthodoxGreatFasts,
      );

      await robot.toggle(switchId(FastingTradition.catholic));

      expect(await tester.runAsync(settings.getFastingTraditions), isEmpty);
      expectDisabled(
        tester,
        lookId(FastingTradition.catholic),
        l10n.fastingLookRow,
      );
      expectDisabled(
        tester,
        SemanticsIds.calendarFastingScheduleOpen,
        l10n.fastingPracticeRow,
        glyph: true,
      );

      await teardownApp(tester);
    });

    testWidgets('the rows a tradition enables are enabled in the frame its '
        'switch flips, not after the write lands', (tester) async {
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: robot.row(switchId(FastingTradition.catholic)),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();

      expect(robot.isEnabled(lookId(FastingTradition.catholic)), isTrue);
      expect(robot.isEnabled(SemanticsIds.calendarFastingScheduleOpen), isTrue);

      await robot.settle();
      await teardownApp(tester);
    });

    testWidgets('a look row whose tradition is off reads back the style '
        'stored for it, so turning the tradition on shows what was there', (
      tester,
    ) async {
      const stored = FastingTraditionStyle(
        style: FastingDisplayStyle.bar,
        placement: FastingRowPlacement.first,
      );
      await tester.runAsync(
        () => settings.setFastingAppearance(
          const FastingAppearance(
            byTradition: {FastingTradition.catholic: stored},
          ),
        ),
      );
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);
      final id = lookId(FastingTradition.catholic);

      expectDisabled(tester, id, l10n.fastingLookRow);
      expectRowSays(id, styleSummary(stored));

      await robot.toggle(switchId(FastingTradition.catholic));

      expectEnabled(tester, id);
      expectRowSays(id, styleSummary(stored));

      await teardownApp(tester);
    });

    testWidgets('the four look rows share their visible title, and each is '
        'spoken under a name of its own that leads with its tradition', (
      tester,
    ) async {
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);

      final labels = <String>{};
      for (final tradition in FastingTradition.values) {
        final id = lookId(tradition);
        expectRowSays(id, l10n.fastingLookRow);
        final label = tester
            .getSemantics(
              find
                  .descendant(
                    of: robot.row(id),
                    matching: find.byType(ListTile),
                  )
                  .first,
            )
            .getSemanticsData()
            .label;
        expect(
          label,
          startsWith(
            '${FastingCalendar.traditionNameOf(tradition, l10n)}, '
            '${l10n.fastingLookRow}',
          ),
          reason: id,
        );
        labels.add(label);
      }
      expect(labels, hasLength(FastingTradition.values.length));

      await teardownApp(tester);
    });

    testWidgets('a look row opens the style sheet after the palette prewarm; '
        'a style picked there is written and read back on the row', (
      tester,
    ) async {
      const custom = 0xFF2E7D6B;
      await tester.runAsync(() async {
        await seedTraditions(const {FastingTradition.orthodox});
        await settings.setCustomCalendarColors(const [custom]);
      });
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);

      // The facade the sheet's swatch strip reads synchronously is up before
      // any row can be tapped.
      expect(CalendarPalette.custom, const [custom]);
      final id = lookId(FastingTradition.orthodox);
      expectRowSays(id, styleSummary(const FastingTraditionStyle()));

      await robot.tapRow(id);
      expect(find.byType(FastingStyleSheet), findsOneWidget);

      final style = FastingStyleRobot(tester);
      await style.pickStyle(FastingDisplayStyle.bar);
      await robot.settle();

      final stored = await tester.runAsync(settings.getFastingAppearance);
      expect(
        stored!.styleFor(FastingTradition.orthodox).style,
        FastingDisplayStyle.bar,
      );
      expectRowSays(
        id,
        styleSummary(
          const FastingTraditionStyle(style: FastingDisplayStyle.bar),
        ),
      );

      await style.close();
      await robot.settle();
      expect(find.byType(FastingStyleSheet), findsNothing);

      await teardownApp(tester);
    });
  });

  group('multi-day fasts', () {
    const greatFastsId = SemanticsIds.fastingGreatFastsSwitch;

    /// [text] is the caption shown: the template and the shown line both
    /// read it, and the one painted is the last, outside every zero opacity.
    void expectShown(WidgetTester tester, String text) {
      final lines = find.descendant(
        of: FastingSettingsRobot(tester).row(greatFastsId),
        matching: find.text(text),
      );
      expect(lines, findsNWidgets(2), reason: text);
      expect(
        find.ancestor(of: lines.last, matching: find.byType(Opacity)),
        findsNothing,
        reason: text,
      );
    }

    /// The switch's rect in the list's own coordinates, so a scroll a step
    /// takes on its way cannot pass for the switch moving.
    Rect switchInList(WidgetTester tester) {
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      return FastingSettingsRobot(
        tester,
      ).switchRect(greatFastsId).shift(Offset(0, position.pixels));
    }

    testWidgets('a stored off reads as N109 whether Orthodox is off or on, a '
        'stored on as the fasts, and the switch keeps one rect through all '
        'four states', (tester) async {
      await tester.runAsync(() => settings.setFastingOrthodoxGreatFasts(false));
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester, surface: const Size(360, 780));
      await tester.ensureVisible(robot.row(greatFastsId));
      await tester.pump();

      // Orthodox off, stored off.
      expectDisabled(tester, greatFastsId, l10n.fastingOrthodoxGreatFasts);
      expectShown(tester, l10n.fastingGreatFastsOffDesc);
      final rect = switchInList(tester);

      // Orthodox on, stored off.
      await robot.toggle(switchId(FastingTradition.orthodox));
      expectEnabled(tester, greatFastsId);
      expectShown(tester, l10n.fastingGreatFastsOffDesc);
      expect(switchInList(tester), rect);

      // Orthodox on, stored on.
      await robot.toggle(greatFastsId);
      expect(
        await tester.runAsync(settings.getFastingOrthodoxGreatFasts),
        isTrue,
      );
      expectEnabled(tester, greatFastsId);
      expectShown(tester, l10n.fastingOrthodoxGreatFastsDesc);
      expect(switchInList(tester), rect);

      // Orthodox off, stored on.
      await robot.toggle(switchId(FastingTradition.orthodox));
      expectDisabled(tester, greatFastsId, l10n.fastingOrthodoxGreatFasts);
      expectShown(tester, l10n.fastingOrthodoxGreatFastsDesc);
      expect(switchInList(tester), rect);

      await teardownApp(tester);
    });

    testWidgets('disabled while Orthodox is off, enabled once it is on', (
      tester,
    ) async {
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);
      expectDisabled(
        tester,
        SemanticsIds.fastingGreatFastsSwitch,
        l10n.fastingOrthodoxGreatFasts,
      );

      await robot.toggle(switchId(FastingTradition.orthodox));

      expectEnabled(tester, SemanticsIds.fastingGreatFastsSwitch);
      expectEnabled(tester, lookId(FastingTradition.orthodox));

      await teardownApp(tester);
    });

    testWidgets('a toggle writes the switch and swaps the caption between '
        'the fasts and the N109 sentence, the switch never moving', (
      tester,
    ) async {
      await tester.runAsync(
        () => seedTraditions(const {FastingTradition.orthodox}),
      );
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester, surface: const Size(360, 780));
      const id = greatFastsId;
      await tester.ensureVisible(robot.row(id));
      await tester.pump();

      final onRect = robot.switchRect(id);
      final onRow = tester.getRect(robot.row(id));
      expectShown(tester, l10n.fastingOrthodoxGreatFastsDesc);

      await robot.toggle(id);

      expect(
        await tester.runAsync(settings.getFastingOrthodoxGreatFasts),
        isFalse,
      );
      expect(robot.switchRect(id), onRect);
      expect(tester.getRect(robot.row(id)), onRow);
      expectShown(tester, l10n.fastingGreatFastsOffDesc);

      await robot.toggle(id);

      expect(
        await tester.runAsync(settings.getFastingOrthodoxGreatFasts),
        isTrue,
      );
      expect(robot.switchRect(id), onRect);
      expectShown(tester, l10n.fastingOrthodoxGreatFastsDesc);

      await teardownApp(tester);
    });
  });

  group('your practice', () {
    testWidgets('with a tradition on, the row opens the schedule sheet; a '
        'weekday picked there is written and the summary follows', (
      tester,
    ) async {
      await tester.runAsync(
        () => seedTraditions(const {FastingTradition.catholic}),
      );
      final robot = FastingSettingsRobot(tester);
      await pumpPage(tester);
      const id = SemanticsIds.calendarFastingScheduleOpen;
      expectRowSays(id, 'Wed, Fri\u00A0· All year');

      await robot.tapRow(id);
      expect(find.byType(FastingScheduleSheet), findsOneWidget);

      final schedule = FastingScheduleRobot(tester);
      await schedule.toggleWeekday(DateTime.monday);
      await robot.settle();

      expect((await tester.runAsync(settings.getFastingSchedule))!.weekdays, {
        DateTime.monday,
        ...FastingSchedule.defaultWeekdays,
      });
      expectRowSays(id, 'Mon, Wed, Fri\u00A0· All year');

      await schedule.close();
      await robot.settle();
      expect(find.byType(FastingScheduleSheet), findsNothing);

      await teardownApp(tester);
    });
  });

  testWidgets('How it works pushes the guide\'s fasting topic, unstamped '
      '(D12)', (tester) async {
    final observer = PageRouteRecorder();
    await pumpPage(tester, observers: [observer]);
    observer.pushed.clear();

    await FastingSettingsRobot(
      tester,
    ).tapRowUnbuilt(SemanticsIds.fastingSettingsHowItWorksOpen);

    final route = observer.pushed.single as MaterialPageRoute<Object?>;
    expect(route.settings.arguments, isNull);
    final topicPage = route.builder(
      tester.element(find.byType(FastingSettingsPage)),
    );
    expect(topicPage, isA<CalendarGuideTopicPage>());
    expect(
      (topicPage as CalendarGuideTopicPage).topic,
      CalendarGuideTopic.fasting,
    );

    await teardownApp(tester);
  });

  // Roboto is loaded, so a word is as wide as a phone draws it. Orthodox is
  // on, so every kind of row is laid out — enabled, disabled and the
  // caption slot's template.
  group('large text', () {
    setUp(() => seedTraditions(const {FastingTradition.orthodox}));

    testWidgets('English at 1.0 on a 412 × 915 phone lays out to the end '
        'whole', (tester) async {
      await pumpPage(
        tester,
        surface: const Size(412, 915),
        density: VisualDensity.standard,
      );
      await expectPageWhole(tester);

      await teardownApp(tester);
    });

    for (final (locale, scale, dark) in const [
      (Locale('en'), 1.0, false),
      (Locale('de'), 2.0, false),
      (Locale('de'), 2.0, true),
      (Locale('ro'), 2.0, false),
      (Locale('ro'), 2.0, true),
    ]) {
      testWidgets('${locale.languageCode} at $scale on a 360 × 780 phone, '
          '${dark ? 'dark' : 'light'}: every paragraph down to the last row '
          'whole, uncut and unbroken inside a word, no overflow', (
        tester,
      ) async {
        await pumpPage(
          tester,
          surface: const Size(360, 780),
          locale: locale,
          textScale: scale,
          dark: dark,
          density: VisualDensity.standard,
        );
        await expectPageWhole(tester);

        await teardownApp(tester);
      });
    }
  });
}
