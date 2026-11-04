import 'dart:math' as math;

import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart';

import '../constants/analytics_metrics.dart';
import '../constants/category_kinds.dart';
import '../constants/report_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/overview_period.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import 'category_profile_labels.dart' show lifeAreaName;
import 'date_span_label.dart';

/// One run of a tile's value line: a figure ("21", "18.5", "—"), drawn large,
/// or the words around it ("of", " h"), drawn at the label's size (§4.8, D).
typedef ReportValueRun = ({String text, bool figure});

/// The three cards drawn from category groups (W). A group's facts depend
/// on its card — Missed counts only what was missed — and its ids carry the
/// card, because one category heads a group in each.
enum ReportCard { categories, missed, ahead }

/// What a goal row says about its state (§2.2's glyph table): a period's
/// [GoalState] and a gap's [GapState] in one set, so the spoken word and the
/// band's count read the same state.
enum _GoalWord {
  met,
  onPace,
  behind,
  over,
  missed,
  notStarted,
  planned,
  within,
  dueSoon,
  pastLimit,
}

/// The shapes a periodic goal's caption takes (§2.2's read-back table).
enum _GoalShape {
  pace,
  done,
  left,
  over,
  closedMet,
  closedMissed,
  closedWithin,
  closedOver,
  planned,
}

/// Every word the report says about its numbers — tiles, deltas, the
/// caption, the band's subtitle, the spoken tile labels — in one place, so
/// the page, the report digest's words and the share read alike (S4, S5
/// reuse it). Built once per build from the locale's strings; it holds the
/// formatters, so nothing is built per tile. Free of widgets on purpose.
///
/// Hours are decimal hours everywhere ("18.5 h", B): "18 Std. 30 Min."
/// forced the tiles into one column in German at 1.0. Under an hour they
/// read in minutes ("40 min", D36.5), where "0.7 h" says nothing at a glance.
class ReportLabels {
  ReportLabels(
    this.l10n, {
    this.currencySymbol = '',
    this.currencySuffix = false,
  }) : _hours = NumberFormat('0.#', l10n.localeName),
       _countedTo = DateFormat.MMMMd(l10n.localeName);

  final AppLocalizations l10n;

  /// The ledger's currency display (`MoneyDisplayConfig`), so an amount on
  /// a goal, a header or an insight reads as the notes it was summed from;
  /// empty writes the plain decimal.
  final String currencySymbol;

  /// Whether [currencySymbol] follows the amount ("12.50 lei").
  final bool currencySuffix;

  final NumberFormat _hours;
  final DateFormat _countedTo;
  late final NumberFormat _count = NumberFormat.decimalPattern(l10n.localeName);

  // A goal's period end and a due row's day ("Nov 1"); built on first use,
  // as most reports carry no goal.
  late final DateFormat _dayMonth = DateFormat.MMMd(l10n.localeName);

  // The Over time card's formatters, built on first use: most labels a page
  // builds never word a trend.
  late final DateFormat _weekday = DateFormat.EEEE(l10n.localeName);
  late final DateFormat _peakDay = DateFormat.MMMMEEEEd(l10n.localeName);
  late final DateFormat _peakWeek = DateFormat.MMMMd(l10n.localeName);
  late final DateFormat _peakMonth = DateFormat.yMMMM(l10n.localeName);

  // A group row's day, with the month only for a period across months (U),
  // composed by the `reportRowDay` templates: German writes "Do., 8. Okt.",
  // which no raw pattern spells in all three languages. The names come from
  // the date symbols' format forms, because the `E` and `MMM` skeletons give
  // the standalone ones ("Do", "Okt") that German never writes in a date.
  late final DateFormat _rowDayOfMonth = DateFormat.d(l10n.localeName);
  late final DateSymbols _rowSymbols = _rowDayOfMonth.dateSymbols;

  // The When card's clock (S5), built on first use. The hour-only clock
  // follows `EventTimeFormatter`'s rule for a day period — the locale's `jm`
  // writes one — so "6 PM" stands where "6:00 PM" would.
  late final bool _clockHasDayPeriod =
      (DateFormat.jm(l10n.localeName).pattern ?? '').contains('a');
  late final DateFormat _hourOnly = DateFormat('h a', l10n.localeName);

  /// The names already worded by this instance: a build names the shown
  /// period three times and each `menuValue` builds a `DateFormat`.
  final Map<OverviewPeriod, String> _periodNames = {};
  CalendarReport? _comparedReport;
  String? _comparedName;

  /// A tile with nothing in the period.
  static const String nothing = '—';

  /// Joins a caption's or a detail's facts: the no-break space keeps the dot
  /// off the start of a wrapped line.
  static const String separator = '$_noBreak· ';

  /// What binds a figure to the word beside it (W).
  static const String _noBreak = '\u00a0';

  /// A figure, signed or not, with the locale's decimal mark, or the dash —
  /// what the value line draws large; everything else is a unit.
  static final RegExp _figure = RegExp(r'[+−\-±]?\d+(?:[.,]\d+)?|—');

  /// [hours] with the locale's decimal mark, a trailing ".0" dropped.
  String hoursFigure(num hours) => _hours.format(hours);

  /// A count with the locale's grouping, for the words that print one bare.
  String count(int n) => _count.format(n);

  /// [cents] in whole units with the locale's grouping and the ledger's
  /// symbol where the ledger puts it ("€1,340", "1.340 lei"): a report
  /// reads amounts at a glance, where the cents only widen the figure. A
  /// suffix symbol is bound to its figure.
  String money(int cents) {
    final figure = _moneyFigure(cents.abs());
    final sign = cents < 0 ? '-' : '';
    if (currencySymbol.isEmpty) return '$sign$figure';
    return currencySuffix
        ? '$sign$figure$_noBreak$currencySymbol'
        : '$sign$currencySymbol$figure';
  }

  /// [cents] as [money]'s bare figure ("1,340"): a goal's target after
  /// "of" and what is left or over, the unit said once by the value.
  String _moneyFigure(int cents) => _count.format((cents / 100).round());

  /// A space after a figure ("3 of", "1. Nov"), or between a word and the
  /// figure it introduces ("of 3", "max. 14") — what [_bindNumbers] turns
  /// into a no-break one. A space after a comma or the separator's dot
  /// stays a break.
  static final RegExp _numberSpace = RegExp(
    r'(?<=\d\.?) |(?<=[\p{L}.]) (?=\d)',
    unicode: true,
  );

  /// [text] with every number bound to the words beside it ("2 of 3",
  /// "limit 14", W), so a wrapped caption never strands a figure.
  static String _bindNumbers(String text) =>
      text.replaceAll(_numberSpace, _noBreak);

  /// [minutes] as decimal hours ("18.5 h"), or under an hour in minutes
  /// ("40 min") through the duration grammar the event rows use.
  String hours(int minutes) => minutes < Duration.minutesPerHour
      ? l10n.eventDurationMinutes(minutes)
      : l10n.reportHours(hoursFigure(minutes / Duration.minutesPerHour));

  String tileLabel(ReportTile tile) => switch (tile) {
    ReportTile.events => l10n.reportTileEvents,
    ReportTile.planned => l10n.reportTilePlanned,
    ReportTile.attended => l10n.reportTileAttended,
    ReportTile.missed => l10n.reportTileMissed,
    ReportTile.hours => l10n.reportTileHours,
    ReportTile.tasks => l10n.reportTileTasks,
  };

  /// Whether [value] has nothing in the period — drawn as [nothing] with a
  /// blank detail. A share tile is empty when its whole is, a count when it
  /// is zero.
  static bool isNothing(ReportTileValue value) =>
      value.of != null ? value.of == 0 : value.value == 0;

