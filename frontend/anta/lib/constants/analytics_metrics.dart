/// The calendar analytics' numbers — the card caps and the insight rules'
/// thresholds (`docs/calendar-analytics-roadmap.md` Z, §6.7–§6.12). Plain
/// Dart values only, `ReportMetrics`'s rule: the builder and the rules
/// import this file, and no rule or widget carries a literal of its own.
/// The kinds' suggested counts-as live on their catalogue rows.
abstract final class AnalyticsMetrics {
  /// Rows the Due soon card shows before "n more" (§6.8): enough for the
  /// month's few deadlines, never a list that pushes the goals off-screen.
  static const int dueSoonRows = 6;

  /// Tags the By tag card lists (§6.9): the people and places that matter
  /// in a span, not every word ever tagged once.
  static const int tagRows = 8;

  /// Texts whose tags are kept tokenised (§8 "Cost"): the task-count
  /// cache's size, since a fold reads the same titles, descriptions and
  /// per-day texts the task counter does.
  static const int tagCacheSize = 256;

  /// Lookbacks and lookaheads a report service keeps (R): per category that
  /// has a target or reads a gap and per span the owner steps between, one
  /// of each on a past span, so a step ◄ ► never rescans a window it
  /// already scanned.
  static const int lastSeenCacheSize = 64;

  /// Days before a span the lookback reads (R, §6.6): a year of streak and
  /// last-seen. `EventAgenda.maxRangeDays`, the one scan's cap — a test pins
  /// the two equal, since the pure builder cannot import the agenda.
  static const int lookbackDays = 366;

  /// Insights the page shows (§6.7): three sentences read at a glance; more
  /// become a list nobody reads.
  static const int insightsOnPage = 3;

  /// Insights a report digest carries (§6.7): a notification holds one
  /// sentence worth acting on.
  static const int insightsInDigest = 1;

  /// Goal lines a report digest carries: the notification's expanded body
  /// stays inside what the shade shows without a scroll.
  static const int digestGoalLines = 3;

  /// Due soon lines a report digest carries, after the goals.
  static const int digestDueLines = 2;

  /// The share of a gap limit, at its end, in which a gap target reads due
  /// rather than within (§6.6, D2): the limit's last fifth leaves time to
  /// book the dentist before it is overdue.
  static const double gapDueFraction = 0.2;

  /// The share of a period that must have elapsed before an *at least* goal
  /// can read behind (G1): on a Monday every weekly goal is behind, which
  /// says nothing.
  static const double goalBehindMinElapsed = 0.5;

  /// The streak length whose multiples are celebrated (G4): every week would
  /// be noise, a month of weeks is a milestone.
  static const int streakMilestone = 4;

  /// The share of a Leave allowance left below which G5 warns: three days
  /// of twenty-five is the point where planning starts to matter.
  static const double leaveLowFraction = 0.2;

  /// The share of the year still ahead for the low-allowance warning (G5):
  /// in December a nearly spent allowance is the plan, not a warning.
  static const double leaveQuarterAhead = 0.25;

  /// Days left in the year under which unused Leave days are flagged (G5):
  /// a month is still enough to take them.
  static const int leaveUnusedDaysLeft = 30;

  /// Days ahead within which an Expiry warns (D3): two months covers a
  /// passport's or a licence's renewal queue.
  static const int expiryWarnDays = 60;

  /// Episodes needed before a next one is predicted (D5): two make one gap,
  /// which is no pattern.
  static const int episodeMinCount = 3;

  /// The largest coefficient of variation of the gaps between episodes that
  /// still reads as regular (D5): beyond it a "usual gap" would be a guess.
  static const double episodeRegularCv = 0.25;

  /// Days ahead within which an expected episode is mentioned (D5): a week
  /// is enough notice to act on, further out it is only a worry.
  static const int episodeAheadDays = 7;

