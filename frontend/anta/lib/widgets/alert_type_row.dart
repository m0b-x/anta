import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/event_alert.dart';
import 'form_rows.dart';

/// An alert's Type: `[glyph] Type … [Reminder] [Alarm]` over the line that
/// reads the choice back — the alert sheet's first row and the quick
/// alarm's.
///
/// One widget for both because the two sheets ask the same question, and as
/// two copies they had come to offer the tiers in opposite orders. Reminder
/// comes first wherever this row stands.
///
/// The line under the chips sits in a slot as tall as the tallest thing it
/// may say, so neither a tier change nor [alarmWarning] turning up after the
/// sheet has opened moves the rows under it.
class AlertTypeRow extends FormDividedRow {
  /// The tier whose chip is the selected one.
  final AlertMode mode;

  /// A chip was tapped, the selected one included. The sheet owns the tier,
  /// and with it whatever a change of tier parks.
  final ValueChanged<AlertMode> onChanged;

  /// The chips' `SemanticsIds`. Each sheet passes its own pair, so a device
  /// script names a chip on the sheet it is driving.
  final String reminderIdentifier;
  final String alarmIdentifier;

  /// A warning the Alarm tier can show in place of its hint, in the error
  /// colour — the alert sheet's "full-screen alarms are off". Null on a
  /// sheet that has none to give. The slot is sized for it whether it shows
  /// or not, because the answer that decides it arrives after the sheet has
  /// opened.
  final String? alarmWarning;

  /// Whether [alarmWarning] stands in for the Alarm tier's hint now.
  final bool showAlarmWarning;

  const AlertTypeRow({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.reminderIdentifier,
    required this.alarmIdentifier,
    this.alarmWarning,
    this.showAlarmWarning = false,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isAlarm = mode == AlertMode.ring;
    final notifyHint = FormCaption(text: l10n.eventAlertNotifyHint);
    final ringHint = FormCaption(text: l10n.eventAlertRingHint);
    final warning = switch (alarmWarning) {
      final text? => FormCaption(text: text, error: true),
      null => null,
    };
    return FormChipRow(
      glyph: Icons.notifications_outlined,
      label: l10n.eventAlertTypeSection,
      chips: [
        FormChip(
          label: l10n.eventAlertModeNotify,
          selected: !isAlarm,
          identifier: reminderIdentifier,
          onTap: () => onChanged(AlertMode.notify),
        ),
        FormChip(
          label: l10n.eventAlertModeRing,
          selected: isAlarm,
          identifier: alarmIdentifier,
          onTap: () => onChanged(AlertMode.ring),
        ),
      ],
      caption: FormCaptionSlot(
        candidates: [notifyHint, ringHint, ?warning],
        child: !isAlarm
            ? notifyHint
            : warning != null && showAlarmWarning
            ? warning
            : ringHint,
      ),
    );
  }
}
