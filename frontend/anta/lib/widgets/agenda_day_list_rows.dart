import 'package:flutter/material.dart';

import '../constants/calendar_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import 'agenda_list_view.dart';

/// A row of a dated entry list: a month separator, a day header, or an entry.
sealed class AgendaDayListRow {
  const AgendaDayListRow();
}

class AgendaDayListMonthRow extends AgendaDayListRow {
  final DateTime month;
  final bool showYear;

  const AgendaDayListMonthRow({required this.month, required this.showYear});
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
/// two years.
List<AgendaDayListRow> buildAgendaDayListRows(
  List<DateTime> days,
  List<AgendaDayListEntry> Function(DateTime day) entriesOf, {
  required bool groupByDay,
  required bool withMonths,
  required int Function(DateTime day) keptCountOf,
}) {
  if (days.isEmpty) return const [];
  final rows = <AgendaDayListRow>[];
  final multiMonth =
      withMonths &&
      (days.first.year != days.last.year ||
          days.first.month != days.last.month);
  final crossesYear = days.first.year != days.last.year;
  int? currentMonth;
  for (final day in days) {
    final entries = entriesOf(day);
    if (entries.isEmpty) continue;
    if (multiMonth) {
      final key = day.year * 12 + day.month;
      if (key != currentMonth) {
        currentMonth = key;
        rows.add(
          AgendaDayListMonthRow(
            month: DateTime.utc(day.year, day.month, 1),
            showYear: crossesYear,
          ),
        );
      }
    }
    if (groupByDay) {
      final kept = keptCountOf(day);
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
  return rows;
}

/// "3 entries", or "3 entries · 2 missed" where the attendance count alone
/// would leave the missed ones unaccounted for.
String agendaDayListCountLabel(AppLocalizations l10n, int kept, int missed) {
  final label = l10n.daySummaryEntryCount(kept);
  if (missed == 0) return label;
  return '$label · ${l10n.dayListMissedCount(missed)}';
}

/// One row of a dated entry list, drawn from [rows] at [index] so a header
/// can size its gap against the row above it.
class AgendaDayListRowView extends StatelessWidget {
  final List<AgendaDayListRow> rows;
  final int index;

  /// Date-only UTC today, for the Today/Tomorrow day headers.
  final DateTime today;

  final ValueChanged<AgendaDayListEntry> onEntryTap;

  /// Offered on rows whose entry carries an edit action; null hides the
  /// trailing button on every row.
  final ValueChanged<AgendaDayListEntry>? onEntryEdit;

  const AgendaDayListRowView({
    super.key,
    required this.rows,
    required this.index,
    required this.today,
    required this.onEntryTap,
    this.onEntryEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final row = rows[index];
    switch (row) {
      case AgendaDayListMonthRow(:final month, :final showYear):
        return Padding(
          padding: EdgeInsets.fromLTRB(8, index == 0 ? 0 : 16, 8, 4),
          child: Row(
            children: [
              Text(
                AgendaListView.monthLabel(
                  l10n.localeName,
                  month,
                  withYear: showYear,
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(height: 1, color: colorScheme.outlineVariant),
              ),
            ],
          ),
        );
      case AgendaDayListDayRow(:final day, :final count, :final missed):
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            index == 0 || rows[index - 1] is AgendaDayListMonthRow ? 4 : 16,
            16,
            4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AgendaListView.dayHeaderLabel(l10n, day, today),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                agendaDayListCountLabel(l10n, count, missed),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      case AgendaDayListEntryRow(:final entry):
        final onEdit = onEntryEdit;
        final tile = ListTile(
          leading: CircleAvatar(
            backgroundColor: entry.color.withValues(alpha: 0.16),
            foregroundColor: entry.color,
            child: Icon(entry.icon),
          ),
          title: Text(entry.title),
          subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
          trailing: onEdit == null || entry.onEdit == null
              ? null
              : IconButton(
                  tooltip: l10n.upcomingEditEvent,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => onEdit(entry),
                ),
          onTap: () => onEntryTap(entry),
        );
        if (!entry.missed) return tile;
        return Opacity(opacity: CalendarColors.missedEventAlpha, child: tile);
    }
  }
}