  /// The value line's text: "31", "21 of 24", "18.5 h", or [nothing]. With
  /// [ofInDetail] — the Totals card's second stage (D37), where "888 of
  /// 888" does not fit half the card — a share reads as its bare figure and
  /// [detail] carries the "of 24".
  String tileValue(ReportTileValue value, {bool ofInDetail = false}) {
    if (isNothing(value)) return nothing;
    if (value.tile == ReportTile.hours) return hours(value.value);
    final of = value.of;
    if (of != null && !ofInDetail) {
      return l10n.reportOfTotal(count(value.value), count(of));
    }
    return count(value.value);
  }

  /// [text] split into figure and unit runs.
  static List<ReportValueRun> valueRuns(String text) {
    final runs = <ReportValueRun>[];
    var at = 0;
    for (final match in _figure.allMatches(text)) {
      if (match.start > at) {
        runs.add((text: text.substring(at, match.start), figure: false));
      }
      runs.add((text: match.group(0)!, figure: true));
      at = match.end;
    }
    if (at < text.length) runs.add((text: text.substring(at), figure: false));
    return runs;
  }

  /// The change against the previous period, signed ("+2", "−1", "±0",
  /// "+1.2 h"), or null when there is no previous period.
  String? delta(ReportTileValue value) {
    final previous = value.previous;
    if (previous == null) return null;
    final change = value.value - previous;
    final sign = change > 0
        ? '+'
        : change < 0
        ? '−'
        : '±';
    final size = change.abs();
    return value.tile == ReportTile.hours
        ? '$sign${hours(size)}'
        : '$sign$size';
  }

  int? _percent(ReportTileValue value) {
    final of = value.of;
    if (value.tile != ReportTile.attended || of == null || of == 0) return null;
    return (value.value * 100 / of).round();
  }

  int? _open(ReportTileValue value) {
    final of = value.of;
    if (value.tile != ReportTile.tasks || of == null || of == 0) return null;
    return of - value.value;
  }

  /// The detail line under a value: the share or what is open, then the
  /// bare delta ("88 % · +2", "3 open · +2", "+4"); empty for [nothing].
  /// With [ofInDetail] a share's whole leads it ("of 24 · 88 % · +2"), the
  /// part [tileValue] then leaves out.
  String detail(ReportTileValue value, {bool ofInDetail = false}) {
    if (isNothing(value)) return '';
    final percent = _percent(value);
    final open = _open(value);
    final of = value.of;
    return [
      if (ofInDetail && of != null && value.tile != ReportTile.hours)
        l10n.reportOfTotalOnly(count(of)),
      if (percent != null) l10n.reportPercent('$percent'),
      if (open != null && open > 0) l10n.reportTasksOpen(open),
      ?delta(value),
    ].join(separator);
  }

  /// What a screen reader hears for a tile ("Attended, 21 of 24, 88
  /// percent, 2 more than September 2026"); [against] names the period the
  /// delta compares with. Hours are spoken with their unit spelled out
  /// ("45 hours, 3 hours less than …", D44), and a count shrinks by
  /// "fewer" where hours shrink by "less".
  ///
  /// [nominalMinutes] is the report's counts-as part of the Hours tile (O):
  /// what the drawn tile leaves to the Totals caption is said here.
  String tileSemantics(
    ReportTileValue value, {
    String? against,
    int nominalMinutes = 0,
  }) {
    final label = tileLabel(value.tile);
    if (isNothing(value)) return '$label, ${l10n.reportTileNone}';
    final isHours = value.tile == ReportTile.hours;
    final percent = _percent(value);
    final open = _open(value);
    final previous = value.previous;
    String? change;
    if (previous != null && against != null) {
      final size = (value.value - previous).abs();
      change = value.value == previous
          ? l10n.reportDeltaSame(against)
          : isHours
          ? value.value > previous
                ? l10n.reportDeltaMore(hoursSpoken(size), against)
                : l10n.reportDeltaLess(hoursSpoken(size), against)
          : value.value > previous
          ? l10n.reportDeltaMoreCount(size, against)
          : l10n.reportDeltaFewerCount(size, against);
    }
    return [
      label,
      if (isHours) hoursSpoken(value.value) else tileValue(value),
      if (percent != null) l10n.reportPercentSpoken('$percent'),
      if (open != null && open > 0) l10n.reportTasksOpen(open),
      ?change,
      if (isHours && nominalMinutes > 0)
        l10n.reportCountedAsSpoken(hoursSpoken(nominalMinutes)),
    ].join(', ');
  }

  /// How the report names [period]: the band's own title.
  String periodName(OverviewPeriod period) =>
      _periodNames.putIfAbsent(period, () => period.menuValue(l10n));

  /// What "against …" names for [report] (D28, D36.3): the previous
  /// period's own name — [previous], the shown period stepped back — when
  /// its whole span was compared, else the span of days counted ("Sep 1 –
  /// Sep 15, 2026" beside October so far); null with no previous period.
  String? comparisonName(CalendarReport report, {OverviewPeriod? previous}) {
    if (identical(report, _comparedReport)) return _comparedName;
    final span = report.previousSpan;
    final counted = report.previousCounted ?? span;
    final String? name;
    if (span == null || counted == null) {
      name = null;
    } else if (counted == span && previous != null) {
      name = periodName(previous);
    } else {
      name = dateSpanLabel(l10n, counted.start, counted.end);
    }
    _comparedReport = report;
    return _comparedName = name;
  }

  /// A count bound to its word, so "2 skipped" never breaks across lines.
  static String _bound(String count) => count.replaceAll(' ', _noBreak);

  /// The caption under the Totals card: "To 30 October · against September
  /// 2026 · 2 skipped · 2 ahead", or "[periodName] · Nothing happened" for
  /// an empty span — composed, because a period's name is a noun phrase no
  /// one preposition fits in three languages (D36.4). The working days
  /// close it ("22 working days · 1 public holiday", the holidays only
  /// beside them) when the service resolved them — when is its rule (P) —
  /// then the counts-as part of the Hours tile (O). In the future tense,
  /// where nothing is counted yet, only the working days, or null.
  ///
  /// [beside] names a saved view compared as a second Totals card (S5
  /// §2.5): "beside Work / Life" takes the "against …" fact's place, since
  /// the two cards cover one span and no delta is drawn.
  String? caption(
    CalendarReport report, {
    required String periodName,
    String? against,
    String? beside,
  }) {
    final working = report.workingDays;
    final days = [
      if (working > 0) _bound(l10n.reportWorkingDays(working)),
      if (working > 0 && report.publicHolidays > 0)
        _bound(l10n.reportPublicHolidays(report.publicHolidays)),
    ];
    if (report.tense == ReportTense.future) {
      return days.isEmpty ? null : days.join(separator);
    }
    if (report.isEmpty) {
      return [
        '$periodName$separator${l10n.reportCaptionNothing}',
        ...days,
      ].join(separator);
    }
    return [
      l10n.reportCaptionTo(_countedTo.format(report.countedTo)),
      if (beside != null)
        l10n.reportCaptionBeside(beside)
      else if (against != null && report.previousSpan != null)
        l10n.reportCaptionAgainst(against),
      if (report.skippedDays > 0)
        _bound(l10n.reportSkippedCount(report.skippedDays)),
      if (report.aheadCount > 0)
        _bound(l10n.reportAheadCount(report.aheadCount)),
      ...days,
      if (report.nominalMinutes > 0)
        l10n.reportCaptionCountedAs(_bindNumbers(hours(report.nominalMinutes))),
    ].join(separator);
  }

  /// The tallest column of [trend], happened and missed together — the
  /// value the plot's top hairline stands for.
  static int peakOf(ReportTrend trend) {
    var peak = 0;
    for (final bucket in trend.buckets) {
      final total = bucket.happened + bucket.missed;
      if (total > peak) peak = total;
    }
    return peak;
  }

