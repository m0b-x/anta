import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/icon_picker_sheet.dart';

/// The picker's whole point at 300 icons is that typing narrows it, so the
/// properties worth pinning are the ones a flat `Wrap` never had: an active
/// query flattens the catalog and *ranks* it, membership reaches through the
/// localized group labels (which is how the unlocalized English keywords stay
/// reachable in de/ro), and a query that finds nothing offers a way back.
///
/// Since the 2026-09-27 Tier 1 pass the sheet wears the language's chrome:
/// the search row is pinned above the grid and stays put while the results
/// change, and the section headings are `FormSectionLabel`s (uppercased, so
/// they are found by the label's text, never by the rendered string).
void main() {
  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Future<_Result> openSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size? size,
    double textScale = 1.0,
  }) async {
    if (size != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
    }
    final result = _Result();
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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await IconPickerSheet.show(
                  context,
                  tint: Colors.blue,
                );
                result.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
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

  /// A section heading by the label it was given — the widget uppercases
  /// what it renders.
  Finder sectionLabel(String text) => find.byWidgetPredicate(
    (w) => w is FormSectionLabel && w.text == text,
    description: 'FormSectionLabel "$text"',
  );

  testWidgets('an empty query keeps the grouped catalog', (tester) async {
    await openSheet(tester);

    expect(sectionLabel('Strength'), findsOneWidget);
    expect(sectionLabel('Cardio'), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
  });

  testWidgets('a query flattens the catalog to its matches', (tester) async {
    await openSheet(tester);
    await type(tester, 'run');

    expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsNothing);
    // Section headings belong to the grouped view only.
    expect(sectionLabel('Strength'), findsNothing);
  });

  /// The companion to the `cardio` case below, which passes for a reason that
  /// does not generalise: for `cardio` *every* entry lands in the same band and
  /// the catalog-index tie-break happens to reproduce the expectation, so it
  /// cannot catch a band that is computed wrongly.
  ///
  /// `recovery` separates them. It is the Recovery group's label, so all five
  /// of its entries are members — but only `bedtime`, `spa` and `bathtub`
  /// carry it as a keyword of their own; `hotel` and `weekend` match through
  /// the heading alone and must therefore sort behind all three, not
  /// interleave with them by catalog position.
  ///
  /// This is the case that fails when `FuzzyRank.score`'s `-1` "no match"
  /// sentinel is conflated with the exact-term band, which is also `-1`: the
  /// two heading-only hits are promoted to the *best* band and the order comes
  /// back in bare catalog order instead.
  testWidgets('a group-label-only hit ranks below a real text hit', (
    tester,
  ) async {
    await openSheet(tester);
    await type(tester, 'recovery');

    expect(results(tester), [
      Icons.bedtime_rounded,
      Icons.spa_rounded,
      Icons.bathtub_rounded,
      Icons.hotel_rounded,
      Icons.weekend_rounded,
    ]);
  });

  testWidgets('an exact term outranks a merely-prefixed one', (tester) async {
    await openSheet(tester);
    // `a` is a whole keyword on the letter A and a prefix of the search text
    // of `ac_unit`, `alarm` and `attach_money` — FuzzyRank's best tier. Without
    // the exact-term band the letter is unreachable by its own name.
    await type(tester, 'a');

    expect(results(tester).first, const IconData(0x41));
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
    expect(find.byType(Wrap), findsNothing);

    // The search row's own ✕ is the way back; there is no second button.
    expect(find.text('Clear search'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('No icons found'), findsNothing);
    expect(sectionLabel('Strength'), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
  });

  testWidgets('tapping a result pops its key', (tester) async {
    final result = await openSheet(tester);
    await type(tester, 'run');
    await tester.tap(find.byIcon(Icons.directions_run_rounded));
    await tester.pumpAndSettle();

    expect(result.value, 'directions_run');
  });

  testWidgets('the search row carries its id on the one text field', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.descendant(
        of: byId(SemanticsIds.iconPickSearch),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FormRowGroup),
        matching: find.byType(FormSearchRow),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the header is a close and a title with no text button, and '
      'close pops null', (tester) async {
    final result = await openSheet(tester);

    expect(find.byType(FormSheetHandle), findsOneWidget);
    expect(find.byType(FormSheetHeader), findsOneWidget);
    expect(find.text('Choose icon'), findsOneWidget);
    expect(find.byType(FormHeaderTextButton), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FormSheetHeader),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Cancel'), findsOneWidget);

    await tester.tap(byId(SemanticsIds.iconPickClose));
    await tester.pumpAndSettle();

    expect(result.returned, isTrue);
    expect(result.value, isNull);
    expect(find.byType(IconPickerSheet), findsNothing);
  });

  testWidgets('the search group stays put while the results change', (
    tester,
  ) async {
    // Pinned between the header and the grid: a field that scrolled away
    // with its results was unreachable while they changed.
    await openSheet(tester);
    final atRest = tester.getRect(find.byType(FormSearchRow));
    expect(
      atRest.top,
      greaterThanOrEqualTo(tester.getRect(find.byType(FormSheetHeader)).bottom),
    );

    await type(tester, 'run');
    expect(tester.getRect(find.byType(FormSearchRow)), atRest);
    expect(
      tester.getRect(find.byType(ListView)).top,
      greaterThanOrEqualTo(atRest.bottom),
    );

    await type(tester, 'zzzz');
    expect(tester.getRect(find.byType(FormSearchRow)), atRest);
    expect(
      tester.getTopLeft(find.text('No icons found')).dy,
      greaterThanOrEqualTo(atRest.bottom),
    );

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FormSearchRow)), atRest);
  });

  testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
      'overflows and the search row reads whole', (tester) async {
    await openSheet(
      tester,
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Symbol wählen'), findsOneWidget);
    expect(find.byTooltip('Abbrechen'), findsOneWidget);
    expect(find.text('Symbole suchen...'), findsOneWidget);
    expect(sectionLabel('Kraft'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FormSheetHeader)).height,
      FormMetrics.headerHeight,
    );

    await type(tester, 'zzzz');
    expect(tester.takeException(), isNull);
    expect(find.text('Keine Symbole gefunden'), findsOneWidget);

    await tester.tap(find.byTooltip('Suche löschen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(sectionLabel('Kraft'), findsOneWidget);

    await tester.tap(byId(SemanticsIds.iconPickClose));
    await tester.pumpAndSettle();
    expect(find.byType(IconPickerSheet), findsNothing);
  });
}

/// Carries the sheet's result out of the closure that awaited it.
class _Result {
  String? value;
  bool returned = false;
}
