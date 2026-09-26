import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_bounds.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../services/recurrence_formatter.dart';
import 'automation_id.dart';
import 'calendar_date_picker_sheet.dart';
import 'form_rows.dart';

enum RepeatKind {
  daily,
  weekly,
  monthly,
  yearly,
  workdays,
  weekends,
  holidays;

  bool get supportsInterval => switch (this) {
    daily || weekly || monthly || yearly => true,
    workdays || weekends || holidays => false,
  };
}

class EventRepeatDraft extends Equatable {
  final bool recurring;
  final RepeatKind kind;
  final int interval;
  final Set<int> weekdays;
  final DateTime? endDate;
  final bool retroactive;

  static const int maxInterval = 99;

  const EventRepeatDraft({
    required this.recurring,
    required this.kind,
    this.interval = 1,
    this.weekdays = const {},
    this.endDate,
    this.retroactive = false,
  });

  EventRepeatDraft copyWith({
    bool? recurring,
    RepeatKind? kind,
    int? interval,
    Set<int>? weekdays,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? retroactive,
  }) {
    return EventRepeatDraft(
      recurring: recurring ?? this.recurring,
      kind: kind ?? this.kind,
      interval: interval ?? this.interval,
      weekdays: weekdays == null
          ? this.weekdays
          : Set<int>.unmodifiable(weekdays),
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      retroactive: retroactive ?? this.retroactive,
    );
  }

  bool get isValid =>
      !recurring || kind != RepeatKind.weekly || weekdays.isNotEmpty;

  @override
  List<Object?> get props => [
    recurring,
    kind,
    interval,
    weekdays,
    endDate,
    retroactive,
  ];
}

class EventRepeatSheet extends StatefulWidget {
  final EventRepeatDraft draft;
  final DateTime startDate;
  final CalendarAppearance appearance;
  final PickerDayLoad? dayLoad;

  const EventRepeatSheet({
    super.key,
    required this.draft,
    required this.startDate,
    required this.appearance,
    this.dayLoad,
  });

  static const double _heightFactor = 0.92;
  static const double _doneFontSize = 14;
  static const double _doneHorizontalPadding = 12;
  static const double _headerTrailingInset = 8;

  static Future<EventRepeatDraft?> show(
    BuildContext context, {
    required EventRepeatDraft draft,
    required DateTime startDate,
    required CalendarAppearance appearance,
    PickerDayLoad? dayLoad,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<EventRepeatDraft>(
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
          maxHeight: MediaQuery.sizeOf(context).height * _heightFactor,
        ),
        child: EventRepeatSheet(
          draft: draft,
          startDate: startDate,
          appearance: appearance,
          dayLoad: dayLoad,
        ),
      ),
    );
  }

  static String kindLabel(RepeatKind kind, AppLocalizations l10n) {
    return switch (kind) {
      RepeatKind.daily => l10n.recurrenceDaily,
      RepeatKind.weekly => l10n.recurrenceWeekly,
      RepeatKind.monthly => l10n.recurrenceMonthly,
      RepeatKind.yearly => l10n.recurrenceYearly,
      RepeatKind.workdays => l10n.recurrenceWorkdays,
      RepeatKind.weekends => l10n.recurrenceWeekends,
      RepeatKind.holidays => l10n.recurrenceHolidaysOnly,
    };
  }

  @override
  State<EventRepeatSheet> createState() => _EventRepeatSheetState();
}

class _EventRepeatSheetState extends State<EventRepeatSheet> {
  static const Set<int> _everyWeekday = {1, 2, 3, 4, 5, 6, 7};

