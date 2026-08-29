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
  work,
  education,
  health,
  home,
  finance,
  foodDrink,
  transport,
  entertainment,
  people,
  nature,
  tech,
  symbols,
  letters,
  digits,
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
    IconGroup(IconGroupId.work, [
      CalendarIconEntry('work', Icons.work_rounded, [
        'work',
        'job',
        'office',
        'briefcase',
        'career',
      ]),
      CalendarIconEntry('groups', Icons.groups_rounded, [
        'team',
        'group',
        'meeting',
        'colleagues',
        'staff',
      ]),
      CalendarIconEntry('handshake', Icons.handshake_rounded, [
        'handshake',
        'deal',
        'agreement',
        'partnership',
        'client',
      ]),
      CalendarIconEntry('business_center', Icons.business_center_rounded, [
        'business',
        'briefcase',
        'corporate',
        'work bag',
      ]),
      CalendarIconEntry('badge', Icons.badge_rounded, [
        'badge',
        'id card',
        'employee',
        'pass',
        'credential',
      ]),
      CalendarIconEntry('phone_in_talk', Icons.phone_in_talk_rounded, [
        'call',
        'phone call',
        'support',
        'hotline',
        'dial',
      ]),
      CalendarIconEntry('co_present', Icons.co_present_rounded, [
        'presentation',
        'present',
        'slides',
        'demo',
        'talk',
      ]),
      CalendarIconEntry('description', Icons.description_rounded, [
        'document',
        'file',
        'report',
        'paperwork',
        'form',
      ]),
      CalendarIconEntry('meeting_room', Icons.meeting_room_rounded, [
        'meeting room',
        'conference',
        'boardroom',
        'booking',
      ]),
    ]),
    IconGroup(IconGroupId.education, [
      CalendarIconEntry('school', Icons.school_rounded, [
        'school',
        'class',
        'lesson',
        'university',
        'course',
      ]),
      CalendarIconEntry('menu_book', Icons.menu_book_rounded, [
        'book',
        'reading',
        'textbook',
        'study',
        'manual',
      ]),
      CalendarIconEntry('history_edu', Icons.history_edu_rounded, [
        'history',
        'scroll',
        'lecture',
        'archive',
        'essay',
      ]),
      CalendarIconEntry('quiz', Icons.quiz_rounded, [
        'quiz',
        'exam',
        'test',
        'question',
        'revision',
      ]),
      CalendarIconEntry('backpack', Icons.backpack_rounded, [
        'backpack',
        'bag',
        'student',
        'rucksack',
        'kit',
      ]),
      CalendarIconEntry('draw', Icons.draw_rounded, [
        'draw',
        'sketch',
        'pencil',
        'handwriting',
        'notes',
      ]),
      CalendarIconEntry('translate', Icons.translate_rounded, [
        'translate',
        'language',
        'vocabulary',
        'dictionary',
        'foreign',
      ]),
    ]),
    IconGroup(IconGroupId.health, [
      CalendarIconEntry('medical_services', Icons.medical_services_rounded, [
        'doctor',
        'medical',
        'clinic',
        'checkup',
        'appointment',
      ]),
      CalendarIconEntry('vaccines', Icons.vaccines_rounded, [
        'vaccine',
        'injection',
        'shot',
        'immunisation',
        'syringe',
      ]),
      CalendarIconEntry('medication', Icons.medication_rounded, [
        'medication',
        'pill',
        'prescription',
        'tablet',
        'dose',
      ]),
      CalendarIconEntry('healing', Icons.healing_rounded, [
        'healing',
        'bandage',
        'injury',
        'first aid',
        'wound',
      ]),
      CalendarIconEntry('local_hospital', Icons.local_hospital_rounded, [
        'hospital',
        'emergency',
        'ward',
        'surgery',
        'admission',
      ]),
      CalendarIconEntry(
        'medical_information',
        Icons.medical_information_rounded,
        ['medical record', 'chart', 'patient notes', 'health file'],
      ),
      CalendarIconEntry('bloodtype', Icons.bloodtype_rounded, [
        'blood',
        'blood test',
        'donation',
        'lab',
        'type',
      ]),
      CalendarIconEntry('hearing', Icons.hearing_rounded, [
        'hearing',
        'ear',
        'audiology',
        'sound',
        'aid',
      ]),
    ]),
    IconGroup(IconGroupId.home, [
      CalendarIconEntry('home', Icons.home_rounded, [
        'home',
        'house',
        'apartment',
        'flat',
        'household',
      ]),
      CalendarIconEntry('cleaning_services', Icons.cleaning_services_rounded, [
        'cleaning',
        'chores',
        'tidy',
        'housework',
        'mop',
      ]),
      CalendarIconEntry(
        'local_laundry_service',
        Icons.local_laundry_service_rounded,
        ['laundry', 'washing', 'clothes', 'machine', 'ironing'],
      ),
      CalendarIconEntry('kitchen', Icons.kitchen_rounded, [
        'kitchen',
        'cooking',
        'appliance',
        'oven',
        'counter',
      ]),
      CalendarIconEntry('chair', Icons.chair_rounded, [
        'chair',
        'furniture',
        'seat',
        'living room',
        'interior',
      ]),
      CalendarIconEntry('yard', Icons.yard_rounded, [
        'garden',
        'yard',
        'lawn',
        'mowing',
        'outdoor',
      ]),
      CalendarIconEntry('plumbing', Icons.plumbing_rounded, [
        'plumbing',
        'pipes',
        'leak',
        'sink',
        'repair',
      ]),
      CalendarIconEntry('handyman', Icons.handyman_rounded, [
        'handyman',
        'repair',
        'diy',
        'tools',
        'maintenance',
      ]),
      CalendarIconEntry('construction', Icons.construction_rounded, [
        'construction',
        'renovation',
        'building',
        'works',
        'site',
      ]),
      CalendarIconEntry('key', Icons.key_rounded, [
        'key',
        'keys',
        'access',
        'rent',
        'landlord',
      ]),
    ]),
    IconGroup(IconGroupId.finance, [
      CalendarIconEntry('payments', Icons.payments_rounded, [
        'payment',
        'pay',
        'bill',
        'invoice',
        'transfer',
      ]),
      CalendarIconEntry('savings', Icons.savings_rounded, [
        'savings',
        'piggy bank',
        'save',
        'deposit',
        'fund',
      ]),
      CalendarIconEntry('account_balance', Icons.account_balance_rounded, [
        'bank',
        'account',
        'balance',
        'institution',
        'finance',
      ]),
      CalendarIconEntry('credit_card', Icons.credit_card_rounded, [
        'card',
        'credit card',
        'debit',
        'bank card',
        'spending',
      ]),
      CalendarIconEntry('receipt_long', Icons.receipt_long_rounded, [
        'receipt',
        'expense',
        'statement',
        'ledger',
        'itemised',
      ]),
      CalendarIconEntry('request_quote', Icons.request_quote_rounded, [
        'quote',
        'estimate',
        'pricing',
        'offer',
        'tender',
      ]),
      CalendarIconEntry('trending_up', Icons.trending_up_rounded, [
        'growth',
        'trend',
        'increase',
        'profit',
        'chart',
      ]),
      CalendarIconEntry('redeem', Icons.redeem_rounded, [
        'gift',
        'reward',
        'voucher',
        'present',
        'bonus',
      ]),
      CalendarIconEntry('shopping_cart', Icons.shopping_cart_rounded, [
        'shopping',
        'cart',
        'groceries',
        'buy',
        'purchase',
      ]),
    ]),
    IconGroup(IconGroupId.foodDrink, [
      CalendarIconEntry('local_pizza', Icons.local_pizza_rounded, [
        'pizza',
        'takeaway',
        'italian',
        'slice',
      ]),
      CalendarIconEntry('lunch_dining', Icons.lunch_dining_rounded, [
        'lunch',
        'sandwich',
        'midday meal',
        'burger',
      ]),
      CalendarIconEntry('breakfast_dining', Icons.breakfast_dining_rounded, [
        'breakfast',
        'croissant',
        'morning meal',
        'pastry',
      ]),
      CalendarIconEntry('ramen_dining', Icons.ramen_dining_rounded, [
        'ramen',
        'noodles',
        'soup',
        'asian',
        'bowl',
      ]),
      CalendarIconEntry('bakery_dining', Icons.bakery_dining_rounded, [
        'bakery',
        'bread',
        'baking',
        'patisserie',
        'buns',
      ]),
      CalendarIconEntry('icecream', Icons.icecream_rounded, [
        'ice cream',
        'dessert',
        'gelato',
        'sweet',
        'cone',
      ]),
      CalendarIconEntry('liquor', Icons.liquor_rounded, [
        'liquor',
        'spirits',
        'bottle',
        'whisky',
        'alcohol',
      ]),
      CalendarIconEntry('local_bar', Icons.local_bar_rounded, [
        'bar',
        'cocktail',
        'drinks',
        'pub',
        'evening out',
      ]),
      CalendarIconEntry('egg', Icons.egg_rounded, [
        'egg',
        'eggs',
        'protein',
        'omelette',
        'boiled',
      ]),
      CalendarIconEntry('set_meal', Icons.set_meal_rounded, [
        'meal',
        'set meal',
        'dinner',
        'plate',
        'course',
      ]),
    ]),
    IconGroup(IconGroupId.transport, [
      CalendarIconEntry('directions_car', Icons.directions_car_rounded, [
        'car',
        'drive',
        'driving',
        'vehicle',
        'road trip',
      ]),
      CalendarIconEntry('directions_bus', Icons.directions_bus_rounded, [
        'bus',
        'coach',
        'public transport',
        'route',
      ]),
      CalendarIconEntry('train', Icons.train_rounded, [
        'train',
        'rail',
        'railway',
        'station',
        'journey',
      ]),
      CalendarIconEntry('tram', Icons.tram_rounded, [
        'tram',
        'streetcar',
        'light rail',
        'city transport',
      ]),
      CalendarIconEntry('local_taxi', Icons.local_taxi_rounded, [
        'taxi',
        'cab',
        'ride',
        'pickup',
        'fare',
      ]),
      CalendarIconEntry('two_wheeler', Icons.two_wheeler_rounded, [
        'motorbike',
        'motorcycle',
        'moped',
        'delivery',
        'courier',
      ]),
      CalendarIconEntry('electric_scooter', Icons.electric_scooter_rounded, [
        'electric scooter',
        'e scooter',
        'kick scooter',
        'micromobility',
      ]),
      CalendarIconEntry('local_gas_station', Icons.local_gas_station_rounded, [
        'fuel',
        'petrol',
        'gas station',
        'refuel',
        'diesel',
      ]),
      CalendarIconEntry('ev_station', Icons.ev_station_rounded, [
        'charging',
        'electric',
        'ev',
        'charge point',
        'plug',
      ]),
      CalendarIconEntry('commute', Icons.commute_rounded, [
        'commute',
        'travel to work',
        'transit',
        'daily journey',
      ]),
      CalendarIconEntry('luggage', Icons.luggage_rounded, [
        'luggage',
        'suitcase',
        'packing',
        'baggage',
        'trip',
      ]),
    ]),
    IconGroup(IconGroupId.entertainment, [
      CalendarIconEntry('movie', Icons.movie_rounded, [
        'movie',
        'film',
        'cinema',
        'screening',
        'watch',
      ]),
      CalendarIconEntry('music_note', Icons.music_note_rounded, [
        'music',
        'song',
        'track',
        'listen',
        'melody',
      ]),
      CalendarIconEntry('headphones', Icons.headphones_rounded, [
        'headphones',
        'podcast',
        'audio',
        'listening',
        'audiobook',
      ]),
      CalendarIconEntry('photo_camera', Icons.photo_camera_rounded, [
        'camera',
        'photo',
        'photography',
        'shoot',
        'picture',
      ]),
      CalendarIconEntry('palette', Icons.palette_rounded, [
        'art',
        'painting',
        'palette',
        'colours',
        'creative',
      ]),
      CalendarIconEntry('brush', Icons.brush_rounded, [
        'brush',
        'paint',
        'drawing',
        'craft',
        'decorating',
      ]),
      CalendarIconEntry('theater_comedy', Icons.theater_comedy_rounded, [
        'theatre',
        'play',
        'show',
        'comedy',
        'performance',
      ]),
      CalendarIconEntry('mic', Icons.mic_rounded, [
        'microphone',
        'singing',
        'karaoke',
        'recording',
        'speech',
      ]),
      CalendarIconEntry('piano', Icons.piano_rounded, [
        'piano',
        'keyboard',
        'practice',
        'instrument',
        'rehearsal',
      ]),
      CalendarIconEntry('tv', Icons.tv_rounded, [
        'tv',
        'television',
        'series',
        'episode',
        'streaming',
      ]),
      CalendarIconEntry('festival', Icons.festival_rounded, [
        'festival',
        'concert',
        'gig',
        'live music',
        'carnival',
      ]),
    ]),
    IconGroup(IconGroupId.people, [
      CalendarIconEntry('people', Icons.people_rounded, [
        'people',
        'friends',
        'social',
        'gathering',
        'together',
      ]),
      CalendarIconEntry(
        'volunteer_activism',
        Icons.volunteer_activism_rounded,
        ['volunteer', 'charity', 'giving', 'help', 'donation'],
      ),
      CalendarIconEntry('church', Icons.church_rounded, [
        'church',
        'mass',
        'chapel',
        'liturgy',
        'worship',
      ]),
      CalendarIconEntry('mosque', Icons.mosque_rounded, [
        'mosque',
        'prayer',
        'islam',
        'worship',
        'friday prayer',
      ]),
      CalendarIconEntry('synagogue', Icons.synagogue_rounded, [
        'synagogue',
        'prayer',
        'judaism',
        'worship',
        'shabbat',
      ]),
      CalendarIconEntry('nightlife', Icons.nightlife_rounded, [
        'nightlife',
        'party',
        'club',
        'night out',
        'evening',
      ]),
      CalendarIconEntry('diversity_3', Icons.diversity_3_rounded, [
        'community',
        'diversity',
        'inclusion',
        'support group',
        'circle',
      ]),
      CalendarIconEntry('child_care', Icons.child_care_rounded, [
        'childcare',
        'kids',
        'baby',
        'nursery',
        'parenting',
      ]),
      CalendarIconEntry('elderly', Icons.elderly_rounded, [
        'elderly',
        'senior',
        'grandparents',
        'care',
        'visit',
      ]),
    ]),
    IconGroup(IconGroupId.nature, [
      // Key `sunny`, icon `wb_sunny_rounded`: the key is the persisted,
      // searchable half and `wb` is a Material prefix nobody types.
      CalendarIconEntry('sunny', Icons.wb_sunny_rounded, [
        'sun',
        'sunny',
        'weather',
        'clear',
        'summer',
      ]),
      CalendarIconEntry('cloud', Icons.cloud_rounded, [
        'cloud',
        'cloudy',
        'overcast',
        'weather',
        'sky',
      ]),
      CalendarIconEntry('ac_unit', Icons.ac_unit_rounded, [
        'cold',
        'snow',
        'winter',
        'air conditioning',
        'freeze',
      ]),
      CalendarIconEntry('umbrella', Icons.umbrella_rounded, [
        'rain',
        'umbrella',
        'wet',
        'weather',
        'shelter',
      ]),
      CalendarIconEntry('park', Icons.park_rounded, [
        'park',
        'green space',
        'outdoors',
        'bench',
        'stroll',
      ]),
      CalendarIconEntry('forest', Icons.forest_rounded, [
        'forest',
        'woods',
        'trees',
        'nature',
        'trail',
      ]),
      CalendarIconEntry('water', Icons.water_rounded, [
        'water',
        'sea',
        'lake',
        'river',
        'waves',
      ]),
      CalendarIconEntry('eco', Icons.eco_rounded, [
        'eco',
        'leaf',
        'green',
        'sustainable',
        'plant',
      ]),
      CalendarIconEntry('thunderstorm', Icons.thunderstorm_rounded, [
        'storm',
        'thunder',
        'lightning',
        'weather',
        'downpour',
      ]),
      CalendarIconEntry('nights_stay', Icons.nights_stay_rounded, [
        'night',
        'moon',
        'evening',
        'overnight',
        'dark',
      ]),
      CalendarIconEntry('pets', Icons.pets_rounded, [
        'pet',
        'dog',
        'cat',
        'animal',
        'vet',
      ]),
      CalendarIconEntry('agriculture', Icons.agriculture_rounded, [
        'farm',
        'agriculture',
        'tractor',
        'harvest',
        'field',
      ]),
    ]),
    IconGroup(IconGroupId.tech, [
      CalendarIconEntry('computer', Icons.computer_rounded, [
        'computer',
        'laptop',
        'desktop',
        'pc',
        'screen',
      ]),
      CalendarIconEntry('phone_android', Icons.phone_android_rounded, [
        'phone',
        'mobile',
        'smartphone',
        'device',
        'android',
      ]),
      CalendarIconEntry('wifi', Icons.wifi_rounded, [
        'wifi',
        'internet',
        'network',
        'connection',
        'router',
      ]),
      CalendarIconEntry('cloud_upload', Icons.cloud_upload_rounded, [
        'upload',
        'backup',
        'sync',
        'cloud',
        'save',
      ]),
      CalendarIconEntry('code', Icons.code_rounded, [
        'code',
        'programming',
        'development',
        'software',
        'coding',
      ]),
      CalendarIconEntry('build', Icons.build_rounded, [
        'build',
        'tools',
        'setup',
        'configure',
        'wrench',
      ]),
      CalendarIconEntry('memory', Icons.memory_rounded, [
        'memory',
        'hardware',
        'chip',
        'ram',
        'processor',
      ]),
      CalendarIconEntry('print', Icons.print_rounded, [
        'print',
        'printer',
        'paper',
        'copy',
        'scan',
      ]),
      CalendarIconEntry('storage', Icons.storage_rounded, [
        'storage',
        'disk',
        'archive',
        'files',
        'space',
      ]),
    ]),
    IconGroup(IconGroupId.symbols, [
      CalendarIconEntry('circle', Icons.circle_rounded, [
        'circle',
        'dot',
        'marker',
        'plain',
        'shape',
      ]),
      CalendarIconEntry('square', Icons.square_rounded, [
        'square',
        'shape',
        'marker',
        'box',
        'tile',
      ]),
      CalendarIconEntry('bookmark', Icons.bookmark_rounded, [
        'bookmark',
        'saved',
        'keep',
        'shortlist',
        'marker',
      ]),
      CalendarIconEntry('label', Icons.label_rounded, [
        'label',
        'tag',
        'category',
        'name',
        'marker',
      ]),
      CalendarIconEntry('priority_high', Icons.priority_high_rounded, [
        'priority',
        'urgent',
        'important',
        'exclamation',
        'alert',
      ]),
      CalendarIconEntry('warning', Icons.warning_rounded, [
        'warning',
        'caution',
        'attention',
        'risk',
        'alert',
      ]),
      CalendarIconEntry('check_circle', Icons.check_circle_rounded, [
        'done',
        'complete',
        'check',
        'finished',
        'tick',
      ]),
      CalendarIconEntry('block', Icons.block_rounded, [
        'blocked',
        'cancelled',
        'forbidden',
        'stop',
        'unavailable',
      ]),
      CalendarIconEntry('lock', Icons.lock_rounded, [
        'lock',
        'locked',
        'private',
        'secure',
        'password',
      ]),
      CalendarIconEntry('shield', Icons.shield_rounded, [
        'shield',
        'protection',
        'security',
        'safety',
        'guard',
      ]),
      CalendarIconEntry('push_pin', Icons.push_pin_rounded, [
        'pin',
        'pinned',
        'fixed',
        'sticky',
        'reminder',
      ]),
    ]),
    // Letters and digits are ordinary catalog entries, not a parallel
    // rendering path. `Icon` paints `String.fromCharCode(icon.codePoint)`
    // styled with `icon.fontFamily`, so an `IconData` carrying **no** font
    // family renders that character in the ambient font — which means every
    // downstream surface, from `DaySummaryEntry.icon` to the day bars, keeps
    // working with no change at all. Verified to survive a release build's
    // `--tree-shake-icons`: the shaker subsets the fonts named by const
    // `IconData` instances, and one naming no font simply is not a candidate.
    //
    // Cosmetic caveat, accepted: a letter sits smaller and lower than a
    // Material glyph at the same `fontSize` and takes the ambient weight.
    IconGroup(IconGroupId.letters, [
      CalendarIconEntry('letter_a', IconData(0x41), ['a', 'letter a']),
      CalendarIconEntry('letter_b', IconData(0x42), ['b', 'letter b']),
      CalendarIconEntry('letter_c', IconData(0x43), ['c', 'letter c']),
      CalendarIconEntry('letter_d', IconData(0x44), ['d', 'letter d']),
      CalendarIconEntry('letter_e', IconData(0x45), ['e', 'letter e']),
      CalendarIconEntry('letter_f', IconData(0x46), ['f', 'letter f']),
      CalendarIconEntry('letter_g', IconData(0x47), ['g', 'letter g']),
      CalendarIconEntry('letter_h', IconData(0x48), ['h', 'letter h']),
      CalendarIconEntry('letter_i', IconData(0x49), ['i', 'letter i']),
      CalendarIconEntry('letter_j', IconData(0x4A), ['j', 'letter j']),
      CalendarIconEntry('letter_k', IconData(0x4B), ['k', 'letter k']),
      CalendarIconEntry('letter_l', IconData(0x4C), ['l', 'letter l']),
      CalendarIconEntry('letter_m', IconData(0x4D), ['m', 'letter m']),
      CalendarIconEntry('letter_n', IconData(0x4E), ['n', 'letter n']),
      CalendarIconEntry('letter_o', IconData(0x4F), ['o', 'letter o']),
      CalendarIconEntry('letter_p', IconData(0x50), ['p', 'letter p']),
      CalendarIconEntry('letter_q', IconData(0x51), ['q', 'letter q']),
      CalendarIconEntry('letter_r', IconData(0x52), ['r', 'letter r']),
      CalendarIconEntry('letter_s', IconData(0x53), ['s', 'letter s']),
      CalendarIconEntry('letter_t', IconData(0x54), ['t', 'letter t']),
      CalendarIconEntry('letter_u', IconData(0x55), ['u', 'letter u']),
      CalendarIconEntry('letter_v', IconData(0x56), ['v', 'letter v']),
      CalendarIconEntry('letter_w', IconData(0x57), ['w', 'letter w']),
      CalendarIconEntry('letter_x', IconData(0x58), ['x', 'letter x']),
      CalendarIconEntry('letter_y', IconData(0x59), ['y', 'letter y']),
      CalendarIconEntry('letter_z', IconData(0x5A), ['z', 'letter z']),
    ]),
    IconGroup(IconGroupId.digits, [
      CalendarIconEntry('digit_0', IconData(0x30), ['0', 'zero', 'digit 0']),
      CalendarIconEntry('digit_1', IconData(0x31), ['1', 'one', 'digit 1']),
      CalendarIconEntry('digit_2', IconData(0x32), ['2', 'two', 'digit 2']),
      CalendarIconEntry('digit_3', IconData(0x33), ['3', 'three', 'digit 3']),
      CalendarIconEntry('digit_4', IconData(0x34), ['4', 'four', 'digit 4']),
      CalendarIconEntry('digit_5', IconData(0x35), ['5', 'five', 'digit 5']),
      CalendarIconEntry('digit_6', IconData(0x36), ['6', 'six', 'digit 6']),
      CalendarIconEntry('digit_7', IconData(0x37), ['7', 'seven', 'digit 7']),
      CalendarIconEntry('digit_8', IconData(0x38), ['8', 'eight', 'digit 8']),
      CalendarIconEntry('digit_9', IconData(0x39), ['9', 'nine', 'digit 9']),
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

  /// The folded terms that *are* an entry, rather than merely appearing in it:
  /// its key read with underscores as spaces, and each keyword whole.
  static final Map<String, Set<String>> _exactTermsByKey = {
    for (final group in groups)
      for (final entry in group.entries)
        entry.key: {
          normalizeForSearch(entry.key.replaceAll('_', ' ')),
          for (final keyword in entry.keywords) normalizeForSearch(keyword),
        },
  };

  /// True when [foldedTerm] *is* one of [key]'s terms rather than a fragment
  /// of one — the signal that outranks every [FuzzyRank] tier.
  ///
  /// [FuzzyRank] scores a prefix of the whole search text, which a
  /// one-character query cannot use: typing `a` puts every entry whose text
  /// begins with "a" (`ac unit`, `alarm`, `attach money`) ahead of the letter
  /// **A**, whose text begins with "letter". An exact term is the strongest
  /// evidence available and costs one set lookup, so it is checked first —
  /// which is also what makes `gym` land on `fitness_center` rather than on
  /// whatever happens to spell "gym" earliest.
  static bool isExactTerm(String? key, String foldedTerm) {
    if (key == null || foldedTerm.isEmpty) return false;
    return _exactTermsByKey[key]?.contains(foldedTerm) ?? false;
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
      IconGroupId.work => l10n.iconGroupWork,
      IconGroupId.education => l10n.iconGroupEducation,
      IconGroupId.health => l10n.iconGroupHealth,
      IconGroupId.home => l10n.iconGroupHome,
      IconGroupId.finance => l10n.iconGroupFinance,
      IconGroupId.foodDrink => l10n.iconGroupFoodDrink,
      IconGroupId.transport => l10n.iconGroupTransport,
      IconGroupId.entertainment => l10n.iconGroupEntertainment,
      IconGroupId.people => l10n.iconGroupPeople,
      IconGroupId.nature => l10n.iconGroupNature,
      IconGroupId.tech => l10n.iconGroupTech,
      IconGroupId.symbols => l10n.iconGroupSymbols,
      IconGroupId.letters => l10n.iconGroupLetters,
      IconGroupId.digits => l10n.iconGroupDigits,
    };
  }
}
