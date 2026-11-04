import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/category_kinds.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/category_profile.dart';
import '../utils/category_profile_labels.dart';
import 'form_rows.dart';

/// What the goal sheet hands back: a goal to keep, or the stored one taken
/// away. Null — ✕, the barrier, back, a drag — changes nothing.
sealed class CategoryGoalResult {
  const CategoryGoalResult();
}

final class CategoryGoalSaved extends CategoryGoalResult {
  final ReportTarget target;

  const CategoryGoalSaved(this.target);
}

final class CategoryGoalRemoved extends CategoryGoalResult {
  const CategoryGoalRemoved();
}

/// A category's goal (record §6.6, the S3 spec's §2.5): its type, a value
/// in the primary measure's unit — typed or stepped — and the period it is
/// counted over, read back in words under them. ✕ · Goal · Done.
///
/// A draft, like every sub-sheet: Done returns the goal and the editor's
/// Save persists it (the spec's I). The value and the days of a gap are held
/// apart, so switching the type back and forth loses neither; the period
/// chips stay in place under Days between, disabled and with none chosen —
/// a gap has no period — and the period comes back with an amount. The
/// value block is sized over every type and every read-back the sheet can
/// show, so nothing moves while the owner works in it.
class CategoryGoalSheet extends StatefulWidget {
  /// The stored goal, which the sheet opens on and offers to remove.
  final ReportTarget? initial;

  /// The category's effective primary: the value's unit, and which types
  /// it can take.
  final ReportMeasure? primary;

  /// The kind's goal presets: the opening type and period of a category
  /// with no goal yet. They preselect, never reorder — the types keep one
  /// order on every kind, so a type is where the owner last found it.
  final List<TargetPreset> presets;

  const CategoryGoalSheet({
    super.key,
    required this.initial,
    required this.primary,
    required this.presets,
  });

  static Future<CategoryGoalResult?> show(
    BuildContext context, {
    required ReportTarget? initial,
    required ReportMeasure? primary,
    required List<TargetPreset> presets,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<CategoryGoalResult>(
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
        child: CategoryGoalSheet(
          initial: initial,
          primary: primary,
          presets: presets,
        ),
      ),
    );
  }

  @override
  State<CategoryGoalSheet> createState() => _CategoryGoalSheetState();
}

class _CategoryGoalSheetState extends State<CategoryGoalSheet> {
  final FormHeaderHairline _hairline = FormHeaderHairline();
  final TextEditingController _value = TextEditingController();
  final FocusNode _valueFocus = FocusNode();

  late final CategoryGoalUnit _unit =
      CategoryGoalLimits.unitOf(widget.primary) ?? CategoryGoalUnit.count;

  /// The three types in the canonical order — At least, At most or Budget,
  /// Days between — and last a stored type the primary does not list
  /// ([_unlisted]).
  late final List<TargetKind> _types = [
    ...CategoryGoalLimits.listedFor(widget.primary),
    ?_unlisted,
  ];

  /// The stored goal's type when the primary does not list it — Budget off
  /// a Money primary, At most on one, as sync or a later build can leave
  /// it. It stays on screen, checked, so the read-back says what is stored
  /// and Done keeps it; once left it cannot be picked again.
  late final TargetKind? _unlisted = () {
    final kind = widget.initial?.kind;
    if (kind == null) return null;
    return CategoryGoalLimits.listedFor(widget.primary).contains(kind)
        ? null
        : kind;
  }();

  late TargetKind _type;
  late TargetPeriod _period;

  /// Whether the owner picked a period here, which a switch to Budget then
  /// keeps rather than preselecting Month (K).
  bool _periodPicked = false;

  /// The field's text for an amount and for a gap's days, the one not on
  /// show kept as it was left.
  late String _amountText;
  late String _daysText;

  /// The stored value, kept verbatim until the owner changes the value or
  /// the type: the field holds whole hours and whole money, so 7.5 h would
  /// otherwise come back as 7 from a Done that only moved the period.
  int? _keptValue;
  String? _keptText;