  /// [text] with its first letter capitalised: "usually 18:00 – 19:30"
  /// opens the caption when there is no busiest weekday before it.
  static String _sentence(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// The trend's caption facts (D29): the busiest weekday, then the usual
  /// band — the end only when the occurrences have durations. Times follow
  /// the phone's clock style, as the detail sheet writes them.
  List<String> _trendFacts(ReportTrend trend, {required bool use24Hour}) {
    String time(int minute) => EventTimeFormatter.formatMinuteFor(
      minute,
      localeName: l10n.localeName,
      use24Hour: use24Hour,
    );
    final weekday = trend.busiestWeekday;
    final start = trend.usualStartMinute;
    final end = trend.usualEndMinute;
    return [
      // January 2024 opens on a Monday, so its day N is weekday N.
      if (weekday != null)
        l10n.reportTrendBusiest(
          _weekday.format(DateTime.utc(2024, 1, weekday)),
        ),
      if (start != null)
        end != null
            ? l10n.reportTrendUsual(time(start), time(end))
            : l10n.reportTrendUsualAt(time(start)),
    ];
  }

  /// The Over time card's words from one pass over the facts: the caption
  /// under the plot ("Most on Monday · usually 18:00 – 19:30", null with
  /// neither fact) and what a screen reader hears — the same facts, or with
  /// none the peak and the day, week or month it fell on; the plot itself
  /// is not read, and a trend with no occurrence says only its name.
  ///
  /// Under Compare with last year the spoken label closes with last year's
  /// events ("…; same period last year, 41 events"): the ticks are drawn,
  /// so they are heard too. The caption stays this year's.
  ({String? caption, String spoken}) trendWords(
    ReportTrend trend, {
    required bool use24Hour,
  }) {
    final lastYear = trend.lastYear?.fold(0, (sum, n) => sum + n) ?? 0;
    final tail = lastYear > 0
        ? '; ${l10n.reportTrendLastYearSpoken(lastYear)}'
        : '';
    final facts = _trendFacts(trend, use24Hour: use24Hour);
    if (facts.isNotEmpty) {
      return (
        caption: _sentence(facts.join(separator)),
        spoken: l10n.reportTrendSpoken(_sentence(facts.join(', '))) + tail,
      );
    }
    final peak = peakOf(trend);
    if (peak <= 0) {
      return (caption: null, spoken: l10n.reportSectionOverTime + tail);
    }
    final at = trend.buckets.firstWhere(
      (bucket) => bucket.happened + bucket.missed == peak,
    );
    final phrase = switch (trend.unit) {
      ReportTrendUnit.day => l10n.reportTrendPeak(
        '$peak',
        _peakDay.format(at.start),
      ),
      ReportTrendUnit.week => l10n.reportTrendPeakWeek(
        '$peak',
        _peakWeek.format(at.start),
      ),
      ReportTrendUnit.month => l10n.reportTrendPeakMonth(
        '$peak',
        _peakMonth.format(at.start),
      ),
    };
    return (caption: null, spoken: l10n.reportTrendSpoken(phrase) + tail);
  }

  /// The band's subtitle: "31 events · 3 missed", or for a plan "10 planned
  /// · 9.5 h". With goals the missed count gives way to them (Q): "31
  /// events · 2 of 3 goals on pace" while the span runs — met, on pace, not
  /// started and a gap within its limit all count — and "· 2 of 3 goals
  /// met" once it is over; a plan keeps its own form. [goals] false words
  /// the missed form whatever the report holds: the band's fallback where
  /// the goals form would shrink below the 1.0 size.
  String subtitle(CalendarReport report, {bool goals = true}) {
    int? valueOf(ReportTile tile) {
      for (final value in report.tiles) {
        if (value.tile == tile) return value.value;
      }
      return null;
    }

    if (report.tense == ReportTense.future) {
      final minutes = valueOf(ReportTile.hours);
      return [
        l10n.reportPlannedCount(valueOf(ReportTile.planned) ?? 0),
        if (minutes != null && minutes > 0) hours(minutes),
      ].join(separator);
    }
    final events = l10n.reportEventCount(valueOf(ReportTile.events) ?? 0);
    final shown = goals ? report.goals : const <ReportGoal>[];
    if (shown.isNotEmpty) {
      final past = report.tense == ReportTense.past;
      var kept = 0;
      for (final goal in shown) {
        final word = _goalWord(goal, report);
        if (word == _GoalWord.met ||
            word == _GoalWord.within ||
            (!past &&
                (word == _GoalWord.onPace || word == _GoalWord.notStarted))) {
          kept++;
        }
      }
      return [
        events,
        past
            ? l10n.reportGoalsMet(kept, shown.length)
            : l10n.reportGoalsOnPace(kept, shown.length),
      ].join(separator);
    }
    final missed = valueOf(ReportTile.missed) ?? 0;
    return [
      events,
      if (missed > 0) l10n.dayListMissedCount(missed),
    ].join(separator);
  }

  /// The goals subtitle at its widest for [goalCount] goals — "888 events ·
  /// N of N goals on pace", or with [past] "… goals met" — which the nav
  /// draws [subtitle] against: the goals form shows only when this fits
  /// without shrinking below the 1.0 size (Q), so a value never decides it.
  String subtitleTemplate(int goalCount, {bool past = false}) => [
    l10n.reportEventCount(_eights(3)),
    past
        ? l10n.reportGoalsMet(goalCount, goalCount)
        : l10n.reportGoalsOnPace(goalCount, goalCount),
  ].join(separator);

  /// [minutes] as a screen reader says them: "13.2 hours", "1 hour", "40
  /// minutes" — the figure [hours] draws, with the unit spelled out. The
  /// figure is formatted once and read back, so what is heard is what is
  /// shown, and a whole figure takes the plural grammar ("1 hour", ro "20
  /// de ore").
  String hoursSpoken(int minutes) {
    if (minutes < Duration.minutesPerHour) {
      return l10n.reportMinutesSpoken(minutes);
    }
    final figure = hoursFigure(minutes / Duration.minutesPerHour);
    final whole = int.tryParse(figure);
    return whole != null
        ? l10n.reportWholeHoursSpoken(whole)
        : l10n.reportHoursSpoken(figure);
  }

  /// A group header's caption: "14 · 13.2 h · 2 missed" in Categories,
  /// "2 missed" in Missed (nothing was spent on a missed day), "1 · 1 h" in
  /// Ahead (nothing ahead can be missed yet). A count with nothing to join
  /// says its noun ("1 event", D44): a bare "1" reads as no fact at all.
  ///
  /// A profiled category's Categories header leads with its primary (N) —
  /// "31 h · 12", "8 of 10 attended · 12", "23 days ago · 4" — from its
  /// [measures]; an unprofiled one, a Count primary or a primary with no
  /// value keeps the facts above. [use24Hour] writes a Timing primary on
  /// the phone's clock.
  String groupFacts(
    ReportCard card,
    ReportCategoryGroup group, {
    ReportMeasures? measures,
    bool use24Hour = true,
  }) {
    if (card == ReportCard.missed) return l10n.dayListMissedCount(group.missed);
    final primary = card == ReportCard.categories
        ? _primaryFact(measures, use24Hour: use24Hour, spoken: false)
        : null;
    if (primary != null) {
      return [
        primary,
        count(group.count),
        if (group.missed > 0) l10n.dayListMissedCount(group.missed),
      ].join(separator);
    }
    if (group.minutes <= 0 && group.missed <= 0) {
      return l10n.reportEventCount(group.count);
    }
    return [
      count(group.count),
      if (group.minutes > 0) hours(group.minutes),
      if (group.missed > 0) l10n.dayListMissedCount(group.missed),
    ].join(separator);
  }

  /// What a screen reader hears for a group header ("Gym, 14 events, 13.2
  /// hours, 2 missed"): the caption's figures read badly aloud. A profiled
  /// header says its primary first, as [groupFacts] draws it: "Work, 31
  /// hours, 12 events, 1 missed".
  String groupSpoken(
    ReportCard card,
    ReportCategoryGroup group, {
    required String category,
    ReportMeasures? measures,
    bool use24Hour = true,
  }) {
    final counts = card != ReportCard.missed;
    final primary = card == ReportCard.categories
        ? _primaryFact(measures, use24Hour: use24Hour, spoken: true)
        : null;
    if (primary != null) {
      return [
        category,
        primary,
        l10n.reportEventCount(group.count),
        if (group.missed > 0) l10n.dayListMissedCount(group.missed),
      ].join(spokenSeparator);
    }
    return [
      category,
      if (counts) l10n.reportEventCount(group.count),
      if (counts && group.minutes > 0) hoursSpoken(group.minutes),
      if (group.missed > 0) l10n.dayListMissedCount(group.missed),
    ].join(spokenSeparator);
  }

  /// Joins the facts a screen reader hears: a comma is a pause, where the
  /// drawn [separator]'s dot would be read out as a word or skipped.
  static const String spokenSeparator = ', ';

  /// A routine aggregate's caption: "8 of 10 attended · 8 h".
  String routineCaption(ReportRoutineRow row) => [
    l10n.reportAttendedOf(row.total, row.attended),
    if (row.minutes > 0) hours(row.minutes),
  ].join(separator);

  /// [day]'s label on a row: "Thu 8", or "Thu 8 Oct" when the period spans
  /// months (U). No year: a span reaches a second year's same day only in
  /// its 366th day.
  String _rowDay(DateTime day, {required bool spansMonths}) {
    // The symbols run from Sunday; `DateTime.weekday` from Monday as 1.
    final weekday =
        _rowSymbols.SHORTWEEKDAYS[day.weekday % DateTime.daysPerWeek];
    final ofMonth = _rowDayOfMonth.format(day);
    return spansMonths
        ? l10n.reportRowDayMonth(
            weekday,
            ofMonth,
            _rowSymbols.SHORTMONTHS[day.month - 1],
          )
        : l10n.reportRowDay(weekday, ofMonth);
  }

  /// A dated row's subtitle, composed by the report (§4.3): the day, the
  /// start time of a timed [event] on the phone's clock, its duration, the
  /// count label the day panel shows for that day ("32 years", "Week 3"),
  /// then "5 of 8 tasks" — "Thu 8 · 17:00 · 1 h". Not the day panel's tail:
  /// a report row is one fact per occurrence, so no end time, no "All day",
  /// no recurrence word and no alert note.
  String rowSubtitle(
    ReportDatedRow row, {
    required CalendarEvent event,
    required bool use24Hour,
    required bool spansMonths,
  }) {
    final time = event.time;
    final duration = time?.durationMinutes ?? 0;
    final tasks = row.tasks;
    return [
      _rowDay(row.day, spansMonths: spansMonths),
      if (time != null)
        EventTimeFormatter.formatMinuteFor(
          time.startMinute,
          localeName: l10n.localeName,
          use24Hour: use24Hour,
        ),
      if (duration > 0) hours(duration),
      ?RecurrenceFormatter.countLabel(event, row.day, l10n),
      if (tasks != null) l10n.reportTasksOf(tasks.total, tasks.ticked),
    ].join(separator);
  }

  /// A profiled Categories header's leading fact, or null to keep today's
  /// facts: an unprofiled category, a Count primary (the count already
  /// leads), or a primary with nothing to say over the span. Only Hours is
  /// spoken otherwise than drawn.
  String? _primaryFact(
    ReportMeasures? measures, {
    required bool use24Hour,
    required bool spoken,
  }) {
    if (measures == null || !measures.profiled) return null;
    final lastSeen = measures.lastSeenDays;
    final leadTime = measures.leadTimeDays;
    final start = measures.medianStartMinute;
    final until = measures.daysUntil;
    switch (measures.primary) {
      case ReportMeasure.count:
        return null;
      case ReportMeasure.events:
        return l10n.reportEventCount(measures.events);
      case ReportMeasure.hours:
        return spoken ? hoursSpoken(measures.minutes) : hours(measures.minutes);
      case ReportMeasure.attendance:
        return l10n.reportAttendedOf(measures.tracked, measures.attended);
      case ReportMeasure.cancelled:
        return l10n.reportCancelledCount(measures.cancelled);
      case ReportMeasure.tasks:
        return l10n.reportTasksOf(measures.tasksTotal, measures.tasksTicked);
      case ReportMeasure.money:
        // Spent leads, as a ledger's net does; money only received is
        // signed, so it never reads as spending.
        return measures.spentCents == 0 && measures.receivedCents > 0
            ? '+${money(measures.receivedCents)}'
            : money(measures.spentCents);
      case ReportMeasure.lastSeen:
        return lastSeen == null ? null : l10n.reportLastSeenAgo(lastSeen);
      case ReportMeasure.leadTime:
        return leadTime == null ? null : l10n.reportLeadTime(leadTime);
      case ReportMeasure.timing:
        return start == null
            ? null
            : l10n.reportTrendUsualAt(
                EventTimeFormatter.formatMinuteFor(
                  start,
                  localeName: l10n.localeName,
                  use24Hour: use24Hour,
                ),
              );
      case ReportMeasure.daysUntil:
        return until == null ? null : l10n.reportDaysUntil(until);
    }
  }

  /// [n] written in [ReportMetrics.goalTemplateDigit] ("888" for 3).
  static int _eights(int n) => int.parse(ReportMetrics.goalTemplateDigit * n);

  /// The period [goal]'s caption, glyph and meter read (F): in a current
  /// span the one holding today; in a plan its first; in a past span the
  /// last that has closed, else its last, still open and read as current —
  /// a past week under a monthly goal whose month runs on. Null for a gap
  /// goal.
  static ReportGoalPeriod? goalPeriod(ReportGoal goal, CalendarReport report) {
    final periods = goal.periods;
    if (periods.isEmpty) return null;
    switch (report.tense) {
      case ReportTense.current:
        final today = report.today;
        for (final period in periods) {
          if (!period.start.isAfter(today) && !period.end.isBefore(today)) {
            return period;
          }
        }
        return periods.last;
      case ReportTense.future:
        return periods.first;
      case ReportTense.past:
        return closedPeriods(goal, report).lastOrNull ?? periods.last;
    }
  }

  /// [goal]'s periods in the span that ended before today, oldest first:
  /// what a past span of several periods counts as met (F). A period is
  /// closed by its end, never by the span's tense — a past month's last
  /// week can run into today's.
  static List<ReportGoalPeriod> closedPeriods(
    ReportGoal goal,
    CalendarReport report,
  ) => [
    for (final period in goal.periods)
      if (period.end.isBefore(report.today)) period,
  ];

  /// Whether [goal]'s caption counts its closed periods met ("3 of 4 weeks
  /// met", F) rather than reading one period: a past span of several, one
  /// of them closed at least.
  static bool _readsPeriodsMet(ReportGoal goal, CalendarReport report) =>
      report.tense == ReportTense.past &&
      goal.periods.length > 1 &&
      goal.periods.first.end.isBefore(report.today);

  /// [goal]'s state as one word, which the glyph's spoken label and the
  /// band's goals count both read — the state of the period the caption
  /// reads, so the two never disagree.
  _GoalWord _goalWord(ReportGoal goal, CalendarReport report) {
    if (goal.target.kind == TargetKind.maxGap) {
      return switch (goal.gap?.state) {
        null => _GoalWord.notStarted,
        GapState.within => _GoalWord.within,
        GapState.due => _GoalWord.dueSoon,
        GapState.overdue => _GoalWord.pastLimit,
      };
    }
    if (_readsPeriodsMet(goal, report)) {
      // Several closed periods are met only when every one was.
      if (closedPeriods(goal, report).every((p) => p.state == GoalState.met)) {
        return _GoalWord.met;
      }
      return goal.target.kind == TargetKind.atLeast
          ? _GoalWord.missed
          : _GoalWord.over;
    }
    final period = goalPeriod(goal, report);
    if (period == null) return _GoalWord.notStarted;
    return switch (period.state) {
      GoalState.met => _GoalWord.met,
      GoalState.onPace => _GoalWord.onPace,
      GoalState.behind => _GoalWord.behind,
      GoalState.over => _GoalWord.over,
      GoalState.missed => _GoalWord.missed,
      GoalState.notDue => _GoalWord.notStarted,
      GoalState.future => _GoalWord.planned,
    };
  }

  /// What a screen reader hears for [goal]'s state glyph — the shape and
  /// this word carry the state, never the colour alone.
  String goalStateWord(ReportGoal goal, CalendarReport report) =>
      switch (_goalWord(goal, report)) {
        _GoalWord.met => l10n.reportGoalStateMet,
        _GoalWord.onPace => l10n.reportGoalStateOnPace,
        _GoalWord.behind => l10n.reportGoalStateBehind,
        _GoalWord.over => l10n.reportGoalStateOver,
        _GoalWord.missed => l10n.reportGoalStateMissed,
        _GoalWord.notStarted => l10n.reportGoalStateNotStarted,
        _GoalWord.planned => l10n.reportGoalStatePlanned,
        _GoalWord.within => l10n.reportGoalStateWithin,
        _GoalWord.dueSoon => l10n.reportGoalStateDueSoon,
        _GoalWord.pastLimit => l10n.reportGoalStatePastLimit,
      };

  /// A goal value beside its target ("31 h" of 40): hours always in hours,
  /// since "40 min of 40" would mix two units.
  String _goalValue(ReportMeasure measure, int value) => switch (measure) {
    ReportMeasure.hours => l10n.reportHours(
      hoursFigure(value / Duration.minutesPerHour),
    ),
    ReportMeasure.money => money(value),
    _ => count(value),
  };

  /// A goal's target after "of": the bare figure, its unit said once by the
  /// value before it.
  String _goalFigure(ReportMeasure measure, int value) => switch (measure) {
    ReportMeasure.hours => hoursFigure(value / Duration.minutesPerHour),
    ReportMeasure.money => _moneyFigure(value),
    _ => count(value),
  };

  /// What is left, over or still needed, in the measure's unit — money
  /// bare, its symbol said once by the value before it.
  String _goalAmount(ReportMeasure measure, int value) => switch (measure) {
    ReportMeasure.hours => hours(value),
    ReportMeasure.money => _moneyFigure(value),
    _ => count(value),
  };

  /// "one more by Sunday", "2 h more by Nov 30", "one more today".
  String _goalMore(
    ReportMeasure measure,
    TargetPeriod period,
    int amount,
    DateTime end,
  ) {
    final counted =
        measure != ReportMeasure.hours && measure != ReportMeasure.money;
    if (period == TargetPeriod.day) {
      return counted
          ? l10n.reportGoalMoreToday(amount)
          : l10n.reportGoalAmountMoreToday(_goalAmount(measure, amount));
    }
    // A week ends on its weekday; a month or a year on its date.
    final day = period == TargetPeriod.week
        ? _weekday.format(end)
        : _dayMonth.format(end);
    return counted
        ? l10n.reportGoalMoreBy(amount, day)
        : l10n.reportGoalAmountMoreBy(_goalAmount(measure, amount), day);
  }

  /// A periodic goal's facts in [shape], from plain numbers so the caption
  /// and its templates (D) are one sentence. [amount] is what is still
  /// needed, left or over; [sayPeriod] adds "this week" to what is left (E).
  List<String> _periodFacts(
    _GoalShape shape, {
    required ReportMeasure measure,
    required TargetPeriod period,
    required int value,
    required int target,
    required int amount,
    required DateTime end,
    required bool sayPeriod,
  }) {
    if (shape == _GoalShape.planned) {
      return [
        l10n.reportGoalPlanned(
          _goalValue(measure, value),
          _goalFigure(measure, target),
        ),
      ];
    }
    final progress = l10n.reportOfTotal(
      _goalValue(measure, value),
      _goalFigure(measure, target),
    );
    final fact = switch (shape) {
      _GoalShape.pace => _goalMore(measure, period, amount, end),
      _GoalShape.done => l10n.reportGoalDone(period.name),
      _GoalShape.left =>
        sayPeriod
            ? l10n.reportGoalLeftIn(_goalAmount(measure, amount), period.name)
            : l10n.reportGoalLeft(_goalAmount(measure, amount)),
      _GoalShape.over => l10n.reportGoalOver(_goalAmount(measure, amount)),
      _GoalShape.closedMet => l10n.reportGoalMet,
      _GoalShape.closedMissed => l10n.reportGoalMissed,
      _GoalShape.closedWithin => l10n.reportGoalWithin,
      _GoalShape.closedOver => l10n.reportGoalOverWord,
      _GoalShape.planned => '',
    };
    return [progress, fact];
  }

  /// A gap goal's facts: [days] since the last kept day, null for none
  /// yet, or [long] for "over a year" (the lookback's floor).
  List<String> _gapFacts({int? days, bool long = false, required int limit}) =>
      [
        long
            ? l10n.reportGoalGapLong
            : days == null
            ? l10n.reportGoalGapNone
            : l10n.reportGoalGapDays(days),
        l10n.reportGoalLimit(limit),
      ];

  /// Whether the period read differs from the span shown, so what is left
  /// says its period (E): a week's goal in a month report.
  static bool _saysPeriod(ReportGoalPeriod? period, CalendarReport report) =>
      period != null &&
      (period.start != report.span.start || period.end != report.span.end);

  /// The shape [reading] takes in [goal]'s caption: one word only once the
  /// period has closed (K), whatever the span's tense — an open period in a
  /// past span still reads its pace.
  static _GoalShape _shapeOf(
    ReportGoal goal,
    ReportGoalPeriod reading,
    CalendarReport report,
  ) {
    final atLeast = goal.target.kind == TargetKind.atLeast;
    final state = reading.state;
    if (state == GoalState.future) return _GoalShape.planned;
    if (reading.end.isBefore(report.today)) {
      if (atLeast) {
        return state == GoalState.met
            ? _GoalShape.closedMet
            : _GoalShape.closedMissed;
      }
      return state == GoalState.over
          ? _GoalShape.closedOver
          : _GoalShape.closedWithin;
    }
    if (state == GoalState.over) return _GoalShape.over;
    if (!atLeast) return _GoalShape.left;
    return state == GoalState.met || reading.value >= goal.target.value
        ? _GoalShape.done
        : _GoalShape.pace;
  }

  /// Whether [goal]'s caption already says its state in words — a closed
  /// period's one word or the periods met — so the spoken label does not
  /// say it twice ("Met, met").
  static bool _captionSaysState(ReportGoal goal, CalendarReport report) {
    if (goal.target.kind == TargetKind.maxGap || goal.target.period == null) {
      return false;
    }
    if (_readsPeriodsMet(goal, report)) return true;
    final reading = goalPeriod(goal, report);
    if (reading == null) return false;
    return switch (_shapeOf(goal, reading, report)) {
      _GoalShape.closedMet ||
      _GoalShape.closedMissed ||
      _GoalShape.closedWithin ||
      _GoalShape.closedOver => true,
      _ => false,
    };
  }

  /// [goal]'s caption facts without the streak, which the drawn and the
  /// spoken forms word apart.
  List<String> _goalFacts(ReportGoal goal, CalendarReport report) {
    final target = goal.target;
    final period = target.period;
    if (target.kind == TargetKind.maxGap || period == null) {
      final gap = goal.gap;
      return _gapFacts(
        days: gap?.daysSince,
        long: gap?.beyondLookback ?? false,
        limit: target.value,
      );
    }
    if (_readsPeriodsMet(goal, report)) {
      final closed = closedPeriods(goal, report);
      final met = closed.where((p) => p.state == GoalState.met).length;
      return [l10n.reportGoalPeriodsMet(met, closed.length, period.name)];
    }
    final reading = goalPeriod(goal, report);
    if (reading == null) return const [];
    final shape = _shapeOf(goal, reading, report);
    final value = reading.value;
    return _periodFacts(
      shape,
      measure: goal.measure,
      period: period,
      value: value,
      target: target.value,
      amount: shape == _GoalShape.over
          ? value - target.value
          : math.max(0, target.value - value),
      end: reading.end,
      sayPeriod: _saysPeriod(reading, report),
    );
  }

  /// Whether [goal]'s caption ends on its streak (B): a periodic goal whose
  /// last closed periods were met.
  static bool _hasStreak(ReportGoal goal) =>
      goal.streak > 0 && goal.target.kind != TargetKind.maxGap;

  /// A goal row's caption (§2.2): "2 of 3 · one more by Sunday · 4 in a
  /// row", "31 h of 40 · 9 h left", "23 days · limit 14", "3 of 4 weeks
  /// met", "2 of 3 planned". Every number is bound to its words (W).
  String goalCaption(ReportGoal goal, CalendarReport report) => [
    ..._goalFacts(goal, report),
    if (_hasStreak(goal)) l10n.reportGoalStreak(goal.streak),
  ].map(_bindNumbers).join(separator);

  /// What a screen reader hears for a goal row: "Gym, 2 of 3, one more by
  /// Sunday, on pace, 4 weeks in a row" — [name] is the category's display
  /// name, the streak said with its period. The state word is left out
  /// where the caption already says it ("Gym, 3 of 3, Met").
  String goalSpoken(String name, ReportGoal goal, CalendarReport report) {
    final period = goal.target.period;
    return [
      name,
      ..._goalFacts(goal, report),
      if (!_captionSaysState(goal, report)) goalStateWord(goal, report),
      if (_hasStreak(goal) && period != null)
        l10n.reportGoalStreakSpoken(goal.streak, period.name),
    ].join(spokenSeparator);
  }

  /// Every caption [goal] can show in [report], each figure written in
  /// [ReportMetrics.goalTemplateDigit] at the target's digit count — one
  /// more for the met and over states, hours with the locale's decimal
  /// ("88.8 h") — the streak and the periods met in two digits, three for a
  /// day goal in a span of 100 days or more, and the real period-end word.
  /// The set is the reading's own, as the date decides it and the value
  /// never does: a closed period's words, the periods met, a plan's, or
  /// the open sentences, their "one more" among them. The card reserves
  /// the lines the widest of them wraps to (D), so a row's height never
  /// follows its value.
  List<String> goalTemplates(ReportGoal goal, CalendarReport report) {
    final target = goal.target;
    final measure = goal.measure;
    final whole = switch (measure) {
      ReportMeasure.hours => target.value ~/ Duration.minutesPerHour,
      ReportMeasure.money => target.value ~/ 100,
      _ => target.value,
    };
    final digits = '$whole'.length;
    final span = report.span;
    final spanDays = span.end.difference(span.start).inDays + 1;
    final tally = math.max(
      ReportMetrics.goalTemplateStreak,
      _eights('${target.period == TargetPeriod.day ? spanDays : 0}'.length),
    );
    String line(List<String> facts, {required bool streak}) => [
      ...facts,
      if (streak) l10n.reportGoalStreak(tally),
    ].map(_bindNumbers).join(separator);

    final period = target.period;
    if (target.kind == TargetKind.maxGap || period == null) {
      final limit = _eights(digits);
      return [
        line(_gapFacts(days: _eights(digits + 1), limit: limit), streak: false),
        line(_gapFacts(limit: limit), streak: false),
        line(_gapFacts(long: true, limit: limit), streak: false),
      ];
    }
    // "88.8 h" and "88.88": the fraction is written in the digit too.
    final digit = int.parse(ReportMetrics.goalTemplateDigit);
    int figure(int width) => switch (measure) {
      ReportMeasure.hours =>
        _eights(width) * Duration.minutesPerHour +
            digit * Duration.minutesPerHour ~/ 10,
      ReportMeasure.money => _eights(width) * 100,
      _ => _eights(width),
    };
    if (_readsPeriodsMet(goal, report)) {
      return [
        line([
          l10n.reportGoalPeriodsMet(tally, tally, period.name),
        ], streak: true),
      ];
    }
    final reading = goalPeriod(goal, report);
    if (reading == null) return [line(const [], streak: true)];
    final short = figure(digits);
    final long = figure(digits + 1);
    final shapes = switch (_shapeOf(goal, reading, report)) {
      _GoalShape.planned => [(_GoalShape.planned, long, 0)],
      _GoalShape.closedMet || _GoalShape.closedMissed => [
        (_GoalShape.closedMet, long, 0),
        (_GoalShape.closedMissed, short, 0),
      ],
      _GoalShape.closedWithin || _GoalShape.closedOver => [
        (_GoalShape.closedWithin, short, 0),
        (_GoalShape.closedOver, long, 0),
      ],
      // "one more by Sunday" is wider than "8 more by Sunday".
      _GoalShape.pace || _GoalShape.done => [
        (_GoalShape.pace, short, short),
        (_GoalShape.pace, short, 1),
        (_GoalShape.done, long, 0),
      ],
      _GoalShape.left || _GoalShape.over => [
        (_GoalShape.left, short, short),
        (_GoalShape.over, long, long),
      ],
    };
    return [
      for (final (shape, value, amount) in shapes)
        line(
          _periodFacts(
            shape,
            measure: measure,
            period: period,
            value: value,
            target: short,
            amount: amount,
            end: reading.end,
            sayPeriod: _saysPeriod(reading, report),
          ),
          streak: true,
        ),
    ];
  }

  /// What a screen reader hears for an insight's severity glyph (J): 3
  /// "Needs attention" down to 0 "For information".
  String insightSeverityWord(int severity) => switch (severity) {
    >= 3 => l10n.reportInsightAttention,
    2 => l10n.reportInsightNotable,
    1 => l10n.reportInsightObservation,
    _ => l10n.reportInsightInfo,
  };

  /// An insight row's label (I): [category] — the display name of the
  /// insight's category, resolved by the caller as for [groupSpoken] —
  /// "#tag" as typed for the tag rules, or the rule's own noun where no one
  /// category is the subject (M1 "Bills", A2 "Next trip"), or for D3 / D4
  /// the event's title ("Electricity bill" above "3 days not marked"):
  /// those are about one event, which the category's name would hide. A1
  /// keeps its category ("Birthdays · 3 ahead by Nov 30"), so the subject
  /// stays a noun and the count moves to the detail.
  String insightSubject(
    ReportInsight insight,
    CalendarReport report, {
    required String category,
  }) => switch (insight.rule) {
    InsightRule.r1 || InsightRule.r2 => '#${_tagLabel(insight, report)}',
    InsightRule.m1 => l10n.reportInsightBills,
    InsightRule.a2 => l10n.reportInsightNextTrip,
    InsightRule.d3 ||
    InsightRule.d4 => report.events[insight.eventId]?.title ?? category,
    _ => category,
  };

  String _tagLabel(ReportInsight insight, CalendarReport report) {
    final key = insight.tagKey ?? '';
    for (final tag in report.tags) {
      if (tag.key == key) return tag.label;
    }
    return key;
  }

  /// [index] (0–6 from [weekStart], as P1 counts) as the locale's weekday.
  String _weekdayFrom(int index, CalendarWeekStart weekStart) {
    final weekday = (weekStart.weekday - 1 + index) % DateTime.daysPerWeek + 1;
    // January 2024 opens on a Monday, so its day N is weekday N.
    return _weekday.format(DateTime.utc(2024, 1, weekday));
  }

  /// An insight row's caption: the sentence without its subject (§6.7),
  /// numbers bound to their words. [category] is the subject's name, which
  /// R2 also says; [weekStart] places P1's weekdays, which the report
  /// counts from the app's week start and does not carry. T1 and T2 word
  /// the value in the category's primary unit, T3 the spent money; their
  /// period is the compared fold's, named as the Totals caption's "against
  /// …" names it.
  String insightDetail(
    ReportInsight insight,
    CalendarReport report, {
    required String category,
    required CalendarWeekStart weekStart,
  }) {
    // A G rule's numbers are in its goal's unit and period.
    final goal = report.goals
        .where((goal) => goal.categoryId == insight.categoryId)
        .firstOrNull;
    final measure = goal?.measure ?? ReportMeasure.count;
    final period = goal?.target.period ?? TargetPeriod.week;
    final n1 = insight.n1;
    final n2 = insight.n2;
    final n3 = insight.n3;
    String progress() =>
        l10n.reportOfTotal(_goalValue(measure, n1), _goalFigure(measure, n2));
    final title = report.events[insight.eventId]?.title ?? '';
    final day = insight.day ?? report.today;
    final text = switch (insight.rule) {
      InsightRule.g1 => l10n.reportInsightBehind(
        progress(),
        _goalMore(measure, period, n3, insight.dayEnd ?? day),
      ),
      InsightRule.g2 => l10n.reportInsightOver(
        progress(),
        period.name,
        l10n.reportGoalOver(_goalAmount(measure, n3)),
      ),
      InsightRule.g3 => l10n.reportInsightDone(
        progress(),
        l10n.reportGoalDone(period.name),
      ),
      InsightRule.g4 =>
        insight.alternate
            ? l10n.reportInsightStreakEnded(n1, period.name)
            : l10n.reportGoalStreakSpoken(n1, period.name),
      InsightRule.g5 =>
        insight.alternate
            ? [
                l10n.reportInsightAllowanceUnused(n1),
                l10n.reportInsightDaysLeftInYear(n3),
              ].join(spokenSeparator)
            : [
                l10n.reportInsightAllowance(count(n1), n2),
                l10n.reportInsightMonthsToGo(n3),
              ].join(spokenSeparator),
      InsightRule.d1 =>
        insight.beyondLookback
            ? l10n.reportInsightGapOverdueLong(n2)
            : l10n.reportInsightGapOverdue(n1, n2),
      InsightRule.d2 => l10n.reportInsightGapDue(n1),
      InsightRule.d3 =>
        insight.alternate
            ? l10n.reportInsightExpired(n1)
            : l10n.reportInsightExpires(n1),
      InsightRule.d4 => l10n.reportInsightUnmarked(_dayMonth.format(day), n1),
      InsightRule.d5 => l10n.reportInsightEpisodeNext(_weekday.format(day)),
      InsightRule.p1 => l10n.reportInsightWeekdays(
        _weekdayFrom(n3, weekStart),
        '$n1',
        _weekdayFrom(insight.n4, weekStart),
        '$n2',
      ),
      InsightRule.p2 =>
        insight.alternate
            ? l10n.reportInsightWeekend(hours(insight.minutes))
            : l10n.reportInsightLateEvenings(n1),
      InsightRule.p3 =>
        insight.alternate
            ? l10n.reportInsightBedtimeSpread(hours(n2))
            : l10n.reportInsightShortNights(
                n1,
                hours(AnalyticsMetrics.sleepShortMinutes),
              ),
      InsightRule.p4 => l10n.reportInsightMeetingShare(
        hours(insight.minutes),
        '${((insight.ratio ?? 0) * 100).round()}',
      ),
      InsightRule.p5 => l10n.reportInsightCancelled(n1, n2),
      InsightRule.p6 => l10n.reportInsightRestGap(n1),
      InsightRule.m1 => l10n.reportInsightBillsAhead(
        money(insight.cents),
        AnalyticsMetrics.billsAheadDays,
      ),
      InsightRule.m2 => l10n.reportInsightBillsYear(money(insight.cents), n1),
      InsightRule.r1 =>
        insight.alternate
            ? l10n.reportInsightTagGapLong(n1)
            : l10n.reportInsightGapOverdue(n1, n2),
      InsightRule.r2 => l10n.reportInsightTagTop(category, n1),
      InsightRule.l1 => l10n.reportInsightLeadTime(n1),
      InsightRule.l2 => l10n.reportInsightOpenPast(n1),
      InsightRule.a1 => l10n.reportInsightAhead(
        n1,
        _dayMonth.format(insight.dayEnd ?? day),
      ),
      InsightRule.a2 => l10n.reportInsightTrip(title, n1),
      InsightRule.t1 || InsightRule.t2 => _trendSentence(
        _trendValue(
          report.measures[insight.categoryId]?.primary ?? ReportMeasure.count,
          n1,
        ),
        insight,
        report,
        rose: n1 > n2,
      ),
      InsightRule.t3 => _trendSentence(
        money(insight.cents),
        insight,
        report,
        rose: insight.cents > n1,
      ),
    };
    return _bindNumbers(text);
  }

  /// A trend's value in its primary's unit: money with its symbol, as it
  /// stands alone in the sentence.
  String _trendValue(ReportMeasure primary, int value) =>
      primary == ReportMeasure.money
      ? money(value)
      : _goalAmount(primary, value);

  /// "31 h, up 35 % on September 2026": [value] this span and the change
  /// against the compared fold. The direction follows the signed ratio,
  /// the values only where the ratio is absent.
  String _trendSentence(
    String value,
    ReportInsight insight,
    CalendarReport report, {
    required bool rose,
  }) {
    final ratio = insight.ratio;
    final up = ratio != null ? ratio > 0 : rose;
    final percent = '${((ratio ?? 0).abs() * 100).round()}';
    final period = _comparedSpanName(report);
    return up
        ? l10n.reportInsightUpOn(value, percent, period)
        : l10n.reportInsightDownOn(value, percent, period);
  }

  /// The compared fold's days by name, as [comparisonName] names them from
  /// the period: a whole calendar month by its month ("September 2026",
  /// under last year "October 2025"), a whole year by its number, any other
  /// span by its dates. Read from the span, so it holds whichever period
  /// the fold compared with — the insight card has no period to step.
  String _comparedSpanName(CalendarReport report) {
    final span = report.previousCounted ?? report.previousSpan;
    if (span == null) return '';
    final (:start, :end) = span;
    if (start.day == 1 && end == DateTime.utc(start.year, start.month + 1, 0)) {
      return _peakMonth.format(start);
    }
    if (start.month == 1 &&
        start.day == 1 &&
        end == DateTime.utc(start.year, 12, 31)) {
      return '${start.year}';
    }
    return dateSpanLabel(l10n, start, end);
  }

  /// What a screen reader hears for an insight row: "Needs attention. Car
  /// service, 212 days since the last, the limit is 180".
  String insightSpoken(
    ReportInsight insight,
    CalendarReport report, {
    required String category,
    required CalendarWeekStart weekStart,
  }) =>
      '${insightSeverityWord(insight.severity)}. '
      '${insightSubject(insight, report, category: category)}'
      '$spokenSeparator'
      '${insightDetail(insight, report, category: category, weekStart: weekStart)}';

  /// A Due soon row's phrase (§2.4, K): "Overdue 32 days", "Due in 18
  /// days", "Expires in 42 days", "Expired 3 days ago", "Nov 1 · not
  /// marked", "Dec 1 · in 12 days"; a gap last kept before the lookback
  /// "Over a year ago". Numbers are bound to their words (W).
  String dueCaption(ReportDueRow row, CalendarReport report) {
    final days = row.days;
    final List<String> facts;
    if (row.kind == ReportDueKind.gap && row.beyondLookback) {
      facts = [l10n.reportDueLong];
    } else {
      facts = switch (row.kind) {
        ReportDueKind.gap => [
          row.state == ReportDueState.overdue
              ? l10n.reportDueOverdue(days)
              : l10n.reportDueIn(days),
        ],
        ReportDueKind.expiry => [
          row.state == ReportDueState.overdue
              ? l10n.reportDueExpired(days)
              : l10n.reportDueExpires(days),
        ],
        ReportDueKind.unmarked => [
          _dayMonth.format(row.day),
          l10n.reportDueNotMarked,
        ],
        ReportDueKind.upcoming => [
          _dayMonth.format(row.day),
          l10n.reportDaysUntil(days),
        ],
      };
    }
    return facts.map(_bindNumbers).join(separator);
  }

  /// What a screen reader hears for a Due soon row: "{title}, {phrase}",
  /// [title] the event's.
  String dueSpoken(String title, ReportDueRow row, CalendarReport report) =>
      '$title$spokenSeparator${dueCaption(row, report)}';

  /// The `reportTagCount` noun of a tag whose first category is of [kind]
  /// (S5 §2.2, B): four kinds name what the tag was seen at, every other —
  /// Bill and Custom among them — counts "times".
  static String _tagNoun(CategoryKind kind) => switch (kind) {
    CategoryKind.social ||
    CategoryKind.trip ||
    CategoryKind.maintenance ||
    CategoryKind.workout => kind.name,
    _ => 'other',
  };

  /// The longest of [names] by length: the template's stand-in for the
  /// widest; the row measures the real width.
  static String _longest(List<String> names) =>
      names.reduce((a, b) => b.length > a.length ? b : a);

  /// [day] as a screen reader hears it on a tag ("Saturday 24 October"):
  /// the row's template with the long names, the month always, as no span
  /// is heard beside it.
  String _rowDaySpoken(DateTime day) => l10n.reportRowDayMonth(
    _rowSymbols.WEEKDAYS[day.weekday % DateTime.daysPerWeek],
    _rowDayOfMonth.format(day),
    _rowSymbols.MONTHS[day.month - 1],
  );

  /// "today", "yesterday" or "last [day]" for a tag last seen on [seen].
  String _tagLastSeen(DateTime seen, DateTime today, String day) {
    final days = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(seen.year, seen.month, seen.day)).inDays;
    return l10n.reportTagLastSeen(switch (days) {
      0 => 'today',
      1 => 'yesterday',
      _ => 'other',
    }, day);
  }

