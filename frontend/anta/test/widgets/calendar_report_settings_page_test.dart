import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/report_cards.dart';
import 'package:anta/pages/calendar_report_settings_page.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/report_settings_robot.dart';
import 'support/settings_page_whole.dart' show expectBreaksBetweenWords;

/// Report cards (W): the report's thirteen cards in their stored order,
/// each with a handle and a switch; a toggle or a drag writes the setting at
/// once, an off card keeps its row dimmed, Reset is held while the list is
/// the default and puts it back with a message, and the large-text cases.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  late AppDatabase db;
  late SettingsService settings;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// [density] left out is the host's — compact on a desktop, where these
  /// tests run; `VisualDensity.standard` is the phone's.
  Future<void> pumpPage(
    WidgetTester tester, {
    Size surface = const Size(800, 3000),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    VisualDensity? density,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const CalendarReportSettingsPage(),
      ),
    );
    await ReportSettingsRobot(tester).settle();
  }

  Future<void> teardownApp(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// The setting as the report reads it.
  Future<ReportCards> stored(WidgetTester tester) async {
    final loaded = await tester.runAsync(
      () => settings.getCalendarReportSettings(
        today: DateUtils.dateOnly(DateTime.now()),
      ),
    );
    return loaded!.cards;
  }

  String nameOf(ReportCardKind kind) =>
      CalendarReportSettingsPage.cardName(kind, l10n);

  group('the page', () {
    testWidgets('the thirteen cards in the default order, each named, with '
        'its handle at the start and its switch on at the end; the intro '
        'above them, Reset below and disabled', (tester) async {
      await pumpPage(tester);
      final robot = ReportSettingsRobot(tester);

      expect(find.text(l10n.calendarSettingsReportTitle), findsOneWidget);
      expect(ReportCardKind.values, hasLength(13));
      expect(robot.order(), ReportCardKind.values);
      final introTop = tester
          .getTopLeft(find.text(l10n.calendarSettingsReportDescription))
          .dy;
      expect(
        introTop,
        lessThan(tester.getTopLeft(robot.handleOf(ReportCardKind.goals)).dy),
      );
      for (final kind in ReportCardKind.values) {
        final name = find.text(nameOf(kind));
        expect(name, findsOneWidget, reason: kind.name);
        expect(robot.isOn(kind), isTrue, reason: kind.name);
        expect(robot.isDimmed(nameOf(kind)), isFalse, reason: kind.name);
        // One line: the handle, the name and the switch share a centre.
        final centre = tester.getCenter(name).dy;
        expect(tester.getCenter(robot.handleOf(kind)).dy, closeTo(centre, 1));
        expect(tester.getCenter(robot.switchOf(kind)).dy, closeTo(centre, 1));
        expect(
          tester.getTopLeft(robot.handleOf(kind)).dx,
          lessThan(tester.getTopLeft(name).dx),
        );
        expect(
          tester.getTopRight(robot.switchOf(kind)).dx,
          greaterThan(tester.getTopRight(name).dx),
        );
      }
      expect(
        tester.getTopLeft(robot.reset).dy,
        greaterThan(tester.getTopLeft(robot.handleOf(ReportCardKind.ahead)).dy),
      );
      expect(find.text(l10n.reportCardsReset), findsOneWidget);
      expect(robot.isResetEnabled(), isFalse);

      await teardownApp(tester);
    });

    testWidgets('the switch is named by its card and says it is on; the '
        'handle is named "Reorder …"; both are 48 dp targets', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester, density: VisualDensity.standard);
      final robot = ReportSettingsRobot(tester);

      for (final kind in ReportCardKind.values) {
        final toggle = tester
            .getSemantics(robot.switchOf(kind))
            .getSemanticsData();
        expect(toggle.label, nameOf(kind), reason: kind.name);
        expect(
          toggle.flagsCollection.isToggled,
          Tristate.isTrue,
          reason: kind.name,
        );
        expect(
          tester.getSemantics(robot.handleOf(kind)).getSemanticsData().label,
          l10n.categoryReorderLabel(nameOf(kind)),
          reason: kind.name,
        );
        final handleSize = tester.getSize(robot.handleOf(kind));
        expect(handleSize.width, greaterThanOrEqualTo(48), reason: kind.name);
        expect(handleSize.height, greaterThanOrEqualTo(48), reason: kind.name);
        expect(
          tester.getSize(robot.switchOf(kind)).height,
          greaterThanOrEqualTo(48),
          reason: kind.name,
        );
      }

      await teardownApp(tester);
      handle.dispose();
    });

    testWidgets('a stored order and an off card are read back on open', (
      tester,
    ) async {
      final saved = ReportCards.defaults
          .moved(0, 12)
          .toggled(ReportCardKind.insights, false);
      await tester.runAsync(() => settings.setReportCards(saved));
      await pumpPage(tester);
      final robot = ReportSettingsRobot(tester);

      expect(robot.order(), [
        ...ReportCardKind.values.skip(1),
        ReportCardKind.goals,
      ]);
      expect(robot.isOn(ReportCardKind.insights), isFalse);
      expect(robot.isDimmed(nameOf(ReportCardKind.insights)), isTrue);
      expect(robot.isOn(ReportCardKind.goals), isTrue);
      expect(robot.isResetEnabled(), isTrue);

      await teardownApp(tester);
    });
  });

  group('a toggle', () {
    testWidgets('turning Due soon off writes it at once, dims its name and '
        'keeps its row, its switch and every other row where they were; on '
        'again clears the key', (tester) async {
      await pumpPage(tester);
      final robot = ReportSettingsRobot(tester);
      const kind = ReportCardKind.dueSoon;
      final switchRect = tester.getRect(robot.switchOf(kind));

      await robot.toggle(kind);

      expect(robot.isOn(kind), isFalse);
      expect(robot.isDimmed(nameOf(kind)), isTrue);
      expect(robot.isDimmed(nameOf(ReportCardKind.goals)), isFalse);
      expect(tester.getRect(robot.switchOf(kind)), switchRect);
      expect(robot.order(), ReportCardKind.values);
      final off = await stored(tester);
      expect(off.off, {kind});
      expect(off.order, ReportCardKind.values);
      expect(robot.isResetEnabled(), isTrue);

      await robot.toggle(kind);

      expect(robot.isOn(kind), isTrue);
      expect(robot.isDimmed(nameOf(kind)), isFalse);
      expect(await stored(tester), ReportCards.defaults);
      expect(
        await tester.runAsync(
          () => db.userSettingsDao.getValue(SettingsKeys.reportCards),
        ),
        isNull,
      );
      expect(robot.isResetEnabled(), isFalse);

      await teardownApp(tester);
    });

    testWidgets('a tap on the name toggles too, as a kit switch row does', (
      tester,
    ) async {
      await pumpPage(tester);
      final robot = ReportSettingsRobot(tester);

      await tester.tap(find.text(nameOf(ReportCardKind.balance)));
      await robot.settle();

      expect(robot.isOn(ReportCardKind.balance), isFalse);
      expect((await stored(tester)).off, {ReportCardKind.balance});

      await teardownApp(tester);
    });
  });

  testWidgets('a drag by the handle moves the row and writes the new order, '
      'the off set kept', (tester) async {
    await tester.runAsync(
      () => settings.setReportCards(
        ReportCards.defaults.toggled(ReportCardKind.records, false),
      ),
    );
    await pumpPage(tester);
    final robot = ReportSettingsRobot(tester);
    final pitch =
        tester.getTopLeft(robot.handleOf(ReportCardKind.insights)).dy -
        tester.getTopLeft(robot.handleOf(ReportCardKind.goals)).dy;

    await robot.dragBy(ReportCardKind.goals, Offset(0, pitch * 3));

    final expected = ReportCards.defaults
        .toggled(ReportCardKind.records, false)
        .moved(0, 3);
    expect(robot.order(), expected.order);
    expect(robot.order().indexOf(ReportCardKind.goals), 3);
    expect(await stored(tester), expected);
    expect(robot.isOn(ReportCardKind.records), isFalse);

    await teardownApp(tester);
  });

  testWidgets('Reset is held on the defaults, takes a tap after a change, '
      'and writes the defaults with its message', (tester) async {
    await pumpPage(tester);
    final robot = ReportSettingsRobot(tester);
    expect(robot.isResetEnabled(), isFalse);

    await robot.toggle(ReportCardKind.tags);
    final pitch =
        tester.getTopLeft(robot.handleOf(ReportCardKind.insights)).dy -
        tester.getTopLeft(robot.handleOf(ReportCardKind.goals)).dy;
    await robot.dragBy(ReportCardKind.ahead, Offset(0, -pitch * 2));
    expect(await stored(tester), isNot(ReportCards.defaults));
    expect(robot.isResetEnabled(), isTrue);

    await robot.tapReset();

    expect(find.text(l10n.reportCardsResetDone), findsOneWidget);
    expect(robot.order(), ReportCardKind.values);
    expect(robot.isOn(ReportCardKind.tags), isTrue);
    expect(await stored(tester), ReportCards.defaults);
    expect(robot.isResetEnabled(), isFalse);

    await teardownApp(tester);
  });

  // Roboto is loaded, so a word is as wide as a phone draws it. Records is
  // off, so the dimmed row is laid out too.
  group('large text', () {
    setUp(
      () => settings.setReportCards(
        ReportCards.defaults.toggled(ReportCardKind.records, false),
      ),
    );

    /// Every paragraph the page lays out, top to bottom, is painted whole
    /// and breaks only between words, nothing overflows on the way down,
    /// and every handle and switch stands where the first row's does.
    Future<void> expectPageWhole(WidgetTester tester) async {
      final robot = ReportSettingsRobot(tester);
      final scrollable = find.byType(Scrollable).first;
      double? handleLeft;
      double? switchRight;
      for (var i = 0; i < 60; i++) {
        expect(tester.takeException(), isNull);
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject;
          if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
          final text = paragraph.text.toPlainText();
          expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text"');
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
          expectBreaksBetweenWords(paragraph);
        }
        for (final kind in ReportCardKind.values) {
          if (robot.handleOf(kind).evaluate().isEmpty) continue;
          final left = tester.getTopLeft(robot.handleOf(kind)).dx;
          final right = tester.getTopRight(robot.switchOf(kind)).dx;
          expect(left, closeTo(handleLeft ??= left, 0.01), reason: kind.name);
          expect(right, closeTo(switchRight ??= right, 0.01));
        }
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.pixels >= position.maxScrollExtent) return;
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      fail('the page never reached its end');
    }

    for (final (locale, scale, dark) in const [
      (Locale('en'), 1.0, false),
      (Locale('en'), 1.0, true),
      (Locale('de'), 2.0, false),
      (Locale('de'), 2.0, true),
      (Locale('ro'), 2.0, false),
      (Locale('ro'), 2.0, true),
    ]) {
      testWidgets('${locale.languageCode} at $scale on a 360 × 780 phone, '
          '${dark ? 'dark' : 'light'}: every name whole and unbroken inside '
          'a word down to Reset, the handles and switches in one column, no '
          'overflow', (tester) async {
        await pumpPage(
          tester,
          surface: const Size(360, 780),
          locale: locale,
          textScale: scale,
          dark: dark,
          density: VisualDensity.standard,
        );
        await expectPageWhole(tester);
        expect(ReportSettingsRobot(tester).reset, findsOneWidget);

        await teardownApp(tester);
      });
    }

    testWidgets('dark: the names in the dark onSurface, an off one at the '
        'switched-off opacity', (tester) async {
      await pumpPage(tester, dark: true);
      final scheme = AppTheme.dark().colorScheme;
      final robot = ReportSettingsRobot(tester);
      for (final kind in const [ReportCardKind.goals, ReportCardKind.records]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(nameOf(kind)),
        );
        expect(paragraph.text.style?.color, scheme.onSurface);
      }
      expect(robot.isDimmed(nameOf(ReportCardKind.records)), isTrue);
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text(nameOf(ReportCardKind.records)),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        FormMetrics.switchedOffOpacity,
      );

      await teardownApp(tester);
    });
  });
}
