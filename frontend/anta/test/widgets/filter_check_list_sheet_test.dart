import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/filter_check_list_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// The check-list sub-sheet serves two value lists of the filter sheet, so
/// what it must get right is the contract both rely on: Done returns exactly
/// the checked ids — an empty set included — and every other exit returns
/// null and changes nothing; every row and both header actions carry an id.
void main() {
  const items = [
    FilterCheckItem(
      id: 'tracked',
      icon: Icons.checklist_rounded,
      label: 'Tracked',
      identifier: 'filter-list-tracked',
    ),
    FilterCheckItem(
      id: 'missed',
      icon: Icons.remove_circle_outline_rounded,
      label: 'Missed',
      identifier: 'filter-list-missed',
    ),
    FilterCheckItem(
      id: 'money',
      icon: Icons.payments_outlined,
      label: 'With money',
      identifier: 'filter-list-money',
    ),
  ];

  Future<_Outcome> open(
    WidgetTester tester, {
    Set<String> selected = const {},
    Locale locale = const Locale('en'),
  }) async {
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await FilterCheckListSheet.show(
                  context,
                  title: 'Only show',
                  items: items,
                  selected: selected,
                );
                outcome.record(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder id(String value) => find.bySemanticsIdentifier(value);

  testWidgets('Done returns the checked ids', (tester) async {
    final outcome = await open(tester, selected: const {'missed'});

    await tap(tester, id('filter-list-tracked'));
    await tap(tester, id('filter-list-missed'));
    await tap(tester, id('filter-list-money'));
    await tap(tester, id(SemanticsIds.filterListDone));

    expect(outcome.returned, isTrue);
    expect(outcome.result, {'tracked', 'money'});
    expect(find.byType(FilterCheckListSheet), findsNothing);
  });

  testWidgets('Done with nothing checked returns an empty set, never null', (
    tester,
  ) async {
    final outcome = await open(tester, selected: const {'tracked'});

    await tap(tester, id('filter-list-tracked'));
    await tap(tester, id(SemanticsIds.filterListDone));

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNotNull);
    expect(outcome.result, isEmpty);
  });

  testWidgets('the close button returns null and keeps nothing', (
    tester,
  ) async {
    final outcome = await open(tester);

    await tap(tester, id('filter-list-tracked'));
    await tap(tester, id(SemanticsIds.filterListClose));

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(FilterCheckListSheet), findsNothing);
  });

  testWidgets('the barrier returns null', (tester) async {
    final outcome = await open(tester);

    await tap(tester, id('filter-list-tracked'));
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('the system back returns null', (tester) async {
    final outcome = await open(tester);

    await tap(tester, id('filter-list-tracked'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(FilterCheckListSheet), findsNothing);
  });

  testWidgets('every row is a check row with its own icon, checked as opened', (
    tester,
  ) async {
    await open(tester, selected: const {'missed'});

    expect(find.byType(FormCheckRow), findsNWidgets(3));
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);
    expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.map((box) => box.value), [false, true, false]);
    expect(find.text('Only show'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('the sheet is as tall as its rows, with the header first', (
    tester,
  ) async {
    await open(tester);

    final sheet = tester.getSize(find.byType(FilterCheckListSheet));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(sheet.height, lessThan(screen.height * FormMetrics.sheetHeightFactor));
    expect(
      tester.getTopLeft(find.byIcon(Icons.close_rounded)).dy,
      lessThan(tester.getTopLeft(find.text('Tracked')).dy),
    );
  });
}

class _Outcome {
  bool returned = false;
  Set<String>? result;

  void record(Set<String>? value) {
    returned = true;
    result = value;
  }
}
