import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/utils/category_search.dart';
import 'package:anta/utils/fuzzy_rank.dart';
import 'package:anta/utils/settings_search.dart';

/// The one ranking function shared by the management page and the picker
/// sheet, so the two cannot drift.
///
/// The three claims worth pinning are the ones a reimplementation gets wrong:
/// a name hit outranks an icon-only hit, diacritics fold, and same-band rows
/// keep a deterministic order — `List.sort` is not stable in Dart, and here
/// nearly every row shares a band.
void main() {
  final l10n = AppLocalizationsEn();

  CalendarCategory category(
    String id, {
    required String name,
    String iconKey = 'event',
    int sortOrder = 0,
    bool isBuiltIn = false,
    bool isHidden = false,
  }) {
    return CalendarCategory(
      id: id,
      name: name,
      colorValue: 0xFF112233,
      iconKey: iconKey,
      sortOrder: sortOrder,
      isBuiltIn: isBuiltIn,
      isHidden: isHidden,
    );
  }

  List<String> idsFor(String raw, List<CalendarCategory> categories) {
    return [
      for (final row in rankCategories(
        SettingsQuery.parse(raw),
        categories,
        l10n,
      ))
        row.category.id,
    ];
  }

  tearDown(() => CalendarCategories.updateCache(const []));

  test('an empty query keeps every category in display order', () {
    final categories = [
      category('c', name: 'Cardio', sortOrder: 2),
      category('a', name: 'Gym', sortOrder: 0),
      category('b', name: 'Rest', sortOrder: 1),
    ];
    expect(idsFor('   ', categories), ['a', 'b', 'c']);
    expect(
      rankCategories(SettingsQuery.empty, categories, l10n).map((r) => r.band),
      everyElement(FuzzyRank.tierPrefix),
    );
  });

  test('a name hit outranks an icon-only hit for the same query', () {
    final categories = [
      // The icon-only hit is deliberately first in sort order, so a passing
      // result can only come from the band, never from the tiebreak.
      category(
        'viaIcon',
        name: 'Errands',
        iconKey: 'fitness_center',
        sortOrder: 0,
      ),
      category('viaName', name: 'Gym night', sortOrder: 9),
    ];

    final ranked = rankCategories(SettingsQuery.parse('gym'), categories, l10n);

    expect(ranked.map((r) => r.category.id), ['viaName', 'viaIcon']);
    expect(ranked.first.band, lessThan(kIconOnlyBand));
    expect(ranked.last.band, kIconOnlyBand);
  });

  test('an icon keyword reaches a category whose name does not match', () {
    final categories = [
      category('dentist', name: 'Dentist', iconKey: 'medical_services'),
      category('gym', name: 'Gym', iconKey: 'fitness_center'),
    ];
    // `dumbbell` is a keyword of `fitness_center` and appears in no name.
    expect(idsFor('dumbbell', categories), ['gym']);
  });

  test('the localized icon group label is searchable', () {
    final categories = [
      category('trip', name: 'Trip', iconKey: 'flight_takeoff'),
      category('gym', name: 'Gym', iconKey: 'fitness_center'),
    ];
    // "Travel" is the group label for `flight_takeoff`, not a keyword and not
    // in the name — this is the seam that gives a non-English user a way in.
    expect(idsFor('travel', categories), ['trip']);
  });

  test('diacritics fold in both directions', () {
    final categories = [
      category('health', name: 'Sănătate'),
      category('gym', name: 'Gym'),
    ];
    expect(idsFor('sanatate', categories), ['health']);
    expect(idsFor('Sănăt', categories), ['health']);
  });

  test('extra tokens narrow rather than widen', () {
    final categories = [
      category('a', name: 'Morning gym', sortOrder: 0),
      category('b', name: 'Morning run', sortOrder: 1),
    ];
    expect(idsFor('morning', categories), ['a', 'b']);
    expect(idsFor('morning run', categories), ['b']);
    expect(idsFor('morning swim', categories), isEmpty);
  });

  test('a prefix outranks a mid-word substring', () {
    final categories = [
      category('mid', name: 'Home gym', sortOrder: 0),
      category('prefix', name: 'Gymnastics', sortOrder: 9),
    ];
    // Same band would leave the sortOrder tiebreak in charge, which would put
    // `mid` first — so this only passes on the band.
    expect(idsFor('gym', categories), ['prefix', 'mid']);
  });

  test('same-band rows sort on (sortOrder, id), never on input order', () {
    final categories = [
      category('z', name: 'Gym z', sortOrder: 5),
      category('a', name: 'Gym a', sortOrder: 1),
      category('m', name: 'Gym m', sortOrder: 3),
    ];
    final first = idsFor('gym', categories);
    final again = idsFor('gym', categories.reversed.toList());

    expect(first, ['a', 'm', 'z']);
    expect(
      again,
      first,
      reason:
          'List.sort is not stable in Dart, so identical bands must be broken '
          'explicitly or the list reshuffles between rebuilds',
    );
  });

  test('a duplicated sortOrder still yields a deterministic order', () {
    final categories = [
      category('b', name: 'Gym b', sortOrder: 1),
      category('a', name: 'Gym a', sortOrder: 1),
    ];
    expect(idsFor('gym', categories), ['a', 'b']);
  });

  test('a built-in ranks on its localized label, not its stored name', () {
    CalendarCategories.updateCache(const []);
    final categories = [
      category('gym', name: 'Gym', isBuiltIn: true, iconKey: 'fitness_center'),
    ];
    // `labelOf` resolves a built-in through AppLocalizations; in English the
    // label and the stored fallback name coincide, so the check that matters
    // is that the label path is exercised at all rather than throwing.
    expect(idsFor('gym', categories), ['gym']);
  });

  test('ranking never filters — it only orders', () {
    // A query no fuzzy tier can score against the name, but whose tokens are
    // each a substring of it. Membership must still admit it, at the weakest
    // name band rather than the icon band.
    final categories = [category('a', name: 'Lent Great')];
    final ranked = rankCategories(
      SettingsQuery.parse('great lent'),
      categories,
      l10n,
    );

    expect(ranked.map((r) => r.category.id), ['a']);
    expect(ranked.single.band, lessThan(kIconOnlyBand));
  });

  test('an unknown icon key does not throw and matches on name alone', () {
    final categories = [category('a', name: 'Gym', iconKey: 'no_such_icon')];
    expect(idsFor('gym', categories), ['a']);
    expect(idsFor('dumbbell', categories), isEmpty);
  });

  test('the caller decides the input set, hidden included or not', () {
    final categories = [
      category('open', name: 'Gym open', sortOrder: 0),
      category('archived', name: 'Gym archived', sortOrder: 1, isHidden: true),
    ];
    // rankCategories ranks what it is handed; visibility is `visible` /
    // `visiblePlus`'s job, one layer up.
    expect(idsFor('gym', categories), ['open', 'archived']);
    expect(idsFor('gym', [categories.first]), ['open']);
  });
}
