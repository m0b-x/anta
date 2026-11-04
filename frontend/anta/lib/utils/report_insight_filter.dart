import '../constants/category_kinds.dart';
import '../models/calendar_report.dart';

/// Which of a report's insights the page's Insights card shows (S4 H): a
/// goal's or a due row's own news is already said on the card above, so
/// saying it again in the sentence below only pushes Totals further down.
/// The digest reads [CalendarReport.insights] whole; only the page drops.
abstract final class ReportInsightFilter {
  /// [report]'s insights in their rank order, without G1–G3 whose category
  /// has a row in the Goals card, G4's milestone whose category's periodic
  /// row already ends on the streak ("· 8 in a row"; a broken streak is
  /// news the row does not say), and D1–D4 whose subject a card above
  /// shows — D1 / D2 a gap goal row or a gap due row of that category, D3
  /// an expiry row of that event, D4 an unmarked row of that event. Every
  /// due row counts, folded or not: what the card's "n more" opens never
  /// changes the insights. The card caps what is left.
  static List<ReportInsight> forPage(CalendarReport report) {
    final insights = report.insights;
    if (insights.isEmpty) return insights;
    final goalCategories = <String>{};
    final periodicCategories = <String>{};
    final gapCategories = <String>{};
    for (final goal in report.goals) {
      goalCategories.add(goal.categoryId);
      if (goal.target.kind == TargetKind.maxGap) {
        gapCategories.add(goal.categoryId);
      } else if (goal.target.period != null) {
        periodicCategories.add(goal.categoryId);
      }
    }
    final expiryEvents = <String>{};
    final unmarkedEvents = <String>{};
    for (final row in report.dueSoon) {
      switch (row.kind) {
        case ReportDueKind.gap:
          gapCategories.add(row.categoryId);
        case ReportDueKind.expiry:
          expiryEvents.add(row.eventId);
        case ReportDueKind.unmarked:
          unmarkedEvents.add(row.eventId);
        case ReportDueKind.upcoming:
          break;
      }
    }
    bool shownAbove(ReportInsight insight) => switch (insight.rule) {
      InsightRule.g1 ||
      InsightRule.g2 ||
      InsightRule.g3 => goalCategories.contains(insight.categoryId),
      InsightRule.g4 =>
        !insight.alternate && periodicCategories.contains(insight.categoryId),
      InsightRule.d1 ||
      InsightRule.d2 => gapCategories.contains(insight.categoryId),
      InsightRule.d3 => expiryEvents.contains(insight.eventId),
      InsightRule.d4 => unmarkedEvents.contains(insight.eventId),
      _ => false,
    };
    return [
      for (final insight in insights)
        if (!shownAbove(insight)) insight,
    ];
  }
}
