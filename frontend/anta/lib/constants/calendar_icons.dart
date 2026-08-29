import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;

/// Identifier for an icon group rendered as a section in the icon picker.
/// Add a value here, append a group to [CalendarIcons.groups] and add a case
/// to [CalendarIcons.groupLabel] — the `switch` is sealed over the enum, so
/// the compiler enumerates any label you forget.
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

/// One icon in the catalog: its stable persisted [key], the [icon] it renders
/// as, and the English [keywords] it can be searched by.
class CalendarIconEntry {
  final String key;
  final IconData icon;

  /// Match-only search terms. Never rendered — see the l10n note on
  /// [CalendarIcons].
  final List<String> keywords;

  const CalendarIconEntry(this.key, this.icon, this.keywords);
}

class IconGroup {
  final IconGroupId id;
  final List<CalendarIconEntry> entries;

  const IconGroup(this.id, this.entries);
}

/// Centralized icon palette for calendar events.
///
/// Icons are addressed by stable string keys to keep model serialization
/// trivial (and to avoid storing raw [IconData] code points, which are
/// tree-shaken away unless explicitly opted out).
///
/// [groups] is the **single source** for the catalog: the key→entry lookup,
/// the key→group map and the search index are all derived from it once, on
/// first touch. Listing a key in two places is what lets the two lists drift.
///
/// To add a new icon: append a [CalendarIconEntry] to the right group, with at
/// least one keyword.
///
/// > **Hard rule — additive only.** Icon keys are persisted in four places:
/// > `calendar_categories.icon_key`, `calendar_events.icon_key`,
/// > `calendar_event_templates` and the fasting appearance settings. **Never
/// > rename or delete a key that has shipped.** To retire an icon, drop its
/// > entry from [groups] but keep the key resolvable — otherwise every row
/// > holding it silently loses its icon.
///
/// **Localization exception, deliberate and documented.** [keywords] are
/// English and live in code rather than the ARB files. They are match-only —
/// never rendered — so the `AppLocalizations` rule, which exists for text the
/// user reads, does not reach them; three locales across a catalog this size
/// would be a thousand ARB entries nobody ever sees. Per-locale reachability
/// comes from the **group labels**, which are localized ([groupLabel]) and
/// join the searchable fields: a German user typing `Ernährung` still lands on
/// the nutrition section.
abstract final class CalendarIcons {
  /// Ordered grouping used by the icon picker UI, and the one catalog.
  static const List<IconGroup> groups = [
    IconGroup(IconGroupId.strength, [
      CalendarIconEntry('fitness_center', Icons.fitness_center_rounded, [
        'gym',
        'weights',
        'dumbbell',
        'lifting',
        'strength',
        'barbell',
      ]),
      CalendarIconEntry('sports_gymnastics', Icons.sports_gymnastics_rounded, [
        'gymnastics',
        'stretch',
        'tumbling',
        'acrobatics',
        'flexibility',
      ]),
      CalendarIconEntry(
        'sports_martial_arts',
        Icons.sports_martial_arts_rounded,
        [
          'martial arts',
          'karate',
          'judo',
          'boxing',
          'kickboxing',
          'taekwondo',
          'mma',
        ],
      ),
      CalendarIconEntry('sports_handball', Icons.sports_handball_rounded, [
        'handball',
        'throw',
        'ball',
        'team',
      ]),
      CalendarIconEntry('self_improvement', Icons.self_improvement_rounded, [
        'yoga',
        'meditation',
        'mindfulness',
        'breathing',
        'mobility',
        'zen',
      ]),
      CalendarIconEntry('accessibility_new', Icons.accessibility_new_rounded, [
        'body',
        'posture',
        'person',
        'stretch',
        'accessibility',
      ]),
    ]),
    IconGroup(IconGroupId.cardio, [
      CalendarIconEntry('directions_run', Icons.directions_run_rounded, [
        'run',
        'running',
        'jog',
        'sprint',
        'cardio',
        'marathon',
        'race',
      ]),
      CalendarIconEntry('directions_bike', Icons.directions_bike_rounded, [
        'bike',
        'cycling',
        'bicycle',
        'ride',
        'cardio',
        'spin',
      ]),
      CalendarIconEntry('directions_walk', Icons.directions_walk_rounded, [
        'walk',
        'walking',
        'steps',
        'stroll',
      ]),
      CalendarIconEntry('pool', Icons.pool_rounded, [
        'swim',
        'swimming',
        'pool',
        'water',
        'laps',
      ]),
      CalendarIconEntry('hiking', Icons.hiking_rounded, [
        'hike',
        'hiking',
        'trail',
        'trek',
        'mountain',
        'walk',
      ]),
      CalendarIconEntry('rowing', Icons.rowing_rounded, [
        'row',
        'rowing',
        'kayak',
        'canoe',
        'boat',
        'paddle',
      ]),
      CalendarIconEntry('downhill_skiing', Icons.downhill_skiing_rounded, [
        'ski',
        'skiing',
        'snow',
        'slope',
        'winter',
        'alpine',
      ]),
      CalendarIconEntry('snowboarding', Icons.snowboarding_rounded, [
        'snowboard',
        'snow',
        'winter',
        'slope',
        'board',
      ]),
    ]),
    IconGroup(IconGroupId.sports, [
      CalendarIconEntry('sports_basketball', Icons.sports_basketball_rounded, [
        'basketball',
        'hoops',
        'ball',
        'court',
      ]),
      CalendarIconEntry('sports_soccer', Icons.sports_soccer_rounded, [
        'soccer',
        'football',
        'ball',
        'pitch',
        'goal',
      ]),
      CalendarIconEntry('sports_tennis', Icons.sports_tennis_rounded, [
        'tennis',
        'racket',
        'court',
        'serve',
        'padel',
      ]),
      CalendarIconEntry('sports_volleyball', Icons.sports_volleyball_rounded, [
        'volleyball',
        'ball',
        'net',
        'beach',
      ]),
      CalendarIconEntry('sports_baseball', Icons.sports_baseball_rounded, [
        'baseball',
        'softball',
        'bat',
        'pitch',
        'ball',
      ]),
      CalendarIconEntry('sports_football', Icons.sports_football_rounded, [
        'american football',
        'rugby',
        'ball',
        'gridiron',
      ]),
      CalendarIconEntry('sports_golf', Icons.sports_golf_rounded, [
        'golf',
        'putt',
        'course',
        'tee',
        'club',
      ]),
      CalendarIconEntry('sports_hockey', Icons.sports_hockey_rounded, [
        'hockey',
        'ice',
        'puck',
        'stick',
        'skate',
      ]),
      CalendarIconEntry('sports_cricket', Icons.sports_cricket_rounded, [
        'cricket',
        'bat',
        'wicket',
        'ball',
      ]),
      CalendarIconEntry('sports_esports', Icons.sports_esports_rounded, [
        'esports',
        'gaming',
        'video game',
        'controller',
        'console',
      ]),
    ]),
    IconGroup(IconGroupId.recovery, [
      CalendarIconEntry('bedtime', Icons.bedtime_rounded, [
        'sleep',
        'bed',
        'rest',
        'night',
        'moon',
        'recovery',
      ]),
      CalendarIconEntry('hotel', Icons.hotel_rounded, [
        'hotel',
        'bed',
        'stay',
        'rest',
        'lodging',
        'room',
      ]),
      CalendarIconEntry('spa', Icons.spa_rounded, [
        'spa',
        'relax',
        'massage',
        'wellness',
        'recovery',
        'calm',
      ]),
      CalendarIconEntry('bathtub', Icons.bathtub_rounded, [
        'bath',
        'tub',
        'soak',
        'shower',
        'relax',
        'recovery',
      ]),
      CalendarIconEntry('weekend', Icons.weekend_rounded, [
        'weekend',
        'sofa',
        'couch',
        'rest',
        'lounge',
        'relax',
      ]),
    ]),
    IconGroup(IconGroupId.body, [
      CalendarIconEntry('monitor_heart', Icons.monitor_heart_rounded, [
        'heart rate',
        'pulse',
        'ecg',
        'monitor',
        'health',
        'vitals',
      ]),
      CalendarIconEntry('favorite', Icons.favorite_rounded, [
        'heart',
        'love',
        'favorite',
        'like',
        'health',
      ]),
      CalendarIconEntry('water_drop', Icons.water_drop_rounded, [
        'water',
        'hydration',
        'drink',
        'drop',
        'fluid',
      ]),
      CalendarIconEntry('restaurant', Icons.restaurant_rounded, [
        'food',
        'meal',
        'eat',
        'restaurant',
        'dinner',
        'cutlery',
      ]),
      CalendarIconEntry('local_dining', Icons.local_dining_rounded, [
        'dining',
        'meal',
        'eat',
        'food',
        'lunch',
        'cutlery',
      ]),
      CalendarIconEntry('fastfood', Icons.fastfood_rounded, [
        'fast food',
        'burger',
        'junk',
        'snack',
        'takeaway',
      ]),
      CalendarIconEntry('local_cafe', Icons.local_cafe_rounded, [
        'coffee',
        'cafe',
        'tea',
        'drink',
        'espresso',
        'cup',
      ]),
      CalendarIconEntry('no_food', Icons.no_food_rounded, [
        'fasting',
        'no food',
        'skip meal',
        'diet',
        'abstain',
      ]),
    ]),
    IconGroup(IconGroupId.measurement, [
      CalendarIconEntry('straighten', Icons.straighten_rounded, [
        'measure',
        'ruler',
        'tape',
        'length',
        'size',
        'measurement',
      ]),
      CalendarIconEntry('monitor_weight', Icons.monitor_weight_rounded, [
        'weight',
        'scale',
        'bodyweight',
        'mass',
        'kilograms',
        'pounds',
      ]),
      CalendarIconEntry('science', Icons.science_rounded, [
        'science',
        'lab',
        'test',
        'experiment',
        'flask',
        'analysis',
      ]),
    ]),
    IconGroup(IconGroupId.achievements, [
      CalendarIconEntry('emoji_events', Icons.emoji_events_rounded, [
        'trophy',
        'award',
        'win',
        'competition',
        'champion',
        'prize',
      ]),
      CalendarIconEntry('military_tech', Icons.military_tech_rounded, [
        'medal',
        'award',
        'rank',
        'honor',
        'badge',
      ]),
      CalendarIconEntry('workspace_premium', Icons.workspace_premium_rounded, [
        'premium',
        'badge',
        'certificate',
        'quality',
        'award',
      ]),
      CalendarIconEntry('flag', Icons.flag_rounded, [
        'flag',
        'goal',
        'milestone',
        'target',
        'finish',
      ]),
      CalendarIconEntry('star', Icons.star_rounded, [
        'star',
        'favorite',
        'rating',
        'highlight',
        'important',
      ]),
      CalendarIconEntry('celebration', Icons.celebration_rounded, [
        'celebration',
        'party',
        'confetti',
        'congrats',
        'festive',
      ]),
      CalendarIconEntry('cake', Icons.cake_rounded, [
        'birthday',
        'cake',
        'anniversary',
        'celebration',
        'party',
      ]),
    ]),
    IconGroup(IconGroupId.travel, [
      CalendarIconEntry('flight_takeoff', Icons.flight_takeoff_rounded, [
        'flight',
        'plane',
        'travel',
        'airport',
        'vacation',
        'trip',
        'takeoff',
      ]),
      CalendarIconEntry('beach_access', Icons.beach_access_rounded, [
        'beach',
        'umbrella',
        'holiday',
        'vacation',
        'sea',
        'summer',
      ]),
      CalendarIconEntry('terrain', Icons.terrain_rounded, [
        'terrain',
        'mountain',
        'hills',
        'outdoors',
        'landscape',
        'nature',
      ]),
    ]),
    IconGroup(IconGroupId.time, [
      CalendarIconEntry('schedule', Icons.schedule_rounded, [
        'clock',
        'time',
        'schedule',
        'hour',
        'duration',
      ]),
      CalendarIconEntry('alarm', Icons.alarm_rounded, [
        'alarm',
        'reminder',
        'wake',
        'clock',
        'ring',
      ]),
      CalendarIconEntry('today', Icons.today_rounded, [
        'today',
        'date',
        'day',
        'calendar',
      ]),
      CalendarIconEntry('event', Icons.event_rounded, [
        'event',
        'calendar',
        'date',
        'appointment',
      ]),
      CalendarIconEntry('event_note', Icons.event_note_rounded, [
        'event note',
        'agenda',
        'calendar note',
        'memo',
      ]),
      CalendarIconEntry('event_available', Icons.event_available_rounded, [
        'available',
        'confirmed',
        'booked',
        'calendar check',
        'done',
      ]),
      CalendarIconEntry('event_busy', Icons.event_busy_rounded, [
        'busy',
        'cancelled',
        'blocked',
        'calendar cross',
        'unavailable',
      ]),
    ]),
    IconGroup(IconGroupId.generic, [
      CalendarIconEntry('note', Icons.note_rounded, [
        'note',
        'memo',
        'text',
        'write',
        'paper',
      ]),
      CalendarIconEntry('lightbulb', Icons.lightbulb_rounded, [
        'idea',
        'lightbulb',
        'tip',
        'insight',
        'inspiration',
      ]),
      CalendarIconEntry('bolt', Icons.bolt_rounded, [
        'bolt',
        'energy',
        'power',
        'fast',
        'lightning',
        'boost',
      ]),
      CalendarIconEntry(
        'local_fire_department',
        Icons.local_fire_department_rounded,
        ['fire', 'flame', 'streak', 'burn', 'hot', 'calories'],
      ),
      CalendarIconEntry('psychology', Icons.psychology_rounded, [
        'brain',
        'mind',
        'psychology',
        'therapy',
        'mental',
        'focus',
      ]),
      CalendarIconEntry('mood', Icons.mood_rounded, [
        'mood',
        'smile',
        'happy',
        'feeling',
        'emoji',
      ]),
      CalendarIconEntry('attach_money', Icons.attach_money_rounded, [
        'money',
        'cash',
        'dollar',
        'payment',
        'cost',
        'price',
      ]),
    ]),
  ];