  @override
  void initState() {
    super.initState();
    final scale = CategoryGoalLimits.scaleOf(_unit);
    final initial = widget.initial;
    final presetPeriod = [
      for (final preset in widget.presets) ?preset.period,
    ].firstOrNull;
    _amountText = '${CategoryGoalLimits.seed(_unit)}';
    _daysText = '${CategoryGoalLimits.seedDays}';
    if (initial != null) {
      _type = initial.kind;
      _period = initial.period ?? presetPeriod ?? TargetPeriod.week;
      if (initial.kind == TargetKind.maxGap) {
        _daysText = '${_clamped(initial.value, CategoryGoalLimits.dayDigits)}';
      } else {
        _amountText =
            '${_clamped(initial.value ~/ scale, CategoryGoalLimits.maxDigits(_unit))}';
      }
    } else {
      final preset = widget.presets
          .where(
            (preset) => CategoryGoalLimits.allows(widget.primary, preset.kind),
          )
          .firstOrNull;
      _type =
          preset?.kind ??
          _types
              .where((kind) => CategoryGoalLimits.allows(widget.primary, kind))
              .firstOrNull ??
          _types.first;
      _period = preset?.period ?? presetPeriod ?? TargetPeriod.week;
    }
    _value.text = _isGap ? _daysText : _amountText;
    if (initial != null) {
      _keptValue = initial.value;
      _keptText = _value.text;
    }
    _value.addListener(_onValueChanged);
  }

  @override
  void dispose() {
    _value.removeListener(_onValueChanged);
    _value.dispose();
    _valueFocus.dispose();
    _hairline.dispose();
    super.dispose();
  }

  static int _clamped(int value, int digits) =>
      value.clamp(CategoryGoalLimits.min, CategoryGoalLimits.maxFor(digits));

  void _onValueChanged() => setState(() {
    if (_value.text != _keptText) _dropKept();
  });

  void _dropKept() {
    _keptValue = null;
    _keptText = null;
  }

  bool get _isGap => _type == TargetKind.maxGap;

  int get _digits => _isGap
      ? CategoryGoalLimits.dayDigits
      : CategoryGoalLimits.maxDigits(_unit);

  int get _number => int.tryParse(_value.text) ?? 0;

  /// The widest number the box ever holds, so it is sized once per open.
  String get _widest =>
      '${CategoryGoalLimits.maxFor(math.max(CategoryGoalLimits.maxDigits(_unit), CategoryGoalLimits.dayDigits))}';

  bool get _canSave =>
      _number >= CategoryGoalLimits.min &&
      (_type == _unlisted || CategoryGoalLimits.allows(widget.primary, _type));

  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  void _selectType(TargetKind kind) {
    if (kind == _type) return;
    if (_isGap) {
      _daysText = _value.text;
    } else {
      _amountText = _value.text;
    }
    _type = kind;
    _dropKept();
    if (kind == TargetKind.budget && !_periodPicked) {
      _period = TargetPeriod.month;
    }
    _setText(_isGap ? _daysText : _amountText);
  }

