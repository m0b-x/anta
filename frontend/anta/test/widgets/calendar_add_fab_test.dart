import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';

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
  }) async {
    final notifier = ValueNotifier(extended);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          floatingActionButton: CalendarAddFab(
            selectedDay: selectedDay,
            appearance: appearance,
            extended: notifier,
            onPressed: onPressed ?? (_) {},
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
    /// A notification carrying [direction] along [axis], as a scrollable would
    /// emit it.
    UserScrollNotification notify(
      ScrollDirection direction, {
      Axis axis = Axis.vertical,
    }) {
      return UserScrollNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          pixels: 100,
          viewportDimension: 500,
          axisDirection: axis == Axis.vertical
              ? AxisDirection.down
              : AxisDirection.right,
          devicePixelRatio: 1,
        ),
        context: _FakeBuildContext(),
        direction: direction,
      );
    }

    test('scrolling down collapses the button', () {
      expect(fabExtendedFor(notify(ScrollDirection.reverse)), isFalse);
    });

    test('scrolling up and stopping both extend it', () {
      expect(fabExtendedFor(notify(ScrollDirection.forward)), isTrue);
      expect(fabExtendedFor(notify(ScrollDirection.idle)), isTrue);
    });

    test('a horizontal scroll is ignored entirely', () {
      // The agenda's summary-chip row and the timeline's hour track both
      // scroll sideways; neither hides anything, so neither may move the
      // button. Null, not `true` — an unrelated swipe must not re-extend it
      // mid-scroll either.
      for (final direction in ScrollDirection.values) {
        expect(
          fabExtendedFor(notify(direction, axis: Axis.horizontal)),
          isNull,
        );
      }
    });
  });
}

/// `UserScrollNotification` requires a context but never reads it here.
class _FakeBuildContext extends Fake implements BuildContext {}
