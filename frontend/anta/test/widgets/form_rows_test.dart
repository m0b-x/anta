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
}
