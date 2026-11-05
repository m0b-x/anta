import '../constants/analytics_metrics.dart';
import '../constants/calendar_categories.dart';
import '../constants/category_kinds.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/date_range.dart';
import '../models/export_format.dart';
import 'report_insight_filter.dart';
import 'report_labels.dart';

/// The report as Markdown, for Share report (K): the page's cards in the
/// page's order, every word and number through [ReportLabels], so the
/// shared text can never disagree with the screen. Unlike the page it is
/// unbounded — every category group, tag, due row, record and strip, and
/// every row, past the cards' caps — because a shared text has no fold to
/// open; only Insights keep the page's filter and cap, which no fold
/// opens either (S7). Pure: the caller hands it the labels and the clock
/// style.
abstract final class ReportMarkdown {
  /// [report] in Markdown, lines ended by `\n`: the title, the band's
  /// subtitle, the Totals caption in italics, then Goals, Insights, Due
  /// soon, Totals, on a whole year Records and Months, Categories, By tag,
  /// Over time, When, Balance, Missed and Ahead as level-2 sections, each
  /// drawn only with content, as the page draws its cards; a plan has no
  /// Insights, Over time, Missed or Ahead (T). [periodName], [against] and
  /// [beside] are the values the page's caption reads; [weekStart] places
  /// the weekdays Insights and When name, as the page's cards read it.
  ///
  /// Beside a saved view the caption names the view in place of the
  /// compared period, and neither Totals column carries a delta, as the
  /// page's two cards draw none (S5 I): the view's column follows the
  /// page's under the view's name.
  static String render(
    CalendarReport report,
    ReportLabels labels, {
    required bool use24Hour,
    required String periodName,
    String? against,
    String? beside,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
  }) {
    final l10n = labels.l10n;
    const dot = ReportLabels.separator;
    final plan = report.tense == ReportTense.future;
    final out = StringBuffer();
    void block(String text) {
      if (out.isNotEmpty) out.write('\n');
      out.write('$text\n');
    }

    void section(String label, Iterable<String> lines) {
      final list = lines.toList();
      if (list.isEmpty) return;
      block('## $label');
      block(list.join('\n'));
    }

    String categoryName(String categoryId) => escapeMarkdown(
      CalendarCategories.labelOf(CalendarCategories.resolve(categoryId), l10n),
    );

    block('# ${l10n.reportTitle}$dot$periodName');
    block(labels.subtitle(report));
    final caption = labels.caption(
      report,
      periodName: periodName,
      against: against,
      beside: beside,
    );
    if (caption != null) block('*$caption*');

    section(l10n.reportSectionGoals, [
      for (final goal in report.goals)
        '- ${categoryName(goal.categoryId)}: '
            '${labels.goalSharedCaption(goal, report)}',
    ]);
    if (!plan) {
      section(l10n.reportSectionInsights, [
        for (final insight in ReportInsightFilter.forPage(
          report,
        ).take(AnalyticsMetrics.insightsOnPage))
          _insightLine(insight, report, labels, weekStart: weekStart),
      ]);
    }
    section(l10n.reportSectionDueSoon, [
      for (final row in report.dueSoon)
        '- ${escapeMarkdown(report.events[row.eventId]?.title ?? row.eventId)}'
            ': ${labels.dueCaption(row, report)}',
    ]);

    if (report.tiles.isNotEmpty) {
      block('## ${l10n.reportSectionTotals}');
      block(
        [
          for (final tile in report.tiles)
            _tileLine(beside == null ? tile : _withoutDelta(tile), labels),
        ].join('\n'),
      );
      final view = report.compare == ReportCompare.view
          ? report.compared
          : null;
      if (beside != null && view != null && view.tiles.isNotEmpty) {
        block('### ${escapeMarkdown(beside)}');
        block(
          [
            for (final tile in view.tiles)
              _tileLine(_withoutDelta(tile), labels),
          ].join('\n'),
        );
      }
    }

    final year = report.year;
    if (year != null) {
      section(l10n.reportSectionRecords, [
        for (final record in year.records)
          '- ${labels.recordName(record.kind)}: '
              '${_escapeInline(labels.recordWords(record, report).caption)}',
      ]);
      // The months after today's in the current year have not happened.
      final aheadFrom = report.span.start.year == report.today.year
          ? report.today.month + 1
          : null;
      section(l10n.reportSectionMonths, [
        for (final group in report.categories)
          if ((year.months[group.categoryId], year.spans[group.categoryId])
              case (final months?, final span?))
            _monthsLine(
              categoryName(group.categoryId),
              labels.yearSpan(span.first, span.last),
              labels.yearMonthsLine(
                months: months,
                primary:
                    report.measures[group.categoryId]?.primary ??
                    ReportMeasure.count,
                aheadFrom: aheadFrom,
              ),
            ),
      ]);
    }

    final span = report.span;
    final spansMonths =
        span.start.year != span.end.year || span.start.month != span.end.month;
    void rows(List<ReportRow> all) {
      final lines = <String>[];
      for (final row in all) {
        final event = report.events[row.eventId];
        // Every row's event is in the report's map (D38): a missing one
        // means the group and the map came from different reports, and a
        // release build leaves the row out as the page does.
        assert(event != null, 'no event ${row.eventId} for a report row');
        if (event == null) continue;
        lines.add(
          _rowLine(
            row,
            event,
            labels,
            use24Hour: use24Hour,
            spansMonths: spansMonths,
          ),
        );
      }
      if (lines.isNotEmpty) block(lines.join('\n'));
    }

    void card(ReportCard card, String label, List<ReportCategoryGroup> all) {
      if (all.isEmpty) return;
      block('## $label');
      for (final group in all) {
        final name = categoryName(group.categoryId);
        block('### $name$dot${labels.groupFacts(card, group)}');
        rows(group.rows);
      }
    }

    card(
      ReportCard.categories,
      l10n.reportSectionCategories,
      report.categories,
    );
    if (report.tags.isNotEmpty) {
      block('## ${l10n.reportSectionTags}');
      for (final tag in report.tags) {
        final words = labels.tagWords(
          tag,
          spansMonths: spansMonths,
          today: report.today,
        );
        block('### #${escapeMarkdown(tag.label)}$dot${words.caption}');
        rows(tag.rows);
      }
    }

    final trend = report.trend;
    if (!plan && trend != null) {
      final words = labels.trendWords(trend, use24Hour: use24Hour).caption;
      if (words != null) {
        block('## ${l10n.reportSectionOverTime}');
        block(words);
      }
    }
    final when = report.when;
    final whenWords = when == null
        ? null
        : labels.whenWords(when, weekStart: weekStart, use24Hour: use24Hour);
    if (whenWords != null) {
      block('## ${l10n.reportSectionWhen}');
      block(whenWords.caption);
    }
    if (report.balance.length >= AnalyticsMetrics.balanceMinAreas) {
      section(l10n.reportSectionBalance, _balanceLines(report, labels));
    }
    if (!plan) {
      card(ReportCard.missed, l10n.reportSectionMissed, report.missed);
      card(ReportCard.ahead, l10n.reportSectionAhead, report.ahead);
    }
    return out.toString();
  }

