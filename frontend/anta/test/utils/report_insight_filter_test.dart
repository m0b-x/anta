import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/utils/report_insight_filter.dart';

/// The page's Insights filter (S4 H) over hand-built reports: each rule the
/// Goals or Due soon card already says is dropped for its own subject only,
/// every other insight is kept, and the rank order holds.
void main() {
  final november = (
    start: DateTime.utc(2026, 11, 1),
    end: DateTime.utc(2026, 11, 30),
  );
  final day = DateTime.utc(2026, 11, 20);

  CalendarReport report({
    required List<ReportInsight> insights,
    List<ReportGoal> goals = const [],
    List<ReportDueRow> dueSoon = const [],
  }) => CalendarReport(
    span: november,
    today: DateTime.utc(2026, 11, 4),
    tense: ReportTense.current,
    countedTo: DateTime.utc(2026, 11, 4),
    events: const {},
    tiles: const [],
    skippedDays: 0,
    aheadCount: 0,
    categories: const [],
    missed: const [],
    ahead: const [],
    goals: goals,
    dueSoon: dueSoon,
    insights: insights,
  );

  ReportGoal goal(String categoryId) => ReportGoal(
    categoryId: categoryId,
    measure: ReportMeasure.count,
    target: const ReportTarget(
      kind: TargetKind.atLeast,
      value: 3,
      period: TargetPeriod.week,
    ),
  );

  ReportGoal gapGoal(String categoryId) => ReportGoal(
    categoryId: categoryId,
    measure: ReportMeasure.lastSeen,
    target: const ReportTarget(kind: TargetKind.maxGap, value: 180),
    gap: const ReportGapState(
      daysSince: 212,
      limit: 180,
      state: GapState.overdue,
    ),
  );

  ReportDueRow due(ReportDueKind kind, {String category = 'car', String? id}) =>
      ReportDueRow(
        categoryId: category,
        eventId: id ?? 'e-$category',
        day: day,
        kind: kind,
        state: ReportDueState.due,
        days: 16,
      );

  ReportInsight insight(
    InsightRule rule, {
    String? categoryId,
    String? eventId,
    bool alternate = false,
  }) => ReportInsight(
    rule: rule,
    severity: 2,
    categoryId: categoryId,
    eventId: eventId,
    target: InsightTarget.categoryGroup,
    alternate: alternate,
  );

  test('nothing to drop hands the list back as it came', () {
    final insights = [
      insight(InsightRule.g1, categoryId: 'gym'),
      insight(InsightRule.p4, categoryId: 'work'),
    ];
    final shown = ReportInsightFilter.forPage(report(insights: insights));
    expect(shown, insights);
  });

  test('G1–G3 drop when their category has a goal row; G5 stays', () {
    final kept = [
      insight(InsightRule.g1, categoryId: 'run'),
      insight(InsightRule.g5, categoryId: 'gym'),
    ];
    final shown = ReportInsightFilter.forPage(
      report(
        goals: [goal('gym')],
        insights: [
          insight(InsightRule.g1, categoryId: 'gym'),
          kept[0],
          insight(InsightRule.g2, categoryId: 'gym'),
          insight(InsightRule.g3, categoryId: 'gym'),
          kept[1],
        ],
      ),
    );
    expect(shown, kept);
  });

  test('G4\'s milestone drops beside a periodic row, which ends on the '
      'streak; a broken streak and another category\'s stay', () {
    final broken = insight(InsightRule.g4, categoryId: 'gym', alternate: true);
    final elsewhere = insight(InsightRule.g4, categoryId: 'run');
    final besideGap = insight(InsightRule.g4, categoryId: 'car');
    final shown = ReportInsightFilter.forPage(
      report(
        goals: [goal('gym'), gapGoal('car')],
        insights: [
          insight(InsightRule.g4, categoryId: 'gym'),
          broken,
          elsewhere,
          besideGap,
        ],
      ),
    );
    expect(shown, [broken, elsewhere, besideGap]);
  });

  test('D1 and D2 drop beside a gap goal row of their category, never '
      'beside a periodic one', () {
    final kept = insight(InsightRule.d2, categoryId: 'gym');
    final shown = ReportInsightFilter.forPage(
      report(
        goals: [gapGoal('car'), goal('gym')],
        insights: [
          insight(InsightRule.d1, categoryId: 'car'),
          kept,
          insight(InsightRule.d2, categoryId: 'car'),
        ],
      ),
    );
    expect(shown, [kept]);
  });

  test('D1 and D2 drop beside a gap row of their category, never another '
      'kind of row', () {
    final kept = insight(InsightRule.d2, categoryId: 'dentist');
    final shown = ReportInsightFilter.forPage(
      report(
        dueSoon: [
          due(ReportDueKind.gap),
          due(ReportDueKind.expiry, category: 'dentist'),
        ],
        insights: [
          insight(InsightRule.d1, categoryId: 'car'),
          insight(InsightRule.d2, categoryId: 'car'),
          kept,
        ],
      ),
    );
    expect(shown, [kept]);
  });

  test('D3 drops beside its event\'s expiry row and D4 beside its '
      'unmarked row', () {
    final keptExpiry = insight(InsightRule.d3, eventId: 'passport');
    final keptUnmarked = insight(InsightRule.d4, eventId: 'yoga');
    final shown = ReportInsightFilter.forPage(
      report(
        dueSoon: [
          due(ReportDueKind.expiry, id: 'licence'),
          due(ReportDueKind.unmarked, id: 'gym'),
          // The wrong kinds for the kept two: an unmarked passport, an
          // expiring yoga.
          due(ReportDueKind.unmarked, id: 'passport'),
          due(ReportDueKind.expiry, id: 'yoga'),
          due(ReportDueKind.upcoming, id: 'bill'),
        ],
        insights: [
          insight(InsightRule.d3, eventId: 'licence'),
          keptExpiry,
          insight(InsightRule.d4, eventId: 'gym'),
          keptUnmarked,
        ],
      ),
    );
    expect(shown, [keptExpiry, keptUnmarked]);
  });

  test('every other rule stays whatever the cards above hold, in its rank '
      'order', () {
    final others = [
      insight(InsightRule.d5, categoryId: 'car'),
      insight(InsightRule.p1, categoryId: 'gym'),
      insight(InsightRule.t1, categoryId: 'gym'),
      insight(InsightRule.m1),
      insight(InsightRule.a2, eventId: 'licence'),
    ];
    final shown = ReportInsightFilter.forPage(
      report(
        goals: [goal('gym')],
        dueSoon: [
          due(ReportDueKind.gap),
          due(ReportDueKind.expiry, id: 'licence'),
        ],
        insights: [
          insight(InsightRule.g1, categoryId: 'gym'),
          ...others,
          insight(InsightRule.d1, categoryId: 'car'),
        ],
      ),
    );
    expect(shown, others);
  });
}
