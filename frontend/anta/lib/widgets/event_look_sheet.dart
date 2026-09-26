import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import 'color_swatch_picker.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'icon_picker_sheet.dart';

class EventLookDraft extends Equatable {
  final String? iconKey;
  final int? colorValue;
  final bool tintIcon;

  const EventLookDraft({this.iconKey, this.colorValue, this.tintIcon = true});

  EventLookDraft copyWith({
    String? iconKey,
    bool clearIconKey = false,
    int? colorValue,
    bool clearColorValue = false,
    bool? tintIcon,
  }) {
    return EventLookDraft(
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
      colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
      tintIcon: tintIcon ?? this.tintIcon,
    );
  }

  bool get isCustom => iconKey != null || colorValue != null;

  @override
  List<Object?> get props => [iconKey, colorValue, tintIcon];
}

abstract final class _LookMetrics {
  static const double maxHeightFactor = 0.92;
  static const double headerTrailingInset = 8;
  static const double doneFontSize = 14;
  static const EdgeInsets donePadding = EdgeInsets.symmetric(horizontal: 12);
  static const EdgeInsets iconRowPadding = EdgeInsets.symmetric(vertical: 8);
  static const EdgeInsets paletteRowPadding = EdgeInsets.fromLTRB(
    RowMetrics.groupInset,
    8,
    RowMetrics.groupInset,
    12,
  );
  static const double swatchSpacing = 2;
}

class EventLookSheet extends StatefulWidget {
  final EventLookDraft draft;
  final CalendarCategory category;

  const EventLookSheet({
    super.key,
    required this.draft,
    required this.category,
  });

  static Future<EventLookDraft?> show(
    BuildContext context, {
    required EventLookDraft draft,
    required CalendarCategory category,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<EventLookDraft>(
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
              MediaQuery.sizeOf(context).height * _LookMetrics.maxHeightFactor,
        ),
        child: EventLookSheet(draft: draft, category: category),
      ),
    );
  }

  @override
  State<EventLookSheet> createState() => _EventLookSheetState();
}

class _EventLookSheetState extends State<EventLookSheet> {
  late EventLookDraft _draft = widget.draft;

  IconData get _icon =>
      CalendarIcons.forKey(_draft.iconKey) ??
      CalendarIcons.forKey(widget.category.iconKey) ??
      Icons.event_rounded;

  Color get _accent {
    final colorValue = _draft.colorValue;
    return colorValue != null && _draft.tintIcon
        ? Color(colorValue)
        : widget.category.color;
  }

  Future<void> _pickIcon() async {
    final picked = await IconPickerSheet.show(
      context,
      tint: _accent,
      initialKey: _draft.iconKey,
    );
    if (picked == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(iconKey: picked));
  }

  void _clearIcon() {
    setState(() => _draft = _draft.copyWith(clearIconKey: true));
  }

  void _setColor(int? value) {
    setState(() {
      _draft = value == null
          ? _draft.copyWith(clearColorValue: true)
          : _draft.copyWith(colorValue: value);
    });
  }

  void _setTint(bool value) {
    setState(() => _draft = _draft.copyWith(tintIcon: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final category = widget.category;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final hasIcon = _draft.iconKey != null;
    final hasColor = _draft.colorValue != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.eventAppearance,
          trailingInset: _LookMetrics.headerTrailingInset,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).pop(_draft),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
              minimumSize: const Size(0, FormMetrics.headerHeight),
              padding: _LookMetrics.donePadding,
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontSize: _LookMetrics.doneFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(l10n.eventDescriptionDone),
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
            child: FormRowGroup(
              trailingGap: false,
              children: [
                _IconRow(
                  icon: _icon,
                  color: _accent,
                  label: l10n.iconLabel,
                  value: hasIcon ? l10n.eventLookCustom : l10n.eventLookDefault,
                  onTap: _pickIcon,
                  trailingButton: hasIcon
                      ? FormTrailingButton(
                          icon: Icons.refresh_rounded,
                          tooltip: l10n.resetToDefault,
                          onPressed: _clearIcon,
                        )
                      : null,
                ),
                _PaletteRow(
                  child: ColorSwatchPicker(
                    value: _draft.colorValue,
                    onChanged: _setColor,
                    spacing: _LookMetrics.swatchSpacing,
                    collapsible: false,
                    defaultOption: ColorSwatchDefault(
                      color: category.color,
                      icon:
                          CalendarIcons.forKey(category.iconKey) ??
                          Icons.event_rounded,
                      tooltip: l10n.eventColorCategoryDefault,
                    ),
                  ),
                ),
                FormSwitchRow(
                  label: l10n.eventTintIcon,
                  value: _draft.tintIcon,
                  onChanged: hasColor ? _setTint : null,
                  dividerIndent: FormMetrics.dividerIndentPlain,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconRow extends FormDividedRow {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;
  final FormTrailingButton? trailingButton;

  const _IconRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailingButton,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final button = trailingButton;
    final well = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: FormMetrics.titleRowMinHeight,
        ),
        child: Padding(
          padding: _LookMetrics.iconRowPadding.copyWith(
            left: RowMetrics.groupInset,
            right: button == null ? RowMetrics.groupInset : 0,
          ),
          child: Row(
            children: [
              EventAvatar(icon: icon, color: color),
              const SizedBox(width: FormMetrics.gap),
              Expanded(child: FormLabelValue(label: label, value: value)),
              if (button == null) ...[
                const SizedBox(width: FormMetrics.gap),
                const FormChevron(),
              ],
            ],
          ),
        ),
      ),
    );
    if (button == null) return well;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: well),
        button,
      ],
    );
  }
}

class _PaletteRow extends FormDividedRow {
  final Widget child;

  const _PaletteRow({required this.child});

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: _LookMetrics.paletteRowPadding, child: child);
  }
}
