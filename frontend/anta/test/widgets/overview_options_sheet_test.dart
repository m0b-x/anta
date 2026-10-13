import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/overview_list_options.dart';

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
    await robot.show(listMode: false, onChanged: writes.add);

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
}
