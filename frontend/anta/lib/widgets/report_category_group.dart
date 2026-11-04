import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_presence.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../services/day_summary_resolver.dart';
import '../utils/report_labels.dart';
import 'agenda_day_list_rows.dart';
import 'event_avatar.dart';
import 'form_rows.dart';

/// One category group of the report's Categories, Missed or Ahead card (W,
/// X): a [FormMeterRow] header with a fold glyph and, while [open], the
/// group's rows inset to the header's text — the first
/// [ReportMetrics.groupPreviewRows], then "n more" to show the rest in place
/// and "Show less" to fold back.
///
/// A row builder, not a widget, in [AgendaDayListRowBuilder]'s shape:
/// `ReportGroupStack` lays each group into the group's own `SliverList`
/// through [rowCount] and [build], so the surface keeps one `Scrollable`
/// and builds only the rows on screen. A group never scrolls inside itself
/// — a fixed slot scrolling in the page is the nested-scroll trap
/// `GuideStageSlot` had to work around (2026-10-30), and it hides how many
/// rows there are. Each row comes
/// in its `FormRowShell`, so a run of them reads as one card.
///
/// Nothing animates but the header's glyph: opening or closing inserts or
/// removes the rows at once, so nothing slides under the finger.
class ReportGroupRows {
  /// The card the group stands in: it decides the header's facts, the meter
  /// and whether a Missed row carries the presence button, and it is part
  /// of every id and key, since one category heads a group in each card.
  final ReportCard card;

  /// The group drawn: its header's figures and its rows in the report's
  /// order.
  final ReportCategoryGroup group;

  /// The report's events by id ([CalendarReport.events]); a row's words are
  /// read from its event at render time.
  final Map<String, CalendarEvent> events;

  /// The page's one [ReportLabels], so the rows word their numbers as the
  /// cards above them do and share its formatters.
  final ReportLabels labels;

  /// The header meter's share — the group's count over the card's largest —
  /// on the Categories and By tag cards only; ignored on the others.
  final double fraction;

  /// Whether the group's rows are shown under its header.
  final bool open;

  /// Whether the group shows every row (up to [ReportMetrics.maxListRows])
  /// rather than its preview.
  final bool expanded;

  /// Toggles [open]: the header's tap. The state is the page's, per visit.
  final VoidCallback onToggle;

  /// Toggles [expanded]: the "n more" and "Show less" rows' tap.
  final VoidCallback onMore;

  /// A dated row's tap: the page opens the detail sheet on the row's day.
  /// Null leaves the row inert, as the guide's stage draws it.
  final void Function(ReportDatedRow row)? onDatedTap;

  /// A routine aggregate's tap: the page opens the detail sheet on
  /// [ReportRoutineRow.latestDay], the one day the aggregate stands for.
  /// Null leaves the row inert.
  final void Function(ReportRoutineRow row)? onRoutineTap;

  /// The presence button's press on a Missed row, handed the status to
  /// write; read on the Missed card only — nothing in Categories or Ahead
  /// is there to mark.
  final void Function(ReportDatedRow row, bool missed)? onPresence;

  /// The "Show as list" row's tap, under a group longer than
  /// [ReportMetrics.maxListRows] (V); null draws it disabled.
  final VoidCallback? onShowAsList;

  /// Date-only UTC today, which the [AgendaDayListRowBuilder] a dated row
  /// is drawn by requires; the row's own day label does not read it.
  final DateTime today;

  /// Whether the period crosses a calendar month: a row's day then names
  /// its month (U).
  final bool spansMonths;

  /// Whether the phone is on the 24-hour clock
  /// (`MediaQuery.alwaysUse24HourFormatOf`): a dated row's start time reads
  /// as every other calendar time does.
  final bool use24Hour;

  /// The air below the group's last row, as `FormRowGroup` carries it.
  final bool trailingGap;

  /// The category's measures, which a profiled Categories header leads
  /// with (N); null — every other card, an unprofiled report — keeps the
  /// header's count facts.
  final ReportMeasures? measures;