  /// The attendance spread, in percentage points, between a routine's best
  /// and worst weekday that P1 reports: smaller differences are chance.
  static const int weekdaySpreadPoints = 40;

  /// Occurrences each compared weekday needs for P1: one missed Friday is
  /// not "Fridays".
  static const int weekdayMinDays = 4;

  /// The minute of day after which a Work occurrence ends late (P2): 19:00,
  /// past an ordinary working evening.
  static const int workLateMinute = 19 * 60;

  /// Late Work evenings in one week that P2 reports: one late day is a
  /// deadline, three are a pattern.
  static const int lateEveningsPerWeek = 3;

  /// A night shorter than this is short (P3): seven hours, the adult
  /// guideline's floor.
  static const int sleepShortMinutes = 7 * 60;

  /// The shortest sample that counts as a night for P3's short nights: a
  /// sample shorter than three hours is a nap, not a night.
  static const int sleepNightMinMinutes = 3 * 60;

  /// Short nights in one week that P3 reports, the late-evenings twin.
  static const int shortNightsPerWeek = 3;

  /// The bedtime spread, in minutes, past which P3 calls sleep irregular:
  /// an hour and a half either way is a different evening.
  static const int bedtimeSpreadMinutes = 90;

  /// The share of the bedtimes left out at each end before P3's spread is
  /// read — the 10th to the 90th percentile — so one late night in thirty
  /// does not make a whole month irregular.
  static const double bedtimeSpreadTrim = 0.1;

  /// Meetings' share of Work + Meeting hours that P4 reports: past half, the
  /// meetings are the job.
  static const double meetingShare = 0.5;

  /// The cancelled share of planned occurrences that P5 reports.
  static const double cancelledShare = 0.3;

  /// Planned occurrences P5 needs: one of three cancelled is a week, not a
  /// trend.
  static const int cancelledMinPlanned = 4;

  /// Days without a Workout occurrence that P6 reports as a rest gap: past
  /// a week and a half, a routine has stopped.
  static const int restGapDays = 10;

  /// The relative move of a primary against the compared period that T1 /
  /// T2 report: smaller changes are a month's noise.
  static const double trendDelta = 0.3;

  /// Occurrences either side needs for T1 / T2, unless [trendMinMinutes]
  /// holds: a move from two to three is not "up 50 %".
  static const int trendMinOccurrences = 5;

  /// Minutes either side that also qualify T1 / T2 — two hours, so an
  /// hours-led category with few long occurrences still reads.
  static const int trendMinMinutes = 120;

  /// The relative move of a Bill against its previous occurrence that T3
  /// reports: a tenth is a price change, not rounding.
  static const double billDelta = 0.1;

  /// Days ahead whose Bills M1 sums: the next month's outgoings.
  static const int billsAheadDays = 30;

  /// How many of a tag's median gaps make its last-seen worth a line (R1)
  /// when the category has no gap limit of its own.
  static const int tagGapMultiple = 3;

  /// The median lead time, in days, under which L1 says events are booked
  /// at short notice.
  static const int leadTimeShortDays = 2;

  /// Events L1 needs before a median lead time means anything.
  static const int leadTimeMinEvents = 4;

  /// Deadlines open past their day that L2 reports: one is a slip, three a
  /// backlog.
  static const int deadlinesOpenMin = 3;

  /// Timed kept samples the When heatmap needs (§6.10): fewer leave a grid
  /// of empty cells that says nothing.
  static const int whenMinTimedSamples = 10;

  /// Areas with hours the Balance card needs (§6.10): one area is no
  /// balance.
  static const int balanceMinAreas = 2;

  /// Categories the year's Months strip lists before "n more" (§6.12),
  /// `ReportMetrics.maxCategoryRows`'s seven for the same reason.
  static const int yearMonthsStripCategories = 7;

  /// The shortest run of kept occurrences a year's Records lists as a
  /// streak (S6 J): two in a row is any week's routine, three is the first
  /// run worth naming.
  static const int recordStreakMin = 3;
}
