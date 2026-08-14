import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'calendar_event.dart';

/// A single entry rendered in the calendar's bottom "day summary" panel.
///
/// Entries are produced by `DaySummaryProvider`s. Lower [priority] values
/// float to the top of the list; suggested ranges:
///   *   0..99   events
///   * 100..199  public holiday
///   * 200..299  weekend / contextual
class DaySummaryEntry extends Equatable {
  /// Stable identifier used for deduplication (e.g. `"weekend"`,
  /// `"holiday"`, `"event:<id>"`).
  final String key;

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// Raw markdown description carried by the underlying event, rendered
  /// clamped by the row. Null for entries that have none (and for the
  /// non-event entry types). Never pre-rendered — surfaces build spans on
  /// demand, so nothing derived is stored or persisted.
  final String? description;

  final int priority;

  /// Optional payload for callers that want to act on a tap (e.g. the
  /// event-list entry carries the underlying [CalendarEvent]).
  final CalendarEvent? event;

  const DaySummaryEntry({
    required this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.priority,
    this.subtitle,
    this.description,
    this.event,
  });

  @override
  List<Object?> get props => [
    key,
    icon,
    color,
    title,
    subtitle,
    description,
    priority,
    event,
  ];
}
