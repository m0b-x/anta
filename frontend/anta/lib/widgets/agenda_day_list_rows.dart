import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import 'agenda_list_view.dart';
import 'event_avatar.dart';
import 'form_rows.dart';

/// A row of a dated entry list: a month separator, a day header, or an entry
/// — or, folded per event, a category's label and an event's row.
sealed class AgendaDayListRow {
  const AgendaDayListRow();
}

class AgendaDayListMonthRow extends AgendaDayListRow {
  final DateTime month;
  final bool showYear;

  /// The attended and the missed entries of the days the month row heads,
  /// for a list whose month labels carry their count.
  final int kept;
  final int missed;

  const AgendaDayListMonthRow({
    required this.month,
    required this.showYear,
    this.kept = 0,
    this.missed = 0,
  });
}

/// A category's group in a list folded per event: its label and how many
/// events the group holds.
class AgendaDayListCategoryRow extends AgendaDayListRow {
  final String categoryId;
  final String label;
  final int eventCount;

  const AgendaDayListCategoryRow({
    required this.categoryId,
    required this.label,
    required this.eventCount,
  });
}

/// One event folded over a list's entries: its first entry's look, how often
/// it occurred and was missed, and its first and last day.
class AgendaDayListEventRow extends AgendaDayListRow {
  final AgendaDayListEntry entry;
  final int count;
  final int missed;
  final DateTime first;
  final DateTime last;

  const AgendaDayListEventRow({
    required this.entry,
    required this.count,
    required this.missed,
    required this.first,
    required this.last,
  });
}

/// The height classes of [AgendaDayListRowBuilder]'s rows: a list whose rows
/// are all one line can give every row of a kind the same extent, measured
/// once per text scale and locale. A category label is a [month], an event
/// row an [entryCaption].
enum AgendaRowExtentKind { month, dayRead, entry, entryCaption }

/// How a list that gives every row of a kind one slot lays out its headers
/// at the text scale and locale in use — one decision per kind, read off the
/// widest header the kind can show: on one line while that one fits there,
/// the label ellipsizing beside its count; else wrapped, the count under the
/// label where it does not fit beside it, so no label is squeezed to an
/// ellipsis at a large text scale. With the heights, every header takes its
/// kind's slot whatever its own text needs: a section label sits on the
/// group below it, a read row centres its text.
@immutable
class AgendaHeaderSlots {
  final bool sectionsOnOneLine;
  final bool daysOnOneLine;

  /// A section label's box; null leaves the label its own height.
  final double? sectionHeight;

  /// A day read row's height inside its shell, the hairline under it not
  /// included; null leaves the row its own height.
  final double? dayReadHeight;

  const AgendaHeaderSlots({
    required this.sectionsOnOneLine,
    required this.daysOnOneLine,
    this.sectionHeight,
    this.dayReadHeight,
  });

  @override
  bool operator ==(Object other) =>
      other is AgendaHeaderSlots &&
      other.sectionsOnOneLine == sectionsOnOneLine &&
      other.daysOnOneLine == daysOnOneLine &&
      other.sectionHeight == sectionHeight &&
      other.dayReadHeight == dayReadHeight;

  @override
  int get hashCode => Object.hash(
    sectionsOnOneLine,
    daysOnOneLine,
    sectionHeight,
    dayReadHeight,
  );
}

class AgendaDayListDayRow extends AgendaDayListRow {
  final DateTime day;

  /// Entries on the day that were attended.
  final int count;

  final int missed;

  const AgendaDayListDayRow({
    required this.day,
    required this.count,
    required this.missed,
  });
}

class AgendaDayListEntryRow extends AgendaDayListRow {
  final AgendaDayListEntry entry;

  const AgendaDayListEntryRow({required this.entry});
}

