import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/widgets/form_rows.dart';

import 'support/layout_errors.dart';
import 'support/overview_options_robot.dart';

/// The overview list's options sheet (`docs/calendar-overview-list-roadmap.md`
/// §3.2 item 6): a live-apply sub-sheet, so every control writes at once and
/// every way out keeps what was set.
void main() {
  late List<OverviewListOptions> writes;

  setUp(() => writes = []);

  testWidgets('opens on the options it was handed', (tester) async {
    final robot = OverviewOptionsRobot(tester);
    await robot.show(
      initial: const OverviewListOptions(
        order: OverviewOrder.newestFirst,
        rows: OverviewRows.perEvent,
        missedOnly: true,
      ),
      onChanged: writes.add,
    );

    expect(robot.order, OverviewOrder.newestFirst);
    expect(robot.orderLabel, robot.l10n.overviewOrderNewestFirst);
    expect(robot.rows, OverviewRows.perEvent);
    expect(robot.rowsLabel, robot.l10n.overviewRowsPerEvent);
    expect(robot.missedOnly, isTrue);
    expect(writes, isEmpty);
  });

  testWidgets('each control writes at once and the sheet redraws', (
    tester,
  ) async {
    final robot = OverviewOptionsRobot(tester);
    await robot.show(onChanged: writes.add);

    await robot.pickOrder(OverviewOrder.newestFirst);
    expect(
      writes.last,
      const OverviewListOptions(order: OverviewOrder.newestFirst),
    );
    expect(robot.orderLabel, robot.l10n.overviewOrderNewestFirst);

    await robot.pickRows(OverviewRows.perEvent);
    expect(
      writes.last,
      const OverviewListOptions(
        order: OverviewOrder.newestFirst,
        rows: OverviewRows.perEvent,
      ),
    );
    expect(robot.rowsLabel, robot.l10n.overviewRowsPerEvent);

    await robot.toggleMissedOnly();
    expect(
      writes.last,
      const OverviewListOptions(
        order: OverviewOrder.newestFirst,
        rows: OverviewRows.perEvent,
        missedOnly: true,
      ),
    );
    expect(robot.missedOnly, isTrue);
    expect(writes, hasLength(3));
    expect(robot.isOpen, isTrue, reason: 'nothing to confirm, nothing closes');
  });

  testWidgets('the current item wears the check; picking it writes nothing', (
    tester,
  ) async {
    final robot = OverviewOptionsRobot(tester);
    await robot.show(onChanged: writes.add);

    await robot.tapRow(SemanticsIds.overviewOrder);
    expect(robot.menuItemChecked(SemanticsIds.overviewOrderOldest), isTrue);
    expect(robot.menuItemChecked(SemanticsIds.overviewOrderNewest), isFalse);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.overviewOrderOldest),
    );
    await tester.pumpAndSettle();

    expect(writes, isEmpty);
  });

  for (final (name, leave)
      in <(String, Future<void> Function(OverviewOptionsRobot))>[
        ('✕', (robot) => robot.close()),
        ('the barrier', (robot) => robot.tapBarrier()),
        ('a drag', (robot) => robot.dragDown()),
      ]) {
    testWidgets('$name closes the sheet and keeps what was set', (
      tester,
    ) async {
      final robot = OverviewOptionsRobot(tester);
      await robot.show(onChanged: writes.add);
      await robot.toggleMissedOnly();

      await leave(robot);

      expect(robot.isOpen, isFalse);
      expect(writes, [const OverviewListOptions(missedOnly: true)]);
    });
  }

  testWidgets('outside list mode Order and Rows are disabled, never hidden; '
      'Missed only stays live', (tester) async {
    final robot = OverviewOptionsRobot(tester);
    await robot.show(mode: AgendaDayListMode.month, onChanged: writes.add);

    expect(robot.enabled(SemanticsIds.overviewOrder), isFalse);
    expect(robot.enabled(SemanticsIds.overviewRows), isFalse);
    expect(robot.enabled(SemanticsIds.overviewMissedOnly), isTrue);

    await robot.tapRow(SemanticsIds.overviewOrder);
    expect(robot.menuOpen, isFalse);
    await robot.tapRow(SemanticsIds.overviewRows);
    expect(robot.menuOpen, isFalse);

    await robot.toggleMissedOnly();
    expect(writes, [const OverviewListOptions(missedOnly: true)]);
  });

  testWidgets('in Year mode Missed only is disabled too, never hidden: the '
      'tiles do not change with it (D33)', (tester) async {
    final robot = OverviewOptionsRobot(tester);
    await robot.show(mode: AgendaDayListMode.year, onChanged: writes.add);

    expect(robot.enabled(SemanticsIds.overviewOrder), isFalse);
    expect(robot.enabled(SemanticsIds.overviewRows), isFalse);
    expect(robot.enabled(SemanticsIds.overviewMissedOnly), isFalse);
    expect(robot.enabled(SemanticsIds.overviewCategories), isTrue);

    await robot.tapRow(SemanticsIds.overviewMissedOnly);
    expect(robot.missedOnly, isFalse);
    expect(writes, isEmpty);
  });

  testWidgets('German at 200 % on a 360 × 780 phone: no overflow, every label '
      'whole', (tester) async {
    final robot = OverviewOptionsRobot(tester);
    final errors = await layoutErrorsDuring(() async {
      await robot.show(
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(360, 780),
        initial: const OverviewListOptions(
          order: OverviewOrder.newestFirst,
          rows: OverviewRows.perEvent,
        ),
        onChanged: writes.add,
      );
    });

    expect(errors, isEmpty);
    for (final id in [
      SemanticsIds.overviewOrder,
      SemanticsIds.overviewRows,
      SemanticsIds.overviewMissedOnly,
    ]) {
      expect(robot.controlLabelWhole(id), isTrue, reason: id);
    }
  });

  testWidgets('a Rows change writes rows alone', (tester) async {
    final robot = OverviewOptionsRobot(tester);
    await robot.show(onChanged: writes.add);

    await robot.pickRows(OverviewRows.perEvent);

    expect(writes, [const OverviewListOptions(rows: OverviewRows.perEvent)]);
  });

  group('Categories (D22)', () {
    late List<Set<String>> picks;

    setUp(() {
      picks = [];
      CalendarCategories.updateCache([
        for (var i = 0; i < 4; i++)
          CalendarCategory(
            id: 'c$i',
            name: 'Cat$i',
            colorValue: 0xFF1E88E5,
            iconKey: 'event',
            sortOrder: i,
            isBuiltIn: false,
          ),
      ]);
    });

    tearDown(() => CalendarCategories.updateCache(const []));

    testWidgets('the first row reads the allowlist back: All, two names, '
        'then "+N more"', (tester) async {
      final robot = OverviewOptionsRobot(tester);
      await robot.show(onChanged: writes.add);
      expect(robot.categoriesValue, robot.l10n.calendarFilterCategoriesAll);
      expect(
        tester
            .getTopLeft(
              find.bySemanticsIdentifier(SemanticsIds.overviewCategories),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.bySemanticsIdentifier(SemanticsIds.overviewOrder),
              )
              .dy,
        ),
        reason: 'above Order',
      );
      await robot.close();

      await robot.show(onChanged: writes.add, categoryIds: {'c2', 'c0'});
      expect(robot.categoriesValue, 'Cat0, Cat2');
      await robot.close();

      await robot.show(onChanged: writes.add, categoryIds: {'c0', 'c1', 'c3'});
      expect(
        robot.categoriesValue,
        'Cat0, Cat1 ${robot.l10n.categoriesMore(1)}',
      );
    });

    testWidgets('a pick opens the picker over the sheet, applies at once and '
        'reports once; the same set again reports nothing', (tester) async {
      final robot = OverviewOptionsRobot(tester);
      await robot.show(onChanged: writes.add, onCategoriesChanged: picks.add);

      await robot.openCategories();
      expect(robot.pickerOpen, isTrue);
      expect(robot.isOpen, isTrue, reason: 'the sheet stays under it');
      await robot.pickerSelectNone();
      await robot.togglePickerRow('c1');
      await robot.pickerDone();

      expect(robot.pickerOpen, isFalse);
      expect(picks, [
        {'c1'},
      ]);
      expect(robot.categoriesValue, 'Cat1');

      await robot.pickCategories({'c1'});
      expect(picks, hasLength(1));

      await robot.openCategories();
      await robot.pickerClose();
      expect(picks, hasLength(1), reason: 'a dismissed picker changes nothing');
      expect(writes, isEmpty);
    });

    testWidgets('a pick covering every offered category collapses to the '
        'empty allowlist', (tester) async {
      final robot = OverviewOptionsRobot(tester);
      await robot.show(
        onChanged: writes.add,
        categoryIds: {'c0'},
        onCategoriesChanged: picks.add,
      );

      await robot.openCategories();
      await robot.pickerSelectAll();
      await robot.pickerDone();

      expect(picks, [<String>{}]);
      expect(robot.categoriesValue, robot.l10n.calendarFilterCategoriesAll);
    });

    testWidgets('a pick that turns All into two names and "+N more" takes '
        'the value\'s second line, never an ellipsis, under the semantics '
        'refresh (D33)', (tester) async {
      final robot = OverviewOptionsRobot(tester);
      await robot.show(onChanged: writes.add, surface: const Size(360, 780));
      expect(robot.categoriesValue, robot.l10n.calendarFilterCategoriesAll);
      expect(find.byType(FormSheetSemanticsRefresh), findsOneWidget);
      final before = robot.sheetRect.height;

      await robot.pickCategories({'c0', 'c1', 'c3'});

      expect(
        robot.categoriesValue,
        'Cat0, Cat1 ${robot.l10n.categoriesMore(1)}',
      );
      final value = robot.categoriesValueParagraph;
      expect(value.maxLines, FormMetrics.valueMaxLines);
      expect(value.didExceedMaxLines, isFalse);
      expect(
        robot.sheetRect.height,
        greaterThan(before),
        reason: 'the read-back wraps to its second line at 360 dp',
      );
    });

    testWidgets('an archived category in the allowlist is still read back', (
      tester,
    ) async {
      CalendarCategories.updateCache([
        for (var i = 0; i < 4; i++)
          CalendarCategory(
            id: 'c$i',
            name: 'Cat$i',
            colorValue: 0xFF1E88E5,
            iconKey: 'event',
            sortOrder: i,
            isBuiltIn: false,
            isHidden: i == 2,
          ),
      ]);
      final robot = OverviewOptionsRobot(tester);
      await robot.show(onChanged: writes.add, categoryIds: {'c2', 'c0'});

      expect(robot.categoriesValue, 'Cat0, Cat2');
    });
  });
}
