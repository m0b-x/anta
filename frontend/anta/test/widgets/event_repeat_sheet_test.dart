import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/row_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const surface = Size(800, 1400);
  final startDate = DateTime.utc(2026, 9, 25);
  const weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  /// [forTemplate] opens the template variant. Left false the call is the
  /// event editor's own, argument for argument, so every case that does not
  /// ask for the variant also proves the default.
  Future<_Outcome> open(
    WidgetTester tester,
    EventRepeatDraft draft, {
    bool forTemplate = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = forTemplate
                    ? await EventRepeatSheet.show(
                        context,
                        draft: draft,
                        startDate: startDate,
                        appearance: const CalendarAppearance(),
                        forTemplate: true,
                      )
                    : await EventRepeatSheet.show(
                        context,
                        draft: draft,
                        startDate: startDate,
                        appearance: const CalendarAppearance(),
                      );
                outcome.record(result);
              },
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder shown(String text) => find.text(text).hitTestable();

  Finder done() => find.widgetWithText(TextButton, 'Done');

  VoidCallback? doneAction(WidgetTester tester) =>
      tester.widget<TextButton>(done()).onPressed;

  Finder stepButton(String tooltip) =>
      find.ancestor(of: find.byTooltip(tooltip).hitTestable(), matching: find.byType(IconButton));

  VoidCallback? stepAction(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(stepButton(tooltip)).onPressed;

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(EventRepeatSheet)).height;

  ColorScheme colorsOf(WidgetTester tester) =>
      Theme.of(tester.element(done())).colorScheme;

  group('every option round-trips through Done', () {
    const base = EventRepeatDraft(
      recurring: false,
      kind: RepeatKind.daily,
      weekdays: {1},
    );
    const recurringOptions = <String, RepeatKind>{
      'Daily': RepeatKind.daily,
      'Weekly': RepeatKind.weekly,
      'Monthly': RepeatKind.monthly,
      'Yearly': RepeatKind.yearly,
      'Workdays': RepeatKind.workdays,
      'Weekends': RepeatKind.weekends,
      'Public holidays only': RepeatKind.holidays,
    };

    for (final option in recurringOptions.entries) {
      testWidgets(option.key, (tester) async {
        final outcome = await open(tester, base);

        await tap(tester, find.text(option.key));
        await tap(tester, done());

        expect(outcome.returned, isTrue);
        expect(outcome.result, isNotNull);
        expect(outcome.result!.recurring, isTrue);
        expect(outcome.result!.kind, option.value);
        expect(find.byType(EventRepeatSheet), findsNothing);
      });
    }

    testWidgets('Does not repeat', (tester) async {
      final outcome = await open(
        tester,
        const EventRepeatDraft(recurring: true, kind: RepeatKind.daily),
      );

      await tap(tester, find.text('Does not repeat'));
      await tap(tester, done());

      expect(outcome.returned, isTrue);
      expect(outcome.result!.recurring, isFalse);
    });
  });

  testWidgets('the eight options are listed once each, in order', (
    tester,
  ) async {
    await open(
      tester,
      const EventRepeatDraft(recurring: false, kind: RepeatKind.daily),
    );

    const labels = [
      'Does not repeat',
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
      'Workdays',
      'Weekends',
      'Public holidays only',
    ];
    var previousTop = double.negativeInfinity;
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      final top = tester.getTopLeft(find.text(label)).dy;
      expect(top, greaterThan(previousTop), reason: '$label is out of order');
      previousTop = top;
    }
  });

  testWidgets('weekly with no weekday disables Done until a day is picked', (
    tester,
  ) async {
    await open(
      tester,
      const EventRepeatDraft(recurring: true, kind: RepeatKind.weekly),
    );

    expect(doneAction(tester), isNull);
    expect(shown('Pick at least one weekday'), findsOneWidget);
    final hint = tester.widget<Text>(shown('Pick at least one weekday'));
    expect(hint.style?.color, colorsOf(tester).error);

    await tap(tester, find.bySemanticsLabel('Monday'));

    expect(doneAction(tester), isNotNull);
    expect(shown('Pick at least one weekday'), findsNothing);
    expect(shown('Mon'), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('Monday'));

    expect(doneAction(tester), isNull);
    expect(shown('Pick at least one weekday'), findsOneWidget);
  });

  testWidgets('switching to weekly from another kind disables Done while '
      'no weekday is picked', (tester) async {
    await open(
      tester,
      const EventRepeatDraft(recurring: true, kind: RepeatKind.daily),
    );
    expect(doneAction(tester), isNotNull);

    await tap(tester, find.text('Weekly'));

    expect(doneAction(tester), isNull);
  });

  testWidgets('the close button returns null', (tester) async {
    final outcome = await open(
      tester,
      const EventRepeatDraft(recurring: true, kind: RepeatKind.daily),
    );

    await tap(tester, find.text('Monthly'));
    await tap(tester, find.byTooltip('Cancel'));

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(EventRepeatSheet), findsNothing);
  });

  testWidgets('the system back returns null', (tester) async {
    final outcome = await open(
      tester,
      const EventRepeatDraft(recurring: true, kind: RepeatKind.daily),
    );

    await tap(tester, find.text('Monthly'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(EventRepeatSheet), findsNothing);
  });

  testWidgets('the interval cannot go below 1 and steps the unit text', (
    tester,
  ) async {
    final outcome = await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.weekly,
        weekdays: {1},
      ),
    );

    expect(shown('1 week'), findsOneWidget);
    expect(stepAction(tester, 'More frequent'), isNull);
    expect(stepAction(tester, 'Less frequent'), isNotNull);

    await tap(tester, find.byTooltip('Less frequent').hitTestable());

    expect(shown('2 weeks'), findsOneWidget);
    expect(shown('1 week'), findsNothing);
    expect(stepAction(tester, 'More frequent'), isNotNull);

    await tap(tester, find.byTooltip('More frequent').hitTestable());

    expect(shown('1 week'), findsOneWidget);
    expect(stepAction(tester, 'More frequent'), isNull);

    await tap(tester, find.byTooltip('Less frequent').hitTestable());
    await tap(tester, done());

    expect(outcome.result!.interval, 2);
  });

  testWidgets('the interval cannot go above 99', (tester) async {
    await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.daily,
        interval: EventRepeatDraft.maxInterval,
      ),
    );

    expect(shown('99 days'), findsOneWidget);
    expect(stepAction(tester, 'Less frequent'), isNull);
    expect(stepAction(tester, 'More frequent'), isNotNull);

    await tap(tester, find.byTooltip('More frequent').hitTestable());

    expect(shown('98 days'), findsOneWidget);
    expect(stepAction(tester, 'Less frequent'), isNotNull);
  });

  testWidgets('the stepper\'s buttons say what they do to the event: minus '
      'makes it more frequent, plus less', (tester) async {
    // A smaller interval is a more frequent event, so the names run against
    // the signs. A screen reader has only the names.
    final outcome = await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.daily,
        interval: 3,
      ),
    );

    IconButton buttonWith(IconData icon) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(icon).hitTestable(),
        matching: find.byType(IconButton),
      ),
    );
    expect(buttonWith(Icons.remove_rounded).tooltip, 'More frequent');
    expect(buttonWith(Icons.add_rounded).tooltip, 'Less frequent');

    await tap(tester, find.byTooltip('More frequent').hitTestable());
    expect(shown('2 days'), findsOneWidget);

    await tap(tester, find.byTooltip('Less frequent').hitTestable());
    await tap(tester, find.byTooltip('Less frequent').hitTestable());
    expect(shown('4 days'), findsOneWidget);

    await tap(tester, done());
    expect(outcome.result!.interval, 4);
  });

  testWidgets('the unit follows the kind', (tester) async {
    await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.daily,
        interval: 2,
        weekdays: {1},
      ),
    );

    expect(shown('2 days'), findsOneWidget);
    await tap(tester, find.text('Weekly'));
    expect(shown('2 weeks'), findsOneWidget);
    await tap(tester, find.text('Monthly'));
    expect(shown('2 months'), findsOneWidget);
    await tap(tester, find.text('Yearly'));
    expect(shown('2 years'), findsOneWidget);
    await tap(tester, find.text('Workdays'));
    expect(shown('Repeat every'), findsNothing);
  });

  testWidgets('the weekday caption reads the picked days back', (
    tester,
  ) async {
    await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.weekly,
        weekdays: {4, 1},
      ),
    );

    expect(find.text('Mon, Thu'), findsOneWidget);
    final caption = tester.widget<Text>(find.text('Mon, Thu'));
    expect(caption.style?.color, colorsOf(tester).onSurfaceVariant);

    await tap(tester, find.bySemanticsLabel('Friday'));

    expect(find.text('Mon, Thu, Fri'), findsOneWidget);
    expect(find.text('Mon, Thu'), findsNothing);
  });

  testWidgets('the weekday cells carry the full day name and selection', (
    tester,
  ) async {
    await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.weekly,
        weekdays: {1, 4},
      ),
    );

    for (final name in weekdayNames) {
      expect(find.bySemanticsLabel(name), findsOneWidget);
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Monday')),
      matchesSemantics(
        label: 'Monday',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tuesday')),
      matchesSemantics(
        label: 'Tuesday',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    final letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    var previousLeft = double.negativeInfinity;
    for (var i = 0; i < 7; i++) {
      final cell = find.descendant(
        of: find.bySemanticsLabel(weekdayNames[i]),
        matching: find.text(letters[i]),
      );
      expect(cell, findsOneWidget);
      final left = tester.getTopLeft(cell).dx;
      expect(left, greaterThan(previousLeft));
      previousLeft = left;
      expect(
        tester.getSize(find.bySemanticsLabel(weekdayNames[i])).height,
        greaterThanOrEqualTo(64),
      );
    }
  });

  testWidgets('the sheet keeps one height across kinds, weekdays, the end '
      'date and the switch', (tester) async {
    await open(
      tester,
      EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.daily,
        endDate: DateTime.utc(2026, 12, 31),
      ),
    );
    final height = sheetHeight(tester);
    expect(height, lessThan(surface.height * 0.92));

    void check(String step) {
      expect(sheetHeight(tester), height, reason: 'moved after $step');
    }

    await tap(tester, find.text('Weekly'));
    check('weekly with no weekday');
    expect(shown('Pick at least one weekday'), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('Monday'));
    check('one weekday');

    for (final name in weekdayNames.skip(1)) {
      await tap(tester, find.bySemanticsLabel(name));
    }
    check('seven weekdays');
    expect(find.text('Mon, Tue, Wed, Thu, Fri, Sat, Sun'), findsNWidgets(2));

    await tap(tester, find.byTooltip('Remove end date').hitTestable());
    check('clearing the end date');
    expect(find.text('Never'), findsOneWidget);

    await tap(tester, shown('Also before the start date'));
    check('switching retroactive on');

    for (final label in [
      'Monthly',
      'Yearly',
      'Workdays',
      'Weekends',
      'Public holidays only',
      'Does not repeat',
      'Daily',
    ]) {
      await tap(tester, find.text(label));
      check(label);
    }
  });

  testWidgets('the Ends row clears back to Never', (tester) async {
    final outcome = await open(
      tester,
      EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.monthly,
        endDate: DateTime.utc(2026, 10, 30),
      ),
    );

    expect(shown('Oct 30, 2026'), findsOneWidget);
    expect(find.text('Never'), findsNothing);

    await tap(tester, find.byTooltip('Remove end date').hitTestable());

    expect(find.text('Never'), findsOneWidget);
    expect(shown('Oct 30, 2026'), findsNothing);
    expect(find.byTooltip('Remove end date').hitTestable(), findsNothing);

    await tap(tester, done());

    expect(outcome.result!.endDate, isNull);
  });

  testWidgets('the retroactive switch round-trips and names the start date', (
    tester,
  ) async {
    final outcome = await open(
      tester,
      const EventRepeatDraft(recurring: true, kind: RepeatKind.monthly),
    );

    expect(
      shown('Shows on matching days before Sep 25, 2026'),
      findsOneWidget,
    );
    final toggle = tester.widget<Switch>(find.byType(Switch).hitTestable());
    expect(toggle.value, isFalse);

    await tap(tester, shown('Also before the start date'));

    expect(
      tester.widget<Switch>(find.byType(Switch).hitTestable()).value,
      isTrue,
    );

    await tap(tester, done());

    expect(outcome.result!.retroactive, isTrue);
  });

  testWidgets('the retroactive hint reads Also in earlier years for yearly', (
    tester,
  ) async {
    await open(
      tester,
      const EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.yearly,
        retroactive: true,
      ),
    );

    expect(find.text('Also in earlier years'), findsOneWidget);
    expect(
      shown('Shows on matching days before Sep 25, 2026'),
      findsNothing,
    );
    expect(
      tester.widget<Switch>(find.byType(Switch).hitTestable()).value,
      isTrue,
    );

    await tap(tester, find.text('Monthly'));

    expect(find.text('Also in earlier years'), findsNothing);
    expect(
      shown('Shows on matching days before Sep 25, 2026'),
      findsOneWidget,
    );
  });

  testWidgets('the retroactive switch is offered for every recurring kind', (
    tester,
  ) async {
    await open(
      tester,
      const EventRepeatDraft(recurring: false, kind: RepeatKind.daily),
    );
    expect(shown('Also before the start date'), findsNothing);

    for (final label in [
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
      'Workdays',
      'Weekends',
      'Public holidays only',
    ]) {
      await tap(tester, find.text(label));
      expect(
        shown('Also before the start date'),
        findsOneWidget,
        reason: '$label lost the switch',
      );
      expect(shown('Ends'), findsOneWidget, reason: '$label lost Ends');
    }
  });

  testWidgets('picking a kind keeps interval, weekdays, end date and '
      'retroactive', (tester) async {
    final endDate = DateTime.utc(2026, 12, 31);
    final outcome = await open(
      tester,
      EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.weekly,
        interval: 3,
        weekdays: const {1, 4},
        endDate: endDate,
        retroactive: true,
      ),
    );

    await tap(tester, find.text('Monthly'));
    await tap(tester, find.text('Does not repeat'));
    await tap(tester, find.text('Workdays'));
    await tap(tester, find.text('Yearly'));
    await tap(tester, done());

    final result = outcome.result!;
    expect(result.recurring, isTrue);
    expect(result.kind, RepeatKind.yearly);
    expect(result.interval, 3);
    expect(result.weekdays, {1, 4});
    expect(result.endDate, endDate);
    expect(result.retroactive, isTrue);
  });

  testWidgets('the returned weekday set is unmodifiable and the caller\'s '
      'set is never touched', (tester) async {
    final callerWeekdays = <int>{1};
    final outcome = await open(
      tester,
      EventRepeatDraft(
        recurring: true,
        kind: RepeatKind.weekly,
        weekdays: callerWeekdays,
      ),
    );

    await tap(tester, find.bySemanticsLabel('Thursday'));
    await tap(tester, find.bySemanticsLabel('Monday'));
    await tap(tester, done());

    expect(callerWeekdays, {1});
    final result = outcome.result!;
    expect(result.weekdays, {4});
    expect(() => result.weekdays.add(2), throwsUnsupportedError);
  });

  group('the template variant', () {
    const templateHint = 'Also on matching days before the day it is added';
    const datedHint = 'Shows on matching days before Sep 25, 2026';
    const recurringLabels = [
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
      'Workdays',
      'Weekends',
    ];
    const oneTime = EventRepeatDraft(recurring: false, kind: RepeatKind.daily);

    testWidgets('lists seven options in order: Public holidays only is not '
        'offered', (tester) async {
      await open(tester, oneTime, forTemplate: true);

      var previousTop = double.negativeInfinity;
      for (final label in ['Does not repeat', ...recurringLabels]) {
        expect(find.text(label), findsOneWidget);
        final top = tester.getTopLeft(find.text(label)).dy;
        expect(top, greaterThan(previousTop), reason: '$label is out of order');
        previousTop = top;
      }
      expect(find.text('Public holidays only'), findsNothing);
    });

    testWidgets('has no Ends row for any kind and keeps the before-start '
        'switch', (tester) async {
      await open(tester, oneTime, forTemplate: true);
      expect(shown('Also before the start date'), findsNothing);

      for (final label in recurringLabels) {
        await tap(tester, find.text(label));
        // Nowhere in the tree: the copy that sizes the area has no Ends row
        // either, so no room is kept for one.
        expect(find.text('Ends'), findsNothing, reason: '$label offers Ends');
        expect(find.text('Never'), findsNothing, reason: '$label offers Ends');
        expect(
          shown('Also before the start date'),
          findsOneWidget,
          reason: '$label lost the switch',
        );
      }
    });

    testWidgets('a draft that arrives with an end date shows none and hands '
        'it back untouched', (tester) async {
      final endDate = DateTime.utc(2026, 12, 31);
      final outcome = await open(
        tester,
        EventRepeatDraft(
          recurring: true,
          kind: RepeatKind.monthly,
          endDate: endDate,
        ),
        forTemplate: true,
      );

      expect(find.text('Ends'), findsNothing);
      expect(find.byTooltip('Remove end date'), findsNothing);
      expect(find.text('Dec 31, 2026'), findsNothing);

      await tap(tester, done());

      expect(outcome.result!.endDate, endDate);
    });

    testWidgets('the before-start switch reads the template hint and never '
        'names the start date', (tester) async {
      await open(
        tester,
        const EventRepeatDraft(recurring: true, kind: RepeatKind.monthly),
        forTemplate: true,
      );

      expect(shown(templateHint), findsOneWidget);
      expect(find.text(datedHint), findsNothing);

      await tap(tester, find.text('Yearly'));

      expect(shown('Also in earlier years'), findsOneWidget);
      expect(shown(templateHint), findsNothing);

      for (final label in ['Daily', 'Weekly', 'Workdays', 'Weekends']) {
        await tap(tester, find.text(label));
        expect(shown(templateHint), findsOneWidget, reason: label);
        expect(find.text(datedHint), findsNothing, reason: label);
      }
    });

    testWidgets('no weekday is pre-selected, so Weekly keeps Done disabled '
        'until one is picked', (tester) async {
      final outcome = await open(tester, oneTime, forTemplate: true);
      expect(doneAction(tester), isNotNull);

      await tap(tester, find.text('Weekly'));

      expect(doneAction(tester), isNull);
      expect(shown('Pick at least one weekday'), findsOneWidget);
      for (final name in weekdayNames) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(name)),
          matchesSemantics(
            label: name,
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
          reason: '$name is pre-selected',
        );
      }

      await tap(tester, find.bySemanticsLabel('Wednesday'));

      expect(doneAction(tester), isNotNull);
      expect(shown('Pick at least one weekday'), findsNothing);
      expect(shown('Wed'), findsOneWidget);

      await tap(tester, done());

      final result = outcome.result!;
      expect(result.recurring, isTrue);
      expect(result.kind, RepeatKind.weekly);
      expect(result.weekdays, {3});
    });

    testWidgets('the interval and the switch round-trip through Done', (
      tester,
    ) async {
      final outcome = await open(
        tester,
        const EventRepeatDraft(recurring: true, kind: RepeatKind.monthly),
        forTemplate: true,
      );

      expect(shown('1 month'), findsOneWidget);
      await tap(tester, find.byTooltip('Less frequent').hitTestable());
      expect(shown('2 months'), findsOneWidget);
      await tap(tester, shown('Also before the start date'));
      await tap(tester, done());

      final result = outcome.result!;
      expect(result.recurring, isTrue);
      expect(result.kind, RepeatKind.monthly);
      expect(result.interval, 2);
      expect(result.retroactive, isTrue);
      expect(result.endDate, isNull);
      expect(find.byType(EventRepeatSheet), findsNothing);
    });

    testWidgets('the close button returns null', (tester) async {
      final outcome = await open(tester, oneTime, forTemplate: true);

      await tap(tester, find.text('Monthly'));
      await tap(tester, find.byTooltip('Cancel'));

      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    });

    testWidgets('the sheet keeps one height across kinds, weekdays and the '
        'switch', (tester) async {
      await open(
        tester,
        const EventRepeatDraft(recurring: true, kind: RepeatKind.daily),
        forTemplate: true,
      );
      final height = sheetHeight(tester);
      expect(height, lessThan(surface.height * 0.92));

      void check(String step) {
        expect(sheetHeight(tester), height, reason: 'moved after $step');
      }

      await tap(tester, find.text('Weekly'));
      check('weekly with no weekday');
      expect(shown('Pick at least one weekday'), findsOneWidget);

      for (final name in weekdayNames) {
        await tap(tester, find.bySemanticsLabel(name));
      }
      check('seven weekdays');

      await tap(tester, shown('Also before the start date'));
      check('switching retroactive on');

      for (final label in [
        'Monthly',
        'Yearly',
        'Workdays',
        'Weekends',
        'Does not repeat',
        'Daily',
      ]) {
        await tap(tester, find.text(label));
        check(label);
      }
    });

    testWidgets('it is shorter than the editor\'s sheet by exactly the two '
        'rows it never shows', (tester) async {
      const draft = EventRepeatDraft(recurring: true, kind: RepeatKind.daily);
      await open(tester, draft);
      final editorHeight = sheetHeight(tester);
      await tap(tester, find.byTooltip('Cancel'));

      await open(tester, draft, forTemplate: true);

      // The Public holidays only row and the Ends row, each with the
      // hairline that came with it.
      expect(
        editorHeight - sheetHeight(tester),
        2 * (FormMetrics.rowMinHeight + 1),
      );
    });

    testWidgets('without forTemplate the sheet is the editor\'s: eight '
        'kinds, Ends and the dated hint', (tester) async {
      await open(
        tester,
        const EventRepeatDraft(recurring: true, kind: RepeatKind.monthly),
      );

      expect(find.text('Public holidays only'), findsOneWidget);
      expect(shown('Ends'), findsOneWidget);
      expect(shown('Never'), findsOneWidget);
      expect(shown(datedHint), findsOneWidget);
      expect(find.text(templateHint), findsNothing);
    });

    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out '
        'without overflow, the hint in full', (tester) async {
      await initializeDateFormatting('de');
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => EventRepeatSheet.show(
                  context,
                  draft: const EventRepeatDraft(
                    recurring: true,
                    kind: RepeatKind.weekly,
                    weekdays: {1, 4},
                  ),
                  startDate: startDate,
                  appearance: const CalendarAppearance(),
                  forTemplate: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sheetHeight(tester), lessThanOrEqualTo(780 * 0.92));

      // The visible copy is the later of the two; the first only sizes.
      const hint = 'Auch an passenden Tagen vor dem Tag des Hinzufügens';
      final shownHint = find.text(hint).last;
      await tester.ensureVisible(shownHint);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(shownHint);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      // Wrapped under the switch's label, inside the group.
      expect(tester.getSize(shownHint).height, greaterThan(18 * 2.0));
      expect(
        tester.getRect(shownHint).right,
        lessThanOrEqualTo(360 - RowMetrics.groupInset),
      );
      expect(find.text('Endet'), findsNothing);
      expect(find.text('Nur an Feiertagen'), findsNothing);
    });

    testWidgets('German at text scale 2.0 on a 360 × 780 phone: stepping the '
        'interval from 1 to 12 moves neither button, the label stays whole '
        'under no stepper, and the sheet keeps its height', (tester) async {
      await initializeDateFormatting('de');
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => EventRepeatSheet.show(
                  context,
                  draft: const EventRepeatDraft(
                    recurring: true,
                    kind: RepeatKind.weekly,
                    weekdays: {1, 4},
                  ),
                  startDate: startDate,
                  appearance: const CalendarAppearance(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final height = sheetHeight(tester);

      // The live row's parts are the last of each: the sizer lays its copies
      // out first, one per kind, unseen and under the fold or not.
      Finder less() => find.byTooltip('Häufiger').last;
      Finder more() => find.byTooltip('Seltener').last;
      Finder label() => find.text('Wiederholen alle').last;
      Future<void> reveal(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }

      await reveal(label());
      // The label is whole — never broken inside a word while its row can
      // hold the word; the test font, a full em a glyph, makes "Wiederholen"
      // wider than the row itself at this scale, and then the label is the
      // row's whole width — and has the stepper under it, not beside it.
      void expectLabelWholeOverTheStepper() {
        final paragraph = tester.renderObject<RenderParagraph>(label());
        final rowWidth =
            tester.getSize(find.byType(FormStepperRow).last).width -
            RowMetrics.groupInset;
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(
            math.min(
                  paragraph.getMinIntrinsicWidth(double.infinity),
                  rowWidth,
                ) -
                0.01,
          ),
        );
        expect(
          tester.getRect(less()).top,
          greaterThanOrEqualTo(tester.getRect(label()).bottom),
        );
      }

      expectLabelWholeOverTheStepper();
      expect(shown('1 Woche'), findsOneWidget);
      // Where the buttons stand across the row: the value box is sized for
      // "99 Wochen" from the start. (Their height on the row is the test
      // font's to vary: a two-digit "Wochen" is wider than the row can give
      // the box here and wraps inside it, which a phone's font never does.)
      final lessLeft = tester.getRect(less()).left;
      final moreLeft = tester.getRect(more()).left;
      expect(
        tester.getRect(more()).right,
        360 - RowMetrics.groupInset,
        reason: 'the stepper is end-aligned',
      );

      for (var interval = 2; interval <= 12; interval++) {
        await reveal(more());
        await tester.tap(more());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$interval');
        expect(shown('$interval Wochen'), findsOneWidget);
        expect(sheetHeight(tester), height, reason: 'moved at $interval');
        expect(tester.getRect(less()).left, lessLeft, reason: '$interval');
        expect(tester.getRect(more()).left, moreLeft, reason: '$interval');
        expectLabelWholeOverTheStepper();
      }

      for (final kind in ['Monatlich', 'Täglich', 'Jährlich', 'Wöchentlich']) {
        await reveal(find.text(kind));
        await tester.tap(find.text(kind));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: kind);
        expect(sheetHeight(tester), height, reason: 'moved after $kind');
      }
    });
  });

  test('the draft compares by value with the weekday set unordered', () {
    final a = EventRepeatDraft(
      recurring: true,
      kind: RepeatKind.weekly,
      weekdays: const {1, 4},
      endDate: DateTime.utc(2026, 12, 31),
    );
    final b = EventRepeatDraft(
      recurring: true,
      kind: RepeatKind.weekly,
      weekdays: const {4, 1},
      endDate: DateTime.utc(2026, 12, 31),
    );

    expect(a, b);
    expect(a.copyWith(clearEndDate: true).endDate, isNull);
    expect(a.copyWith(kind: RepeatKind.daily), isNot(b));
    expect(a.isValid, isTrue);
    expect(a.copyWith(weekdays: const {}).isValid, isFalse);
    expect(
      a.copyWith(weekdays: const {}, recurring: false).isValid,
      isTrue,
    );
    expect(a.copyWith(weekdays: const {}, kind: RepeatKind.daily).isValid, isTrue);
    for (final kind in RepeatKind.values) {
      expect(
        kind.supportsInterval,
        const {
          RepeatKind.daily,
          RepeatKind.weekly,
          RepeatKind.monthly,
          RepeatKind.yearly,
        }.contains(kind),
      );
    }
  });
}

class _Outcome {
  bool returned = false;
  EventRepeatDraft? result;

  void record(EventRepeatDraft? value) {
    returned = true;
    result = value;
  }
}
