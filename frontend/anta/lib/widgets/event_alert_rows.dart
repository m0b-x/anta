import 'package:flutter/material.dart';

import '../constants/event_alerts.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../services/event_time_formatter.dart';
import 'automation_id.dart';
import 'form_rows.dart';

/// The event editor's alert rows — the event's own, then the ones its
/// category hands down, then Add alert — built once for the editor and for
/// the read sheet of a partner's event (share surfaces §8, row 5), so my
/// alerts on a shared event read and behave exactly as on my own.
///
/// [enabled] false is the read sheet under "Alerts for shared events: Off"
/// (decision k): every row stays where it stands at 38 %, with no tap, and
/// the ✕ dims through [FormTrailingButton.disabledColor], which its own
/// colour would otherwise beat.
List<Widget> eventAlertRows(
  BuildContext context, {
  required AppLocalizations l10n,
  required CalendarEvent previewEvent,
  required List<EventAlert> alerts,
  required List<EventAlert> inherited,
  required String categoryLabel,
  required ValueChanged<EventAlert> onEdit,
  required ValueChanged<EventAlert> onRemove,
  required VoidCallback onAdd,
  required String addIdentifier,
  bool inheritedEnabled = true,
  bool enabled = true,
}) {
  String formatMinute(int minute) =>
      EventTimeFormatter.formatMinute(minute, context);
  final disabledColor = enabled
      ? null
      : Theme.of(
          context,
        ).colorScheme.outline.withValues(alpha: FormMetrics.disabledOpacity);
  return [
    for (final (index, alert) in alerts.indexed)
      FormPickerRow(
        glyph: alert.isAlarm
            ? Icons.alarm_outlined
            : Icons.notifications_outlined,
        label: alert.describe(l10n, previewEvent, formatMinute: formatMinute),
        value: alert.isAlarm
            ? l10n.eventAlertModeRing
            : l10n.eventAlertModeNotify,
        onTap: () => onEdit(alert),
        enabled: enabled,
        trailingButton: FormTrailingButton(
          icon: Icons.close_rounded,
          tooltip: l10n.eventAlertRemove,
          identifier: SemanticsIds.eventAlertRemove(index),
          onPressed: enabled ? () => onRemove(alert) : null,
          disabledColor: disabledColor,
        ),
      ),
    for (final (index, alert) in inherited.indexed)
      FormPickerRow(
        glyph: alert.isAlarm
            ? Icons.alarm_outlined
            : Icons.notifications_outlined,
        label: alert.describe(l10n, previewEvent, formatMinute: formatMinute),
        caption: [
          l10n.eventAlertFromCategory(categoryLabel),
          alert.isAlarm ? l10n.eventAlertModeRing : l10n.eventAlertModeNotify,
        ].join(' · '),
        identifier: SemanticsIds.eventInheritedAlert(index),
        onTap: null,
        showChevron: false,
        enabled: inheritedEnabled && enabled,
      ),
    if (alerts.length < kMaxAlertsPerEvent)
      AutomationId(
        identifier: addIdentifier,
        child: FormActionRow(
          glyph: Icons.add_rounded,
          label: l10n.eventAlertAdd,
          onTap: enabled ? onAdd : null,
        ),
      ),
  ];
}