/// Flattens [days] and their entries into rows.
///
/// [keptCountOf] rather than the row count: a day header prints how many of
/// the day's entries were **attended**, so a faded missed occurrence is
/// visible in the list without being counted as one. Month separators appear
/// only when the days span two or more months, with the year once they span
/// two years — or on every month with [alwaysMonths], for a list whose header
/// must not come and go as its period narrows to one month. [showYear] names
/// the year by the caller's period instead of by the days that happen to
/// carry entries, so a span across New Year reads the same however it fills.
List<AgendaDayListRow> buildAgendaDayListRows(
  List<DateTime> days,
  List<AgendaDayListEntry> Function(DateTime day) entriesOf, {
  required bool groupByDay,
  required bool withMonths,
  required int Function(DateTime day) keptCountOf,
  bool alwaysMonths = false,
  bool? showYear,
}) {
  if (days.isEmpty) return const [];
  final rows = <AgendaDayListRow>[];
  final multiMonth =
      withMonths &&
      (days.first.year != days.last.year ||
          days.first.month != days.last.month);
  final showMonths = alwaysMonths || multiMonth;
  final crossesYear = showYear ?? days.first.year != days.last.year;
  int? currentMonth;
  var monthIndex = -1;
  var monthKept = 0;
  var monthMissed = 0;
  // A month row is added before its days are walked, so its counts are
  // written back once the next month opens, and after the last day.
  void closeMonth() {
    if (monthIndex < 0) return;
    final row = rows[monthIndex] as AgendaDayListMonthRow;
    rows[monthIndex] = AgendaDayListMonthRow(
      month: row.month,
      showYear: row.showYear,
      kept: monthKept,
      missed: monthMissed,
    );
  }

  for (final day in days) {
    final entries = entriesOf(day);
    if (entries.isEmpty) continue;
    final kept = groupByDay || showMonths ? keptCountOf(day) : 0;
    if (showMonths) {
      final key = day.year * 12 + day.month;
      if (key != currentMonth) {
        closeMonth();
        currentMonth = key;
        monthIndex = rows.length;
        monthKept = 0;
        monthMissed = 0;
        rows.add(
          AgendaDayListMonthRow(
            month: DateTime.utc(day.year, day.month, 1),
            showYear: crossesYear,
          ),
        );
      }
      monthKept += kept;
      monthMissed += entries.length - kept;
    }
    if (groupByDay) {
      rows.add(
        AgendaDayListDayRow(
          day: day,
          count: kept,
          missed: entries.length - kept,
        ),
      );
    }
    for (final entry in entries) {
      rows.add(AgendaDayListEntryRow(entry: entry));
    }
  }
  closeMonth();
  return rows;
}

/// [entries] folded per event (`docs/calendar-overview-list-roadmap.md`
/// §3.6): one row per event under its category's label, the groups in
/// [categoryOrder] (the catalog's), an unknown category after them by label.
/// Within a group the most frequent event leads, ties by title — or, with
/// [newestFirst], the event seen last leads. Each row wears its first
/// entry's look, so a series reads as it began in the period.
List<AgendaDayListRow> foldAgendaDayListRowsByEvent(
  List<AgendaDayListEntry> entries, {
  required Map<String, String> categoryLabels,
  required List<String> categoryOrder,
  required bool newestFirst,
  required String Function(AgendaDayListEntry entry) categoryOf,
}) {
  final folds = <String, _EventFold>{};
  for (final entry in entries) {
    (folds[entry.eventId ?? entry.title] ??= _EventFold(
      entry,
      categoryOf(entry),
    )).add(entry);
  }
  final groups = <String, List<_EventFold>>{};
  for (final fold in folds.values) {
    (groups[fold.categoryId] ??= <_EventFold>[]).add(fold);
  }
  final rank = {for (final (index, id) in categoryOrder.indexed) id: index};
  String labelOf(String id) => categoryLabels[id] ?? id;
  final categoryIds = groups.keys.toList()
    ..sort((a, b) {
      final byRank = (rank[a] ?? rank.length).compareTo(rank[b] ?? rank.length);
      return byRank != 0 ? byRank : labelOf(a).compareTo(labelOf(b));
    });
  final rows = <AgendaDayListRow>[];
  for (final id in categoryIds) {
    final group = groups[id]!
      ..sort((a, b) {
        final lead = newestFirst
            ? b.last.compareTo(a.last)
            : b.count.compareTo(a.count);
        if (lead != 0) return lead;
        final byTitle = a.titleFold.compareTo(b.titleFold);
        return byTitle != 0 ? byTitle : a.key.compareTo(b.key);
      });
    rows.add(
      AgendaDayListCategoryRow(
        categoryId: id,
        label: labelOf(id),
        eventCount: group.length,
      ),
    );
    for (final fold in group) {
      rows.add(
        AgendaDayListEventRow(
          entry: fold.entry,
          count: fold.count,
          missed: fold.missed,
          first: fold.entry.day,
          last: fold.last,
        ),
      );
    }
  }
  return rows;
}

