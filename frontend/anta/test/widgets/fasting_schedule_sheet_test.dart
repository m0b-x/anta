import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/widgets/form_rows.dart';

import 'support/fasting_schedule_robot.dart';
import 'support/layout_errors.dart';

/// The scope chips are the one control in this sheet whose meaning is not
/// self-evident from the chips above them, so the hint under them is doing
/// real work — and it was **false** under the default scope: it said "a day
/// you turn off is never marked" while `weeklyOnly` lets a multi-day fast mark
/// every one of its days. A Wed/Fri practice therefore read as broken every
/// August, where the Dormition fast covers Aug 1–14 no matter which weekdays
/// are picked.
///
/// These pin the hint to the **selected** scope, in both axes; the group
/// after them pins what every control writes, live, through `onChanged`; the
/// last group pins the sub-sheet of the UI language the sheet became in
/// Tier 3 (slice 4): chips that never change width, bulk rows disabled in
/// place, a caption slot that never changes height, the exception rows and
/// their removes, the ids, German at 200 % on a phone.
///
/// Every case drives the sheet through [FastingScheduleRobot] (`support/`),
/// so a rebuild of the chrome rewrites the robot and leaves these bodies
/// alone.
void main() {
  Future<FastingScheduleRobot> pumpSheet(
    WidgetTester tester,
    FastingSchedule schedule,
  ) async {
    final robot = FastingScheduleRobot(tester);
    await robot.show(initialSchedule: schedule, onChanged: (_) {});
    return robot;
  }

  const weekdayWeekly = 'Multi-day fasts still mark every one of their days';
  const weekdayAll = 'A day you turn off is never marked';
  const monthWeekly = 'Multi-day fasts still show in a month you turn off';
  const monthAll = 'A month you turn off is never marked';

  testWidgets('the default scope admits that multi-day fasts still mark', (
    tester,
  ) async {
    final robot = await pumpSheet(tester, const FastingSchedule());

    expect(robot.weekdayScopeHint, weekdayWeekly);
    expect(robot.monthScopeHint, monthWeekly);
  });

  testWidgets('the all-fasts weekday scope claims the stronger rule', (
    tester,
  ) async {
    final robot = await pumpSheet(
      tester,
      const FastingSchedule(weekdayScope: FastingWeekdayScope.allFasts),
    );

    expect(robot.weekdayScopeHint, weekdayAll);
    // The two axes are independent: the month scope is still weeklyOnly here.
    expect(robot.monthScopeHint, monthWeekly);
  });

  testWidgets('the all-fasts month scope claims the stronger rule', (
    tester,
  ) async {
    final robot = await pumpSheet(
      tester,
      const FastingSchedule(monthScope: FastingMonthScope.allFasts),
    );

    expect(robot.monthScopeHint, monthAll);
    expect(robot.weekdayScopeHint, weekdayWeekly);
  });

  testWidgets('tapping a scope chip moves its hint with it', (tester) async {
    final robot = await pumpSheet(tester, const FastingSchedule());

    await robot.pickWeekdayScope(FastingWeekdayScope.allFasts);

    expect(robot.weekdayScopeHint, weekdayAll);
  });

  group('what each control writes', () {
    /// Opens the sheet on [initial] and collects every schedule it writes.
    Future<(FastingScheduleRobot, List<FastingSchedule>)> open(
      WidgetTester tester, {
      FastingSchedule initial = const FastingSchedule(),
    }) async {
      final writes = <FastingSchedule>[];
      final robot = FastingScheduleRobot(tester);
      await robot.show(initialSchedule: initial, onChanged: writes.add);
      return (robot, writes);
    }

    /// Two days of the month the Dates sheet opens on — this one — so they
    /// can be ticked without paging.
    final now = DateTime.now();
    final first = DateTime.utc(now.year, now.month, 1);
    final second = DateTime.utc(now.year, now.month, 2);

    testWidgets('toggling a weekday writes the schedule with it flipped', (
      tester,
    ) async {
      final (robot, writes) = await open(tester);
      expect(robot.weekdaySelected(DateTime.wednesday), isTrue);
      expect(robot.weekdaySelected(DateTime.monday), isFalse);

      await robot.toggleWeekday(DateTime.monday);
      expect(writes.last.weekdays, {
        DateTime.monday,
        DateTime.wednesday,
        DateTime.friday,
      });
      expect(robot.weekdaySelected(DateTime.monday), isTrue);

      await robot.toggleWeekday(DateTime.wednesday);
      expect(writes.last.weekdays, {DateTime.monday, DateTime.friday});
      expect(writes, hasLength(2));
    });

    testWidgets('Select all and None write every weekday or none', (
      tester,
    ) async {
      final (robot, writes) = await open(tester);

      await robot.weekdaysSelectAll();
      expect(writes.last.weekdays, {1, 2, 3, 4, 5, 6, 7});

      await robot.weekdaysNone();
      expect(writes.last.weekdays, isEmpty);
      expect(writes.last.months, FastingSchedule.allMonths);
    });

    testWidgets('toggling a month writes the schedule with it flipped', (
      tester,
    ) async {
      final (robot, writes) = await open(tester);
      expect(robot.monthSelected(8), isTrue);

      await robot.toggleMonth(8);
      expect(writes.last.months, FastingSchedule.allMonths.difference({8}));
      expect(robot.monthSelected(8), isFalse);

      await robot.toggleMonth(8);
      expect(writes.last.months, FastingSchedule.allMonths);
    });

    testWidgets('Select all and None write every month or none', (
      tester,
    ) async {
      final (robot, writes) = await open(tester);

      await robot.monthsNone();
      expect(writes.last.months, isEmpty);
      // An empty month set is legal, and the scope stays on offer.
      expect(robot.monthScope, FastingMonthScope.weeklyOnly);

      await robot.monthsSelectAll();
      expect(writes.last.months, FastingSchedule.allMonths);
      expect(writes.last.weekdays, FastingSchedule.defaultWeekdays);
    });

    testWidgets('a scope chip writes its scope and only its axis', (
      tester,
    ) async {
      final (robot, writes) = await open(tester);

      await robot.pickWeekdayScope(FastingWeekdayScope.allFasts);
      expect(writes.last.weekdayScope, FastingWeekdayScope.allFasts);
      expect(writes.last.monthScope, FastingMonthScope.weeklyOnly);
      expect(robot.weekdayScope, FastingWeekdayScope.allFasts);

      await robot.pickMonthScope(FastingMonthScope.allFasts);
      expect(writes.last.monthScope, FastingMonthScope.allFasts);
      expect(writes.last.weekdayScope, FastingWeekdayScope.allFasts);
      expect(robot.monthScope, FastingMonthScope.allFasts);
    });

    testWidgets('Days off adds the picked dates and takes them out of the '
        'extra fast days', (tester) async {
      final (robot, writes) = await open(
        tester,
        initial: FastingSchedule(forceDates: {first}),
      );
      expect(robot.datesShown(FastingDateKind.force), [robot.dateLabel(first)]);

      await robot.addDaysOff();
      expect(robot.datesSheetOpen, isTrue);
      await robot.pickDates([first, second]);

      expect(robot.datesSheetOpen, isFalse);
      expect(writes.last.skipDates, {first, second});
      expect(writes.last.forceDates, isEmpty);
      expect(robot.datesShown(FastingDateKind.skip), [
        robot.dateLabel(first),
        robot.dateLabel(second),
      ]);
      expect(robot.datesShown(FastingDateKind.force), isEmpty);
    });

    testWidgets('Extra fast days adds the picked dates and takes them out of '
        'the days off', (tester) async {
      final (robot, writes) = await open(
        tester,
        initial: FastingSchedule(skipDates: {first}),
      );

      await robot.addExtraDays();
      await robot.pickDates([first, second]);

      expect(writes.last.forceDates, {first, second});
      expect(writes.last.skipDates, isEmpty);
      expect(robot.datesShown(FastingDateKind.force), [
        robot.dateLabel(first),
        robot.dateLabel(second),
      ]);
      expect(robot.datesShown(FastingDateKind.skip), isEmpty);
    });

    testWidgets('a cancelled Dates sheet writes nothing', (tester) async {
      final (robot, writes) = await open(tester);

      await robot.addDaysOff();
      await robot.cancelDates();

      expect(robot.datesSheetOpen, isFalse);
      expect(writes, isEmpty);
      expect(robot.datesShown(FastingDateKind.skip), isEmpty);
    });

    testWidgets('a date row\'s remove writes the schedule without it', (
      tester,
    ) async {
      final (robot, writes) = await open(
        tester,
        initial: FastingSchedule(skipDates: {second, first}),
      );
      // Sorted ascending, whatever order they were stored in.
      expect(robot.datesShown(FastingDateKind.skip), [
        robot.dateLabel(first),
        robot.dateLabel(second),
      ]);

      await robot.removeDate(FastingDateKind.skip, first);

      expect(writes.last.skipDates, {second});
      expect(robot.datesShown(FastingDateKind.skip), [robot.dateLabel(second)]);
    });

    testWidgets('at the cap the add button is disabled and reads Limit '
        'reached', (tester) async {
      final full = {
        for (var i = 0; i < FastingSchedule.maxExceptionDates; i++)
          DateTime.utc(2030, 1, 1).add(Duration(days: i)),
      };
      final (robot, _) = await open(
        tester,
        initial: FastingSchedule(skipDates: full),
      );

      expect(await robot.addDisabled(FastingDateKind.skip), isTrue);
      expect(await robot.addLabel(FastingDateKind.skip), 'Limit reached');
      expect(await robot.addDisabled(FastingDateKind.force), isFalse);
      // The row's value is the list's count, "None" while it is empty — the
      // old outlined button's invitation went with the button (Tier 3, D17).
      expect(await robot.addLabel(FastingDateKind.force), 'None');
    });
  });

  group('the sub-sheet of the language', () {
    const phone = Size(360, 780);

    Future<(FastingScheduleRobot, List<FastingSchedule>)> open(
      WidgetTester tester, {
      FastingSchedule initial = const FastingSchedule(),
      Size surface = FastingScheduleRobot.defaultSurface,
    }) async {
      final writes = <FastingSchedule>[];
      final robot = FastingScheduleRobot(tester);
      await robot.show(
        initialSchedule: initial,
        onChanged: writes.add,
        surface: surface,
      );
      return (robot, writes);
    }

    final weekdayIds = [
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        SemanticsIds.fastingWeekday(weekday),
    ];
    final monthIds = [
      for (var month = DateTime.january; month <= DateTime.december; month++)
        SemanticsIds.fastingMonth(month),
    ];
    const scopeIds = [
      SemanticsIds.fastingWeekdayScopeWeekly,
      SemanticsIds.fastingWeekdayScopeAll,
      SemanticsIds.fastingMonthScopeWeekly,
      SemanticsIds.fastingMonthScopeAll,
    ];
    const bulkIds = [
      SemanticsIds.fastingWeekdaysAll,
      SemanticsIds.fastingWeekdaysNone,
      SemanticsIds.fastingMonthsAll,
      SemanticsIds.fastingMonthsNone,
    ];

    /// The rects of [ids] relative to the first of them, so a body that
    /// scrolled to reach a control compares the same as one that did not.
    Map<String, Rect> rectsOf(FastingScheduleRobot robot, List<String> ids) {
      final anchor = robot.targetOf(ids.first).topLeft;
      return {for (final id in ids) id: robot.targetOf(id).shift(-anchor)};
    }

    testWidgets('a chip keeps its rect selected and unselected, and the run '
        'around it never reflows', (tester) async {
      // The old filter chips grew a check glyph when selected, so one tap
      // moved every chip after it (D16).
      final (robot, _) = await open(tester, surface: phone);
      final weekdaysBefore = rectsOf(robot, weekdayIds);
      final monthsBefore = rectsOf(robot, monthIds);
      final scopesBefore = rectsOf(robot, scopeIds.sublist(0, 2));

      await robot.toggleWeekday(DateTime.monday);
      expect(robot.weekdaySelected(DateTime.monday), isTrue);
      expect(rectsOf(robot, weekdayIds), weekdaysBefore);

      await robot.toggleWeekday(DateTime.wednesday);
      expect(robot.weekdaySelected(DateTime.wednesday), isFalse);
      expect(rectsOf(robot, weekdayIds), weekdaysBefore);

      await robot.toggleMonth(8);
      expect(robot.monthSelected(8), isFalse);
      expect(rectsOf(robot, monthIds), monthsBefore);

      await robot.pickWeekdayScope(FastingWeekdayScope.allFasts);
      expect(robot.weekdayScope, FastingWeekdayScope.allFasts);
      expect(rectsOf(robot, scopeIds.sublist(0, 2)), scopesBefore);
      expect(rectsOf(robot, weekdayIds), weekdaysBefore);
    });

    testWidgets('Select all and None are disabled in place while they would '
        'change nothing, in both sections', (tester) async {
      final (robot, writes) = await open(tester);
      final before = rectsOf(robot, bulkIds);
      // Wed and Fri: both weekday rows have work to do. Every month: Select
      // all has none.
      expect(robot.actionEnabled(SemanticsIds.fastingWeekdaysAll), isTrue);
      expect(robot.actionEnabled(SemanticsIds.fastingWeekdaysNone), isTrue);
      expect(robot.actionEnabled(SemanticsIds.fastingMonthsAll), isFalse);
      expect(robot.actionEnabled(SemanticsIds.fastingMonthsNone), isTrue);

      await robot.weekdaysSelectAll();
      expect(robot.actionEnabled(SemanticsIds.fastingWeekdaysAll), isFalse);
      expect(robot.actionEnabled(SemanticsIds.fastingWeekdaysNone), isTrue);
      // Disabled, never hidden: the row is still there, where it was.
      expect(rectsOf(robot, bulkIds), before);

      await robot.weekdaysSelectAll();
      expect(writes, hasLength(1), reason: 'a disabled row writes nothing');

      await robot.weekdaysNone();
      expect(robot.actionEnabled(SemanticsIds.fastingWeekdaysAll), isTrue);
      expect(robot.actionEnabled(SemanticsIds.fastingWeekdaysNone), isFalse);

      await robot.monthsNone();
      expect(robot.actionEnabled(SemanticsIds.fastingMonthsAll), isTrue);
      expect(robot.actionEnabled(SemanticsIds.fastingMonthsNone), isFalse);
      expect(rectsOf(robot, bulkIds), before);

      await robot.monthsNone();
      expect(writes, hasLength(3));
    });

    testWidgets('the scope caption slot keeps its height across the scope on '
        'both axes, so nothing under it moves', (tester) async {
      final (robot, _) = await open(tester, surface: phone);
      final weekdayLabel = robot.l10n.fastingWeekdayScopeTitle;
      final monthLabel = robot.l10n.fastingMonthScopeTitle;
      final weekdaySlot = robot.scopeSlotHeight(weekdayLabel);
      final monthSlot = robot.scopeSlotHeight(monthLabel);
      // How far the next section's first row sits under each scope's chips:
      // the body may scroll to reach a chip, the distance may not change.
      double underWeekdays() =>
          robot.targetOf(SemanticsIds.fastingMonthsAll).top -
          robot.targetOf(SemanticsIds.fastingWeekdayScopeWeekly).top;
      double underMonths() =>
          robot.targetOf(SemanticsIds.fastingDaysOff).top -
          robot.targetOf(SemanticsIds.fastingMonthScopeWeekly).top;
      final underWeekdaysBefore = underWeekdays();
      final underMonthsBefore = underMonths();

      await robot.pickWeekdayScope(FastingWeekdayScope.allFasts);
      expect(robot.weekdayScopeHint, weekdayAll);
      expect(robot.scopeSlotHeight(weekdayLabel), weekdaySlot);
      expect(underWeekdays(), moreOrLessEquals(underWeekdaysBefore));

      await robot.pickMonthScope(FastingMonthScope.allFasts);
      expect(robot.monthScopeHint, monthAll);
      expect(robot.scopeSlotHeight(monthLabel), monthSlot);
      expect(underMonths(), moreOrLessEquals(underMonthsBefore));
    });

    testWidgets('the exception rows and each date\'s remove carry ids, and a '
        'remove is a button named Remove', (tester) async {
      final skip = DateTime.utc(2030, 3, 15);
      final force = DateTime.utc(2030, 5, 1);
      final (robot, writes) = await open(
        tester,
        initial: FastingSchedule(skipDates: {skip}, forceDates: {force}),
      );

      expect(
        robot.targetOf(SemanticsIds.fastingDaysOff).height,
        greaterThanOrEqualTo(FormMetrics.rowMinHeight),
      );
      expect(
        robot.targetOf(SemanticsIds.fastingExtraDays).height,
        greaterThanOrEqualTo(FormMetrics.rowMinHeight),
      );
      expect(robot.removeIdsShown(FastingDateKind.skip), [
        SemanticsIds.fastingDateRemove('skip', skip),
      ]);
      expect(robot.removeIdsShown(FastingDateKind.force), [
        SemanticsIds.fastingDateRemove('force', force),
      ]);
      final remove = robot.nodeOf(SemanticsIds.fastingDateRemove('skip', skip));
      expect(remove.tooltip, 'Remove');
      expect(remove.flagsCollection.isButton, isTrue);
      expect(await robot.addLabel(FastingDateKind.skip), '1 exception');

      await robot.removeDate(FastingDateKind.force, force);
      expect(writes.single.forceDates, isEmpty);
      expect(writes.single.skipDates, {skip});
      expect(robot.removeIdsShown(FastingDateKind.force), isEmpty);
      expect(await robot.addLabel(FastingDateKind.force), 'None');
    });

    testWidgets('at the cap the Days off row is disabled in place and the '
        'Extra fast days row stays enabled', (tester) async {
      final full = {
        for (var i = 0; i < FastingSchedule.maxExceptionDates; i++)
          DateTime.utc(2030, 1, 1).add(Duration(days: i)),
      };
      final (robot, writes) = await open(
        tester,
        initial: FastingSchedule(skipDates: full),
      );

      final daysOff = robot.nodeOf(SemanticsIds.fastingDaysOff);
      expect(daysOff.flagsCollection.isEnabled, Tristate.isFalse);
      expect(daysOff.label, contains('Limit reached'));
      expect(
        robot.nodeOf(SemanticsIds.fastingExtraDays).flagsCollection.isEnabled,
        isNot(Tristate.isFalse),
      );
      expect(robot.datesShown(FastingDateKind.skip), hasLength(full.length));

      await robot.addDaysOff();
      expect(robot.datesSheetOpen, isFalse, reason: 'a disabled row is inert');
      expect(writes, isEmpty);
    });

    testWidgets('German at text scale 2.0 on 360 × 780 lays out with no '
        'layout error: the section labels, chip labels and action labels '
        'whole', (tester) async {
      // The old sheet broke "Wöchentliche Fastentage" over eight lines
      // beside its two text buttons at this scale (the record's §1).
      final robot = FastingScheduleRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          onChanged: (_) {},
          locale: const Locale('de'),
          textScale: 2.0,
          surface: phone,
        );
        expect(robot.headerTitle, 'Meine Praxis');
        expect(robot.sectionLabelWhole('Wöchentliche Fastentage'), isTrue);
        expect(robot.sectionLabelWhole('Monate, die du hältst'), isTrue);
        expect(robot.textWhole('Alle auswählen'), isTrue);
        expect(robot.textWhole('Wochentage gelten für'), isTrue);
        expect(robot.textWhole('Monate gelten für'), isTrue);
        expect(robot.textWhole('Nur wöchentliches Fasten'), isTrue);
        expect(robot.textWhole('Alle Fastenzeiten'), isTrue);
        expect(robot.textWhole('Freie Tage'), isTrue);
        expect(robot.textWhole('Zusätzliche Fastentage'), isTrue);
        for (
          var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++
        ) {
          expect(
            robot.controlLabelWhole(SemanticsIds.fastingWeekday(weekday)),
            isTrue,
            reason: 'weekday $weekday',
          );
        }
        for (
          var month = DateTime.january;
          month <= DateTime.december;
          month++
        ) {
          expect(
            robot.controlLabelWhole(SemanticsIds.fastingMonth(month)),
            isTrue,
            reason: 'month $month',
          );
        }
        for (final id in [...scopeIds, ...bulkIds]) {
          expect(robot.controlLabelWhole(id), isTrue, reason: id);
        }
        // Every control inside the sheet's width.
        final sheet = robot.sheetRect;
        for (final id in [
          ...weekdayIds,
          ...monthIds,
          ...scopeIds,
          ...bulkIds,
          SemanticsIds.fastingDaysOff,
          SemanticsIds.fastingExtraDays,
        ]) {
          final rect = robot.targetOf(id);
          expect(rect.left, greaterThanOrEqualTo(sheet.left), reason: id);
          expect(rect.right, lessThanOrEqualTo(sheet.right), reason: id);
        }
      });
      expect(errors, isEmpty);
    });

    testWidgets('every control is a 48 dp target at 360 × 780', (tester) async {
      final date = DateTime.utc(2030, 3, 15);
      final (robot, _) = await open(
        tester,
        initial: FastingSchedule(skipDates: {date}),
        surface: phone,
      );

      final close = robot.targetOf(SemanticsIds.fastingScheduleClose);
      expect(close.width, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
      expect(
        close.height,
        greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
      );
      for (final id in [...weekdayIds, ...monthIds, ...scopeIds]) {
        expect(
          robot.targetOf(id).height,
          greaterThanOrEqualTo(FormMetrics.chipTapTarget),
          reason: id,
        );
      }
      for (final id in [
        ...bulkIds,
        SemanticsIds.fastingDaysOff,
        SemanticsIds.fastingExtraDays,
      ]) {
        expect(
          robot.targetOf(id).height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
          reason: id,
        );
      }
      final remove = robot.targetOf(
        SemanticsIds.fastingDateRemove('skip', date),
      );
      expect(
        remove.width,
        greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
      );
      expect(
        remove.height,
        greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
      );
    });

    testWidgets('the ✕ carries its id, is named Close and closes the sheet '
        'without a write', (tester) async {
      final (robot, writes) = await open(tester);
      expect(robot.headerTitle, 'My practice');
      final close = robot.nodeOf(SemanticsIds.fastingScheduleClose);
      expect(close.tooltip, 'Close');
      expect(close.flagsCollection.isButton, isTrue);

      await robot.close();

      expect(robot.isOpen, isFalse);
      expect(writes, isEmpty);
    });
  });
}
