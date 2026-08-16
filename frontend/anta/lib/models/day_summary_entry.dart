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

  /// Whether the underlying event opts into presence tracking **and** this
  /// day is one it can be marked on (**v26**). Only such rows offer the
  /// present/missed toggle; false for every non-event entry.
  final bool presenceTracked;

  /// Whether this occurrence is currently marked as missed. Meaningful only
  /// when [presenceTracked] is true.
  final bool missed;

  const DaySummaryEntry({
    required this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.priority,
    this.subtitle,
    this.description,
    this.event,
    this.presenceTracked = false,
    this.missed = false,
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
    presenceTracked,
    missed,
  ];
}
