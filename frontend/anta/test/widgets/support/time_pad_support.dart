import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';

/// Types [time] on the open `TimePadSheet`, which closes it with that time.
///
/// Shared by the sheet robots and not rewritten with them: the pad has been on
/// the UI language since Tier 1 and the Tier 2 rebuild leaves it alone, so its
/// `SemanticsIds` are a contract a robot can lean on.
///
/// Both hour digits, both minute digits, then the period — the pad is never
/// left to guess the half of the day from the minute it opened on. The period
/// keys exist only on a 12-hour pad, which is the one an `en` suite gets.
Future<void> typeOnTimePad(WidgetTester tester, TimeOfDay time) async {
  final digits = [
    time.hourOfPeriod ~/ 10,
    time.hourOfPeriod % 10,
    time.minute ~/ 10,
    time.minute % 10,
  ];
  for (final digit in digits) {
    await tester.tap(_key(SemanticsIds.timePadDigit(digit)));
    await tester.pump();
  }
  await tester.tap(
    _key(
      time.period == DayPeriod.am
          ? SemanticsIds.timePadAm
          : SemanticsIds.timePadPm,
    ),
  );
  await tester.pumpAndSettle();
}

/// Leaves the open `TimePadSheet` through its ✕, with nothing picked.
Future<void> cancelTimePad(WidgetTester tester) async {
  await tester.tap(_key(SemanticsIds.timePadCancel));
  await tester.pumpAndSettle();
}

Finder _key(String id) => find.bySemanticsIdentifier(id, skipOffstage: false);