  late EventRepeatDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft.copyWith(weekdays: widget.draft.weekdays);
  }

  EventRepeatDraft get _template => EventRepeatDraft(
    recurring: true,
    kind: RepeatKind.weekly,
    weekdays: _everyWeekday,
    endDate: widget.startDate,
  );

  void _select(RepeatKind? kind) {
    setState(() {
      _draft = kind == null
          ? _draft.copyWith(recurring: false)
          : _draft.copyWith(recurring: true, kind: kind);
    });
  }

  void _stepInterval(int delta) {
    final next = (_draft.interval + delta).clamp(
      1,
      EventRepeatDraft.maxInterval,
    );
    if (next == _draft.interval) return;
    setState(() => _draft = _draft.copyWith(interval: next));
  }

  void _toggleWeekday(int weekday) {
    final next = Set<int>.of(_draft.weekdays);
    if (!next.add(weekday)) next.remove(weekday);
    setState(() => _draft = _draft.copyWith(weekdays: next));
  }

  Future<void> _pickEndDate() async {
    final start = widget.startDate;
    final initial = _draft.endDate ?? start;
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: initial.isBefore(start) ? start : initial,
      firstDate: start,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draft = _draft.copyWith(
        endDate: DateTime.utc(picked.year, picked.month, picked.day),
      );
    });
  }

  void _clearEndDate() {
    setState(() => _draft = _draft.copyWith(clearEndDate: true));
  }

  void _setRetroactive(bool value) {
    setState(() => _draft = _draft.copyWith(retroactive: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.eventRepeat,
          trailingInset: EventRepeatSheet._headerTrailingInset,
          trailing: AutomationId(
            identifier: SemanticsIds.repeatDone,
            child: TextButton(
            onPressed: _draft.isValid
                ? () => Navigator.of(context).pop(_draft)
                : null,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
              minimumSize: const Size(0, FormMetrics.headerHeight),
              padding: const EdgeInsets.symmetric(
                horizontal: EventRepeatSheet._doneHorizontalPadding,
              ),
              textStyle: const TextStyle(
                fontSize: EventRepeatSheet._doneFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(l10n.eventDescriptionDone),
          ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_buildKinds(l10n), _buildDependentArea()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKinds(AppLocalizations l10n) {
    return FormRowGroup(
      children: [
        FormRadioRow(
          label: l10n.recurrenceDoesNotRepeat,
          selected: !_draft.recurring,
          onTap: () => _select(null),
        ),
        for (final kind in RepeatKind.values)
          FormRadioRow(
            label: EventRepeatSheet.kindLabel(kind, l10n),
            selected: _draft.recurring && _draft.kind == kind,
            onTap: () => _select(kind),
          ),
      ],
    );
  }

  Widget _buildDependentArea() {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: _DependentGroup(
                  draft: _template,
                  startDate: widget.startDate,
                  template: true,
                ),
              ),
            ),
          ),
        ),
        if (_draft.recurring)
          _DependentGroup(
            draft: _draft,
            startDate: widget.startDate,
            onStepInterval: _stepInterval,
            onToggleWeekday: _toggleWeekday,
            onPickEndDate: _pickEndDate,
            onClearEndDate: _clearEndDate,
            onRetroactive: _setRetroactive,
          ),
      ],
    );
  }
}

class _DependentGroup extends StatelessWidget {
  final EventRepeatDraft draft;
  final DateTime startDate;
  final bool template;
  final ValueChanged<int>? onStepInterval;
  final ValueChanged<int>? onToggleWeekday;
  final VoidCallback? onPickEndDate;
  final VoidCallback? onClearEndDate;
  final ValueChanged<bool>? onRetroactive;

  const _DependentGroup({
    required this.draft,
    required this.startDate,
    this.template = false,
    this.onStepInterval,
    this.onToggleWeekday,
    this.onPickEndDate,
    this.onClearEndDate,
    this.onRetroactive,
  });

  static String _unitLabel(AppLocalizations l10n, RepeatKind kind, int n) {
    return switch (kind) {
      RepeatKind.daily => l10n.recurrenceUnitDays(n),
      RepeatKind.weekly => l10n.recurrenceUnitWeeks(n),
      RepeatKind.monthly => l10n.recurrenceUnitMonths(n),
      RepeatKind.yearly => l10n.recurrenceUnitYears(n),
      RepeatKind.workdays || RepeatKind.weekends || RepeatKind.holidays => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat.yMMMd(l10n.localeName);
    final endDate = draft.endDate;
    return FormRowGroup(
      trailingGap: false,
      children: [
        if (draft.kind.supportsInterval)
          _IntervalRow(
            interval: draft.interval,
            unit: _unitLabel(l10n, draft.kind, draft.interval),
            onStep: onStepInterval,
          ),
        if (draft.kind == RepeatKind.weekly)
          _WeekdayRow(
            weekdays: draft.weekdays,
            template: template,
            onToggle: onToggleWeekday,
          ),
        FormPickerRow(
          label: l10n.recurrenceEnds,
          value: endDate == null ? l10n.never : dateFormat.format(endDate),
          onTap: onPickEndDate,
          dividerIndent: FormMetrics.dividerIndentPlain,
          trailingButton: endDate == null
              ? null
              : FormTrailingButton(
                  icon: Icons.close_rounded,
                  tooltip: l10n.recurrenceEndDateRemove,
                  onPressed: onClearEndDate,
                ),
        ),
        FormSwitchRow(
          label: l10n.recurrenceBeforeStart,
          subtitle: draft.kind == RepeatKind.yearly
              ? l10n.recurrenceBeforeStartYearlyHint
              : l10n.recurrenceBeforeStartHint(dateFormat.format(startDate)),
          value: draft.retroactive,
          onChanged: onRetroactive,
          dividerIndent: FormMetrics.dividerIndentPlain,
        ),
      ],
    );
  }
}

class _IntervalRow extends FormDividedRow {
  final int interval;
  final String unit;
  final ValueChanged<int>? onStep;

