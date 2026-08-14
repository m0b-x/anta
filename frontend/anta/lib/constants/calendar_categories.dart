import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import 'calendar_icons.dart';

/// Definition of a seeded built-in category.
class BuiltInCategorySeed {
  final CalendarEventCategory kind;
  final String iconKey;
  final int colorValue;

  const BuiltInCategorySeed(this.kind, this.iconKey, this.colorValue);

  /// Stable id == enum name, which matches the value already stored in
  /// `calendar_events.category` for existing events.
  String get id => kind.name;
}

/// Synchronous, in-memory facade over the persisted category set, populated
/// by `CategoryService` at startup. Mirrors the `PublicHolidays` pattern so
/// calendar render paths (`markerBuilder`, day summary, pickers) resolve a
/// category in O(1) with no `await` and no per-build allocation.
abstract final class CalendarCategories {
  /// Built-in seed catalog. Order defines the default sort order (0..N) so
  /// built-ins lead the list ahead of user-created categories. Colors mirror
  /// the historical `CalendarColors` palette; every icon key must exist in
  /// [CalendarIcons].
  static const List<BuiltInCategorySeed> builtInSeeds = [
    BuiltInCategorySeed(
      CalendarEventCategory.gym,
      'fitness_center',
      0xFF1E88E5,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.cardio,
      'directions_run',
      0xFFE53935,
    ),
    BuiltInCategorySeed(CalendarEventCategory.rest, 'bedtime', 0xFF43A047),
    BuiltInCategorySeed(
      CalendarEventCategory.holiday,
      'flight_takeoff',
      0xFFFFA000,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.competition,
      'emoji_events',
      0xFF8E24AA,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.measurement,
      'straighten',
      0xFF00897B,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.mobility,
      'self_improvement',
      0xFFEC407A,
    ),
    BuiltInCategorySeed(CalendarEventCategory.birthday, 'cake', 0xFFD81B60),
    BuiltInCategorySeed(CalendarEventCategory.other, 'event', 0xFF757575),
  ];

  static Map<String, CalendarCategory> _byId = const {};
  static List<CalendarCategory> _ordered = const [];

  /// Fallback for an event whose stored id no longer resolves (e.g. its
  /// custom category was deleted). Keeps render paths total.
  static const CalendarCategory fallback = CalendarCategory(
    id: 'other',
    name: 'Other',
    colorValue: 0xFF757575,
    iconKey: 'event',
    sortOrder: 1 << 20,
    isBuiltIn: true,
  );

  /// Replaces the cache. Called by `CategoryService` after every load/mutation.
  static void updateCache(List<CalendarCategory> categories) {
    final sorted = [...categories]..sort(_byOrder);
    _ordered = List.unmodifiable(sorted);
    _byId = Map.unmodifiable({for (final c in sorted) c.id: c});
  }

  static int _byOrder(CalendarCategory a, CalendarCategory b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  }

  /// All categories in display order.
  static List<CalendarCategory> get all => _ordered;

  /// O(1) lookup; null when unknown.
  static CalendarCategory? byId(String id) => _byId[id];

  /// O(1) lookup that always yields a usable category ([fallback] when the
  /// id is unknown).
  static CalendarCategory resolve(String id) => _byId[id] ?? fallback;

  /// Resolves the display icon for [event]: an explicit per-event override
  /// wins, otherwise the event's category icon, otherwise a safe default.
  static IconData iconFor(CalendarEvent event) {
    final override = CalendarIcons.forKey(event.iconKey);
    if (override != null) return override;
    final category = resolve(event.categoryId);
    return CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
  }

  /// Localized label: built-ins resolve via their stable id; customs show
  /// their stored [CalendarCategory.name] verbatim.
  static String labelOf(CalendarCategory category, AppLocalizations l10n) {
    if (category.isBuiltIn) {
      final builtIn = _builtInById[category.id];
      if (builtIn != null) return builtInLabel(builtIn, l10n);
    }
    return category.name;
  }

  static final Map<String, CalendarEventCategory> _builtInById = {
    for (final c in CalendarEventCategory.values) c.name: c,
  };

  static String builtInLabel(CalendarEventCategory c, AppLocalizations l10n) {
    return switch (c) {
      CalendarEventCategory.gym => l10n.eventCategoryGym,
      CalendarEventCategory.cardio => l10n.eventCategoryCardio,
      CalendarEventCategory.rest => l10n.eventCategoryRest,
      CalendarEventCategory.holiday => l10n.eventCategoryHoliday,
      CalendarEventCategory.competition => l10n.eventCategoryCompetition,
      CalendarEventCategory.measurement => l10n.eventCategoryMeasurement,
      CalendarEventCategory.mobility => l10n.eventCategoryMobility,
      CalendarEventCategory.birthday => l10n.eventCategoryBirthday,
      CalendarEventCategory.other => l10n.eventCategoryOther,
    };
  }

  /// English fallback name persisted in a built-in row's `name` column. The
  /// UI never shows this directly — it uses [labelOf] — but it keeps the row
  /// self-describing in backups and raw DB inspection.
  static String builtInSeedName(CalendarEventCategory c) {
    return switch (c) {
      CalendarEventCategory.gym => 'Gym',
      CalendarEventCategory.cardio => 'Cardio',
      CalendarEventCategory.rest => 'Rest',
      CalendarEventCategory.holiday => 'Holiday',
      CalendarEventCategory.competition => 'Competition',
      CalendarEventCategory.measurement => 'Measurement',
      CalendarEventCategory.mobility => 'Mobility',
      CalendarEventCategory.birthday => 'Birthday',
      CalendarEventCategory.other => 'Other',
    };
  }
}
