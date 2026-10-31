import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_more_categories_sheet.dart';

import '../goldens/support/golden_fonts.dart';

class _Outcome {
  ReportSheetResult? result;
  bool returned = false;
}

/// The "n more categories" sheet on its own: the groups it is handed, their
/// folds, what a pick closes it with, and the filler's dismissals.
void main() {
  setUpAll(loadGoldenFonts);

  setUp(() {
    CalendarCategories.updateCache([
      for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: seed.kind.name,
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: index,
          isBuiltIn: true,
        ),
    ]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  DateTime march(int day) => DateTime.utc(2026, 3, day);
  final today = DateTime.utc(2026, 10, 30);

  /// The card's seven, one one-off each; they never reach the sheet.
  const first = [
    'gym',
    'cardio',
    'rest',
    'holiday',
    'competition',
    'measurement',
    'mobility',
  ];

  CalendarEvent oneOff(String categoryId, int i) => CalendarEvent(
    id: 'e-$categoryId-$i',
    title: '$categoryId ${i + 1}',
    categoryId: categoryId,
    startDate: march(1 + i),
    rule: const OneTimeRecurrence(),
  );

  final routine = CalendarEvent(
    id: 'e-routine',
    title: 'Stretch',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 7 * 60, durationMinutes: 30),
    tracksPresence: true,
  );

  ReportCategoryGroup group(String categoryId, List<ReportRow> rows) =>
      ReportCategoryGroup(
        categoryId: categoryId,
        count: rows.length,
        minutes: 0,
        missed: 0,
        rows: rows,
      );

  /// Nine groups as the report folds them: the card's seven, then Birthday
  /// with [birthdays] one-offs and Other with a routine's aggregate — or,
  /// with [others], that many one-offs instead.
  ({List<ReportCategoryGroup> groups, Map<String, CalendarEvent> events}) nine({
    int birthdays = 30,
    int others = 0,
  }) {
    final events = <String, CalendarEvent>{routine.id: routine};
    final groups = <ReportCategoryGroup>[];
    for (final id in first) {
      final event = oneOff(id, 0);
      events[event.id] = event;
      groups.add(group(id, [ReportDatedRow(eventId: event.id, day: march(1))]));
    }
    final rows = <ReportRow>[];
    for (var i = 0; i < birthdays; i++) {
      final event = oneOff('birthday', i);
      events[event.id] = event;
      rows.add(ReportDatedRow(eventId: event.id, day: march(1 + i)));
    }
    groups.add(group('birthday', rows));
    final otherRows = <ReportRow>[];
    for (var i = 0; i < others; i++) {
      final event = oneOff('other', i);
      events[event.id] = event;
      otherRows.add(ReportDatedRow(eventId: event.id, day: march(1 + i)));
    }
    groups.add(
      group('other', [
        if (others == 0)
          ReportRoutineRow(
            eventId: routine.id,
            attended: 20,
            total: 31,
            minutes: 600,
            latestDay: march(31),
          ),
        ...otherRows,
      ]),
    );
    return (groups: groups, events: events);
  }

  Future<_Outcome> openSheet(
    WidgetTester tester, {
    List<ReportCategoryGroup>? groups,
    Map<String, CalendarEvent>? events,
    int? largest,
    Locale locale = const Locale('en'),
    double? textScale,
    Brightness brightness = Brightness.light,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    final seeded = nine();
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScale == null
                ? MediaQuery.of(context).textScaler
                : TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                outcome.result = await ReportMoreCategoriesSheet.show(
                  context,
                  groups: (groups ?? seeded.groups).skip(7).toList(),
                  events: events ?? seeded.events,
                  labels: ReportLabels(AppLocalizations.of(context)!),
                  today: today,
                  spansMonths: false,
                  use24Hour: true,
                  largest: largest,
                );
                outcome.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportMoreCategoriesSheet), findsOneWidget);
    return outcome;
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);
  Finder header(String categoryId) =>
      byId(SemanticsIds.reportGroup('categories', categoryId));
  Finder birthday(int i) =>
      byId(SemanticsIds.reportRow('e-birthday-$i', march(1 + i)));

  ScrollController scroll(WidgetTester tester) => tester
      .widget<CustomScrollView>(
        find.descendant(
          of: byId(SemanticsIds.reportMoreList),
          matching: find.byType(CustomScrollView),
        ),
      )
      .controller!;

  Finder disclosure(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(FormActionRow));

  testWidgets('lists the groups past the card\'s seven under its title and '
      'its ✕, none of the seven', (tester) async {
    await openSheet(tester);
    expect(find.text('More categories'), findsOneWidget);
    expect(byId(SemanticsIds.reportMoreClose), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(header('birthday'), findsOneWidget);
    expect(header('other'), findsOneWidget);
    for (final id in first) {
      expect(header(id), findsNothing, reason: id);
    }
    expect(find.byType(Scrollable), findsNWidgets(1));
  });

  testWidgets('a header tap closes its group and a second opens it', (
    tester,
  ) async {
    await openSheet(tester);
    expect(birthday(0), findsOneWidget);
    await tester.tap(header('birthday'));
    await tester.pump();
    expect(birthday(0), findsNothing);
    expect(find.text('26 more'), findsNothing);
    expect(header('other'), findsOneWidget);
    await tester.tap(header('birthday'));
    await tester.pump();
    expect(birthday(0), findsOneWidget);
  });

  testWidgets('"n more" shows every row; "Show less" deep in a long group '
      'above another keeps "n more" under the finger in the first frame (S)', (
    tester,
  ) async {
    // Other's 30 rows expanded under Birthday's: the room below that lets
    // Birthday's "Show less" sit mid-sheet.
    final seeded = nine(others: 30);
    await openSheet(tester, groups: seeded.groups, events: seeded.events);
    for (var i = 0; i < 4; i++) {
      expect(birthday(i), findsOneWidget);
    }
    expect(birthday(4), findsNothing);
    final more = byId(SemanticsIds.reportGroupMore('categories', 'birthday'));
    await tester.tap(more);
    await tester.pump();
    expect(birthday(4), findsOneWidget);
    final otherMore = byId(SemanticsIds.reportGroupMore('categories', 'other'));
    final controller = scroll(tester);
    // Jumps, never drags: a drag that reaches an edge leaves the stretch
    // overscroll easing back, and every rect read under it is scaled.
    Future<void> reveal(Finder finder, {required int direction}) async {
      while (finder.evaluate().isEmpty) {
        controller.jumpTo(controller.offset + direction * 300);
        await tester.pump();
      }
    }

    await reveal(otherMore, direction: 1);
    await tester.ensureVisible(otherMore);
    await tester.pump();
    await tester.tap(otherMore);
    await tester.pump();

    await reveal(more, direction: -1);
    // Mid-sheet. Twice: the lists estimate their extent from the rows
    // built, and the first jump changes which are; the second lands within
    // a few pixels, and the finger is where it lands.
    for (var i = 0; i < 2; i++) {
      controller.jumpTo(controller.offset + tester.getRect(more).top - 400);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final less = tester.getRect(more);
    final y = less.top;
    expect(y, inInclusiveRange(300, 500));
    expect(birthday(4), findsNothing, reason: 'far above the viewport');
    final otherHeader = tester.getRect(header('other'));

    await tester.tapAt(less.center);
    await tester.pump();
    expect(
      find.descendant(of: more, matching: find.text('26 more')),
      findsOneWidget,
    );
    expect(tester.getRect(more).top, closeTo(y, 1));
    expect(tester.getRect(header('other')).top, closeTo(otherHeader.top, 1));
    await tester.pumpAndSettle();
    expect(tester.getRect(more).top, closeTo(y, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long group closed by its header at the end of the sheet '
      'keeps the header where it was', (tester) async {
    final seeded = nine(others: 8);
    await openSheet(tester, groups: seeded.groups, events: seeded.events);
    final controller = scroll(tester);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(disclosure('4 more'));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
    }
    final offset = controller.offset;
    expect(offset, greaterThan(0));
    final rect = tester.getRect(header('other'));
    expect(rect.top, greaterThan(0));

    await tester.tap(header('other'));
    await tester.pump();
    expect(byId(SemanticsIds.reportRow('e-other-0', march(1))), findsNothing);
    expect(controller.offset, offset);
    expect(tester.getRect(header('other')), rect);
    await tester.pumpAndSettle();
    expect(tester.getRect(header('other')), rect);
  });

  testWidgets('the meters are a share of the largest handed over, or of the '
      'sheet\'s own largest without one', (tester) async {
    double fraction(String categoryId) => tester
        .widget<FormMeterRow>(
          find.byWidgetPredicate(
            (w) =>
                w is FormMeterRow &&
                w.identifier ==
                    SemanticsIds.reportGroup('categories', categoryId),
          ),
        )
        .fraction!;

    final seeded = nine(birthdays: 1);
    await openSheet(
      tester,
      groups: seeded.groups,
      events: seeded.events,
      largest: 4,
    );
    expect(fraction('birthday'), 0.25);
    await tester.pumpWidget(const SizedBox.shrink());

    await openSheet(tester, groups: seeded.groups, events: seeded.events);
    expect(fraction('birthday'), 1.0);
  });

  testWidgets('a dated row closes the sheet with its event and day', (
    tester,
  ) async {
    final outcome = await openSheet(tester);
    await tester.tap(birthday(2));
    await tester.pumpAndSettle();
    expect(outcome.returned, isTrue);
    expect(outcome.result, ReportSheetPick('e-birthday-2', march(3)));
    expect(find.byType(ReportMoreCategoriesSheet), findsNothing);
  });

  testWidgets('a routine row closes the sheet on its latest day', (
    tester,
  ) async {
    final outcome = await openSheet(tester);
    await tester.tap(byId(SemanticsIds.reportRoutine(routine.id)));
    await tester.pumpAndSettle();
    expect(outcome.result, ReportSheetPick(routine.id, march(31)));
  });

  testWidgets('a group\'s Show as list, past 200 rows, closes the sheet with '
      'its category', (tester) async {
    final seeded = nine(birthdays: 201);
    final outcome = await openSheet(
      tester,
      groups: seeded.groups,
      events: seeded.events,
    );
    await tester.tap(disclosure('197 more'));
    await tester.pump();
    final list = byId(SemanticsIds.reportGroupList('categories', 'birthday'));
    await tester.scrollUntilVisible(list, 600);
    await tester.tap(list);
    await tester.pumpAndSettle();
    expect(outcome.result, const ReportSheetShowList('birthday'));
  });

  testWidgets('✕, the barrier and system back close it with null', (
    tester,
  ) async {
    var outcome = await openSheet(tester);
    await tester.tap(byId(SemanticsIds.reportMoreClose));
    await tester.pumpAndSettle();
    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);

    outcome = await openSheet(tester);
    // Above the sheet's box, on the scrim.
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);

    outcome = await openSheet(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('German at 2.0 on 360 × 780 lays out with no exception; the '
      'dark theme too', (tester) async {
    await openSheet(tester, locale: const Locale('de'), textScale: 2.0);
    expect(find.text('Weitere Kategorien'), findsOneWidget);
    await tester.tap(disclosure('26 weitere'));
    await tester.pump();
    await tester.scrollUntilVisible(header('other'), 300);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(header('other'))).pop();
    await tester.pumpAndSettle();

    await openSheet(tester, brightness: Brightness.dark);
    expect(header('birthday'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
