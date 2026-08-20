import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_cell.dart';

/// Regression guard for hoisting `DateTime.now()` out of `_cell` in
/// `CalendarDatePickerSheet`. If the hoisted `now` were never threaded
/// through (or normalized differently than the live grid), exactly one
/// [CalendarDayCell] would stop being `isToday` — either none, or, at a
/// month boundary, two.
Widget _wrap() {
  final now = DateTime.now();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: CalendarDatePickerSheet(
        mode: CalendarDatePickerMode.single,
        initialSelection: const {},
        firstDate: DateTime.utc(now.year - 1, 1, 1),
        lastDate: DateTime.utc(now.year + 1, 12, 31),
        appearance: const CalendarAppearance(),
      ),
    ),
  );
}

void main() {
  testWidgets('exactly one rendered day cell is today', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    final cells = tester.widgetList<CalendarDayCell>(
      find.byType(CalendarDayCell),
    );
    expect(cells.where((cell) => cell.isToday).length, 1);
  });
}
