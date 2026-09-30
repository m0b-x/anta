import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/row_metrics.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';

/// The grouped-row primitives every calendar sheet is built from. These pin
/// the contract the `calendar-ui` skill states: an `identifier` lands on the
/// row's own node together with its label and its tap, a two-target row keeps
/// its trailing button as a second node, a chip's tap target is padded to
/// 48 dp, and a disabled row is drawn at the disabled opacity without ink.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: FormRowGroup(children: [child]),
    ),
  );

  group('identifiers', () {
    testWidgets('a picker row merges the id, the label and the tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          FormPickerRow(
            glyph: Icons.label_outlined,
            label: 'Category',
            value: 'Strength',
            identifier: 'event-category',
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('event-category'), findsOneWidget);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('event-category'),
          matching: find.text('Category'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsIdentifier('event-category'));
      expect(taps, 1);
    });

    testWidgets('a two-target row keeps its trailing button as its own node', (
      tester,
    ) async {
      var rowTaps = 0;
      var removes = 0;
      await tester.pumpWidget(
        host(
          FormPickerRow(
            glyph: Icons.event_outlined,
            label: 'Sep 30',
            identifier: 'event-date-row',
            onTap: () => rowTaps++,
            trailingButton: FormTrailingButton(
              icon: Icons.close_rounded,
              tooltip: 'Remove date',
              onPressed: () => removes++,
            ),
          ),
        ),
      );
      final row = tester.getSemantics(
        find.bySemanticsIdentifier('event-date-row'),
      );
      expect(row.label, isNot(contains('Remove date')));
      await tester.tap(find.byTooltip('Remove date'));
      expect(removes, 1);
      expect(rowTaps, 0);
      await tester.tap(find.bySemanticsIdentifier('event-date-row'));
      expect(rowTaps, 1);
    });

    testWidgets('a switch row is one node that toggles from the id', (
      tester,
    ) async {
      bool? received;
      await tester.pumpWidget(
        host(
          FormSwitchRow(
            glyph: Icons.schedule_outlined,
            label: 'All day',
            value: false,
            identifier: 'event-all-day',
            onChanged: (v) => received = v,
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('event-all-day'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('event-all-day'));
      expect(received, isTrue);
    });

    testWidgets('an action row carries its id and its label', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          FormActionRow(
            glyph: Icons.delete_outline,
            label: 'Delete event',
            destructive: true,
            identifier: 'event-delete',
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('event-delete'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('event-delete'));
      expect(taps, 1);
    });

    testWidgets('a menu row passes its id to the row it draws', (tester) async {
      await tester.pumpWidget(
        host(
          FormMenuRow<int>(
            glyph: Icons.flag_outlined,
            label: 'Priority',
            value: 'Normal',
            selected: 3,
            identifier: 'event-priority',
            menuWidth: 200,
            items: const [
              FormMenuItem(value: 1, label: 'Highest'),
              FormMenuItem(value: 3, label: 'Normal'),
            ],
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('event-priority'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('event-priority'));
      await tester.pumpAndSettle();
      expect(find.text('Highest'), findsOneWidget);
    });

    testWidgets('a row without an identifier exposes no id node', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(FormPickerRow(label: 'Starts', value: '18:00', onTap: () {})),
      );
      expect(find.bySemanticsIdentifier('event-starts'), findsNothing);
      expect(find.text('Starts'), findsOneWidget);
    });
  });

  group('geometry', () {
    testWidgets('a chip is padded to the 48 dp tap target', (tester) async {
      await tester.pumpWidget(
        host(
          FormChipRow(
            chips: [
              FormChip(label: 'Count from 1', selected: true, onTap: () {}),
            ],
          ),
        ),
      );
      final size = tester.getSize(find.byType(FormChip));
      expect(size.height, FormMetrics.chipTapTarget);
    });

    testWidgets('a picker row is at least the row minimum', (tester) async {
      await tester.pumpWidget(
        host(FormPickerRow(label: 'Repeat', value: 'Weekly', onTap: () {})),
      );
      expect(
        tester.getSize(find.byType(FormPickerRow)).height,
        greaterThanOrEqualTo(FormMetrics.rowMinHeight),
      );
    });

    testWidgets('a picker row with a leading widget takes the title row '
        'shape, the title indent and stays one node', (tester) async {
      var taps = 0;
      final row = FormPickerRow(
        leading: const EventAvatar(
          icon: Icons.fitness_center,
          color: Colors.blue,
        ),
        label: 'Leg day',
        identifier: 'template-pick-t1',
        showChevron: false,
        onTap: () => taps++,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormRowGroup(
              children: [
                row,
                FormPickerRow(label: 'Blank event', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentTitle);
      expect(
        tester.widget<Divider>(find.byType(Divider)).indent,
        FormMetrics.dividerIndentTitle,
      );
      expect(
        tester.getSize(find.byType(FormPickerRow).first).height,
        FormMetrics.titleRowMinHeight,
      );
      expect(
        tester.getTopLeft(find.text('Leg day')).dx,
        RowMetrics.groupInset + FormMetrics.rowLeadingSize + FormMetrics.gap,
      );
      // The avatar is decoration: the row is still one node carrying the
      // id, the label and the tap.
      expect(find.bySemanticsIdentifier('template-pick-t1'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Leg day')), findsOneWidget);
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('template-pick-t1'))
          .getSemanticsData();
      expect(data.identifier, 'template-pick-t1');
      expect(data.label, contains('Leg day'));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.bySemanticsIdentifier('template-pick-t1'));
      expect(taps, 1);
    });

    testWidgets('a picker row with a leading widget and a caption takes the '
        'two-line shape, centres the widget against both lines and stays '
        'one node', (tester) async {
      const summary = 'Gym · Every week on Mon, Wed · 18:00–19:30';
      var taps = 0;
      await tester.pumpWidget(
        host(
          FormPickerRow(
            leading: const EventAvatar(
              icon: Icons.fitness_center,
              color: Colors.blue,
            ),
            label: 'Leg day',
            caption: summary,
            identifier: 'template-pick-t1',
            showChevron: false,
            onTap: () => taps++,
          ),
        ),
      );
      final row = tester.getRect(find.byType(FormPickerRow));
      expect(row.height, FormMetrics.twoLineRowMinHeight);
      // The avatar sits on the row's centre line — between the label and the
      // caption — not on the label's, where it floated with the caption
      // hanging under it.
      expect(
        tester.getCenter(find.byType(EventAvatar)).dy,
        closeTo(row.center.dy, 0.5),
      );
      final label = tester.getRect(find.text('Leg day'));
      final caption = tester.getRect(find.text(summary));
      expect(caption.left, label.left);
      expect(caption.top, greaterThanOrEqualTo(label.bottom));
      expect(label.top - row.top, closeTo(row.bottom - caption.bottom, 0.5));
      // Clamped like a value: a summary at 200 % German ran four lines.
      expect(tester.widget<Text>(find.text(summary)).maxLines, 2);
      // One node carrying the id, the label, the caption and the tap.
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('template-pick-t1'))
          .getSemanticsData();
      expect(data.label, contains('Leg day'));
      expect(data.label, contains('18:00'));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.bySemanticsIdentifier('template-pick-t1'));
      expect(taps, 1);
    });

    testWidgets('a disabled action row is faded and inert', (tester) async {
      await tester.pumpWidget(
        host(
          FormActionRow(
            glyph: Icons.add,
            label: 'Add alert',
            identifier: 'event-alert-add',
            onTap: null,
          ),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(FormActionRow),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, FormMetrics.disabledOpacity);
      final node = tester.getSemantics(
        find.bySemanticsIdentifier('event-alert-add'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });
  });
  group('shared chrome and read rows', () {
    Widget page(Widget child, {double width = 412}) => MediaQuery(
      data: MediaQueryData(size: Size(width, 915)),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: FormRowGroup(children: [child]),
          ),
        ),
      ),
    );

    testWidgets('the header text button carries its id and its label', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormHeaderTextButton(
              label: 'Done',
              identifier: 'look-done',
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('look-done'), findsOneWidget);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier('look-done'),
          matching: find.text('Done'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        FormMetrics.headerHeight,
      );
      await tester.tap(find.bySemanticsIdentifier('look-done'));
      expect(taps, 1);
    });

    testWidgets('a disabled header text button has no tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormHeaderTextButton(
              label: 'Done',
              identifier: 'repeat-done',
              onPressed: null,
            ),
          ),
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsIdentifier('repeat-done'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets("a picker row's caption sits inside the row's own node", (
      tester,
    ) async {
      await tester.pumpWidget(
        page(
          const FormPickerRow(
            glyph: Icons.next_plan_outlined,
            label: 'Next occurrence',
            value: 'Mon, Sep 28',
            caption: 'then Oct 1 · Oct 5 · Oct 8',
            identifier: 'next-row',
            onTap: null,
            showChevron: false,
          ),
        ),
      );
      // The merging node reports its merged label and id through its data,
      // not through the node's own getters.
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('next-row'))
          .getSemanticsData();
      expect(data.identifier, 'next-row');
      expect(data.label, contains('Next occurrence'));
      expect(data.label, contains('then Oct 1'));
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      // The caption is aligned with the label, past the glyph column.
      expect(
        tester.getTopLeft(find.text('then Oct 1 · Oct 5 · Oct 8')).dx,
        tester.getTopLeft(find.text('Next occurrence')).dx,
      );
      expect(
        tester.getSize(find.byType(FormPickerRow)).height,
        greaterThan(FormMetrics.rowMinHeight),
      );
    });

    testWidgets('a labelled chip row keeps the label and the chips on one '
        'line while they fit', (tester) async {
      // The test font draws every glyph 15 px wide, so the phone width that
      // fits "Presence" beside two chips on a device is 600 here.
      await tester.pumpWidget(
        page(
          FormChipRow(
            glyph: Icons.how_to_reg_outlined,
            label: 'Presence',
            chips: [
              FormChip(label: 'Present', selected: true, onTap: () {}),
              FormChip(label: 'Missed', selected: false, onTap: () {}),
            ],
          ),
          width: 600,
        ),
      );
      final label = tester.getCenter(find.text('Presence'));
      final chip = tester.getCenter(find.text('Missed'));
      expect(chip.dy, moreOrLessEquals(label.dy, epsilon: 1));
      expect(chip.dx, greaterThan(label.dx));
      for (final chipFinder in [
        find.text('Present'),
        find.text('Missed'),
      ]) {
        expect(
          tester
              .getSize(
                find.ancestor(of: chipFinder, matching: find.byType(FormChip)),
              )
              .height,
          FormMetrics.chipTapTarget,
        );
      }
      expect(
        tester.getSize(find.byType(FormChipRow)).height,
        FormMetrics.rowMinHeight,
      );
    });

    testWidgets('a labelled chip row drops the chips under a long label on '
        'a narrow phone and keeps their 48 dp targets', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpWidget(
        page(
          FormChipRow(
            glyph: Icons.how_to_reg_outlined,
            label: 'Anwesenheit an diesem einen Tag der Woche',
            chips: [
              FormChip(label: 'Anwesend', selected: true, onTap: () {}),
              FormChip(label: 'Verpasst', selected: false, onTap: () {}),
            ],
            caption: const FormCaption(text: '12/14 wahrgenommen'),
          ),
          width: 360,
        ),
      );
      expect(tester.takeException(), isNull);
      final labelBottom = tester
          .getBottomLeft(find.text('Anwesenheit an diesem einen Tag der Woche'))
          .dy;
      final chipTop = tester.getTopLeft(find.text('Anwesend')).dy;
      expect(chipTop, greaterThan(labelBottom));
      expect(
        tester.getSize(find.byType(FormChip).first).height,
        FormMetrics.chipTapTarget,
      );
      expect(
        tester.getTopLeft(find.text('12/14 wahrgenommen')).dx,
        tester
            .getTopLeft(find.text('Anwesenheit an diesem einen Tag der Woche'))
            .dx,
      );
    });

    testWidgets("a chip's id lands on the chip's own node", (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        page(
          FormChipRow(
            chips: [
              FormChip(
                label: 'Present',
                selected: true,
                identifier: 'event-detail-present',
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      );
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('event-detail-present'))
          .getSemanticsData();
      expect(data.identifier, 'event-detail-present');
      expect(data.label, 'Present');
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.bySemanticsIdentifier('event-detail-present'));
      expect(taps, 1);
    });
  });

  group('check, search and menu rows', () {
    SemanticsData dataOf(WidgetTester tester, String id) =>
        tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

    testWidgets('a section label writes ß as SS in capitals', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FormSectionLabel(text: 'Außerdem anzeigen')),
        ),
      );
      expect(find.text('AUSSERDEM ANZEIGEN'), findsOneWidget);
    });

    testWidgets('a check row is one node with its checked state and id, and '
        'toggles from the id', (tester) async {
      bool? received;
      await tester.pumpWidget(
        host(
          FormCheckRow(
            glyph: Icons.checklist_rounded,
            label: 'Tracked',
            checked: false,
            identifier: 'filter-list-tracked',
            onChanged: (v) => received = v,
          ),
        ),
      );
      final data = dataOf(tester, 'filter-list-tracked');
      expect(data.identifier, 'filter-list-tracked');
      expect(data.label, contains('Tracked'));
      expect(data.flagsCollection.isChecked, CheckedState.isFalse);
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.byType(Checkbox), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier('filter-list-tracked'));
      expect(received, isTrue);
    });

    testWidgets('a check row is 48, 62 or 56 tall by shape', (tester) async {
      await tester.pumpWidget(
        host(
          FormCheckRow(
            glyph: Icons.flag_outlined,
            label: 'High',
            checked: true,
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(FormCheckRow)).height,
        FormMetrics.rowMinHeight,
      );
      await tester.pumpWidget(
        host(
          FormCheckRow(
            label: 'Top priority',
            caption: 'Highest, High',
            checked: true,
            exclusive: true,
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(FormCheckRow)).height,
        FormMetrics.twoLineRowMinHeight,
      );
      await tester.pumpWidget(
        host(
          FormCheckRow(
            leading: const EventAvatar(
              icon: Icons.fitness_center,
              color: Colors.blue,
            ),
            label: 'Gym',
            checked: false,
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(FormCheckRow)).height,
        FormMetrics.titleRowMinHeight,
      );
      expect(
        tester.getTopLeft(find.text('Gym')).dx,
        RowMetrics.groupInset + EventAvatar.radius * 2 + FormMetrics.gap,
      );
    });

    testWidgets('a disabled check row is faded and inert', (tester) async {
      await tester.pumpWidget(
        host(
          const FormCheckRow(
            glyph: Icons.no_food_rounded,
            label: 'Fasting',
            checked: true,
            identifier: 'filter-fasting-row',
            onChanged: null,
          ),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(FormCheckRow),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, FormMetrics.disabledOpacity);
      final data = dataOf(tester, 'filter-fasting-row');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
    });

    testWidgets('an exclusive check row is a radio node with the check glyph', (
      tester,
    ) async {
      var picks = 0;
      await tester.pumpWidget(
        host(
          FormCheckRow(
            label: 'No filter',
            checked: true,
            exclusive: true,
            identifier: 'filter-preset-none',
            onChanged: (_) => picks++,
          ),
        ),
      );
      final data = dataOf(tester, 'filter-preset-none');
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.bySemanticsIdentifier('filter-preset-none'));
      expect(picks, 1);

      await tester.pumpWidget(
        host(
          FormCheckRow(
            label: 'No filter',
            checked: false,
            exclusive: true,
            identifier: 'filter-preset-none',
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(
        dataOf(tester, 'filter-preset-none').flagsCollection.isChecked,
        CheckedState.isFalse,
      );
    });

    testWidgets("a check row's trailing button is its own node beside the "
        "row's", (tester) async {
      var picks = 0;
      var menus = 0;
      await tester.pumpWidget(
        host(
          FormCheckRow(
            label: 'Top priority',
            caption: 'Highest, High',
            checked: false,
            exclusive: true,
            identifier: 'filter-preset-p1',
            onChanged: (_) => picks++,
            trailingButton: FormTrailingButton(
              icon: Icons.more_vert_rounded,
              tooltip: 'Saved filter options',
              identifier: 'filter-preset-options-p1',
              onPressed: () => menus++,
            ),
          ),
        ),
      );
      final row = dataOf(tester, 'filter-preset-p1');
      expect(row.label, contains('Top priority'));
      expect(row.label, contains('Highest, High'));
      expect(row.label, isNot(contains('Saved filter options')));
      // An icon button's words are its tooltip, not a label.
      final button = dataOf(tester, 'filter-preset-options-p1');
      expect(button.tooltip, 'Saved filter options');
      expect(
        tester.getSize(find.byTooltip('Saved filter options')),
        const Size(FormMetrics.trailingButtonSize, FormMetrics.trailingButtonSize),
      );
      await tester.tap(find.bySemanticsIdentifier('filter-preset-options-p1'));
      expect(menus, 1);
      expect(picks, 0);
      await tester.tap(find.bySemanticsIdentifier('filter-preset-p1'));
      expect(picks, 1);
    });

    testWidgets("a check row's handle is a third node at the row's start, "
        'the text at the glyph column', (tester) async {
      var picks = 0;
      await tester.pumpWidget(
        host(
          FormCheckRow(
            label: 'Top priority',
            caption: 'Highest, High',
            checked: false,
            exclusive: true,
            identifier: 'filter-preset-p1',
            onChanged: (_) => picks++,
            handle: const FormDragHandle(
              label: 'Drag to reorder',
              identifier: 'filter-preset-handle-p1',
            ),
            trailingButton: FormTrailingButton(
              icon: Icons.more_vert_rounded,
              tooltip: 'Saved filter options',
              identifier: 'filter-preset-options-p1',
              onPressed: () {},
            ),
          ),
        ),
      );
      final handle = dataOf(tester, 'filter-preset-handle-p1');
      expect(handle.label, 'Drag to reorder');
      final row = dataOf(tester, 'filter-preset-p1');
      expect(row.label, isNot(contains('Drag to reorder')));
      expect(dataOf(tester, 'filter-preset-options-p1').tooltip,
          'Saved filter options');
      // The 48 dp slot leads the row; the text sits where a glyph row's
      // text does, so the rows above and below line up with the names.
      final slot = find.byType(FormDragHandle);
      expect(
        tester.getSize(slot),
        const Size(FormMetrics.dragHandleSlot, FormMetrics.dragHandleSlot),
      );
      expect(
        tester.getTopLeft(slot).dx,
        tester.getTopLeft(find.byType(FormCheckRow)).dx,
      );
      expect(
        tester.getTopLeft(find.text('Top priority')).dx,
        tester.getTopLeft(find.byType(FormCheckRow)).dx +
            FormMetrics.dividerIndentGlyph,
      );
      expect(
        tester.getSize(find.byType(FormCheckRow)).height,
        FormMetrics.twoLineRowMinHeight,
      );
      expect(
        tester.widget<FormCheckRow>(find.byType(FormCheckRow)).dividerIndent,
        FormMetrics.dividerIndentGlyph,
      );
      // A tap on the handle is not a pick.
      await tester.tap(find.bySemanticsIdentifier('filter-preset-handle-p1'));
      expect(picks, 0);
      await tester.tap(find.bySemanticsIdentifier('filter-preset-p1'));
      expect(picks, 1);
    });

    testWidgets('a locked handle greys in place and drags nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Row(
            children: [
              FormDragHandle(
                index: 0,
                enabled: false,
                label: 'Drag to reorder',
                identifier: 'filter-preset-handle-p1',
              ),
            ],
          ),
        ),
      );
      // Still there, still 48 dp: the row keeps its shape while a search
      // locks the list.
      expect(
        tester.getSize(find.byType(FormDragHandle)),
        const Size(FormMetrics.dragHandleSlot, FormMetrics.dragHandleSlot),
      );
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(find.byIcon(Icons.drag_handle), findsOneWidget);
      expect(dataOf(tester, 'filter-preset-handle-p1').label,
          'Drag to reorder');
    });

    testWidgets('a row shell rounds the ends only and draws a hairline under '
        'every row but the last', (tester) async {
      Widget shells({required bool trailingGap}) => MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 3; i++)
                FormRowShell(
                  first: i == 0,
                  last: i == 2,
                  trailingGap: trailingGap,
                  child: FormCheckRow(
                    label: 'Row $i',
                    checked: false,
                    exclusive: true,
                    onChanged: (_) {},
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(shells(trailingGap: false));
      final materials = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(FormRowShell),
              matching: find.byType(Material),
            ),
          )
          .where((m) => m.type == MaterialType.card)
          .toList();
      expect(materials, hasLength(2), reason: 'only the ends are clipped');
      final radius = Radius.circular(RowMetrics.groupRadius);
      expect(
        materials.first.borderRadius,
        BorderRadius.vertical(top: radius),
      );
      expect(
        materials.last.borderRadius,
        BorderRadius.vertical(bottom: radius),
      );
      expect(find.byType(Divider), findsNWidgets(2));
      // The hairline sits at the child's own indent, as in a group.
      final divider = tester.widget<Divider>(find.byType(Divider).first);
      expect(divider.indent, FormMetrics.dividerIndentPlain);
      // Three shells, no air between them, none below the last.
      final tops = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(find.text('Row $i')).dy,
      ];
      expect(tops[1] - tops[0], FormMetrics.rowMinHeight + 1);
      expect(tops[2] - tops[1], FormMetrics.rowMinHeight + 1);
      expect(
        tester.getSize(find.byType(FormRowShell).last).height,
        FormMetrics.rowMinHeight,
      );

      await tester.pumpWidget(shells(trailingGap: true));
      expect(
        tester.getSize(find.byType(FormRowShell).last).height,
        FormMetrics.rowMinHeight + RowMetrics.groupGap,
      );
    });

    testWidgets("a search row's field carries its id and its clear button is "
        'a second node that empties it', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        host(
          FormSearchRow(
            controller: controller,
            hint: 'Search categories',
            clearTooltip: 'Clear search',
            identifier: 'category-pick-search',
            onChanged: changes.add,
          ),
        ),
      );
      expect(
        dataOf(tester, 'category-pick-search').flagsCollection.isTextField,
        isTrue,
      );
      expect(find.byTooltip('Clear search'), findsNothing);
      final fieldWidth = tester.getSize(find.byType(TextField)).width;

      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pump();

      expect(changes, ['gym']);
      expect(find.byTooltip('Clear search'), findsOneWidget);
      expect(tester.getSize(find.byType(TextField)).width, fieldWidth);
      expect(
        dataOf(tester, 'category-pick-search').label,
        isNot(contains('Clear search')),
      );

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(changes.last, '');
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets("a tap at the search row's top or bottom edge focuses the "
        'field, and a tap outside unfocuses it', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          FormSearchRow(
            controller: controller,
            hint: 'Search categories',
            clearTooltip: 'Clear search',
            onChanged: (_) {},
          ),
        ),
      );
      final rect = tester.getRect(find.byType(FormSearchRow));
      expect(rect.height, FormMetrics.rowMinHeight);
      FocusNode node() =>
          tester.widget<EditableText>(find.byType(EditableText)).focusNode;

      await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
      await tester.pump();
      expect(node().hasFocus, isTrue);

      // Below the group: the pointer lands on nothing, and the field still
      // hears it through its tap region.
      await tester.tapAt(Offset(rect.center.dx, rect.bottom + 120));
      await tester.pump();
      expect(node().hasFocus, isFalse);

      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
      await tester.pump();
      expect(node().hasFocus, isTrue);
    });

    testWidgets("a check row's caption clamps at two lines at 200 %", (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      const caption =
          'Mit Anwesenheit · Verpasst · Wiederkehrend · Mit Geld · '
          'Mit Beschreibung · Gezählt · Nicht beendet';
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: FormRowGroup(
              children: [
                FormCheckRow(
                  label: 'Verpasste Einheiten',
                  caption: caption,
                  checked: false,
                  exclusive: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text(caption));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      // Two 36 px lines, not the four the words would need.
      expect(
        tester.getSize(find.text(caption)).height,
        lessThanOrEqualTo(2 * 18 * 2.0 + 1),
      );
    });

    testWidgets('a search row never autofocuses', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          FormSearchRow(
            controller: controller,
            hint: 'Search',
            clearTooltip: 'Clear search',
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isFalse,
      );
    });

    FormMenuRow<int> repeatRow({ValueChanged<int>? onSelected}) =>
        FormMenuRow<int>(
          glyph: Icons.repeat_rounded,
          label: 'Repeat',
          value: 'Recurring',
          selected: 2,
          identifier: 'filter-repeat',
          menuWidth: 220,
          items: const [
            FormMenuItem(value: 1, label: 'All', identifier: 'filter-repeat-all'),
            FormMenuItem(
              value: 2,
              label: 'Recurring',
              icon: Icons.repeat_rounded,
              identifier: 'filter-repeat-recurring',
            ),
          ],
          onSelected: onSelected ?? (_) {},
        );

    /// A group inset from the screen edges as a sheet's is, so the menu's
    /// right edge has somewhere to align to short of the screen.
    Widget sheetLike(Widget row, {Alignment alignment = Alignment.topCenter}) =>
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RowMetrics.groupInset,
                ),
                child: FormRowGroup(children: [row]),
              ),
            ),
          ),
        );

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.bySemanticsIdentifier('filter-repeat'));
      await tester.pumpAndSettle();
    }

    testWidgets("a menu row's items are radio nodes with ids and the current "
        'one checked', (tester) async {
      int? picked;
      await tester.pumpWidget(sheetLike(repeatRow(onSelected: (v) => picked = v)));
      await openMenu(tester);

      final current = dataOf(tester, 'filter-repeat-recurring');
      expect(current.role, SemanticsRole.menuItemRadio);
      expect(current.flagsCollection.isChecked, CheckedState.isTrue);
      expect(current.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(current.label, contains('Recurring'));
      final other = dataOf(tester, 'filter-repeat-all');
      expect(other.role, SemanticsRole.menuItemRadio);
      expect(other.flagsCollection.isChecked, CheckedState.isFalse);
      expect(
        find.descendant(
          of: find.byType(FormMenuChoiceItem<int>),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsIdentifier('filter-repeat-all'));
      await tester.pumpAndSettle();

      expect(picked, 1);
      expect(find.byType(FormMenuChoiceItem<int>), findsNothing);
    });

    testWidgets('the menu opens right-aligned with the group, under the row '
        'while there is room', (tester) async {
      await tester.pumpWidget(sheetLike(repeatRow()));
      final rowRect = tester.getRect(find.byType(FormPickerRow));
      final groupRect = tester.getRect(find.byType(FormRowGroup));
      await openMenu(tester);

      final items = find.byType(FormMenuChoiceItem<int>);
      final first = tester.getRect(items.first);
      // The popup sizes to its labels in 56 px steps between the floor and
      // the cap; the test font's 15 px glyphs put "Recurring" just past 220.
      expect(first.width, inInclusiveRange(220, FormMetrics.menuMaxWidth));
      expect(first.right, moreOrLessEquals(groupRect.right, epsilon: 0.5));
      expect(
        first.top,
        moreOrLessEquals(rowRect.bottom + FormMetrics.menuPadding.top,
            epsilon: 0.5),
      );
      expect(first.height, FormMetrics.menuRowHeight);
    });

    testWidgets('a long label widens the menu past menuWidth up to the cap, '
        'still on the group\'s right edge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RowMetrics.groupInset,
              ),
              child: FormRowGroup(
                children: [
                  FormMenuRow<int>(
                    glyph: Icons.repeat_rounded,
                    label: 'Wiederholung',
                    value: 'Alle',
                    selected: 1,
                    identifier: 'filter-repeat',
                    menuWidth: 220,
                    items: const [
                      FormMenuItem(value: 1, label: 'Alle'),
                      FormMenuItem(
                        value: 2,
                        label: 'Wiederkehrend',
                        icon: Icons.repeat_rounded,
                      ),
                    ],
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final groupRect = tester.getRect(find.byType(FormRowGroup));
      await openMenu(tester);

      // The test font's 30 px glyphs push the label past even the cap, so
      // what this pins is the widening itself and the edge it keeps; that
      // Roboto then fits the word on one line is the device pass's fact.
      final item = tester.getRect(find.byType(FormMenuChoiceItem<int>).first);
      expect(item.width, FormMetrics.menuMaxWidth);
      expect(item.right, moreOrLessEquals(groupRect.right, epsilon: 0.5));
    });

    testWidgets('the menu opens above the row when there is no room below', (
      tester,
    ) async {
      await tester.pumpWidget(
        sheetLike(repeatRow(), alignment: Alignment.bottomCenter),
      );
      final rowRect = tester.getRect(find.byType(FormPickerRow));
      await openMenu(tester);

      final last = tester.getRect(find.byType(FormMenuChoiceItem<int>).last);
      expect(
        last.bottom + FormMetrics.menuPadding.bottom,
        lessThanOrEqualTo(rowRect.top + 0.5),
      );
    });

    testWidgets('a menu row drops focus before it opens', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focusNode),
                FormRowGroup(children: [repeatRow()]),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await openMenu(tester);
      // The route holds focus while open, so the check runs once it is gone:
      // a focus dropped only by the push would come back with the pop.
      await tester.tapAt(const Offset(5, 590));
      await tester.pumpAndSettle();

      expect(find.byType(FormMenuChoiceItem<int>), findsNothing);
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('a disabled menu row is faded, inert and not enabled, and '
        'opens nothing', (tester) async {
      await tester.pumpWidget(
        sheetLike(
          FormMenuRow<int>(
            glyph: Icons.no_food_rounded,
            label: 'Fasting rows',
            value: 'Periods',
            selected: 2,
            identifier: 'agenda-filter-fasting-rows',
            menuWidth: 220,
            items: const [
              FormMenuItem(
                value: 1,
                label: 'Every day',
                identifier: 'agenda-filter-fasting-rows-every-day',
              ),
              FormMenuItem(
                value: 2,
                label: 'Periods',
                identifier: 'agenda-filter-fasting-rows-periods',
              ),
            ],
            onSelected: null,
          ),
        ),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(FormMenuRow<int>),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, FormMetrics.disabledOpacity);
      final well = tester.widget<InkWell>(
        find.descendant(
          of: find.byType(FormMenuRow<int>),
          matching: find.byType(InkWell),
        ),
      );
      expect(well.onTap, isNull);
      final data = dataOf(tester, 'agenda-filter-fasting-rows');
      expect(data.label, contains('Fasting rows'));
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(
        find.bySemanticsIdentifier('agenda-filter-fasting-rows'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FormMenuChoiceItem<int>), findsNothing);
      expect(find.text('Every day'), findsNothing);
    });
  });

  group('form sheet frame', () {
    var leaves = 0;
    var dismisses = 0;
    var clean = true;

    setUp(() {
      leaves = 0;
      dismisses = 0;
      clean = true;
    });

    /// The editor's route, shape for shape: the frame inside the fixed box,
    /// on a transparent route that does not drag itself.
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: false,
                  enableDrag: false,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  builder: (sheetContext) => FractionallySizedBox(
                    heightFactor: FormMetrics.sheetHeightFactor,
                    child: FormSheetFrame(
                      onLeave: () async {
                        leaves++;
                      },
                      isClean: () => clean,
                      onDismiss: () {
                        dismisses++;
                        Navigator.of(sheetContext).pop();
                      },
                      chrome: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FormSheetHandle(),
                          FormSheetHeader(
                            leadingIcon: Icons.close_rounded,
                            leadingTooltip: 'Cancel',
                            onLeading: () {},
                            title: 'Add event',
                            trailing: const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      body: const [Expanded(child: SizedBox.expand())],
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(FormSheetFrame), findsOneWidget);
    }

    testWidgets('a fling on the chrome pops a clean sheet through onDismiss', (
      tester,
    ) async {
      await open(tester);
      await tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      );
      await tester.pumpAndSettle();

      expect(dismisses, 1);
      expect(leaves, 0);
      expect(find.byType(FormSheetFrame), findsNothing);
    });

    testWidgets('a fling on a dirty sheet snaps back and asks once through '
        'onLeave', (tester) async {
      clean = false;
      await open(tester);
      final before = tester.getTopLeft(find.byType(FormSheetHandle));
      await tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      );
      await tester.pumpAndSettle();

      expect(leaves, 1);
      expect(dismisses, 0);
      expect(find.byType(FormSheetFrame), findsOneWidget);
      expect(tester.getTopLeft(find.byType(FormSheetHandle)), before);
    });

    testWidgets('a short drag snaps back and calls nothing', (tester) async {
      clean = false;
      await open(tester);
      final before = tester.getTopLeft(find.byType(FormSheetHandle));
      await tester.timedDrag(
        find.byType(FormSheetHandle),
        const Offset(0, 40),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();

      expect(leaves, 0);
      expect(dismisses, 0);
      expect(find.byType(FormSheetFrame), findsOneWidget);
      expect(tester.getTopLeft(find.byType(FormSheetHandle)), before);
    });

    testWidgets('the system back gesture asks through onLeave and the route '
        'stays', (tester) async {
      clean = false;
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(leaves, 1);
      expect(dismisses, 0);
      expect(find.byType(FormSheetFrame), findsOneWidget);
    });

    testWidgets('the barrier asks through onLeave and the route stays', (
      tester,
    ) async {
      clean = false;
      await open(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(leaves, 1);
      expect(dismisses, 0);
      expect(find.byType(FormSheetFrame), findsOneWidget);
    });
  });
}
