import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/widgets/alert_offset_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// The Custom sub-sheet on its own: what it opens on for a stored offset,
/// what the units and the stepper do to the number, and that nothing reaches
/// the caller but Done. The arithmetic is `AlertOffset`'s, table-tested in
/// `test/utils/alert_offset_test.dart`, and the read-back's wording is the
/// caller's; these pin that the sheet shows what the two say and returns
/// what it shows.
void main() {
  const perDay = EventAlert.minutesPerDay;
  const phone = Size(360, 780);

  /// The caller's wording in these cases: the stored number itself, so a
  /// read-back names exactly what Done would hand back.
  String stored(int value) => '$value stored';

  Future<_Outcome> open(
    WidgetTester tester, {
    required int initial,
    bool allDay = false,
    String Function(int stored)? readBack,
    Size? surface,
    Locale locale = const Locale('en'),
    double? textScale,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: textScale == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => outcome.record(
                await AlertOffsetSheet.show(
                  context,
                  initial: initial,
                  allDay: allDay,
                  readBack: readBack ?? stored,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Future<void> tap(WidgetTester tester, String id) async {
    await tester.tap(byId(id));
    await tester.pumpAndSettle();
  }

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(byId(id)).getSemanticsData();

  /// The copy of a row the user sees. The sheet also lays out every unit's
  /// group and every line the read-back can say, unseen, to hold its height;
  /// those come first in the tree and the live ones last.
  Finder live(Finder matching) => matching.last;

  FormStepperRow stepper(WidgetTester tester) =>
      tester.widget(live(find.byType(FormStepperRow)));

  String shownReadBack(WidgetTester tester) =>
      tester.widget<FormCaption>(live(find.byType(FormCaption))).text;

  /// The label of the unit chip that is selected, among the live ones.
  String? selectedUnit(WidgetTester tester) {
    final chips = tester
        .widgetList<FormChip>(
          find.descendant(
            of: live(find.byType(FormChipRow)),
            matching: find.byType(FormChip),
          ),
        )
        .where((chip) => chip.selected);
    return chips.isEmpty ? null : chips.single.label;
  }

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AlertOffsetSheet)).height;

  /// A label nothing cuts: its box is as tall as its text needs at the width
  /// it was given.
  void expectWhole(WidgetTester tester, Finder text, {required String reason}) {
    final label = tester.renderObject<RenderParagraph>(text);
    expect(
      label.size.height,
      moreOrLessEquals(
        label.getMaxIntrinsicHeight(label.size.width),
        epsilon: 0.01,
      ),
      reason: reason,
    );
    expect(label.didExceedMaxLines, isFalse, reason: reason);
  }

  void expectClosedWith(_Outcome outcome, int? value) {
    expect(outcome.returned, isTrue);
    expect(outcome.result, value);
    expect(find.byType(AlertOffsetSheet), findsNothing);
  }

  group('what Done returns', () {
    testWidgets('the minutes a timed offset stands on', (tester) async {
      final outcome = await open(tester, initial: 10);

      await tap(tester, SemanticsIds.alertCustomDone);

      expectClosedWith(outcome, 10);
    });

    testWidgets('minutes whatever unit the number is counted in', (
      tester,
    ) async {
      final outcome = await open(tester, initial: 10);

      await tap(tester, SemanticsIds.alertCustomUnitHours);
      await tap(tester, SemanticsIds.alertCustomMore);
      expect(shownReadBack(tester), stored(11 * 60));
      await tap(tester, SemanticsIds.alertCustomDone);

      expectClosedWith(outcome, 11 * 60);
    });

    testWidgets('whole days for an all-day event', (tester) async {
      final outcome = await open(tester, initial: 3, allDay: true);

      await tap(tester, SemanticsIds.alertCustomLess);
      await tap(tester, SemanticsIds.alertCustomDone);

      expectClosedWith(outcome, 2);
    });
  });

  group('every other way out returns nothing', () {
    final waysOut = <String, Future<void> Function(WidgetTester tester)>{
      'the close button': (tester) =>
          tester.tap(find.bySemanticsIdentifier(SemanticsIds.alertCustomClose)),
      'the barrier': (tester) => tester.tapAt(const Offset(10, 10)),
      'the system back': (tester) => tester.binding.handlePopRoute(),
      'a fling on the handle': (tester) => tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      ),
    };
    for (final way in waysOut.entries) {
      testWidgets(way.key, (tester) async {
        final outcome = await open(tester, initial: 10);

        // Something to lose: the number has moved before the sheet is left.
        await tap(tester, SemanticsIds.alertCustomMore);
        expect(stepper(tester).value, '11');
        await way.value(tester);
        await tester.pumpAndSettle();

        expectClosedWith(outcome, null);
      });
    }
  });

  group('what it opens on', () {
    const timed = <({int stored, String unit, String value, int done})>[
      // "At start" is no number of minutes: the stepper stands on one, which
      // only Done hands back.
      (stored: 0, unit: 'Minutes', value: '1', done: 1),
      (stored: 5, unit: 'Minutes', value: '5', done: 5),
      (stored: 45, unit: 'Minutes', value: '45', done: 45),
      (stored: 60, unit: 'Hours', value: '1', done: 60),
      (stored: 120, unit: 'Hours', value: '2', done: 120),
      (stored: perDay, unit: 'Days', value: '1', done: perDay),
      (stored: 3 * perDay, unit: 'Days', value: '3', done: 3 * perDay),
      // What the stepper cannot count opens on the bound of its unit.
      (stored: 90, unit: 'Minutes', value: '59', done: 59),
      (stored: 36 * 60, unit: 'Hours', value: '23', done: 23 * 60),
      (stored: 45 * perDay, unit: 'Days', value: '30', done: 30 * perDay),
    ];

    testWidgets('a timed offset opens in its natural unit, clamped', (
      tester,
    ) async {
      for (final seed in timed) {
        final reason = '${seed.stored} min';
        final outcome = await open(tester, initial: seed.stored);

        expect(selectedUnit(tester), seed.unit, reason: reason);
        expect(stepper(tester).label, seed.unit, reason: reason);
        expect(stepper(tester).value, seed.value, reason: reason);
        // The line under the stepper is the caller's wording for the number
        // Done would hand back: the clamped one, never the one that arrived.
        expect(shownReadBack(tester), stored(seed.done), reason: reason);
        await tap(tester, SemanticsIds.alertCustomDone);

        expect(outcome.result, seed.done, reason: reason);
      }
    });

    testWidgets('an all-day offset opens in days, 1 to 30', (tester) async {
      const seeds = <({int stored, String value, int done})>[
        (stored: 0, value: '1', done: 1),
        (stored: 1, value: '1', done: 1),
        (stored: 7, value: '7', done: 7),
        (stored: 30, value: '30', done: 30),
        (stored: 45, value: '30', done: 30),
      ];
      for (final seed in seeds) {
        final reason = '${seed.stored} days';
        final outcome = await open(tester, initial: seed.stored, allDay: true);

        expect(stepper(tester).label, 'Days', reason: reason);
        expect(stepper(tester).value, seed.value, reason: reason);
        // Days, as the alert stores them for an all-day event: the caller is
        // asked to word a day count, never a number of minutes.
        expect(shownReadBack(tester), stored(seed.done), reason: reason);
        await tap(tester, SemanticsIds.alertCustomDone);

        expect(outcome.result, seed.done, reason: reason);
      }
    });
  });

  group('the unit', () {
    testWidgets('is three chips in order, each on its id, the current one '
        'selected', (tester) async {
      await open(tester, initial: 120);

      final chips = tester
          .widgetList<FormChip>(
            find.descendant(
              of: live(find.byType(FormChipRow)),
              matching: find.byType(FormChip),
            ),
          )
          .toList();
      expect(
        [for (final chip in chips) chip.label],
        ['Minutes', 'Hours', 'Days'],
      );
      expect(
        [for (final chip in chips) chip.identifier],
        [
          SemanticsIds.alertCustomUnitMinutes,
          SemanticsIds.alertCustomUnitHours,
          SemanticsIds.alertCustomUnitDays,
        ],
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.alertCustomUnitHours,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.alertCustomUnitMinutes,
        ).flagsCollection.isSelected,
        Tristate.isFalse,
      );
    });

    testWidgets('a change keeps the number, clamped into the new range, and '
        'does not give it back', (tester) async {
      final outcome = await open(tester, initial: 45);

      await tap(tester, SemanticsIds.alertCustomUnitHours);
      expect(selectedUnit(tester), 'Hours');
      expect(stepper(tester).label, 'Hours');
      expect(stepper(tester).value, '23');
      expect(shownReadBack(tester), stored(23 * 60));

      await tap(tester, SemanticsIds.alertCustomUnitMinutes);
      expect(stepper(tester).value, '23');
      expect(shownReadBack(tester), stored(23));

      await tap(tester, SemanticsIds.alertCustomUnitDays);
      expect(stepper(tester).label, 'Days');
      expect(stepper(tester).value, '23');
      expect(shownReadBack(tester), stored(23 * perDay));
      await tap(tester, SemanticsIds.alertCustomDone);

      expectClosedWith(outcome, 23 * perDay);
    });

    testWidgets('a number that fits every range survives every change', (
      tester,
    ) async {
      await open(tester, initial: 5);

      for (final unit in const [
        (id: SemanticsIds.alertCustomUnitHours, minutes: 5 * 60),
        (id: SemanticsIds.alertCustomUnitDays, minutes: 5 * perDay),
        (id: SemanticsIds.alertCustomUnitMinutes, minutes: 5),
      ]) {
        await tap(tester, unit.id);
        expect(stepper(tester).value, '5');
        expect(shownReadBack(tester), stored(unit.minutes));
      }
    });
  });

  group('the bounds', () {
    /// Both buttons where they are, one of them switched off: disabled in
    /// place, never taken away.
    void expectOnly({
      required WidgetTester tester,
      required String enabledId,
      required String disabledId,
      required Map<String, Rect> rects,
      required String reason,
    }) {
      final disabled = dataOf(tester, disabledId);
      expect(disabled.hasAction(SemanticsAction.tap), isFalse, reason: reason);
      expect(
        disabled.flagsCollection.isEnabled,
        Tristate.isFalse,
        reason: reason,
      );
      final enabled = dataOf(tester, enabledId);
      expect(enabled.hasAction(SemanticsAction.tap), isTrue, reason: reason);
      expect(
        enabled.flagsCollection.isEnabled,
        Tristate.isTrue,
        reason: reason,
      );
      for (final id in rects.keys) {
        expect(tester.getRect(byId(id)), rects[id], reason: reason);
      }
    }

    Map<String, Rect> buttonRects(WidgetTester tester) => {
      for (final id in [
        SemanticsIds.alertCustomLess,
        SemanticsIds.alertCustomMore,
      ])
        id: tester.getRect(byId(id)),
    };

    testWidgets('the floor of every unit disables the minus button in place', (
      tester,
    ) async {
      await open(tester, initial: 2);
      final rects = buttonRects(tester);
      expect(
        dataOf(
          tester,
          SemanticsIds.alertCustomLess,
        ).hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tap(tester, SemanticsIds.alertCustomLess);
      for (final unit in const [
        SemanticsIds.alertCustomUnitMinutes,
        SemanticsIds.alertCustomUnitHours,
        SemanticsIds.alertCustomUnitDays,
      ]) {
        await tap(tester, unit);
        expect(stepper(tester).value, '1');
        expectOnly(
          tester: tester,
          enabledId: SemanticsIds.alertCustomMore,
          disabledId: SemanticsIds.alertCustomLess,
          rects: rects,
          reason: unit,
        );
        // A tap on the dead button moves nothing.
        await tester.tap(
          byId(SemanticsIds.alertCustomLess),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(stepper(tester).value, '1');
      }
    });

    testWidgets('the ceiling of every unit disables the plus button in '
        'place', (tester) async {
      const ceilings = <({int stored, String value})>[
        (stored: 59, value: '59'),
        (stored: 23 * 60, value: '23'),
        (stored: 30 * perDay, value: '30'),
      ];
      for (final ceiling in ceilings) {
        final outcome = await open(tester, initial: ceiling.stored);
        final reason = '${ceiling.stored} min';

        expect(stepper(tester).value, ceiling.value, reason: reason);
        // One step down and back up: the rects of an enabled pair, then the
        // ceiling again.
        await tap(tester, SemanticsIds.alertCustomLess);
        final rects = buttonRects(tester);
        await tap(tester, SemanticsIds.alertCustomMore);
        expectOnly(
          tester: tester,
          enabledId: SemanticsIds.alertCustomLess,
          disabledId: SemanticsIds.alertCustomMore,
          rects: rects,
          reason: reason,
        );
        await tester.tap(
          byId(SemanticsIds.alertCustomMore),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(stepper(tester).value, ceiling.value, reason: reason);
        await tap(tester, SemanticsIds.alertCustomDone);

        expect(outcome.result, ceiling.stored, reason: reason);
      }
    });

    testWidgets('between the bounds both buttons step by one', (tester) async {
      await open(tester, initial: 10);

      await tap(tester, SemanticsIds.alertCustomMore);
      await tap(tester, SemanticsIds.alertCustomMore);
      expect(stepper(tester).value, '12');
      expect(shownReadBack(tester), stored(12));
      await tap(tester, SemanticsIds.alertCustomLess);
      expect(stepper(tester).value, '11');
      expect(
        dataOf(tester, SemanticsIds.alertCustomLess).tooltip,
        'Less time before',
      );
      expect(
        dataOf(tester, SemanticsIds.alertCustomMore).tooltip,
        'More time before',
      );
    });
  });

  group('an all-day event', () {
    testWidgets('has no unit choice: the stepper counts days and nothing '
        'else', (tester) async {
      await open(tester, initial: 2, allDay: true);

      expect(find.byType(FormChipRow), findsNothing);
      expect(find.byType(FormChip), findsNothing);
      for (final unit in const [
        SemanticsIds.alertCustomUnitMinutes,
        SemanticsIds.alertCustomUnitHours,
        SemanticsIds.alertCustomUnitDays,
      ]) {
        expect(byId(unit), findsNothing);
      }
      expect(stepper(tester).label, 'Days');
      expect(stepper(tester).value, '2');
    });

    testWidgets('stops at 1 and at 30 days', (tester) async {
      final outcome = await open(tester, initial: 1, allDay: true);
      expect(stepper(tester).onDecrement, isNull);
      expect(stepper(tester).onIncrement, isNotNull);
      await tap(tester, SemanticsIds.alertCustomClose);
      expectClosedWith(outcome, null);

      await open(tester, initial: 30, allDay: true);
      expect(stepper(tester).onIncrement, isNull);
      expect(stepper(tester).onDecrement, isNotNull);
    });
  });

  group('chrome and layout', () {
    testWidgets('the header is a close, Custom and a text Done, each on its '
        'id', (tester) async {
      await open(tester, initial: 10);

      expect(find.byType(FormSheetHandle), findsOneWidget);
      final header = tester.widget<FormSheetHeader>(
        find.byType(FormSheetHeader),
      );
      expect(header.title, 'Custom');
      expect(header.leadingIcon, Icons.close_rounded);
      expect(header.leadingIdentifier, SemanticsIds.alertCustomClose);
      expect(dataOf(tester, SemanticsIds.alertCustomClose).tooltip, 'Cancel');
      final done = tester.widget<FormHeaderTextButton>(
        find.byType(FormHeaderTextButton),
      );
      expect(done.label, 'Done');
      expect(done.identifier, SemanticsIds.alertCustomDone);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('one group: the units from the group inset over a plain '
        'hairline, the stepper, and the read-back under the group', (
      tester,
    ) async {
      await open(tester, initial: 45);

      // A sheet is at most 640 wide and centred, so every position is read
      // against the sheet's own edge.
      final sheetLeft = tester.getRect(find.byType(AlertOffsetSheet)).left;
      final group = live(find.byType(FormRowGroup));
      final groupRect = tester.getRect(group);
      expect(groupRect.left, sheetLeft + RowMetrics.groupInset);
      expect(tester.widget<FormRowGroup>(group).trailingGap, isFalse);

      final chipRow = live(find.byType(FormChipRow));
      expect(tester.getSize(chipRow).height, FormMetrics.rowMinHeight);
      expect(
        tester.getRect(byId(SemanticsIds.alertCustomUnitMinutes)).left,
        groupRect.left + RowMetrics.groupInset,
      );
      final hairline = tester.widget<Divider>(
        find.descendant(of: group, matching: find.byType(Divider)),
      );
      expect(hairline.indent, FormMetrics.dividerIndentPlain);

      final stepperRow = live(find.byType(FormStepperRow));
      expect(tester.getSize(stepperRow).height, FormMetrics.rowMinHeight);
      expect(
        tester.getRect(stepperRow).top,
        tester.getRect(chipRow).bottom + 1,
      );
      expect(groupRect.height, FormMetrics.rowMinHeight * 2 + 1);

      final caption = live(find.text(stored(45)));
      expect(
        tester.getRect(caption).left,
        groupRect.left + FormMetrics.groupCaptionPadding.left,
      );
      expect(
        tester.getRect(caption).top,
        groupRect.bottom + FormMetrics.groupCaptionPadding.top,
      );
    });

    testWidgets('only the live body is announced', (tester) async {
      await open(tester, initial: 45);

      // Every unit's group and every line the read-back can say are laid out
      // to size the sheet, and none of them reaches a screen reader or a
      // script.
      expect(find.byType(FormStepperRow), findsNWidgets(4));
      expect(find.text(stored(45)), findsNWidgets(2));
      expect(find.semantics.byLabel(stored(45)), findsOne);
      expect(find.text(stored(59)), findsOneWidget);
      expect(find.semantics.byLabel(stored(59)), findsNothing);
      expect(find.semantics.byLabel(stored(23 * 60)), findsNothing);
      expect(find.semantics.byLabel(stored(30 * perDay)), findsNothing);
      for (final id in [
        SemanticsIds.alertCustomClose,
        SemanticsIds.alertCustomDone,
        SemanticsIds.alertCustomUnitMinutes,
        SemanticsIds.alertCustomUnitHours,
        SemanticsIds.alertCustomUnitDays,
        SemanticsIds.alertCustomLess,
        SemanticsIds.alertCustomMore,
      ]) {
        expect(byId(id), findsOneWidget, reason: id);
      }
    });

    /// Walks every unit and both ends of each, the sheet's height unchanged
    /// at every stop.
    Future<void> expectOneHeight(WidgetTester tester) async {
      final height = sheetHeight(tester);
      Future<void> check(String step) async {
        expect(tester.takeException(), isNull, reason: step);
        expect(sheetHeight(tester), height, reason: 'moved after $step');
      }

      for (final unit in const [
        SemanticsIds.alertCustomUnitHours,
        SemanticsIds.alertCustomUnitDays,
        SemanticsIds.alertCustomUnitMinutes,
      ]) {
        await tap(tester, unit);
        await check(unit);
        while (stepper(tester).onDecrement != null) {
          await tap(tester, SemanticsIds.alertCustomLess);
        }
        await check('$unit at the floor');
        await tap(tester, SemanticsIds.alertCustomMore);
        await check('$unit at two');
      }
    }

    testWidgets('the sheet keeps one height across the units and the number', (
      tester,
    ) async {
      await open(tester, initial: 45);
      expect(
        sheetHeight(tester),
        lessThan(600 * FormMetrics.sheetHeightFactor),
      );

      await expectOneHeight(tester);
    });

    testWidgets("the sheet is as tall as the caller's tallest line from the "
        'start, wherever in the range that line is', (tester) async {
      // The wording is the caller's, and its longest line need not belong to
      // a bound: a week reads longer than thirty days in German. Here one
      // value in the middle of the minutes takes several lines.
      const tall =
          'seven minutes, said at such length that the line under the stepper '
          'has to wrap more than once at any width a sheet can have, which '
          'is the point of saying it this way';
      String wordy(int stored) => stored == 7 ? tall : '$stored';

      await open(tester, initial: 5);
      final plain = sheetHeight(tester);
      await tap(tester, SemanticsIds.alertCustomClose);

      await open(tester, initial: 5, readBack: wordy);
      final height = sheetHeight(tester);
      expect(height, greaterThan(plain));
      expect(height, lessThan(600 * FormMetrics.sheetHeightFactor));

      for (final expected in ['6', tall, '8']) {
        await tap(tester, SemanticsIds.alertCustomMore);
        expect(shownReadBack(tester), expected);
        expect(sheetHeight(tester), height, reason: 'moved at "$expected"');
      }
      // The tall line is whole where it stands: nothing clamps it.
      await tap(tester, SemanticsIds.alertCustomLess);
      final line = tester.renderObject<RenderParagraph>(live(find.text(tall)));
      expect(line.size.height, line.getMaxIntrinsicHeight(line.size.width));
      expect(line.size.height, greaterThan(18 * 2));
    });

    testWidgets('on a 360 × 780 phone every control keeps a 48 dp target', (
      tester,
    ) async {
      await open(tester, initial: 45, surface: phone);

      expect(tester.takeException(), isNull);
      expect(
        sheetHeight(tester),
        lessThan(phone.height * FormMetrics.sheetHeightFactor),
      );
      for (final id in [
        SemanticsIds.alertCustomUnitMinutes,
        SemanticsIds.alertCustomUnitHours,
        SemanticsIds.alertCustomUnitDays,
      ]) {
        final chip = find.byWidgetPredicate(
          (widget) => widget is FormChip && widget.identifier == id,
        );
        expect(
          tester.getSize(live(chip)).height,
          FormMetrics.chipTapTarget,
          reason: id,
        );
      }
      // Whole runs of 48 dp and nothing between them. How many is the font's
      // to say: the test font is about twice as wide as a phone's, which
      // fits the three units on one run.
      expect(
        tester.getSize(live(find.byType(FormChipRow))).height %
            FormMetrics.rowMinHeight,
        0,
      );
      for (final id in [
        SemanticsIds.alertCustomLess,
        SemanticsIds.alertCustomMore,
      ]) {
        expect(
          tester.getSize(byId(id)),
          const Size.square(FormMetrics.trailingButtonSize),
          reason: id,
        );
      }
      expect(
        tester.getRect(byId(SemanticsIds.alertCustomMore)).right,
        phone.width - RowMetrics.groupInset,
      );
      await expectOneHeight(tester);
    });

    testWidgets('the header\'s hairline follows the body: on while it is '
        'scrolled over a bottom inset, off once the inset is gone and the '
        'sheet no longer scrolls', (tester) async {
      // A window short enough for the inset to push this small sheet past
      // its clamp, which is what gives its body something to scroll.
      const short = Size(360, 420);
      await open(tester, initial: 45, surface: short);
      expect(
        sheetHeight(tester),
        lessThan(short.height * FormMetrics.sheetHeightFactor),
      );
      final body = find.byType(SingleChildScrollView);
      final scrolled = tester
          .widget<FormSheetHeader>(find.byType(FormSheetHeader))
          .scrolled!;
      double offset() => tester
          .state<ScrollableState>(
            find.descendant(of: body, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;
      expect(scrolled.value, isFalse);

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(scrolled.value, isFalse);
      await tester.drag(body, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(offset(), greaterThan(0));
      expect(scrolled.value, isTrue);

      // Back at its top without a scroll: no listener on a scroll controller
      // hears of it.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(offset(), 0);
      expect(scrolled.value, isFalse);
    });

    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out '
        'without overflow, every label whole, at one height', (tester) async {
      await open(
        tester,
        initial: 45,
        readBack: (stored) => '$stored Min. vorher',
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(
        sheetHeight(tester),
        lessThan(phone.height * FormMetrics.sheetHeightFactor),
      );
      expect(
        tester
            .widget<FormHeaderTextButton>(find.byType(FormHeaderTextButton))
            .label,
        'Fertig',
      );
      expect(shownReadBack(tester), '45 Min. vorher');

      // Every unit chip is whole — as tall as its label's line needs, where
      // a 32 dp chip used to cut it at this scale — inside the group, and
      // keeps its 48 dp target on whichever run it lands.
      final groupRect = tester.getRect(live(find.byType(FormRowGroup)));
      for (final label in ['Minuten', 'Stunden', 'Tage']) {
        final chip = live(find.widgetWithText(FormChip, label));
        final rect = tester.getRect(chip);
        expect(rect.height, FormMetrics.chipTapTarget, reason: label);
        expect(rect.left, greaterThanOrEqualTo(groupRect.left), reason: label);
        expect(rect.right, lessThanOrEqualTo(groupRect.right), reason: label);
        expectWhole(
          tester,
          find.descendant(of: chip, matching: find.text(label)),
          reason: label,
        );
      }
      // The stepper's label and the read-back wrap rather than cut.
      final stepperLabel = find.descendant(
        of: live(find.byType(FormStepperRow)),
        matching: find.text('Minuten'),
      );
      expect(tester.widget<Text>(stepperLabel).maxLines, isNull);
      expectWhole(tester, stepperLabel, reason: 'the stepper label');
      expect(
        tester.widget<FormCaption>(live(find.byType(FormCaption))).maxLines,
        isNull,
      );
      expectWhole(
        tester,
        live(find.text('45 Min. vorher')),
        reason: 'the read-back',
      );
      expect(
        tester.getRect(live(find.text('45 Min. vorher'))).right,
        lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
      );
      for (final id in [
        SemanticsIds.alertCustomLess,
        SemanticsIds.alertCustomMore,
      ]) {
        expect(
          tester.getSize(byId(id)),
          const Size.square(FormMetrics.trailingButtonSize),
          reason: id,
        );
      }

      await expectOneHeight(tester);
    });
  });
}

class _Outcome {
  bool returned = false;
  int? result;

  void record(int? value) {
    returned = true;
    result = value;
  }
}
