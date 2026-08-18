import 'package:flutter/material.dart';

import '../models/event_template.dart';
import 'calendar_categories.dart';
import 'calendar_icons.dart';

/// Synchronous, in-memory facade over the persisted event templates,
/// populated by `EventTemplateService` at startup.
///
/// The same shape as [CalendarCategories]: the picker sheets and the editor's
/// chip strip read it during build, so it must never require an `await`. The
/// table holds dozens of rows at most, which is why the service loads all of
/// them once instead of querying per use.
abstract final class CalendarTemplates {
  static List<EventTemplate> _ordered = const [];
  static Map<String, EventTemplate> _byId = const {};

  /// Replaces the cache. Called by `EventTemplateService` after every
  /// load/mutation.
  static void updateCache(List<EventTemplate> templates) {
    final sorted = [...templates]..sort(_byOrder);
    _ordered = List.unmodifiable(sorted);
    _byId = Map.unmodifiable({for (final t in sorted) t.id: t});
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: without
  /// this the previous database's templates keep showing after a switch.
  static void resetCache() {
    _ordered = const [];
    _byId = const {};
  }

  static int _byOrder(EventTemplate a, EventTemplate b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  }

  /// All templates in display order.
  static List<EventTemplate> get all => _ordered;

  static bool get isEmpty => _ordered.isEmpty;

  /// O(1) lookup; null when unknown.
  static EventTemplate? byId(String id) => _byId[id];

  /// Display icon for [template]: its own override wins, otherwise the icon
  /// of the category it will stamp out, otherwise a safe default. Mirrors
  /// [CalendarCategories.iconFor] so a template's row and the event it
  /// creates never show different icons.
  static IconData iconFor(EventTemplate template) {
    final override = CalendarIcons.forKey(template.iconKey);
    if (override != null) return override;
    final category = CalendarCategories.resolve(template.categoryId);
    return CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
  }

  /// Display colour for [template], following the day-bar rule: an explicit
  /// override wins, otherwise the category colour.
  static Color colorFor(EventTemplate template) {
    final override = template.colorValue;
    if (override != null) return Color(override);
    return CalendarCategories.resolve(template.categoryId).color;
  }
}