  /// Derived once on first touch, never per call: [forKey] runs on render
  /// paths (`CalendarCategories.iconFor` feeds `day_summary_resolver.dart` and
  /// `agenda_list_view.dart`), so it has to stay an O(1) map read.
  static final Map<String, CalendarIconEntry> _byKey = {
    for (final group in groups)
      for (final entry in group.entries) entry.key: entry,
  };

  static final Map<String, IconGroupId> _groupByKey = {
    for (final group in groups)
      for (final entry in group.entries) entry.key: group.id,
  };

  /// Folded search text per key: the key with `_` read as spaces, plus every
  /// keyword. Built once so a keystroke is a `contains` over prebuilt strings
  /// rather than a fold of the whole catalog — which is what keeps the picker's
  /// filter synchronous and undebounced.
  static final Map<String, String> _searchTextByKey = {
    for (final group in groups)
      for (final entry in group.entries)
        entry.key: normalizeForSearch(
          '${entry.key.replaceAll('_', ' ')} ${entry.keywords.join(' ')}',
        ),
  };

  /// Returns the icon for [key], or `null` if the key is unknown / `null`.
  static IconData? forKey(String? key) {
    if (key == null) return null;
    return _byKey[key]?.icon;
  }

  /// The full catalog entry for [key], or `null` when unknown / `null`.
  static CalendarIconEntry? entryFor(String? key) {
    if (key == null) return null;
    return _byKey[key];
  }

