import 'package:equatable/equatable.dart';

import 'calendar_event.dart';
import 'recurrence_rule.dart';

/// A reusable event preset: everything an event needs except a date.
///
/// Separate from `CalendarCategory` on purpose — a category is a taxonomy,
/// while a user wants several presets inside one ("Push day" and "Leg day"
/// both under Gym). See `event_templates_table.dart` for the storage
/// rationale.
///
/// [name] doubles as the title stamped onto the created event.
class EventTemplate extends Equatable {
  final String id;
  final String name;
  final String categoryId;
  final RecurrenceRule rule;

  /// Time of day, or `null` for an all-day event — the same derivation
  /// [CalendarEvent.allDay] uses, so a template can never carry an
  /// inconsistent pair.
  final EventTime? time;

  final String? description;

  /// Per-template icon override; `null` uses the category's icon.
  final String? iconKey;

  /// 32-bit ARGB override; `null` uses the category's colour.
  final int? colorValue;

  final bool tintIcon;
  final int priority;
  final bool retroactive;
  final bool countOccurrences;
  final OccurrenceCountStyle countStyle;
  final bool tracksPresence;
  final bool perOccurrenceDescriptions;
  final int sortOrder;

  const EventTemplate({
    required this.id,
    required this.name,
    required this.categoryId,
    this.rule = const OneTimeRecurrence(),
    this.time,
    this.description,
    this.iconKey,
    this.colorValue,
    this.tintIcon = true,
    this.priority = kDefaultEventPriority,
    this.retroactive = false,
    this.countOccurrences = false,
    this.countStyle = OccurrenceCountStyle.numbered,
    this.tracksPresence = false,
    this.perOccurrenceDescriptions = false,
    this.sortOrder = 0,
  });

  /// Stamps out the event this template describes, anchored on [startDate].
  ///
  /// The three flags that only mean anything for a repeating rule
  /// ([retroactive], [tracksPresence], [perOccurrenceDescriptions]) are
  /// cleared for a one-time rule here, matching the editor's own save guards —
  /// a template captured while recurring and later flipped to one-time must
  /// not stamp out an event carrying flags its rule cannot honour.
  CalendarEvent buildEvent({
    required String id,
    required DateTime startDate,
  }) {
    final repeats = rule is! OneTimeRecurrence;
    return CalendarEvent(
      id: id,
      title: name,
      categoryId: categoryId,
      startDate: DateTime.utc(
        startDate.year,
        startDate.month,
        startDate.day,
      ),
      rule: rule,
      iconKey: iconKey,
      time: time,
      description: description,
      colorValue: colorValue,
      tintIcon: tintIcon,
      priority: priority,
      retroactive: repeats && retroactive,
      countOccurrences: repeats && countOccurrences,
      countStyle: countStyle,
      tracksPresence: repeats && tracksPresence,
      perOccurrenceDescriptions: repeats && perOccurrenceDescriptions,
    );
  }

  EventTemplate copyWith({
    String? name,
    String? categoryId,
    RecurrenceRule? rule,
    EventTime? time,
    bool clearTime = false,
    String? description,
    bool clearDescription = false,
    String? iconKey,
    bool clearIconKey = false,
    int? colorValue,
    bool clearColorValue = false,
    bool? tintIcon,
    int? priority,
    bool? retroactive,
    bool? countOccurrences,
    OccurrenceCountStyle? countStyle,
    bool? tracksPresence,
    bool? perOccurrenceDescriptions,
    int? sortOrder,
  }) {
    return EventTemplate(
      id: id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      rule: rule ?? this.rule,
      time: clearTime ? null : (time ?? this.time),
      description: clearDescription ? null : (description ?? this.description),
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
      colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
      tintIcon: tintIcon ?? this.tintIcon,
      priority: priority ?? this.priority,
      retroactive: retroactive ?? this.retroactive,
      countOccurrences: countOccurrences ?? this.countOccurrences,
      countStyle: countStyle ?? this.countStyle,
      tracksPresence: tracksPresence ?? this.tracksPresence,
      perOccurrenceDescriptions:
          perOccurrenceDescriptions ?? this.perOccurrenceDescriptions,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    categoryId,
    rule,
    time,
    description,
    iconKey,
    colorValue,
    tintIcon,
    priority,
    retroactive,
    countOccurrences,
    countStyle,
    tracksPresence,
    perOccurrenceDescriptions,
    sortOrder,
  ];
}