  /// Rewrites the field with the caret at its end, where the next typed
  /// digit goes.
  void _setText(String text) {
    _value.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _step(int by) {
    final next = (_number + by).clamp(
      CategoryGoalLimits.min,
      CategoryGoalLimits.maxFor(_digits),
    );
    _setText('$next');
  }

  /// The goal on screen as the profile stores it: minutes and cents, a
  /// gap's days with no period.
  ReportTarget _target(TargetKind kind, int number, TargetPeriod period) {
    if (kind == TargetKind.maxGap) {
      return ReportTarget(kind: kind, value: number);
    }
    return ReportTarget(
      kind: kind,
      value: number * CategoryGoalLimits.scaleOf(_unit),
      period: period,
    );
  }

  /// The goal the owner is looking at: the stored value while it is kept.
  ReportTarget get _onScreen {
    final target = _target(_type, _number, _period);
    final kept = _keptValue;
    if (kept == null) return target;
    return ReportTarget(kind: target.kind, value: kept, period: target.period);
  }

  void _done() {
    _blur();
    Navigator.of(context).pop(CategoryGoalSaved(_onScreen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.categoryGoalClose,
          onLeading: () {
            _blur();
            Navigator.of(context).pop();
          },
          title: l10n.categoryGoalTitle,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.eventDescriptionDone,
            identifier: SemanticsIds.categoryGoalDone,
            onPressed: _canSave ? _done : null,
          ),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormSectionLabel(text: l10n.categoryGoalTypeSection),
                  FormRowGroup(
                    children: [
                      for (final kind in _types)
                        FormCheckRow(
                          label: targetKindName(l10n, kind),
                          caption: kind == _unlisted
                              ? l10n.categoryGoalTypeNotForMeasure
                              : null,
                          checked: kind == _type,
                          exclusive: true,
                          identifier: SemanticsIds.categoryGoalType(kind.name),
                          onChanged:
                              kind != _unlisted &&
                                  CategoryGoalLimits.allows(
                                    widget.primary,
                                    kind,
                                  )
                              ? (_) => setState(() => _selectType(kind))
                              : null,
                        ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.categoryGoalTargetSection),
                  // The value's label and the read-back both change with the
                  // type and the number: the tallest of every state is laid
                  // out unseen under the one on show (the offset sheet's
                  // sizer), so a switch never moves the rows under the finger.
                  FormCaptionSlot(
                    candidates: [_buildSizer(l10n)],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTargetGroup(l10n, _type, editable: true),
                        _buildReadBack(_readBackText(l10n)),
                      ],
                    ),
                  ),
                  if (widget.initial != null) ...[
                    const SizedBox(height: RowMetrics.groupGap),
                    FormRowGroup(
                      trailingGap: false,
                      children: [
                        FormActionRow(
                          glyph: Icons.delete_outline_rounded,
                          label: l10n.categoryGoalRemove,
                          destructive: true,
                          identifier: SemanticsIds.categoryGoalRemove,
                          onTap: () {
                            _blur();
                            Navigator.of(
                              context,
                            ).pop(const CategoryGoalRemoved());
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// What the line under the value says: the goal in words, or that there
  /// is none while the field holds no number Done could keep.
  String _readBackText(AppLocalizations l10n) {
    if (_number < CategoryGoalLimits.min) return l10n.categoryGoalNone;
    return categoryGoalReadBack(l10n, _onScreen, widget.primary);
  }

  /// Every type's group laid over one another, and under them every
  /// read-back at the widest number.
  Widget _buildSizer(AppLocalizations l10n) {
    String widestFor(TargetKind kind, TargetPeriod period) {
      final digits = kind == TargetKind.maxGap
          ? CategoryGoalLimits.dayDigits
          : CategoryGoalLimits.maxDigits(_unit);
      return categoryGoalReadBack(
        l10n,
        _target(kind, CategoryGoalLimits.maxFor(digits), period),
        widget.primary,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            for (final kind in _types)
              _buildTargetGroup(l10n, kind, editable: false),
          ],
        ),
        Stack(
          children: [
            _buildReadBack(l10n.categoryGoalNone),
            for (final kind in _types)
              for (final period in TargetPeriod.values)
                _buildReadBack(widestFor(kind, period)),
          ],
        ),
      ],
    );
  }

  String _unitLabel(AppLocalizations l10n, TargetKind kind) {
    if (kind == TargetKind.maxGap) return l10n.categoryGoalUnitDays;
    return switch (_unit) {
      CategoryGoalUnit.count => l10n.categoryGoalUnitCount,
      CategoryGoalUnit.hours => l10n.categoryGoalUnitHours,
      CategoryGoalUnit.tasks => l10n.categoryGoalUnitTasks,
      CategoryGoalUnit.money => l10n.categoryGoalUnitAmount,
    };
  }

  /// The value and the period for [kind]. Only the [editable] one is drawn
  /// with the field and the live handlers; the sizer's twins carry the
  /// widest number as plain text, which the stepper lays out in the same
  /// box.
  Widget _buildTargetGroup(
    AppLocalizations l10n,
    TargetKind kind, {
    required bool editable,
  }) {
    final gap = kind == TargetKind.maxGap;
    final number = _number;
    final max = CategoryGoalLimits.maxFor(_digits);
    return FormRowGroup(
      trailingGap: false,
      children: [
        FormStepperRow(
          label: _unitLabel(l10n, kind),
          // Every type's unit decides beside or stacked, so the buttons and
          // the chips under them stay put on a switch of type.
          widestLabel: [
            for (final type in _types) _unitLabel(l10n, type),
          ].join(' '),
          value: editable ? _value.text : _widest,
          widestValue: _widest,
          controller: editable ? _value : null,
          focusNode: editable ? _valueFocus : null,
          maxDigits: editable ? _digits : null,
          fieldIdentifier: editable ? SemanticsIds.categoryGoalValue : null,
          decrementTooltip: l10n.categoryGoalLess,
          incrementTooltip: l10n.categoryGoalMore,
          decrementIdentifier: editable ? SemanticsIds.categoryGoalLess : null,
          incrementIdentifier: editable ? SemanticsIds.categoryGoalMore : null,
          onDecrement: editable && number > CategoryGoalLimits.min
              ? () => _step(-CategoryGoalLimits.step)
              : null,
          onIncrement: editable && number < max
              ? () => _step(CategoryGoalLimits.step)
              : null,
        ),
        FormChipRow(
          indented: false,
          chips: [
            for (final period in TargetPeriod.values)
              FormChip(
                label: targetPeriodName(l10n, period),
                selected: !gap && period == _period,
                identifier: editable
                    ? SemanticsIds.categoryGoalPeriod(period.name)
                    : null,
                onTap: editable && !gap
                    ? () => setState(() {
                        _period = period;
                        _periodPicked = true;
                      })
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadBack(String text) {
    return FormCaption(text: text, padding: FormMetrics.groupCaptionPadding);
  }
}