class _EventFold {
  AgendaDayListEntry entry;
  final String categoryId;
  int count = 0;
  int missed = 0;
  DateTime last;

  _EventFold(this.entry, this.categoryId) : last = entry.day;

  String get key => entry.eventId ?? entry.title;

  String get titleFold => entry.title.toLowerCase();

  void add(AgendaDayListEntry next) {
    count++;
    if (next.missed) missed++;
    if (next.day.isBefore(entry.day)) entry = next;
    if (next.day.isAfter(last)) last = next.day;
  }
}

/// "3 entries", or "3 entries · 2 missed" where the attendance count alone
/// would leave the missed ones unaccounted for.
String agendaDayListCountLabel(AppLocalizations l10n, int kept, int missed) {
  final label = l10n.daySummaryEntryCount(kept);
  if (missed == 0) return label;
  return '$label · ${l10n.dayListMissedCount(missed)}';
}

/// The rows of a dated entry list in the UI language — months as section
/// labels, a day as the read row heading its group, entries under it — for
/// every surface that lists them: the day list sheet, and the overview's
/// list and month bodies (T1), so the two never drift apart. Built per frame
/// over the caller's [rows]; it holds nothing but the choices below.
///
/// A row's tap always opens or selects its entry; marking presence is the
/// day panel's button in the row's trailing slot ([onEntryPresence]), never
/// a mode that changes what the tap does — the overview's tap-to-mark switch
/// read as dead where it could not act and was retired on 2026-10-17.
///
/// The hairline and the corners are the shells'; the gap between groups
/// rides the last row of each, as `FormRowGroup` carries it, and the list's
/// last row carries none — the body's own bottom padding follows it.
class AgendaDayListRowBuilder {
  final List<AgendaDayListRow> rows;

  /// Date-only UTC today, for the Today/Tomorrow day headers.
  final DateTime today;

  final ValueChanged<AgendaDayListEntry> onEntryTap;

  /// The day panel's presence button on every row whose entry tracks
  /// presence ([AgendaDayListEntry.presenceTracked]), handed the status to
  /// write — the explicit opposite of the row's, never a clear. Null offers
  /// no button on any row.
  final void Function(AgendaDayListEntry entry, bool missed)? onEntryPresence;

  /// A `SemanticsIds` value for an entry's presence button — the
  /// [rowIdentifier] twin, since the button is a node beside the row's.
  final String? Function(AgendaDayListEntry entry)? presenceIdentifier;

  /// Offered on rows whose entry carries an edit action; null hides the
  /// trailing button on every row.
  final ValueChanged<AgendaDayListEntry>? onEntryEdit;

  /// A per-event row's tap; null leaves those rows inert.
  final ValueChanged<AgendaDayListEventRow>? onEventTap;

  /// Clamps an entry's caption; null keeps the row's own two-line clamp.
  final int? captionMaxLines;

  /// Whether day headers name the year — a list whose period crosses one.
  final bool dayHeaderWithYear;

  /// Whether a month label carries its month's count.
  final bool monthCounts;

  /// How section labels and day read rows lay out, for a list that gives
  /// every row of a kind one slot; null lets them wrap as their text needs,
  /// the day list sheet's flow.
  final AgendaHeaderSlots? headerSlots;

  /// Keeps an entry's title to one line beside nothing else. With
  /// [headerSlots] and a [captionMaxLines] of one, every row of a kind is one
  /// height ([extentKindOf]).
  final bool singleLineTitles;

  /// A `SemanticsIds` value per entry row, for a surface a device script
  /// walks; null puts none on any row.
  final String? Function(AgendaDayListEntry entry)? rowIdentifier;

  /// The same for a per-event row.
  final String? Function(AgendaDayListEventRow row)? eventRowIdentifier;

