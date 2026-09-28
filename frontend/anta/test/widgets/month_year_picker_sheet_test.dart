import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/month_year_picker_sheet.dart';

/// The wheels and the typed field are the picker's content; since the
/// 2026-09-27 Tier 1 pass the chrome around them is the sub-sheet's — ✕ ·
/// title · Apply in the header, then Today and "Type the date" as rows under
/// the wheels. Every case pins what the sheet pops, never how a wheel draws.
void main() {
  Finder id(String value) => find.bySemanticsIdentifier(value);

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<_Picked> open(
    WidgetTester tester, {
    DateTime? initialDate,
    Locale locale = const Locale('en'),
    Size size = const Size(800, 1400),
    double textScale = 1.0,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    final picked = _Picked();
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
                picked.value = await MonthYearPickerSheet.show(
                  context,
                  initialDate: initialDate ?? DateTime.utc(2026, 8, 15),
                  firstDate: CalendarBounds.earliest,
                  lastDate: CalendarBounds.latest,
                  accent: Colors.blue,
                );
                picked.returned = true;
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

  FormSwitchRow typedSwitch(WidgetTester tester) =>
      tester.widget<FormSwitchRow>(
        find.ancestor(
          of: id(SemanticsIds.monthYearTyped),
          matching: find.byType(FormSwitchRow),
        ),
      );

  testWidgets('Apply pops the date the wheels opened on', (tester) async {
    final picked = await open(tester, initialDate: DateTime.utc(2026, 8, 15));

    expect(find.byType(FormSheetHeader), findsOneWidget);
    expect(find.text('Pick a date'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNWidgets(3));
    expect(find.byType(FilledButton), findsNothing);

    await tap(tester, id(SemanticsIds.monthYearApply));
    expect(picked.returned, isTrue);
    expect(picked.value, DateTime.utc(2026, 8, 15));
    expect(find.byType(MonthYearPickerSheet), findsNothing);
  });

  testWidgets('the switch swaps the wheels for the typed field and back', (
    tester,
  ) async {
    await open(tester, initialDate: DateTime.utc(2026, 8, 15));
    expect(typedSwitch(tester).value, isFalse);
    expect(find.byType(TextField), findsNothing);

    await tap(tester, id(SemanticsIds.monthYearTyped));
    expect(typedSwitch(tester).value, isTrue);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);
    // The field opens on the wheel date, selected whole, so typing replaces
    // it and Apply with nothing typed keeps it.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '15/08/2026');
    expect(field.controller!.selection.start, 0);
    expect(field.controller!.selection.end, '15/08/2026'.length);
    expect(field.focusNode!.hasFocus, isTrue);

    await tap(tester, id(SemanticsIds.monthYearTyped));
    expect(typedSwitch(tester).value, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ListWheelScrollView), findsNWidgets(3));
  });

  testWidgets('a typed date pops through Apply', (tester) async {
    final picked = await open(tester);
    await tap(tester, id(SemanticsIds.monthYearTyped));

    await tester.enterText(find.byType(TextField), '3/2/2027');
    await tap(tester, id(SemanticsIds.monthYearApply));

    expect(picked.value, DateTime.utc(2027, 2, 3));
  });

  testWidgets('a typed date nobody can read keeps the sheet open with the '
      'invalid caption', (tester) async {
    final picked = await open(tester);
    await tap(tester, id(SemanticsIds.monthYearTyped));

    await tester.enterText(find.byType(TextField), 'soon');
    await tap(tester, id(SemanticsIds.monthYearApply));

    expect(picked.returned, isFalse);
    expect(find.byType(MonthYearPickerSheet), findsOneWidget);
    expect(find.text('Type a date, like 15/08/2026'), findsOneWidget);

    // Typing again clears the caption; a year outside the bounds names them.
    await tester.enterText(find.byType(TextField), '15/08/2200');
    await tester.pump();
    expect(find.text('Type a date, like 15/08/2026'), findsNothing);
    await tap(tester, id(SemanticsIds.monthYearApply));
    expect(picked.returned, isFalse);
    expect(find.text('Choose a year between 1900 and 2100'), findsOneWidget);
  });

  testWidgets('Today moves the wheels to the current date', (tester) async {
    final picked = await open(tester, initialDate: DateTime.utc(2000, 1, 1));

    await tap(tester, id(SemanticsIds.monthYearToday));
    await tap(tester, id(SemanticsIds.monthYearApply));

    final now = DateTime.now();
    expect(picked.value, DateTime.utc(now.year, now.month, now.day));
  });

  testWidgets('Today leaves typed mode for the wheels', (tester) async {
    await open(tester);
    await tap(tester, id(SemanticsIds.monthYearTyped));
    expect(find.byType(TextField), findsOneWidget);

    await tap(tester, id(SemanticsIds.monthYearToday));

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ListWheelScrollView), findsNWidgets(3));
    expect(typedSwitch(tester).value, isFalse);
  });

  testWidgets('✕ pops nothing', (tester) async {
    final picked = await open(tester);

    await tap(tester, id(SemanticsIds.monthYearClose));

    expect(picked.returned, isTrue);
    expect(picked.value, isNull);
    expect(find.byType(MonthYearPickerSheet), findsNothing);
  });

  testWidgets('the barrier pops nothing', (tester) async {
    final picked = await open(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(picked.returned, isTrue);
    expect(picked.value, isNull);
  });

  testWidgets('the system back pops nothing', (tester) async {
    final picked = await open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(picked.returned, isTrue);
    expect(picked.value, isNull);
  });

  testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
      'overflows and the rows read whole in both modes', (tester) async {
    await open(
      tester,
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Datum wählen'), findsOneWidget);
    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.byTooltip('Abbrechen'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FormSheetHeader)).height,
      FormMetrics.headerHeight,
    );
    // The two rows stay whole beside their controls and above the fold.
    expect(find.text('Heute'), findsOneWidget);
    expect(find.text('Datum eintippen'), findsOneWidget);
    expect(
      tester.getRect(id(SemanticsIds.monthYearTyped)).bottom,
      lessThanOrEqualTo(780),
    );
    // The bold selected month scales down to its column instead of being
    // cut to "Augu…": its box fits the wheel and nothing is ellipsized.
    final august = find.text('August');
    expect(august, findsOneWidget);
    expect(
      tester
          .widget<FittedBox>(
            find.ancestor(of: august, matching: find.byType(FittedBox)).first,
          )
          .fit,
      BoxFit.scaleDown,
    );
    expect(
      tester.renderObject<RenderParagraph>(august).didExceedMaxLines,
      isFalse,
    );
    final wheel = tester.getRect(
      find.ancestor(of: august, matching: find.byType(ListWheelScrollView)).first,
    );
    expect(tester.getRect(august).left, greaterThanOrEqualTo(wheel.left));
    expect(tester.getRect(august).right, lessThanOrEqualTo(wheel.right));
    final headerBefore = tester.getRect(find.byType(FormSheetHeader));
    final boxBefore = tester.getSize(find.byType(AnimatedSize));

    await tap(tester, id(SemanticsIds.monthYearTyped));
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Datum eintippen'), findsOneWidget);
    // The typed entry takes the wheels' box, so switching modes moves
    // neither the header nor anything under the box — even once the error
    // caption sits under the field.
    expect(tester.getRect(find.byType(FormSheetHeader)), headerBefore);
    expect(tester.getSize(find.byType(AnimatedSize)), boxBefore);
    await tester.enterText(find.byType(TextField), 'bald');
    await tap(tester, id(SemanticsIds.monthYearApply));
    expect(tester.takeException(), isNull);
    expect(find.text('Datum eingeben, z. B. 15.08.2026'), findsOneWidget);
    expect(tester.getRect(find.byType(FormSheetHeader)), headerBefore);
    expect(tester.getSize(find.byType(AnimatedSize)), boxBefore);
    expect(
      tester.getRect(find.text('Datum eingeben, z. B. 15.08.2026')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(AnimatedSize)).bottom),
    );
  });
}

class _Picked {
  DateTime? value;
  bool returned = false;
}
