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

  /// Archived. Hidden categories are dropped from the pickers and the filter
  /// surfaces (`CalendarCategories.visible`) but stay in
  /// `CalendarCategories.all`, so events already carrying one still resolve
  /// to it and keep their own colour. Built-ins can be hidden; they still
  /// cannot be deleted. Defaults to `false` — the flag is additive, and
  /// hiding is the exceptional state.
  final bool isHidden;

  /// Another account's own category, which it shares with this one
  /// (`docs/cloud-share-surfaces-roadmap.md` §6.1): stored under the
  /// partner's `owner_id` and read-only here, so it draws the partner's
  /// events but is never chosen, edited or exported. Transient — set where
  /// `CategoryService` loads its rows, never stored, never written out. A
  /// built-in the partner shares is never one: its events resolve to this
  /// person's own row of the same id.
  final bool fromPartner;

  const CalendarCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.sortOrder,
    required this.isBuiltIn,
    this.isHidden = false,
    this.fromPartner = false,
  });

  Color get color => Color(colorValue);

  CalendarCategory copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    int? sortOrder,
    bool? isHidden,
  }) {
    return CalendarCategory(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      isBuiltIn: isBuiltIn,
      isHidden: isHidden ?? this.isHidden,
      fromPartner: fromPartner,
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
    isHidden,
    fromPartner,
  ];
}
