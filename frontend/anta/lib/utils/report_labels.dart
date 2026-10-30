import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_report.dart';
import '../models/overview_period.dart';
import '../services/event_time_formatter.dart';
import 'date_span_label.dart';

/// One run of a tile's value line: a figure ("21", "18.5", "—"), drawn large,
/// or the words around it ("of", " h"), drawn at the label's size (§4.8, D).
typedef ReportValueRun = ({String text, bool figure});

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
  ReportLabels(this.l10n)
    : _hours = NumberFormat('0.#', l10n.localeName),
      _countedTo = DateFormat.MMMMd(l10n.localeName);

  final AppLocalizations l10n;
  final NumberFormat _hours;
  final DateFormat _countedTo;

  // The Over time card's formatters, built on first use: most labels a page
  // builds never word a trend.
  late final DateFormat _weekday = DateFormat.EEEE(l10n.localeName);
  late final DateFormat _peakDay = DateFormat.MMMMEEEEd(l10n.localeName);
  late final DateFormat _peakWeek = DateFormat.MMMMd(l10n.localeName);
  late final DateFormat _peakMonth = DateFormat.yMMMM(l10n.localeName);

  /// The names already worded by this instance: a build names the shown
  /// period three times and each `menuValue` builds a `DateFormat`.
  final Map<OverviewPeriod, String> _periodNames = {};
  CalendarReport? _comparedReport;
  String? _comparedName;

  /// A tile with nothing in the period.
  static const String nothing = '—';

  /// Joins a caption's or a detail's facts: the no-break space keeps the dot
  /// off the start of a wrapped line.
  static const String separator = ' · ';

  /// A figure, signed or not, with the locale's decimal mark, or the dash —
  /// what the value line draws large; everything else is a unit.
  static final RegExp _figure = RegExp(r'[+−\-±]?\d+(?:[.,]\d+)?|—');

  /// [hours] with the locale's decimal mark, a trailing ".0" dropped.
  String hoursFigure(num hours) => _hours.format(hours);

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
      return l10n.reportOfTotal('${value.value}', '$of');
    }
    return '${value.value}';
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
        l10n.reportOfTotalOnly('$of'),
      if (percent != null) l10n.reportPercent('$percent'),
      if (open != null && open > 0) l10n.reportTasksOpen(open),
      ?delta(value),
    ].join(separator);
  }

  /// What a screen reader hears for a tile ("Attended, 21 of 24, 88
  /// percent, 2 more than September 2026"); [against] names the period the
  /// delta compares with.
  String tileSemantics(ReportTileValue value, {String? against}) {
    final label = tileLabel(value.tile);
    if (isNothing(value)) return '$label, ${l10n.reportTileNone}';
    final percent = _percent(value);
    final open = _open(value);
    final previous = value.previous;
    String? change;
    if (previous != null && against != null) {
      final size = (value.value - previous).abs();
      final amount = value.tile == ReportTile.hours ? hours(size) : '$size';
      change = value.value > previous
          ? l10n.reportDeltaMore(amount, against)
          : value.value < previous
          ? l10n.reportDeltaLess(amount, against)
          : l10n.reportDeltaSame(against);
    }
    return [
      label,
      tileValue(value),
      if (percent != null) l10n.reportPercentSpoken('$percent'),
      if (open != null && open > 0) l10n.reportTasksOpen(open),
      ?change,
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
  static String _bound(String count) => count.replaceAll(' ', ' ');

  /// The caption under the Totals card: "To 30 October · against September
  /// 2026 · 2 skipped · 2 ahead", or "[periodName] · Nothing happened" for
  /// an empty span — composed, because a period's name is a noun phrase no
  /// one preposition fits in three languages (D36.4); null in the future
  /// tense, where nothing is counted yet.
  String? caption(
    CalendarReport report, {
    required String periodName,
    String? against,
  }) {
    if (report.tense == ReportTense.future) return null;
    if (report.isEmpty) {
      return '$periodName$separator${l10n.reportCaptionNothing}';
    }
    return [
      l10n.reportCaptionTo(_countedTo.format(report.countedTo)),
      if (against != null && report.previousSpan != null)
        l10n.reportCaptionAgainst(against),
      if (report.skippedDays > 0)
        _bound(l10n.reportSkippedCount(report.skippedDays)),
      if (report.aheadCount > 0)
        _bound(l10n.reportAheadCount(report.aheadCount)),
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
  ({String? caption, String spoken}) trendWords(
    ReportTrend trend, {
    required bool use24Hour,
  }) {
    final facts = _trendFacts(trend, use24Hour: use24Hour);
    if (facts.isNotEmpty) {
      return (
        caption: _sentence(facts.join(separator)),
        spoken: l10n.reportTrendSpoken(_sentence(facts.join(', '))),
      );
    }
    final peak = peakOf(trend);
    if (peak <= 0) return (caption: null, spoken: l10n.reportSectionOverTime);
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
    return (caption: null, spoken: l10n.reportTrendSpoken(phrase));
  }

  /// The band's subtitle: "31 events · 3 missed", or for a plan "10 planned
  /// · 9.5 h".
  String subtitle(CalendarReport report) {
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
    final missed = valueOf(ReportTile.missed) ?? 0;
    return [
      l10n.reportEventCount(valueOf(ReportTile.events) ?? 0),
      if (missed > 0) l10n.dayListMissedCount(missed),
    ].join(separator);
  }
}
