import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show Color;

/// A calendar event category.
///
/// Categories are data-driven (persisted in the `calendar_categories` table)
/// so users can create their own in addition to the seeded built-ins.
///
/// Built-in categories carry a stable string [id] equal to the historical
/// `CalendarEventCategory` enum name (e.g. `'gym'`) — which is exactly the
/// value already stored in `calendar_events.category`. Seeding built-ins with
/// those ids means existing events link to them with **no data migration**.
/// A built-in's [name] is only an English fallback; its localized label is
/// resolved by id at render time (see `CalendarCategories.labelOf`). Custom
/// categories carry a UUID [id] and a user-entered [name] shown verbatim.
class CalendarCategory extends Equatable {
  final String id;
  final String name;

  /// 32-bit ARGB color value (stored as an int so it round-trips through
  /// SQLite and backup without any platform `Color` dependency).
  final int colorValue;

  /// Key into `CalendarIcons` palette.
  final String iconKey;

  /// Display order. Built-ins seed at 0..N; customs append after.
  final int sortOrder;

  /// Built-ins cannot be deleted and use a localized label; customs are
  /// fully user-editable and shown by their stored [name].
  final bool isBuiltIn;

  const CalendarCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.sortOrder,
    required this.isBuiltIn,
  });

  Color get color => Color(colorValue);

  CalendarCategory copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    int? sortOrder,
  }) {
    return CalendarCategory(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      isBuiltIn: isBuiltIn,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    colorValue,
    iconKey,
    sortOrder,
    isBuiltIn,
  ];
}