  /// A net amount as a tag's fact: spent reads as [money], money only
  /// received is signed "+", so it never reads as spending.
  String _netMoney(int net) => net < 0 ? '+${money(-net)}' : money(net);

  /// A By tag header's words (S5 §2.2): the caption's two facts, the
  /// template lines its height is reserved from, and the spoken label.
  ///
  /// The count leads with the noun of [ReportTag.kind] — a Trip counts its
  /// events ("2 trips") because its second fact is the days ("5 days").
  /// Maintenance and Bill follow with the net money ("1,240", "+1,240"
  /// received only), every other kind — and money at 0 — with the day last
  /// seen as the dated rows write it, the month only when [spansMonths];
  /// with no day seen up to [today] the count stands alone.
  ///
  /// [templates] is one line per shape the caption can take, every count
  /// written as 888 and the day as the locale's longest names, so the row
  /// reserves its lines from the shapes and a refold never changes its
  /// height (S4 D). A money line keeps the real figure's digit count. The
  /// spoken label says the day in full and never the '#'.
  ({String caption, List<String> templates, String spoken}) tagWords(
    ReportTag tag, {
    required bool spansMonths,
    required DateTime today,
  }) {
    final noun = _tagNoun(tag.kind);
    final trip = tag.kind == CategoryKind.trip;
    final money =
        tag.kind == CategoryKind.maintenance || tag.kind == CategoryKind.bill;
    final net = tag.spentCents - tag.receivedCents;
    final seen = tag.lastSeenDay;
    final counted = l10n.reportTagCount(noun, trip ? tag.events : tag.count);
    final String? drawn;
    final String? heard;
    if (trip) {
      drawn = heard = l10n.reportTagDays(tag.count);
    } else if (money && net != 0) {
      drawn = heard = _netMoney(net);
    } else if (seen != null) {
      drawn = _tagLastSeen(
        seen,
        today,
        _rowDay(seen, spansMonths: spansMonths),
      );
      heard = _tagLastSeen(seen, today, _rowDaySpoken(seen));
    } else {
      drawn = heard = null;
    }

    final widest = l10n.reportTagCount(noun, _eights(3));
    String template(String? fact) =>
        [widest, ?fact].map(_bindNumbers).join(separator);
    final weekday = _longest(_rowSymbols.SHORTWEEKDAYS);
    final ofMonth = _rowDayOfMonth.format(DateTime.utc(2026, 1, 28));
    final lastSeen = [
      l10n.reportTagLastSeen('today', ''),
      l10n.reportTagLastSeen('yesterday', ''),
      l10n.reportTagLastSeen(
        'other',
        spansMonths
            ? l10n.reportRowDayMonth(
                weekday,
                ofMonth,
                _longest(_rowSymbols.SHORTMONTHS),
              )
            : l10n.reportRowDay(weekday, ofMonth),
      ),
    ];
    final moneyTemplate = _eights('${(net.abs() / 100).round()}'.length) * 100;
    return (
      caption: [counted, ?drawn].map(_bindNumbers).join(separator),
      templates: trip
          ? [template(l10n.reportTagDays(_eights(3)))]
          : [
              if (money)
                template(_netMoney(net < 0 ? -moneyTemplate : moneyTemplate)),
              for (final fact in lastSeen) template(fact),
              template(null),
            ],
      spoken: l10n.reportTagSpoken(
        tag.label,
        [counted, ?heard].join(spokenSeparator),
      ),
    );
  }

