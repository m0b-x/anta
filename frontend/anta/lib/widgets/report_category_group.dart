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
  /// on the Categories card only; ignored on the others.
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
  final void Function(ReportDatedRow row) onDatedTap;

  /// A routine aggregate's tap: the page opens the detail sheet on
  /// [ReportRoutineRow.latestDay], the one day the aggregate stands for.
  final void Function(ReportRoutineRow row) onRoutineTap;

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
    required this.onDatedTap,
    required this.onRoutineTap,
    this.onPresence,
    this.onShowAsList,
    required this.today,
    required this.spansMonths,
    required this.use24Hour,
    this.trailingGap = true,
  });

  /// Read for a dated row's icon, colour and title only: the row's subtitle
  /// is the report's own ([ReportLabels.rowSubtitle]).
  late final EventSummaryProvider _summaries = EventSummaryProvider(
    labels.l10n,
  );

  late final CalendarCategory _category = CalendarCategories.resolve(
    group.categoryId,
  );

  late final String _categoryName = CalendarCategories.labelOf(
    _category,
    labels.l10n,
  );

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
    return Padding(
      key: keyOf(index),
      padding: EdgeInsets.only(
        bottom: last && trailingGap ? RowMetrics.groupGap : 0,
      ),
      child: FormRowShell(
        first: index == 0,
        last: last,
        trailingGap: false,
        child: _row(context, index),
      ),
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
        semanticsLabel: labels.l10n.reportGroupListSpoken(_categoryName),
        identifier: SemanticsIds.reportGroupList(card.name, group.categoryId),
      );
    }
    return _disclosure();
  }

  Widget _header(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    return FormMeterRow(
      leading: EventAvatar(
        icon: CalendarIcons.forKey(_category.iconKey) ?? Icons.event_rounded,
        color: _category.color,
      ),
      label: _categoryName,
      caption: labels.groupFacts(card, group),
      fraction: card == ReportCard.categories ? fraction : null,
      meterColor: _category.color,
      trailing: AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: animate ? Durations.short4 : Duration.zero,
        curve: Easing.standard,
        child: const FormTrailingGlyph(icon: Icons.expand_more_rounded),
      ),
      onTap: onToggle,
      expanded: open,
      semanticsLabel: labels.groupSpoken(card, group, category: _categoryName),
      identifier: SemanticsIds.reportGroup(card.name, group.categoryId),
    );
  }

  /// §4.8's aggregate row: the dated rows' shape, the attended count as the
  /// value so the column sums to the header (K, D26).
  Widget _routineRow(ReportRoutineRow row, CalendarEvent event) {
    return FormPickerRow(
      leading: const SizedBox.shrink(),
      label: event.title,
      value: '${row.attended}',
      caption: labels.routineCaption(row),
      captionMaxLines: 1,
      singleLine: true,
      showChevron: false,
      onTap: () => onRoutineTap(row),
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
    );
    final mark = card == ReportCard.missed ? onPresence : null;
    return AgendaDayListRowBuilder(
      rows: const [],
      today: today,
      captionMaxLines: 1,
      singleLineTitles: true,
      avatars: false,
      fadeMissed: false,
      onEntryTap: (_) => onDatedTap(row),
      onEntryPresence: mark == null ? null : (_, missed) => mark(row, missed),
      presenceIdentifier: mark == null
          ? null
          : (_) => SemanticsIds.reportRowPresence(row.eventId, row.day),
      rowIdentifier: (_) => SemanticsIds.reportRow(row.eventId, row.day),
    ).entryRow(context, entry);
  }

  /// "n more ▾" under the preview, "Show less ▴" under the expansion — one
  /// id both ways.
  Widget _disclosure() {
    final l10n = labels.l10n;
    final name = _categoryName;
    final id = SemanticsIds.reportGroupMore(card.name, group.categoryId);
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
