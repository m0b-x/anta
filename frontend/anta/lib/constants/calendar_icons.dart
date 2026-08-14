import 'package:flutter/material.dart';

/// Identifier for an icon group rendered as a section in the icon picker.
/// Add a value here, append it to [CalendarIcons.groups] and add a label
/// case in `IconPickerSheet` to introduce a new section.
enum IconGroupId {
  strength,
  cardio,
  sports,
  recovery,
  body,
  measurement,
  achievements,
  travel,
  time,
  generic,
}

class IconGroup {
  final IconGroupId id;
  final List<String> iconKeys;

  const IconGroup(this.id, this.iconKeys);
}

/// Centralized icon palette for calendar events.
///
/// Icons are addressed by stable string keys to keep model serialization
/// trivial (and to avoid storing raw [IconData] code points, which are
/// tree-shaken away unless explicitly opted out).
///
/// To add a new icon:
///   1. Map a stable key → [IconData] in [_byKey].
///   2. Append the key to the appropriate group in [groups].
abstract final class CalendarIcons {
  static const Map<String, IconData> _byKey = {
    // Strength / gym
    'fitness_center': Icons.fitness_center_rounded,
    'sports_gymnastics': Icons.sports_gymnastics_rounded,
    'sports_martial_arts': Icons.sports_martial_arts_rounded,
    'sports_handball': Icons.sports_handball_rounded,
    'self_improvement': Icons.self_improvement_rounded,
    'accessibility_new': Icons.accessibility_new_rounded,
    // Cardio
    'directions_run': Icons.directions_run_rounded,
    'directions_bike': Icons.directions_bike_rounded,
    'directions_walk': Icons.directions_walk_rounded,
    'pool': Icons.pool_rounded,
    'hiking': Icons.hiking_rounded,
    'rowing': Icons.rowing_rounded,
    'downhill_skiing': Icons.downhill_skiing_rounded,
    'snowboarding': Icons.snowboarding_rounded,
    // Team / racket sports
    'sports_basketball': Icons.sports_basketball_rounded,
    'sports_soccer': Icons.sports_soccer_rounded,
    'sports_tennis': Icons.sports_tennis_rounded,
    'sports_volleyball': Icons.sports_volleyball_rounded,
    'sports_baseball': Icons.sports_baseball_rounded,
    'sports_football': Icons.sports_football_rounded,
    'sports_golf': Icons.sports_golf_rounded,
    'sports_hockey': Icons.sports_hockey_rounded,
    'sports_cricket': Icons.sports_cricket_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    // Recovery / rest
    'bedtime': Icons.bedtime_rounded,
    'hotel': Icons.hotel_rounded,
    'spa': Icons.spa_rounded,
    'bathtub': Icons.bathtub_rounded,
    'weekend': Icons.weekend_rounded,
    // Body / nutrition
    'monitor_heart': Icons.monitor_heart_rounded,
    'favorite': Icons.favorite_rounded,
    'water_drop': Icons.water_drop_rounded,
    'restaurant': Icons.restaurant_rounded,
    'local_dining': Icons.local_dining_rounded,
    'fastfood': Icons.fastfood_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'no_food': Icons.no_food_rounded,
    // Measurement
    'straighten': Icons.straighten_rounded,
    'monitor_weight': Icons.monitor_weight_rounded,
    'science': Icons.science_rounded,
    // Achievements
    'emoji_events': Icons.emoji_events_rounded,
    'military_tech': Icons.military_tech_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'flag': Icons.flag_rounded,
    'star': Icons.star_rounded,
    'celebration': Icons.celebration_rounded,
    'cake': Icons.cake_rounded,
    // Travel
    'flight_takeoff': Icons.flight_takeoff_rounded,
    'beach_access': Icons.beach_access_rounded,
    'terrain': Icons.terrain_rounded,
    // Time / schedule
    'schedule': Icons.schedule_rounded,
    'alarm': Icons.alarm_rounded,
    'today': Icons.today_rounded,
    'event': Icons.event_rounded,
    'event_note': Icons.event_note_rounded,
    'event_available': Icons.event_available_rounded,
    'event_busy': Icons.event_busy_rounded,
    // Generic
    'note': Icons.note_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    'bolt': Icons.bolt_rounded,
    'local_fire_department': Icons.local_fire_department_rounded,
    'psychology': Icons.psychology_rounded,
    'mood': Icons.mood_rounded,
    'attach_money': Icons.attach_money_rounded,
  };

  /// Ordered grouping used by the icon picker UI.
  static const List<IconGroup> groups = [
    IconGroup(IconGroupId.strength, [
      'fitness_center',
      'sports_gymnastics',
      'sports_martial_arts',
      'sports_handball',
      'self_improvement',
      'accessibility_new',
    ]),
    IconGroup(IconGroupId.cardio, [
      'directions_run',
      'directions_bike',
      'directions_walk',
      'pool',
      'hiking',
      'rowing',
      'downhill_skiing',
      'snowboarding',
    ]),
    IconGroup(IconGroupId.sports, [
      'sports_basketball',
      'sports_soccer',
      'sports_tennis',
      'sports_volleyball',
      'sports_baseball',
      'sports_football',
      'sports_golf',
      'sports_hockey',
      'sports_cricket',
      'sports_esports',
    ]),
    IconGroup(IconGroupId.recovery, [
      'bedtime',
      'hotel',
      'spa',
      'bathtub',
      'weekend',
    ]),
    IconGroup(IconGroupId.body, [
      'monitor_heart',
      'favorite',
      'water_drop',
      'restaurant',
      'local_dining',
      'fastfood',
      'local_cafe',
      'no_food',
    ]),
    IconGroup(IconGroupId.measurement, [
      'straighten',
      'monitor_weight',
      'science',
    ]),
    IconGroup(IconGroupId.achievements, [
      'emoji_events',
      'military_tech',
      'workspace_premium',
      'flag',
      'star',
      'celebration',
      'cake',
    ]),
    IconGroup(IconGroupId.travel, [
      'flight_takeoff',
      'beach_access',
      'terrain',
    ]),
    IconGroup(IconGroupId.time, [
      'schedule',
      'alarm',
      'today',
      'event',
      'event_note',
      'event_available',
      'event_busy',
    ]),
    IconGroup(IconGroupId.generic, [
      'note',
      'lightbulb',
      'bolt',
      'local_fire_department',
      'psychology',
      'mood',
      'attach_money',
    ]),
  ];

  /// Returns the icon for [key], or `null` if the key is unknown / `null`.
  static IconData? forKey(String? key) {
    if (key == null) return null;
    return _byKey[key];
  }
}
