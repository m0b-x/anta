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
