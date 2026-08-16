import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_bounds.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/fasting_schedule.dart';
import '../services/recurrence_formatter.dart';
import 'calendar_date_picker_sheet.dart';

/// Editor for the personal fasting practice: the weekdays kept, the months
/// kept, what a disabled month suppresses, and the exception dates.
///
/// Applies **live** through [onChanged] rather than gating behind a Save,
/// exactly like [FastingStyleSheet] — every control is a settings toggle and
/// the caller persists on each change, so dismissing keeps the edits. Nothing
/// here is a text field, so there is no debounce to flush either.
class FastingScheduleSheet extends StatefulWidget {
  final FastingSchedule initialSchedule;

  /// Look & feel for the exception-date picker, passed down from the calendar
  /// page rather than re-read: `getCalendarAppearance()` is seven sequential
  /// settings reads and the settings page already holds a current copy.
  final CalendarAppearance appearance;

  final ValueChanged<FastingSchedule> onChanged;

  const FastingScheduleSheet({
    super.key,
    required this.initialSchedule,
    required this.appearance,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required FastingSchedule initialSchedule,
    required CalendarAppearance appearance,
    required ValueChanged<FastingSchedule> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FastingScheduleSheet(
        initialSchedule: initialSchedule,
        appearance: appearance,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<FastingScheduleSheet> createState() => _FastingScheduleSheetState();
}

class _FastingScheduleSheetState extends State<FastingScheduleSheet> {
  late FastingSchedule _schedule;

  @override
  void initState() {
    super.initState();
    _schedule = widget.initialSchedule;
  }

  void _apply(FastingSchedule next) {
    setState(() => _schedule = next);
    widget.onChanged(next);
  }

  void _toggleWeekday(int weekday) {
    final next = {..._schedule.weekdays};
    next.contains(weekday) ? next.remove(weekday) : next.add(weekday);
    _apply(_schedule.copyWith(weekdays: next));
  }

  void _toggleMonth(int month) {
    final next = {..._schedule.months};
    next.contains(month) ? next.remove(month) : next.add(month);
    _apply(_schedule.copyWith(months: next));
  }

  /// Adds dates to one exception list and removes them from the other, so a
  /// day can never be asked to be both skipped and forced. The model's
  /// normalization would resolve the clash silently in force's favour; doing
  /// it here means the tap the user just made is always the one that wins.
  Future<void> _addDates({required bool skip}) async {
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      // Deliberately empty rather than the current set: `pickMulti` never
      // returns an empty selection (clearing everything keeps the caller's
      // dates), so it is used purely additively and removal happens through
      // the rows below.
      initialSelection: const {},
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    _apply(
      skip
          ? _schedule.copyWith(
              skipDates: {..._schedule.skipDates, ...picked},
              forceDates: {..._schedule.forceDates}..removeAll(picked),
            )
          : _schedule.copyWith(
              forceDates: {..._schedule.forceDates, ...picked},
              skipDates: {..._schedule.skipDates}..removeAll(picked),
            ),
    );
  }

  void _removeDate(DateTime date, {required bool skip}) {
    _apply(
      skip
          ? _schedule.copyWith(
              skipDates: {..._schedule.skipDates}..remove(date),
            )
          : _schedule.copyWith(
              forceDates: {..._schedule.forceDates}..remove(date),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    l10n.fastingScheduleTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _labelRow(
                  theme,
                  l10n.fastingWeekdayDaysTitle,
                  l10n,
                  onAll: () => _apply(
                    _schedule.copyWith(weekdays: {1, 2, 3, 4, 5, 6, 7}),
                  ),
                  onNone: () =>
                      _apply(_schedule.copyWith(weekdays: const {})),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var weekday = 1; weekday <= 7; weekday++)
                      FilterChip(
                        label: Text(
                          RecurrenceFormatter.weekdayShort(
                            weekday,
                            l10n.localeName,
                          ),
                        ),
                        selected: _schedule.weekdays.contains(weekday),
                        onSelected: (_) => _toggleWeekday(weekday),
                      ),
                  ],
                ),
                _hint(theme, l10n.fastingWeekdayDaysDesc),
                _labelRow(
                  theme,
                  l10n.fastingMonthsTitle,
                  l10n,
                  onAll: () => _apply(
                    _schedule.copyWith(months: FastingSchedule.allMonths),
                  ),
                  onNone: () => _apply(_schedule.copyWith(months: const {})),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var month = 1; month <= 12; month++)
                      FilterChip(
                        label: Text(_monthLabel(month, l10n.localeName)),
                        selected: _schedule.months.contains(month),
                        onSelected: (_) => _toggleMonth(month),
                      ),
                  ],
                ),
                _label(theme, l10n.fastingMonthScopeTitle),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final scope in FastingMonthScope.values)
                      ChoiceChip(
                        label: Text(_scopeLabel(scope, l10n)),
                        selected: _schedule.monthScope == scope,
                        onSelected: (selected) {
                          if (selected) {
                            _apply(_schedule.copyWith(monthScope: scope));
                          }
                        },
                      ),
                  ],
                ),
                _hint(theme, l10n.fastingMonthScopeHint),
                _ExceptionSection(
                  title: l10n.fastingExceptionsSkipTitle,
                  hint: l10n.fastingExceptionsSkipHint,
                  icon: Icons.event_busy_rounded,
                  dates: _schedule.skipDates,
                  onAdd: () => _addDates(skip: true),
                  onRemove: (date) => _removeDate(date, skip: true),
                ),
                _ExceptionSection(
                  title: l10n.fastingExceptionsForceTitle,
                  hint: l10n.fastingExceptionsForceHint,
                  icon: Icons.event_available_rounded,
                  dates: _schedule.forceDates,
                  onAdd: () => _addDates(skip: false),
                  onRemove: (date) => _removeDate(date, skip: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Locale-specific abbreviated month name, derived from `intl` against an
  /// anchor date — never an ARB month matrix, the same rule the week-start
  /// dropdown and the month/year wheel already follow.
  String _monthLabel(int month, String localeName) {
    final name = DateFormat.MMM(localeName).format(DateTime.utc(2024, month));
    return toBeginningOfSentenceCase(name, localeName) ?? name;
  }

  String _scopeLabel(FastingMonthScope scope, AppLocalizations l10n) {
    return switch (scope) {
      FastingMonthScope.weeklyOnly => l10n.fastingMonthScopeWeekly,
      FastingMonthScope.allFasts => l10n.fastingMonthScopeAll,
    };
  }

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  /// A section label with the two bulk actions on its trailing edge, so
  /// clearing or filling a twelve-chip row is one tap rather than twelve.
  Widget _labelRow(
    ThemeData theme,
    String text,
    AppLocalizations l10n, {
    required VoidCallback onAll,
    required VoidCallback onNone,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onAll, child: Text(l10n.selectAll)),
          TextButton(onPressed: onNone, child: Text(l10n.selectNone)),
        ],
      ),
    );
  }

  Widget _hint(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One exception-date list: a label, an add button and the picked dates as
/// removable rows. Both lists behave identically, so they share this.
class _ExceptionSection extends StatelessWidget {
  final String title;
  final String hint;
  final IconData icon;
  final Set<DateTime> dates;
  final VoidCallback onAdd;
  final ValueChanged<DateTime> onRemove;

  const _ExceptionSection({
    required this.title,
    required this.hint,
    required this.icon,
    required this.dates,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final full = dates.length >= FastingSchedule.maxExceptionDates;
    final sorted = dates.toList()..sort();
    final formatter = DateFormat.yMMMEd(l10n.localeName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.lg,
            0,
            AppSpacing.sm,
          ),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: full ? null : onAdd,
          icon: Icon(icon),
          label: Text(full ? l10n.fastingExceptionsFull : l10n.fastingAddDates),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final date in sorted)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: colorScheme.onSurfaceVariant),
            title: Text(formatter.format(date)),
            trailing: IconButton(
              tooltip: l10n.remove,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => onRemove(date),
            ),
          ),
      ],
    );
  }
}