  const AgendaDayListRowBuilder({
    required this.rows,
    required this.today,
    required this.onEntryTap,
    this.onEntryPresence,
    this.presenceIdentifier,
    this.onEntryEdit,
    this.onEventTap,
    this.captionMaxLines,
    this.dayHeaderWithYear = false,
    this.monthCounts = false,
    this.headerSlots,
    this.singleLineTitles = false,
    this.rowIdentifier,
    this.eventRowIdentifier,
  });

  static bool _isItem(AgendaDayListRow row) =>
      row is AgendaDayListEntryRow || row is AgendaDayListEventRow;

  /// Which height class the row at [index] takes.
  AgendaRowExtentKind extentKindOf(int index) {
    return switch (rows[index]) {
      AgendaDayListMonthRow() ||
      AgendaDayListCategoryRow() => AgendaRowExtentKind.month,
      AgendaDayListDayRow() => AgendaRowExtentKind.dayRead,
      AgendaDayListEntryRow(:final entry) =>
        entry.subtitle == null
            ? AgendaRowExtentKind.entry
            : AgendaRowExtentKind.entryCaption,
      AgendaDayListEventRow() => AgendaRowExtentKind.entryCaption,
    };
  }

  /// Whether the row at [index] ends its group — the shell's last row, with
  /// no hairline under it. A section label and a day row never do.
  bool closesGroupOf(int index) {
    if (!_isItem(rows[index])) return false;
    return index == rows.length - 1 || !_isItem(rows[index + 1]);
  }

  /// Whether the row at [index] carries the gap to the next group below it.
  bool trailingGapOf(int index) =>
      closesGroupOf(index) && index < rows.length - 1;

