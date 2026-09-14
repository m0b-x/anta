import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/widgets/calendar_add_fab.dart';

/// The add button targets the calendar's **selected** day, not today, and a
/// bare `+` never said so — the label is the whole point of this widget, so
/// most of what is pinned here is that it names the right day and disappears
/// only when there is genuinely nothing to name.
void main() {
  /// Fixed relative to `DateTime.now()`, because the label's Today/Tomorrow
  /// branch is resolved against the real clock inside the widget.
  DateTime today() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  Future<ValueNotifier<bool>> pumpFab(
    WidgetTester tester, {
    required DateTime? selectedDay,
    bool extended = true,
    CalendarAppearance appearance = const CalendarAppearance(),
    ValueChanged<DateTime>? onPressed,
    ValueChanged<DateTime>? onLongPressed,
    ValueListenable<String?>? trace,
    ThemeData? theme,
  }) async {
    final notifier = ValueNotifier(extended);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          floatingActionButton: CalendarAddFab(
            selectedDay: selectedDay,
            appearance: appearance,
            extended: notifier,
            onPressed: onPressed ?? (_) {},
            onLongPressed: onLongPressed,
            trace: trace,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  FloatingActionButton fab(WidgetTester tester) =>
      tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));

  group('the label names the target day', () {
    testWidgets('today reads as Today', (tester) async {
      await pumpFab(tester, selectedDay: today());

      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('tomorrow reads as Tomorrow', (tester) async {
      await pumpFab(tester, selectedDay: today().add(const Duration(days: 1)));

      expect(find.text('Tomorrow'), findsOneWidget);
    });

    testWidgets('anything further out reads as a short date', (tester) async {
      // Far enough that it can never collide with Today/Tomorrow whatever day
      // the suite runs on.
      final day = today().add(const Duration(days: 40));
      await pumpFab(tester, selectedDay: day);

      expect(find.text('Today'), findsNothing);
      expect(find.text('Tomorrow'), findsNothing);
      // "MMM d" — a month abbreviation and the day number, nothing longer.
      expect(find.textContaining('${day.day}'), findsOneWidget);
    });
  });

  group('collapse', () {
    testWidgets('extended shows the label, collapsed hides it', (tester) async {
      final notifier = await pumpFab(tester, selectedDay: today());
      expect(find.text('Today'), findsOneWidget);

      notifier.value = false;
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsNothing);
      // The button itself stays — collapsing must never remove the action.
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('re-extending brings the label back', (tester) async {
      final notifier = await pumpFab(
        tester,
        selectedDay: today(),
        extended: false,
      );
      expect(find.text('Today'), findsNothing);

      notifier.value = true;
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
    });
  });

  group('before the calendar services resolve', () {
    testWidgets('a null day is inert and unlabelled', (tester) async {
      await pumpFab(tester, selectedDay: null);

      // Disabled: the editor reads CalendarCategories, still empty here.
      expect(fab(tester).onPressed, isNull);
      // And collapsed even though `extended` is true — an extended button
      // carrying an empty label would read as broken.
      expect(fab(tester).isExtended, isFalse);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });
  });

  group('accent', () {
    testWidgets('a dark accent takes a white foreground', (tester) async {
      await pumpFab(
        tester,
        selectedDay: today(),
        appearance: const CalendarAppearance(
          accentColorValue: 0xFF1A237E, // indigo 900
        ),
      );

      expect(fab(tester).backgroundColor, const Color(0xFF1A237E));
      expect(fab(tester).foregroundColor, Colors.white);
    });

    testWidgets('a pale accent flips the foreground dark', (tester) async {
      // The accent is user-picked and can be anything, so `onPrimary` is not
      // enough — this is the same guard the day cells apply to a filled day.
      await pumpFab(
        tester,
        selectedDay: today(),
        appearance: const CalendarAppearance(
          accentColorValue: 0xFFFFF176, // yellow 300
        ),
      );

      expect(fab(tester).backgroundColor, const Color(0xFFFFF176));
      expect(fab(tester).foregroundColor, Colors.black87);
    });

    testWidgets('no accent falls back to the theme primary', (tester) async {
      await pumpFab(tester, selectedDay: today());

      final theme = Theme.of(tester.element(find.byType(FloatingActionButton)));
      expect(fab(tester).backgroundColor, theme.colorScheme.primary);
    });

    testWidgets('rests at elevation 2 in every state', (tester) async {
      // Material's 6 was the only shadow on an otherwise flat page.
      await pumpFab(tester, selectedDay: today());

      expect(fab(tester).elevation, CalendarAddFab.elevation);
      expect(fab(tester).focusElevation, CalendarAddFab.elevation);
      expect(fab(tester).highlightElevation, CalendarAddFab.elevation);
      expect(fab(tester).disabledElevation, isNull);
    });
  });

  group('dark theme', () {
    final dark = ThemeData(colorScheme: AppTheme.darkScheme);

    testWidgets('no accent takes the primary container pair', (tester) async {
      // Filled with dark's pale primary the button was the brightest thing on
      // screen; the container tone is what Material gives a FAB by default.
      await pumpFab(tester, selectedDay: today(), theme: dark);

      expect(fab(tester).backgroundColor, AppTheme.darkScheme.primaryContainer);
      expect(
        fab(tester).foregroundColor,
        AppTheme.darkScheme.onPrimaryContainer,
      );
    });

    testWidgets('a custom accent takes two lightness stops of its own hue', (
      tester,
    ) async {
      await pumpFab(
        tester,
        selectedDay: today(),
        theme: dark,
        appearance: const CalendarAppearance(
          accentColorValue: 0xFF1A237E, // indigo 900
        ),
      );

      // Indigo is not a luminous hue, so the lightest fill stop holds.
      final hsl = HSLColor.fromColor(const Color(0xFF1A237E));
      expect(fab(tester).backgroundColor, hsl.withLightness(0.32).toColor());
      expect(fab(tester).foregroundColor, hsl.withLightness(0.90).toColor());
    });
  });

  group('calendarAddFabColors', () {
    const light = AppTheme.lightScheme;
    const dark = AppTheme.darkScheme;

    test('light keeps the filled look for the theme accent', () {
      final colors = calendarAddFabColors(
        scheme: light,
        appearance: const CalendarAppearance(),
      );
      expect(colors.background, light.primary);
      expect(colors.foreground, Colors.white);
    });

    test('light picks the glyph by the accent brightness', () {
      final pale = calendarAddFabColors(
        scheme: light,
        appearance: const CalendarAppearance(accentColorValue: 0xFFFFF176),
      );
      expect(pale.foreground, Colors.black87);
      final deep = calendarAddFabColors(
        scheme: light,
        appearance: const CalendarAppearance(accentColorValue: 0xFF1A237E),
      );
      expect(deep.foreground, Colors.white);
    });

    test('the fill steps down only for luminous hues', () {
      // Purple holds the lightest stop; teal (the palette's worst case for a
      // 0.90 glyph) has to drop two stops before the glyph clears 4.5:1.
      final purple = HSLColor.fromColor(const Color(0xFF5E35B1));
      expect(
        calendarAddFabColors(
          scheme: dark,
          appearance: const CalendarAppearance(accentColorValue: 0xFF5E35B1),
        ).background,
        purple.withLightness(0.32).toColor(),
      );
      final teal = HSLColor.fromColor(const Color(0xFF00897B));
      expect(
        calendarAddFabColors(
          scheme: dark,
          appearance: const CalendarAppearance(accentColorValue: 0xFF00897B),
        ).background,
        teal.withLightness(0.24).toColor(),
      );
    });

    test('dark keeps the glyph readable on every built-in swatch', () {
      // The stepped fill replaces the brightness guard: whichever stop wins,
      // the 0.90 glyph clears 4.5:1 for every hue in the palette.
      for (final swatch in CalendarColors.swatchPalette) {
        final colors = calendarAddFabColors(
          scheme: dark,
          appearance: CalendarAppearance(accentColorValue: swatch),
        );
        final lf = colors.foreground.computeLuminance();
        final lb = colors.background.computeLuminance();
        final ratio = (lf + 0.05) / (lb + 0.05);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'swatch ${swatch.toRadixString(16)} → $ratio',
        );
      }
    });

    test('dark with the theme accent is the scheme pair, not a derivation', () {
      final colors = calendarAddFabColors(
        scheme: dark,
        appearance: const CalendarAppearance(),
      );
      expect(colors.background, dark.primaryContainer);
      expect(colors.foreground, dark.onPrimaryContainer);
    });
  });

  testWidgets('tapping reports the selected day', (tester) async {
    DateTime? tapped;
    final day = today().add(const Duration(days: 40));
    await pumpFab(
      tester,
      selectedDay: day,
      onPressed: (value) => tapped = value,
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(tapped, day);
  });

  group('fabExtendedFor', () {
    FixedScrollMetrics metricsAt(double pixels, {Axis axis = Axis.vertical}) {
      return FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: pixels,
        viewportDimension: 500,
        axisDirection: axis == Axis.vertical
            ? AxisDirection.down
            : AxisDirection.right,
        devicePixelRatio: 1,
      );
    }

    final context = _FakeBuildContext();

    ScrollUpdateNotification update(
      double pixels,
      double delta, {
      Axis axis = Axis.vertical,
    }) {
      return ScrollUpdateNotification(
        metrics: metricsAt(pixels, axis: axis),
        context: context,
        scrollDelta: delta,
      );
    }

    test('reading down past the slack collapses it', () {
      expect(fabExtendedFor(update(100, 12)), isFalse);
      expect(fabExtendedFor(update(fabTopSlack + 1, 4)), isFalse);
    });

    test('moving back toward the top extends it', () {
      expect(fabExtendedFor(update(400, -12)), isTrue);
    });

    test('within the top slack it stays extended whichever way it moves', () {
      // A drag that starts at the top has hidden nothing yet; the button must
      // not flinch on the first few pixels.
      expect(fabExtendedFor(update(0, 3)), isTrue);
      expect(fabExtendedFor(update(fabTopSlack, 2)), isTrue);
    });

    test('a zero or absent delta is left alone off the top', () {
      expect(fabExtendedFor(update(300, 0)), isNull);
      expect(
        fabExtendedFor(
          ScrollUpdateNotification(metrics: metricsAt(300), context: context),
        ),
        isNull,
      );
    });

    test('a list mounting or reshaping at its top extends it', () {
      // A mode switch mounts a fresh list at pixels 0; a day change may
      // clamp the day panel back to the top. Both re-label the button
      // without any finger involved.
      expect(
        fabExtendedFor(
          ScrollMetricsNotification(metrics: metricsAt(0), context: context),
        ),
        isTrue,
      );
    });

    test('a lazy list growing mid-read is left alone', () {
      // `ListView.builder` re-reports its extent as it lays out more rows;
      // that must not pull the label back while the reader is down inside.
      expect(
        fabExtendedFor(
          ScrollMetricsNotification(metrics: metricsAt(600), context: context),
        ),
        isNull,
      );
    });

    test('overscroll past the top extends, past the bottom is left alone', () {
      expect(
        fabExtendedFor(
          OverscrollNotification(
            metrics: metricsAt(0),
            context: context,
            overscroll: -20,
          ),
        ),
        isTrue,
      );
      expect(
        fabExtendedFor(
          OverscrollNotification(
            metrics: metricsAt(1000),
            context: context,
            overscroll: 20,
          ),
        ),
        isNull,
      );
    });

    test('the finger lifting changes nothing', () {
      // The old rule keyed off `UserScrollNotification` and re-extended on
      // `idle`, so the button collapsed only while a finger was moving. Now a
      // direction change, start or end is not an input at all.
      for (final direction in ScrollDirection.values) {
        expect(
          fabExtendedFor(
            UserScrollNotification(
              metrics: metricsAt(300),
              context: context,
              direction: direction,
            ),
          ),
          isNull,
        );
      }
      expect(
        fabExtendedFor(
          ScrollEndNotification(metrics: metricsAt(300), context: context),
        ),
        isNull,
      );
      expect(
        fabExtendedFor(
          ScrollStartNotification(metrics: metricsAt(300), context: context),
        ),
        isNull,
      );
    });

    test('a horizontal scroll is ignored entirely', () {
      // The agenda's summary-chip row, the timeline's hour track and the
      // grid's month pager all scroll sideways; none hides anything, so none
      // may move the button — not even back to extended.
      expect(fabExtendedFor(update(0, 3, axis: Axis.horizontal)), isNull);
      expect(fabExtendedFor(update(200, 12, axis: Axis.horizontal)), isNull);
      expect(fabExtendedFor(update(200, -12, axis: Axis.horizontal)), isNull);
      expect(
        fabExtendedFor(
          ScrollMetricsNotification(
            metrics: metricsAt(0, axis: Axis.horizontal),
            context: context,
          ),
        ),
        isNull,
      );
    });

    test('the trace names what it saw and decided', () {
      expect(
        describeFabNotification(update(142, 12), false),
        'update ↓ v 142px → collapse',
      );
      expect(
        describeFabNotification(
          ScrollMetricsNotification(metrics: metricsAt(0), context: context),
          true,
        ),
        'metrics v 0px → extend',
      );
      expect(
        describeFabNotification(
          UserScrollNotification(
            metrics: metricsAt(300),
            context: context,
            direction: ScrollDirection.idle,
          ),
          null,
        ),
        isNull,
      );
    });
  });

  group('long press and trace', () {
    testWidgets('a long press quick-adds for the same day', (tester) async {
      DateTime? longPressed;
      DateTime? pressed;
      final day = today().add(const Duration(days: 3));
      await pumpFab(
        tester,
        selectedDay: day,
        onPressed: (d) => pressed = d,
        onLongPressed: (d) => longPressed = d,
      );

      await tester.longPress(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(longPressed, day);
      expect(pressed, isNull);
      // The tooltip is manual so the long press is not spent showing it.
      expect(find.text('Add event'), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(pressed, day);
    });

    testWidgets('a null day disarms the long press too', (tester) async {
      var longPressed = false;
      await pumpFab(
        tester,
        selectedDay: null,
        onLongPressed: (_) => longPressed = true,
      );

      await tester.longPress(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(longPressed, isFalse);
    });

    testWidgets('the trace caption follows its notifier', (tester) async {
      final trace = ValueNotifier<String?>(null);
      addTearDown(trace.dispose);
      await pumpFab(tester, selectedDay: today(), trace: trace);

      expect(find.textContaining('→'), findsNothing);

      trace.value = 'update ↓ v 142px → collapse';
      await tester.pump();
      expect(find.text('update ↓ v 142px → collapse'), findsOneWidget);
      // Never part of the button's accessible name.
      expect(
        tester.getSemantics(find.byType(FloatingActionButton)).label,
        isNot(contains('collapse')),
      );

      trace.value = null;
      await tester.pump();
      expect(find.textContaining('→'), findsNothing);
    });
  });
}

/// `UserScrollNotification` requires a context but never reads it here.
class _FakeBuildContext extends Fake implements BuildContext {}
