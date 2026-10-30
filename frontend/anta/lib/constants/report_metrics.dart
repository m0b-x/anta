/// The calendar report's numbers — the caps, thresholds and cache sizes the
/// builder, the service and the page share (`docs/calendar-report-roadmap.md`
/// §4.3, §4.7, D29), and the page's own geometry (§4.8). Plain Dart values
/// only: the builder imports this file and its import closure stays off
/// Flutter, so a padding is two numbers here, never an `EdgeInsets`.
abstract final class ReportMetrics {
  /// Stat tiles per row of the Totals card: two keep a value and its delta
  /// on one line on a phone, and an odd last tile takes the full width.
  static const int tileColumns = 2;

  /// Category groups the Categories card shows before folding the rest into
  /// one "n more categories" row (V): past seven classes a chart's colours
  /// stop telling groups apart, and a card never grows with the data.
  static const int maxCategoryRows = 7;

  /// Dated rows a list shows before a "Show as list" row (V): the overview's
  /// List is the unbounded view, so a report card stays a bounded sliver.
  static const int maxListRows = 200;

  /// Rows an open category group shows before its "n more" row (X): enough
  /// to answer "what was in it" without a fifty-row group pushing the rest
  /// of the page off the screen.
  static const int groupPreviewRows = 4;

  /// Happened occurrences below which the Over time card is not drawn (Q):
  /// three birthdays make no chart, and the groups already tell the story.
  static const int trendMinOccurrences = 4;

  /// Timed happened occurrences the usual time band needs (D29): a median of
  /// one or two starts is an anecdote, not a habit.
  static const int trendMinTimedForBand = 3;

  /// The longest span, in days, whose trend has one column per day (D29): a
  /// month reads day by day, and 31 columns still fit a phone's width.
  static const int trendDayUnitMaxDays = 31;

  /// The longest span, in days, whose trend has one column per week (D29):
  /// 26 weeks still fit; a longer span reads per month.
  static const int trendWeekUnitMaxDays = 182;

  /// Folded reports the service keeps (D30): a step back and forth and one
  /// category change hit the memo instead of re-scanning.
  static const int memoFolds = 4;

  /// Description texts whose task count stays cached (D27): a shared text is
  /// parsed once however many days show it, and the cache stays bounded
  /// however many notes the user keeps.
  static const int taskCountCacheSize = 256;

  /// A stat tile's start and end inset (§4.8): the group rows' own, so a
  /// tile's label lines up with the section label above the card.
  static const double tilePaddingHorizontal = 16;

  /// A stat tile's top and bottom inset (§4.8): with the three lines it
  /// makes a 98 dp tile at 1.0, the height the designer measured.
  static const double tilePaddingVertical = 12;

  /// A tile value's figures (§4.8, D): large enough to read at a glance, the
  /// units beside them stay at the label size.
  static const double tileValueSize = 28;

  /// The value line's forced strut: a figure run and a 15 px unit run share
  /// one line box, so "21 of 24" is exactly as tall as "31".
  static const double tileValueLineHeight = 34;

  /// The count template the column rule lays out (§4.8, C): three digits is
  /// the widest a count in one report reaches in practice.
  static const int tileTemplateCount = 888;

  /// The hours template the column rule lays out (§4.8, C), the widest
  /// decimal-hours value a report shows in practice.
  static const double tileTemplateHours = 888.8;

  /// The Over time card's start and end inset (§4.8): the Totals tiles'
  /// own, so the two cards' contents line up down the page.
  static const double chartPaddingHorizontal = tilePaddingHorizontal;

  /// The Over time card's top and bottom inset, the tiles' own.
  static const double chartPaddingVertical = tilePaddingVertical;

  /// The widest a chart column grows (§4.3): a week's seven columns stay
  /// columns, never slabs.
  static const double columnMaxWidth = 24;

  /// The surface gap between two columns and between a column's happened
  /// and missed parts (§4.8, the dataviz spacer): the parts read as two
  /// marks, not one two-tone bar.
  static const double columnGap = 2;

  /// The rounding of a column's data end, capped at half its width so a
  /// narrow day column stays a column; the baseline end stays square.
  static const double columnRadius = 4;

  /// The plot's height: the peak column fills it, so a period's shape reads
  /// whatever its numbers are.
  static const double chartPlotHeight = 80;

  /// Between the legend row and the plot's top hairline.
  static const double chartTopGap = 4;

  /// Between the axis labels and the caption under the plot.
  static const double chartCaptionGap = 12;

  /// Between a legend dot and its word.
  static const double legendDotGap = 6;

  /// Between the legend's two items; the wrap's spacing, so German at 2.0
  /// puts Missed on a second line instead of overflowing.
  static const double legendItemSpacing = 16;

  /// The least room between two axis labels: a label closer than this to
  /// the last one drawn is skipped, so labels never touch.
  static const double axisLabelMinGap = 4;

  /// Between the plot's baseline and the axis labels.
  static const double axisGap = 4;

  /// The body's opacity while a refold runs (§4.8, R): the previous render
  /// stays readable and plainly not current, with no skeleton.
  static const double refoldOpacity = 0.6;

  /// How long a refold runs before the body dims (§4.8, R) — Material's
  /// `Durations.short3`: a memo hit or a quick fold lands before it, so the
  /// common refold never flickers.
  static const Duration refoldDimDelay = Duration(milliseconds: 150);
}