  const _IntervalRow({
    required this.interval,
    required this.unit,
    required this.onStep,
  });

  static const double valueMinWidth = 96;

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final step = onStep;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(left: RowMetrics.groupInset),
        child: Row(
          children: [
            Expanded(
              child: FormLabelValue(label: l10n.recurrenceIntervalLabel),
            ),
            FormTrailingButton(
              icon: Icons.remove_rounded,
              tooltip: l10n.recurrenceIntervalDecrement,
              color: colorScheme.primary,
              onPressed: step != null && interval > 1 ? () => step(-1) : null,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: valueMinWidth),
              child: Text(
                '$interval $unit',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: FormMetrics.labelSize,
                  height: 20 / FormMetrics.labelSize,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            FormTrailingButton(
              icon: Icons.add_rounded,
              tooltip: l10n.recurrenceIntervalIncrement,
              color: colorScheme.primary,
              onPressed: step != null && interval < EventRepeatDraft.maxInterval
                  ? () => step(1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayRow extends FormDividedRow {
  final Set<int> weekdays;
  final bool template;
  final ValueChanged<int>? onToggle;

  const _WeekdayRow({
    required this.weekdays,
    required this.template,
    required this.onToggle,
  });

  static const double cellHeight = 64;
  static const double circleSize = 40;
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(horizontal: 8);
  static const EdgeInsets captionPadding = EdgeInsets.fromLTRB(
    RowMetrics.groupInset,
    0,
    RowMetrics.groupInset,
    12,
  );

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeName = l10n.localeName;
    final letters = DateFormat.EEEEE(localeName);
    final names = DateFormat.EEEE(localeName);
    final monday = DateTime(2024, 1, 1);
    final toggle = onToggle;
    final readback = FormCaption(
      text: RecurrenceFormatter.formatWeekdays(weekdays, localeName),
      padding: captionPadding,
    );
    final hint = FormCaption(
      text: l10n.weeklyDaysHint,
      error: true,
      padding: captionPadding,
    );
    final Widget caption;
    if (template) {
      caption = Stack(children: [readback, hint]);
    } else {
      caption = weekdays.isEmpty ? hint : readback;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: rowPadding,
          child: Row(
            children: [
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: _WeekdayCell(
                    letter: letters.format(
                      monday.add(Duration(days: weekday - 1)),
                    ),
                    name: names.format(monday.add(Duration(days: weekday - 1))),
                    selected: weekdays.contains(weekday),
                    onTap: toggle == null ? null : () => toggle(weekday),
                  ),
                ),
            ],
          ),
        ),
        caption,
      ],
    );
  }
}

class _WeekdayCell extends StatelessWidget {
  final String letter;
  final String name;
  final bool selected;
  final VoidCallback? onTap;

  const _WeekdayCell({
    required this.letter,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Semantics(
        button: true,
        selected: selected,
        label: name,
        excludeSemantics: true,
        child: SizedBox(
          height: _WeekdayRow.cellHeight,
          child: Center(
            child: Container(
              width: _WeekdayRow.circleSize,
              height: _WeekdayRow.circleSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colorScheme.primary : null,
                border: selected
                    ? null
                    : Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: FormMetrics.labelSize,
                  height: 20 / FormMetrics.labelSize,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
