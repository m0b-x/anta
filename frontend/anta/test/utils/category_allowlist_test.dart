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

      /// With their group alone held this picker opens with no row ticked:
      /// a Done on it untouched is no pick, and keeps what the list meant.
      test('their group: an untouched Done keeps it; a part of mine joins '
          'it', () {
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

      /// Second review: "Select none" is every category, whatever was
      /// carried — a report digest or one under "Only alerts I add".
      test('select none over a part of mine beside their group is every '
          'category', () {
        expect(unlisted({'c0', theirs}, const {}), isEmpty);
        expect(CategoryAllowlist.filtersNothing(const {}), isTrue);
      });

      test('a no-op Done keeps the list; a part of mine still carries '
          'their group', () {
        expect(unlisted({'c0', theirs}, {'c0'}), {'c0', theirs});
        expect(unlisted({'c0', theirs}, {'c0', 'c1'}), {'c0', 'c1', theirs});
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

    /// Second review: a carried hidden id never turns "Select none" into a
    /// filter, and still rides with any pick that ticks a listed row.
    test('select none over a hidden id of theirs is every category; a '
        'partial pick keeps it', () {
      CalendarCategories.updatePartnerHidden({'p1'});
      expect(
        CategoryAllowlist.fromPicker({'c0', 'p1'}, {'p1'}),
        isEmpty,
        reason: 'the picker hands the hidden id back with no row ticked',
      );
      expect(CategoryAllowlist.fromPicker({'c0', 'p1'}, const {}), isEmpty);
      expect(CategoryAllowlist.fromPicker({'c0', 'p1'}, {'c0', 'c1', 'p1'}), {
        'c0',
        'c1',
        'p1',
      });
      expect(
        CategoryAllowlist.fromPicker(
          {'c0', 'p1'},
          {'other', 'gym', 'c0', 'c1', 'p0', 'p1'},
        ),
        isEmpty,
        reason: 'both listed groups whole is every category',
      );
    });

    /// "Nothing ticked is every category" is about a pick the person made.
    /// A Done on a picker nobody touched, with no new row to choose about,
    /// is no store at all: the list stays the list it was, byte for byte.
    test('an untouched Done keeps the list it was', () {
      CalendarCategories.updatePartnerHidden({'p1'});
      expect(
        CategoryAllowlist.fromPicker({'p1'}, {'p1'}),
        {'p1'},
        reason: 'a hidden one of theirs alone: no row ticked, none touched',
      );
      expect(
        CategoryAllowlist.fromPicker(
          {'other', 'gym', 'c0', 'c1'},
          {'other', 'gym', 'c0', 'c1'},
        ),
        {'other', 'gym', 'c0', 'c1'},
        reason:
            'every id of mine, listed by hand, stays that list until a '
            'pick changes it',
      );
      expect(
        CategoryAllowlist.fromPicker({'deleted'}, {'deleted'}),
        {'deleted'},
        reason: 'an id no category holds is dropped by a pick, not by a look',
      );
      expect(
        CategoryAllowlist.fromPicker(
          {mine, 'p1'},
          {'other', 'gym', 'c0', 'c1', 'p1'},
        ),
        {mine, 'p1'},
      );
    });

    test('a whole listed group with a carried entry keeps its meaning', () {
      final both = CategoryAllowlist.fromPicker(
        {mine, theirs},
        {'other', 'gym', 'c0', 'c1'},
        partnerListed: false,
      );
      expect(both, {
        mine,
        theirs,
      }, reason: 'nobody touched it: the list comes back as it is');
      expect(CategoryAllowlist.filtersNothing(both), isTrue);
      expect(
        CategoryAllowlist.fromPicker(
          {'c0', theirs},
          {'other', 'gym', 'c0', 'c1'},
          partnerListed: false,
        ),
        isEmpty,
      );
    });

    test('a group that lists nothing never writes its entry', () {
      CalendarCategories.updateCache([
        category('p0', fromPartner: true),
        category('p1', fromPartner: true),
      ]);
      expect(stored({'p0'}), {'p0'});
    });

    /// The review of the fix pass. A picker hands back an id it has no row
    /// for, so "Select none" leaves it in the answer.
    group('after the review of the fix pass', () {
      /// What the picker opened with, as each sheet now hands it over.
      Set<String> pickedFrom(
        Set<String> previous,
        Set<String> Function(Set<String> opened) pick,
      ) {
        final opening = CategoryAllowlist.opening(previous);
        return CategoryAllowlist.fromPicker(
          previous,
          pick(opening.ticked),
          opening: opening,
        );
      }

      /// Every row the picker lists, ticked: its "Select all".
      Set<String> all(Set<String> previous) => {
        for (final c in CategoryAllowlist.listed(previous)) c.id,
      };

      test('after the pair ends, a pick changed to nothing is every '
          'category — never their old id alone, a list that shows nothing', () {
        seed(partner: false);
        expect(
          pickedFrom({'c0', 'p0'}, (opened) => {...opened}..remove('c0')),
          isEmpty,
        );
      });

      test('never paired: the same over a deleted category\'s id, and an '
          'untouched Done stores what it always did', () {
        seed(partner: false);
        const previous = {'c0', 'deleted'};
        expect(
          pickedFrom(previous, (opened) => {...opened}..remove('c0')),
          isEmpty,
        );
        expect(pickedFrom(previous, (opened) => opened), previous);
        expect(
          pickedFrom(previous, (opened) => {...opened, 'c1'}),
          {'c0', 'c1', 'deleted'},
          reason: 'a pick that ticks something is stored as it came',
        );
      });

      test('a category of theirs left out and then hidden stays out while '
          'no row of theirs is changed', () {
        CalendarCategories.updatePartnerHidden({'p0'});
        const partOfTheirs = {'c0', 'p1'};
        expect(pickedFrom(partOfTheirs, (opened) => opened), partOfTheirs);
        expect(pickedFrom(partOfTheirs, (opened) => {...opened, 'c1'}), {
          'c0',
          'c1',
          'p1',
        });
        expect(
          pickedFrom({'c0', theirs}, (opened) => {...opened, 'c1'}),
          {'c0', 'c1', theirs},
          reason: 'their group held whole: the hidden one rides in the entry',
        );
        expect(
          pickedFrom({'c0', 'p0', 'p1'}, (opened) => opened),
          {'c0', 'p0', 'p1'},
          reason: 'no row of theirs changed: their part is what it was',
        );
        expect(
          pickedFrom({'c0', 'p0'}, (opened) => {...opened, 'p1'}),
          {'c0', theirs},
          reason:
              'a row of theirs ticked, and the list held the hidden one: '
              'their group is whole',
        );
        expect(
          pickedFrom({'c0'}, (opened) => {...opened, 'p1'}),
          {'c0', theirs},
          reason: 'every row of theirs on offer ticked by hand is their group',
        );
        expect(
          pickedFrom(const {}, (opened) => {...opened}..remove('c1')),
          {'other', 'gym', 'c0', theirs},
          reason: 'an empty list held all of theirs',
        );
      });

      /// The second look at the fix: with one of theirs hidden, "Select
      /// all" stored my group beside the one row of theirs on offer — every
      /// row ticked and a filter still on, one a category they share later
      /// stays out of.
      test('a pick changed to every row on offer is every category, with '
          'one of theirs hidden too', () {
        CalendarCategories.updatePartnerHidden({'p0'});
        for (final previous in [
          {mine},
          {'c0'},
          {'c0', 'p1'},
          {'other', 'gym', 'c0', 'p1'},
        ]) {
          expect(
            pickedFrom(previous, (_) => all(previous)),
            isEmpty,
            reason: '$previous',
          );
        }
        expect(
          pickedFrom({mine, 'p1'}, (opened) => opened),
          {mine, 'p1'},
          reason:
              'every row was ticked already and none was changed: the '
              'list, with the hidden one left out, stays',
        );
      });

      /// The third look: with none of theirs on offer — every one hidden,
      /// or a surface that lists none — "Select all" stored my group alone,
      /// which reads as off until one of theirs is shown or shared, and then
      /// leaves it out.
      test('a pick changed to every row on offer is every category when '
          'none of theirs is on offer', () {
        CalendarCategories.updatePartnerHidden({'p0', 'p1'});
        for (final previous in [
          {'c0'},
          {'other', 'c0'},
        ]) {
          expect(
            pickedFrom(previous, (_) => all(previous)),
            isEmpty,
            reason: 'all of theirs hidden, $previous',
          );
        }
        CalendarCategories.updatePartnerHidden(const {});
        final opening = CategoryAllowlist.opening(const {
          'c0',
        }, partnerListed: false);
        expect(
          CategoryAllowlist.fromPicker(
            const {'c0'},
            {'other', 'gym', 'c0', 'c1'},
            opening: opening,
            partnerListed: false,
          ),
          isEmpty,
          reason: 'a surface that lists none of theirs',
        );
        expect(
          pickedFrom({mine}, (opened) => opened),
          {mine},
          reason: 'my group, chosen as mine alone, is not a pick: it stays',
        );
      });

      test('my group with an archived category left out is not turned into '
          'every category by a Done nobody touched', () {
        const previous = {'other', 'gym', 'c0', 'c1', theirs};
        expect(pickedFrom(previous, (opened) => opened), previous);
      });

      test('a category of theirs that arrives while the picker is open is '
          'not left out by a Done nobody touched', () {
        const previous = {'c0', theirs};
        final opening = CategoryAllowlist.opening(previous);
        final opened = opening.ticked;
        expect(opened, {'c0', 'p0', 'p1'});
        CalendarCategories.updateCache([
          ...CalendarCategories.all,
          category('p-new', fromPartner: true),
        ]);
        expect(
          CategoryAllowlist.fromPicker(previous, opened, opening: opening),
          previous,
        );
      });

      test('their group alone, opened with nothing of theirs to show, is '
          'still their group when one arrives before Done', () {
        seed(partner: false);
        const previous = {theirs};
        final opening = CategoryAllowlist.opening(previous);
        expect(opening.ticked, isEmpty);
        seed();
        expect(
          CategoryAllowlist.fromPicker(
            previous,
            opening.ticked,
            opening: opening,
          ),
          previous,
        );
      });

      test('a category of mine made inside the picker and left un-ticked '
          'stays out: a Done that changed no tick still stores', () {
        const previous = <String>{};
        final opening = CategoryAllowlist.opening(previous);
        CalendarCategories.updateCache([
          ...CalendarCategories.all,
          category('c-new'),
        ]);
        expect(
          CategoryAllowlist.fromPicker(
            previous,
            opening.ticked,
            opening: opening,
          ),
          {'other', 'gym', 'c0', 'c1', theirs},
        );
      });
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

    /// Second review: while no category is known nothing is claimed — an
    /// entry reads as in force, as [CategoryAllowlist.admits] treats it, and
    /// no count is made up for it.
    test('with no catalogue a list that holds anything is in force', () {
      CalendarCategories.updateCache(const []);
      expect(CategoryAllowlist.filtersNothing(const {}), isTrue);
      expect(CategoryAllowlist.filtersNothing({mine}), isFalse);
      expect(CategoryAllowlist.filtersNothing({mine, theirs}), isFalse);
      expect(
        CategoryAllowlist.admits(event('p0', fromPartner: true), {mine}),
        isFalse,
      );
      expect(CategoryAllowlist.tickedCount({mine}), isNull);
      expect(CategoryAllowlist.tickedCount({'c0', 'deleted'}), 2);
      expect(CategoryAllowlist.tickedCount(const {}), 0);
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