  /// The tag a By tag group stands for (`ReportGroupStack.tagGroups`): the
  /// header names it and wears the avatar and colour of the category its
  /// noun is read from ([ReportTag.kindCategoryId], P), and every id is the
  /// tag's, since a tag's row can also be a Categories row. Null on every
  /// other card.
  final ReportTag? tag;

  /// The stack's measured tag captions, which outlive this builder so a
  /// fold's rebuild lays no unchanged header out again; null measures in a
  /// memo of this builder's own, one build long.
  final ReportTagCaptions? tagCaptions;

  ReportGroupRows({
    required this.card,
    required this.group,
    required this.events,
    required this.labels,
    this.fraction = 0,
    required this.open,
    required this.expanded,
    required this.onToggle,
    required this.onMore,
    this.onDatedTap,
    this.onRoutineTap,
    this.onPresence,
    this.onShowAsList,
    required this.today,
    required this.spansMonths,
    required this.use24Hour,
    this.trailingGap = true,
    this.measures,
    this.tag,
    this.tagCaptions,
  });

  /// Read for a dated row's icon, colour and title only: the row's subtitle
  /// is the report's own ([ReportLabels.rowSubtitle]).
  late final EventSummaryProvider _summaries = EventSummaryProvider(
    labels.l10n,
  );

  late final CalendarCategory _category = CalendarCategories.resolve(
    tag?.kindCategoryId ?? group.categoryId,
  );

  /// What the header and the disclosure rows name: the category, or the
  /// tag as typed.
  late final String _groupName = switch (tag) {
    final tag? => '#${tag.label}',
    null => CalendarCategories.labelOf(_category, labels.l10n),
  };

  /// [_groupName] as the disclosure rows speak it: "tag ana", since a '#'
  /// would be read as a number sign.
  late final String _spokenName = switch (tag) {
    final tag? => labels.l10n.reportTagName(tag.label),
    null => _groupName,
  };

  /// The group's rows shown under the open header.
  late final int _shown = math.min(
    group.rows.length,
    expanded ? ReportMetrics.maxListRows : ReportMetrics.groupPreviewRows,
  );

  bool get _discloses => group.rows.length > ReportMetrics.groupPreviewRows;

  bool get _capped => expanded && group.rows.length > ReportMetrics.maxListRows;

  /// The header, then while [open] the shown rows, "Show as list" when the
  /// expansion is capped, and the disclosure row.
  late final int rowCount = open
      ? 1 + _shown + (_capped ? 1 : 0) + (_discloses ? 1 : 0)
      : 1;

  /// The key of the row at [index], unique across every card's groups: the
  /// group's own `SliverList` maps rows across an open or a fold through
  /// `findChildIndexCallback`, so a header that moves keeps its own glyph's
  /// state rather than taking over the one drawn at its new index.
  Key keyOf(int index) =>
      ValueKey<String>('${card.name}/${group.categoryId}/${_slotOf(index)}');

  String _slotOf(int index) {
    if (index == 0) return 'h';
    final at = index - 1;
    if (at < _shown) {
      return switch (group.rows[at]) {
        final ReportRoutineRow row => row.eventId,
        final ReportDatedRow row =>
          '${row.eventId}/${row.day.toIso8601String().substring(0, 10)}',
      };
    }
    if (_capped && at == _shown) return 'list';
    return 'more';
  }

  /// The row at [index] in its shell, under [keyOf].
  ///
  /// The air below the group is a padding every row carries, not the
  /// shell's `trailingGap`: the shell adds its padding only to a last row,
  /// so a header turning from last (closed) to first (open) would change
  /// shape and lose its glyph's state mid-turn.
  Widget build(BuildContext context, int index) {
    final last = index == rowCount - 1;
    Widget shell(Widget row) => FormRowShell(
      first: index == 0,
      last: last,
      trailingGap: false,
      child: row,
    );
    final tag = this.tag;
    return Padding(
      key: keyOf(index),
      padding: EdgeInsets.only(
        bottom: last && trailingGap ? RowMetrics.groupGap : 0,
      ),
      // A tag header reserves its caption lines at the row's width; the
      // builder sits outside the shell, which reads the row's divider
      // indent from the row itself.
      child: index == 0 && tag != null
          ? LayoutBuilder(
              builder: (context, constraints) =>
                  shell(_tagHeader(context, tag, constraints.maxWidth)),
            )
          : shell(_row(context, index)),
    );
  }

