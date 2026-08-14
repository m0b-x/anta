import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';

/// Display mapping for event priorities.
///
/// Priorities read like P1..P5: **1 is the highest**, 5 the lowest,
/// [kDefaultEventPriority] (3) the neutral middle. The single home for the
/// icon and label of each level, used by the event editor's picker, the
/// agenda's filter chips and the agenda row badges — so the scale can never
/// read differently on two surfaces.
abstract final class EventPriorities {
  static IconData iconFor(int priority) {
    return switch (priority.clamp(kMinEventPriority, kMaxEventPriority)) {
      1 => Icons.keyboard_double_arrow_up_rounded,
      2 => Icons.keyboard_arrow_up_rounded,
      4 => Icons.keyboard_arrow_down_rounded,
      5 => Icons.keyboard_double_arrow_down_rounded,
      _ => Icons.drag_handle_rounded,
    };
  }

  static String labelOf(int priority, AppLocalizations l10n) {
    return switch (priority.clamp(kMinEventPriority, kMaxEventPriority)) {
      1 => l10n.eventPriorityHighest,
      2 => l10n.eventPriorityHigh,
      4 => l10n.eventPriorityLow,
      5 => l10n.eventPriorityLowest,
      _ => l10n.eventPriorityNormal,
    };
  }
}
