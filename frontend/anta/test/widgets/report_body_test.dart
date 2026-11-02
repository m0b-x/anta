import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/utils/calendar_report_builder.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_body.dart';
import 'package:anta/widgets/report_group_stack.dart';
import 'package:anta/widgets/report_totals_card.dart';

import '../goldens/support/golden_fonts.dart';

/// Counts the routes pushed over the body, so a case can prove a tap opened
/// nothing.
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushes++;
  }
}

/// `ReportBody` and `ReportBand` over a report folded the pure way, with
/// every callback null — as the guide's screen stage draws them (D74): the
/// cards are drawn, nothing a tap reaches leaves the body, the folds stay
/// live.
void main() {
  setUpAll(loadGoldenFonts);

  /// The suite's clock: no case reads the wall clock.
  DateTime clock() => DateTime(2026, 10, 30, 10);
  final today = EventAgenda.dateOnly(clock());
  const october = OverviewMonthPeriod(2026, 10);
  const years = (first: 2020, last: 2026);

  /// Tracked, timed, Tuesdays and Thursdays; the week of the 13th missed.
  final gym = CalendarEvent(
    id: 'e-gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 1),
    rule: const WeeklyRecurrence(weekdays: {2, 4}),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    tracksPresence: true,
  );

  /// One time, timed.
  final dentist = CalendarEvent(
    id: 'e-dentist',
    title: 'Dentist',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 10, 9),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 9 * 60, durationMinutes: 30),
  );

  /// All day, every year.
  final birthday = CalendarEvent(
    id: 'e-birthday',
    title: 'Ana',
    categoryId: 'birthday',
    startDate: DateTime.utc(2020, 10, 21),
    rule: const YearlyRecurrence(),
  );

  late CalendarReport report;
  late ReportGroupFolds folds;
  late _PushCounter pushes;

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
    EventPresence.updateCache(
      byEvent: {
        gym.id: {DateTime.utc(2026, 10, 13): PresenceStatus.missed},
      },
    );
    report = CalendarReportBuilder.fold(
      CalendarReportService.sampleInput(
        ReportRequest(
          span: october.resolve(today: today, yearBounds: years),
          previousSpan: october
              .stepped(direction: -1, today: today, yearBounds: years)
              ?.resolve(today: today, yearBounds: years),
          events: [gym, dentist, birthday],
          today: today,
          weekStart: CalendarWeekStart.monday,
        ),
      ),
    );
    folds = ReportGroupFolds();
    pushes = _PushCounter();
  });

  tearDown(() {
    EventPresence.resetCache();
    CalendarCategories.updateCache(const []);
    AppNavigator.pendingOverviewLook.value = null;
  });

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Future<void> pumpBody(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    Size surface = const Size(360, 780),
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        navigatorObservers: [pushes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            final labels = ReportLabels(AppLocalizations.of(context)!);
            return Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReportBand(
                    period: october,
                    home: october,
                    report: report,
                    today: today,
                    years: years,
                    labels: labels,
                  ),
                  Expanded(
                    child: ReportBody(
                      report: report,
                      period: october,
                      today: today,
                      years: years,
                      weekStart: CalendarWeekStart.monday,
                      labels: labels,
                      folds: folds,
                      bottomClearance: 0,
                      use24Hour: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the body down a screen at a time to its end, handing each
  /// frame to [atEach].
  Future<void> scrollThrough(
    WidgetTester tester,
    void Function() atEach,
  ) async {
    final scrollable = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(Scrollable),
    );
    atEach();
    for (var i = 0; i < 20; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      atEach();
    }
  }

  test('the fold holds what the cases read', () {
    expect(report.trend, isNotNull);
    expect(report.categories, isNotEmpty);
    expect(report.missed, isNotEmpty);
  });

  testWidgets('draws the totals, the trend and the groups under their ids', (
    tester,
  ) async {
    await pumpBody(tester);
    expect(byId(SemanticsIds.reportBody), findsOneWidget);
    expect(byId(SemanticsIds.reportTile('events')), findsOneWidget);
    expect(byId(SemanticsIds.reportNavTitle), findsOneWidget);
    expect(byId(SemanticsIds.reportGroup('categories', 'gym')), findsOneWidget);
    final seen = <String>{};
    await scrollThrough(tester, () {
      for (final id in [
        SemanticsIds.reportTrend,
        SemanticsIds.reportGroup('missed', 'gym'),
        SemanticsIds.reportRow(gym.id, DateTime.utc(2026, 10, 13)),
        SemanticsIds.reportShowList,
        SemanticsIds.reportShare,
        SemanticsIds.reportSend,
      ]) {
        if (byId(id).evaluate().isNotEmpty) seen.add(id);
      }
    });
    expect(seen, hasLength(6));
  });

  testWidgets('with every callback null no tap opens a route or leaves the '
      'body, and the Missed row has no presence button', (tester) async {
    await pumpBody(tester);
    final scrollable = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(Scrollable),
    );
    // Every row and tile on screen tapped, a screen at a time to the end.
    var tapped = 0;
    for (var i = 0; i < 20; i++) {
      final rows = [
        ...find.byType(FormPickerRow).evaluate(),
        ...find.byType(FormActionRow).evaluate(),
        ...find.byType(ReportTotalsCard).evaluate(),
      ];
      for (final row in rows) {
        if (!row.mounted) continue;
        final box = row.renderObject;
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final centre = box.localToGlobal(box.size.center(Offset.zero));
        if (centre.dy < 0 || centre.dy >= 780) continue;
        await tester.tapAt(centre);
        await tester.pumpAndSettle();
        tapped++;
      }
      final position = tester.state<ScrollableState>(scrollable).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(tapped, greaterThan(0));
    expect(pushes.pushes, 0);
    expect(AppNavigator.pendingOverviewLook.value, isNull);
    expect(tester.takeException(), isNull);
    expect(
      byId(SemanticsIds.reportRowPresence(gym.id, DateTime.utc(2026, 10, 13))),
      findsNothing,
    );
    for (final id in [
      SemanticsIds.reportShowList,
      SemanticsIds.reportShare,
      SemanticsIds.reportSend,
    ]) {
      final row = tester.widget<FormActionRow>(
        find.ancestor(of: byId(id), matching: find.byType(FormActionRow)).first,
      );
      expect(row.onTap, isNull, reason: id);
    }
  });

  testWidgets('a header tap folds its group and opens it again', (
    tester,
  ) async {
    await pumpBody(tester);
    final header = byId(SemanticsIds.reportGroup('categories', 'gym'));
    final rowsBelow = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(FormPickerRow),
    );
    final open = rowsBelow.evaluate().length;
    expect(folds.isOpen(ReportCard.categories, 'gym'), isTrue);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(folds.isOpen(ReportCard.categories, 'gym'), isFalse);
    expect(rowsBelow.evaluate().length, lessThan(open));

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(folds.isOpen(ReportCard.categories, 'gym'), isTrue);
    expect(rowsBelow.evaluate().length, open);
  });

  testWidgets('de at 2.0 on 360 × 780 lays the band and the body out with no '
      'overflow', (tester) async {
    await pumpBody(tester, locale: const Locale('de'), textScale: 2);
    await scrollThrough(tester, () => expect(tester.takeException(), isNull));
  });

  testWidgets('the band with no callbacks draws every control disabled', (
    tester,
  ) async {
    await pumpBody(tester);
    final nav = tester.widget<AgendaPeriodNav>(find.byType(AgendaPeriodNav));
    expect(nav.onTitleTap, isNull);
    expect(nav.onPrevious, isNull);
    expect(nav.onNext, isNull);
    expect(nav.onToday, isNull);
    expect(byId(SemanticsIds.reportNavPrevious), findsOneWidget);
    expect(byId(SemanticsIds.reportNavNext), findsOneWidget);
  });
}