  /// [tile] without its delta: beside a saved view the two columns are the
  /// comparison (S5 I).
  static ReportTileValue _withoutDelta(ReportTileValue tile) =>
      ReportTileValue(tile: tile.tile, value: tile.value, of: tile.of);

  /// One insight as a list item: "- Gym: 3 weeks without one", the subject
  /// and the detail the card draws. A tag rule's subject keeps its '#'
  /// bare — mid-line it is no heading — and escapes the tag the user typed.
  static String _insightLine(
    ReportInsight insight,
    CalendarReport report,
    ReportLabels labels, {
    required CalendarWeekStart weekStart,
  }) {
    final categoryId = insight.categoryId;
    // With no one category the labels' own nouns stand in, as on the card.
    final category = categoryId == null
        ? ''
        : CalendarCategories.labelOf(
            CalendarCategories.resolve(categoryId),
            labels.l10n,
          );
    final subject = labels.insightSubject(insight, report, category: category);
    final tagged =
        insight.rule == InsightRule.r1 || insight.rule == InsightRule.r2;
    final label = tagged
        ? '#${escapeMarkdown(subject.substring(1))}'
        : escapeMarkdown(subject);
    final detail = labels.insightDetail(
      insight,
      report,
      category: category,
      weekStart: weekStart,
    );
    return '- $label: ${_escapeInline(detail)}';
  }

  /// One Months row: "- Gym: Jan 2 – Dec 30 · Jan 9 · Feb 8 · …", the span
  /// alone while no month has happened.
  static String _monthsLine(String name, String span, String months) =>
      months.isEmpty
      ? '- $name: $span'
      : '- $name: $span${ReportLabels.separator}$months';

