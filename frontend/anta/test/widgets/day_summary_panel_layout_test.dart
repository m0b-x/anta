import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/day_summary_entry.dart';
import 'package:anta/widgets/day_summary_panel.dart';

/// Regression coverage for roadmap item 5.6: the day panel's per-row accent
/// stripe used to be sized by wrapping each `Row` in an `IntrinsicHeight` so
/// `CrossAxisAlignment.stretch` had a bounded height to stretch into — a
/// double layout pass on every row. The stripe is now a `Positioned` inside a
/// `Stack` (mirroring `_AgendaCard` in `agenda_list_view.dart`), which sizes
/// off the Stack's own height with no intrinsic pass at all. These tests pin
/// the property `IntrinsicHeight` used to guarantee — the stripe spans the
/// full row — at more than one row height, so it isn't coincidental.
void main() {
  Future<void> pumpPanel(WidgetTester tester, List<DaySummaryEntry> entries) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DaySummaryPanel(
              day: DateTime.utc(2026, 8, 24),
              entries: entries,
            ),
          ),
        ),
      ),
    );
  }

  const shortKey = 'event:short';
  const tallKey = 'event:tall';

  DaySummaryEntry shortEntry() => const DaySummaryEntry(
    key: shortKey,
    icon: Icons.event,
    color: Colors.blue,
    title: 'Standup',
    priority: 0,
  );

  DaySummaryEntry tallEntry() => const DaySummaryEntry(
    key: tallKey,
    icon: Icons.event,
    color: Colors.red,
    title: 'Quarterly planning offsite',
    subtitle: 'Daily · 9:00 AM',
    // Long enough to wrap across more than one line inside the ListTile at
    // the 360-wide viewport above, so this row is genuinely taller than a
    // plain one-line entry rather than coincidentally so.
    description:
        'A long description that keeps going and going so it wraps across '
        'more than one line inside the ListTile and forces this row to be '
        'noticeably taller than a plain one-line entry would ever be.',
    priority: 0,
  );

  /// The accent-stripe `Container` inside the row keyed [entryKey] — the same
  /// `Container(width: 4, color: entry.color)` both this widget and
  /// `_AgendaCard` render. Matched by its distinctive solid `color`, which no
  /// other `Container` in the row shares (the leading `CircleAvatar` uses an
  /// alpha-blended tint of the same colour, never the flat one).
  Finder stripeFinder(String entryKey, Color color) {
    return find.descendant(
      of: find.byKey(ValueKey(entryKey)),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.color == color,
      ),
    );
  }

  Finder tileFinder(String entryKey) {
    return find.descendant(
      of: find.byKey(ValueKey(entryKey)),
      matching: find.byType(ListTile),
    );
  }

  testWidgets('no IntrinsicHeight remains in the panel', (tester) async {
    await pumpPanel(tester, [shortEntry(), tallEntry()]);

    expect(find.byType(IntrinsicHeight), findsNothing);
  });

  testWidgets('the stripe spans the full height of a short, one-line row', (
    tester,
  ) async {
    await pumpPanel(tester, [shortEntry()]);

    final stripe = stripeFinder(shortKey, Colors.blue);
    expect(stripe, findsOneWidget);

    final stripeHeight = tester.getSize(stripe).height;
    final tileHeight = tester.getSize(tileFinder(shortKey)).height;
    expect(stripeHeight, closeTo(tileHeight, 0.5));
  });

  testWidgets(
    'the stripe spans the full height of a tall row with a wrapped description',
    (tester) async {
      await pumpPanel(tester, [tallEntry()]);

      final stripe = stripeFinder(tallKey, Colors.red);
      expect(stripe, findsOneWidget);

      final stripeHeight = tester.getSize(stripe).height;
      final tileHeight = tester.getSize(tileFinder(tallKey)).height;
      expect(stripeHeight, closeTo(tileHeight, 0.5));
    },
  );

  testWidgets('the tall row really is taller than the short one', (
    tester,
  ) async {
    // Proves the two height-matching assertions above hold at genuinely
    // different heights, not at one size by coincidence.
    await pumpPanel(tester, [shortEntry()]);
    final shortHeight = tester.getSize(tileFinder(shortKey)).height;

    await pumpPanel(tester, [tallEntry()]);
    final tallHeight = tester.getSize(tileFinder(tallKey)).height;

    expect(tallHeight, greaterThan(shortHeight));
  });

  testWidgets('the stripe uses the entry colour', (tester) async {
    await pumpPanel(tester, [shortEntry(), tallEntry()]);

    expect(stripeFinder(shortKey, Colors.blue), findsOneWidget);
    expect(stripeFinder(tallKey, Colors.red), findsOneWidget);
  });
}