  /// [hour] (0–24) on the phone's clock, the hour alone where it reads with
  /// a day period ("6 PM"), else as the rows write it ("18:00").
  String _hourOf(int hour, {required bool use24Hour}) =>
      !use24Hour && _clockHasDayPeriod
      ? _hourOnly.format(DateTime(2000, 1, 1, hour % Duration.hoursPerDay))
      : EventTimeFormatter.formatMinuteFor(
          hour * Duration.minutesPerHour,
          localeName: l10n.localeName,
          use24Hour: use24Hour,
        );

  /// The When card's words (S5 §2.3): "Busiest: Tuesday · 18:00–19:00" and
  /// the spoken summary with the timed days it was drawn from; null while
  /// the fold names no busiest day. The fold's row counts from
  /// [weekStart], so the weekday is resolved through it.
  ({String caption, String spoken})? whenWords(
    ReportWhen when, {
    required CalendarWeekStart weekStart,
    required bool use24Hour,
  }) {
    final row = when.busiestWeekday;
    final hour = when.busiestHour;
    if (row == null || hour == null) return null;
    final weekday = (weekStart.weekday - 1 + row) % DateTime.daysPerWeek + 1;
    // January 2024 opens on a Monday, so its day N is weekday N.
    final name = _weekday.format(DateTime.utc(2024, 1, weekday));
    final from = _hourOf(hour, use24Hour: use24Hour);
    final to = _hourOf(hour + 1, use24Hour: use24Hour);
    return (
      caption: l10n.reportWhenBusiest(name, _bindNumbers('$from–$to')),
      spoken: l10n.reportWhenSpoken(name, from, to, when.timedDays),
    );
  }