  /// The Balance rows, in the card's order and words: the most hours first,
  /// ties in [LifeArea]'s order, each "38 h · 67 %" of the hours shown; under
  /// Compare: last year the areas of both spans, by this span's hours, then
  /// last year's, each "1,720 h · last year 1,650 h".
  static List<String> _balanceLines(
    CalendarReport report,
    ReportLabels labels,
  ) {
    final balance = report.balance;
    String line(LifeArea area, String caption) =>
        '- ${labels.areaName(area)}: $caption';
    if (report.balanceLastYear case final lastYear?) {
      final areas = {...balance.keys, ...lastYear.keys}.toList()
        ..sort((a, b) {
          final byMinutes = (balance[b] ?? 0).compareTo(balance[a] ?? 0);
          if (byMinutes != 0) return byMinutes;
          final byLastYear = (lastYear[b] ?? 0).compareTo(lastYear[a] ?? 0);
          return byLastYear != 0 ? byLastYear : a.index - b.index;
        });
      return [
        for (final area in areas)
          line(
            area,
            labels
                .balanceLastYearWords(
                  area,
                  balance[area] ?? 0,
                  lastYear[area] ?? 0,
                )
                .caption,
          ),
      ];
    }
    final areas = balance.entries.toList()
      ..sort((a, b) {
        final byMinutes = b.value.compareTo(a.value);
        return byMinutes != 0 ? byMinutes : a.key.index - b.key.index;
      });
    final shares = ReportLabels.shares([for (final area in areas) area.value]);
    return [
      for (final (i, MapEntry(key: area, value: minutes)) in areas.indexed)
        line(
          area,
          labels.balanceWords(area, minutes, percent: shares[i]).caption,
        ),
    ];
  }

  /// One row as a list item: the title, then the caption the group draws
  /// under it — "- Gym · 8 of 10 attended · 8 h", "- PT session · Thu 8 ·
  /// 17:00 · 1 h".
  static String _rowLine(
    ReportRow row,
    CalendarEvent event,
    ReportLabels labels, {
    required bool use24Hour,
    required bool spansMonths,
  }) {
    final caption = switch (row) {
      ReportRoutineRow() => labels.routineCaption(row),
      ReportDatedRow() => labels.rowSubtitle(
        row,
        event: event,
        use24Hour: use24Hour,
        spansMonths: spansMonths,
      ),
    };
    return '- ${escapeMarkdown(event.title)}${ReportLabels.separator}$caption';
  }

  static final RegExp _markdownCharacter = RegExp(r'[\\`*_\[\]#<>]');
  static final RegExp _leadingListMarker = RegExp(r'^(\d+)([.)])|^([+\-])');

  /// [text] with every character Markdown would read as syntax
  /// backslash-escaped, and a leading list marker ("+ ", "- ", "1.") too —
  /// a title like "# Plan", "*Leg* day", "[ ] Call" or "1. Squats" is the
  /// user's words, never a heading, emphasis, a checkbox or a nested list.
  /// Only the user's text goes through it: the labels are ours.
  static String escapeMarkdown(String text) {
    final escaped = text.replaceAllMapped(
      _markdownCharacter,
      (match) => '\\${match[0]}',
    );
    return escaped.replaceFirstMapped(
      _leadingListMarker,
      (match) =>
          match[1] != null ? '${match[1]}\\${match[2]}' : '\\${match[3]}',
    );
  }

  /// [text] with only its syntax characters escaped, for words that carry
  /// the user's text mid-line — a record's trip title, an insight's
  /// category: after "- Name: " a leading "+" or "1." starts no list, and
  /// "\+2 h" would only show the backslash in a plain-text share.
  static String _escapeInline(String text) =>
      text.replaceAllMapped(_markdownCharacter, (match) => '\\${match[0]}');

  /// One tile as a list item: "- Attended: 21 of 24 · 88 % · +2" — the
  /// value line, then the detail line, whose last part is the bare delta.
  static String _tileLine(ReportTileValue tile, ReportLabels labels) {
    final detail = labels.detail(tile);
    final value = labels.tileValue(tile);
    final label = labels.tileLabel(tile.tile);
    return detail.isEmpty
        ? '- $label: $value'
        : '- $label: $value${ReportLabels.separator}$detail';
  }

  /// The shared file's name over [span]: `anta_report_20261001-20261031.md`.
  /// Digits by hand, so no locale's numerals reach a file name.
  static String fileName(DateRange span) {
    String stamp(DateTime day) =>
        '${day.year.toString().padLeft(4, '0')}'
        '${day.month.toString().padLeft(2, '0')}'
        '${day.day.toString().padLeft(2, '0')}';
    return 'anta_report_${stamp(span.start)}-${stamp(span.end)}'
        '.${ExportFormat.markdown.extension}';
  }
}
