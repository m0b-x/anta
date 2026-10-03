import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_bounds.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/fasting_schedule.dart';
import '../services/recurrence_formatter.dart';
import 'calendar_date_picker_sheet.dart';
import 'form_rows.dart';

/// Editor for the personal fasting practice: the weekdays kept, the months
/// kept, what a disabled month suppresses, and the exception dates — a
/// sub-sheet of the UI language (Tier 3, D15–D17): two labelled groups of
/// chips with their bulk actions and scope, then the two exception lists as
/// picker rows with one removable sub-row per date.
///
/// Applies **live** through [onChanged] rather than gating behind a Save,
/// exactly like [FastingStyleSheet] — every control is a settings toggle and
/// the caller persists on each change, so dismissing keeps the edits. Nothing
/// here is a text field, so nothing is pending when the sheet goes, and the
/// sheet is unguarded like every sub-sheet.
class FastingScheduleSheet extends StatefulWidget {
  final FastingSchedule initialSchedule;

  /// Look & feel for the exception-date picker, passed down from the calendar
  /// page rather than re-read: the settings page already holds a current copy,
  /// and a leaf-local load would go stale when appearance changes.
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
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: FastingScheduleSheet(
          initialSchedule: initialSchedule,
          appearance: appearance,
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  State<FastingScheduleSheet> createState() => _FastingScheduleSheetState();
}

class _FastingScheduleSheetState extends State<FastingScheduleSheet> {
  late FastingSchedule _schedule;
  final FormHeaderHairline _hairline = FormHeaderHairline();

  /// The anchor year the month labels are formatted against. Any year
  /// serves — only the month matters — and one fixed year keeps the labels
  /// identical across sessions.
  static const int _monthLabelAnchorYear = 2024;

  /// The ids' names for the two exception lists, keyed into
  /// [SemanticsIds.fastingDateRemove].
  static const String _skipKind = 'skip';
  static const String _forceKind = 'force';

  static final Set<int> _everyWeekday = {
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
      weekday,
  };

