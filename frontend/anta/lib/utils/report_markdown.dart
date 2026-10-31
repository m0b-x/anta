import '../constants/calendar_categories.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../models/date_range.dart';
import '../models/export_format.dart';
import 'report_labels.dart';

/// The report as Markdown, for Share report (K): the page's cards in the
/// page's order, every word and number through [ReportLabels], so the
/// shared text can never disagree with the screen. Unlike the page it is
/// unbounded — every category group and every row, past the card's seven
/// groups and a group's row cap — because a shared text has no fold to
/// open. Pure: the caller hands it the labels and the clock style.
abstract final class ReportMarkdown {
  /// [report] in Markdown, lines ended by `\n`: the title, the band's
  /// subtitle, the Totals caption in italics, then Totals, Categories, Over
  /// time, Missed and Ahead as level-2 sections, each drawn only with
  /// content, as the page draws its cards; a plan has Totals and Categories
  /// only (T). [periodName] and [against] are the values the page's caption
  /// reads.
  static String render(
    CalendarReport report,
    ReportLabels labels, {
    required bool use24Hour,
    required String periodName,
    String? against,
  }) {
    final l10n = labels.l10n;
    const dot = ReportLabels.separator;
    final out = StringBuffer();
    void block(String text) {
      if (out.isNotEmpty) out.write('\n');
      out.write('$text\n');
    }

    block('# ${l10n.reportTitle}$dot$periodName');
    block(labels.subtitle(report));
    final caption = labels.caption(
      report,
      periodName: periodName,
      against: against,
    );
    if (caption != null) block('*$caption*');

    if (report.tiles.isNotEmpty) {
      block('## ${l10n.reportSectionTotals}');
      block(
        [for (final tile in report.tiles) _tileLine(tile, labels)].join('\n'),
      );
    }

    final span = report.span;
    final spansMonths =
        span.start.year != span.end.year || span.start.month != span.end.month;
    void card(ReportCard card, String label, List<ReportCategoryGroup> all) {
      if (all.isEmpty) return;
      block('## $label');
      for (final group in all) {
        final name = escapeMarkdown(
          CalendarCategories.labelOf(
            CalendarCategories.resolve(group.categoryId),
            l10n,
          ),
        );
        block('### $name$dot${labels.groupFacts(card, group)}');
        final rows = <String>[];
        for (final row in group.rows) {
          final event = report.events[row.eventId];
          // Every row's event is in the report's map (D38): a missing one
          // means the group and the map came from different reports, and a
          // release build leaves the row out as the page does.
          assert(event != null, 'no event ${row.eventId} for a report row');
          if (event == null) continue;
          rows.add(
            _rowLine(
              row,
              event,
              labels,
              use24Hour: use24Hour,
              spansMonths: spansMonths,
            ),
          );
        }
        if (rows.isNotEmpty) block(rows.join('\n'));
      }
    }

    card(
      ReportCard.categories,
      l10n.reportSectionCategories,
      report.categories,
    );
    if (report.tense == ReportTense.future) return out.toString();

    final trend = report.trend;
    if (trend != null) {
      final words = labels.trendWords(trend, use24Hour: use24Hour).caption;
      if (words != null) {
        block('## ${l10n.reportSectionOverTime}');
        block(words);
      }
    }
    card(ReportCard.missed, l10n.reportSectionMissed, report.missed);
    card(ReportCard.ahead, l10n.reportSectionAhead, report.ahead);
    return out.toString();
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
