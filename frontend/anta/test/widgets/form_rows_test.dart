import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
