import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/analytics_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_analytics_cards.dart';
import 'package:anta/widgets/report_group_stack.dart';

import '../goldens/support/golden_fonts.dart';

/// The report's Goals card (S4 §2.2) drawn alone, with Roboto loaded so the
/// template rule measures the real font: every state's glyph and caption,
/// the meter's share and colour, one node per row, the tap, and the row
/// heights of §2.2's table at 1.0, 1.3 and 2.0 in en, de and ro, light and
/// dark. 4 November 2026 is a Wednesday; its week runs Monday 2 to Sunday 8.
void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    await initializeDateFormatting();
  });

  final today = DateTime.utc(2026, 11, 4);
  final thisWeek = (
    start: DateTime.utc(2026, 11, 2),
    end: DateTime.utc(2026, 11, 8),
  );
  final lastWeek = (
    start: DateTime.utc(2026, 10, 26),
    end: DateTime.utc(2026, 11, 1),
  );
  final nextWeek = (
    start: DateTime.utc(2026, 11, 9),
    end: DateTime.utc(2026, 11, 15),
  );
  final november = (
    start: DateTime.utc(2026, 11, 1),
    end: DateTime.utc(2026, 11, 30),
  );

  /// The four weeks Monday 5 October to Sunday 1 November.
  final fourWeeks = [
    for (var i = 0; i < 4; i++)
      (
        start: DateTime.utc(2026, 10, 5 + 7 * i),
        end: DateTime.utc(2026, 10, 11 + 7 * i),
      ),
  ];

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

  CalendarReport reportOf(
    DateRange span,
    List<ReportGoal> goals, {
    DateTime? on,
  }) {
    final day = on ?? today;
    return CalendarReport(
      span: span,
      today: day,
      tense: CalendarReport.tenseOf(span: span, today: day),
      countedTo: CalendarReport.countedToOf(span: span, today: day),
      events: const {},
      tiles: const [],
      skippedDays: 0,
      aheadCount: 0,
      categories: const [],
      missed: const [],
      ahead: const [],
      goals: goals,
    );
  }

  ReportGoalPeriod period(DateRange range, int value, GoalState state) =>
      ReportGoalPeriod(
        start: range.start,
        end: range.end,
        value: value,
        expected: 0,
        state: state,
      );

  ReportGoal atLeast(
    String categoryId,
    List<ReportGoalPeriod> periods, {
    int streak = 0,
  }) => ReportGoal(
    categoryId: categoryId,
    measure: ReportMeasure.count,
    target: const ReportTarget(
      kind: TargetKind.atLeast,
      value: 3,
      period: TargetPeriod.week,
    ),
    periods: periods,
    streak: streak,
  );

  ReportGoal atMostHours(String categoryId, List<ReportGoalPeriod> periods) =>
      ReportGoal(
        categoryId: categoryId,
        measure: ReportMeasure.hours,
        target: const ReportTarget(
          kind: TargetKind.atMost,
          value: 40 * 60,
          period: TargetPeriod.week,
        ),
        periods: periods,
      );

  ReportGoal maxGap(String categoryId, ReportGapState? gap) => ReportGoal(
    categoryId: categoryId,
    measure: ReportMeasure.lastSeen,
    target: const ReportTarget(kind: TargetKind.maxGap, value: 14),
    gap: gap,
  );

  ReportGapState gapOf(int days, GapState state) =>
      ReportGapState(daysSince: days, limit: 14, state: state);

  // One goal per built-in category, every current state between them.
  final onPace = atLeast('gym', [
    period(thisWeek, 2, GoalState.onPace),
  ], streak: 4);
  final met = atLeast('cardio', [period(thisWeek, 3, GoalState.met)]);
  final behind = atLeast('rest', [period(thisWeek, 0, GoalState.behind)]);
  final over = atMostHours('measurement', [
    period(thisWeek, 44 * 60, GoalState.over),
  ]);
  final notDue = atLeast('mobility', [period(thisWeek, 0, GoalState.notDue)]);
  final within = maxGap('competition', gapOf(3, GapState.within));
  final due = maxGap('birthday', gapOf(12, GapState.due));
  final overdue = maxGap('holiday', gapOf(23, GapState.overdue));
  final never = maxGap('other', null);
  final current = reportOf(thisWeek, [
    onPace,
    met,
    behind,
    over,
    notDue,
    within,
    due,
    overdue,
    never,
  ]);

  // Last week, closed.
  final closedMet = atLeast('gym', [period(lastWeek, 3, GoalState.met)]);
  final closedMissed = atLeast('cardio', [
    period(lastWeek, 1, GoalState.missed),
  ]);
  final closedWithin = atMostHours('measurement', [
    period(lastWeek, 38 * 60, GoalState.met),
  ]);
  final closedOver = atMostHours('rest', [
    period(lastWeek, 44 * 60, GoalState.over),
  ]);
  final past = reportOf(lastWeek, [
    closedMet,
    closedMissed,
    closedWithin,
    closedOver,
  ]);

  // Four past weeks, one missed.
  final periodsMet = atLeast('gym', [
    for (final (i, week) in fourWeeks.indexed)
      period(week, i == 1 ? 1 : 3, i == 1 ? GoalState.missed : GoalState.met),
  ]);
  final fourWeekReport = reportOf(
    (start: fourWeeks.first.start, end: fourWeeks.last.end),
    [periodsMet],
  );

  // A plan.
  final planned = atLeast('gym', [period(nextWeek, 2, GoalState.future)]);
  final future = reportOf(nextWeek, [planned]);

  // A weekly limit in a month view: the week holding today is read.
  final weekInMonth = atMostHours('measurement', [
    period(lastWeek, 50 * 60, GoalState.over),
    period(thisWeek, 31 * 60, GoalState.onPace),
    period(nextWeek, 0, GoalState.future),
  ]);
  final month = reportOf(november, [weekInMonth]);

  final tapped = <ReportGoal>[];

  Future<void> pump(
    WidgetTester tester,
    CalendarReport report, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    bool tappable = true,
    bool Function(ReportGoal goal)? canTap,
    bool boldText = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    tapped.clear();
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
            textScaler: TextScaler.linear(textScale),
            boldText: boldText,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: RowMetrics.groupInset,
              ),
              children: [
                ReportGoalsCard(
                  report: report,
                  labels: ReportLabels(AppLocalizations.of(context)!),
                  onGoalTap: tappable ? tapped.add : null,
                  canTap: canTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  ReportLabels labelsIn(String locale) =>
      ReportLabels(lookupAppLocalizations(Locale(locale)));

  Finder rowOf(ReportGoal goal) => find.ancestor(
    of: find.bySemanticsIdentifier(SemanticsIds.reportGoal(goal.categoryId)),
    matching: find.byType(FormMeterRow),
  );

  FormMeterRow rowWidget(WidgetTester tester, ReportGoal goal) =>
      tester.widget<FormMeterRow>(rowOf(goal));

  /// §2.2's measured goal rows by caption lines, per scale. The table stops
  /// at three lines; a weekly hours limit in a month view ("… left this
  /// week") takes a fourth in Romanian at 2.0, one more caption line by the
  /// same rule.
  final heights = {
    1.0: {1: 66.0, 2: 84.0},
    1.3: {1: 77.4, 2: 100.8},
    2.0: {1: 104.0, 2: 140.0, 3: 176.0, 4: 212.0},
  };

  group('geometry', () {
    for (final scale in heights.keys) {
      testWidgets('at $scale a goal row is §2.2\'s height for its caption '
          'lines, in every locale and both themes', (tester) async {
        final seen = <int>{};
        for (final brightness in Brightness.values) {
          for (final locale in const ['en', 'de', 'ro']) {
            for (final report in [
              current,
              past,
              fourWeekReport,
              future,
              month,
            ]) {
              await pump(
                tester,
                report,
                locale: Locale(locale),
                textScale: scale,
                brightness: brightness,
              );
              for (final goal in report.goals) {
                final lines = rowWidget(tester, goal).captionLines!;
                seen.add(lines);
                expect(
                  heights[scale]!.keys,
                  contains(lines),
                  reason: '${goal.categoryId} in $locale',
                );
                expect(
                  tester.getRect(rowOf(goal)).height,
                  closeTo(heights[scale]![lines]!, 1),
                  reason: '${goal.categoryId} in $locale at $lines lines',
                );
              }
            }
          }
        }
        expect(
          seen,
          containsAll(heights[scale]!.keys),
          reason: 'every row height of the table is drawn',
        );
      });
    }

    testWidgets('en 1.0 pins §2.2: a count row takes one line, the hours '
        'limit two', (tester) async {
      await pump(tester, current);
      expect(tester.getRect(rowOf(onPace)).height, closeTo(66, 1));
      expect(rowWidget(tester, onPace).captionLines, 1);
      await pump(tester, month);
      expect(tester.getRect(rowOf(weekInMonth)).height, closeTo(84, 1));
      expect(rowWidget(tester, weekInMonth).captionLines, 2);
    });

    testWidgets('a refold that changes the value keeps the row height (D)', (
      tester,
    ) async {
      for (final scale in heights.keys) {
        final heightsSeen = <double>{};
        for (final (value, state) in [
          (0, GoalState.notDue),
          (2, GoalState.onPace),
          (3, GoalState.met),
          (8, GoalState.met),
        ]) {
          final goal = atLeast('gym', [
            period(thisWeek, value, state),
          ], streak: value);
          await pump(tester, reportOf(thisWeek, [goal]), textScale: scale);
          heightsSeen.add(tester.getRect(rowOf(goal)).height);
        }
        expect(heightsSeen, hasLength(1), reason: 'at $scale');
      }
    });

    testWidgets('under bold text every caption is measured bold and drawn '
        'whole on its lines', (tester) async {
      for (final locale in const ['en', 'de', 'ro']) {
        for (final scale in heights.keys) {
          for (final report in [current, past, fourWeekReport, future, month]) {
            await pump(
              tester,
              report,
              locale: Locale(locale),
              textScale: scale,
              boldText: true,
            );
            for (final goal in report.goals) {
              final row = rowWidget(tester, goal);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: rowOf(goal),
                  matching: find.text(row.caption!),
                ),
              );
              final reason = '${goal.categoryId} $locale $scale';
              expect(paragraph.text.style?.fontWeight, FontWeight.bold);
              expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
            }
          }
        }
      }
    });

    testWidgets('from 1.6 the leading is the category glyph and the '
        'hairline moves to the glyph indent', (tester) async {
      await pump(tester, current, textScale: 2.0);
      expect(find.byType(EventAvatar), findsNothing);
      expect(find.byType(FormGlyph), findsNWidgets(current.goals.length));
      expect(
        tester.widget<Divider>(find.byType(Divider).first).indent,
        RowMetrics.dividerIndentWithGlyph,
      );

      await pump(tester, current, textScale: 1.3);
      expect(find.byType(EventAvatar), findsNWidgets(current.goals.length));
      expect(find.byType(FormGlyph), findsNothing);
      expect(
        tester.widget<Divider>(find.byType(Divider).first).indent,
        FormMetrics.dividerIndentTitle,
      );
    });

    testWidgets('no built-in category name breaks mid-word', (tester) async {
      for (final locale in const ['en', 'de', 'ro']) {
        for (final scale in heights.keys) {
          await pump(tester, current, locale: Locale(locale), textScale: scale);
          for (final goal in current.goals) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.descendant(
                  of: rowOf(goal),
                  matching: find.text(rowWidget(tester, goal).label),
                ),
                matching: find.byType(RichText),
              ),
            );
            final text = paragraph.text.toPlainText();
            var start = 0;
            for (final word in text.split(' ')) {
              final lines = {
                for (final box in paragraph.getBoxesForSelection(
                  TextSelection(
                    baseOffset: start,
                    extentOffset: start + word.length,
                  ),
                ))
                  box.top,
              };
              expect(
                lines,
                hasLength(1),
                reason: '"$word" broke in $locale at $scale',
              );
              start += word.length + 1;
            }
            expect(paragraph.didExceedMaxLines, isFalse);
          }
        }
      }
    });
  });

  group('states', () {
    (IconData, Color) glyphOf(WidgetTester tester, ReportGoal goal) {
      final glyph = tester.widget<FormTrailingGlyph>(
        find.descendant(
          of: rowOf(goal),
          matching: find.byType(FormTrailingGlyph),
        ),
      );
      return (glyph.icon, glyph.color!);
    }

    for (final brightness in Brightness.values) {
      testWidgets('each state wears its glyph and role, never error red '
          '(${brightness.name})', (tester) async {
        await pump(tester, current, brightness: brightness);
        final scheme = Theme.of(
          tester.element(find.byType(ReportGoalsCard)),
        ).colorScheme;
        final expected = {
          met: (Icons.check_circle_rounded, scheme.primary),
          onPace: (Icons.timelapse_rounded, scheme.onSurfaceVariant),
          within: (Icons.timelapse_rounded, scheme.onSurfaceVariant),
          behind: (Icons.hourglass_bottom_rounded, scheme.onSurfaceVariant),
          due: (Icons.hourglass_bottom_rounded, scheme.onSurfaceVariant),
          over: (Icons.error_outline_rounded, scheme.onSurface),
          overdue: (Icons.error_outline_rounded, scheme.onSurface),
          notDue: (
            Icons.radio_button_unchecked_rounded,
            scheme.onSurfaceVariant,
          ),
          never: (
            Icons.radio_button_unchecked_rounded,
            scheme.onSurfaceVariant,
          ),
        };
        for (final MapEntry(key: goal, value: glyph) in expected.entries) {
          expect(glyphOf(tester, goal), glyph, reason: goal.categoryId);
          expect(glyph.$2, isNot(scheme.error));
        }

        await pump(tester, past, brightness: brightness);
        expect(glyphOf(tester, closedMet).$1, Icons.check_circle_rounded);
        expect(glyphOf(tester, closedMissed).$1, Icons.error_outline_rounded);
        expect(glyphOf(tester, closedWithin).$1, Icons.check_circle_rounded);
        expect(glyphOf(tester, closedOver).$1, Icons.error_outline_rounded);

        await pump(tester, fourWeekReport, brightness: brightness);
        expect(
          glyphOf(tester, periodsMet),
          (Icons.timelapse_rounded, scheme.onSurfaceVariant),
          reason: 'three weeks of four met is a partial result, not a failure',
        );

        await pump(tester, future, brightness: brightness);
        expect(
          glyphOf(tester, planned).$1,
          Icons.radio_button_unchecked_rounded,
        );
      });
    }

    testWidgets('the captions read each state back', (tester) async {
      final en = labelsIn('en');
      String caption(ReportGoal goal) => rowWidget(tester, goal).caption!;

      await pump(tester, current);
      for (final goal in current.goals) {
        expect(caption(goal), en.goalCaption(goal, current));
      }
      expect(caption(onPace), endsWith('in a row'));
      expect(caption(met), isNot(contains('in a row')));
      expect(caption(never), startsWith('None yet'));

      await pump(tester, past);
      expect(caption(closedMet), endsWith('Met'));
      expect(caption(closedMissed), endsWith('Missed'));
      expect(caption(closedWithin), endsWith('Within'));
      expect(caption(closedOver), endsWith('Over'));

      await pump(tester, fourWeekReport);
      expect(
        caption(periodsMet).replaceAll(String.fromCharCode(0xA0), ' '),
        '3 of 4 weeks met',
      );

      await pump(tester, future);
      expect(caption(planned), contains('planned'));

      await pump(tester, month);
      expect(caption(weekInMonth), endsWith('left this week'));
    });

    Finder fillOf(ReportGoal goal, Color color) => find.descendant(
      of: rowOf(goal),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == color,
      ),
    );

    Color colourOf(ReportGoal goal) =>
        CalendarCategories.resolve(goal.categoryId).color;

    double share(WidgetTester tester, ReportGoal goal) {
      final track = Theme.of(
        tester.element(find.byType(ReportGoalsCard)),
      ).colorScheme.rowDivider;
      final fill = fillOf(goal, colourOf(goal));
      if (fill.evaluate().isEmpty) return 0;
      return tester.getSize(fill).width /
          tester.getSize(fillOf(goal, track)).width;
    }

    testWidgets('the meter fills in the category colour in every state, '
        'over included (C)', (tester) async {
      await pump(tester, current);
      // Behind at 0 of 3 draws the bare track; every other share fills.
      for (final goal in [onPace, met, over, within, due, overdue]) {
        expect(fillOf(goal, colourOf(goal)), findsOneWidget);
      }
      for (final goal in current.goals) {
        expect(rowWidget(tester, goal).meterColor, colourOf(goal));
      }
    });

    testWidgets('the meter reads the caption\'s period: value of target, '
        'days of the limit, weeks met of weeks', (tester) async {
      await pump(tester, current);
      expect(share(tester, onPace), closeTo(2 / 3, 0.01));
      expect(share(tester, met), closeTo(1, 0.01));
      expect(share(tester, over), closeTo(1, 0.01), reason: 'clamped');
      expect(share(tester, behind), 0);
      expect(share(tester, overdue), closeTo(1, 0.01), reason: 'clamped');
      expect(share(tester, due), closeTo(12 / 14, 0.01));
      expect(rowWidget(tester, never).fraction, 0);

      await pump(tester, fourWeekReport);
      expect(share(tester, periodsMet), closeTo(3 / 4, 0.01));

      await pump(tester, month);
      expect(
        share(tester, weekInMonth),
        closeTo(31 / 40, 0.01),
        reason: 'the week holding today, not last week\'s 50 h',
      );
    });

    testWidgets('a past week under a monthly goal whose month runs on reads '
        'its pace: the pace glyph and the month\'s share, never "Missed"', (
      tester,
    ) async {
      final midMonth = DateTime.utc(2026, 11, 18);
      final pastWeek = (
        start: DateTime.utc(2026, 11, 9),
        end: DateTime.utc(2026, 11, 15),
      );
      final monthly = ReportGoal(
        categoryId: 'gym',
        measure: ReportMeasure.count,
        target: const ReportTarget(
          kind: TargetKind.atLeast,
          value: 8,
          period: TargetPeriod.month,
        ),
        periods: [period(november, 5, GoalState.onPace)],
      );
      final report = reportOf(pastWeek, [monthly], on: midMonth);
      expect(report.tense, ReportTense.past);
      await pump(tester, report);
      final scheme = Theme.of(
        tester.element(find.byType(ReportGoalsCard)),
      ).colorScheme;
      expect(glyphOf(tester, monthly), (
        Icons.timelapse_rounded,
        scheme.onSurfaceVariant,
      ));
      final caption = rowWidget(tester, monthly).caption!;
      expect(caption, labelsIn('en').goalCaption(monthly, report));
      expect(caption, isNot(contains('Missed')));
      expect(share(tester, monthly), closeTo(5 / 8, 0.01));
    });

    for (final (metWeeks, icon, role, label)
        in <(int, IconData, Color Function(ColorScheme), String)>[
          (4, Icons.check_circle_rounded, (s) => s.primary, 'met'),
          (3, Icons.timelapse_rounded, (s) => s.onSurfaceVariant, 'pace'),
          (0, Icons.error_outline_rounded, (s) => s.onSurface, 'the alarm'),
        ]) {
      testWidgets('$metWeeks of 4 weeks met wears $label\'s glyph and fills '
          '$metWeeks / 4', (tester) async {
        final goal = atLeast('gym', [
          for (final (i, week) in fourWeeks.indexed)
            i < metWeeks
                ? period(week, 3, GoalState.met)
                : period(week, 1, GoalState.missed),
        ]);
        await pump(tester, reportOf(fourWeekReport.span, [goal]));
        final scheme = Theme.of(
          tester.element(find.byType(ReportGoalsCard)),
        ).colorScheme;
        expect(glyphOf(tester, goal), (icon, role(scheme)));
        expect(rowWidget(tester, goal).fraction, closeTo(metWeeks / 4, 0.001));
        expect(
          rowWidget(
            tester,
            goal,
          ).caption!.replaceAll(String.fromCharCode(0xA0), ' '),
          '$metWeeks of 4 weeks met',
        );
      });
    }

    testWidgets('a past month whose last week runs into today counts only '
        'the closed weeks: glyph and meter read met of closed', (tester) async {
      // Today is Sunday 1 November: October's last week ends today, open.
      final october = (
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 31),
      );
      final weeks = [
        for (var i = 0; i < 5; i++)
          (
            start: DateTime.utc(2026, 9, 28 + 7 * i),
            end: DateTime.utc(2026, 10, 4 + 7 * i),
          ),
      ];
      final goal = atLeast('gym', [
        period(weeks[0], 3, GoalState.met),
        period(weeks[1], 3, GoalState.met),
        period(weeks[2], 1, GoalState.missed),
        period(weeks[3], 3, GoalState.met),
        period(weeks[4], 0, GoalState.behind),
      ]);
      final report = reportOf(october, [goal], on: DateTime.utc(2026, 11, 1));
      expect(report.tense, ReportTense.past);
      await pump(tester, report);
      final scheme = Theme.of(
        tester.element(find.byType(ReportGoalsCard)),
      ).colorScheme;
      expect(glyphOf(tester, goal), (
        Icons.timelapse_rounded,
        scheme.onSurfaceVariant,
      ));
      expect(rowWidget(tester, goal).fraction, closeTo(3 / 4, 0.001));
      expect(
        rowWidget(
          tester,
          goal,
        ).caption!.replaceAll(String.fromCharCode(0xA0), ' '),
        '3 of 4 weeks met',
      );
    });
  });

  group('semantics', () {
    testWidgets('one node per row with its id, the spoken label and the '
        'button flag', (tester) async {
      final handle = tester.ensureSemantics();
      for (final locale in const ['en', 'de', 'ro']) {
        await pump(tester, current, locale: Locale(locale));
        final labels = labelsIn(locale);
        for (final goal in current.goals) {
          final node = tester.getSemantics(
            find.bySemanticsIdentifier(
              SemanticsIds.reportGoal(goal.categoryId),
            ),
          );
          final data = node.getSemanticsData();
          final name = CalendarCategories.labelOf(
            CalendarCategories.resolve(goal.categoryId),
            labels.l10n,
          );
          expect(node.childrenCount, 0, reason: 'the row is one node');
          expect(data.label, labels.goalSpoken(name, goal, current));
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
        }
      }
      handle.dispose();
    });

    testWidgets('the spoken label says the state and the streak', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, current);
      expect(
        tester
            .getSemantics(
              find.bySemanticsIdentifier(SemanticsIds.reportGoal('gym')),
            )
            .getSemanticsData()
            .label,
        'Gym, 2 of 3, one more by Sunday, on pace, 4 weeks in a row',
      );
      handle.dispose();
    });

    testWidgets('a tap hands the card its goal; without a callback a row '
        'is no button', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, current);
      await tester.tap(rowOf(over));
      expect(tapped, [over]);

      await pump(tester, current, tappable: false);
      for (final goal in current.goals) {
        final data = tester
            .getSemantics(
              find.bySemanticsIdentifier(
                SemanticsIds.reportGoal(goal.categoryId),
              ),
            )
            .getSemanticsData();
        expect(data.flagsCollection.isButton, isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
      }
      handle.dispose();
    });

    testWidgets('a goal canTap refuses is a read row — no tap, no button — '
        'beside rows that keep theirs (G)', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, current, canTap: (goal) => goal != over);
      for (final goal in current.goals) {
        final data = tester
            .getSemantics(
              find.bySemanticsIdentifier(
                SemanticsIds.reportGoal(goal.categoryId),
              ),
            )
            .getSemanticsData();
        final live = goal != over;
        expect(data.flagsCollection.isButton, live, reason: goal.categoryId);
        expect(data.hasAction(SemanticsAction.tap), live);
        expect(rowWidget(tester, goal).onTap != null, live);
      }
      await tester.tap(rowOf(over), warnIfMissed: false);
      expect(tapped, isEmpty);
      handle.dispose();
    });

    testWidgets('no goals draws nothing', (tester) async {
      await pump(tester, reportOf(thisWeek, const []));
      expect(find.byType(FormMeterRow), findsNothing);
      expect(find.byType(FormRowGroup), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('tap targets, labelled taps and text contrast '
          '(${brightness.name})', (tester) async {
        final handle = tester.ensureSemantics();
        for (final report in [current, past]) {
          await pump(tester, report, brightness: brightness);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        handle.dispose();
      });
    }
  });

  // The Insights and Due soon cards (§2.3, §2.4), on one report that
  // carries both, drawn by the same harness.

  final events = {
    for (final (id, title) in const [
      ('e-car', 'Car service'),
      ('e-pass', 'Passport'),
      ('e-bill', 'Electricity bill'),
      ('e-dent', 'Dentist'),
      ('e-ins', 'Insurance'),
      ('e-rent', 'Rent'),
      ('e-tax', 'Tax return'),
      ('e-phone', 'Phone plan'),
    ])
      id: CalendarEvent(
        id: id,
        title: title,
        categoryId: 'other',
        startDate: DateTime.utc(2026, 1, 1),
        rule: const OneTimeRecurrence(),
      ),
  };

  ReportDueRow dueRow(
    String eventId,
    DateTime day,
    ReportDueKind kind,
    ReportDueState state,
    int days,
  ) => ReportDueRow(
    categoryId: 'other',
    eventId: eventId,
    day: day,
    kind: kind,
    state: state,
    days: days,
  );

  // Every kind and state between them, in the model's order.
  final dueRows = [
    dueRow(
      'e-car',
      DateTime.utc(2026, 10, 3),
      ReportDueKind.gap,
      ReportDueState.overdue,
      32,
    ),
    dueRow(
      'e-pass',
      DateTime.utc(2026, 11, 1),
      ReportDueKind.expiry,
      ReportDueState.overdue,
      3,
    ),
    dueRow(
      'e-bill',
      DateTime.utc(2026, 11, 1),
      ReportDueKind.unmarked,
      ReportDueState.unmarked,
      3,
    ),
    dueRow(
      'e-dent',
      DateTime.utc(2026, 11, 22),
      ReportDueKind.gap,
      ReportDueState.due,
      18,
    ),
    dueRow(
      'e-ins',
      DateTime.utc(2026, 12, 16),
      ReportDueKind.expiry,
      ReportDueState.due,
      42,
    ),
    dueRow(
      'e-rent',
      DateTime.utc(2026, 11, 16),
      ReportDueKind.upcoming,
      ReportDueState.upcoming,
      12,
    ),
    dueRow(
      'e-tax',
      DateTime.utc(2026, 10, 30),
      ReportDueKind.unmarked,
      ReportDueState.unmarked,
      5,
    ),
    dueRow(
      'e-phone',
      DateTime.utc(2026, 11, 21),
      ReportDueKind.upcoming,
      ReportDueState.upcoming,
      17,
    ),
  ];

  /// A short finding, one caption line at 1.0 in English.
  const gapOverdue = ReportInsight(
    rule: InsightRule.d1,
    severity: 3,
    categoryId: 'holiday',
    target: InsightTarget.categoryGroup,
    n1: 23,
    n2: 14,
  );

  /// A longer finding: one caption line at 1.0 in English, two at 1.3.
  final unmarked = ReportInsight(
    rule: InsightRule.d4,
    severity: 2,
    categoryId: 'other',
    eventId: 'e-bill',
    target: InsightTarget.dueSoon,
    day: DateTime.utc(2026, 11, 1),
    n1: 3,
  );

  const lateEvenings = ReportInsight(
    rule: InsightRule.p2,
    severity: 1,
    categoryId: 'gym',
    target: InsightTarget.overviewDays,
    n1: 3,
  );

  /// No one category: the subject is the rule's noun.
  const bills = ReportInsight(
    rule: InsightRule.m1,
    severity: 0,
    target: InsightTarget.dueSoon,
    cents: 18000,
  );

  CalendarReport analyticsReport({
    List<ReportDueRow> dueSoon = const [],
    List<ReportInsight> insights = const [],
    Map<LifeArea, int> balance = const {},
  }) => CalendarReport(
    span: thisWeek,
    today: today,
    tense: CalendarReport.tenseOf(span: thisWeek, today: today),
    countedTo: CalendarReport.countedToOf(span: thisWeek, today: today),
    events: events,
    tiles: const [],
    skippedDays: 0,
    aheadCount: 0,
    categories: const [],
    missed: const [],
    ahead: const [],
    dueSoon: dueSoon,
    insights: insights,
    balance: balance,
  );

  final threeInsights = [gapOverdue, unmarked, lateEvenings];
  final insightReport = analyticsReport(insights: [...threeInsights, bills]);

  Future<void> pumpCard(
    WidgetTester tester,
    Widget Function(ReportLabels labels) card, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    ScrollController? scroll,
    double room = 0,
    Size surface = const Size(360, 780),
    bool boldText = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        // A theme switch between two pumps of one test lands at once, so a
        // colour read right after it is the new theme's.
        themeAnimationStyle: AnimationStyle.noAnimation,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            boldText: boldText,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(
                horizontal: RowMetrics.groupInset,
              ),
              children: [
                // Blank room around the card, so a scroll has somewhere to
                // go either way.
                if (room > 0) SizedBox(height: room),
                card(ReportLabels(AppLocalizations.of(context)!)),
                if (room > 0) SizedBox(height: room),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  String categoryName(ReportInsight insight, ReportLabels labels) =>
      insight.categoryId == null
      ? ''
      : CalendarCategories.labelOf(
          CalendarCategories.resolve(insight.categoryId!),
          labels.l10n,
        );

  Finder pickerRowOf(String identifier) => find.ancestor(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(FormPickerRow),
  );

  /// The leading glyph's icon and colour in [row].
  Icon glyphIn(WidgetTester tester, Finder row) => tester.widget<Icon>(
    find.descendant(
      of: find.descendant(of: row, matching: find.byType(FormGlyph)),
      matching: find.byType(Icon),
    ),
  );

  /// How many lines [caption] is drawn on in [row], from its paragraph's
  /// height at [scale].
  int captionLinesIn(
    WidgetTester tester,
    Finder row,
    String caption,
    double scale,
  ) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: row, matching: find.text(caption)),
    );
    return (paragraph.size.height / (FormMetrics.captionLineHeight * scale))
        .round();
  }

  /// What binds a number to its word in the captions (W).
  final noBreakSpace = String.fromCharCode(0x00A0);

  /// [node]'s children that are not merged into it: zero for a row a
  /// screen reader reads as one node.
  int separateChildren(SemanticsNode node) {
    var separate = 0;
    node.visitChildren((child) {
      if (!child.isMergedIntoParent) separate++;
      return true;
    });
    return separate;
  }

  group('insights', () {
    final tapped = <ReportInsight>[];

    Future<void> pumpInsights(
      WidgetTester tester,
      List<ReportInsight> insights, {
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Brightness brightness = Brightness.light,
      bool tappable = true,
      bool Function(ReportInsight insight)? canTap,
    }) {
      tapped.clear();
      return pumpCard(
        tester,
        (labels) => ReportInsightsCard(
          insights: insights,
          report: insightReport,
          labels: labels,
          weekStart: CalendarWeekStart.monday,
          onInsightTap: tappable ? tapped.add : null,
          canTap: canTap,
        ),
        locale: locale,
        textScale: textScale,
        brightness: brightness,
      );
    }

    testWidgets('three, one or none: the card draws the first '
        '${AnalyticsMetrics.insightsOnPage} by rank, and nothing without '
        'one', (tester) async {
      await pumpInsights(tester, insightReport.insights);
      expect(find.byType(FormPickerRow), findsNWidgets(3));
      for (var rank = 0; rank < 3; rank++) {
        expect(
          find.bySemanticsIdentifier(SemanticsIds.reportInsight(rank)),
          findsOneWidget,
        );
      }
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reportInsight(3)),
        findsNothing,
      );

      await pumpInsights(tester, const [bills]);
      expect(find.byType(FormPickerRow), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reportInsight(0)),
        findsOneWidget,
      );

      await pumpInsights(tester, const []);
      expect(find.byType(FormPickerRow), findsNothing);
      expect(find.byType(FormRowGroup), findsNothing);
    });

    testWidgets('each severity wears its glyph; only "act now" is drawn in '
        'onSurface (J)', (tester) async {
      final expected = {
        3: (Icons.error_outline_rounded, true),
        2: (Icons.flag_outlined, false),
        1: (Icons.lightbulb_outline_rounded, false),
        0: (Icons.info_outline_rounded, false),
      };
      for (final brightness in Brightness.values) {
        final scheme = brightness == Brightness.light
            ? AppTheme.light().colorScheme
            : AppTheme.dark().colorScheme;
        for (final insight in [...threeInsights, bills]) {
          await pumpInsights(tester, [insight], brightness: brightness);
          final icon = glyphIn(
            tester,
            pickerRowOf(SemanticsIds.reportInsight(0)),
          );
          final (glyph, loud) = expected[insight.severity]!;
          expect(icon.icon, glyph, reason: 'severity ${insight.severity}');
          expect(
            icon.color,
            loud ? scheme.onSurface : scheme.onSurfaceVariant,
            reason: 'severity ${insight.severity}',
          );
          expect(icon.size, FormMetrics.glyphSize);
        }
      }
    });

    testWidgets('each row reads the labels\' subject and detail, in every '
        'locale', (tester) async {
      for (final locale in const ['en', 'de', 'ro']) {
        await pumpInsights(tester, threeInsights, locale: Locale(locale));
        final labels = labelsIn(locale);
        for (final (rank, insight) in threeInsights.indexed) {
          final row = tester.widget<FormPickerRow>(
            pickerRowOf(SemanticsIds.reportInsight(rank)),
          );
          final category = categoryName(insight, labels);
          expect(row.label, isNotEmpty);
          expect(
            row.label,
            labels.insightSubject(insight, insightReport, category: category),
          );
          expect(
            row.caption,
            labels.insightDetail(
              insight,
              insightReport,
              category: category,
              weekStart: CalendarWeekStart.monday,
            ),
          );
          expect(row.captionMaxLines, ReportMetrics.insightCaptionMaxLines);
          expect(row.singleLine, isTrue);
          expect(row.showChevron, isFalse);
        }
      }
      // An insight with no category is named by its rule's noun.
      await pumpInsights(tester, const [bills]);
      expect(find.text('Bills'), findsOneWidget);
    });

    testWidgets('one node per row: button, the id by rank and "{severity '
        'word}. {subject}, {detail}"', (tester) async {
      final handle = tester.ensureSemantics();
      for (final locale in const ['en', 'de', 'ro']) {
        await pumpInsights(tester, threeInsights, locale: Locale(locale));
        final labels = labelsIn(locale);
        for (final (rank, insight) in threeInsights.indexed) {
          final node = tester.getSemantics(
            find.bySemanticsIdentifier(SemanticsIds.reportInsight(rank)),
          );
          final data = node.getSemanticsData();
          final category = categoryName(insight, labels);
          expect(separateChildren(node), 0, reason: 'the row is one node');
          expect(
            data.label,
            '${labels.insightSeverityWord(insight.severity)}. '
            '${labels.insightSubject(insight, insightReport, category: category)}'
            ', '
            '${labels.insightDetail(insight, insightReport, category: category, weekStart: CalendarWeekStart.monday)}',
          );
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
        }
      }
      handle.dispose();
    });

    testWidgets('a tap hands over the insight; without a callback a row has '
        'no tap', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInsights(tester, threeInsights);
      await tester.tap(pickerRowOf(SemanticsIds.reportInsight(1)));
      expect(tapped, [unmarked]);

      await pumpInsights(tester, threeInsights, tappable: false);
      for (var rank = 0; rank < 3; rank++) {
        final data = tester
            .getSemantics(
              find.bySemanticsIdentifier(SemanticsIds.reportInsight(rank)),
            )
            .getSemanticsData();
        // `FormPickerRow` marks a spoken-label row a button whatever the
        // tap and says it is off: no tap, a disabled state.
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      }
      handle.dispose();
    });

    testWidgets('an insight canTap refuses has no tap, beside rows that keep '
        'theirs', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInsights(
        tester,
        threeInsights,
        canTap: (insight) => insight != unmarked,
      );
      for (final (rank, insight) in threeInsights.indexed) {
        final data = tester
            .getSemantics(
              find.bySemanticsIdentifier(SemanticsIds.reportInsight(rank)),
            )
            .getSemanticsData();
        final live = insight != unmarked;
        expect(data.hasAction(SemanticsAction.tap), live, reason: '$rank');
        expect(
          data.flagsCollection.isEnabled,
          live ? Tristate.isTrue : Tristate.isFalse,
        );
      }
      await tester.tap(pickerRowOf(SemanticsIds.reportInsight(1)));
      expect(tapped, isEmpty);
      await tester.tap(pickerRowOf(SemanticsIds.reportInsight(0)));
      expect(tapped, [gapOverdue]);
      handle.dispose();
    });

    /// §2.3's measured insight rows by caption lines, per scale. The table
    /// gives two sentences per scale, which wrap to two and three lines at
    /// 2.0.
    final insightHeights = {
      1.0: {1: 62.0, 2: 74.0},
      1.3: {1: 67.0, 2: 90.0},
      2.0: {2: 130.0, 3: 166.0},
    };

    for (final scale in insightHeights.keys) {
      testWidgets('at $scale an insight row is §2.3\'s height for its '
          'caption lines, in every locale and both themes', (tester) async {
        final seen = <int>{};
        for (final brightness in Brightness.values) {
          for (final locale in const ['en', 'de', 'ro']) {
            await pumpInsights(
              tester,
              threeInsights,
              locale: Locale(locale),
              textScale: scale,
              brightness: brightness,
            );
            for (var rank = 0; rank < 3; rank++) {
              final finder = pickerRowOf(SemanticsIds.reportInsight(rank));
              final row = tester.widget<FormPickerRow>(finder);
              final lines = captionLinesIn(tester, finder, row.caption!, scale);
              seen.add(lines);
              expect(
                insightHeights[scale]!.keys,
                contains(lines),
                reason: 'rank $rank in $locale',
              );
              expect(
                tester.getRect(finder).height,
                closeTo(insightHeights[scale]![lines]!, 1),
                reason: 'rank $rank in $locale at $lines lines',
              );
            }
          }
        }
        expect(
          seen.length,
          greaterThanOrEqualTo(2),
          reason: 'a short and a long caption are both drawn',
        );
      });
    }

    testWidgets('pins §2.3: the short finding 62 / 67 / 130 and the unmarked '
        'bill 62 / 90 / 130 in en, the long one 74 / 90 / 166 in de', (
      tester,
    ) async {
      for (final (scale, short, bill, long) in const [
        (1.0, 62.0, 62.0, 74.0),
        (1.3, 67.0, 90.0, 90.0),
        (2.0, 130.0, 130.0, 166.0),
      ]) {
        await pumpInsights(tester, threeInsights, textScale: scale);
        expect(
          tester.getRect(pickerRowOf(SemanticsIds.reportInsight(2))).height,
          closeTo(short, 1),
          reason: '"3 late evenings in one week" at $scale',
        );
        expect(
          tester.getRect(pickerRowOf(SemanticsIds.reportInsight(1))).height,
          closeTo(bill, 1),
          reason: 'the unmarked bill at $scale',
        );
        await pumpInsights(
          tester,
          threeInsights,
          locale: const Locale('de'),
          textScale: scale,
        );
        expect(
          tester.getRect(pickerRowOf(SemanticsIds.reportInsight(0))).height,
          closeTo(long, 1),
          reason: 'the gap past its limit in German at $scale',
        );
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets('tap targets, labelled taps and text contrast '
          '(${brightness.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpInsights(tester, threeInsights, brightness: brightness);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('due soon', () {
    final tapped = <ReportDueRow>[];
    late ReportGroupFolds folds;
    final shrinks = <bool>[];

    setUp(() {
      folds = ReportGroupFolds();
      shrinks.clear();
    });

    Future<void> pumpDue(
      WidgetTester tester,
      List<ReportDueRow> rows, {
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Brightness brightness = Brightness.light,
      bool tappable = true,
      ScrollController? scroll,
    }) {
      tapped.clear();
      return pumpCard(
        tester,
        (labels) => ReportDueSoonCard(
          report: analyticsReport(dueSoon: rows),
          labels: labels,
          folds: folds,
          onDueTap: tappable ? tapped.add : null,
          // Records whether the card was still expanded when told it
          // would shrink: the fold must come after the call.
          onShrink: () => shrinks.add(folds.isDueSoonExpanded),
          scroll: scroll,
        ),
        locale: locale,
        textScale: textScale,
        brightness: brightness,
        scroll: scroll,
        room: scroll == null ? 0 : 900,
      );
    }

    String dueId(ReportDueRow row) =>
        SemanticsIds.reportDue(row.eventId, row.day);

    Finder more() => find.bySemanticsIdentifier(SemanticsIds.reportDueMore);

    testWidgets('four rows draw whole, with no disclosure', (tester) async {
      await pumpDue(tester, dueRows.take(4).toList());
      expect(find.byType(FormPickerRow), findsNWidgets(4));
      expect(more(), findsNothing);
      expect(find.byType(FormActionRow), findsNothing);
    });

    testWidgets('eight rows: six and "2 more", expanded eight and "Show '
        'less"; "Show less" calls onShrink, then folds', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDue(tester, dueRows);
      expect(find.byType(FormPickerRow), findsNWidgets(6));
      for (final row in dueRows.skip(6)) {
        expect(find.bySemanticsIdentifier(dueId(row)), findsNothing);
      }
      expect(find.text('2 more'), findsOneWidget);
      var data = tester.getSemantics(more()).getSemanticsData();
      expect(data.label, '2 more in Due soon');
      expect(data.flagsCollection.isExpanded, Tristate.isFalse);

      await tester.tap(more());
      await tester.pump();
      expect(find.byType(FormPickerRow), findsNWidgets(8));
      expect(find.text('Show less'), findsOneWidget);
      data = tester.getSemantics(more()).getSemanticsData();
      expect(data.label, 'Show less of Due soon');
      expect(data.flagsCollection.isExpanded, Tristate.isTrue);
      expect(folds.isDueSoonExpanded, isTrue);
      expect(shrinks, isEmpty, reason: 'expanding never shrinks');

      await tester.tap(more());
      await tester.pump();
      expect(shrinks, [true], reason: 'onShrink came before the fold');
      expect(find.byType(FormPickerRow), findsNWidgets(6));
      expect(find.text('2 more'), findsOneWidget);
      expect(folds.isDueSoonExpanded, isFalse);
      handle.dispose();
    });

    testWidgets('given the scroll, "Show less" jumps back by the rows that '
        'leave, so "2 more" lands where the finger was; expanding moves '
        'nothing', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpDue(tester, dueRows, scroll: scroll);
      scroll.jumpTo(700);
      await tester.pump();
      await tester.tap(more());
      await tester.pump();
      expect(scroll.offset, 700, reason: 'expanding never compensates');
      expect(find.text('Show less'), findsOneWidget);

      final tapY = tester.getRect(more()).top;
      // The two rows past the first six, with the hairline under each.
      final leaving =
          tester.getRect(pickerRowOf(dueId(dueRows[7]))).bottom +
          1 -
          tester.getRect(pickerRowOf(dueId(dueRows[6]))).top;
      await tester.tap(more());
      await tester.pump();
      expect(find.text('2 more'), findsOneWidget);
      expect(shrinks, [true]);
      expect(scroll.offset, closeTo(700 - leaving, 0.01));
      expect(tester.getRect(more()).top, closeTo(tapY, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the expansion survives a rebuild through the folds', (
      tester,
    ) async {
      await pumpDue(tester, dueRows);
      await tester.tap(more());
      await tester.pump();
      // A refold hands the page a new report and a new card.
      await pumpCard(
        tester,
        (labels) => ReportDueSoonCard(
          key: UniqueKey(),
          report: analyticsReport(dueSoon: List.of(dueRows)),
          labels: labels,
          folds: folds,
        ),
      );
      expect(find.byType(FormPickerRow), findsNWidgets(8));
      expect(find.text('Show less'), findsOneWidget);

      folds = ReportGroupFolds();
      await pumpDue(tester, dueRows);
      expect(find.byType(FormPickerRow), findsNWidgets(6));
    });

    testWidgets('each state wears its glyph; what is past its day is drawn '
        'in onSurface', (tester) async {
      final expected = {
        ReportDueState.overdue: (Icons.error_outline_rounded, true),
        ReportDueState.due: (Icons.hourglass_bottom_rounded, false),
        ReportDueState.unmarked: (Icons.radio_button_unchecked_rounded, true),
        ReportDueState.upcoming: (Icons.schedule_rounded, false),
      };
      for (final brightness in Brightness.values) {
        final scheme = brightness == Brightness.light
            ? AppTheme.light().colorScheme
            : AppTheme.dark().colorScheme;
        await pumpDue(tester, dueRows.take(6).toList(), brightness: brightness);
        for (final row in dueRows.take(6)) {
          final icon = glyphIn(tester, pickerRowOf(dueId(row)));
          final (glyph, loud) = expected[row.state]!;
          expect(icon.icon, glyph, reason: row.state.name);
          expect(
            icon.color,
            loud ? scheme.onSurface : scheme.onSurfaceVariant,
            reason: row.state.name,
          );
        }
      }
    });

    testWidgets('each row reads its event\'s title and the labels\' phrase, '
        'in every locale', (tester) async {
      final report = analyticsReport(dueSoon: dueRows);
      for (final locale in const ['en', 'de', 'ro']) {
        await pumpDue(tester, dueRows.take(6).toList(), locale: Locale(locale));
        final labels = labelsIn(locale);
        for (final row in dueRows.take(6)) {
          final widget = tester.widget<FormPickerRow>(pickerRowOf(dueId(row)));
          expect(widget.label, events[row.eventId]!.title);
          expect(widget.caption, labels.dueCaption(row, report));
          expect(widget.captionMaxLines, 1);
          expect(widget.singleLine, isTrue);
          expect(widget.showChevron, isFalse);
        }
      }
      // English, per kind and state (§2.4's phrases), read past the
      // no-break spaces that bind each number (W).
      await pumpDue(tester, dueRows.take(6).toList());
      expect(
        [
          for (final row in dueRows.take(6))
            tester
                .widget<FormPickerRow>(pickerRowOf(dueId(row)))
                .caption!
                .replaceAll(noBreakSpace, ' '),
        ],
        const [
          'Overdue 32 days',
          'Expired 3 days ago',
          'Nov 1 · not marked',
          'Due in 18 days',
          'Expires in 42 days',
          'Nov 16 · in 12 days',
        ],
      );
    });

    testWidgets('a row whose event is gone is titled by its id', (
      tester,
    ) async {
      final orphan = dueRow(
        'e-gone',
        DateTime.utc(2026, 11, 1),
        ReportDueKind.unmarked,
        ReportDueState.unmarked,
        3,
      );
      await pumpDue(tester, [orphan]);
      expect(
        tester.widget<FormPickerRow>(pickerRowOf(dueId(orphan))).label,
        'e-gone',
      );
    });

    testWidgets('one node per row: button, report-due-<eventId>-<yyyy-MM-dd> '
        'and "{title}, {phrase}"', (tester) async {
      final handle = tester.ensureSemantics();
      final report = analyticsReport(dueSoon: dueRows);
      expect(dueId(dueRows.first), 'report-due-e-car-2026-10-03');
      expect(SemanticsIds.reportDueMore, 'report-due-more');
      for (final locale in const ['en', 'de', 'ro']) {
        await pumpDue(tester, dueRows.take(6).toList(), locale: Locale(locale));
        final labels = labelsIn(locale);
        for (final row in dueRows.take(6)) {
          final node = tester.getSemantics(
            find.bySemanticsIdentifier(dueId(row)),
          );
          final data = node.getSemanticsData();
          final title = events[row.eventId]!.title;
          expect(separateChildren(node), 0, reason: 'the row is one node');
          expect(data.label, '$title, ${labels.dueCaption(row, report)}');
          expect(data.label, labels.dueSpoken(title, row, report));
          expect(data.flagsCollection.isButton, isTrue);
        }
      }
      handle.dispose();
    });

    testWidgets('a tap hands over the row; without a callback a row has no '
        'tap', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDue(tester, dueRows.take(4).toList());
      await tester.tap(pickerRowOf(dueId(dueRows[2])));
      expect(tapped, [dueRows[2]]);

      await pumpDue(tester, dueRows.take(4).toList(), tappable: false);
      for (final row in dueRows.take(4)) {
        final data = tester
            .getSemantics(find.bySemanticsIdentifier(dueId(row)))
            .getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      }
      handle.dispose();
    });

    for (final (scale, height) in const [
      (1.0, 62.0),
      (1.3, 67.0),
      (2.0, 94.0),
    ]) {
      testWidgets('at $scale a due row is $height and the disclosure at '
          'least 48, in every locale and both themes', (tester) async {
        for (final brightness in Brightness.values) {
          for (final locale in const ['en', 'de', 'ro']) {
            folds = ReportGroupFolds()..setDueSoonExpanded(true);
            await pumpDue(
              tester,
              dueRows,
              locale: Locale(locale),
              textScale: scale,
              brightness: brightness,
            );
            for (final row in dueRows) {
              final finder = pickerRowOf(dueId(row));
              await tester.ensureVisible(finder);
              expect(
                tester.getRect(finder).height,
                closeTo(height, 1),
                reason: '${row.eventId} in $locale',
              );
            }
            await tester.ensureVisible(more());
            expect(
              tester
                  .getRect(
                    find.ancestor(
                      of: more(),
                      matching: find.byType(FormActionRow),
                    ),
                  )
                  .height,
              greaterThanOrEqualTo(48),
              reason: 'Show less in $locale',
            );
            expect(tester.takeException(), isNull);
          }
        }
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('tap targets, labelled taps and text contrast '
          '(${brightness.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDue(tester, dueRows, brightness: brightness);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('balance', () {
    // Written out of order: the card sorts. Work is 38 h, two thirds of the
    // 57 h shown; Health and Leisure tie at 5 h. Shared to 100 by the
    // largest remainder, two thirds read 66 % beside Home's 16 and 9 each:
    // rounded alone they would read 67 + 16 + 9 + 9 = 101.
    const balance = {
      LifeArea.leisure: 300,
      LifeArea.health: 300,
      LifeArea.home: 540,
      LifeArea.work: 2280,
    };
    const order = [
      LifeArea.work,
      LifeArea.home,
      LifeArea.health,
      LifeArea.leisure,
    ];
    const percents = {
      LifeArea.work: 66,
      LifeArea.home: 16,
      LifeArea.health: 9,
      LifeArea.leisure: 9,
    };

    Future<void> pumpBalance(
      WidgetTester tester, {
      Map<LifeArea, int> areas = balance,
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Brightness brightness = Brightness.light,
      double width = 360,
      bool boldText = false,
    }) => pumpCard(
      tester,
      (labels) => ReportBalanceCard(
        report: analyticsReport(balance: areas),
        labels: labels,
      ),
      locale: locale,
      textScale: textScale,
      brightness: brightness,
      surface: Size(width, 780),
      boldText: boldText,
    );

    String balanceId(LifeArea area) => SemanticsIds.reportBalance(area.name);
    Finder rowOf(LifeArea area) => find.byWidgetPredicate(
      (widget) =>
          widget is FormMeterRow && widget.identifier == balanceId(area),
    );

    testWidgets('the areas by hours, largest first, ties in LifeArea order; '
        'nothing under two areas', (tester) async {
      await pumpBalance(tester);
      final tops = [for (final area in order) tester.getRect(rowOf(area)).top];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.byType(FormMeterRow), findsNWidgets(4));
      expect(find.byType(FormRowGroup), findsOneWidget);
      expect(
        tester.widget<FormRowGroup>(find.byType(FormRowGroup)).trailingGap,
        isFalse,
      );

      await pumpBalance(tester, areas: const {LifeArea.work: 2280});
      expect(AnalyticsMetrics.balanceMinAreas, 2);
      expect(find.byType(FormMeterRow), findsNothing);
      expect(find.byType(FormRowGroup), findsNothing);
      await pumpBalance(tester, areas: const {});
      expect(find.byType(FormMeterRow), findsNothing);
    });

    testWidgets('each row: the area\'s glyph in onSurfaceVariant, its name, '
        '"38 h · 66 %", and the share of the largest in primary', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        final scheme = brightness == Brightness.light
            ? AppTheme.light().colorScheme
            : AppTheme.dark().colorScheme;
        await pumpBalance(tester, brightness: brightness);
        final labels = labelsIn('en');
        for (final area in order) {
          final row = tester.widget<FormMeterRow>(rowOf(area));
          final icon = glyphIn(tester, rowOf(area));
          expect(icon.icon, CalendarIcons.areaIcon(area), reason: area.name);
          expect(icon.color, scheme.onSurfaceVariant, reason: area.name);
          expect(row.label, labels.areaName(area));
          expect(
            row.caption,
            labels
                .balanceWords(area, balance[area]!, percent: percents[area]!)
                .caption,
          );
          expect(row.captionLines, isNull, reason: 'the one-line slot');
          expect(row.fraction, balance[area]! / 2280);
          expect(row.meterColor, isNull, reason: 'primary');
          expect(row.onTap, isNull);
        }
        final fill = tester.widget<FormMeterRow>(rowOf(LifeArea.work));
        expect(fill.fraction, 1);
      }
      expect(
        tester
            .widget<FormMeterRow>(rowOf(LifeArea.work))
            .caption!
            .replaceAll(noBreakSpace, ' '),
        '38 h · 66 %',
      );
      expect(tester.widget<FormMeterRow>(rowOf(LifeArea.work)).label, 'Work');
    });

    testWidgets('the shares sum to 100: six areas read 55 / 21 / 14 / 6 / 3 '
        '/ 1, where rounding each alone reads 101', (tester) async {
      // Most first, so the card's order is the map's.
      const six = {
        LifeArea.work: 546,
        LifeArea.health: 206,
        LifeArea.home: 136,
        LifeArea.leisure: 66,
        LifeArea.people: 34,
        LifeArea.money: 12,
      };
      await pumpBalance(tester, areas: six);
      final read = [
        for (final area in six.keys)
          tester
              .widget<FormMeterRow>(rowOf(area))
              .caption!
              .replaceAll(noBreakSpace, ' ')
              .split(' · ')
              .last,
      ];
      expect(read, ['55 %', '21 %', '14 %', '6 %', '3 %', '1 %']);
    });

    testWidgets('one node per row, report-balance-<area>, spoken "Work, 38 '
        'hours, 66 percent of the hours", no button', (tester) async {
      final handle = tester.ensureSemantics();
      expect(balanceId(LifeArea.work), 'report-balance-work');
      await pumpBalance(tester);
      final labels = labelsIn('en');
      for (final area in order) {
        final node = tester.getSemantics(
          find.bySemanticsIdentifier(balanceId(area)),
        );
        final data = node.getSemanticsData();
        expect(separateChildren(node), 0, reason: area.name);
        expect(
          data.label,
          labels
              .balanceWords(area, balance[area]!, percent: percents[area]!)
              .spoken,
        );
        expect(data.flagsCollection.isButton, isFalse, reason: area.name);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
      }
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(balanceId(LifeArea.work)))
            .label
            .replaceAll(noBreakSpace, ' '),
        'Work, 38 hours, 66 percent of the hours',
      );
      handle.dispose();
    });

    for (final (scale, height, card) in const [
      (1.0, 66.0, 267.0),
      (1.3, 77.4, 312.6),
      (2.0, 104.0, 419.0),
    ]) {
      testWidgets('at $scale a row is $height and four areas $card, at 360 '
          'and 412, in every locale, light and dark', (tester) async {
        for (final brightness in Brightness.values) {
          for (final width in const [360.0, 412.0]) {
            for (final locale in const ['en', 'de', 'ro']) {
              final reason = '$locale $width ${brightness.name}';
              await pumpBalance(
                tester,
                locale: Locale(locale),
                textScale: scale,
                brightness: brightness,
                width: width,
              );
              for (final area in order) {
                expect(
                  tester.getRect(rowOf(area)).height,
                  closeTo(height, 1),
                  reason: '${area.name} $reason',
                );
              }
              expect(
                tester.getRect(find.byType(FormRowGroup)).height,
                closeTo(card, 1),
                reason: reason,
              );
              expect(tester.takeException(), isNull, reason: reason);
            }
          }
        }
      });
    }

    testWidgets('German at 2.0 shrinks no caption, at 360 and 412', (
      tester,
    ) async {
      for (final width in const [360.0, 412.0]) {
        await pumpBalance(
          tester,
          locale: const Locale('de'),
          textScale: 2.0,
          width: width,
        );
        for (final area in order) {
          final caption = find.descendant(
            of: rowOf(area),
            matching: find.text(
              tester.widget<FormMeterRow>(rowOf(area)).caption!,
            ),
          );
          final slot = find.ancestor(
            of: caption,
            matching: find.byType(FittedBox),
          );
          // A FittedBox that scales down is narrower than its child.
          expect(
            tester.getSize(caption).width,
            lessThanOrEqualTo(tester.getSize(slot).width + 0.01),
            reason: '${area.name} at $width',
          );
        }
      }
    });

    testWidgets('under bold text no caption shrinks or cuts, at 360 and 412, '
        '1.0 to 2.0, in every locale', (tester) async {
      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final width in const [360.0, 412.0]) {
          for (final locale in const ['en', 'de', 'ro']) {
            await pumpBalance(
              tester,
              locale: Locale(locale),
              textScale: scale,
              width: width,
              boldText: true,
            );
            for (final area in order) {
              final reason = '${area.name} $locale $scale $width';
              final caption = find.descendant(
                of: rowOf(area),
                matching: find.text(
                  tester.widget<FormMeterRow>(rowOf(area)).caption!,
                ),
              );
              final paragraph = tester.renderObject<RenderParagraph>(caption);
              expect(paragraph.text.style?.fontWeight, FontWeight.bold);
              expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
              final slot = find.ancestor(
                of: caption,
                matching: find.byType(FittedBox),
              );
              expect(
                tester.getSize(caption).width,
                lessThanOrEqualTo(tester.getSize(slot).width + 0.01),
                reason: reason,
              );
            }
          }
        }
      }
    });
  });
}