  /// A row whose event is not in [events] asserts: the builder reads every
  /// row's event from the same map (`events[id]!`), so it would mean the
  /// group and the map came from different reports. A release build draws
  /// nothing in its place rather than a row with no words.
  Widget _row(BuildContext context, int index) {
    if (index == 0) return _header(context);
    final at = index - 1;
    if (at < _shown) {
      final row = group.rows[at];
      final event = events[row.eventId];
      assert(event != null, 'no event ${row.eventId} for a report row');
      if (event == null) return const SizedBox.shrink();
      return switch (row) {
        final ReportRoutineRow routine => _routineRow(routine, event),
        final ReportDatedRow dated => _datedRow(context, dated, event),
      };
    }
    if (_capped && at == _shown) {
      return FormActionRow.disclosure(
        glyph: Icons.chevron_right_rounded,
        label: labels.l10n.reportShowAsList,
        onTap: onShowAsList,
        semanticsLabel: labels.l10n.reportGroupListSpoken(_spokenName),
        identifier: switch (tag) {
          final tag? => SemanticsIds.reportTagList(tag.key),
          null => SemanticsIds.reportGroupList(card.name, group.categoryId),
        },
      );
    }
    return _disclosure();
  }

  Widget get _avatar => EventAvatar(
    icon: CalendarIcons.forKey(_category.iconKey) ?? Icons.event_rounded,
    color: _category.color,
  );

  /// The fold glyph, half a turn while [open].
  Widget _chevron(BuildContext context) => AnimatedRotation(
    turns: open ? 0.5 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Durations.short4,
    curve: Easing.standard,
    child: const FormTrailingGlyph(icon: Icons.expand_more_rounded),
  );

  Widget _header(BuildContext context) {
    return FormMeterRow(
      leading: _avatar,
      label: _groupName,
      caption: labels.groupFacts(
        card,
        group,
        measures: measures,
        use24Hour: use24Hour,
      ),
      fraction: card == ReportCard.categories ? fraction : null,
      meterColor: _category.color,
      trailing: _chevron(context),
      onTap: onToggle,
      expanded: open,
      semanticsLabel: labels.groupSpoken(
        card,
        group,
        category: _groupName,
        measures: measures,
        use24Hour: use24Hour,
      ),
      identifier: SemanticsIds.reportGroup(card.name, group.categoryId),
    );
  }

  /// A By tag header (§2.2): "#ana" over its two facts, on as many caption
  /// lines as the widest of the tag's templates takes in a row [width]
  /// wide (S4 D) — never the value's, so a refold keeps the row's height.
  /// Spoken "tag ana, …": a '#' would be read as a number sign.
  Widget _tagHeader(BuildContext context, ReportTag tag, double width) {
    final words = labels.tagWords(tag, spansMonths: spansMonths, today: today);
    return FormMeterRow(
      leading: _avatar,
      label: _groupName,
      caption: words.caption,
      captionLines: (tagCaptions ?? ReportTagCaptions()).linesOf(
        tag,
        labels: labels,
        spansMonths: spansMonths,
        style: reportCaptionStyleOf(context),
        scaler: MediaQuery.textScalerOf(context),
        direction: Directionality.of(context),
        // The caption runs from the text column's start to the fold glyph.
        width:
            width -
            RowMetrics.groupInset -
            FormMetrics.rowLeadingSize -
            FormMetrics.gap -
            FormMetrics.gap -
            FormMetrics.trailingIconSize -
            FormMetrics.rowEndPadding,
      ),
      fraction: fraction,
      meterColor: _category.color,
      trailing: _chevron(context),
      onTap: onToggle,
      expanded: open,
      semanticsLabel: words.spoken,
      identifier: SemanticsIds.reportTag(tag.key),
    );
  }