  /// [area]'s name, S3's words.
  String areaName(LifeArea area) => lifeAreaName(l10n, area);

  /// A Balance row's words (S5 §2.4): "38 h · 67 %" — the share of
  /// [totalMinutes], the hours the card shows, 0 % with none, written as
  /// the Attended tile writes its share — and "Work, 38 hours, 67 percent
  /// of the hours". [areaName] defaults to [ReportLabels.areaName] of
  /// [area].
  ({String caption, String spoken}) balanceWords(
    LifeArea area,
    int minutes, {
    required int totalMinutes,
    String? areaName,
  }) {
    final percent = totalMinutes > 0
        ? (minutes * 100 / totalMinutes).round()
        : 0;
    return (
      caption: _bindNumbers(
        [hours(minutes), l10n.reportPercent('$percent')].join(separator),
      ),
      spoken: l10n.reportBalanceSpoken(
        areaName ?? this.areaName(area),
        hoursSpoken(minutes),
        l10n.reportPercentSpoken('$percent'),
      ),
    );
  }

  /// What the footer's Compare with row names: the choice, or for a view
  /// its [viewName] — "No saved views" when the view is gone.
  String compareName(ReportCompare compare, {String? viewName}) =>
      switch (compare) {
        ReportCompare.previous => l10n.reportComparePrevious,
        ReportCompare.lastYear => l10n.reportCompareLastYear,
        ReportCompare.view => viewName ?? l10n.reportCompareNoViews,
      };
}
