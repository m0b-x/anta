import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/utils/settings_search.dart';

/// Guards the catalog now that it has exactly **one** source.
///
/// Before A1 every key was written twice — once in the `_byKey` map, once in
/// `groups` — and nothing checked that the two agreed. The lookup map is now
/// derived from `groups`, which removes that whole class of drift; what
/// remains worth pinning is the part a person still hand-maintains: keys are
/// unique, every entry carries at least one keyword, and the built-in category
/// seeds resolve. That last one makes the standing comment in
/// `calendar_categories.dart` ("every icon key must exist in CalendarIcons")
/// enforceable rather than aspirational.
void main() {
  final allEntries = [
    for (final group in CalendarIcons.groups) ...group.entries,
  ];

  test('the catalog is not empty', () {
    // A scrape-style sanity check: every assertion below is vacuously true
    // over an empty list.
    expect(allEntries, isNotEmpty);
    expect(CalendarIcons.groups, isNotEmpty);
  });

  test('every key is unique across the whole catalog', () {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final entry in allEntries) {
      if (!seen.add(entry.key)) duplicates.add(entry.key);
    }
    expect(
      duplicates,
      isEmpty,
      reason:
          'a duplicated key silently loses one of its entries when the '
          'lookup map is built, and the two would render different icons',
    );
  });

  test('every catalog entry resolves through forKey', () {
    for (final entry in allEntries) {
      expect(
        CalendarIcons.forKey(entry.key),
        isNotNull,
        reason: '${entry.key} is in groups but does not resolve',
      );
      expect(CalendarIcons.forKey(entry.key), entry.icon);
    }
  });

  test('every built-in category seed icon key exists', () {
    for (final seed in CalendarCategories.builtInSeeds) {
      expect(
        CalendarIcons.forKey(seed.iconKey),
        isNotNull,
        reason:
            'built-in "${seed.id}" seeds icon key "${seed.iconKey}", which is '
            'not in the catalog — the category would render the fallback',
      );
    }
  });

  test('every entry carries at least one keyword', () {
    for (final entry in allEntries) {
      expect(
        entry.keywords.where((k) => k.trim().isNotEmpty),
        isNotEmpty,
        reason: '${entry.key} is unreachable by search with no keywords',
      );
    }
  });

  test('an unknown or null key resolves to null rather than throwing', () {
    expect(CalendarIcons.forKey(null), isNull);
    expect(CalendarIcons.forKey('no_such_icon'), isNull);
    expect(CalendarIcons.entryFor('no_such_icon'), isNull);
    expect(CalendarIcons.groupIdOf('no_such_icon'), isNull);
    expect(CalendarIcons.searchTextOf('no_such_icon'), isEmpty);
  });

  test('every key maps back to the group that declares it', () {
    for (final group in CalendarIcons.groups) {
      for (final entry in group.entries) {
        expect(CalendarIcons.groupIdOf(entry.key), group.id);
      }
    }
  });

  test('every group has a localized label', () {
    final l10n = AppLocalizationsEn();
    for (final id in IconGroupId.values) {
      expect(CalendarIcons.groupLabel(id, l10n).trim(), isNotEmpty);
    }
  });

  test('every IconGroupId is actually declared in the catalog', () {
    final declared = {for (final group in CalendarIcons.groups) group.id};
    expect(
      IconGroupId.values.toSet().difference(declared),
      isEmpty,
      reason:
          'an enum value with no entries is a heading the picker can never '
          'render and a label nobody reaches',
    );
  });

  /// The hard rule the whole catalog rests on: **icon keys are persisted** in
  /// `calendar_categories.icon_key`, `calendar_events.icon_key`,
  /// `calendar_event_templates` and the fasting appearance settings. Removing
  /// or renaming one silently blanks the icon of every row still holding it,
  /// and nothing else in the codebase would notice.
  ///
  /// This is the shipped set as of the 63-icon catalog, frozen. Retiring an
  /// icon means dropping it from `groups` while keeping the key resolvable —
  /// so this list checks `forKey`, not group membership. **Only ever append.**
  group('shipped keys stay resolvable', () {
    const shipped = <String>[
      'fitness_center',
      'sports_gymnastics',
      'sports_martial_arts',
      'sports_handball',
      'self_improvement',
      'accessibility_new',
      'directions_run',
      'directions_bike',
      'directions_walk',
      'pool',
      'hiking',
      'rowing',
      'downhill_skiing',
      'snowboarding',
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
      'bedtime',
      'hotel',
      'spa',
      'bathtub',
      'weekend',
      'monitor_heart',
      'favorite',
      'water_drop',
      'restaurant',
      'local_dining',
      'fastfood',
      'local_cafe',
      'no_food',
      'straighten',
      'monitor_weight',
      'science',
      'emoji_events',
      'military_tech',
      'workspace_premium',
      'flag',
      'star',
      'celebration',
      'cake',
      'flight_takeoff',
      'beach_access',
      'terrain',
      'schedule',
      'alarm',
      'today',
      'event',
      'event_note',
      'event_available',
      'event_busy',
      'note',
      'lightbulb',
      'bolt',
      'local_fire_department',
      'psychology',
      'mood',
      'attach_money',
    ];

    test('every key that has ever shipped still resolves', () {
      for (final key in shipped) {
        expect(
          CalendarIcons.forKey(key),
          isNotNull,
          reason:
              '"$key" has shipped and may be stored in four tables — it must '
              'stay resolvable even if it is retired from the picker',
        );
      }
    });
  });

  /// Letters and digits are ordinary catalog entries whose `IconData` names
  /// **no font family**, so `Icon` paints the character in the ambient font.
  /// That is the whole mechanism: no `CategoryGlyph`, no parallel display
  /// path, and every surface that already renders an `IconData` keeps working.
  group('letters and digits', () {
    test('a letter resolves to its own character in no icon font', () {
      final a = CalendarIcons.forKey('letter_a');
      expect(a, isNotNull);
      expect(a!.codePoint, 0x41);
      expect(
        a.fontFamily,
        isNull,
        reason:
            'a font family would send the glyph to an icon font that has no '
            'such code point, and would make it a tree-shake candidate',
      );
      expect(String.fromCharCode(a.codePoint), 'A');
    });

    test('the alphabet and the digits are complete and in order', () {
      for (var i = 0; i < 26; i++) {
        final key = 'letter_${String.fromCharCode(0x61 + i)}';
        expect(CalendarIcons.forKey(key)?.codePoint, 0x41 + i, reason: key);
      }
      for (var i = 0; i < 10; i++) {
        expect(CalendarIcons.forKey('digit_$i')?.codePoint, 0x30 + i);
      }
    });
  });

  group('exact terms outrank fuzzy tiers', () {
    test('a one-character query names its letter exactly', () {
      expect(CalendarIcons.isExactTerm('letter_a', 'a'), isTrue);
      // `ac_unit` is the entry a bare "a" would otherwise rank first: its
      // search text *starts* with "a", which is FuzzyRank's best tier.
      expect(CalendarIcons.isExactTerm('ac_unit', 'a'), isFalse);
    });

    test('a keyword counts whole, never as a fragment', () {
      expect(CalendarIcons.isExactTerm('fitness_center', 'gym'), isTrue);
      expect(CalendarIcons.isExactTerm('fitness_center', 'gy'), isFalse);
      expect(
        CalendarIcons.isExactTerm('fitness_center', 'fitness center'),
        isTrue,
      );
    });

    test('an unknown key and an empty term are false, not a throw', () {
      expect(CalendarIcons.isExactTerm('no_such_icon', 'a'), isFalse);
      expect(CalendarIcons.isExactTerm(null, 'a'), isFalse);
      expect(CalendarIcons.isExactTerm('letter_a', ''), isFalse);
    });
  });

  group('search index', () {
    List<String> keysFor(String raw) {
      final query = SettingsQuery.parse(raw);
      return [
        for (final entry in allEntries)
          if (matchesSettingsQuery(query, [
            CalendarIcons.searchTextOf(entry.key),
          ], preFolded: true))
            entry.key,
      ];
    }

    test('the index is prebuilt and already folded', () {
      // The whole point of precomputing: `matchesSettingsQuery(preFolded:
      // true)` asserts its inputs are normalized, so this passing in debug is
      // the claim being checked.
      for (final entry in allEntries) {
        final text = CalendarIcons.searchTextOf(entry.key);
        expect(text, isNotEmpty);
        expect(text, text.toLowerCase());
      }
    });

    test('the key itself is searchable with underscores read as spaces', () {
      expect(keysFor('fitness center'), contains('fitness_center'));
      expect(keysFor('fitness'), contains('fitness_center'));
      // The index stores the *spaced* form only. A query is split on
      // whitespace, so `fitness_center` is one token that no indexed string
      // contains — typing a raw key with underscores is not a case this
      // targets, and pinning it here keeps that a decision rather than a bug
      // someone rediscovers.
      expect(keysFor('fitness_center'), isEmpty);
    });

    test('a keyword reaches an icon its key does not spell', () {
      expect(keysFor('gym'), contains('fitness_center'));
      expect(keysFor('trophy'), contains('emoji_events'));
      expect(keysFor('yoga'), contains('self_improvement'));
      expect(keysFor('birthday'), contains('cake'));
      expect(keysFor('coffee'), contains('local_cafe'));
    });

    test('run narrows to the running icons and not to the whole catalog', () {
      final keys = keysFor('run');
      expect(keys, contains('directions_run'));
      expect(keys, isNot(contains('cake')));
      expect(keys.length, lessThan(allEntries.length));
    });

    test('extra tokens narrow rather than widen', () {
      expect(keysFor('sports ball'), contains('sports_basketball'));
      expect(keysFor('sports coffee'), isEmpty);
    });

    test('an empty query matches everything', () {
      expect(keysFor('   '), hasLength(allEntries.length));
    });
  });
}
