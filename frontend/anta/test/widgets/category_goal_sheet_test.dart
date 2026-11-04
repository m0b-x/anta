import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/widgets/category_goal_sheet.dart';

import 'support/category_goal_robot.dart';
import 'support/layout_errors.dart';

/// The goal sheet the category editor opens (analytics S3): the types the
/// primary takes, the value in its unit, the period, the read-back, and
/// Done / Remove goal / null — on a box that never changes height.
void main() {
  String type(TargetKind kind) => SemanticsIds.categoryGoalType(kind.name);

  // Workout's: attendance, at least a week, then a gap.
  const workout = [
    TargetPreset(TargetKind.atLeast, TargetPeriod.week),
    TargetPreset(TargetKind.maxGap),
  ];

  testWidgets('a fresh goal opens on the kind\'s first preset with the seed, '
      'the types in their one order', (tester) async {
    final robot = CategoryGoalRobot(tester);
    final outcome = await robot.show(
      primary: ReportMeasure.attendance,
      presets: workout,
    );

    expect(robot.typeIds, [
      type(TargetKind.atLeast),
      type(TargetKind.atMost),
      type(TargetKind.maxGap),
    ]);
    expect(robot.typeLabels, ['At least', 'At most', 'Days between']);
    expect(robot.selectedType, TargetKind.atLeast);
    expect(robot.valueLabel, 'Count');
    expect(robot.valueText, '3');
    expect(robot.selectedPeriod, TargetPeriod.week);
    expect(robot.readBack, 'At least 3 a week');
    expect(robot.removeShown, isFalse);
    // Never autofocused: the keyboard would cover the period.
    expect(robot.valueFocused, isFalse);

    await robot.done();

    expect(outcome.returned, isTrue);
    final saved = outcome.result! as CategoryGoalSaved;
    expect(
      saved.target,
      const ReportTarget(
        kind: TargetKind.atLeast,
        value: 3,
        period: TargetPeriod.week,
      ),
    );
  });

  testWidgets('✕, back and the barrier return null', (tester) async {
    final robot = CategoryGoalRobot(tester);
    for (final leave in [robot.close, robot.systemBack, robot.tapBarrier]) {
      final outcome = await robot.show(
        primary: ReportMeasure.attendance,
        presets: workout,
      );
      await robot.typeValue('5');
      await leave();
      expect(robot.isOpen, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    }
  });

  testWidgets('Budget lists only on a Money primary, in At most\'s place, '
      'with every period and the amount in whole money', (tester) async {
    final robot = CategoryGoalRobot(tester);
    final outcome = await robot.show(
      primary: ReportMeasure.money,
      presets: const [TargetPreset(TargetKind.budget, TargetPeriod.month)],
    );

    expect(robot.typeIds, [
      type(TargetKind.atLeast),
      type(TargetKind.budget),
      type(TargetKind.maxGap),
    ]);
    expect(robot.selectedType, TargetKind.budget);
    expect(robot.selectedPeriod, TargetPeriod.month);
    expect(robot.valueLabel, 'Amount');
    expect(robot.valueText, '100');
    for (final period in TargetPeriod.values) {
      expect(robot.periodEnabled(period), isTrue, reason: period.name);
    }

    await robot.typeValue('1200');
    expect(robot.readBack, 'Budget 1,200 a month');
    await robot.tapPeriod(TargetPeriod.year);
    expect(robot.readBack, 'Budget 1,200 a year');
    await robot.done();

    expect(
      (outcome.result! as CategoryGoalSaved).target,
      const ReportTarget(
        kind: TargetKind.budget,
        value: 120000,
        period: TargetPeriod.year,
      ),
    );

    await robot.show(primary: ReportMeasure.attendance, presets: workout);
    expect(robot.typeIds, isNot(contains(type(TargetKind.budget))));
  });

  testWidgets('hours are stepped whole and stored as minutes', (tester) async {
    final robot = CategoryGoalRobot(tester);
    final outcome = await robot.show(
      primary: ReportMeasure.hours,
      presets: const [TargetPreset(TargetKind.atMost, TargetPeriod.week)],
    );

    expect(robot.valueLabel, 'Hours');
    expect(robot.valueText, '8');
    await robot.typeValue('40');
    expect(robot.readBack, 'At most 40 h a week');
    await robot.done();

    expect((outcome.result! as CategoryGoalSaved).target.value, 40 * 60);
  });

  testWidgets('Days between counts days, disables the period in place, and '
      'switching back keeps the amount typed before', (tester) async {
    final robot = CategoryGoalRobot(tester);
    final outcome = await robot.show(
      primary: ReportMeasure.attendance,
      presets: workout,
    );
    await robot.typeValue('5');

    await robot.tapType(TargetKind.maxGap);
    expect(robot.valueLabel, 'Days');
    expect(robot.valueText, '30');
    expect(robot.readBack, 'At most 30 days between');
    for (final period in TargetPeriod.values) {
      expect(robot.periodEnabled(period), isFalse, reason: period.name);
    }
    await robot.typeValue('180');

    await robot.tapType(TargetKind.atLeast);
    expect(robot.valueText, '5');
    expect(robot.periodEnabled(TargetPeriod.week), isTrue);
    await robot.tapType(TargetKind.maxGap);
    expect(robot.valueText, '180');
    await robot.done();

    expect(
      (outcome.result! as CategoryGoalSaved).target,
      const ReportTarget(kind: TargetKind.maxGap, value: 180),
    );
  });

  testWidgets('Days between shows no period chosen, and switching back '
      'restores the period last picked', (tester) async {
    final robot = CategoryGoalRobot(tester);
    await robot.show(primary: ReportMeasure.attendance, presets: workout);
    await robot.tapPeriod(TargetPeriod.month);

    await robot.tapType(TargetKind.maxGap);
    expect(robot.selectedPeriod, isNull);

    await robot.tapType(TargetKind.atMost);
    expect(robot.selectedPeriod, TargetPeriod.month);
    expect(robot.readBack, 'At most 3 a month');
    await robot.close();

    // A stored gap opens with none chosen too, and an amount brings the
    // preset's period.
    await robot.show(
      initial: const ReportTarget(kind: TargetKind.maxGap, value: 14),
      primary: ReportMeasure.attendance,
      presets: workout,
    );
    expect(robot.selectedPeriod, isNull);
    await robot.tapType(TargetKind.atLeast);
    expect(robot.selectedPeriod, TargetPeriod.week);
  });

  for (final (primary, presets, order, preselected) in [
    (
      ReportMeasure.attendance,
      workout,
      [TargetKind.atLeast, TargetKind.atMost, TargetKind.maxGap],
      TargetKind.atLeast,
    ),
    (
      ReportMeasure.hours,
      const [TargetPreset(TargetKind.atMost, TargetPeriod.week)],
      [TargetKind.atLeast, TargetKind.atMost, TargetKind.maxGap],
      TargetKind.atMost,
    ),
    (
      ReportMeasure.money,
      const [TargetPreset(TargetKind.budget, TargetPeriod.month)],
      [TargetKind.atLeast, TargetKind.budget, TargetKind.maxGap],
      TargetKind.budget,
    ),
  ]) {
    testWidgets('a ${primary.name} primary lists the types in the one order, '
        'its preset preselected in place', (tester) async {
      final robot = CategoryGoalRobot(tester);
      await robot.show(primary: primary, presets: presets);

      expect(robot.typeIds, [for (final kind in order) type(kind)]);
      expect(robot.selectedType, preselected);
    });
  }

  // de 2.0 is where real fonts split Aufgaben from Tage; in the test font,
  // whose every glyph is a square, the split falls at 1.3.
  for (final (locale, scale) in [('de', 2.0), ('de', 1.3), ('en', 1.0)]) {
    testWidgets('$locale at $scale on 360 × 780: a switch of type moves '
        'neither the − button nor the period chips on a Tasks primary', (
      tester,
    ) async {
      final robot = CategoryGoalRobot(tester);
      await robot.show(
        primary: ReportMeasure.tasks,
        presets: const [TargetPreset(TargetKind.atLeast, TargetPeriod.week)],
        locale: Locale(locale),
        textScale: scale,
        surface: const Size(360, 780),
      );
      // Read against the first type row, which a tap's scroll into view
      // moves by as much: what is left is the layout's own movement.
      Rect inBody(Rect rect) =>
          rect.shift(-robot.typeRect(TargetKind.atLeast).topLeft);
      final less = inBody(robot.lessRect);
      final day = inBody(robot.periodRect(TargetPeriod.day));

      for (final kind in [
        TargetKind.maxGap,
        TargetKind.atMost,
        TargetKind.maxGap,
        TargetKind.atLeast,
      ]) {
        await robot.tapType(kind);
        expect(inBody(robot.lessRect), less, reason: kind.name);
        expect(
          inBody(robot.periodRect(TargetPeriod.day)),
          day,
          reason: kind.name,
        );
      }
    });
  }

  testWidgets('Last seen takes a gap alone: the amounts are disabled in '
      'place and Days between is preselected', (tester) async {
    final robot = CategoryGoalRobot(tester);
    await robot.show(
      primary: ReportMeasure.lastSeen,
      presets: const [TargetPreset(TargetKind.maxGap)],
    );

    expect(robot.typeIds, hasLength(3));
    expect(robot.typeEnabled(TargetKind.atLeast), isFalse);
    expect(robot.typeEnabled(TargetKind.atMost), isFalse);
    expect(robot.typeEnabled(TargetKind.maxGap), isTrue);
    expect(robot.selectedType, TargetKind.maxGap);
  });

  testWidgets('the stepper stops at 1 and at the unit\'s ceiling, and rewrites '
      'the field', (tester) async {
    final robot = CategoryGoalRobot(tester);
    await robot.show(primary: ReportMeasure.count, presets: workout);

    await robot.typeValue('1');
    expect(robot.canLess, isFalse);
    expect(robot.canMore, isTrue);
    await robot.more();
    expect(robot.valueText, '2');
    expect(robot.readBack, 'At least 2 a week');

    // Three digits for a count.
    await robot.typeValue('99999');
    expect(robot.valueText, '999');
    expect(robot.canMore, isFalse);
    await robot.less();
    expect(robot.valueText, '998');
  });

  testWidgets('Done is disabled while the field is empty or 0', (tester) async {
    final robot = CategoryGoalRobot(tester);
    await robot.show(primary: ReportMeasure.count, presets: workout);

    await robot.typeValue('');
    expect(robot.canDone, isFalse);
    expect(robot.readBack, 'No goal');
    await robot.typeValue('0');
    expect(robot.canDone, isFalse);
    await robot.typeValue('4');
    expect(robot.canDone, isTrue);
  });

  testWidgets('a stored goal opens as stored, and Remove goal returns the '
      'removal', (tester) async {
    final robot = CategoryGoalRobot(tester);
    final outcome = await robot.show(
      initial: const ReportTarget(
        kind: TargetKind.atMost,
        value: 40 * 60,
        period: TargetPeriod.month,
      ),
      primary: ReportMeasure.hours,
      presets: const [TargetPreset(TargetKind.atMost, TargetPeriod.week)],
    );

    expect(robot.selectedType, TargetKind.atMost);
    expect(robot.valueText, '40');
    expect(robot.selectedPeriod, TargetPeriod.month);
    expect(robot.removeShown, isTrue);
    await robot.remove();

    expect(outcome.result, isA<CategoryGoalRemoved>());
  });

  testWidgets('a stored part of an hour is kept verbatim: read back exactly, '
      'and stored as it was by a Done that only moved the period', (
    tester,
  ) async {
    final robot = CategoryGoalRobot(tester);
    const stored = ReportTarget(
      kind: TargetKind.atLeast,
      value: 450,
      period: TargetPeriod.week,
    );
    var outcome = await robot.show(
      initial: stored,
      primary: ReportMeasure.hours,
      presets: const [],
    );

    expect(robot.valueText, '7');
    expect(robot.readBack, 'At least 7.5 h a week');
    await robot.tapPeriod(TargetPeriod.month);
    expect(robot.readBack, 'At least 7.5 h a month');
    await robot.done();
    expect(
      (outcome.result! as CategoryGoalSaved).target,
      const ReportTarget(
        kind: TargetKind.atLeast,
        value: 450,
        period: TargetPeriod.month,
      ),
    );

    // A changed value is the owner's own, in whole hours.
    outcome = await robot.show(
      initial: stored,
      primary: ReportMeasure.hours,
      presets: const [],
    );
    await robot.more();
    expect(robot.readBack, 'At least 8 h a week');
    await robot.done();
    expect((outcome.result! as CategoryGoalSaved).target.value, 8 * 60);

    // So is one after a change of type.
    outcome = await robot.show(
      initial: stored,
      primary: ReportMeasure.hours,
      presets: const [],
    );
    await robot.tapType(TargetKind.atMost);
    expect(robot.readBack, 'At most 7 h a week');
    await robot.done();
    expect((outcome.result! as CategoryGoalSaved).target.value, 7 * 60);
  });

  testWidgets('Budget preselects Month on a Money primary with no Budget '
      'preset, unless a period was picked here', (tester) async {
    final robot = CategoryGoalRobot(tester);
    // Income's shape: money, no Budget among the presets.
    const income = [TargetPreset(TargetKind.atLeast, TargetPeriod.week)];
    await robot.show(primary: ReportMeasure.money, presets: income);

    expect(robot.selectedType, TargetKind.atLeast);
    expect(robot.selectedPeriod, TargetPeriod.week);
    await robot.tapType(TargetKind.budget);
    expect(robot.selectedPeriod, TargetPeriod.month);
    await robot.close();

    await robot.show(primary: ReportMeasure.money, presets: income);
    await robot.tapPeriod(TargetPeriod.year);
    await robot.tapType(TargetKind.budget);
    expect(robot.selectedPeriod, TargetPeriod.year);
  });

  testWidgets('a stored type the primary does not list opens checked, with '
      'its reason, and Done keeps it; Remove goal still removes', (
    tester,
  ) async {
    final robot = CategoryGoalRobot(tester);
    const budget = ReportTarget(
      kind: TargetKind.budget,
      value: 5,
      period: TargetPeriod.month,
    );
    var outcome = await robot.show(
      initial: budget,
      primary: ReportMeasure.count,
      presets: workout,
    );

    expect(robot.typeIds, [
      type(TargetKind.atLeast),
      type(TargetKind.atMost),
      type(TargetKind.maxGap),
      type(TargetKind.budget),
    ]);
    expect(robot.selectedType, TargetKind.budget);
    expect(robot.typeCaption(TargetKind.budget), 'Not for this measure');
    expect(robot.typeCaption(TargetKind.atLeast), isNull);
    expect(robot.readBack, 'Budget 5 a month');
    expect(robot.canDone, isTrue);
    await robot.done();
    expect((outcome.result! as CategoryGoalSaved).target, budget);

    // Left for another type, it cannot be picked again.
    await robot.show(
      initial: budget,
      primary: ReportMeasure.count,
      presets: workout,
    );
    await robot.tapType(TargetKind.atLeast);
    expect(robot.typeEnabled(TargetKind.budget), isFalse);
    expect(robot.selectedType, TargetKind.atLeast);
    await robot.close();

    // At most on a Money primary, the other way round.
    outcome = await robot.show(
      initial: const ReportTarget(
        kind: TargetKind.atMost,
        value: 120000,
        period: TargetPeriod.month,
      ),
      primary: ReportMeasure.money,
      presets: const [],
    );
    expect(robot.selectedType, TargetKind.atMost);
    expect(robot.readBack, 'At most 1,200 a month');
    expect(robot.canDone, isTrue);
    await robot.remove();
    expect(outcome.result, isA<CategoryGoalRemoved>());
  });

  for (final (primary, presets) in [
    (
      ReportMeasure.hours,
      const [TargetPreset(TargetKind.atMost, TargetPeriod.week)],
    ),
    (ReportMeasure.count, workout),
    (
      ReportMeasure.tasks,
      const [TargetPreset(TargetKind.atLeast, TargetPeriod.week)],
    ),
  ]) {
    testWidgets('de at 2.0 on 360 × 780: a ${primary.name} goal keeps one '
        'height through every type and value', (tester) async {
      final robot = CategoryGoalRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          primary: primary,
          presets: presets,
          locale: const Locale('de'),
          textScale: 2.0,
          surface: const Size(360, 780),
        );
        final height = robot.sheetRect.height;
        final widest = CategoryGoalLimits.maxFor(
          CategoryGoalLimits.maxDigits(CategoryGoalLimits.unitOf(primary)!),
        );
        for (final kind in [
          TargetKind.atLeast,
          TargetKind.maxGap,
          TargetKind.atMost,
        ]) {
          await robot.tapType(kind);
          expect(robot.sheetRect.height, height, reason: kind.name);
          await robot.typeValue(kind == TargetKind.maxGap ? '9999' : '$widest');
          expect(robot.sheetRect.height, height, reason: '${kind.name} wide');
          await robot.typeValue('');
          expect(robot.sheetRect.height, height, reason: '${kind.name} empty');
        }
      });
      expect(errors, isEmpty);
    });
  }

  for (final (locale, scale) in [('de', 2.0), ('ro', 2.0), ('de', 1.3)]) {
    testWidgets('$locale at $scale on 360 × 780: the sheet keeps one height '
        'through every type and value', (tester) async {
      final robot = CategoryGoalRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          primary: ReportMeasure.money,
          presets: const [TargetPreset(TargetKind.budget, TargetPeriod.month)],
          locale: Locale(locale),
          textScale: scale,
          surface: const Size(360, 780),
        );
        final height = robot.sheetRect.height;
        for (final kind in [
          TargetKind.atLeast,
          TargetKind.maxGap,
          TargetKind.budget,
        ]) {
          await robot.tapType(kind);
          expect(robot.sheetRect.height, height, reason: kind.name);
          await robot.typeValue(kind == TargetKind.maxGap ? '9999' : '9999999');
          expect(robot.sheetRect.height, height, reason: '${kind.name} wide');
          await robot.typeValue('');
          expect(robot.sheetRect.height, height, reason: '${kind.name} empty');
        }
      });
      expect(errors, isEmpty);
    });
  }

  testWidgets('with the keyboard up at 1.3 the value row stays on screen', (
    tester,
  ) async {
    final robot = CategoryGoalRobot(tester);
    await robot.show(
      primary: ReportMeasure.count,
      presets: workout,
      locale: const Locale('de'),
      textScale: 1.3,
      surface: const Size(360, 780),
    );
    await tester.tap(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.categoryGoalValue),
        matching: find.byType(EditableText),
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final field = tester.getRect(
      find.bySemanticsIdentifier(SemanticsIds.categoryGoalValue),
    );
    expect(field.bottom, lessThanOrEqualTo(780 - 330));
  });

  testWidgets('the sheet meets the tap-target, label and contrast '
      'guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final robot = CategoryGoalRobot(tester);
    await robot.show(
      initial: const ReportTarget(
        kind: TargetKind.atLeast,
        value: 3,
        period: TargetPeriod.week,
      ),
      primary: ReportMeasure.count,
      presets: workout,
      surface: const Size(360, 780),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