  /// §4.8's aggregate row: the dated rows' shape, the attended count as the
  /// value so the column sums to the header (K, D26).
  Widget _routineRow(ReportRoutineRow row, CalendarEvent event) {
    final onTap = onRoutineTap;
    return FormPickerRow(
      leading: const SizedBox.shrink(),
      label: event.title,
      value: '${row.attended}',
      caption: labels.routineCaption(row),
      captionMaxLines: 1,
      singleLine: true,
      showChevron: false,
      onTap: onTap == null ? null : () => onTap(row),
      identifier: SemanticsIds.reportRoutine(row.eventId),
    );
  }

  /// The day list's entry row, the avatar left to the header and every row
  /// drawn whole, its subtitle the report's ("Thu 8 · 17:00 · 1 h · 5 of 8
  /// tasks").
  Widget _datedRow(
    BuildContext context,
    ReportDatedRow row,
    CalendarEvent event,
  ) {
    final summary = _summaries.entryFor(event, row.day);
    final entry = AgendaDayListEntry(
      day: row.day,
      icon: summary.icon,
      color: summary.color,
      title: summary.title,
      subtitle: labels.rowSubtitle(
        row,
        event: event,
        use24Hour: use24Hour,
        spansMonths: spansMonths,
      ),
      missed: row.missed,
      eventId: event.id,
      presenceTracked: EventPresence.appliesTo(event),
      categoryId: event.categoryId,
    );
    final mark = card == ReportCard.missed ? onPresence : null;
    final onTap = onDatedTap;
    return AgendaDayListRowBuilder(
      rows: const [],
      today: today,
      captionMaxLines: 1,
      singleLineTitles: true,
      avatars: false,
      fadeMissed: false,
      onEntryTap: onTap == null ? null : (_) => onTap(row),
      onEntryPresence: mark == null ? null : (_, missed) => mark(row, missed),
      presenceIdentifier: mark == null
          ? null
          : (_) => SemanticsIds.reportRowPresence(row.eventId, row.day),
      rowIdentifier: (_) => switch (tag) {
        final tag? => SemanticsIds.reportTagRow(tag.key, row.eventId, row.day),
        null => SemanticsIds.reportRow(row.eventId, row.day),
      },
    ).entryRow(context, entry);
  }

  /// "n more ▾" under the preview, "Show less ▴" under the expansion — one
  /// id both ways.
  Widget _disclosure() {
    final l10n = labels.l10n;
    final name = _spokenName;
    final id = switch (tag) {
      final tag? => SemanticsIds.reportTagMore(tag.key),
      null => SemanticsIds.reportGroupMore(card.name, group.categoryId),
    };
    if (expanded) {
      return FormActionRow.disclosure(
        glyph: Icons.expand_less_rounded,
        label: l10n.reportGroupLess,
        onTap: onMore,
        expanded: true,
        semanticsLabel: l10n.reportGroupLessSpoken(name),
        identifier: id,
      );
    }
    final more = group.rows.length - _shown;
    return FormActionRow.disclosure(
      glyph: Icons.expand_more_rounded,
      label: l10n.reportGroupMore(more),
      onTap: onMore,
      expanded: false,
      semanticsLabel: l10n.reportGroupMoreSpoken(more, name),
      identifier: id,
    );
  }
}

/// [FormMeterRow]'s caption role, to measure a caption ahead of the row;
/// merged over the ambient style, which a bare style would measure in the
/// box font.
const TextStyle reportCaptionStyle = TextStyle(
  fontSize: FormMetrics.captionSize,
  height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
);

/// [reportCaptionStyle] over [context]'s ambient style as the row's caption
/// `Text` will draw it: bold under the bold-text setting, whose wider
/// glyphs would wrap a caption measured without it past its reserved lines.
TextStyle reportCaptionStyleOf(BuildContext context) {
  final style = DefaultTextStyle.of(context).style.merge(reportCaptionStyle);
  return MediaQuery.boldTextOf(context)
      ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
      : style;
}