  @override
  void initState() {
    super.initState();
    _schedule = widget.initialSchedule;
  }

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
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
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the rule every calendar sheet
    // follows (`sheet_bottom_clearance_test.dart`): the box is a fixed
    // fraction of the screen, and a tall IME would collapse a padded Column
    // to nothing.
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.close,
          leadingIdentifier: SemanticsIds.fastingScheduleClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.fastingScheduleTitle,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Nothing to confirm: every control has already written.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: _hairline.watch(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormSectionLabel(text: l10n.fastingWeekdayDaysTitle),
                  FormRowGroup(
                    children: [
                      _buildWeekdayChips(l10n),
                      ..._buildBulkRows(
                        l10n,
                        allIdentifier: SemanticsIds.fastingWeekdaysAll,
                        noneIdentifier: SemanticsIds.fastingWeekdaysNone,
                        complete: _schedule.weekdays.containsAll(_everyWeekday),
                        empty: _schedule.weekdays.isEmpty,
                        onAll: () =>
                            _apply(_schedule.copyWith(weekdays: _everyWeekday)),
                        onNone: () =>
                            _apply(_schedule.copyWith(weekdays: const {})),
                      ),
                      _buildScopeRow(
                        label: l10n.fastingWeekdayScopeTitle,
                        weekly:
                            _schedule.weekdayScope ==
                            FastingWeekdayScope.weeklyOnly,
                        weeklyHint: l10n.fastingWeekdayScopeHintWeekly,
                        allHint: l10n.fastingWeekdayScopeHintAll,
                        chips: [
                          for (final scope in FastingWeekdayScope.values)
                            FormChip(
                              label: _weekdayScopeLabel(scope, l10n),
                              selected: _schedule.weekdayScope == scope,
                              identifier: _weekdayScopeId(scope),
                              onTap: () => _apply(
                                _schedule.copyWith(weekdayScope: scope),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.fastingMonthsTitle),
                  FormRowGroup(
                    children: [
                      _buildMonthChips(l10n),
                      ..._buildBulkRows(
                        l10n,
                        allIdentifier: SemanticsIds.fastingMonthsAll,
                        noneIdentifier: SemanticsIds.fastingMonthsNone,
                        complete: _schedule.keepsEveryMonth,
                        empty: _schedule.months.isEmpty,
                        onAll: () => _apply(
                          _schedule.copyWith(months: FastingSchedule.allMonths),
                        ),
                        onNone: () =>
                            _apply(_schedule.copyWith(months: const {})),
                      ),
                      // Stays with all twelve months ticked: the user has to
                      // see what turning a month off will do before turning
                      // one off.
                      _buildScopeRow(
                        label: l10n.fastingMonthScopeTitle,
                        weekly:
                            _schedule.monthScope ==
                            FastingMonthScope.weeklyOnly,
                        weeklyHint: l10n.fastingMonthScopeHintWeekly,
                        allHint: l10n.fastingMonthScopeHintAll,
                        chips: [
                          for (final scope in FastingMonthScope.values)
                            FormChip(
                              label: _scopeLabel(scope, l10n),
                              selected: _schedule.monthScope == scope,
                              identifier: _monthScopeId(scope),
                              onTap: () =>
                                  _apply(_schedule.copyWith(monthScope: scope)),
                            ),
                        ],
                      ),
                    ],
                  ),
                  FormRowGroup(
                    trailingGap: false,
                    children: [
                      ..._buildExceptionRows(l10n, skip: true),
                      ..._buildExceptionRows(l10n, skip: false),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The seven weekdays, Monday first, each a chip whose width never changes
  /// with its state (D16) — the old filter chips grew a check glyph when
  /// selected and reflowed the whole run under the finger.
  Widget _buildWeekdayChips(AppLocalizations l10n) {
    return FormChipRow(
      indented: false,
      chips: [
        for (final weekday in _everyWeekday)
          FormChip(
            label: RecurrenceFormatter.weekdayShort(weekday, l10n.localeName),
            selected: _schedule.weekdays.contains(weekday),
            identifier: SemanticsIds.fastingWeekday(weekday),
            onTap: () => _toggleWeekday(weekday),
          ),
      ],
      caption: FormCaption(text: l10n.fastingWeekdayDaysDesc),
    );
  }

  Widget _buildMonthChips(AppLocalizations l10n) {
    return FormChipRow(
      indented: false,
      chips: [
        for (var month = DateTime.january; month <= DateTime.december; month++)
          FormChip(
            label: _monthLabel(month, l10n.localeName),
            selected: _schedule.months.contains(month),
            identifier: SemanticsIds.fastingMonth(month),
            onTap: () => _toggleMonth(month),
          ),
      ],
    );
  }

  /// Select all and None as two action rows under a chip run, each disabled
  /// **in place** while it would change nothing (the category picker's
  /// rule): a row that vanished would move the scope row under the finger.
  List<Widget> _buildBulkRows(
    AppLocalizations l10n, {
    required String allIdentifier,
    required String noneIdentifier,
    required bool complete,
    required bool empty,
    required VoidCallback onAll,
    required VoidCallback onNone,
  }) {
    return [
      FormActionRow(
        glyph: Icons.done_all_rounded,
        label: l10n.selectAll,
        identifier: allIdentifier,
        onTap: complete ? null : onAll,
      ),
      FormActionRow(
        glyph: Icons.remove_done_rounded,
        label: l10n.selectNone,
        identifier: noneIdentifier,
        onTap: empty ? null : onNone,
      ),
    ];
  }

  /// A scope as a labelled chip pair over the line that reads the choice
  /// back. The line sits in a slot as tall as the longer of the two hints,
  /// so switching the scope never moves the rows under it.
  Widget _buildScopeRow({
    required String label,
    required bool weekly,
    required String weeklyHint,
    required String allHint,
    required List<Widget> chips,
  }) {
    final weeklyCaption = FormCaption(text: weeklyHint);
    final allCaption = FormCaption(text: allHint);
    return FormChipRow(
      glyph: Icons.tune_rounded,
      label: label,
      chips: chips,
      caption: FormCaptionSlot(
        candidates: [weeklyCaption, allCaption],
        child: weekly ? weeklyCaption : allCaption,
      ),
    );
  }

  /// One exception list: the picker row carrying the count — "Limit reached"
  /// and disabled at the cap, the add row never hidden — then one sub-row
  /// per date, ascending, each with its own remove button (D17, the
  /// editor's explicit-dates shape).
  List<Widget> _buildExceptionRows(
    AppLocalizations l10n, {
    required bool skip,
  }) {
    final dates = skip ? _schedule.skipDates : _schedule.forceDates;
    final full = dates.length >= FastingSchedule.maxExceptionDates;
    final sorted = dates.toList()..sort();
    final formatter = DateFormat.yMMMEd(l10n.localeName);
    final kind = skip ? _skipKind : _forceKind;
    return [
      FormPickerRow(
        glyph: skip ? Icons.event_busy_rounded : Icons.event_available_rounded,
        label: skip
            ? l10n.fastingExceptionsSkipTitle
            : l10n.fastingExceptionsForceTitle,
        value: full
            ? l10n.fastingExceptionsFull
            : dates.isEmpty
            ? l10n.selectNone
            : l10n.fastingExceptionsCount(dates.length),
        caption: skip
            ? l10n.fastingExceptionsSkipHint
            : l10n.fastingExceptionsForceHint,
        enabled: !full,
        onTap: () => _addDates(skip: skip),
        identifier: skip
            ? SemanticsIds.fastingDaysOff
            : SemanticsIds.fastingExtraDays,
      ),
      for (final date in sorted)
        FormPickerRow(
          subRow: true,
          label: formatter.format(date),
          onTap: null,
          showChevron: false,
          trailingButton: FormTrailingButton(
            icon: Icons.close_rounded,
            tooltip: l10n.remove,
            identifier: SemanticsIds.fastingDateRemove(kind, date),
            onPressed: () => _removeDate(date, skip: skip),
          ),
        ),
    ];
  }

  /// Locale-specific abbreviated month name, derived from `intl` against an
  /// anchor date — never an ARB month matrix, the same rule the week-start
  /// dropdown and the month/year wheel already follow.
  String _monthLabel(int month, String localeName) {
    final name = DateFormat.MMM(
      localeName,
    ).format(DateTime.utc(_monthLabelAnchorYear, month));
    return toBeginningOfSentenceCase(name, localeName) ?? name;
  }

  String _scopeLabel(FastingMonthScope scope, AppLocalizations l10n) {
    return switch (scope) {
      FastingMonthScope.weeklyOnly => l10n.fastingMonthScopeWeekly,
      FastingMonthScope.allFasts => l10n.fastingMonthScopeAll,
    };
  }

  static String _monthScopeId(FastingMonthScope scope) => switch (scope) {
    FastingMonthScope.weeklyOnly => SemanticsIds.fastingMonthScopeWeekly,
    FastingMonthScope.allFasts => SemanticsIds.fastingMonthScopeAll,
  };

  static String _weekdayScopeId(FastingWeekdayScope scope) => switch (scope) {
    FastingWeekdayScope.weeklyOnly => SemanticsIds.fastingWeekdayScopeWeekly,
    FastingWeekdayScope.allFasts => SemanticsIds.fastingWeekdayScopeAll,
  };

  /// Shares the month scope's option labels: the two scopes answer the same
  /// question about a different axis, and inventing a second wording for
  /// "weekly fast only" would read as a different meaning.
  ///
  /// The hint under each pair has to describe the **selected** scope, not
  /// the section: under `weeklyOnly` a multi-day fast still marks every one
  /// of its days, so a flat "a day you turn off is never marked" told the
  /// exact opposite of what the default configuration does — which is what
  /// made a Wed/Fri practice look broken every August, when the Dormition
  /// fast covers half the month. The month twin was wrong in the same way.
  String _weekdayScopeLabel(FastingWeekdayScope scope, AppLocalizations l10n) {
    return switch (scope) {
      FastingWeekdayScope.weeklyOnly => l10n.fastingMonthScopeWeekly,
      FastingWeekdayScope.allFasts => l10n.fastingMonthScopeAll,
    };
  }
}
