import 'package:flutter/material.dart';

import '../constants/event_alerts.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';

/// The 14 dp glyphs that say an event will speak up — a bell for a reminder,
/// a clock for an alarm (§5.4).
///
/// Exactly the description badge beside it: same size, same spacing, same
/// `Tooltip`, because a row's title line already has one vocabulary for "this
/// event carries something extra" and a second shape would read as a second
/// kind of thing.
///
/// Read **synchronously** from [EventAlerts], which is what makes this usable
/// inside a list row at all: one map probe, no allocation, no future. Like
/// every other facade here an unconfigured read is silent — a surface that
/// lives above the calendar's service resolution simply draws no badge, which
/// is why nothing but the day panel and the agenda use this.
///
/// The trailing strip is at capacity and the grid cell has no room for a
/// marker; the title line is the one place left where this fits.
class EventAlertBadges extends StatelessWidget {
  final CalendarEvent event;

  /// Gap between the title (or the description badge) and the first glyph.
  static const double _gap = 6;

  static const double _size = 14;

  const EventAlertBadges({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final hasAlarm = EventAlerts.hasAlarm(event.id);
    final hasReminder = EventAlerts.hasReminder(event.id);
    if (!hasAlarm && !hasReminder) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasAlarm) ...[
          const SizedBox(width: _gap),
          Tooltip(
            message: _describe(l10n, AlertMode.ring),
            child: Icon(
              Icons.alarm_rounded,
              size: _size,
              color: colorScheme.primary,
            ),
          ),
        ],
        if (hasReminder) ...[
          const SizedBox(width: _gap),
          Tooltip(
            message: _describe(l10n, AlertMode.notify),
            child: Icon(
              Icons.notifications_active_rounded,
              size: _size,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Every enabled alert of one tier, in the one formatter. Joined with the
  /// same separator the subtitles use, so an event with two alarms reads as
  /// one sentence rather than as a badge that names only the first.
  String _describe(AppLocalizations l10n, AlertMode mode) {
    final parts = <String>[
      for (final alert in EventAlerts.alertsFor(event.id))
        if (alert.enabled && alert.mode == mode) alert.describe(l10n, event),
    ];
    return parts.join(' · ');
  }
}
