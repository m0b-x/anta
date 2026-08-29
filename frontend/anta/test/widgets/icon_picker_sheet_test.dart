import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/icon_picker_sheet.dart';

/// The picker's whole point at 300 icons is that typing narrows it, so the
/// properties worth pinning are the ones a flat `Wrap` never had: an active
/// query flattens the catalog and *ranks* it, membership reaches through the
/// localized group labels (which is how the unlocalized English keywords stay
/// reachable in de/ro), and a query that finds nothing offers a way back.
void main() {
  Future<String?> openSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await IconPickerSheet.show(
                  context,
                  tint: Colors.blue,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  /// The icons of the one result `Wrap`, in render order.
  List<IconData?> results(WidgetTester tester) {
    return [
      for (final icon in tester.widgetList<Icon>(
        find.descendant(of: find.byType(Wrap), matching: find.byType(Icon)),
      ))
        icon.icon,
    ];
  }

  testWidgets('an empty query keeps the grouped catalog', (tester) async {
    await openSheet(tester);

    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('Cardio'), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
  });

  testWidgets('a query flattens the catalog to its matches', (tester) async {
    await openSheet(tester);
    await type(tester, 'run');

    expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsNothing);
    // Section headings belong to the grouped view only.
    expect(find.text('Strength'), findsNothing);
  });

  testWidgets('a keyword hit outranks a group-label-only hit', (tester) async {
    await openSheet(tester);
    // `cardio` is a keyword on two entries and the label of the group holding
    // eight — the two that carry the word themselves must lead.
    await type(tester, 'cardio');

    expect(results(tester), [
      Icons.directions_run_rounded,
      Icons.directions_bike_rounded,
      Icons.directions_walk_rounded,
      Icons.pool_rounded,
      Icons.hiking_rounded,
      Icons.rowing_rounded,
      Icons.downhill_skiing_rounded,
      Icons.snowboarding_rounded,
    ]);
  });

  testWidgets('a localized group label reaches its English keywords', (
    tester,
  ) async {
    // The keywords are English by design; per-locale reach comes from the
    // group labels joining the same match set.
    await openSheet(tester, locale: const Locale('de'));
    await type(tester, 'Ausdauer');

    expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pool_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsNothing);
  });

  testWidgets('group labels match through the diacritics fold', (tester) async {
    await openSheet(tester, locale: const Locale('ro'));
    await type(tester, 'masuratori');

    expect(find.byIcon(Icons.straighten_rounded), findsOneWidget);
    expect(find.byIcon(Icons.monitor_weight_rounded), findsOneWidget);
    expect(find.byIcon(Icons.directions_run_rounded), findsNothing);
  });

  testWidgets('an empty result offers a way back to the catalog', (
    tester,
  ) async {
    await openSheet(tester);
    await type(tester, 'zzzz');

    expect(find.text('No icons found'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('No icons found'), findsNothing);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
  });

  testWidgets('tapping a result pops its key', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await IconPickerSheet.show(context, tint: Colors.blue);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await type(tester, 'run');
    await tester.tap(find.byIcon(Icons.directions_run_rounded));
    await tester.pumpAndSettle();

    expect(picked, 'directions_run');
  });
}