  /// The group [key] belongs to, or `null` when unknown.
  static IconGroupId? groupIdOf(String? key) {
    if (key == null) return null;
    return _groupByKey[key];
  }

  /// The prebuilt, already-folded search text for [key] — pass it to
  /// `matchesSettingsQuery(..., preFolded: true)`. Empty for an unknown key.
  static String searchTextOf(String? key) {
    if (key == null) return '';
    return _searchTextByKey[key] ?? '';
  }

  /// Localized section label. Sealed over [IconGroupId], so adding a group
  /// without a label is a compile error rather than a blank heading.
  static String groupLabel(IconGroupId id, AppLocalizations l10n) {
    return switch (id) {
      IconGroupId.strength => l10n.iconGroupStrength,
      IconGroupId.cardio => l10n.iconGroupCardio,
      IconGroupId.sports => l10n.iconGroupSports,
      IconGroupId.recovery => l10n.iconGroupRecovery,
      IconGroupId.body => l10n.iconGroupBody,
      IconGroupId.measurement => l10n.iconGroupMeasurement,
      IconGroupId.achievements => l10n.iconGroupAchievements,
      IconGroupId.travel => l10n.iconGroupTravel,
      IconGroupId.time => l10n.iconGroupTime,
      IconGroupId.generic => l10n.iconGroupGeneric,
    };
  }
}