  Widget build(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context)!;
    final row = rows[index];
    switch (row) {
      case AgendaDayListMonthRow(
        :final month,
        :final showYear,
        :final kept,
        :final missed,
      ):
        return _section(
          AgendaListView.monthLabel(l10n.localeName, month, withYear: showYear),
          monthCounts ? agendaDayListCountLabel(l10n, kept, missed) : null,
        );
      case AgendaDayListCategoryRow(:final label, :final eventCount):
        return _section(label, l10n.overviewEventCount(eventCount));
      case AgendaDayListDayRow(:final day, :final count, :final missed):
        // A day row is never a group's last: the builder emits one only
        // above the day's entries.
        return FormRowShell(
          first: true,
          last: false,
          child: readRow(context, day: day, kept: count, missed: missed),
        );
      case AgendaDayListEntryRow(:final entry):
        return FormRowShell(
          first: false,
          last: closesGroupOf(index),
          trailingGap: index < rows.length - 1,
          child: _entryRow(l10n, entry),
        );
      case AgendaDayListEventRow():
        // A category's label sits on the ground above its group, so the
        // group's first event row opens it with the rounded top.
        return FormRowShell(
          first: index == 0 || rows[index - 1] is AgendaDayListCategoryRow,
          last: closesGroupOf(index),
          trailingGap: index < rows.length - 1,
          child: _eventRow(l10n, row),
        );
    }
  }

  /// A section label — a month's or a category's — in its slot when
  /// [headerSlots] gives it one, sitting on the group below it.
  Widget _section(String text, String? trailing) {
    final slots = headerSlots;
    final label = FormSectionLabel(
      text: text,
      trailing: trailing,
      singleLine: slots?.sectionsOnOneLine ?? false,
      wrapTrailing: slots != null,
    );
    final height = slots?.sectionHeight;
    if (height == null) return label;
    // An Align, not a Column: for the one frame a text scale or locale change
    // draws new text on the old slots, a taller label is clipped by the list
    // rather than reported as an overflow.
    return SizedBox(
      height: height,
      child: Align(
        alignment: AlignmentDirectional.bottomStart,
        // The full width, so the count still ends the row.
        child: SizedBox(width: double.infinity, child: label),
      ),
    );
  }

  /// A day's head: its label and its attendance count as a read row — fully
  /// drawn and inert, never dimmed, since there is nothing a tap could do.
  /// [trailingButton] is the picked day's "Whole month" in a month body.
  /// In a slot of [headerSlots] the row takes the slot's height, its text
  /// centred in it.
  Widget readRow(
    BuildContext context, {
    required DateTime day,
    required int kept,
    required int missed,
    FormTrailingButton? trailingButton,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final row = FormPickerRow(
      label: AgendaListView.dayHeaderLabel(
        l10n,
        day,
        today,
        withYear: dayHeaderWithYear,
      ),
      value: agendaDayListCountLabel(l10n, kept, missed),
      onTap: null,
      showChevron: false,
      dividerIndent: FormMetrics.dividerIndentPlain,
      trailingButton: trailingButton,
      singleLine: headerSlots?.daysOnOneLine ?? false,
    );
    final height = headerSlots?.dayReadHeight;
    return height == null ? row : SizedBox(height: height, child: row);
  }

  /// An entry: the event's look, its title over the agenda row's own
  /// subtitle, and one second target — the pencil where the entry carries an
  /// edit, else the day panel's presence button where the surface offers it
  /// and the event tracks presence (the overview's day rows, 2026-10-17: the
  /// control the user already knows, visible on the row, rather than a mode
  /// that changes what a tap does). No chevron in any case — a tap selects or
  /// opens the entry's day, never a form. The button fades with a missed row,
  /// as the day panel's does.
  Widget _entryRow(AppLocalizations l10n, AgendaDayListEntry entry) {
    final onEdit = onEntryEdit;
    final onPresence = onEntryPresence;
    final FormTrailingButton? trailing;
    if (onEdit != null && entry.onEdit != null) {
      trailing = FormTrailingButton(
        icon: Icons.edit_outlined,
        tooltip: l10n.upcomingEditEvent,
        onPressed: () => onEdit(entry),
      );
    } else if (onPresence != null && entry.presenceTracked) {
      trailing = FormTrailingButton(
        icon: entry.missed
            ? Icons.event_available_rounded
            : Icons.event_busy_rounded,
        tooltip: entry.missed ? l10n.eventMarkPresent : l10n.eventMarkMissed,
        onPressed: () => onPresence(entry, !entry.missed),
        identifier: presenceIdentifier?.call(entry),
      );
    } else {
      trailing = null;
    }
    return _faded(
      entry.missed,
      FormPickerRow(
        leading: EventAvatar(icon: entry.icon, color: entry.color),
        label: entry.title,
        caption: entry.subtitle,
        captionMaxLines: captionMaxLines,
        singleLine: singleLineTitles,
        identifier: rowIdentifier?.call(entry),
        onTap: () => onEntryTap(entry),
        showChevron: false,
        trailingButton: trailing,
      ),
    );
  }

  /// An event folded over the period: its look and title, how often it
  /// occurred as the value, its first and last day and the missed ones as
  /// the caption. One line beside its count whatever the surface: a count
  /// dropped under a long title would read as the caption's.
  Widget _eventRow(AppLocalizations l10n, AgendaDayListEventRow row) {
    final entry = row.entry;
    final span = _eventSpan(l10n, row.first, row.last);
    final tap = onEventTap;
    return FormPickerRow(
      leading: EventAvatar(icon: entry.icon, color: entry.color),
      label: entry.title,
      value: '${row.count}',
      caption: row.missed > 0
          ? '$span · ${l10n.dayListMissedCount(row.missed)}'
          : span,
      captionMaxLines: captionMaxLines,
      singleLine: true,
      identifier: eventRowIdentifier?.call(row),
      onTap: tap == null ? null : () => tap(row),
      showChevron: false,
    );
  }

  /// The shell reads the hairline's indent off a `FormDividedRow` alone, so
  /// a faded row hands its title indent out through the wrapper.
  static Widget _faded(bool missed, Widget row) {
    if (!missed) return row;
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentTitle,
      child: Opacity(opacity: CalendarColors.missedEventAlpha, child: row),
    );
  }

  /// "Mar 15 – Jun 20, 2026" in the Dates sheet's grammar, both years named
  /// across New Year; one date when the event occurred on one day.
  static String _eventSpan(
    AppLocalizations l10n,
    DateTime first,
    DateTime last,
  ) {
    final localeName = l10n.localeName;
    final lastLabel = DateFormat.yMMMd(localeName).format(last);
    if (first == last) return lastLabel;
    final firstLabel = first.year == last.year
        ? DateFormat.MMMd(localeName).format(first)
        : DateFormat.yMMMd(localeName).format(first);
    return l10n.overviewEventSpan(firstLabel, lastLabel);
  }
}