/// The By tag headers' caption lines (S5 §2.2), measured once and kept by
/// the stack that draws the headers: a fold's `setState` rebuilds every
/// header, and one whose tag, width and spans are unchanged lays nothing
/// out. The widest short weekday and month names the templates are built
/// with are laid out once per locale, scale and style rather than per
/// header. A change of locale, currency, scale, style or direction measures
/// everything again; entries are per tag key, so the memo never outgrows
/// the card's tags ([retain]).
class ReportTagCaptions {
  /// What [_widest] and [_lines] were measured in.
  ({
    String locale,
    String currencySymbol,
    bool currencySuffix,
    TextScaler scaler,
    TextStyle style,
    TextDirection direction,
  })?
  _measuredIn;

  /// The widest of a list of names, by the names joined.
  final Map<String, String> _widest = {};

  final Map<
    String,
    ({ReportTag tag, bool spansMonths, double width, int lines})
  >
  _lines = {};

  /// The lines [tag]'s header reserves at a caption [width] wide: the most
  /// its `ReportLabels.tagTemplates` wraps to, the names in them measured
  /// in [style] — the bold-aware [reportCaptionStyleOf].
  int linesOf(
    ReportTag tag, {
    required ReportLabels labels,
    required bool spansMonths,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
    required double width,
  }) {
    final measuredIn = (
      locale: labels.l10n.localeName,
      currencySymbol: labels.currencySymbol,
      currencySuffix: labels.currencySuffix,
      scaler: scaler,
      style: style,
      direction: direction,
    );
    if (measuredIn != _measuredIn) {
      _measuredIn = measuredIn;
      _widest.clear();
      _lines.clear();
    }
    final kept = _lines[tag.key];
    if (kept != null &&
        kept.width == width &&
        kept.spansMonths == spansMonths &&
        kept.tag == tag) {
      return kept.lines;
    }
    final lines = reportCaptionLines(
      labels.tagTemplates(
        tag,
        spansMonths: spansMonths,
        widest: (names) => _widest.putIfAbsent(
          names.join('\n'),
          () => widestOf(names, style, scaler, direction),
        ),
      ),
      style: style,
      scaler: scaler,
      direction: direction,
      width: width,
    );
    _lines[tag.key] = (
      tag: tag,
      spansMonths: spansMonths,
      width: width,
      lines: lines,
    );
    return lines;
  }

  /// Drops the lines of every tag [tags] no longer holds.
  void retain(Map<String, ReportTag> tags) =>
      _lines.removeWhere((key, _) => !tags.containsKey(key));

  /// The name of [names] that draws widest — not the longest: German
  /// "Mo." is wider than "So.", English "Wed" than "Sun". A tie keeps the
  /// first. Public for the year's Months rows, whose span template names
  /// the widest month the same way.
  static String widestOf(
    Iterable<String> names,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    var widest = '';
    var most = -1.0;
    for (final name in names) {
      final painter = TextPainter(
        text: TextSpan(text: name, style: style),
        textScaler: scaler,
        textDirection: direction,
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width > most) {
        most = width;
        widest = name;
      }
    }
    return widest;
  }
}

/// The lines a [FormMeterRow]'s `captionLines` reserves (S4 D): the most
/// any of [templates] wraps to at the caption's [width] — at least one. The
/// report's goal rows and tag headers decide their height through it, from
/// the shapes their caption can take and never from its value.
int reportCaptionLines(
  Iterable<String> templates, {
  required TextStyle style,
  required TextScaler scaler,
  required TextDirection direction,
  required double width,
}) {
  var most = 1;
  for (final template in templates) {
    final painter = TextPainter(
      text: TextSpan(text: template, style: style),
      textScaler: scaler,
      textDirection: direction,
    )..layout(maxWidth: width);
    final count = painter.computeLineMetrics().length;
    painter.dispose();
    if (count > most) most = count;
  }
  return most;
}
