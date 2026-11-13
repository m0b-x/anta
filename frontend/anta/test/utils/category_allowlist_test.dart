import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/utils/category_allowlist.dart';

/// The truth table of D29 (§16.3 of `docs/cloud-share-surfaces-roadmap.md`):
/// what a picker's answer is stored as, what a stored list ticks, which side
/// an event is on and what a list admits.
void main() {
  const mine = CategoryAllowlist.mineEntry;
  const theirs = CategoryAllowlist.partnerEntry;

  CalendarCategory category(
    String id, {
    bool fromPartner = false,
    bool isHidden = false,
    bool isBuiltIn = false,
  }) => CalendarCategory(
    id: id,
    name: id,
    colorValue: 0xFF1E88E5,
    iconKey: 'event',
    sortOrder: 0,
    isBuiltIn: isBuiltIn,
    isHidden: isHidden,
    fromPartner: fromPartner,
  );

  CalendarEvent event(String categoryId, {bool fromPartner = false}) =>
      CalendarEvent(
        id: '${fromPartner ? 'p' : 'm'}-$categoryId',
        title: 'E',
        categoryId: categoryId,
        startDate: DateTime.utc(2027, 3, 4),
        fromPartner: fromPartner,
      );

  /// Mine: Other and Gym (built-ins), c0, c1, and the archived c-old.
  /// Theirs: p0, p1.
  void seed({bool partner = true}) {
    CalendarCategories.updateCache([
      category('other', isBuiltIn: true),
      category('gym', isBuiltIn: true),
      category('c0'),
      category('c1'),
      category('c-old', isHidden: true),
      if (partner) ...[
        category('p0', fromPartner: true),
        category('p1', fromPartner: true),
      ],
    ]);
  }

  /// A pick over a list that filtered nothing, the partner's group listed.
  Set<String> stored(Set<String> picked) =>
      CategoryAllowlist.fromPicker(const {}, picked);

  setUp(seed);

  tearDown(() {
    CalendarCategories.updatePartnerHidden(const {});
    CalendarCategories.updateCache(const []);
  });

  group('the entries', () {
    test('cannot be a category id and hold no CSV separator', () {
      for (final entry in [mine, theirs]) {
        expect(entry.startsWith('*'), isTrue);
        expect(entry.contains(','), isFalse);
        expect(entry.trim(), entry);
        expect(
          CalendarCategories.builtInSeeds.any((s) => s.id == entry),
          isFalse,
        );
      }
    });
  });

  group('stored from the picker', () {
    test('both groups whole is empty', () {
      expect(stored({'other', 'gym', 'c0', 'c1', 'p0', 'p1'}), isEmpty);
    });

    test('my group whole beside some or none of theirs is my entry', () {
      expect(stored({'other', 'gym', 'c0', 'c1', 'p1'}), {mine, 'p1'});
      expect(stored({'other', 'gym', 'c0', 'c1'}), {mine});
    });

    test('some of mine beside their group whole is their entry', () {
      expect(stored({'c0', 'p0', 'p1'}), {'c0', theirs});
    });

    test('parts of both stay ids', () {
      expect(stored({'c0', 'p1'}), {'c0', 'p1'});
    });

    test('nothing ticked is empty, as today', () {
      expect(stored(const {}), isEmpty);
    });

    test('a stale id is dropped once a partner\'s category is known', () {
      expect(stored({'c0', 'deleted', 'p-gone'}), {'c0'});
      expect(stored({'other', 'gym', 'c0', 'c1', 'deleted'}), {mine});
    });

    test('with nothing of a partner\'s listed or known it is today\'s rule '
        'byte for byte: no entry is ever written', () {
      seed(partner: false);
      expect(stored({'other', 'gym', 'c0', 'c1'}), isEmpty);
      expect(stored({'other', 'gym', 'c0', 'c1', 'deleted'}), isEmpty);
      final part = {'c0', 'deleted'};
      expect(identical(stored(part), part), isTrue);
    });

    test('a category made inside the picker is read at the store', () {
      CalendarCategories.updateCache([
        ...CalendarCategories.all,
        category('c-new'),
      ]);
      expect(stored({'other', 'gym', 'c0', 'c1', 'p0', 'p1'}), {
        'other',
        'gym',
        'c0',
        'c1',
        theirs,
      });
      expect(stored({'other', 'gym', 'c0', 'c-new', 'p0', 'p1'}), {
        'other',
        'gym',
        'c0',
        'c-new',
        theirs,
      });
    });

    /// The rule of the fix pass: a picker changes only the part it showed.
    group('the partner\'s group not listed is carried as it stood', () {
      Set<String> unlisted(Set<String> previous, Set<String> picked) =>
          CategoryAllowlist.fromPicker(previous, picked, partnerListed: false);

      test('their group: a no-op keeps it; a part of mine joins it', () {
        expect(unlisted({theirs}, const {}), {theirs});
        expect(unlisted({theirs}, {'c0', 'c1'}), {'c0', 'c1', theirs});
        expect(unlisted({theirs}, {'other', 'gym', 'c0', 'c1'}), isEmpty);
      });

      test('an id of theirs is carried, a deleted one dropped', () {
        expect(unlisted({'p0', 'c0', 'p-gone'}, {'c0'}), {'c0', 'p0'});
      });

      test('an empty list held all of theirs; nothing ticked is still all', () {
        expect(unlisted(const {}, {'c0'}), {'c0', theirs});
        expect(unlisted(const {}, {'other', 'gym', 'c0', 'c1'}), isEmpty);
        expect(unlisted(const {}, const {}), isEmpty);
      });

      test('my group with none of theirs stays mine', () {
        expect(unlisted({mine}, {'other', 'gym', 'c0', 'c1'}), {mine});
      });
    });

    test('a category of theirs hidden here keeps its place', () {
      CalendarCategories.updatePartnerHidden({'p1'});
      expect(
        CategoryAllowlist.fromPicker(
          {mine, 'p1'},
          {'other', 'gym', 'c0', 'c1', 'p1'},
        ),
        {mine, 'p1'},
      );
    });

    test('a group that lists nothing never writes its entry', () {
      CalendarCategories.updateCache([
        category('p0', fromPartner: true),
        category('p1', fromPartner: true),
      ]);
      expect(stored({'p0'}), {'p0'});
    });
  });

  group('the report keeps only its own part', () {
    test('mine alone is off, their part is dropped, my ids stay', () {
      expect(CategoryAllowlist.forReport({mine}), isEmpty);
      expect(CategoryAllowlist.forReport({mine, 'p0'}), isEmpty);
      expect(CategoryAllowlist.forReport({theirs}), isEmpty);
      expect(CategoryAllowlist.forReport({'c0', theirs, 'p1'}), {'c0'});
      final plain = {'c0', 'deleted'};
      expect(identical(CategoryAllowlist.forReport(plain), plain), isTrue);
    });
  });

  group('ticked in the picker', () {
    Set<String> ticked(Set<String> ids) => CategoryAllowlist.ticked(ids);

    test('empty ticks every listed row', () {
      expect(ticked(const {}), {'other', 'gym', 'c0', 'c1', 'p0', 'p1'});
    });

    test('an entry ticks its whole group; an id ticks itself', () {
      expect(ticked({mine, 'p1'}), {'other', 'gym', 'c0', 'c1', 'p1'});
      expect(ticked({'c0', theirs}), {'c0', 'p0', 'p1'});
    });

    test('a plain list is handed over as it is, a stale id included', () {
      final ids = {'c0', 'deleted'};
      expect(identical(ticked(ids), ids), isTrue);
    });

    test('my entry with no partner\'s category listed ticks everything', () {
      seed(partner: false);
      expect(ticked({mine}), {'other', 'gym', 'c0', 'c1'});
    });
  });

  group('counted and on', () {
    test('filters nothing: empty, or my entry with none of theirs listed', () {
      expect(CategoryAllowlist.filtersNothing(const {}), isTrue);
      expect(CategoryAllowlist.filtersNothing({mine}), isFalse);
      expect(CategoryAllowlist.filtersNothing({theirs}), isFalse);
      expect(CategoryAllowlist.filtersNothing({'c0'}), isFalse);
      expect(
        CategoryAllowlist.filtersNothing({mine}, partnerListed: false),
        isTrue,
      );
      expect(CategoryAllowlist.filtersNothing({mine, theirs}), isTrue);

      CalendarCategories.updatePartnerHidden({'p0', 'p1'});
      expect(CategoryAllowlist.filtersNothing({mine}), isTrue);
      expect(CategoryAllowlist.filtersNothing({mine, 'p0'}), isTrue);
      expect(CategoryAllowlist.filtersNothing({theirs}), isFalse);
    });

    int count(Set<String> ids, {bool partnerListed = true}) =>
        CategoryAllowlist.tickedListed(
          ids,
          partnerListed: partnerListed,
        ).length;

    test('counts the listed categories ticked, never a stale id', () {
      expect(count({mine}), 4);
      expect(count({theirs, 'c0'}), 3);
      expect(count({'c0', 'deleted'}), 1);
      expect(count({theirs}, partnerListed: false), 0);
      expect(count({'p0'}, partnerListed: false), 0);
    });

    test('the sole ticked category is what a label, a row and a payload '
        'wear', () {
      expect(CategoryAllowlist.soleTicked({'c0'})?.id, 'c0');
      expect(CategoryAllowlist.soleTicked({mine}), isNull);
      expect(CategoryAllowlist.soleTicked({'c0', 'c1'}), isNull);
      expect(CategoryAllowlist.soleTicked(const {}), isNull);
      expect(CategoryAllowlist.soleTicked({'deleted'}), isNull);

      CalendarCategories.updatePartnerHidden({'p1'});
      expect(CategoryAllowlist.soleTicked({theirs})?.id, 'p0');
      expect(
        CategoryAllowlist.soleTicked({'p0'}, partnerListed: false),
        isNull,
        reason: 'a partner id that gathers nothing names nothing',
      );
    });
  });

  group('sides and admits', () {
    test('empty admits everything', () {
      expect(
        CategoryAllowlist.admits(event('p0', fromPartner: true), {}),
        true,
      );
      expect(CategoryAllowlist.admits(event('c0'), {}), isTrue);
    });

    test('my entry admits an own event in an archived category and on an id '
        'no category holds', () {
      expect(CategoryAllowlist.admits(event('c-old'), {mine}), isTrue);
      expect(CategoryAllowlist.admits(event('deleted'), {mine}), isTrue);
      expect(CategoryAllowlist.admits(event('c0'), {theirs}), isFalse);
    });

    test('an own event on an id no category holds meets a plain list by its '
        'stored id (the report\'s D32)', () {
      expect(CategoryAllowlist.admits(event('deleted'), {'deleted'}), isTrue);
      expect(CategoryAllowlist.admits(event('deleted'), {'other'}), isFalse);
    });

    test('a partner\'s event in their own category is on their side', () {
      final e = event('p0', fromPartner: true);
      expect(CategoryAllowlist.isPartnerSide(e), isTrue);
      expect(CategoryAllowlist.admits(e, {theirs}), isTrue);
      expect(CategoryAllowlist.admits(e, {'p0'}), isTrue);
      expect(CategoryAllowlist.admits(e, {mine}), isFalse);
      expect(CategoryAllowlist.admits(e, {mine, 'p1'}), isFalse);
    });

    test('a partner\'s event joining my built-in is on my side', () {
      final e = event('gym', fromPartner: true);
      expect(CategoryAllowlist.isPartnerSide(e), isFalse);
      expect(CategoryAllowlist.admits(e, {mine}), isTrue);
      expect(CategoryAllowlist.admits(e, {'gym'}), isTrue);
      expect(CategoryAllowlist.admits(e, {theirs}), isFalse);
    });

    test('a partner\'s event drawn as Other is on my side, met by Other', () {
      final e = event('p-unshared', fromPartner: true);
      expect(CategoryAllowlist.isPartnerSide(e), isFalse);
      expect(CategoryAllowlist.admits(e, {mine}), isTrue);
      expect(CategoryAllowlist.admits(e, {'other'}), isTrue);
      expect(CategoryAllowlist.admits(e, {'p-unshared'}), isFalse);
      expect(CategoryAllowlist.admits(e, {theirs}), isFalse);
    });

    test('my own events are never on their side', () {
      expect(CategoryAllowlist.isPartnerSide(event('p0')), isFalse);
    });

    test('with no catalogue published a partner\'s event is on their side; '
        'unknown is never mine', () {
      CalendarCategories.updateCache(const []);
      final e = event('gym', fromPartner: true);
      expect(CategoryAllowlist.isPartnerSide(e), isTrue);
      expect(CategoryAllowlist.admits(e, {mine}), isFalse);
      expect(CategoryAllowlist.admits(e, {theirs}), isTrue);
      expect(CategoryAllowlist.admits(event('gym'), {mine}), isTrue);
    });

    test('both entries admit everything', () {
      expect(
        CategoryAllowlist.admits(event('p0', fromPartner: true), {
          mine,
          theirs,
        }),
        isTrue,
      );
      expect(CategoryAllowlist.admits(event('c-old'), {mine, theirs}), true);
    });
  });
}
