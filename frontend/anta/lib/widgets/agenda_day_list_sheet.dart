import 'package:flutter/material.dart';

/// One dated row inside an [AgendaDayList].
///
/// Pre-resolved on purpose: the sheet that renders these reads no facade and
/// resolves no localization of its own, so the domain knowledge stays in the
/// agenda layer that already holds it.
class AgendaDayListEntry {
  /// The day this row stands for, and what a tap on it returns.
  final DateTime day;

  final IconData icon;
  final Color color;

  /// Leads with whichever half actually varies down the list — the holiday's
  /// name for a holiday list, the date for a fasting list where every row
  /// belongs to the same fast.
  final String title;
  final String? subtitle;

  /// Optional trailing action. Event rows open the editor with it, so
  /// collapsing the events layer never puts editing further away than a row
  /// tap; a holiday or fasting day has nothing to open and leaves it null,
  /// which is also what keeps those rows free of an empty action strip.
  ///
  /// Held here rather than run from inside the sheet: the sheet resolves it
  /// back to the caller instead, so the editor opens **after** this sheet is
  /// gone rather than stacked on top of it — the same "return an intent, let
  /// the caller route it" contract `EventDetailSheet` follows.
  final VoidCallback? onEdit;

  const AgendaDayListEntry({
    required this.day,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.onEdit,
  });
}

/// What the viewer picked out of the sheet: a day to focus, or an entry's
/// edit action to run.
///
/// A record rather than a sealed hierarchy — the house style for small
/// multi-valued returns (`getMoneyConfig`, the day-group tuples in
/// `buildAgendaRows`) — and returned rather than acted on, so the editor opens
/// after this sheet has closed instead of stacking on it.
typedef AgendaDayListResult = ({DateTime? focusDay, VoidCallback? edit});

/// The full contents behind a summary card, ready to render.
///
/// [title] and [subtitle] are the **card's own**, so the sheet header and the
/// card that opened it read as the same object — and the count the card claims
/// is the count of [entries] rather than a second, separately-derived number.
class AgendaDayList {
  final String title;
  final String subtitle;
  final List<AgendaDayListEntry> entries;

  const AgendaDayList({
    required this.title,
    required this.subtitle,
    required this.entries,
  });
}

/// Drill-down behind an agenda summary card: every day the card stands for,
/// each tappable to focus it on the calendar.
///
/// Scoped to the **agenda window**, because that is what the card summarizes —
/// a sheet reaching further would contradict the number the user tapped. That
/// also means it needs no scan of its own: the caller already holds the days.
///
/// Deliberately dumb — no `PublicHolidays`, no `FastingCalendar`, no
/// `AppLocalizations`. Everything it draws arrives in [AgendaDayList], which is
/// what lets one sheet serve the holiday card and the fasting card, and a third
/// source later.
class AgendaDayListSheet extends StatelessWidget {
  final AgendaDayList list;

  const AgendaDayListSheet({
    super.key,
    required this.list,
    required this.editTooltip,
  });

  /// Localized tooltip for the rows that carry an edit action. Passed in for
  /// the same reason everything else is: this sheet resolves no localization
  /// of its own.
  final String editTooltip;

  /// Resolves to what the viewer picked, or null when dismissed.
  static Future<AgendaDayListResult?> show(
    BuildContext context,
    AgendaDayList list, {
    required String editTooltip,
  }) {
    return showModalBottomSheet<AgendaDayListResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        // Taller than the sibling holiday sheets: a fasting card can stand for
        // forty days, and a list that short would spend most of its height on
        // chrome.
        heightFactor: 0.7,
        child: AgendaDayListSheet(list: list, editTooltip: editTooltip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar — same fix as `CategoryPickerSheet`.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                list.title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                list.subtitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 16 + bottomClearance),
            itemCount: list.entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = list.entries[index];
              final onEdit = entry.onEdit;
              return ListTile(
                // Same avatar treatment the agenda card uses, so a row here
                // reads as the same thing the card summarized.
                leading: CircleAvatar(
                  backgroundColor: entry.color.withValues(alpha: 0.16),
                  foregroundColor: entry.color,
                  child: Icon(entry.icon),
                ),
                title: Text(entry.title),
                subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
                trailing: onEdit == null
                    ? null
                    : IconButton(
                        tooltip: editTooltip,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.of(
                          context,
                        ).pop((focusDay: null, edit: onEdit)),
                      ),
                onTap: () => Navigator.of(
                  context,
                ).pop((focusDay: entry.day, edit: null)),
              );
            },
          ),
        ),
      ],
    );
  }
}
