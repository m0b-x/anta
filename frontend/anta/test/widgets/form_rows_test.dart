import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/value_change_highlight.dart';

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

    testWidgets("a glyph row's caption clamps at captionMaxLines with an "
        'ellipsis, and wraps freely without it', (tester) async {
      const long =
          'Keep it light and simple, fish on the weekends, no meat on '
          'Wednesdays and Fridays, oil and wine only on the feast days of the '
          'period, and nothing at all on the strict days before the great '
          'feast at the end';
      Widget row({int? maxLines}) => FormPickerRow(
        glyph: Icons.notes_rounded,
        label: 'Description',
        caption: long,
        captionMaxLines: maxLines,
        onTap: () {},
      );
      await tester.pumpWidget(page(row(maxLines: FormMetrics.valueMaxLines)));
      final clamped = tester.widget<Text>(find.text(long));
      expect(clamped.maxLines, FormMetrics.valueMaxLines);
      expect(clamped.overflow, TextOverflow.ellipsis);
      expect(
        tester.renderObject<RenderParagraph>(find.text(long)).didExceedMaxLines,
        isTrue,
      );
      final clampedHeight = tester.getSize(find.byType(FormPickerRow)).height;

      await tester.pumpWidget(page(row()));
      final free = tester.widget<Text>(find.text(long));
      expect(free.maxLines, isNull);
      expect(
        tester.renderObject<RenderParagraph>(find.text(long)).didExceedMaxLines,
        isFalse,
      );
      expect(
        tester.getSize(find.byType(FormPickerRow)).height,
        greaterThan(clampedHeight),
        reason: 'unclamped, the caption takes every line it needs',
      );
    });

    testWidgets('a value dot is a circle of the value-dot size in its colour, '
        'before the value and out of the row\'s announcement', (tester) async {
      const color = Color(0xFF2E7D32);
      await tester.pumpWidget(
        page(
          FormPickerRow(
            glyph: Icons.palette_outlined,
            label: 'Icon & color',
            value: 'Custom',
            valueLeading: const FormValueDot(color: color),
            identifier: 'event-look',
            onTap: () {},
          ),
        ),
      );
      final dot = find.byType(FormValueDot);
      expect(tester.getSize(dot), const Size.square(FormMetrics.valueDotSize));
      // The browser's label dot, so a colour dot is one size everywhere.
      expect(FormMetrics.valueDotSize, RowMetrics.labelDotSize);
      final decoration =
          tester
                  .widget<Container>(
                    find.descendant(of: dot, matching: find.byType(Container)),
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.color, color);
      expect(decoration.shape, BoxShape.circle);
      // Before the value on the value's own line, and nothing a screen
      // reader stops on: the row still reads its label and its value.
      final value = tester.getRect(find.text('Custom'));
      final rect = tester.getRect(dot);
      expect(rect.right, lessThan(value.left));
      expect(rect.center.dy, moreOrLessEquals(value.center.dy, epsilon: 0.01));
      final data = tester
          .getSemantics(find.bySemanticsIdentifier('event-look'))
          .getSemanticsData();
      expect(data.label, 'Icon & color\nCustom');
      expect(
        find.descendant(of: dot, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
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

    List<Widget> unitChips() => [
      FormChip(label: 'Minuten', selected: true, onTap: () {}),
      FormChip(label: 'Stunden', selected: false, onTap: () {}),
      FormChip(label: 'Tage', selected: false, onTap: () {}),
    ];

    testWidgets('a chip row under a switch is set in at the sub-row inset '
        'with its own air, the hairline from the glyph column', (tester) async {
      // The shape every chip row had before `indented` existed, and the one
      // it still has when nothing is said.
      final row = FormChipRow(chips: unitChips());
      await tester.pumpWidget(page(row, width: 600));

      expect(row.indented, isTrue);
      final rowRect = tester.getRect(find.byType(FormChipRow));
      final first = tester.getRect(find.byType(FormChip).first);
      expect(first.left - rowRect.left, FormMetrics.subRowInset);
      expect(first.top - rowRect.top, FormMetrics.chipRowPadding.top);
      expect(
        rowRect.height,
        FormMetrics.chipTapTarget + FormMetrics.chipRowPadding.vertical,
      );
      expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentGlyph);
    });

    testWidgets('a standalone chip row starts at the group inset, is one '
        '48 dp row and draws a plain hairline', (tester) async {
      final row = FormChipRow(indented: false, chips: unitChips());
      await tester.pumpWidget(page(row, width: 600));

      final rowRect = tester.getRect(find.byType(FormChipRow));
      expect(rowRect.height, FormMetrics.rowMinHeight);
      final chips = [
        for (final chip in find.byType(FormChip).evaluate())
          tester.getRect(find.byWidget(chip.widget)),
      ];
      expect(chips.first.left - rowRect.left, RowMetrics.groupInset);
      for (final chip in chips) {
        // No air of the row's own: a chip's 48 dp target is the row.
        expect(chip.top, rowRect.top);
        expect(chip.height, FormMetrics.chipTapTarget);
      }
      expect(chips[1].left - chips[0].right, FormMetrics.chipSpacing);
      expect(chips[2].left - chips[1].right, FormMetrics.chipSpacing);
      expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentPlain);
    });

    testWidgets('a standalone chip row wraps to whole 48 dp runs short of '
        "the row's end, its caption from the group inset", (tester) async {
      await tester.pumpWidget(
        page(
          FormChipRow(
            indented: false,
            chips: unitChips(),
            caption: const FormCaption(text: '45 Min. vorher'),
          ),
          width: 300,
        ),
      );

      expect(tester.takeException(), isNull);
      final rowRect = tester.getRect(find.byType(FormChipRow));
      final chips = [
        for (final chip in find.byType(FormChip).evaluate())
          tester.getRect(find.byWidget(chip.widget)),
      ];
      // Two fit the first run, the third starts the second at the same inset.
      expect(chips[1].top, rowRect.top);
      expect(chips[2].top, rowRect.top + FormMetrics.chipTapTarget);
      expect(chips[2].left, chips[0].left);
      for (final chip in chips) {
        expect(
          chip.right,
          lessThanOrEqualTo(rowRect.right - FormMetrics.rowEndPadding),
        );
      }
      final caption = tester.getRect(find.text('45 Min. vorher'));
      expect(caption.left - rowRect.left, RowMetrics.groupInset);
      expect(caption.top, rowRect.top + 2 * FormMetrics.chipTapTarget);
      expect(
        rowRect.bottom - caption.bottom,
        FormMetrics.rowCaptionBottomPadding,
      );
    });

    testWidgets('a labelled chip row is the same row whatever indented says', (
      tester,
    ) async {
      FormChipRow labelled({required bool indented}) => FormChipRow(
        glyph: Icons.notifications_outlined,
        label: 'Type',
        indented: indented,
        chips: [
          FormChip(label: 'Reminder', selected: true, onTap: () {}),
          FormChip(label: 'Alarm', selected: false, onTap: () {}),
        ],
        caption: const FormCaption(text: 'Sits in the shade.'),
      );
      Map<String, Rect> rects() => {
        for (final text in ['Type', 'Reminder', 'Alarm', 'Sits in the shade.'])
          text: tester.getRect(find.text(text)),
        'row': tester.getRect(find.byType(FormChipRow)),
      };

      await tester.pumpWidget(page(labelled(indented: true), width: 600));
      final indentedRects = rects();
      await tester.pumpWidget(page(labelled(indented: false), width: 600));

      expect(rects(), indentedRects);
      expect(
        FormRowGroup.indentOf(labelled(indented: false)),
        FormMetrics.dividerIndentGlyph,
      );
    });

    testWidgets('an indented row hands the group the hairline indent its '
        'child cannot, and draws nothing of its own', (tester) async {
      Widget group(Widget first) => MaterialApp(
        home: Scaffold(
          body: FormRowGroup(
            children: [
              first,
              FormPickerRow(label: 'Ends', value: 'None', onTap: () {}),
            ],
          ),
        ),
      );
      final highlighted = ValueChangeHighlight(
        value: 18 * 60,
        child: FormPickerRow(
          label: 'Starts',
          value: '18:00',
          dividerIndent: FormMetrics.dividerIndentPlain,
          onTap: () {},
        ),
      );
      Divider hairline() => tester.widget<Divider>(find.byType(Divider));

      // Bare, the group cannot see the row through the highlight and falls
      // back to the glyph indent, whatever the row inside says.
      await tester.pumpWidget(group(highlighted));
      expect(hairline().indent, FormMetrics.dividerIndentGlyph);
      final bare = tester.getRect(find.byType(ValueChangeHighlight));

      final indented = FormIndentedRow(
        dividerIndent: FormMetrics.dividerIndentPlain,
        child: highlighted,
      );
      await tester.pumpWidget(group(indented));
      expect(hairline().indent, FormMetrics.dividerIndentPlain);
      expect(FormRowGroup.indentOf(indented), FormMetrics.dividerIndentPlain);
      expect(tester.getRect(find.byType(ValueChangeHighlight)), bare);
      expect(tester.getRect(find.byType(FormIndentedRow)), bare);
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

    testWidgets('a section label carries a trailing count in its own '
        'capitals at the row\'s end, on the same line, in one node', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FormSectionLabel(text: 'Deine Farben', trailing: '24 of 24'),
              ],
            ),
          ),
        ),
      );
      final label = find.text('DEINE FARBEN');
      final count = find.text('24 OF 24');
      expect(label, findsOneWidget);
      expect(count, findsOneWidget);
      expect(tester.getTopLeft(count).dy, tester.getTopLeft(label).dy);
      expect(
        tester.getRect(count).right,
        tester.getRect(find.byType(FormSectionLabel)).right -
            RowMetrics.sectionLabelInset,
      );
      final labelStyle = tester.widget<Text>(label).style!;
      final countStyle = tester.widget<Text>(count).style!;
      expect(countStyle.fontSize, labelStyle.fontSize);
      expect(countStyle.letterSpacing, labelStyle.letterSpacing);
      expect(countStyle.color, labelStyle.color);
      // One node: the section and its count are one line to a screen
      // reader.
      final node = tester.getSemantics(label);
      expect(node.id, tester.getSemantics(count).id);
      expect(node.label, contains('DEINE FARBEN'));
      expect(node.label, contains('24 OF 24'));
    });

    testWidgets('a section label with a count wraps its own text rather '
        'than pushing the count off the line', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: FormSectionLabel(
                    text: 'A long section label that wraps',
                    trailing: '24 of 24',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final label = find.text('A LONG SECTION LABEL THAT WRAPS');
      final count = find.text('24 OF 24');
      final oneLine = tester.getSize(count).height;
      expect(tester.getSize(label).height, greaterThan(oneLine));
      expect(tester.getTopLeft(count).dy, tester.getTopLeft(label).dy);
      expect(
        tester.getRect(count).right,
        tester.getRect(find.byType(FormSectionLabel)).right -
            RowMetrics.sectionLabelInset,
      );
      expect(tester.getRect(label).right, lessThan(tester.getRect(count).left));
    });

    testWidgets('a swatch row is a container node over its dots, at the '
        'plain indent, with the strip\'s own air', (tester) async {
      await tester.pumpWidget(
        host(
          FormSwatchRow(
            identifier: 'swatch-row',
            child: Row(
              key: const Key('strip'),
              children: [
                for (var i = 0; i < 3; i++)
                  Semantics(
                    button: true,
                    label: 'dot $i',
                    child: SizedBox.square(
                      dimension: FormMetrics.trailingButtonSize,
                      child: InkWell(onTap: () {}),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final rowFinder = find.byType(FormSwatchRow);
      expect(
        tester.widget<FormSwatchRow>(rowFinder).dividerIndent,
        FormMetrics.dividerIndentPlain,
      );
      // Three dots stay three nodes under the row's: never a merge.
      final node = tester.getSemantics(find.bySemanticsIdentifier('swatch-row'));
      expect(node.childrenCount, 3);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('dot 1'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      final row = tester.getRect(rowFinder);
      final strip = tester.getRect(find.byKey(const Key('strip')));
      expect(strip.left, row.left + RowMetrics.groupInset);
      expect(strip.right, row.right - RowMetrics.groupInset);
      expect(strip.top, row.top + FormMetrics.swatchRowTopPadding);
      expect(strip.bottom, row.bottom - FormMetrics.swatchRowBottomPadding);
      // The Look sheet's height for one run of dots.
      expect(
        row.height,
        FormMetrics.swatchRowTopPadding +
            FormMetrics.trailingButtonSize +
            FormMetrics.swatchRowBottomPadding,
      );
    });

    testWidgets('a swatch row without an identifier adds no node of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FormSwatchRow(
            child: Semantics(
              button: true,
              label: 'dot',
              child: SizedBox.square(
                dimension: FormMetrics.trailingButtonSize,
                child: InkWell(onTap: () {}),
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('swatch-row'), findsNothing);
      expect(find.bySemanticsLabel('dot'), findsOneWidget);
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

    testWidgets("a picker row's handle is a third node at the row's start, "
        'the text at the glyph column, the hairline with it', (tester) async {
      var taps = 0;
      var deletes = 0;
      await tester.pumpWidget(
        host(
          FormPickerRow(
            label: '#3F51B5',
            identifier: 'palette-row-3f51b5',
            showChevron: false,
            onTap: () => taps++,
            handle: const FormDragHandle(
              label: 'Drag to reorder',
              identifier: 'palette-handle-3f51b5',
            ),
            trailingButton: FormTrailingButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete color',
              identifier: 'palette-delete-3f51b5',
              onPressed: () => deletes++,
            ),
          ),
        ),
      );
      final handle = dataOf(tester, 'palette-handle-3f51b5');
      expect(handle.label, 'Drag to reorder');
      final row = dataOf(tester, 'palette-row-3f51b5');
      expect(row.label, contains('#3F51B5'));
      expect(row.label, isNot(contains('Drag to reorder')));
      expect(dataOf(tester, 'palette-delete-3f51b5').tooltip, 'Delete color');
      // The check row's geometry, mirrored: the 48 dp slot leads the row and
      // the text sits at the glyph column, where the hairline starts.
      final slot = find.byType(FormDragHandle);
      final rowFinder = find.byType(FormPickerRow);
      expect(
        tester.getSize(slot),
        const Size(FormMetrics.dragHandleSlot, FormMetrics.dragHandleSlot),
      );
      expect(tester.getTopLeft(slot).dx, tester.getTopLeft(rowFinder).dx);
      expect(
        tester.getTopLeft(find.text('#3F51B5')).dx,
        tester.getTopLeft(rowFinder).dx + FormMetrics.dividerIndentGlyph,
      );
      expect(tester.getSize(rowFinder).height, FormMetrics.rowMinHeight);
      expect(
        tester.widget<FormPickerRow>(rowFinder).dividerIndent,
        FormMetrics.dividerIndentGlyph,
      );
      final delete = find.bySemanticsIdentifier('palette-delete-3f51b5');
      expect(tester.getRect(delete).right, tester.getRect(rowFinder).right);
      // Three targets, each its own: the handle is not a tap, the delete is
      // not the row's.
      await tester.tap(find.bySemanticsIdentifier('palette-handle-3f51b5'));
      expect(taps, 0);
      await tester.tap(find.bySemanticsIdentifier('palette-row-3f51b5'));
      expect(taps, 1);
      await tester.tap(find.bySemanticsIdentifier('palette-delete-3f51b5'));
      expect((taps, deletes), (1, 1));
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

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

  /// A 360 × 780 phone at 200 % (or [textScale]), the group inset from the
  /// edges and free to grow downwards, as a sheet's scrolling body holds it.
  Future<void> pumpOnNarrowPhoneAtDouble(
    WidgetTester tester,
    Widget row, {
    double textScale = 2.0,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: RowMetrics.groupInset,
            ),
            child: FormRowGroup(children: [row]),
          ),
        ),
      ),
    );
  }

  group('stepper row', () {
    const less = 'alert-custom-less';
    const more = 'alert-custom-more';

    FormStepperRow stepper({
      String value = '45',
      VoidCallback? onDecrement,
      VoidCallback? onIncrement,
    }) => FormStepperRow(
      label: 'Minutes',
      value: value,
      decrementTooltip: 'Less time before',
      incrementTooltip: 'More time before',
      decrementIdentifier: less,
      incrementIdentifier: more,
      onDecrement: onDecrement,
      onIncrement: onIncrement,
    );

    testWidgets('each button carries its id and its tooltip and steps its own '
        'way', (tester) async {
      var value = 45;
      await tester.pumpWidget(
        host(stepper(onDecrement: () => value--, onIncrement: () => value++)),
      );
      final lessData = dataOf(tester, less);
      expect(lessData.identifier, less);
      expect(lessData.tooltip, 'Less time before');
      expect(lessData.hasAction(SemanticsAction.tap), isTrue);
      final moreData = dataOf(tester, more);
      expect(moreData.identifier, more);
      expect(moreData.tooltip, 'More time before');
      expect(moreData.hasAction(SemanticsAction.tap), isTrue);
      // The label and the value stay out of both buttons' nodes.
      expect(lessData.label, isEmpty);
      expect(moreData.label, isEmpty);
      expect(find.text('Minutes'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier(more));
      await tester.tap(find.bySemanticsIdentifier(more));
      expect(value, 47);
      await tester.tap(find.bySemanticsIdentifier(less));
      expect(value, 46);
    });

    testWidgets('each button is disabled on its own, in place', (tester) async {
      await tester.pumpWidget(
        host(stepper(onDecrement: () {}, onIncrement: () {})),
      );
      final lessRect = tester.getRect(find.byTooltip('Less time before'));
      final moreRect = tester.getRect(find.byTooltip('More time before'));

      Future<void> expectOnly(
        String enabledId, {
        required String disabledId,
      }) async {
        final disabled = dataOf(tester, disabledId);
        expect(disabled.hasAction(SemanticsAction.tap), isFalse);
        expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
        final enabled = dataOf(tester, enabledId);
        expect(enabled.hasAction(SemanticsAction.tap), isTrue);
        expect(enabled.flagsCollection.isEnabled, Tristate.isTrue);
        // Disabled, never hidden: both buttons are where they were.
        expect(tester.getRect(find.byTooltip('Less time before')), lessRect);
        expect(tester.getRect(find.byTooltip('More time before')), moreRect);
      }

      var steps = 0;
      await tester.pumpWidget(host(stepper(onIncrement: () => steps++)));
      await expectOnly(more, disabledId: less);
      await tester.tap(find.bySemanticsIdentifier(less), warnIfMissed: false);
      expect(steps, 0);
      await tester.tap(find.bySemanticsIdentifier(more));
      expect(steps, 1);

      await tester.pumpWidget(host(stepper(onDecrement: () => steps--)));
      await expectOnly(less, disabledId: more);
      await tester.tap(find.bySemanticsIdentifier(more), warnIfMissed: false);
      expect(steps, 1);
      await tester.tap(find.bySemanticsIdentifier(less));
      expect(steps, 0);
    });

    testWidgets('the row is 48 dp with a plain hairline, and the value box '
        'keeps the minus button still while the text changes', (tester) async {
      final row = stepper(
        value: '1 day',
        onDecrement: () {},
        onIncrement: () {},
      );
      await tester.pumpWidget(host(row));
      expect(
        tester.getSize(find.byType(FormStepperRow)).height,
        FormMetrics.rowMinHeight,
      );
      expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentPlain);
      expect(tester.getTopLeft(find.text('Minutes')).dx, RowMetrics.groupInset);
      const button = Size(
        FormMetrics.trailingButtonSize,
        FormMetrics.trailingButtonSize,
      );
      expect(tester.getSize(find.byTooltip('Less time before')), button);
      expect(tester.getSize(find.byTooltip('More time before')), button);
      final lessRect = tester.getRect(find.byTooltip('Less time before'));
      final moreRect = tester.getRect(find.byTooltip('More time before'));
      // "1 day" is narrower than the box, so the box is what parts the two.
      expect(moreRect.left - lessRect.right, FormMetrics.stepperValueMinWidth);
      final valueStyle = tester.widget<Text>(find.text('1 day')).style!;
      expect(valueStyle.fontSize, FormMetrics.labelSize);
      expect(valueStyle.fontWeight, FontWeight.w500);
      expect(valueStyle.fontFeatures, const [FontFeature.tabularFigures()]);

      await tester.pumpWidget(
        host(stepper(value: '9 days', onDecrement: () {}, onIncrement: () {})),
      );
      expect(tester.getRect(find.byTooltip('Less time before')), lessRect);
      expect(tester.getRect(find.byTooltip('More time before')), moreRect);
    });

    testWidgets('the value box is as wide as the widest value, laid out '
        'unseen, and the buttons stand still from the narrowest value to '
        'that one', (tester) async {
      FormStepperRow weeks(String value) => FormStepperRow(
        label: 'Repeat every',
        value: value,
        widestValue: '99 weeks',
        decrementTooltip: 'More frequent',
        incrementTooltip: 'Less frequent',
        onDecrement: () {},
        onIncrement: () {},
      );
      double box() =>
          tester.getRect(find.byTooltip('Less frequent')).left -
          tester.getRect(find.byTooltip('More frequent')).right;

      await tester.pumpWidget(host(weeks('1 week')));
      final lessRect = tester.getRect(find.byTooltip('More frequent'));
      final moreRect = tester.getRect(find.byTooltip('Less frequent'));
      final width = box();
      // Wider than the floor: "99 weeks" is, in the test font.
      expect(width, greaterThan(FormMetrics.stepperValueMinWidth));
      expect(find.text('99 weeks'), findsNothing);

      for (final value in ['12 weeks', '99 weeks', '1 week']) {
        await tester.pumpWidget(host(weeks(value)));
        expect(box(), width, reason: value);
        expect(
          tester.getRect(find.byTooltip('More frequent')),
          lessRect,
          reason: value,
        );
        expect(
          tester.getRect(find.byTooltip('Less frequent')),
          moreRect,
          reason: value,
        );
      }
    });

    testWidgets('at 200 % on a narrow phone a label that cannot sit beside '
        'the stepper whole drops it under itself, end-aligned, and nothing '
        'overflows', (tester) async {
      await pumpOnNarrowPhoneAtDouble(
        tester,
        FormStepperRow(
          label: 'Minuten',
          value: '45',
          widestValue: '59',
          decrementTooltip: 'Weniger Vorlauf',
          incrementTooltip: 'Mehr Vorlauf',
          onDecrement: () {},
          onIncrement: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      // "Minuten" is one word, wider at this scale than the stepper leaves
      // beside it: whole on its one line, with the stepper under it.
      final label = tester.getRect(find.text('Minuten'));
      expect(
        label.height,
        moreOrLessEquals(FormMetrics.labelLineHeight * 2.0, epsilon: 1),
      );
      final less = tester.getRect(find.byTooltip('Weniger Vorlauf'));
      final more = tester.getRect(find.byTooltip('Mehr Vorlauf'));
      expect(less.top, greaterThanOrEqualTo(label.bottom));
      expect(less.size, const Size.square(FormMetrics.trailingButtonSize));
      expect(more.size, const Size.square(FormMetrics.trailingButtonSize));
      expect(more.right, tester.getRect(find.byType(FormStepperRow)).right);
      expect(
        more.left - less.right,
        greaterThanOrEqualTo(FormMetrics.stepperValueMinWidth),
      );
      expect(
        tester.getSize(find.byType(FormStepperRow)).height,
        greaterThanOrEqualTo(label.height + FormMetrics.trailingButtonSize),
      );
    });

    testWidgets('at 100 % the same row keeps its stepper beside the label: '
        'the drop follows the scale, not the value', (tester) async {
      await pumpOnNarrowPhoneAtDouble(
        tester,
        FormStepperRow(
          label: 'Minuten',
          value: '45',
          widestValue: '59',
          decrementTooltip: 'Weniger Vorlauf',
          incrementTooltip: 'Mehr Vorlauf',
          onDecrement: () {},
          onIncrement: () {},
        ),
        textScale: 1.0,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FormStepperRow)).height,
        FormMetrics.rowMinHeight,
      );
      final label = tester.getRect(find.text('Minuten'));
      final less = tester.getRect(find.byTooltip('Weniger Vorlauf'));
      expect(less.top, lessThan(label.bottom));
      expect(less.left, greaterThanOrEqualTo(label.right));
    });
  });

  group('title row', () {
    FormTitleRow titleRow(
      TextEditingController controller, {
      bool autofocus = false,
      FocusNode? focusNode,
      TextCapitalization textCapitalization = TextCapitalization.none,
      ValueChanged<String>? onSubmitted,
      String? warning,
    }) => FormTitleRow(
      leading: const EventAvatar(
        icon: Icons.alarm_outlined,
        color: Colors.blue,
      ),
      controller: controller,
      focusNode: focusNode,
      hint: 'Template name',
      maxLength: 60,
      counterFrom: 50,
      counterLabel: (length, max) => '$length/$max',
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      onSubmitted: onSubmitted,
      identifier: 'template-name',
      warning: warning,
    );

    TextEditingController controllerOf([String text = '']) {
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('the row is 56 dp with the field at the title indent and the '
        'hairline under it', (tester) async {
      final row = titleRow(controllerOf());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormRowGroup(
              children: [
                row,
                FormPickerRow(label: 'Category', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(FormTitleRow));
      expect(rect.height, FormMetrics.titleRowMinHeight);
      expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentTitle);
      expect(
        tester.widget<Divider>(find.byType(Divider)).indent,
        FormMetrics.dividerIndentTitle,
      );
      // The avatar's 40 dp box sits at the group inset, the field one gap
      // past it — on the hairline's indent.
      final avatar = tester.getRect(find.byType(EventAvatar));
      expect(avatar.left, RowMetrics.groupInset);
      expect(avatar.size, const Size.square(FormMetrics.rowLeadingSize));
      final field = tester.getRect(find.byType(TextField));
      expect(field.left, FormMetrics.dividerIndentTitle);
      // One 26 px line, dropped so it centres on the avatar.
      expect(
        field.height,
        moreOrLessEquals(
          FormMetrics.titleFontSize * FormMetrics.titleLineHeight,
          epsilon: 0.01,
        ),
      );
      expect(
        field.center.dy,
        moreOrLessEquals(avatar.center.dy, epsilon: 0.01),
      );
      expect(find.text('Template name'), findsOneWidget);
    });

    testWidgets('the typed text is 20 / 500 and the hint 20 / 400', (
      tester,
    ) async {
      await tester.pumpWidget(host(titleRow(controllerOf())));
      final field = tester.widget<TextField>(find.byType(TextField));
      final colorScheme = Theme.of(
        tester.element(find.byType(TextField)),
      ).colorScheme;
      expect(field.style!.fontSize, FormMetrics.titleFontSize);
      expect(field.style!.fontWeight, FontWeight.w500);
      expect(field.style!.color, colorScheme.onSurface);
      final hint = field.decoration!.hintStyle!;
      expect(hint.fontSize, FormMetrics.titleFontSize);
      expect(hint.fontWeight, FontWeight.w400);
      // `onSurfaceVariant`, never `outline`: a hint is text.
      expect(hint.color, colorScheme.onSurfaceVariant);
    });

    testWidgets('the counter appears at counterFrom and turns to the error '
        'colour at the limit', (tester) async {
      await tester.pumpWidget(host(titleRow(controllerOf())));
      final colorScheme = Theme.of(
        tester.element(find.byType(TextField)),
      ).colorScheme;

      await tester.enterText(find.byType(TextField), 'a' * 49);
      await tester.pump();
      expect(find.text('49/60'), findsNothing);
      final withoutCounter = tester.getSize(find.byType(FormTitleRow)).height;

      await tester.enterText(find.byType(TextField), 'a' * 50);
      await tester.pump();
      final counter = tester.widget<Text>(find.text('50/60'));
      expect(counter.style!.color, colorScheme.onSurfaceVariant);
      expect(counter.style!.fontSize, FormMetrics.counterSize);
      expect(counter.textAlign, TextAlign.end);
      // The counter is a line under the field: it adds to the row rather
      // than taking room from the title.
      expect(
        tester.getSize(find.byType(FormTitleRow)).height,
        greaterThan(withoutCounter),
      );
      expect(
        tester.getTopLeft(find.text('50/60')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(TextField)).dy),
      );

      await tester.enterText(find.byType(TextField), 'a' * 59);
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('59/60')).style!.color,
        colorScheme.onSurfaceVariant,
      );

      await tester.enterText(find.byType(TextField), 'a' * 60);
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('60/60')).style!.color,
        colorScheme.error,
      );
    });

    testWidgets('a short title leaves the row at 56 dp, with no counter line', (
      tester,
    ) async {
      await tester.pumpWidget(host(titleRow(controllerOf('Leg day'))));
      expect(
        tester.getSize(find.byType(FormTitleRow)).height,
        FormMetrics.titleRowMinHeight,
      );
      expect(find.text('7/60'), findsNothing);
    });

    testWidgets('a warning is a line of the row\'s own under the field, in '
        'the error colour at the caption size, and shares its line with the '
        'counter near the limit', (tester) async {
      const text = 'A category named "Legs" already exists';
      final controller = controllerOf('Legs');
      await tester.pumpWidget(host(titleRow(controller, warning: text)));
      final field = find.byType(TextField);
      final colorScheme = Theme.of(tester.element(field)).colorScheme;

      final warning = find.text(text);
      expect(warning, findsOneWidget);
      final style = tester.widget<Text>(warning).style!;
      expect(style.color, colorScheme.error);
      expect(style.fontSize, FormMetrics.captionSize);
      expect(find.text('4/60'), findsNothing);
      // Under the field, starting where it starts.
      expect(
        tester.getTopLeft(warning).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(field).dy),
      );
      expect(tester.getTopLeft(warning).dx, tester.getTopLeft(field).dx);
      final alone = tester.getSize(find.byType(FormTitleRow)).height;
      expect(alone, greaterThan(FormMetrics.titleRowMinHeight));

      // Near the limit the counter joins the warning on its line, keeping
      // the end it has on every title row, and the row grows by no second
      // line. A title that long wraps the field in the test font, so the
      // height is compared with the same title under no warning.
      final long = 'a' * 55;
      await tester.pumpWidget(host(titleRow(controllerOf(long))));
      final counterOnly = tester.getSize(find.byType(FormTitleRow)).height;
      await tester.pumpWidget(
        host(titleRow(controllerOf(long), warning: text)),
      );
      final counter = find.text('55/60');
      expect(counter, findsOneWidget);
      expect(
        tester.getTopLeft(counter).dy,
        closeTo(tester.getTopLeft(warning).dy, 2),
      );
      expect(
        tester.getRect(counter).right,
        moreOrLessEquals(tester.getRect(field).right, epsilon: 0.01),
      );
      expect(
        tester.getRect(warning).right,
        lessThanOrEqualTo(
          tester.getRect(counter).left - FormMetrics.gap + 0.01,
        ),
      );
      // The warning's caption line stands in for the counter's; a line of
      // its own would add at least the counter's 16 px again.
      final both = tester.getSize(find.byType(FormTitleRow)).height;
      expect(both - counterOnly, inInclusiveRange(0, 16 - 0.01));

      // Without a warning the row is what it always was.
      await tester.pumpWidget(host(titleRow(controllerOf('Legs'))));
      expect(find.text(text), findsNothing);
      expect(
        tester.getSize(find.byType(FormTitleRow)).height,
        FormMetrics.titleRowMinHeight,
      );
    });

    testWidgets('the title is one field that wraps and refuses a line break', (
      tester,
    ) async {
      final controller = controllerOf();
      await tester.pumpWidget(host(titleRow(controller)));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, isNull);
      expect(field.textInputAction, TextInputAction.done);
      expect(field.maxLength, 60);

      await tester.enterText(find.byType(TextField), 'Leg\nday');
      await tester.pump();
      expect(controller.text, 'Legday');
    });

    testWidgets('a seeded title longer than the limit is kept and counted', (
      tester,
    ) async {
      final controller = controllerOf('a' * 70);
      await tester.pumpWidget(host(titleRow(controller)));
      expect(controller.text, hasLength(70));
      final colorScheme = Theme.of(
        tester.element(find.byType(TextField)),
      ).colorScheme;
      expect(
        tester.widget<Text>(find.text('70/60')).style!.color,
        colorScheme.error,
      );
    });

    testWidgets('the id lands on the text-field node, and the field takes '
        'focus only when asked to', (tester) async {
      await tester.pumpWidget(host(titleRow(controllerOf())));
      await tester.pump();
      final data = dataOf(tester, 'template-name');
      expect(data.identifier, 'template-name');
      expect(data.flagsCollection.isTextField, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isFalse,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(titleRow(controllerOf(), autofocus: true)));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    testWidgets('a tap anywhere in the row focuses the field: its top edge, '
        'its bottom edge, its far right and the avatar', (tester) async {
      await tester.pumpWidget(host(titleRow(controllerOf())));
      bool focused() => tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode
          .hasFocus;
      final row = tester.getRect(find.byType(FormTitleRow));
      final field = tester.getRect(find.byType(TextField));
      final avatar = tester.getRect(find.byType(EventAvatar));
      for (final MapEntry(key: name, value: point) in {
        'the top edge': Offset(field.center.dx, row.top + 1),
        'the bottom edge': Offset(field.center.dx, row.bottom - 1),
        'the far right': Offset(row.right - 1, row.center.dy),
        'the avatar': avatar.center,
      }.entries) {
        // Each point on its own, from an unfocused field — and outside the
        // field's own line, which focuses itself.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(focused(), isFalse, reason: 'before $name');
        expect(field.contains(point), isFalse, reason: name);
        await tester.tapAt(point);
        await tester.pump();
        expect(focused(), isTrue, reason: name);
      }
    });

    testWidgets('a tap in the row brings the keyboard back to a field that '
        'kept the focus under a dismissed one', (tester) async {
      await tester.pumpWidget(host(titleRow(controllerOf())));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);
      final row = tester.getRect(find.byType(FormTitleRow));
      await tester.tapAt(Offset(row.center.dx, row.bottom - 1));
      await tester.pump();

      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the field is named by its hint, empty and typed, and never '
        'twice', (tester) async {
      await tester.pumpWidget(host(titleRow(controllerOf())));
      expect(dataOf(tester, 'template-name').label, 'Template name');

      await tester.enterText(find.byType(TextField), 'Push day');
      await tester.pumpAndSettle();
      final typed = dataOf(tester, 'template-name');
      expect(typed.label, 'Template name');
      expect(typed.value, 'Push day');
      expect(typed.flagsCollection.isTextField, isTrue);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(dataOf(tester, 'template-name').label, 'Template name');
    });

    testWidgets('the focus node, the capitalization and the submit callback '
        'reach the field', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      String? submitted;
      await tester.pumpWidget(
        host(
          titleRow(
            controllerOf(),
            focusNode: focusNode,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (value) => submitted = value,
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode, focusNode);
      expect(field.textCapitalization, TextCapitalization.sentences);

      focusNode.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'Alarm');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, 'Alarm');
    });

    testWidgets('a long German title at 200 % on a narrow phone wraps without '
        'overflow, its counter under it', (tester) async {
      final controller = controllerOf(
        'Krankengymnastik und Rückenschule im Gesundheitszentrum',
      );
      await pumpOnNarrowPhoneAtDouble(tester, titleRow(controller));
      expect(tester.takeException(), isNull);
      expect(find.text('55/60'), findsOneWidget);
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThan(
          FormMetrics.titleFontSize * FormMetrics.titleLineHeight * 2.0,
        ),
      );
    });

    testWidgets('a hint that wraps at 200 % does not hold its lines open '
        'under a typed title: empty the row is as tall as the hint, typed as '
        'tall as one line', (tester) async {
      const line =
          FormMetrics.titleFontSize * FormMetrics.titleLineHeight * 2.0;
      const around =
          2 * FormMetrics.titleRowVerticalPadding +
          FormMetrics.titleFieldTopInset;
      double fieldHeight() => tester.getSize(find.byType(TextField)).height;
      double rowHeight() => tester.getSize(find.byType(FormTitleRow)).height;

      await pumpOnNarrowPhoneAtDouble(tester, titleRow(controllerOf()));
      expect(tester.takeException(), isNull);
      final hintHeight = tester.getSize(find.text('Template name')).height;
      // More than one line, or the typed row below would prove nothing.
      expect(hintHeight, greaterThanOrEqualTo(2 * line - 0.01));
      expect(fieldHeight(), moreOrLessEquals(hintHeight, epsilon: 0.01));
      expect(rowHeight(), moreOrLessEquals(around + hintHeight, epsilon: 0.01));

      await tester.enterText(find.byType(TextField), 'Legs');
      await tester.pumpAndSettle();
      expect(fieldHeight(), moreOrLessEquals(line, epsilon: 0.01));
      expect(rowHeight(), moreOrLessEquals(around + line, epsilon: 0.01));

      // Emptied again, the hint is back with the room it needs.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(fieldHeight(), moreOrLessEquals(hintHeight, epsilon: 0.01));
      expect(rowHeight(), moreOrLessEquals(around + hintHeight, epsilon: 0.01));
    });

    testWidgets('under a one-line hint the row is as tall empty as typed, at '
        '1.0, 1.3 and 2.0', (tester) async {
      // The event editor's own case: "Title" fits one line at every scale,
      // so whether the hint keeps its size cannot show there.
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);

      for (final textScale in const [1.0, 1.3, 2.0]) {
        final controller = controllerOf();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: RowMetrics.groupInset,
                ),
                child: FormRowGroup(
                  children: [
                    FormTitleRow(
                      leading: const EventAvatar(
                        icon: Icons.event_rounded,
                        color: Colors.blue,
                      ),
                      controller: controller,
                      hint: 'Title',
                      maxLength: 120,
                      counterFrom: 100,
                      counterLabel: (length, max) => '$length/$max',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        // One line as the text engine lays it out, which rounds it: within
        // a pixel of 26 times the scale.
        final line = tester.getSize(find.text('Title')).height;
        expect(
          line,
          moreOrLessEquals(
            FormMetrics.titleFontSize * FormMetrics.titleLineHeight * textScale,
            epsilon: 1,
          ),
          reason: 'the hint is one line at $textScale',
        );
        final empty = tester.getSize(find.byType(FormTitleRow));

        await tester.enterText(find.byType(TextField), 'Legs');
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(FormTitleRow)),
          empty,
          reason: 'at $textScale',
        );
        expect(
          tester.getSize(find.byType(TextField)).height,
          moreOrLessEquals(line, epsilon: 0.01),
          reason: 'at $textScale',
        );
      }
    });
  });

  group('hero row', () {
    FormHeroRow hero({
      String value = '7:15',
      String caption = 'Today',
      VoidCallback? onTap,
    }) => FormHeroRow(
      glyph: Icons.alarm_outlined,
      value: value,
      caption: caption,
      tooltip: 'Pick a time',
      identifier: 'quick-alarm-time',
      onTap: onTap ?? () {},
    );

    testWidgets('the row is one button node reading "value, caption" with '
        'the tooltip as its hint', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(hero(onTap: () => taps++)));
      final data = dataOf(tester, 'quick-alarm-time');
      expect(data.identifier, 'quick-alarm-time');
      expect(data.label, '7:15, Today');
      expect(data.hint, 'Pick a time');
      expect(data.tooltip, isEmpty);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      // The two texts are drawn and belong to the row's node, not to nodes
      // of their own.
      expect(find.text('7:15'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.semantics.byLabel('7:15'), findsNothing);
      expect(find.semantics.byLabel('Today'), findsNothing);
      expect(find.semantics.byLabel(RegExp('7:15')), findsOne);
      // Said, never drawn: a `Tooltip` would take the row's long press.
      expect(find.byType(Tooltip), findsNothing);

      await tester.tap(find.bySemanticsIdentifier('quick-alarm-time'));
      expect(taps, 1);
      // One ink well, so a tap on the caption or the chevron is the same tap.
      expect(
        find.descendant(
          of: find.byType(FormHeroRow),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Today'));
      await tester.tap(find.byType(FormChevron));
      expect(taps, 3);
    });

    testWidgets('a row without an id is still one node', (tester) async {
      await tester.pumpWidget(
        host(
          FormHeroRow(
            glyph: Icons.alarm_outlined,
            value: '7:15',
            caption: 'Today',
            tooltip: 'Pick a time',
            onTap: () {},
          ),
        ),
      );
      expect(find.semantics.byLabel('7:15, Today'), findsOne);
      expect(find.semantics.byLabel('Today'), findsNothing);
    });

    testWidgets('the row is 84 dp: the value at 40 on a 46 px line over a '
        'caption line, a plain hairline under it', (tester) async {
      final row = hero();
      await tester.pumpWidget(host(row));
      final rect = tester.getRect(find.byType(FormHeroRow));
      expect(
        rect.height,
        moreOrLessEquals(FormMetrics.heroRowMinHeight, epsilon: 0.01),
      );
      expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentPlain);
      final value = tester.widget<Text>(find.text('7:15'));
      expect(value.style!.fontSize, FormMetrics.heroValueSize);
      expect(value.style!.fontWeight, FontWeight.w400);
      expect(value.style!.fontFeatures, const [FontFeature.tabularFigures()]);
      expect(
        tester.getSize(find.text('7:15')).height,
        moreOrLessEquals(FormMetrics.heroValueLineHeight, epsilon: 0.01),
      );
      final caption = tester.widget<Text>(find.text('Today'));
      expect(caption.style!.fontSize, FormMetrics.captionSize);
      // Glyph, then the value and the caption in one column, then the
      // chevron at the row's end padding.
      final glyph = tester.getRect(find.byIcon(Icons.alarm_outlined));
      expect(glyph.left, RowMetrics.groupInset);
      expect(glyph.center.dy, moreOrLessEquals(rect.center.dy, epsilon: 0.01));
      final valueRect = tester.getRect(find.text('7:15'));
      final captionRect = tester.getRect(find.text('Today'));
      expect(valueRect.left, glyph.right + FormMetrics.gap);
      expect(captionRect.left, valueRect.left);
      expect(
        captionRect.top,
        moreOrLessEquals(valueRect.bottom + RowMetrics.lineGap, epsilon: 0.01),
      );
      expect(
        tester.getRect(find.byType(FormChevron)).right,
        rect.right - FormMetrics.rowEndPadding,
      );
    });

    testWidgets('the value stays on one line at 200 % on a narrow phone', (
      tester,
    ) async {
      await pumpOnNarrowPhoneAtDouble(
        tester,
        hero(value: '12:45 PM', caption: 'Morgen'),
      );
      expect(tester.takeException(), isNull);
      final value = tester.widget<Text>(find.text('12:45 PM'));
      expect(value.maxLines, 1);
      expect(value.softWrap, isFalse);
      // Laid out at its full size on one 92 px line, then fitted into the
      // column: the painted box ends before the chevron.
      expect(
        tester.getSize(find.text('12:45 PM')).height,
        moreOrLessEquals(FormMetrics.heroValueLineHeight * 2.0, epsilon: 0.01),
      );
      final painted = tester.getRect(find.text('12:45 PM'));
      final chevron = tester.getRect(find.byType(FormChevron));
      expect(
        painted.right,
        lessThanOrEqualTo(chevron.left - FormMetrics.gap + 0.01),
      );
      expect(painted.height, lessThan(FormMetrics.heroValueLineHeight * 2.0));
      expect(
        tester.getSize(find.byType(FormHeroRow)).height,
        greaterThanOrEqualTo(FormMetrics.heroRowMinHeight),
      );
      // The caption is not fitted: it scales with the text and may wrap.
      expect(
        tester.getSize(find.text('Morgen')).height,
        greaterThanOrEqualTo(18 * 2.0),
      );
    });

    testWidgets('the row is as tall for a long value as for a short one at '
        '1.0, 1.3 and 2.0: the fit shrinks the value, never the row', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      const values = ['7:15', '9:30 AM', '10:20 AM'];

      for (final textScale in const [1.0, 1.3, 2.0]) {
        final heights = <String, double>{};
        for (final value in values) {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RowMetrics.groupInset,
                  ),
                  child: FormRowGroup(children: [hero(value: value)]),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: '$value, $textScale');
          heights[value] = tester.getSize(find.byType(FormHeroRow)).height;
        }

        // The longest value is fitted at every one of these scales, or equal
        // heights would prove nothing: it is drawn narrower than it was laid
        // out. (Still on screen: the last value pumped.)
        final long = find.text(values.last);
        expect(
          tester.getRect(long).width,
          lessThan(tester.getSize(long).width),
          reason: 'at $textScale',
        );

        expect(
          heights.values.toSet(),
          hasLength(1),
          reason: 'at $textScale: $heights',
        );
        // And that one height is the text scale's: the row's padding around
        // the value's whole line as the text engine lays it out unfitted
        // (which rounds it, so within a pixel of 46 times the scale), the
        // gap and the caption.
        final line = tester.getSize(long).height;
        expect(
          line,
          moreOrLessEquals(
            FormMetrics.heroValueLineHeight * textScale,
            epsilon: 1,
          ),
          reason: 'at $textScale',
        );
        expect(
          heights.values.first,
          moreOrLessEquals(
            RowMetrics.twoLinePadding.vertical +
                line +
                RowMetrics.lineGap +
                tester.getSize(find.text('Today')).height,
            epsilon: 0.01,
          ),
          reason: 'at $textScale',
        );
      }
    });

    testWidgets('a value that fits is drawn at its full size, where it was '
        'before the line was reserved', (tester) async {
      // Reserving the line must not touch the common case: no scale, and the
      // value's box starting at the column's start and top.
      await tester.pumpWidget(host(hero(value: '7:15')));
      final value = find.text('7:15');
      expect(tester.getRect(value).size, tester.getSize(value));
      final glyph = tester.getRect(find.byIcon(Icons.alarm_outlined));
      final row = tester.getRect(find.byType(FormHeroRow));
      expect(tester.getRect(value).left, glyph.right + FormMetrics.gap);
      expect(
        tester.getRect(value).top,
        moreOrLessEquals(
          row.top + RowMetrics.twoLinePadding.top,
          epsilon: 0.01,
        ),
      );
      // The digit that holds the line open is never drawn.
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: find.text('0'), matching: find.byType(Opacity)),
            )
            .opacity,
        0,
      );
      expect(find.semantics.byLabel('0'), findsNothing);
    });
  });

  group('caption slot', () {
    Widget boxed(Widget child) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 200, child: child),
        ),
      ),
    );

    const captions = [
      FormCaption(text: 'Short'),
      FormCaption(text: 'A hint that runs on to more than one line'),
      FormCaption(
        text:
            'A warning that arrives late and is long enough to need more '
            'lines than either hint at this width',
        error: true,
      ),
    ];

    testWidgets('the slot is as tall as its tallest candidate, whichever one '
        'it shows', (tester) async {
      final heights = <double>[];
      for (final caption in captions) {
        await tester.pumpWidget(boxed(caption));
        heights.add(tester.getSize(find.byType(FormCaption)).height);
      }
      expect(heights[0], lessThan(heights[1]));
      expect(heights[1], lessThan(heights[2]));

      for (final shown in captions) {
        await tester.pumpWidget(
          boxed(FormCaptionSlot(candidates: captions, child: shown)),
        );
        expect(
          tester.getSize(find.byType(FormCaptionSlot)).height,
          heights[2],
          reason: 'showing "${shown.text}"',
        );
        // The shown caption starts at the slot's top, as a bare one would.
        expect(
          tester.getTopLeft(find.text(shown.text).hitTestable()),
          tester.getTopLeft(find.byType(FormCaptionSlot)),
        );
      }
    });

    testWidgets('only the shown caption is drawn, announced and hit', (
      tester,
    ) async {
      await tester.pumpWidget(
        boxed(FormCaptionSlot(candidates: captions, child: captions[0])),
      );
      expect(find.semantics.byLabel('Short'), findsOne);
      expect(find.semantics.byLabel(RegExp('A hint that')), findsNothing);
      expect(find.semantics.byLabel(RegExp('A warning')), findsNothing);
      // Every candidate is in the tree, which is what sizes the slot, and
      // none of them is on screen.
      expect(find.text('Short'), findsNWidgets(2));
      expect(find.text('Short').hitTestable(), findsOneWidget);
      expect(find.text(captions[1].text), findsOneWidget);
      expect(find.text(captions[1].text).hitTestable(), findsNothing);
      expect(find.text(captions[2].text).hitTestable(), findsNothing);
      for (final opacity in tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(FormCaptionSlot),
          matching: find.byType(Opacity),
        ),
      )) {
        expect(opacity.opacity, 0);
      }
    });

    testWidgets("a chip row keeps its height across the choice when its "
        'caption is a slot', (tester) async {
      const reminder =
          'Sits in the shade with Snooze and Done. Silent mode and Focus '
          'apply.';
      const alarm = 'Plays on the alarm stream until you stop or snooze it.';
      Widget row(Widget caption) => host(
        FormChipRow(
          glyph: Icons.notifications_outlined,
          label: 'Type',
          chips: [
            FormChip(label: 'Reminder', selected: true, onTap: () {}),
            FormChip(label: 'Alarm', selected: false, onTap: () {}),
          ],
          caption: caption,
        ),
      );
      double rowHeight() => tester.getSize(find.byType(FormChipRow)).height;

      // Bare, the two hints take a different number of lines, so the row
      // under the chips would move with the tier.
      await tester.pumpWidget(row(const FormCaption(text: reminder)));
      final tall = rowHeight();
      await tester.pumpWidget(row(const FormCaption(text: alarm)));
      expect(rowHeight(), lessThan(tall));

      const candidates = [
        FormCaption(text: reminder),
        FormCaption(text: alarm),
      ];
      for (final shown in candidates) {
        await tester.pumpWidget(
          row(FormCaptionSlot(candidates: candidates, child: shown)),
        );
        expect(rowHeight(), tall, reason: 'showing "${shown.text}"');
      }
    });
  });

  group('disabled chip', () {
    Widget presets({required VoidCallback? onTonight, bool selected = false}) =>
        host(
          FormChipRow(
            chips: [
              FormChip(label: 'In 20 min', selected: false, onTap: () {}),
              FormChip(
                label: 'Tonight',
                selected: selected,
                identifier: 'quick-alarm-preset-tonight',
                onTap: onTonight,
              ),
              FormChip(label: 'In 1 hour', selected: false, onTap: () {}),
            ],
          ),
        );

    Finder chip(String label) => find.widgetWithText(FormChip, label);

    testWidgets('an enabled chip carries no enabled state and no opacity '
        'layer', (tester) async {
      await tester.pumpWidget(presets(onTonight: () {}));
      final data = dataOf(tester, 'quick-alarm-preset-tonight');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.none);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(
        find.descendant(of: chip('Tonight'), matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('a disabled chip keeps its place and its 48 dp target, '
        'faded, inert and announced disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(presets(onTonight: () => taps++));
      final enabledRect = tester.getRect(chip('Tonight'));
      final nextRect = tester.getRect(chip('In 1 hour'));

      await tester.pumpWidget(presets(onTonight: null));
      // In place: neither the chip nor the one after it has moved.
      expect(tester.getRect(chip('Tonight')), enabledRect);
      expect(tester.getRect(chip('In 1 hour')), nextRect);
      expect(tester.getSize(chip('Tonight')).height, FormMetrics.chipTapTarget);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: chip('Tonight'), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, FormMetrics.disabledOpacity);
      final well = tester.widget<InkWell>(
        find.descendant(of: chip('Tonight'), matching: find.byType(InkWell)),
      );
      expect(well.onTap, isNull);

      final data = dataOf(tester, 'quick-alarm-preset-tonight');
      expect(data.label, 'Tonight');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.flagsCollection.isSelected, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(chip('Tonight'), warnIfMissed: false);
      // The padded target outside the 32 dp chip is inert too.
      await tester.tapAt(
        tester.getRect(chip('Tonight')).topCenter + const Offset(0, 2),
      );
      expect(taps, 0);
      // The chips either side still work.
      expect(
        tester
            .widget<InkWell>(
              find.descendant(
                of: chip('In 20 min'),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNotNull,
      );
    });

    testWidgets('a disabled chip that is the selected one still says so', (
      tester,
    ) async {
      await tester.pumpWidget(presets(onTonight: null, selected: true));
      final data = dataOf(tester, 'quick-alarm-preset-tonight');
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    });
  });

  group('a chip at a large text scale', () {
    FormChip tage() => FormChip(label: 'Tage', selected: true, onTap: () {});

    /// The three shapes a chip row has in the app: standing alone (a custom
    /// offset's units), under a switch (the editor's count-style and assume
    /// pairs) and beside a label (the detail sheet's presence pair, an
    /// alert's Type).
    final shapes = <String, FormChipRow Function()>{
      'standing alone': () => FormChipRow(indented: false, chips: [tage()]),
      'under a switch': () => FormChipRow(chips: [tage()]),
      'beside a label': () => FormChipRow(
        glyph: Icons.how_to_reg_outlined,
        label: 'Art',
        chips: [tage()],
      ),
    };

    Future<void> pumpAt(
      WidgetTester tester,
      double scale,
      FormChipRow row,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: FormRowGroup(children: [row])),
        ),
      );
    }

    RenderParagraph labelOf(WidgetTester tester) =>
        tester.renderObject<RenderParagraph>(find.text('Tage'));

    /// The height the label's one line needs, whatever box it was given.
    double lineOf(RenderParagraph label) =>
        label.getMaxIntrinsicHeight(label.size.width);

    /// The chip's own box — the filled or outlined shape — and not the
    /// 48 dp target around it.
    double boxHeightOf(WidgetTester tester) => tester
        .getSize(
          find.descendant(
            of: find.byType(FormChip),
            matching: find.byType(Material),
          ),
        )
        .height;

    double targetHeightOf(WidgetTester tester) =>
        tester.getSize(find.byType(FormChip)).height;

    testWidgets('up to 160 % the chip is its 32 dp with its label whole, '
        'inside its 48 dp target', (tester) async {
      for (final shape in shapes.entries) {
        for (final scale in [1.0, 1.3]) {
          final reason = '${shape.key} at $scale';
          await pumpAt(tester, scale, shape.value());
          final label = labelOf(tester);
          expect(boxHeightOf(tester), FormMetrics.chipHeight, reason: reason);
          expect(label.size.height, lineOf(label), reason: reason);
          expect(
            targetHeightOf(tester),
            FormMetrics.chipTapTarget,
            reason: reason,
          );
        }
        // At 160 % the label's line is the chip's 32 dp to a rounding error.
        await pumpAt(tester, 1.6, shape.value());
        final label = labelOf(tester);
        expect(
          boxHeightOf(tester),
          moreOrLessEquals(FormMetrics.chipHeight, epsilon: 0.01),
          reason: shape.key,
        );
        expect(
          label.size.height,
          moreOrLessEquals(lineOf(label), epsilon: 0.01),
          reason: shape.key,
        );
      }
    });

    testWidgets('at 200 % the chip grows with its label and cuts nothing, '
        'still inside its 48 dp target', (tester) async {
      // A 14 px label takes a 40 px line here. The chip used to stay 32 dp
      // and clip it, a descender losing its tail (found 2026-10-02 on the
      // alert sheet's Type chips drawn with a phone's font); the 32 dp is a
      // minimum since.
      for (final shape in shapes.entries) {
        await pumpAt(tester, 2.0, shape.value());
        final label = labelOf(tester);
        expect(
          lineOf(label),
          greaterThan(FormMetrics.chipHeight),
          reason: shape.key,
        );
        expect(
          label.size.height,
          moreOrLessEquals(lineOf(label), epsilon: 0.01),
          reason: shape.key,
        );
        expect(
          boxHeightOf(tester),
          moreOrLessEquals(lineOf(label), epsilon: 0.01),
          reason: shape.key,
        );
        expect(
          targetHeightOf(tester),
          FormMetrics.chipTapTarget,
          reason: shape.key,
        );
      }
    });

    testWidgets('a chip row under a switch and one standing alone are as '
        'tall at 200 % as at 100 %', (tester) async {
      // The taller chip lives inside the target it already had, so the rows
      // the editor and the Custom sub-sheet draw do not move.
      for (final shape in ['standing alone', 'under a switch']) {
        await pumpAt(tester, 1.0, shapes[shape]!());
        final height = tester.getSize(find.byType(FormChipRow)).height;
        await pumpAt(tester, 2.0, shapes[shape]!());
        expect(
          tester.getSize(find.byType(FormChipRow)).height,
          height,
          reason: shape,
        );
      }
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

  group('header hairline', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      Widget body, {
      Axis scrollDirection = Axis.vertical,
    }) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: _HairlineSheet(scrollDirection: scrollDirection, body: body),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final body = find.byType(SingleChildScrollView);

    bool scrolled(WidgetTester tester) => tester
        .widget<FormSheetHeader>(find.byType(FormSheetHeader))
        .scrolled!
        .value;

    /// The 1 px line itself, as the header paints it.
    Color? lineColor(WidgetTester tester) => tester
        .widget<Container>(
          find.descendant(
            of: find.byType(FormSheetHeader),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.constraints?.maxHeight == 1,
            ),
          ),
        )
        .color;

    Color dividerColor(WidgetTester tester) => Theme.of(
      tester.element(find.byType(FormSheetHeader)),
    ).colorScheme.rowDivider;

    double offsetOf(WidgetTester tester, Finder scrollView) => tester
        .state<ScrollableState>(
          find
              .descendant(of: scrollView, matching: find.byType(Scrollable))
              .first,
        )
        .position
        .pixels;

    testWidgets('off over a body at rest, on once it has scrolled, off again '
        'back at the top', (tester) async {
      await pumpSheet(tester, const SizedBox(height: 1500));
      expect(scrolled(tester), isFalse);
      expect(lineColor(tester), Colors.transparent);

      await tester.drag(body, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, body), greaterThan(0));
      expect(scrolled(tester), isTrue);
      expect(lineColor(tester), dividerColor(tester));

      await tester.drag(body, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, body), 0);
      expect(scrolled(tester), isFalse);
      expect(lineColor(tester), Colors.transparent);
    });

    testWidgets('it follows a body that gets shorter under it: the keyboard '
        'goes down over content that no longer scrolls, and the hairline '
        'goes with it', (tester) async {
      // 600 dp of rows fit under the header on their own and scroll only
      // while the keyboard's inset pads them.
      await pumpSheet(tester, const SizedBox(height: 600));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(scrolled(tester), isFalse);

      await tester.drag(body, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, body), greaterThan(0));
      expect(scrolled(tester), isTrue);

      // The scroll view puts itself back at its top without a scroll: no
      // scroll controller's listener hears of it.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(offsetOf(tester, body), 0);
      expect(scrolled(tester), isFalse);
      expect(lineColor(tester), Colors.transparent);
    });

    testWidgets('a scrollable inside the body does not draw it: a list of its '
        'own, a strip that scrolls sideways', (tester) async {
      await pumpSheet(
        tester,
        Column(
          children: [
            SizedBox(
              height: 120,
              child: ListView(
                key: const ValueKey('inner'),
                children: const [SizedBox(height: 600)],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                key: const ValueKey('strip'),
                scrollDirection: Axis.horizontal,
                children: const [SizedBox(width: 900)],
              ),
            ),
          ],
        ),
      );
      final inner = find.byKey(const ValueKey('inner'));
      final strip = find.byKey(const ValueKey('strip'));

      await tester.drag(inner, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, inner), greaterThan(0));
      expect(scrolled(tester), isFalse);

      await tester.drag(strip, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, strip), greaterThan(0));
      expect(scrolled(tester), isFalse);
      expect(lineColor(tester), Colors.transparent);
    });

    testWidgets('nor does a scroll view that runs sideways, watched '
        'directly: nothing has gone under the header', (tester) async {
      await pumpSheet(
        tester,
        const SizedBox(width: 900, height: 48),
        scrollDirection: Axis.horizontal,
      );

      await tester.drag(body, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(offsetOf(tester, body), greaterThan(0));
      expect(scrolled(tester), isFalse);
    });
  });
}

/// A sub-sheet's shape around a [FormHeaderHairline]: the header over a
/// scroll view as tall as its content, its bottom padded by the keyboard's
/// inset.
class _HairlineSheet extends StatefulWidget {
  final Axis scrollDirection;
  final Widget body;

  const _HairlineSheet({required this.scrollDirection, required this.body});

  @override
  State<_HairlineSheet> createState() => _HairlineSheetState();
}

class _HairlineSheetState extends State<_HairlineSheet> {
  final FormHeaderHairline _hairline = FormHeaderHairline();

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: 'Cancel',
          onLeading: () {},
          title: 'Sheet',
          trailing: const SizedBox.shrink(),
          scrolled: _hairline.scrolled,
        ),
        Flexible(
          child: _hairline.watch(
            child: SingleChildScrollView(
              scrollDirection: widget.scrollDirection,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: widget.body,
            ),
          ),
        ),
      ],
    );
  }
}
