import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/widgets/fasting_schedule_sheet.dart';

/// The scope chips are the one control in this sheet whose meaning is not
/// self-evident from the chips above them, so the hint under them is doing
/// real work — and it was **false** under the default scope: it said "a day
/// you turn off is never marked" while `weeklyOnly` lets a multi-day fast mark
/// every one of its days. A Wed/Fri practice therefore read as broken every
/// August, where the Dormition fast covers Aug 1–14 no matter which weekdays
/// are picked.
///
/// These pin the hint to the **selected** scope, in both axes.
void main() {
  /// The sheet body is a lazy `ListView`, so the month section sits outside a
  /// default 800x600 test viewport and is never built. A tall surface keeps
  /// both scope sections in one pass, which is the point here  14 the two axes
  /// have to be asserted against each other.
  Future<void> pumpSheet(WidgetTester tester, FastingSchedule schedule) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: FastingScheduleSheet(
            initialSchedule: schedule,
            appearance: const CalendarAppearance(),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const weekdayWeekly = 'Multi-day fasts still mark every one of their days';
  const weekdayAll = 'A day you turn off is never marked';
  const monthWeekly = 'Multi-day fasts still show in a month you turn off';
  const monthAll = 'A month you turn off is never marked';

  testWidgets('the default scope admits that multi-day fasts still mark', (
    tester,
  ) async {
    await pumpSheet(tester, const FastingSchedule());

    expect(find.text(weekdayWeekly), findsOneWidget);
    expect(find.text(weekdayAll), findsNothing);
    expect(find.text(monthWeekly), findsOneWidget);
    expect(find.text(monthAll), findsNothing);
  });

  testWidgets('the all-fasts weekday scope claims the stronger rule', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      const FastingSchedule(weekdayScope: FastingWeekdayScope.allFasts),
    );

    expect(find.text(weekdayAll), findsOneWidget);
    expect(find.text(weekdayWeekly), findsNothing);
    // The two axes are independent: the month scope is still weeklyOnly here.
    expect(find.text(monthWeekly), findsOneWidget);
  });

  testWidgets('the all-fasts month scope claims the stronger rule', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      const FastingSchedule(monthScope: FastingMonthScope.allFasts),
    );

    expect(find.text(monthAll), findsOneWidget);
    expect(find.text(monthWeekly), findsNothing);
    expect(find.text(weekdayWeekly), findsOneWidget);
  });

  testWidgets('tapping a scope chip moves its hint with it', (tester) async {
    await pumpSheet(tester, const FastingSchedule());

    // "All fasts" appears once per axis, so the weekday one is the first.
    await tester.tap(find.text('All fasts').first);
    await tester.pumpAndSettle();

    expect(find.text(weekdayAll), findsOneWidget);
    expect(find.text(weekdayWeekly), findsNothing);
  });
}
