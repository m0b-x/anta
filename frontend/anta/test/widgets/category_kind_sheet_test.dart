import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';

import 'support/category_kind_robot.dart';
import 'support/layout_errors.dart';

/// The kind picker the category editor opens (analytics S3): the catalogue
/// grouped by area with Custom last, a pick on tap, null on every way out,
/// and every example whole at 200 % in the two longer languages.
void main() {
  String id(CategoryKind kind) => SemanticsIds.categoryKind(kind.name);

  testWidgets('the kinds are grouped by area in the catalogue\'s order, '
      'Leave under Work after Study and Custom last', (tester) async {
    final robot = CategoryKindRobot(tester);
    await robot.show();

    expect(robot.sectionLabels, [
      'Health',
      'Work',
      'Money',
      'People',
      'Home',
      'Leisure',
      'Other',
    ]);
    expect(robot.rowIds, [
      for (final area in LifeArea.values)
        for (final row in CategoryKinds.inArea(area)) id(row.kind),
    ]);
    expect(robot.rowIds, hasLength(CategoryKind.values.length));
    expect(robot.rowIds.last, id(CategoryKind.custom));
    final study = robot.rowIds.indexOf(id(CategoryKind.study));
    expect(robot.rowIds[study + 1], id(CategoryKind.leave));
    expect(robot.rowLabels.first, 'Routine');
    expect(robot.rowCaptions.first, 'Stretching, journaling');
    expect(robot.rowCaptions.last, 'Anything else');
  });

  testWidgets('the selected kind is the one checked row; a tap returns its '
      'kind', (tester) async {
    final robot = CategoryKindRobot(tester);
    final outcome = await robot.show(selected: CategoryKind.bill);

    expect(robot.checkedIds, [id(CategoryKind.bill)]);
    await robot.pick(CategoryKind.chore);

    expect(robot.isOpen, isFalse);
    expect(outcome.returned, isTrue);
    expect(outcome.result, CategoryKind.chore);
  });

  testWidgets('✕, back and the barrier return null', (tester) async {
    final robot = CategoryKindRobot(tester);
    for (final leave in [robot.close, robot.systemBack, robot.tapBarrier]) {
      final outcome = await robot.show(selected: CategoryKind.workout);
      await leave();
      expect(robot.isOpen, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    }
  });

  testWidgets('it opens at the top, wherever the checked row is', (
    tester,
  ) async {
    final robot = CategoryKindRobot(tester);
    await robot.show(
      selected: CategoryKind.custom,
      surface: const Size(360, 780),
    );
    final first = robot.topOf(CategoryKind.routine);

    await robot.close();
    await robot.show(
      selected: CategoryKind.routine,
      surface: const Size(360, 780),
    );
    expect(robot.topOf(CategoryKind.routine), first);
    // Clamp-tall on a phone: twenty-one two-line rows outgrow it.
    expect(robot.sheetRect.height, closeTo(780 * 0.92, 1));
  });

  for (final locale in ['en', 'de', 'ro']) {
    testWidgets('$locale on 360 × 780: every example at most 28 characters '
        'and whole', (tester) async {
      final robot = CategoryKindRobot(tester);
      await robot.show(locale: Locale(locale), surface: const Size(360, 780));
      for (final caption in robot.rowCaptions) {
        // The record's rule, which keeps the two-line caption whole at
        // 200 % in Roboto (the S3 spec's measurements). The test font's
        // square glyphs are far wider, so wholeness is pinned at 100 %
        // here and at 200 % by the design review's real-font renders.
        expect(caption!.length, lessThanOrEqualTo(28), reason: caption);
        expect(robot.textWhole(caption), isTrue, reason: caption);
      }
    });
  }

  for (final locale in ['de', 'ro']) {
    testWidgets('$locale at 2.0 on 360 × 780: no layout error, every row '
        'two-line or taller', (tester) async {
      final robot = CategoryKindRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          locale: Locale(locale),
          textScale: 2.0,
          surface: const Size(360, 780),
        );
        for (final row in CategoryKinds.all) {
          await tester.ensureVisible(
            find.bySemanticsIdentifier(id(row.kind)).first,
          );
          await tester.pumpAndSettle();
          expect(
            robot.heightOf(row.kind),
            greaterThanOrEqualTo(FormMetrics.twoLineRowMinHeight),
          );
          expect(
            tester
                .getRect(find.bySemanticsIdentifier(id(row.kind)).first)
                .right,
            lessThanOrEqualTo(robot.sheetRect.right),
          );
        }
      });
      expect(errors, isEmpty);
    });
  }

  testWidgets('the rows meet the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final robot = CategoryKindRobot(tester);
    await robot.show(
      selected: CategoryKind.workout,
      surface: const Size(360, 780),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
